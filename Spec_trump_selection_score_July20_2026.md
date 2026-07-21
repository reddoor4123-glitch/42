# Spec: `trump_selection_score()` and `calculate_trump_control_value()`

**Status:** ✓ Implemented and validated, July 20, 2026. See `AI_Bid_Behavior_Bug_Log.md`, Pattern D, and `scripts/job6_results.json` for the validation run.

**File:** `ai_player.gd`

**Related:** `AI_Play_Behavior_Bug_Log.md` (Finding #4, off-suit doubles), `Texas_42_Bidding_System_Overview_and_Open_Items_July13_2026.md` (§4)

---

## 1. Problem being fixed

`best_trump()` (`ai_player.gd:192-203` at spec time) currently answers "which trump should I declare" by running `evaluate_hand()` once per candidate suit and taking the argmax of `estimated_points + trump_count*2.0 + (has_double_trump ? 3.0 : 0.0)`. `evaluate_hand()` was built and benchmarked to answer a different question — "given trump is already fixed, how good is this hand" — and one of its terms is not stable under the question `best_trump()` is actually asking.

Specifically: the off-suit-doubles compounding bonus (`ai_player.gd:123-144`) is keyed to how many doubles remain off-suit under this specific candidate, not to the hand's actual double count. Promoting any double to trump shrinks that count by one, costing a flat tier-loss (worth up to 0.7, i.e. 4.2 points of `estimated_points`) regardless of which double was promoted or how strong the resulting trump suit is. Compared across 7 candidates for the same hand, this systematically favors whichever suit happens to leave the most doubles off-suit — not the strongest declarer choice.

Evidence: two independently-found real hands reproduce this exact mechanism (July 20, 2026 flagged hand; the `1:3,0:6,0:3,6:6,1:1,4:4,3:3` hand from the Job 5 classification run). A grid search over the existing flat structural bonus (`trump_count` weight, `has_double_trump` bonus) across a wide range (2.0-8.0 / 3.0-15.0) could not fix the known regression without breaking a different, previously-correct hand — ruling out "the constants are too small" as the explanation. The fix has to live in the off-suit-doubles term itself, not in the flat bonuses layered on top of it.

Separately noted, not addressed here: `decide_bid()`'s `control_score` (`ai_player.gd:247-259` at spec time) already scores trump structure with a tiered curve, independently of and inconsistent with `best_trump()`'s flat terms. That duplication is fixed by §3 below (shared primitive), not by inventing a third formula.

## 2. Scope — what does NOT change

- `evaluate_hand()` is untouched. It remains the sole answer to "given trump is fixed, how good is this hand" and continues to feed `decide_bid()`'s EV estimate exactly as it does today. Do not modify its off-suit-doubles logic, its trump-tile scoring, or `realization_bias`.
- `realization_bias` is not touched anywhere in this spec. One of the three known disagreement hands (`realization_shift` tag) may trace to it, but that hasn't been isolated or diagnosed — out of scope here, flagged for future investigation.
- This spec does not change `decide_bid()`'s own go/no-go logic or its use of `best_trump()`'s output for bid sizing. That's a separate open question (should bid strength reflect what would actually be declared) — not addressed in this pass.

## 3. New primitive: `calculate_trump_control_value()`

Extracted from `decide_bid()`'s existing `control_score` tiers verbatim — no new constants, just named and shared so `best_trump()`/`trump_selection_score()` and `decide_bid()` stop disagreeing about what trump structure is worth.

```gdscript
# Shared structural-strength primitive: how much does holding this many
# trump tiles, including or excluding the trump double, matter — used
# identically by trump_selection_score() and decide_bid()'s control_score.
# Values match the pre-existing control_score tiers exactly; this is an
# extraction, not a retune.
static func calculate_trump_control_value(trump_count: int, has_double_trump: bool) -> float:
	var value := 0.0
	if has_double_trump:
		value += 2.5
	if trump_count >= 4:
		value += 1.5
	if trump_count >= 5:
		value += 3.0
	if trump_count >= 6:
		value += 2.0
	return value
```

**Call site update — `decide_bid()`'s `control_score`:** replace its inline tier logic with a call to `calculate_trump_control_value(trump_count, has_double_trump)`. This is a pure refactor at that call site — output must be numerically identical to current behavior. Verify with a smoke test comparing `control_score` output before/after on a handful of hands.

**Second call site — do not miss this one.** The same tier logic is independently duplicated inside `decide_bid()`'s verbose debug-print block (`control_score_log`), used only for console output — it is not a field persisted in the `bid_decisions`/`eval` dict structure that the headless harness reads, so this isn't a live-play risk, but leaving it unrefactored means the debug print silently drifts out of sync with the real decision logic the next time either tier value changes, which is the same category of problem this whole spec exists to fix, just relocated to a debug path instead of a gameplay path. Replace the inline tiers there with the same `calculate_trump_control_value(...)` call.

## 4. New function: `trump_selection_score()`

```gdscript
# Answers "which trump would I choose to declare" — NOT "how good is this
# hand" (that's evaluate_hand()'s job). Reuses evaluate_hand()'s trump-tile
# and off-suit-non-double scoring unchanged, but recomputes the off-suit-
# doubles compounding bonus on the hand's FIXED total double count instead
# of the count remaining off-suit under this specific candidate — the
# compounding bonus should reward "this hand is doubles-rich," not "this
# particular candidate happens to leave more doubles off-suit than that one."
static func trump_selection_score(hand: Array[Domino], trump: int) -> Dictionary:
	var eval = evaluate_hand(hand, trump)

	# Total doubles in the hand — invariant across all 7 candidate suits.
	var total_doubles := 0
	for d in hand:
		if d.is_double():
			total_doubles += 1

	# Doubles left off-suit under THIS candidate (what evaluate_hand()
	# already computed its tier bonus from).
	var off_suit_doubles := 0
	for d in hand:
		if d.is_double() and not d.is_trump(trump):
			off_suit_doubles += 1

	var corrected_points = eval["estimated_points"] \
		+ 6.0 * (_doubles_tier(total_doubles) - _doubles_tier(off_suit_doubles))

	var control_value = calculate_trump_control_value(
		eval["trump_count"], eval.get("has_double_trump", false)
	)

	var result = eval.duplicate()
	result["corrected_estimated_points"] = corrected_points
	result["control_value"] = control_value
	result["selection_score"] = corrected_points + control_value
	return result

# Cumulative off-suit-doubles compounding bonus for n doubles, matching the
# tier shape already in evaluate_hand(): the 1st off-suit double earns no
# bonus, then +0.3 / +0.5 / +0.7 for the 2nd/3rd/4th.
# NOTE: evaluate_hand()'s match statement only defines tiers for i=1,2,3
# (i.e. up to 4 doubles total). This hits the same ceiling — 5+ doubles in
# one hand is rare but not impossible; flatten at the 4-double value rather
# than extrapolating an untested curve. If this ceiling is hit often in
# practice, that's a sign evaluate_hand()'s own tier definition needs
# extending first, in its own pass — not silently guessed at here.
static func _doubles_tier(n: int) -> float:
	var capped = min(n, 4)
	match capped:
		0, 1: return 0.0
		2: return 0.3
		3: return 0.8
		4: return 1.5
	return 1.5
```

## 5. `best_trump()` — updated to select via the new score

**Correction (caught before implementation, verified against source):** an earlier draft of this spec incorrectly claimed `best_trump()` returns a bare `int` and that its signature was unchanged. It does not — confirmed at `ai_player.gd:192`, `best_trump()` is declared `-> Dictionary` today, and returns the winning suit's full `evaluate_hand()` result dict (not just the suit index). Two real gameplay call sites depend on this, not just internal/test code: `game_table.gd` (AI Splash/Plunge partner declaring trump, and AI bid winner declaring trump) both read `ai_eval["trump"]` off the return value to actually announce and apply the chosen suit. `decide_bid()` also consumes the dict. Changing the return type to `int` would compile but crash at runtime the first time an AI won a bid in live play — not caught by a narrow unit test of `best_trump()`'s chosen suit alone.

Corrected implementation — keep the `Dictionary` contract:

```gdscript
static func best_trump(hand: Array[Domino]) -> Dictionary:
	var best_result := {}
	var best_score := -INF
	for suit in range(7):
		var result = trump_selection_score(hand, suit)
		if result["selection_score"] > best_score:
			best_score = result["selection_score"]
			best_result = result
	return best_result
```

This works cleanly with no further changes needed at any call site, because `trump_selection_score()`'s result is `eval.duplicate()` plus new fields — it already carries `"trump"`, `"estimated_points"`, `"trump_count"`, and `"has_double_trump"` untouched from the original `evaluate_hand()` call. This also automatically satisfies §2's scope boundary: `decide_bid()`'s existing read of `eval["estimated_points"]` still sees the original uncorrected value, not `corrected_estimated_points` or `selection_score`, since `duplicate()` never overwrites an existing key with a new one of a different name.

`best_trump()`'s three call sites require no changes — they already read `result["trump"]` / `eval["estimated_points"]` etc. off a dict, which is exactly what they'll keep getting.

## 6. Validation — done before merging

**6a. Exact-match regression test.** For the hand `[6:6, 3:4, 1:6, 4:4, 0:5, 2:2, 3:3]` (the July 20 flagged hand) and `[1:3, 0:6, 0:3, 6:6, 1:1, 4:4, 3:3]` (the Job 5 clean regression hand): confirm `best_trump()`'s returned `result["trump"]` is `3` for both, not `0`. **✓ Passed.**

**6b. No-regression check on the 37 previously-correct hands.** Corrected formula: 38/40 correct vs. 37/40 for the current formula, zero regressions, one fix (the hand in 6a). Confirmed live in GDScript via `scripts/job6_trump_selection_score_validation.gd`, reusing the 40 hands already generated by the Job 5 classification harness (`scripts/job5_results.json`) rather than re-running the ~9-minute Monte Carlo simulation. **✓ Passed** — exactly one hand flips, and it's the expected one.

**6c. `control_score` refactor smoke test.** Confirm `calculate_trump_control_value()`'s output matches the current inline `control_score` tier logic exactly on hands with varying trump_count (0, 3, 4, 5, 6) and both `has_double_trump` states, at both call sites (the real one and the debug-print duplicate). **✓ Passed.**

**6d. Known-unfixed cases.** The `realization_shift` hand (chosen=5→actual best=4) and the `no_clear_pattern` hand (chosen=1→actual best=5) from Job 5 are expected to remain disagreements after this change. **✓ Confirmed still open** — neither flipped.

## Experimental instrumentation

Per an explicit request to treat this as an experiment rather than final architecture: `trump_selection_score()`'s result also carries `legacy_selection_score` (the old flat formula), computed alongside the corrected `selection_score` purely for side-by-side comparison. `best_trump()` selects on `selection_score` only — `legacy_selection_score` is never used for any decision. This lets old-vs-new be compared without a mode-switching debug flag (and the risk of it being left in the wrong position). Tracked for removal in `Backlog_Triage_Combined_July15_2026.md` (Quality bucket) once the fix has baked in playtesting.
