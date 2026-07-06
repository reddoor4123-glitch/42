# Phase 2 Raw Concept Audit

**Purpose of this document:** collect every place in the project where a Phase-2-adjacent
concept (trust, risk, cooperation, caution, aggression, confidence, commitment, opportunity,
personality) appears — in code, comments, TODOs, bug logs, or design docs — without unifying,
renaming, or evaluating whether the current vocabulary is correct. That step comes after this
document, not inside it.

Each entry answers: Where / What it looks at / What info it uses / What decision it makes /
What behavior changes / Layer (evaluation, commitment, execution, other) / Status (active code,
placeholder, comment, bug log, design doc). Duplicate/related occurrences are grouped.

---

## 1. `risk_bias` — bidding, active, evaluation

**Where:** `ai_player.gd`, `decide_bid()`, Layer 2 (Signal Combiner). Also `AI_MODES` const
(top of file) and `_log_bid_decision()`.

**What it looks at:** Nothing about game state directly — it's a static coefficient pulled from
`AI_MODES[difficulty]["risk_bias"]` (beginner `-0.25`, standard `0.0`, expert `0.25`).

**What info it uses:** The difficulty string only.

**What decision it makes:** Shifts two computed values — `ev_score = est_pts + risk_bias * 4.0`
and `target_bid = roundi(est_pts + risk_bias * 3.0 + stance_bias)`. Higher risk_bias → higher EV
score → more likely to clear the `should_bid >= 28.0` threshold, and a higher target bid.

**Behavior change:** Directly changes whether/how much the AI bids. This is the one Phase-2-named
parameter that is fully wired and doing real work today.

**Layer:** Evaluation (Layer 2 — combines with EV and control signals, no gating/suppression).

