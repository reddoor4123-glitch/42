# Phase 2 Control-Layer Audit (v1, locked)

*Companion to `Phase3_Objective_Audit.md` and successor to
`Phase2_Raw_Concept_Audit.md`. Where the raw audit inventoried every
Phase-2-labeled concept as found, this document is the settled structural
model those concepts sort into — arrived at by stress-testing candidate
models against actual branches in `ai_player.gd` until one stopped
breaking. Nothing in this document required new code; it is a
classification of behavior that already exists (or is explicitly named as
not yet existing).*

*Purpose: this is the working document for wiring `AI_MODES` scalars going
forward. It answers, per concept: which of the three control categories
does this belong to, is it implemented or a placeholder, and what does it
actually consume or produce.*

---

## The core finding

Phase 2 is not a decision-making phase. It does not choose objectives and
it does not decide whether to act on them. **Phase 2's only real job is to
manufacture scalars that other stages consume.** The stages that consume
them are permanent, phase-agnostic parts of the objective pipeline already
described in `Phase3_Objective_Audit.md`.

There are exactly three control categories in the system. A fourth
candidate ("Knowledge" as a pipeline stage above Selection) was proposed
and tested against the code this session and rejected — see "Rejected
alternative" below.

```
SELECTION
  geometry (+ optional PublicKnowledge-derived predicates) → objective
      ↓
COMMITMENT (optional)
  a selected objective may be declined in favor of a safer/cheaper
  realization, gated by a scalar threshold
      ↓
MODULATION
  continuous scalars shift a score inside a fixed decision function;
  never change which code path executes
```

