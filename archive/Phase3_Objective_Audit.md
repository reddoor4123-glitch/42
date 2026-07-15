# Phase 3 Objective Audit — `decide_play()` (v1, locked)

*Companion to the "TRICK OBJECTIVES" header block in `ai_player.gd`. That
block is the vocabulary; this document is the verified, branch-by-branch
mapping against it. Produced by a full pass through every branch in
`decide_play()`, cross-checked against `AI_Play_Behavior_Bug_Log.md` and
`Texas_42_Session_Summary_July_4_2026_RankingUnification.md`.*

*Purpose: this is the working document for the Phase 3 difficulty-branch
collapse. It answers, per branch: is difficulty changing which objective
runs, or just how well a fixed objective is executed — and where neither
question applies because the branch isn't part of the objective system at
all.*

---

## System model

```
SYSTEM ROUTER
├── Mechanical override — no geometry interpreted, decide_play() is
│   fully bypassed (SEVENS, NELLO)
│
└── Geometry-driven objective system — everything else
      geometry → objective (selection) → commitment gate (optional) → execution
```

Three points in that pipeline matter for Phase 3:

- **Selection** — which objective applies, decided from decision geometry
  (`partner_winning`, `can_win`, void state, trump count). Difficulty-invariant
  in every confirmed case except the mechanical overrides.
- **Commitment gate** — a small number of branches make a costlier objective
  geometrically reachable, but require a scalar threshold to pass before
  committing to it. On failure, the branch falls back to `ESCAPE` — never to
  a different objective. Two confirmed instances (see below); this is
  probably the natural home for `trust_threshold` / `contest_threshold` as
  actual `AI_MODES` parameters.
- **Execution** — same objective, same selection, difficulty only changes
  play quality within it (e.g. preferring non-trump winners, or economy vs.
  simplicity of the discard).

**Important distinction, confirmed by the reason_log text itself:** a
commitment-gate failure reuses `ESCAPE`'s action logic, but does not rebind
the objective to `ESCAPE`. The AI's belief state at a failed gate is not "I
cannot win this trick" (true `ESCAPE`) — it's "I could win this, but I'm
choosing not to spend the resource / trust someone else instead." #16's
gate-fail string reads *"there's still a chance someone else covers"* — a
materially different claim than `ESCAPE`'s *"can't win this one."* `ESCAPE`
functions here as a universal fallback **action policy**, not a competing
objective. Treating it as a real strategy during the `AI_MODES` collapse
would blur exactly the distinction this audit exists to preserve.

---

## Objective vocabulary (confirmed, this pass)

Carried over from the original header block, unchanged:
`PROTECT_PARTNER_WIN`, `SECURE_FOR_PARTNER`, `CASH_COUNTERS`,
`CONTEST_IF_WORTHWHILE`, `ESCAPE`, `CONTROL_TRUMP`, `FORCE_A_VOID`.

**`ESCAPE`, meaning constraint (tightened this pass):** `ESCAPE` describes
a no-winning-state belief, not a generic discard action. Commitment-gate
failures (#16, #25) may reuse `ESCAPE`'s action logic but must not inherit
its belief semantics — the AI at a failed gate believes it *could* win and
is declining to, which is not what `ESCAPE` means anywhere else it's used.
Treat this as a consistency rule for future branches, not just a note about
these two: if a new branch reuses `ESCAPE`'s action path, check whether it
also carries `ESCAPE`'s belief before assuming the string can be shared.

New, found this pass — both geometric, both difficulty-invariant in
selection, straightforward additions to the vocabulary:
- **`OPEN_SAFE_SUIT`** — partner leading, give the human a safe suit to
  follow without spending trump or exposing a counter.
- **`PROTECT_COUNTERS_WHILE_LEADING`** — partner leading, when no safe
  off-suit tile exists; prefer any non-counter lead over exposing points.

Reclassified as a named cross-cutting mechanism rather than a branch-local
detail: **`COMMITMENT_GATE`** (see above). Not itself a new objective —
it's the boundary that explains why #15 and #24 don't fit `SECURE_FOR_PARTNER`
or `ESCAPE` cleanly on their own.

**Removed entirely (July 6, 2026), not merely "not part of the objective
system":** `FEEL_OUT_THE_HAND` (branch #19) was originally logged here as a
correctly-left "Neither" exception — no geometric input, difficulty-gated
only. On closer inspection there was no legitimate strategic basis for it:
unconditionally suppressing trump control on trick one regardless of hand
strength isn't a believable skill gap, it's a categorical strategy
suppression — same violation class as the also-removed branch #17 (see
below). Deleted from `ai_player.gd` rather than reclassified. See the
Trick Objectives header in `ai_player.gd` itself for the corrected framing.