**Status:** Active code, confirmed working (per Jul 1 and Jul 2 session summaries: "risk_bias and
max_overbid exist and work").

---

## 2. `max_overbid` — bidding, active, execution

**Where:** Same locations as `risk_bias`. `AI_MODES` values: beginner `2`, standard `4`, expert `6`.

**What it looks at:** Static coefficient, difficulty-keyed.

**What decision it makes:** Caps `target_bid` at `roundi(est_pts) + max_overbid` in Layer 3
(Execution). Layer 3 explicitly does not re-score — this is a legality/ceiling enforcement, not
a judgment.

**Behavior change:** Limits how far above the hand's raw estimated value the AI will bid.

**Layer:** Execution (explicitly Layer 3 in the file's own three-layer comment structure —
distinct from `risk_bias`, which lives in Layer 2).

**Status:** Active code, confirmed working.

**Note:** `risk_bias` and `max_overbid` are both under the `AI_MODES` "personality" heading in
comments, but they sit in two different architectural layers (Evaluation vs. Execution). They
are currently treated as one conceptual unit ("risk personality") despite that split.

---

## 3. `cooperation_bias` — AI_MODES key, inert placeholder

**Where:** `AI_MODES` const (`ai_player.gd`), values `"high"` / `"medium"` / `"medium"` (string,
not numeric — unlike `risk_bias`). Read once in `decide_play()`:
```
var mode = AI_MODES.get(difficulty, AI_MODES["standard"])
@warning_ignore("unused_variable")
var cooperation_bias: String = mode["cooperation_bias"]  # Phase 3
```

**What it looks at:** Nothing — read and immediately discarded via `@warning_ignore`.

**What decision it makes:** None. No branch anywhere in the file consults this variable.

**Behavior change:** None currently.

**Layer:** N/A — dead read.

**Status:** Placeholder. Labeled `# Phase 3` in the inline comment, but referred to as "Phase 2"
in every session summary and the onboarding doc. **This is a direct labeling inconsistency**:
the code comment says Phase 3, the design docs consistently call it the Phase 2 placeholder.

**Cross-reference:** A rename target (`cooperation_bias` → `trust_threshold`) has been proposed
in three separate session docs but is explicitly blocked pending Katy's ruling on the "expert
partner no trust rule" question (see #6 below). No rename has happened yet.

---

## 4. `opportunism` — AI_MODES key, inert placeholder

**Where:** `AI_MODES` const, values `"low"` / `"medium"` / `"high"`. Read in `decide_play()`
identically to `cooperation_bias`:
```
@warning_ignore("unused_variable")
var opportunism: String = mode["opportunism"]  # Phase 3
```

**What it looks at / decides / changes:** Same as above — read, discarded, zero behavioral effect.

**Layer:** N/A — dead read.

**Status:** Placeholder, explicitly and consistently labeled Phase 3 everywhere (code comment
and docs agree here, unlike `cooperation_bias`).

**Related but distinct:** The opponent-behavior header comment in `decide_play()` says:
```
# Expert: compete harder (handled in bidding); TODO Phase 3 opportunism.
```
This TODO originally sat next to a lead-side branch. Per the Jul 4 PublicKnowledge session, that
specific TODO location was later filled in — but with a **Knowledge-classified** mechanism
(`FORCE_A_VOID`, gated on `PublicKnowledge.void_suits()`), not an `opportunism`-parameterized one.
The `opportunism` AI_MODES key itself remains completely unconsulted. So "opportunism" now has
two disconnected referents in the project: (a) the dead dict key, and (b) an implemented
knowledge-gated lead behavior that nobody currently calls "opportunism" in code.

---

## 5. `trust_gate` — branch #16, active, commitment gate

**Where:** `ai_player.gd`, `decide_play()`, partner-following-standard-difficulty branch
(Phase3_Objective_Audit.md branch #16). Actual code:
```
# Standard trust rule: if the human already played and we're not last,
# a later player might handle this — hold trump rather than overriding
# what the human set up.
var human_play = _find_player_play(plays, partner_id)
var is_last_player = (plays.size() == 3)
if human_play != null and not is_last_player:
    ...
    reason_log.append("Saving my trump — there's still a chance someone else covers.")
    return discard
```

**What it looks at:** `plays.size()` (turn position) and whether the partner (human) has already
acted this trick. Pure geometry — no probability, no `PublicKnowledge` query.

**What info it uses:** Turn order and trick state only. Not difficulty-scaled numerically —
this specific branch only runs at all under `difficulty == "standard"` (a bare string check, not
a threshold).

**What decision it makes:** Whether to commit trump to secure a trick the partner could still
possibly cover, or hold back and discard safely instead.

**Behavior change:** Standard-difficulty players hold trump in this situation; beginner and
expert do not (beginner always secures immediately; expert has "no trust rule" and also secures
immediately, for the opposite stated reason).

**Layer:** Commitment gate — this is one of the two branches in the whole file identified as
suppressing a valid, already-selected objective (`SECURE_FOR_PARTNER`) rather than executing or
replacing it. On failure it falls through to `ESCAPE`.

**Status:** ✓ Superseded (July 5, 2026, same session this raw audit was likely written in, but
after this entry). **The code shown above no longer exists.** BUG-005 rewrote this branch entirely
— it no longer looks at turn order/`plays.size()` at all. The new version evaluates a
deterministic worst-case counter bound (`_live_counter_for_suit()`, which *does* now query
`PublicKnowledge.is_void_in()`/`has_been_played()`), a symmetric contract-margin reachability
check, and lead economy. This entry's "pure geometry — no probability, no `PublicKnowledge` query"
characterization is no longer accurate for this branch; kept here as the historical record of what
the code looked like before the fix. See `Phase3_Objective_Audit.md` branch #16 and
`ai_player.gd`'s `decide_play()` for the current version. Named `trust_gate` only in
`Phase3_Objective_Audit.md` — this exact string does not appear as an identifier anywhere in
`ai_player.gd` itself; it's an audit-assigned label for an anonymous inline branch, and the name
is now a misnomer kept only for cross-reference continuity (there is no trust content left).

---

## 6. Expert partner "no trust rule" — active, unresolved classification

**Where:** Same function, immediately adjacent to #5:
```
# Only trump can win.
if difficulty == "expert":
    # Expert Partner: no trust rule — play optimally for the contract.
    var chosen = _lowest_in(can_win, ...)
    reason_log.append("Trumping in — the contract needs this trick.")
    return chosen
```

**What it looks at:** Same geometry as #5 (only trump can win this trick).

**What decision it makes:** Commits immediately, skipping the hold-back check entirely.

**Behavior change:** Expert partner always trumps in here; standard partner sometimes waits.

**Layer:** Also commitment-adjacent, but structured as an early return that *bypasses* the gate
rather than a gate that can fail — different mechanical shape from #5 even though both are
difficulty-conditioned forks off the same geometric branch point.

**Status:** Active code, question reframed (July 5, 2026). This was flagged as an unresolved
conceptual question in the Ranking Unification summary and Next Session Prep: does "no trust rule"
mean better judgment or reduced cooperation? BUG-005's fix to #5 changed what's actually being
asked — the standard-difficulty branch this bypass skips no longer has any trust content, only
deterministic margin/counter/lead-economy evaluation. `Difficulty_Feed_Points_Inventory.md` reframes
this as a concrete, testable question instead: does expert still need a separate bypass at all,
now that the underlying logic it skips is difficulty-agnostic in principle? Recommended as the
next thing to try, not yet tested. The original "better judgment vs. reduced trust" framing is
effectively moot either way, since there's no trust concept left to have an opinion about.

---

## 7. `value_gate` — branch #25, active, commitment gate

**Where:** `decide_play()`, opponent-following-beginner-difficulty branch. Actual code:
```
if difficulty == "beginner":
    # Beginner: only contest the trick if counters are already on the table.
    if can_win.size() > 0:
        var trick_pts = _estimate_trick_value(plays, trump)
        if trick_pts >= 5:
            var chosen = _lowest_in(can_win, ...)
            reason_log.append("These points are worth contesting.")
            return chosen
        # Trick not worth contesting — fall through to discard
```

**What it looks at:** `_estimate_trick_value(plays, trump)` — the point value already visible
in the current trick.

**What info it uses:** Public trick state (no hidden information, no `PublicKnowledge` needed).

**What decision it makes:** Whether a beginner-difficulty opponent bothers contesting a trick it
is capable of winning, gated on a hardcoded `>= 5` threshold.

**Behavior change:** Beginner opponents let low-value tricks go even when they could win them;
standard/expert opponents (see next section) always try.

**Layer:** Commitment gate (per Phase3_Objective_Audit.md) — same shape as `trust_gate`: a valid
objective (`CASH_COUNTERS`/win-the-trick) is suppressed rather than executed, falling through to
the generic discard block on failure.

**Status:** Active code. **Naming collision to flag:** this same branch is called `value_gate`
in `Phase3_Objective_Audit.md`'s branch table, but called `CONTEST_IF_WORTHWHILE` in the trick-
objectives vocabulary header drafted for insertion above `decide_play()`. Both docs describe the
identical branch (`trick_pts >= 5`, beginner-only, opponent-following) under two different names.
Neither name exists as an actual identifier in the code — the branch itself is anonymous.

**Known bug tied to this branch:** its failure path falls into the shared discard block and
picks up the generic reason string *"Can't win this one — discarding low"* — inaccurate, since
the AI can win but is choosing not to. Logged as a candidate for `AI_Explanation_Bug_Log.md`,
not yet fixed.

---

## 8. `trust_threshold` — named in design docs, not built

**Where:** Appears only in `Phase3_Objective_Audit.md` and the two most recent session summaries,
as a **candidate** `AI_MODES` parameter. Does not exist in `ai_player.gd`.

**What it would look at:** Proposed as the generalized form of `trust_gate` (#5) — "trust in
downstream player" as a scalar rather than a bare difficulty string.

**Status:** Design document only, and now **has no confirmed source branch** (updated July 5,
2026) — #5, the branch this was supposed to generalize, no longer has trust content after
BUG-005. Whether `trust_threshold` should still be built, and for what, is the open question now
(not "held pending #6's resolution" as previously framed) — see `Phase3_Objective_Audit.md`'s
post-BUG-005 correction. Don't resume this design work by default.

**Also called** `trust_others` in one place (the doctrine-block comment in `ai_player.gd`
itself: *"an AI_MODES axis (risk_bias, cooperation_bias, opportunism, ...)"* elsewhere lists
*"a 'contest_threshold' or 'trust_others' knob"*). So the not-yet-built parameter already has
three candidate names in circulation: `trust_threshold`, `trust_others`, and the existing
placeholder `cooperation_bias` it's slated to replace.

---

## 9. `contest_threshold` — named in design docs, not built

**Where:** `Phase3_Objective_Audit.md`, candidate `AI_MODES` parameters table. Proposed as the
generalized, tunable form of `value_gate`'s hardcoded `trick_pts >= 5` (#7).

**Status:** Design document only, not built. Noted as sharing the same mechanical shape as
`trust_threshold` — "a scalar compared against a computed signal, gating fallback to `ESCAPE`" —
with an open suggestion (not a decision) to design both as one mechanism with two inputs rather
than two separate parameters.

---

## 10. Beginner "economy/protection" branches (#13, #17) — active, unnamed

**Where:** `decide_play()`, two separate beginner-only branches:

- Branch #13 (partner following, can_win, beginner): *"Beginner Partner: always secure the trick
  without second-guessing card economy"* — skips the non-trump-preference step that standard/
  expert use.
- Branch #17 (partner following, can't win, beginner): *"Beginner Partner: more aggressive
  counter protection — discard highest non-counter non-trump first."*

**What they look at:** Pure geometry (can_win / can't_win), no numeric signal — these are bare
`if difficulty == "beginner"` checks with no threshold at all, unlike `value_gate`.

**What decision it makes:** Branch #13 skips an optimization step. Branch #17 changes discard
order (highest-first vs. lowest-first).

**Behavior change:** Beginner partner plays more simply/protectively in both cases.

**Layer:** Evaluation, per the audit — but currently implemented as bare difficulty branches
with no parameter behind them at all (not even a string like `cooperation_bias`).

**Status:** Active code. Flagged in the candidate-parameters table as *"execution-only, lower
priority... likely folds into a single 'caution' style parameter rather than needing its own
name"* — but this is speculative; no such parameter exists yet, named or unnamed.

---

## 11. `FORCE_A_VOID` aggressive/conservative fork — design-stage, not yet code

**Where:** Currently `FORCE_A_VOID` (expert-only, Knowledge-gated lead into a known void) is a
single fixed execution: always lead the highest domino in the void suit, always maximizing
pressure. No fork exists in code today.

**What the design conversation raised:** The fixed "always aggressive" execution is suspected to
be wrong — real behavior should sometimes maintain control and sometimes pass the lead safely,
and geometry alone (a known void) can't tell you which. This was reframed in the July 5 prep doc
as potentially a **third instance of the commitment-gate pattern** alongside `trust_gate` and
`value_gate`, possibly sharing a mechanism with `trust_threshold`/`contest_threshold`.

**Status:** Open design question, explicitly not resolved, explicitly not something to spec
solo. No code changes have been made. Listed here because it was proposed as sitting on the same
mechanism as Phase 2's trust/commitment concepts, even though `FORCE_A_VOID` itself is
Knowledge-classified (Phase-4-adjacent), not Phase-2-classified, everywhere else in the docs.
This is itself a boundary fuzziness: an aggression/caution fork is being discussed as Phase-2
machinery living inside a Phase-4/Phase-3 lead objective.

---

## 12. "Win Safety" and "Trust" (conceptual, design-doc only — largely unbuilt)

**Where:** Jul 1 and Jul 2 session summaries only. No corresponding code exists beyond `trust_gate`
(#5) and the expert bypass (#6).

**What it's described as:** Win Safety = "the probability that a partner's current winning
position will hold at trick resolution." Trust = "a difficulty-scaled threshold that controls how
aggressively the partner acts on uncertain Win Safety estimates" — answering *"how confident do I
need to be that this trick is safe before I dump a counter into it?"*

**Described properties (all narrative, none implemented as such):**
- Bypassed at P=1.0 (guaranteed wins never consult Trust)
- Bypassed by opportunity cost (best-chance-a-counter-will-ever-get overrides Trust)
- "Active in the uncertain middle" — the actual differentiator between difficulties
- Applies to partner and opponents *separately* — two independent Trust values, not one

**What actually exists in code today:** Only the P=1.0 case is even partially addressed (the
Phase 1 counter-dumping fix, itself only partially implemented per the Phase 1 gap list). The
"uncertain middle" case requires Phase 4 probability estimation that does not exist —
`PublicKnowledge` currently only answers binary/enumerable facts (void, remaining count, etc.),
not probabilities. "Opportunity cost" bypass has no code representation anywhere.

**Status:** Design document only. This is the most elaborate Phase 2 concept in the docs and the
least connected to actual code. Previously the only implemented fragment was `trust_gate`'s
narrow standard-difficulty branch, itself pure turn-order geometry with no reference to "Win
Safety," "P=1.0," or "opportunity cost" — that's now stale too (see #5): the branch no longer
exists in that form, and its replacement (contract margin/live counter/lead economy) still
doesn't implement Win Safety or probability-based Trust in any form. This concept remains design
document only.

**Separately noted, narrative only:** *"Phase 2 also governs opponent play aggression — how hard
they contest tricks, how much they push back under pressure."* This sentence has no attached
mechanism at all — the closest existing code is `value_gate` (#7), which is beginner-only and the
opposite direction (when opponents *don't* contest), not a general aggression dial.

---

## 13. Auction stance (`pressure_opener` / `solid_opener` / `competitive` / `defensive`)

**Where:** `ai_player.gd`, `decide_bid()`, Layer 2. Own subsystem, not part of `AI_MODES`:
```
var auction_stance := "anchor"
if est_tricks >= 4.3 and has_double_trump:
    auction_stance = "pressure_opener"
elif est_tricks >= 4.0 and eval.get("trump_count", 0) >= 4:
    auction_stance = "solid_opener"
elif ev_score >= 24.0:
    auction_stance = "competitive"
else:
    auction_stance = "defensive"
```

**What it looks at:** `estimated_tricks`, `has_double_trump`, `trump_count`, and the already-
computed `ev_score` (which itself already includes `risk_bias`).

**What decision it makes:** Classifies bid intent into one of four labeled stances, each with a
fixed `stance_bias` (+2.0 / +1.0 / 0.0 / -1.5) added into `final_score` and `target_bid`.

**Behavior change:** Shifts both whether the AI bids and how high, on top of what `risk_bias`
already shifted.

**Layer:** Evaluation (Layer 2), explicitly documented as *"a shape modifier on decision
pressure, not a replacement of EV."*

**Status:** Active code, fully wired. **Not named as a Phase 2 concept anywhere** — it doesn't
appear in `AI_MODES`, isn't called "personality," and isn't referenced in any of the four-phase
roadmap docs — despite the stance labels themselves (`pressure_opener`, `competitive`,
`defensive`) being exactly the vocabulary Phase 2 is supposed to own ("how aggressively to act").
This is a case where aggression-shaped behavior exists and is fully active, under a name that has
never been connected to the Phase 2 discussion.

---

## 14. `realization_bias` / `counter_points` — active computation, zero behavioral effect

**Where:** `ai_player.gd`, `evaluate_hand()`.
```
# Does NOT increase expected value — counters in hand do not add EV,
# they only indicate realization confidence for future use (Phase 2 risk).
var baseline_share := estimated_tricks / 7.0
var realization_bias := 0.0
...
```

**What it looks at:** Per-domino win probability for counter tiles (pip_sum 5 or 10), compared
against a baseline share of expected tricks.

**What decision it makes:** None currently — computed, stored in the returned dict, logged in
bid-decision output, and explicitly **not** added to `estimated_points` (the comment says so
directly: *"Do NOT add realization_bias to estimated_points"*).

**Behavior change:** None. Diagnostic/logging only.

**Layer:** N/A — inert signal.

**Status:** Active code, but functionally a no-op. Explicitly labeled in its own comment as
existing "for future use (Phase 2 risk)." This is the one place in the codebase where a
computation is pre-built and directly earmarked for Phase 2 by name, ahead of Phase 2 actually
being speced.

---

## 15. "Confidence" — docstring claims a field that doesn't exist

**Where:** `ai_player.gd`, `evaluate_hand()` docstring:
```
# Score a hand assuming a given trump suit.
# Returns a dictionary with estimated points, tricks, and confidence.
```

**What actually is returned:** `trump`, `trump_count`, `has_double_trump`, `estimated_tricks`,
`expected_capture`, `counter_points`, `realization_bias`, `estimated_points`. **No `confidence`
key exists anywhere in the dictionary.**

**Status:** Comment/code mismatch — a one-off inconsistency, not a design finding. Flagged here
only because "confidence" is one of the words on the list; it does not correspond to any actual
mechanism. The closest real analog is `control_score` in `decide_bid()` (Layer 2), which is
inline-commented as *"structural confidence"* — but `control_score` is never called "confidence"
anywhere else, and the `evaluate_hand()` docstring's "confidence" doesn't refer to it (it's a
stale comment predating `control_score`'s introduction in the bidding rewrite).

---

## 16. Opponent-behavior header comment — narrative personality profile, partially active

**Where:** `decide_play()`, comment immediately above the opponent-behavior block:
```
# ── OPPONENT BEHAVIOR ─────────────────────────────────────────────────────
# Standard: solid casual play — not bloodthirsty, not passive.
# Beginner: conservative opens, only contests tricks with counters already in them.
# Expert: compete harder (handled in bidding); TODO Phase 3 opportunism.
```

**What it describes:** A three-tier personality sketch for opponents specifically (separate from
the partner personality sketch elsewhere in the file).

**Correspondence to actual code:**
- "Beginner: conservative opens" → branch #19, `FEEL_OUT_THE_HAND` (classified Neither, a true
  difficulty-branch exception, not Evaluation/Knowledge).
- "Beginner: only contests tricks with counters already in them" → `value_gate` (#7).
- "Expert: compete harder (handled in bidding)" → this is `risk_bias` (#1), pointing outside
  `decide_play()` entirely.
- "Standard: solid casual play" → no dedicated branch; standard opponents fall through to the
  same logic as expert opponents in every branch except the two called out above.
- "TODO Phase 3 opportunism" → still an open TODO in spirit; the literal comment location was
  filled by `FORCE_A_VOID` (Knowledge-classified), not by an opportunism mechanism (see #4).

**Status:** Comment describing a mix of active code, a pointer to a different subsystem
(bidding), and one still-unfulfilled TODO — three different states bundled into one three-line
personality sketch.

---

## 17. "Personality" as a label — comment-only umbrella term

**Where:** Used in at least four places to describe different things:
1. `decide_bid()` Layer 2 comment: *"(C) Risk signal — how aggressive is this player? (AI_MODES
   personality)"* — refers to `risk_bias` specifically.
2. `_log_bid_decision()` doesn't use the word, but the Jul 1/Jul 2 summaries say *"Personality
   (AI_MODES) lives here via risk_bias and max_overbid"* — refers to both bidding parameters.
3. Onboarding doc: *"AI_MODES is a single dict of named parameters (risk_bias, max_overbid,
   opportunism, cooperation_bias) — that's the intended place personality differences live"* —
   includes all four AI_MODES keys, active and placeholder alike.
4. Roadmap backlog item: *"Named personality presets after observation"* — a still-future,
   unscoped idea about naming difficulty tiers themselves (e.g., "Uncle Ed") after enough
   playtesting, unrelated to any of the above three code-level usages.

**Status:** "Personality" is never a code identifier — it's a comment-level umbrella that
sometimes means "the two active bidding parameters," sometimes means "all four AI_MODES keys
including the two dead ones," and sometimes means "difficulty-tier naming," depending on which
doc is being read.

---

## Summary table — status at a glance

| Concept / identifier | Location type | Active? | Layer |
|---|---|---|---|
| `risk_bias` | code (`AI_MODES`, `decide_bid`) | Yes | Evaluation |
| `max_overbid` | code (`AI_MODES`, `decide_bid`) | Yes | Execution |
| `cooperation_bias` | code (`AI_MODES`), dead read | No | — |
| `opportunism` | code (`AI_MODES`), dead read | No | — |
| `trust_gate` (audit name) | code, anonymous branch #16 | Yes | Commitment gate |
| Expert "no trust rule" | code, anonymous branch | Yes | Commitment-adjacent (bypass) |
| `value_gate` / `CONTEST_IF_WORTHWHILE` | code, anonymous branch #25 | Yes | Commitment gate |
| `trust_threshold` | design doc only | No | proposed Commitment |
| `contest_threshold` | design doc only | No | proposed Commitment |
| Beginner branches #13/#17 | code, bare difficulty checks | Yes | Evaluation (unparameterized) |
| `FORCE_A_VOID` aggressive/conservative fork | design discussion only | No | unresolved |
| "Win Safety" / general Trust concept | design doc only | Mostly no | unresolved |
| Auction stance (`pressure_opener` etc.) | code, `decide_bid` | Yes | Evaluation |
| `realization_bias` / `counter_points` | code, computed, unused | Inert | — |
| "confidence" (docstring) | comment only | N/A | mismatch, no field exists |
| Opponent-behavior personality comment | comment | Mixed | mixed |
| "Personality" as umbrella term | comment, 4 docs | N/A | no single referent |

---

## Fuzziness/inconsistency flags (observations only, no proposed fixes)

1. **`cooperation_bias`** is labeled `# Phase 3` in its own code comment but is called the
   "Phase 2 placeholder" everywhere else.
2. **`value_gate`** and **`CONTEST_IF_WORTHWHILE`** name the same anonymous branch in two
   different documents; neither name exists in the code itself.
3. **`opportunism`** has two disconnected referents: a dead dict key, and an implemented
   Knowledge-gated behavior (`FORCE_A_VOID`) that filled its TODO's former location without
   using its name or mechanism.
4. **Auction stance** implements aggression-shaped behavior (`pressure_opener` /
   `defensive`) that is fully active, fully wired, and never once connected to the Phase 2
   discussion in any doc.
5. **"Confidence"** is promised by a docstring, not present as a field, and loosely echoed by
   an unrelated, differently-named variable (`control_score`) added later.
6. **Trust** currently has three names in circulation for what may be one thing:
   `cooperation_bias` (existing placeholder), `trust_threshold`, and `trust_others`.
7. **`FORCE_A_VOID`'s** possible aggression/caution fork is being discussed as Phase-2-shaped
   machinery while the branch it lives inside is Knowledge-classified (Phase 4-adjacent, expert +
   `PublicKnowledge`-gated) everywhere else.
8. **Win Safety / Trust** as described in the Jul 1/Jul 2 docs is the richest Phase 2 concept in
   prose and the thinnest in code — only one narrow, geometry-only branch (`trust_gate`)
   implements any part of it, and that branch's actual logic (turn order) doesn't match the
   probabilistic language ("P=1.0," "opportunity cost") used to describe the broader concept.
