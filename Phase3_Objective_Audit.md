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
│   fully bypassed (SEVENS, NELLO) or a bare difficulty branch with
│   no geometric input (FEEL_OUT_THE_HAND)
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

Confirmed **not** part of the objective system: `FEEL_OUT_THE_HAND`. No
geometric input, difficulty-gated only — correctly left as a direct branch
per the project's own "Neither" category.

---

## Full branch table

| # | Branch | Geometry | Objective | Type | Difficulty | Notes |
|---|---|---|---|---|---|---|
| 1 | SEVENS (early return) | none | none | mechanical override | NONE | bypasses `decide_play()` entirely |
| 2 | NELLO (early return) | none (role-keyed) | none | mechanical override | NONE | bypasses `decide_play()` entirely |
| 3 | MARKS/PLUNGE/SPLASH, leading | `is_leading` | `CONTROL_TRUMP`-adjacent, unconditional | constrained | NONE | stricter than standard `CONTROL_TRUMP` (no trump-count threshold) |
| 4 | MARKS, partner-winning | `partner_winning` | `PROTECT_PARTNER_WIN` | constrained | NONE (flagged open Q) | **duplicate of #11** — reimplemented, not shared |
| 5 | MARKS, can-win | `can_win` | `SECURE_FOR_PARTNER` | constrained | NONE | economy/trust stripped — arguably correct for Marks |
| 6 | MARKS, can't win | `!can_win` | `ESCAPE` | constrained | NONE | no pip filtering (correct — counters irrelevant under Marks) |
| 7 | Partner leading, `off_safe` | `is_leading`, `is_partner` | `OPEN_SAFE_SUIT` | geometric | NONE | — |
| 8 | Partner leading, `trumps>=3` (with double) or `trumps>=4` | same | `CONTROL_TRUMP` | geometric | NONE | **BUG-003/003b fixed (July 5, 2026)**: now evaluated before #7 (`OPEN_SAFE_SUIT`), double-aware threshold (3+ with the double, 4+ otherwise). No longer unreachable. |
| 9 | Partner leading, `non_counters_lead` | same | `PROTECT_COUNTERS_WHILE_LEADING` | geometric | NONE | fallback tier |
| 10 | Partner leading, final fallback | same | `PROTECT_COUNTERS_WHILE_LEADING` (degraded) | geometric | NONE | last resort |
| 11 | Partner following, `human_is_winning` + double | `partner_winning`, winner is double | `PROTECT_PARTNER_WIN` | geometric | NONE | dump-counters variant |
| 12 | Partner following, `human_is_winning`, no double | same | `PROTECT_PARTNER_WIN` | geometric | NONE | duplicate pair with #4 |
| 13 | Partner following, `can_win`, beginner | `can_win`, `!partner_winning` | `SECURE_FOR_PARTNER` | geometric | WEIGHT | skips economy |
| 14 | Partner following, `can_win`, non-trump avail | same | `SECURE_FOR_PARTNER` | geometric | NONE (all difficulties) | prefer non-trump winner |
| 15 | Partner following, trump-only, expert | same | `SECURE_FOR_PARTNER` | geometric | WEIGHT | commits, no gate |
| 16 | Partner following, trump-only can-win, standard difficulty | `can_win` (trump only), `bid_value`/`team_points` state | `SECURE_FOR_PARTNER` | commitment gate | STANDARD only | **Rewritten under BUG-005 (implemented, playtest-confirmed).** Gate input is now contract margin (symmetric zero-sum reachability check) → live counter status (`_live_counter_for_suit()`, deterministic — rules out a counter only when provably unreachable) → lead economy. No turn-order check remains. See Patch note below — this branch no longer has any trust content. |
| 17 | Partner following, can't win, beginner | `!can_win` | `ESCAPE` | geometric | WEIGHT | protect-highest-first variant |
| 18 | Partner following, can't win, standard | same | `ESCAPE` | geometric | NONE | — |
| 19 | Opponent leading, beginner opening | `hand.size()==7`, beginner | `FEEL_OUT_THE_HAND` | **mechanical, difficulty-gated only** | hardcoded rule | confirmed: the one true selection-level exception |
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
| (execution-only, lower priority) | #13, #17 | beginner economy/protection simplification — likely folds into a single "caution" style parameter rather than needing its own name |

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

---

## Confirmed duplication pairs (candidates for shared logic, not shared file structure)

- `PROTECT_PARTNER_WIN`: #4 (Marks) / #11 / #12 / #24
- `SECURE_FOR_PARTNER`-family: #5 (Marks) / #13 / #14 / #15 / #16
- `ESCAPE`: #6 (Marks) / #17 / #18 / #28
- `CONTROL_TRUMP`: #8 / #21

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