**New (July 6, 2026, later same day) — two more additions, both geometric,
both knowledge-gated, neither difficulty-gated:**
- **`GIFT_A_VOID`** (branch 6a) — partner leading, target a suit the human
  is known void in; lead the double or the currently-highest-remaining
  tile in that suit to hand the human a good-confidence discard. Mirror
  image of `FORCE_A_VOID` in intent (create an opportunity instead of
  forcing a cost) but not the same objective — kept as a separate name
  rather than folded into `FORCE_A_VOID`, since the target (partner's
  void) and the purpose (help, not pressure) both differ.
- **`FORCE_A_VOID`'s partner-leading instance** (branch 6b) — same
  objective and predicate as the existing opponent-leading instance (#20),
  mirrored for partner leads, with a self-assessment gamble (do we have a
  strong follow-up lead) deciding highest-vs-lowest. **Deliberately not
  difficulty-gated**, unlike #20 — see 6b's row in the branch table for
  the asymmetry this creates and why it's by design.

---

## Full branch table

| # | Branch | Geometry | Objective | Type | Difficulty | Notes |
|---|---|---|---|---|---|---|
| 1 | SEVENS (early return) | none | none | mechanical override | NONE | bypasses `decide_play()` entirely |
| 2 | NELLO (early return) | none (role-keyed) | none | mechanical override | NONE | bypasses `decide_play()` entirely |
| 3 | MARKS/PLUNGE/SPLASH, leading | `is_leading` | `CONTROL_TRUMP`-adjacent, unconditional | constrained | NONE | stricter than standard `CONTROL_TRUMP` (no trump-count threshold) |
| 4 | MARKS, partner-winning | `partner_winning` | `PROTECT_PARTNER_WIN` | constrained | NONE | **duplicate of #11** — reimplemented, not shared. **Open-Q tag resolved (July 5, 2026):** the MARKS cardinal-rule question this branch was flagged for has been split and closed — see `Phase1_Control_Layer_Audit.md`. Trick-protection half is ordinary Selection (this row, no special treatment needed); the harder half (declining a guaranteed win to hand lead control to a better-positioned teammate for a future trick) turned out not to be Marks-specific at all and is permanently parked there. |
| 5 | MARKS, can-win | `can_win` | `SECURE_FOR_PARTNER` | constrained | NONE | economy/trust stripped — arguably correct for Marks |
| 6 | MARKS, can't win | `!can_win` | `ESCAPE` | constrained | NONE | no pip filtering (correct — counters irrelevant under Marks) |
| 6a | Partner leading, human known void in a suit | `is_leading`, `is_partner`, `void_suits(partner_id)` | `GIFT_A_VOID` (new) | geometric, knowledge-gated | NONE (deliberately not difficulty-gated) | **New (July 6, 2026).** Runs first in the partner-leading block, before 6b and #8. Targets a suit the human is known void in — lead the double, or the currently-highest-remaining tile in that suit, to hand the human a good-confidence (not guaranteed) discard. An opponent could still trump in; that risk is accepted, not resolved. Mirror-image intent of `FORCE_A_VOID`: opening an opportunity instead of forcing a cost. No difficulty gate — cooperative judgment is knowledge-limited, not difficulty-limited, per this file's own design philosophy. |
| 6b | Partner leading, opposing team known void in a suit | `is_leading`, `is_partner`, `void_suits(opp)` for both opponents, self-assessed `we_are_strong` | `FORCE_A_VOID` (partner-leading mirror of #20) | geometric, knowledge-gated | NONE (deliberately not difficulty-gated, amended July 6, 2026 — originally specced expert-only) | **New (July 6, 2026).** Runs second, after 6a and before #8. Targets a suit the opposing team is known void in — same predicate as #20, mirrored for partner leads. High-vs-low is a self-assessment gamble (do we still have a strong follow-up lead — trump control or a safe off-suit tile), not an information asymmetry about the human's hand; worth flagging that this self-assessment half reads more like Decision Geometry than Knowledge, even though the void-targeting half is genuinely Knowledge-gated same as #20. **Difficulty asymmetry, by design, not drift:** this instance and 6a run at every difficulty; #20 (opponent-leading `FORCE_A_VOID`) stays expert-only. Beginner/standard partners now get void-awareness beginner/standard opponents still don't. |
| 7 | Partner leading, `off_safe` | `is_leading`, `is_partner` | `OPEN_SAFE_SUIT` | geometric | NONE | — |
| 8 | Partner leading, `trumps>=3` (with double) or `trumps>=4` | same | `CONTROL_TRUMP` | geometric (selection) / WEIGHT (execution) | NONE (selection) | **BUG-003/003b fixed (July 5, 2026)**: now evaluated before #7 (`OPEN_SAFE_SUIT`), double-aware threshold (3+ with the double, 4+ otherwise). No longer unreachable. Also now runs after 6a/6b, in addition to before #7. **Execution differentiated by difficulty (July 6, 2026):** the `trump_control` predicate itself is still difficulty-invariant Selection, but *which trump gets led* now differs once control applies without the double — beginner and double-in-hand cases still lead highest ("drawing out the opponents"); standard/expert without the double lead lowest instead, to draw the double out of an opponent's hand before spending higher trump ("Leading low trump to draw out the double first"). A binary technique branch, not a scalar — same shape as the existing #13 beginner execution branch (**not #17 — removed July 6, 2026**, see that row below), not a new `AI_MODES` parameter. |
| 9 | Partner leading, `non_counters_lead` | same | `PROTECT_COUNTERS_WHILE_LEADING` | geometric | NONE | fallback tier |
| 10 | Partner leading, final fallback | same | `PROTECT_COUNTERS_WHILE_LEADING` (degraded) | geometric | NONE | last resort |
| 11 | Partner following, `human_is_winning` + guaranteed win | `partner_winning`, winner is double **or** provably highest-remaining-in-suit with trump exhausted | `PROTECT_PARTNER_WIN` | geometric + knowledge-gated (when non-double) | NONE | dump-counters variant. **Generalized (July 6, 2026):** guaranteed-win detection is no longer double-only — `PublicKnowledge.best_remaining_card_for_suit()` plus a `count_remaining_trump()`-based trump-exhaustion check (same technique as BUG-006) now also recognize a non-double, non-trump winner as safe. Difficulty-invariant by design decision (flagged for confirmation, not assumed) — treated as core cardinal-rule recognition, same as the existing double case, not a strategic technique gap like branch #8. See `AI_Play_Behavior_Bug_Log.md`'s design-notes entry for follow-on generalization ideas (a shared `_is_guaranteed_win()` helper, composing with BUG-007's void knowledge). |
| 12 | Partner following, `human_is_winning`, `not guaranteed_win` | same | `PROTECT_PARTNER_WIN` | geometric | NONE | duplicate pair with #4. **Condition phrasing updated (July 6, 2026):** was "no double," but since #11's generalization the actual gate is `not guaranteed_win` — broader than "no double" alone, since it also excludes the new non-double-but-provably-safe case (highest remaining in suit, trump exhausted). Behavior unchanged; this branch is exactly "everything #11 doesn't catch." |
| 13 | Partner following, `can_win`, beginner | `can_win`, `!partner_winning` | `SECURE_FOR_PARTNER` | geometric | WEIGHT | skips economy |
| 14 | Partner following, `can_win`, non-trump avail | same | `SECURE_FOR_PARTNER` | geometric | NONE (all difficulties) | prefer non-trump winner |
| 15 | Partner following, trump-only, expert | same | `SECURE_FOR_PARTNER` | geometric | WEIGHT | commits, no gate |
| 16 | Partner following, trump-only can-win, standard difficulty | `can_win` (trump only), `bid_value`/`team_points` state | `SECURE_FOR_PARTNER` | commitment gate | STANDARD only | **Rewritten under BUG-005 (implemented, playtest-confirmed).** Gate input is now contract margin (symmetric zero-sum reachability check) → live counter status (`_live_counter_for_suit()`, deterministic — rules out a counter only when provably unreachable) → lead economy. No turn-order check remains. See Patch note below — this branch no longer has any trust content. |
| 17 | ~~Partner following, can't win, beginner~~ | ~~`!can_win`~~ | ~~`ESCAPE`~~ | ~~geometric~~ | ~~WEIGHT~~ | **Removed (July 6, 2026).** The "protect-highest-first" variant (discard the highest safe tile instead of the lowest) had no valid strategic basis — its own stated justification didn't hold, since the pool it drew from already excluded counters same as the standard/expert pool. A reasoning error, not a believable skill gap. Beginner now follows #18's path exactly; #17/#18 fully collapse into one. |
| 18 | Partner following, can't win, standard | same | `ESCAPE` | geometric | NONE | — |
| 19 | ~~Opponent leading, beginner opening~~ | ~~`hand.size()==7`, beginner~~ | ~~`FEEL_OUT_THE_HAND`~~ | ~~mechanical, difficulty-gated only~~ | ~~hardcoded rule~~ | **Removed (July 6, 2026).** Previously logged as "the one true selection-level exception" — that claim didn't hold up. Unconditionally suppressing trump control on trick one regardless of hand strength wasn't a genuine mission difference, it was an unjustified strategy override (same violation class as the also-removed #17). Beginner opponents now evaluate trump control, void-targeting eligibility, and all subsequent leading logic exactly like standard opponents on trick one — the `is_leading` block now starts directly with the expert void-check. |
| 20 | Opponent leading, expert void | `void_suits(opp)` | `FORCE_A_VOID` | geometric, knowledge-gated | KNOWLEDGE | expert-only because lower difficulties can't see the void, not a different mission |
| 21 | Opponent leading, `trumps>=3` | trump count | `CONTROL_TRUMP` | geometric | NONE | duplicate pair with #8 |
| 22 | Opponent leading, strong counter | none (always checked) | `LOCK_IN_COUNTER_LEAD` (new, lead-side) | geometric | NONE | related to `CASH_COUNTERS` (#25) but different geometry (lead vs. follow) |
| 23 | Opponent leading, fallback | none | unnamed default | — | NONE | — |
| 24 | Opponent following, `partner_winning` | `partner_winning` (opponent's own partner) | `PROTECT_PARTNER_WIN` | geometric | NONE | mirrors #11/#12 for the other team |
| 25 | Opponent following, `can_win`, beginner | `can_win` | `SECURE_FOR_PARTNER`-equiv **gated** | **commitment gate** (`value_gate`) | WEIGHT | on failure → falls to `ESCAPE` action; gate input is `trick_pts >= 5` |
| 26 | Opponent following, `can_win`, counter avail | same | `CASH_COUNTERS` | geometric | NONE | — |
| 27 | Opponent following, `can_win`, plain | same | `SECURE_FOR_PARTNER`-equiv, unnamed | geometric | NONE | — |
| 28 | Opponent following, can't win | `!can_win` | `ESCAPE` | geometric | NONE | duplicate pair with #17/#18 |

*(Table renumbered from the in-conversation draft — MARKS branches shifted to
#3–6 to keep contract-level branches grouped first; opponent-following
`partner_winning` is #24, matching its cross-reference to #25/#26/#27.)*

---

## Candidate `AI_MODES` parameters surfaced

| Parameter | Confirmed source branches | Shape |
|---|---|---|
| `trust_threshold` | #16 | commitment gate input (trust in downstream player) |
| `contest_threshold` | #25 | commitment gate input (trick_pts cutoff, currently hardcoded `>=5`) |
| (execution-only, lower priority) | #13 | beginner economy simplification. **#17 removed (July 6, 2026)**, not merely reclassified — see the row above and the "Confirmed duplication pairs" section below. |

Both gate parameters share the same shape (a scalar compared against a
computed signal, gating fallback to `ESCAPE`) — worth designing as one
mechanism with two inputs, not two unrelated parameters, when Phase 3
actually specs `AI_MODES`.

> **Post-BUG-005 correction:** branch #16, the sole confirmed source for
> `trust_threshold`, has been rewritten to use contract margin, live
> counter status, and lead economy — none of which is a trust concept.
> `trust_threshold` currently has **no confirmed source branch**. Whether
> it should still be designed as an `AI_MODES` parameter (and if so, for
> what) is an open question, not a pending-design item — see the
> Phase2Architecture session summary (July 5) for the question as raised.
> Do not resume `trust_threshold` design work by default; resolve the
> question first.

> **Post-Difficulty-Modes-migration correction (July 12, 2026):** the
> question this whole section poses — what should `trust_threshold`/
> `contest_threshold` become as real `AI_MODES` parameters — is now
> answered, differently than either candidate here anticipated. See
> `Spec_Difficulty_Modes_TwoAxis_July12_2026.md`: `AI_MODES` gained
> `vigilance` (`"none"`/`"full"`) and `opportunism` (`0.0`-`1.0`, rolled
> fresh per decision), and every branch below that fed this table is
> affected:
> - **#8** — the difficulty-differentiated high-vs-low trump lead
>   technique described in this row's own correction note is gone.
>   `holds_double_trump` alone is now the complete gate, confirmed
>   identical at every difficulty. (A real, separate correctness gap in
>   this same technique — the low-lead choice doesn't exclude counters —
>   was found during that removal and logged as BUG-010 in
>   `AI_Play_Behavior_Bug_Log.md`; not fixed by the migration.)
> - **#13, #15, #16** — no longer three separate branches. Partner has
>   zero difficulty branching anywhere in `decide_play()` now: the
>   beginner reflexive-win shortcut (#13's shape) and the expert bypass
>   of #16's gate are both removed, leaving one unconditional path that
>   always prefers non-trump winners then always runs #16's margin/
>   counter/lead-economy evaluation. `trust_threshold` (already noted
>   above as having no confirmed source) is even further moot — the
>   branch it might have gated no longer forks by difficulty at all.
> - **#20** — no longer expert-only. Gated on `mode["vigilance"] ==
>   "full"` instead of `difficulty == "expert"`. Behaviorally identical
>   today (only expert sets `vigilance: "full"`), but the form this
>   audit flagged as "correct behavior, imprecise form" (see
>   `Difficulty_Feed_Points_Inventory.md` item #2) is now the precise
>   form.
> - **#25 (`value_gate`)** — retired entirely, not reclassified. Per the
>   fix that replaced it: passing on a cheap trick is the disciplined
>   move, not the distracted one — `contest_threshold`'s hardcoded
>   `trick_pts >= 5` cutoff had the direction backwards. Replaced by
>   `_should_evaluate_tactically()`'s `opportunism` roll, decided fresh
>   per trick rather than by a fixed value cutoff. `contest_threshold`
>   has no successor parameter and none is planned.
>
> The reason_log gap flagged below (#25 lacking its own honest string)
> is moot along with #25 itself — the reflexive path's placeholder
> string ("Taking this one.") is a new, separate entry for the
> strings-pass session, not a fix to the old gap.

---

## Confirmed duplication pairs (candidates for shared logic, not shared file structure)

- `PROTECT_PARTNER_WIN`: #4 (Marks) / #11 / #12 / #24
- `SECURE_FOR_PARTNER`-family: #5 (Marks) / #13 / #14 / #15 / #16
- `ESCAPE`: #6 (Marks) / #18 / #28 (#17 removed July 6, 2026 — fully collapsed into #18, no longer a separate branch)
- `CONTROL_TRUMP`: #8 / #21
- `FORCE_A_VOID`: #20 (opponent leading, expert-only) / 6b (partner leading, all difficulties, added July 6, 2026) — same predicate shape, deliberately different difficulty-gating; see 6b's row for why that asymmetry is by design, not an inconsistency to fix.

None of these are being collapsed by this document — that's Phase 3's job.
This is the map that makes that collapse decision well-informed rather than
speculative.

---

## Open design question carried forward (not resolved by this audit)

**Superseded.** This section described `trust_gate` as it existed before
BUG-005. The rewritten branch #16 has no trust content — the
evaluation-vs-commitment question posed here was about a different piece
of code than the one that currently exists. See
`Texas_42_Session_Summary_July_5_2026_Phase2Architecture.md` for the
question this actually resolves into now: not "does trust belong to
evaluation or commitment" but "does a trust concept belong at this
decision point at all."

## New finding from this pass — reason_log gap (candidate for `AI_Explanation_Bug_Log.md`)

**Superseded (July 12, 2026).** #25 (`value_gate`), the branch this
finding is about, no longer exists — see the Post-Difficulty-Modes-migration
correction note above. Kept as the historical record of the original
observation.

Checking the reason strings to confirm the ESCAPE-reuse distinction above
surfaced a real inconsistency: #16 (`trust_gate`) has its own honest string
("there's still a chance someone else covers"), but #25 (`value_gate`) does
not — its fail path falls into the shared discard block and picks up a
generic string such as *"Can't win this one — discarding low."* That's
inaccurate for this path specifically: the AI *can* win, it's choosing not
to because the trick isn't worth contesting. Unlike #16, this belief state
currently has no distinct string. Flagged here rather than fixed directly,
since reason_log changes go through the existing review process — this is
a candidate line item for the Phase 1 reason-string rewrite, not something
this audit should silently patch.