**Correction (post Phase 1 resolution — see `Phase1_Control_Layer_Audit.md`):**
this section originally claimed Phase 1's cardinal rule sits above this
entire pipeline as a hard invariant, not a category the pipeline resolves
into. That claim was tested directly against real table scenarios during
the Phase 1 resolution session and found to be wrong. The cardinal rule
(`human_is_winning`) is ordinary Selection — `PROTECT_PARTNER_WIN`, geometric,
difficulty-invariant, the same shape as every other objective in
`Phase3_Objective_Audit.md`'s branch table (#4, #11, #12). It does not sit
above the pipeline and does not need its own category. See
`Phase1_Control_Layer_Audit.md` for the full resolution, including the one
genuine exception that *was* found (a long-horizon lead-control concept
that doesn't fit Selection/Commitment/Modulation — parked there, not here).

### The discriminator (the one test that resolved every ambiguous case this session)

> Does this branch change **which action-producing code path executes**,
> or does it only change a **magnitude feeding one fixed path**?

- Changes which path executes → **Commitment** (if a selected objective is
  being declined) or **Selection** (if an objective is being chosen in the
  first place).
- Only changes a magnitude, path never changes → **Modulation**, even if
  the input that produced the magnitude was itself discrete (see
  `auction_stance` below — this was the key edge case that sharpened the
  test).

---

## Category 1 — Selection

Objectives are chosen from predicates. Predicates may be ordinary local
geometry (`partner_winning`, `trump_count >= 3`) or `PublicKnowledge`-derived
(`void_suits(opp)`). **There is no architectural distinction in the code
between these two predicate types** — no candidate-list step, no place
where "knowledge ends and selection begins." Every objective branch is an
inline `if` evaluated against whatever predicate it needs, evaluated in
place, not filtered from a pre-built candidate set. This is why Knowledge
does not get its own pipeline stage: the code gives no seam to hang one on.

**Predicate provenance** is a useful descriptive tag, not a structural
layer: internal-state predicates vs. `PublicKnowledge`-derived predicates
explain why some objectives (`FORCE_A_VOID`) are knowledge-gated to expert
while others (`CONTROL_TRUMP`) are available to everyone — but both are
ordinary Selection-stage objectives.

| Concept | Predicate type | Status |
|---|---|---|
| `FORCE_A_VOID` | PublicKnowledge-derived (`void_suits`) | Implemented, expert-only, playtest-pending |
| `opportunism` | PublicKnowledge-derived (intended) | **Inert placeholder.** Declared in `AI_MODES`, read, never acted on. Once built, belongs here — same shape as `FORCE_A_VOID`, not a new layer, not Modulation. |
| All other named objectives (`PROTECT_PARTNER_WIN`, `SECURE_FOR_PARTNER`, `CASH_COUNTERS`, `CONTROL_TRUMP`, `ESCAPE`, `OPEN_SAFE_SUIT`, `PROTECT_COUNTERS_WHILE_LEADING`) | Internal-state | Implemented — see `Phase3_Objective_Audit.md` for full branch table |
| `FEEL_OUT_THE_HAND` | Internal-state (`hand.size()==7`), difficulty-gated only | **Removed (July 6, 2026).** Previously logged here as "confirmed genuine exception — a case where difficulty changes which mission is even in play." That didn't hold up: no legitimate strategic basis for unconditionally suppressing trump control on trick one regardless of hand strength. Deleted from `ai_player.gd` rather than left as a direct branch — see `Phase3_Objective_Audit.md` branch #19. |

### Rejected alternative — "Knowledge" as a fourth pipeline stage above Selection

Proposed this session: `FORCE_A_VOID` and `opportunism` narrow the
candidate space *before* Selection runs, making Knowledge a distinct stage
sitting above it. Tested against the code and rejected: `FORCE_A_VOID` is
not filtering a pre-existing candidate list — there is no such list
anywhere in `decide_play()`. The objective is constructed in place when its
predicate evaluates true, exactly like every other objective. Promoting it
above Selection would add architecture the implementation doesn't need or
support. Recorded here so this doesn't get re-proposed without the reasons
for rejecting it being visible.

**Watch condition:** this rejection is an accurate empirical description of
the current code, not a structural guarantee. It holds only as long as no
precomputed candidate/legal-action list exists upstream of objective
evaluation in `decide_play()`. If a future refactor ever introduces one
(for performance, UI hinting, or any unrelated reason), re-open this
question before assuming the Selection/Knowledge merger still applies —
that kind of change would silently reintroduce exactly the separation this
section argues against.

---

## Category 2 — Commitment (gates)

A selected objective is available (its Selection predicate is true) but is
**actively declined** in favor of a safer or cheaper realization, gated by
a scalar threshold. This is the only place in the system where "a valid
objective is available and not executed" happens — everywhere else in
Selection, an objective either applies or it doesn't; there's no declining
a live one.

**Confirmed invariant (from the reason_log text itself):** a commitment
failure reuses the `ESCAPE` action, but does not rebind the objective's
*belief state* to `ESCAPE`. The AI at a failed gate believes it could win
and is choosing not to — a materially different claim from true `ESCAPE`
("can't win this one"). Both confirmed gate instances behave identically in
this respect; an earlier suspicion that they diverged structurally was
checked against the code and found to be a reason-string quality gap only
(see Category 2 table, `value_gate`), not a behavioral difference.

| Concept | Current gate input | Shape | Status |
|---|---|---|---|
| `trust_gate` (`decide_play()` branch #16) | Contract margin (zero-sum reachability) → live counter status (`_live_counter_for_suit()`) → lead economy | Sequential scalar/deterministic checks, no turn-order or trust component | **Rewritten under BUG-005** (implemented, playtest-confirmed, July 5). No longer a candidate source for `trust_threshold` — see `Phase3_Objective_Audit.md` correction. Name `trust_gate` is now a misnomer kept only for cross-reference continuity; consider renaming in a future pass. |
| `value_gate` (`decide_play()` branch #25) | `trick_pts >= 5`, hardcoded | Scalar threshold, not yet parameterized | Implemented. Candidate `AI_MODES` param: `contest_threshold`. **Known bug:** failure path's reason string is a generic `ESCAPE`-flavored line ("Can't win this one — discarding low"), which misstates the belief state (AI *can* win, is choosing not to contest). Logged as a candidate for the Phase 1 reason-string rewrite, not fixed here. |
| Void-lead aggressive/conservative fork | Does not exist yet | N/A | **Design-only, no code.** If built as "same `FORCE_A_VOID` intent, second signal decides highest-vs-lowest realization," it becomes a third instance of this category by definition — same shape as `trust_gate`/`value_gate`. This was the open question from the July 5 prep doc; it's now answered conditionally: not yet real, but if built, this is where it goes. |

`trust_threshold` and `contest_threshold` share the same shape (a scalar
compared against a computed signal, gating fallback to `ESCAPE`'s action)
and are worth designing as one mechanism with two inputs, not two unrelated
parameters, per the original Phase 3 audit's note — unchanged by this
session's work.

> The `trust_threshold`/`contest_threshold` "share the same shape" note
> above this table (end of Category 2) was written when `trust_gate` was
> still turn-order-based. `contest_threshold` (`value_gate`, #25) is
> unaffected and still an accurate description. `trust_threshold` no
> longer has a source branch to generalize from — see Patch 1b.

---

## Category 3 — Modulation

Continuous scalars that shift a score inside a fixed decision function.
Never change which action-producing code path executes — only a magnitude
feeding one path that was always going to run.

| Concept | Where | Effect | Status |
|---|---|---|---|
| `risk_bias` | `decide_bid()` Layer 2 | Shifts `ev_score` (`+ risk_bias * 4.0`) and `target_bid` (`+ risk_bias * 3.0`) | Implemented, working, values: beginner `-0.25` / standard `0.0` / expert `0.25` |
| `max_overbid` | `decide_bid()` Layer 3 | Clamps `target_bid` ceiling | Implemented, working |
| `auction_stance` / `stance_bias` | `decide_bid()` Layer 2 | Discretely classified (`pressure_opener`/`solid_opener`/`competitive`/`defensive`) via threshold checks, but only ever feeds a `stance_bias` number into the same `final_score` formula — never selects a different bid-type function | Implemented, working. **Key edge case:** proves discrete classification ≠ topology change. This is what sharpened the discriminator test above. |

---

## Unresolved — not yet sorted, and not sortable from current evidence

**`cooperation_bias`** — Declared in `AI_MODES` (`"beginner": "high"`,
`"standard": "medium"`, `"expert": "medium"`), read in `decide_play()`,
never acted on (`@warning_ignore("unused_variable")`). Unlike `opportunism`,
its intended destination isn't a Selection predicate — the design docs
consistently describe it as feeding *Trust*, which is Commitment-shaped
(a threshold a gate compares against).

**Updated (July 5, 2026) — the rename target itself changed underneath this entry.** The standing
proposal was to rename this to `trust_threshold` so it could supply the scalar `trust_gate`
lacked. Post-BUG-005, `trust_gate` (branch #16, see Category 2 table) no longer has a scalar to
supply at all — it's rebuilt on deterministic contract-margin/live-counter/lead-economy checks,
none of which are a trust threshold. `trust_threshold` currently has **no confirmed source
branch**. The old blocking question below (better judgment vs. reduced trust) is effectively moot
either way, since there's no trust concept left in the branch it was meant to describe —
`Difficulty_Feed_Points_Inventory.md` reframes it instead as a concrete testable question: does
Expert still need a separate bypass, now that the logic underneath is difficulty-agnostic in
principle? Not yet tested. Original framing kept below for history:

Does the Expert partner's "no trust rule"
represent better judgment (evaluation-quality, arguably not a Commitment
concept at all) or reduced trust in teammates (a personality value, same
family as `risk_bias`)? Both interpretations currently produce identical
Expert-level behavior, which is exactly why this is easy to mistake for
resolved once a scalar exists. Until a ruling is made (if one is still needed at all),
`cooperation_bias`/`trust_threshold` should be treated and
documented as a **semantically underspecified axis with no confirmed source branch**: not
constructable in the way originally planned. See
`Texas_42_Session_Summary_July_4_2026_RankingUnification.md`, Finding 5, for the original framing.

**Win Safety / Trust-as-probability** — Defined only in prose (July 1/2
session summaries): a probability estimate of whether a partner's winning
position holds, gated by a Trust threshold. No corresponding data model
exists. The only row of the original Win Safety table that's real is P=1.0
(guaranteed win via double-led, no trump) — which is already handled
unconditionally by the Phase 1 cardinal rule, not by anything called Trust.
The ~0.8 and ~0.6 rows are explicitly marked as needing Phase 4 inference
that doesn't exist yet. This remains a narrative concept without
implementable structure — not wrong, just not yet buildable.

**MARKS cardinal-rule override** — **Resolved (July 5, 2026), no longer unresolved.** This entry
asked whether a partner should ever steal a trick the human is winning under a Marks/Plunge/
Splash contract. Per `Phase1_Control_Layer_Audit.md`'s resolution, the question splits in two:
the ordinary trick-protection half is ordinary Selection (`PROTECT_PARTNER_WIN`), same as the
standard-contract case, no Marks-specific treatment needed. The harder half — declining a
guaranteed win to hand lead control to a better-positioned teammate for a *future* trick — turned
out not to be Marks-specific at all, doesn't fit Selection/Commitment/Modulation (all three are
scoped to the trick in front of you), and is permanently parked in that document. Left here only
as a pointer, since this was a Phase 1 question misfiled adjacent to Phase 2's Commitment category,
not a Phase 2 concept.

---

## What this document changes going forward

- `AI_MODES` entries should be evaluated against the three categories
  before being wired: does this scalar feed a fixed formula (Modulation),
  gate a fallback (Commitment), or guard an objective's predicate
  (Selection)? If it does none of these, it isn't ready to be wired yet —
  see the two Unresolved items above.
- The six bare `difficulty ==` branches from the original Phase 3 audit are
  unaffected by this document except in one respect: their eventual
  `AI_MODES` parameters now have a confirmed home (`trust_threshold` /
  `contest_threshold` → Commitment) rather than an ambiguous "Phase 2" one.
- No code changes are implied or required by this document. It is
  classification only, same as `Phase3_Objective_Audit.md` was for
  objectives.
