extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# bid_filter_trace.gd
#
# Acceptance-criteria harness for the Announced-Bid Filter spec
# (Two-Tier Margin + Shaker Minimum, July 20 2026, ai_player.gd).
# Calls decide_bid() directly — no trick-play harness needed, since
# this spec only touches Layer 3 execution inside decide_bid().
#
# Layer 2's target_bid is a nonlinear function of hand shape (est_pts,
# risk_bias, stance_bias) that isn't worth hand-deriving. Instead this
# probes a spread of candidate hands at "standard" difficulty against
# current_high = null, buckets them by their actual (points-type)
# target_bid, and picks real hands out of those buckets for the
# assertions below — same probe-then-verify method as
# job2_hand_eval_probe.gd / job3_find_bidworthy_hand.gd. Buckets:
#   MARGINAL:    target_bid <= 31          (marginal at min_points=30)
#   STRONG:      32 <= target_bid <= 33    (strong at min_points=30,
#                                            still marginal at min_points=32)
#   VERY_STRONG: target_bid >= 34          (strong at both min_points levels)
# decide_bid() is fully deterministic (confirmed: no randf()/randi() in
# the function or anything it calls except _should_evaluate_tactically(),
# which only play decisions use) — a fixed hand always produces the
# same target_bid, so this probe needs exactly one pass, no repeated
# trials.
#
# Run:
#   "$GODOT" --headless --path . --script res://bid_filter_trace.gd
# ═══════════════════════════════════════════════════════════════════

const BidScript = preload("res://bid.gd")
const DIFFICULTY := "standard"

var trace_lines: Array = []
var failures: Array = []

func _log(s: String):
	trace_lines.append(s)
	print(s)

func _hand_from_pairs(pairs: Array) -> Array[Domino]:
	var h: Array[Domino] = []
	for p in pairs:
		h.append(Domino.new(p[0], p[1]))
	return h

func _check(label: String, condition: bool, detail: String) -> void:
	if condition:
		_log("  PASS: %s — %s" % [label, detail])
	else:
		_log("  FAIL: %s — %s" % [label, detail])
		failures.append(label)

# ── Probe candidates — spread of trump concentration/quality. None of
# these accidentally trigger the marks-bid gate (trump_count >= 5 AND
# has_double_trump AND (off_suit_has_double OR trump_count >= 6)) —
# every double-trump candidate here is kept at trump_count <= 4
# specifically to stay on the points path being tested.
func _candidate_hands() -> Array:
	return [
		{"name": "weak_spread",              "hand": [[0,1],[0,2],[1,3],[2,4],[3,5],[4,5],[1,4]]},
		{"name": "trump2",                   "hand": [[0,6],[1,6],[0,1],[0,2],[1,2],[2,3],[3,4]]},
		{"name": "trump3",                   "hand": [[0,6],[1,6],[2,6],[0,1],[0,2],[1,2],[2,3]]},
		{"name": "trump4",                   "hand": [[1,6],[2,6],[3,6],[4,6],[0,1],[0,2],[1,2]]},
		{"name": "trump5_dbl_weak_off",       "hand": [[2,6],[3,6],[4,6],[5,6],[6,6],[0,1],[0,2]]},
		{"name": "trump4_dbl_1_off_dbl",       "hand": [[6,6],[4,6],[3,6],[0,0],[1,1],[2,3],[4,5]]},
		{"name": "trump4_dbl_3_off_dbl",       "hand": [[6,6],[4,6],[3,6],[2,6],[0,0],[1,1],[5,5]]},
		{"name": "trump4_dbl_3_off_dbl_top",   "hand": [[6,6],[5,6],[4,6],[3,6],[0,0],[1,1],[2,2]]},
		{"name": "trump3_dbl_1_off_dbl",       "hand": [[6,6],[5,6],[1,6],[0,0],[2,3],[3,4],[4,5]]},
		{"name": "trump2_dbl_weak",             "hand": [[6,6],[4,6],[0,1],[0,2],[1,3],[2,4],[3,5]]},
		# Added to fill the 32-33 gap between trump4_dbl_1_off_dbl (target=30)
		# and trump4_dbl_3_off_dbl (target=34) — the first pass's probe sweep
		# jumped straight over the STRONG bucket.
		{"name": "trump4real_dbl_1_off_dbl",   "hand": [[6,6],[4,6],[3,6],[2,6],[0,0],[2,3],[4,5]]},
		{"name": "trump4real_dbl_2_off_dbl",   "hand": [[6,6],[4,6],[3,6],[2,6],[0,0],[1,1],[2,3]]},
		{"name": "trump3_dbl_2_off_dbl",       "hand": [[6,6],[4,6],[3,6],[0,0],[1,1],[2,3],[4,5]]},
		# Second pass — off-suit doubles compound in value by PIP as well as
		# count (evaluate_hand()'s off-suit-doubles scoring: win_prob scales
		# with pip, plus a compounding bonus per additional double). Pairing
		# a low double with a high one should land between the 1-double and
		# 3-double results above without adding a third double.
		{"name": "trump4real_dbl_0033",        "hand": [[6,6],[4,6],[3,6],[2,6],[0,0],[3,3],[2,5]]},
		{"name": "trump4real_dbl_0044",        "hand": [[6,6],[4,6],[3,6],[2,6],[0,0],[4,4],[2,5]]},
		{"name": "trump4real_dbl_0055",        "hand": [[6,6],[4,6],[3,6],[2,6],[0,0],[5,5],[2,3]]},
	]

