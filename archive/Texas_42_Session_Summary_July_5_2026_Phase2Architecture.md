# Texas 42 — Session Summary & Next Session Prep — July 5, 2026 (Phase 2 Architecture)

## What this session covered, in order

1. **Phase 2 conceptual model, built and stress-tested to a locked state.**
   Started from the observation that Phase 2 ("Risk/Trust") had never been
   as tightly defined as Phase 3/4, and worked through several candidate
   models (three-layer intent integrity/selection/modulation, a proposed
   fourth "Knowledge" stage above Selection, topology vs. magnitude as the
   real dividing line) until one survived every branch we ran it against.

2. **Final locked model: three control categories, not four.**
   - **Selection** — geometry (including `PublicKnowledge`-derived
     predicates) → objective. No architectural boundary in the code between
     "ordinary" and "knowledge-gated" objectives — confirmed by checking
     `FORCE_A_VOID`'s actual code, which is a normal Selection-stage
     objective, not a pre-Selection filter.
   - **Commitment** — a selected objective is available but actively
     declined in favor of a safer realization, gated by a scalar. Two real
     instances: `trust_gate` (#16), `value_gate` (#25).
   - **Modulation** — continuous scalars that shift a score inside a fixed
     decision function, never changing which code path executes.
     `risk_bias` and `auction_stance`/`stance_bias` both confirmed here —
     `stance` was the key edge case proving discrete classification ≠
     topology change.
   - A fourth "Knowledge as a pipeline stage" model was proposed, tested
     against the actual code, and explicitly rejected — recorded with a
     **watch condition**: this rejection holds only as long as no
     precomputed candidate/legal-action list exists upstream of objective
     evaluation in `decide_play()`. Re-open if one is ever introduced.
   - Every remaining `AI_MODES` placeholder was sorted against these three
     categories. `opportunism` → Selection (same shape as `FORCE_A_VOID`,
     not built yet). `cooperation_bias` → marked **semantically
     underspecified** rather than resolved — see the update below, this
     status may need revisiting.

3. **Full write-up produced:** `Phase2_Control_Layer_Audit.md` — companion
   to `Phase3_Objective_Audit.md`, includes the rejected-alternative
   reasoning (with watch condition), the three category tables, and the
   Unresolved section (Win Safety, MARKS cardinal-rule override,
   `cooperation_bias`).

4. **A real bug was found through this process, not through code
   inspection alone.** Bottom-up normalization of `trust_gate` and
   `value_gate` into a shared shape exposed that `trust_gate`'s condition
   (`human_play != null and not is_last_player`) can't mean what its own
   reason string claims — a partner who has already acted can't be the
   "someone else" who covers, since partnerships are fixed. Katy walked
   through several real table scenarios (the 5:1/5:0/5:5 example; the
   "do I want the lead" question) that confirmed the branch should be
   evaluating **contract margin, live-counter status, and lead economy**
   instead — none of which is turn-order-based, and none of which requires
   probabilistic modeling.

5. **Logged as `AI_Play_Behavior_Bug_Log_Addendum_PatternD.md` (BUG-005),
   then specced and implemented.** Fix adds two new trailing parameters to
   `decide_play()` (`team_points`, `bid_value`), a new deterministic
   helper (`_live_counter_for_suit` — eliminates a specific counter as a
   threat only when provably out of reach: already played, in our own
   hand, or every remaining actor is known-void in the suit), and replaces
   the standard-difficulty half of branch #16 with a sequential
   margin-then-lead-economy check.

6. **One correction worth remembering:** an early draft of the margin
   formula treated "defending team's target" as requiring separate logic
   from "bidding team's target." Katy's framing ("defenders are still
   chasing a contract, just the inverse one") turned out to be exactly
   right and was confirmed algebraically — a 42-point hand is an exact
   zero-sum partition (25 counter points + 7 trick points = 42, always),
   so `our_target = bid_value if we're the bidding team else (43 -
   bid_value)` is correct as a single symmetric formula, not an
   approximation needing a fix.

7. **Implemented, pushed, and playtest-confirmed working** (Katy, this
   session) — project files now reflect the fix exactly as specced.

---

## Documents produced this session

- `Phase2_Control_Layer_Audit.md` — the locked model (see above).
- `AI_Play_Behavior_Bug_Log_Addendum_PatternD.md` — BUG-005 entry, written
  to match existing bug-log conventions.
- `BUG-005_Fix_Spec.md` — the implemented spec, including a 5-item
  verification checklist.

---

## Housekeeping — do these before anything else next session

- **Merge `AI_Play_Behavior_Bug_Log_Addendum_PatternD.md` into
  `AI_Play_Behavior_Bug_Log.md` proper** — it's currently a standalone
  addendum. Update BUG-005's status marker once merged: it was logged as
  ⚑ (needs more examples before speccing), but it's now implemented and
  playtest-confirmed — likely → or ✓ depending on how much of the
  verification checklist gets run first (see below).
- **Run the remaining verification checklist items** from
  `BUG-005_Fix_Spec.md`. Katy's playtest confirmed the fix is active and
  behaving sensibly, but the checklist has 5 specific scenarios and it's
  not yet confirmed which were actually exercised — particularly #2
  (defending-side margin with real numbers), #3 (lead economy actually
  changing the outcome, not just the reason string), and #4 (no-safe-
  discard forced-commit fallback still works).
- `Texas_42_Documentation_Map.md` should get a new Tier-1-adjacent entry
  for `Phase2_Control_Layer_Audit.md`, alongside the existing
  `Phase3_Objective_Audit.md` entry — not done yet, purely a lookup-table
  update.

---

## New open question surfaced by the BUG-005 fix (worth resolving before other Phase 2 work)

The corrected branch #16 has **no trust content at all** — it's contract
margin, a deterministic counter check, and lead economy. This changes the
status of the still-open `cooperation_bias` → `trust_threshold` question
from `Phase2_Control_Layer_Audit.md`: that question was "does Expert's
'no trust rule' mean better judgment or reduced trust," framed as a
Commitment-layer personality axis. But if the thing standard difficulty is
actually doing at this decision point isn't trust-based at all, it's worth
asking directly: **does `trust_threshold` still make sense as a concept
here, or was the entire premise — that this decision point needs a
"how much do I trust my partner" dial — built on the same misreading that
caused BUG-005 in the first place?** Worth discussing before doing any
further design work on that parameter, rather than carrying the old framing
forward by default.

---

## Next steps, not yet prioritized against each other — pick a direction

1. **Resolve the `cooperation_bias`/trust question above.** Possibly quick,
   possibly reshapes what's left of the Commitment-layer parameter design.
2. **Apply `_live_counter_for_suit` to `value_gate` (#25).** Flagged as a
   deliberate follow-up, not bundled into this session's fix since it's a
   different objective (`CASH_COUNTERS`/contest vs. `SECURE_FOR_PARTNER`).
   Now that the helper exists and is playtest-confirmed once, this is
   likely a smaller lift than #16 was.
3. **Formalize (or decide not to formalize) a shared shape for Commitment
   gates.** `trust_gate` and `value_gate` are still two independently
   coded branches, not a shared mechanism — the original `Phase3_Objective_
   Audit.md` proposal to design `trust_threshold`/`contest_threshold` as
   "one mechanism, two inputs" hasn't been acted on. Worth a decision on
   whether that's still worth doing structurally, or whether two
   well-understood independent branches are fine to leave as-is.
4. **`opportunism`.** Confirmed to belong in Selection, same shape as
   `FORCE_A_VOID`, but no behavior spec exists — this is a "what should it
   actually detect" design conversation, not a wiring one.
5. **Switch to Phase 1 (Cooperation).** Per the original plan from earlier
   this session (work backward: 4 → 3 → 2 → 1, since 4 and 3 were already
   tightly defined and 2 was fuzzy). Now that Phase 2 has a locked model,
   this was the original next stop. The cardinal rule's MARKS-override
   question (still parked pending example hands) would live here.

No recommendation on ordering — all five are reasonable starting points
and none blocks the others except #1, which is small and probably worth
clearing first regardless of which direction is chosen after.