func _probe(name: String, pairs: Array) -> Dictionary:
	var hand = _hand_from_pairs(pairs)
	var bid_decisions: Array = []
	var result = AIPlayer.decide_bid(hand, 0, null, GameSettings.new(), false, DIFFICULTY, bid_decisions, -1)
	var target_bid = bid_decisions[0]["target_bid"] if bid_decisions.size() > 0 else -1
	var should_bid = bid_decisions[0]["should_bid"] if bid_decisions.size() > 0 else false
	var type_str = "PASS"
	if result.type == BidScript.Type.POINTS:
		type_str = "POINTS(%d)" % result.value
	elif result.type == BidScript.Type.MARKS:
		type_str = "MARKS(%d)" % result.value
	_log("  probe %-24s should_bid=%-5s target_bid=%-4d result=%s" % [name, should_bid, target_bid, type_str])
	return {"name": name, "pairs": pairs, "should_bid": should_bid, "target_bid": target_bid, "is_points": result.type == BidScript.Type.POINTS}

func _init():
	trace_lines.clear()
	failures.clear()

	_log("═══════════════════════════════════════════════════════════")
	_log("PROBE SWEEP (current_high=null, min_points=30, standard difficulty)")
	_log("═══════════════════════════════════════════════════════════")

	var probes: Array = []
	for c in _candidate_hands():
		probes.append(_probe(c["name"], c["hand"]))

	var marginal = probes.filter(func(p): return p["is_points"] and p["target_bid"] <= 31)
	# Single STRONG bucket (target_bid >= 32) instead of two disjoint
	# STRONG(32-33)/VERY_STRONG(>=34) buckets — case 2 only needs
	# target_bid > 31 and case 4b only needs target_bid > 33; the spec
	# never requires those to come from different hands, and a hand with
	# target_bid >= 34 already satisfies both. Splitting them was a
	# self-imposed constraint the probe sweep struggled to fill (off-suit
	# doubles compound in big discrete jumps — see evaluate_hand()'s
	# compounding bonus — so 32/33 specifically is a narrow needle).
	var strong = probes.filter(func(p): return p["is_points"] and p["target_bid"] >= 32)

	_log("")
	_log("Bucket sizes — MARGINAL(<=31): %d   STRONG(>=32): %d" % [marginal.size(), strong.size()])

	if marginal.is_empty() or strong.is_empty():
		_log("")
		_log("!!! One or more buckets came up empty — acceptance criteria below that")
		_log("!!! depend on it will be SKIPPED, not silently passed. Add more probe")
		_log("!!! candidates to _candidate_hands() and rerun.")

	var hand_marginal = marginal[0] if marginal.size() > 0 else null
	# Prefer a STRONG candidate whose target_bid is also > 33, so the same
	# hand can serve case 2 (needs > 31) and case 4b (needs > 33) at once.
	var strong_over_33 = strong.filter(func(p): return p["target_bid"] > 33)
	var hand_strong = strong_over_33[0] if strong_over_33.size() > 0 else (strong[0] if strong.size() > 0 else null)
	var hand_very_strong = hand_strong

	var settings = GameSettings.new()

	# ── Case 1: marginal open, not shaker ────────────────────────────
	_log("")
	_log("═══════════════════════════════════════════════════════════")
	_log("CASE 1 — marginal open, not shaker (min_points=30)")
	_log("═══════════════════════════════════════════════════════════")
	if hand_marginal != null:
		_log("  using hand: %s (target_bid=%d)" % [hand_marginal["name"], hand_marginal["target_bid"]])
		var hand = _hand_from_pairs(hand_marginal["pairs"])
		var bd: Array = []
		var result = AIPlayer.decide_bid(hand, 0, null, settings, false, DIFFICULTY, bd, -1)
		_check("case1_final_bid_30", result.type == BidScript.Type.POINTS and result.value == 30,
			"expected POINTS(30), got %s" % result.debug_string())
	else:
		_log("  SKIPPED — no MARGINAL candidate found")

	# ── Case 2: strong open, not shaker ───────────────────────────────
	_log("")
	_log("═══════════════════════════════════════════════════════════")
	_log("CASE 2 — strong open, not shaker (min_points=30)")
	_log("═══════════════════════════════════════════════════════════")
	if hand_strong != null:
		_log("  using hand: %s (target_bid=%d)" % [hand_strong["name"], hand_strong["target_bid"]])
		var hand = _hand_from_pairs(hand_strong["pairs"])
		var bd: Array = []
		var result = AIPlayer.decide_bid(hand, 0, null, settings, false, DIFFICULTY, bd, -1)
		_check("case2_final_bid_31_not_target", result.type == BidScript.Type.POINTS and result.value == 31,
			"expected POINTS(31) — ceiling withheld from target_bid=%d — got %s" % [hand_strong["target_bid"], result.debug_string()])
	else:
		_log("  SKIPPED — no STRONG candidate found")

	# ── Case 3: shaker with a strong hand — override takes precedence ─
	_log("")
	_log("═══════════════════════════════════════════════════════════")
	_log("CASE 3 — shaker with the same strong hand as case 2 (min_points=30)")
	_log("═══════════════════════════════════════════════════════════")
	if hand_strong != null:
		_log("  using hand: %s (target_bid=%d), player_id == shaker == 0" % [hand_strong["name"], hand_strong["target_bid"]])
		var hand = _hand_from_pairs(hand_strong["pairs"])
		var bd: Array = []
		var result = AIPlayer.decide_bid(hand, 0, null, settings, false, DIFFICULTY, bd, 0)  # shaker == player_id
		_check("case3_shaker_overrides_to_min_points", result.type == BidScript.Type.POINTS and result.value == 30,
			"expected POINTS(30) — shaker override takes precedence over two-tier filter — got %s" % result.debug_string())
	else:
		_log("  SKIPPED — no STRONG candidate found")

	# ── Case 4: mid-auction raise, not shaker (current_high = 31 pts) ─
	_log("")
	_log("═══════════════════════════════════════════════════════════")
	_log("CASE 4 — mid-auction raise, not shaker (current_high=31, min_points=32)")
	_log("═══════════════════════════════════════════════════════════")
	var raise_high = BidScript.new(BidScript.Type.POINTS, 31, 1)  # someone else bid 31
	if hand_marginal != null:
		_log("  4a (target <= 33): using hand %s (raw target_bid=%d)" % [hand_marginal["name"], hand_marginal["target_bid"]])
		var hand = _hand_from_pairs(hand_marginal["pairs"])
		var bd: Array = []
		var result = AIPlayer.decide_bid(hand, 0, raise_high, settings, false, DIFFICULTY, bd, -1)
		_check("case4a_final_bid_32", result.type == BidScript.Type.POINTS and result.value == 32,
			"expected POINTS(32), got %s" % result.debug_string())
	else:
		_log("  4a SKIPPED — no MARGINAL candidate found")

	if hand_very_strong != null:
		_log("  4b (target > 33): using hand %s (target_bid=%d)" % [hand_very_strong["name"], hand_very_strong["target_bid"]])
		var hand2 = _hand_from_pairs(hand_very_strong["pairs"])
		var bd2: Array = []
		var result2 = AIPlayer.decide_bid(hand2, 0, raise_high, settings, false, DIFFICULTY, bd2, -1)
		_check("case4b_final_bid_33", result2.type == BidScript.Type.POINTS and result2.value == 33,
			"expected POINTS(33) — ceiling withheld from target_bid=%d — got %s" % [hand_very_strong["target_bid"], result2.debug_string()])
	else:
		_log("  4b SKIPPED — no VERY_STRONG candidate found")

	# ── Forced-bid sanity check ────────────────────────────────────────
	_log("")
	_log("═══════════════════════════════════════════════════════════")
	_log("FORCED BID — is_forced=true, weak hand, current_high=null (min_points=30)")
	_log("═══════════════════════════════════════════════════════════")
	_log("  current_high=null guarantees points_still_legal stays true, so this")
	_log("  scenario cannot reach the separate forced-fallback block by")
	_log("  construction — a POINTS(30) result here is necessarily routed")
	_log("  through _announced_points_bid(), not the fallback.")
	var weak_pairs = _candidate_hands()[0]["hand"]  # "weak_spread"
	var weak_hand = _hand_from_pairs(weak_pairs)
	var bd_forced: Array = []
	var forced_result = AIPlayer.decide_bid(weak_hand, 0, null, settings, true, DIFFICULTY, bd_forced, -1)
	_check("forced_bid_sane_minimum", forced_result.type == BidScript.Type.POINTS and forced_result.value == 30,
		"expected POINTS(30), got %s" % forced_result.debug_string())

	# ── Case 5: safety clamp with synthetic max_overbid — direct call ─
	_log("")
	_log("═══════════════════════════════════════════════════════════")
	_log("CASE 5 — safety clamp, synthetic max_overbid=0 (not reachable via any")
	_log("real AI_MODES preset today) — calling _announced_points_bid() directly")
	_log("═══════════════════════════════════════════════════════════")
	var clamped = AIPlayer._announced_points_bid(40, 30, 0, -1, 0)  # good hand, not shaker, max_overbid=0
	_check("case5_safety_clamp_engages", clamped == 30,
		"expected 30 (clamped down from the two-tier filter's min_points+1=31 by max_overbid=0), got %d" % clamped)
	var unclamped = AIPlayer._announced_points_bid(40, 30, 0, -1, 4)  # sanity: normal max_overbid doesn't clamp
	_check("case5_control_normal_max_overbid_unaffected", unclamped == 31,
		"expected 31 (max_overbid=4 doesn't interfere), got %d" % unclamped)

	_log("")
	_log("═══════════════════════════════════════════════════════════")
	if failures.is_empty():
		_log("ALL CHECKS PASSED")
	else:
		_log("FAILURES: %s" % [failures])
	_log("═══════════════════════════════════════════════════════════")

	var out = {
		"failures": failures,
		"probes": probes,
		"buckets": {
			"marginal_count": marginal.size(),
			"strong_count": strong.size(),
			"strong_over_33_count": strong_over_33.size(),
		},
		"full_log": trace_lines,
	}
	var f = FileAccess.open("res://bid_filter_trace_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()

	print("")
	print("Results written to res://bid_filter_trace_results.json")
	quit(0 if failures.is_empty() else 1)
