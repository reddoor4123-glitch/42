extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# trump_control_trace.gd
#
# Purpose: exercise BOTH trump-leading code paths in ai_player.gd's
# decide_play() with fully deterministic hands, and log the exact gate
# values at the moment of each leading decision — not just the final
# chosen tile. Built to test the hypothesis from the July 20 2026
# session: Partner-side CONTROL_TRUMP (ai_player.gd ~587-651, gated by
# `if is_partner:`) and Opponent-side trump leading (ai_player.gd
# ~995-1005, the `trumps.size() >= 3` branch) are two DIFFERENT
# implementations with different stopping conditions, and this may
# explain "the AI doesn't call in trumps" reports.
#
# Follows Headless_Harness_Reference.md conventions:
#   - DIFFICULTY = "expert" for full determinism (opportunism=1.0, no roll)
#   - is_partner computed explicitly per seat (Gotcha #1)
#   - turn order is (current_player + 3) % 4 (Gotcha #2)
#   - record_trick() passed current_trick.plays, not [] (Gotcha #3)
#   - results written to a JSON file, not parsed from stdout (Gotcha #4)
#
# Run:
#   "$GODOT" --headless --path . --script res://trump_control_trace.gd > /dev/null 2>/tmp/stderr.txt
#   cat /tmp/stderr.txt   (should be empty)
#   then read res://trump_control_trace_results.json
#
# This script does NOT modify any live game file — read-only
# instrumentation on top of existing Game/AIPlayer/PublicKnowledge APIs.
# ═══════════════════════════════════════════════════════════════════

const BidScript = preload("res://bid.gd")
const DIFFICULTY := "expert"
const TRUMP_SUIT := 6          # numeric trump suit; top tiles are 6:6, 5:6, 4:6
const BID_VALUE := 30
const BIDDER_SEAT := 0
const PARTNER_SEAT := 2        # (BIDDER_SEAT + 2) % 4 — the ONLY seat that ever
                                # runs is_partner == true in this harness

var trace_lines: Array = []    # human-readable, printed to log
var trace_records: Array = []  # structured, written to JSON

func _log(s: String):
	trace_lines.append(s)
	print(s)

# ── Hand construction ──────────────────────────────────────────────

func _hand_from_pairs(pairs: Array) -> Array[Domino]:
	var h: Array[Domino] = []
	for p in pairs:
		h.append(Domino.new(p[0], p[1]))
	return h

func _validate_full_deck(all_hands: Array) -> void:
	# Sanity check: exactly 28 distinct tiles across all four hands.
	var seen := {}
	var count := 0
	for hand in all_hands:
		for d in hand:
			var key = "%d:%d" % [d.left, d.right]
			if seen.has(key):
				push_error("DUPLICATE TILE IN HAND SETUP: %s" % key)
			seen[key] = true
			count += 1
	if count != 28:
		push_error("Hand setup does not total 28 tiles (got %d)" % count)

# ── Scenario A — Partner control (P2 holds top 3 trump, on lead) ────
# P0: 0:1 0:2 0:3 0:4 0:5 0:6 1:6
# P1: 1:2 1:3 1:4 1:5 2:3 2:4 3:6      (opponent, holds 1 trump)
# P2: 0:0 1:1 2:2 3:3 4:6 5:6 6:6      (PARTNER — top 3 trump)
# P3: 2:5 3:4 3:5 4:4 4:5 5:5 2:6      (opponent, holds 1 trump)
func _scenario_a_hands() -> Array:
	var p0 = _hand_from_pairs([[0,1],[0,2],[0,3],[0,4],[0,5],[0,6],[1,6]])
	var p1 = _hand_from_pairs([[1,2],[1,3],[1,4],[1,5],[2,3],[2,4],[3,6]])
	var p2 = _hand_from_pairs([[0,0],[1,1],[2,2],[3,3],[4,6],[5,6],[6,6]])
	var p3 = _hand_from_pairs([[2,5],[3,4],[3,5],[4,4],[4,5],[5,5],[2,6]])
	return [p0, p1, p2, p3]

# ── Scenario B — Opponent control (P1 holds top 3 trump, on lead) ───
# P0: 0:1 0:2 0:3 0:4 0:5 1:2 3:6      (opposing team to P1, holds 1 trump)
# P1: 0:0 1:1 2:2 3:3 4:6 5:6 6:6      (OPPONENT — top 3 trump, on lead)
# P2: 1:3 1:4 1:5 2:3 2:4 2:5 2:6      (opposing team to P1, holds 1 trump; also PARTNER_SEAT)
# P3: 3:4 3:5 4:4 4:5 5:5 0:6 1:6      (P1's own teammate)
func _scenario_b_hands() -> Array:
	var p0 = _hand_from_pairs([[0,1],[0,2],[0,3],[0,4],[0,5],[1,2],[3,6]])
	var p1 = _hand_from_pairs([[0,0],[1,1],[2,2],[3,3],[4,6],[5,6],[6,6]])
	var p2 = _hand_from_pairs([[1,3],[1,4],[1,5],[2,3],[2,4],[2,5],[2,6]])
	var p3 = _hand_from_pairs([[3,4],[3,5],[4,4],[4,5],[5,5],[0,6],[1,6]])
	return [p0, p1, p2, p3]

func _setup_game(hands: Array) -> Game:
	_validate_full_deck(hands)
	var game = Game.new()
	game.setup_players(0)  # human_seat is nominal here — no human seat plays
	for i in range(4):
		game.players[i].hand.clear()
		game.players[i].reset_round()
		for d in hands[i]:
			game.players[i].hand.append(d)
	game.team_points[0] = 0
	game.team_points[1] = 0
	game.tricks_played = 0
	var bid = BidScript.new(BidScript.Type.POINTS, BID_VALUE, BIDDER_SEAT)
	game.current_bid = bid
	game.apply_bid_result(TRUMP_SUIT)
	return game

# ── Diagnostic recomputation ─────────────────────────────────────────
# Mirrors the EXACT gate formulas from ai_player.gd so we can log their
# values even though decide_play() doesn't expose them as out-params.
# Partner gates: ai_player.gd ~625-634 (trump_control) and ~670-673
# (heuristic fallback). Opponent gate: ai_player.gd ~995-999 (trumps.size()>=3).

func _sorted_hand_str(hand: Array, trump: int) -> String:
	var copy = hand.duplicate()
	copy.sort_custom(func(a, b): return a.get_rank(trump) > b.get_rank(trump))
	var parts: Array = []
	for d in copy:
		parts.append(d.debug_string())
	return ", ".join(parts)

func _compute_partner_diagnostics(legal: Array, hand: Array, trump: int, player_id: int, partner_id: int, knowledge: PublicKnowledge) -> Dictionary:
	var trumps = legal.filter(func(d): return d.is_trump(trump))
	var holds_double_trump = trumps.any(func(d): return d.is_double())
	var opposing_team = [0, 1, 2, 3].filter(func(p): return p != player_id and p != partner_id)

	var rank_safe = false
	var best_trump_candidate_str = "none"
	var top_remaining_str = "none"
	if trumps.size() > 0:
		var best_trump_candidate: Domino = trumps[0]
		for d in trumps:
			if d.get_rank(trump) > best_trump_candidate.get_rank(trump):
				best_trump_candidate = d
		best_trump_candidate_str = best_trump_candidate.debug_string()
		var top_remaining = knowledge.highest_remaining_trump()
		if top_remaining != null:
			top_remaining_str = top_remaining.debug_string()
			rank_safe = top_remaining.debug_string() == best_trump_candidate.debug_string()

	var objective_incomplete = not opposing_team.all(func(opp): return knowledge.void_suits(opp).has(trump))
	var trump_control = rank_safe and objective_incomplete

	var heuristic_fallback = (not trump_control) and trumps.size() >= 4 and not holds_double_trump
	var objective_incomplete_heuristic = false
	if trumps.size() >= 4 and not holds_double_trump:
		objective_incomplete_heuristic = not opposing_team.all(func(opp): return knowledge.void_suits(opp).has(trump))
	heuristic_fallback = heuristic_fallback and objective_incomplete_heuristic

	return {
		"trumps_held": trumps.size(),
		"holds_double_trump": holds_double_trump,
		"best_trump_candidate": best_trump_candidate_str,
		"highest_remaining_trump": top_remaining_str,
		"rank_safe": rank_safe,
		"opposing_team": opposing_team,
		"opposing_team_all_void_in_trump": not objective_incomplete,
		"trump_control_eligible": trump_control,
		"heuristic_fallback_eligible": heuristic_fallback,
	}

func _compute_opponent_diagnostics(legal: Array, trump: int) -> Dictionary:
	var trumps = legal.filter(func(d): return d.is_trump(trump))
	return {
		"trumps_held": trumps.size(),
		"trumps_size_gte_3": trumps.size() >= 3,
	}

func _label_objective(reason: String, is_partner: bool, diag: Dictionary) -> String:
	if reason == "I have trump control — drawing out the opponents.":
		return "CONTROL_TRUMP (double accounted for)"
	if reason == "Leading low trump to draw out the double first.":
		if is_partner and diag.get("trump_control_eligible", false):
			return "CONTROL_TRUMP (double not accounted for)"
		return "CONTROL_TRUMP_HEURISTIC_FALLBACK (Step 3, trumps>=4 no double)"
	if reason == "Nothing can beat this." or reason == "Leading my double — nothing left to beat it.":
		return "SAFE tier"
	if reason == "Giving you a free discard.":
		return "GIFT_A_VOID"
	if reason == "Leading a suit you can't beat.":
		return "OPPONENT_SAFE_LEAD (BUG-012 two-path check)"
	if reason == "Drawing out trumps.":
		return "OPPONENT_TRUMP_LEAD (trumps.size() >= 3)"
	if reason == "Leading my strong count to lock in the points.":
		return "OPPONENT_STRONG_COUNTER"
	if reason in ["Last domino.", "Leading my double.", "Leading my best domino."]:
		return "FALLBACK_BEST (no trump-control condition met)"
	return "UNMAPPED: " + reason

# ── Trace runner ──────────────────────────────────────────────────────

func _run_scenario(name: String, hands: Array, target_seat: int, is_partner_target: bool) -> Dictionary:
	_log("")
	_log("═══════════════════════════════════════════════════════════")
	_log("SCENARIO %s — target seat P%d (is_partner=%s)" % [name, target_seat, is_partner_target])
	_log("═══════════════════════════════════════════════════════════")

	var game = _setup_game(hands)
	var leader = target_seat
	var stop_reason = "completed all 7 tricks without stopping"
	var trick_records: Array = []

	for trick_num in range(7):
		game.start_trick(leader)
		_log("")
		_log("── Trick %d — leader P%d ──" % [trick_num + 1, leader])

		var this_trick_record = {"trick": trick_num + 1, "leader": leader}
		var target_led_trump = false
		var target_reason = ""
		var target_chosen = ""
		var target_diag = {}

		for turn in range(4):
			var player = game.players[game.current_player]
			var legal = game.get_legal_moves(player)
			var partner_id = (player.id + 2) % 4
			var is_partner_seat = (player.id == PARTNER_SEAT)
			var reason_log: Array = []
			var frame = PublicFrame.new(game.hand_history, game.current_trick)
			var knowledge = PublicKnowledge.from_state(frame)
			var is_leading_this_play = (game.current_trick.plays.size() == 0)

			if player.id == target_seat and is_leading_this_play:
				_log("  P%d hand (sorted by trump rank): %s" % [player.id, _sorted_hand_str(player.hand, game.trump)])
				if is_partner_seat:
					target_diag = _compute_partner_diagnostics(legal, player.hand, game.trump, player.id, partner_id, knowledge)
					_log("  highest_remaining_trump(): %s" % target_diag["highest_remaining_trump"])
					_log("  best trump in hand:        %s" % target_diag["best_trump_candidate"])
					_log("  rank_safe:                 %s" % target_diag["rank_safe"])
					_log("  opposing_team %s all void in trump: %s" % [target_diag["opposing_team"], target_diag["opposing_team_all_void_in_trump"]])
					_log("  CONTROL_TRUMP eligible (rank_safe AND not-all-void): %s" % target_diag["trump_control_eligible"])
					_log("  Step-3 heuristic fallback eligible (trumps>=4, no double, not-all-void): %s" % target_diag["heuristic_fallback_eligible"])
				else:
					target_diag = _compute_opponent_diagnostics(legal, game.trump)
					_log("  trumps held: %d   (trumps.size() >= 3 -> %s)" % [target_diag["trumps_held"], target_diag["trumps_size_gte_3"]])

			var chosen = AIPlayer.decide_play(
				legal, player.hand, game.current_trick,
				player.id, partner_id, game.trump, reason_log,
				DIFFICULTY, is_partner_seat, game.variant,
				game.current_bid.player_id, knowledge,
				game.team_points, game.current_bid.value
			)

			if player.id == target_seat and is_leading_this_play:
				target_led_trump = chosen.is_trump(game.trump)
				target_reason = reason_log[-1] if reason_log.size() > 0 else "(no reason logged)"
				target_chosen = chosen.debug_string()
				var label = _label_objective(target_reason, is_partner_seat, target_diag)
				_log("  >>> CHOSE: %s   objective: %s" % [target_chosen, label])
				_log("  >>> reason_log: \"%s\"" % target_reason)
				this_trick_record["target_diagnostics"] = target_diag
				this_trick_record["target_chosen"] = target_chosen
				this_trick_record["target_reason"] = target_reason
				this_trick_record["target_objective_label"] = label
				this_trick_record["target_led_trump"] = target_led_trump

			game.play_domino(player, chosen)
			game.current_player = (game.current_player + 3) % 4

		var winner_id = game.resolve_trick()
		game.record_trick(game.current_trick, winner_id, game.current_trick.plays)
		_log("  Trick winner: P%d" % winner_id)
		this_trick_record["winner"] = winner_id
		trick_records.append(this_trick_record)

		# ── Stop conditions, checked in this priority order ──
		var target_hand_after = game.players[target_seat].hand
		var target_still_has_trump = target_hand_after.any(func(d): return d.is_trump(game.trump))

		if not target_still_has_trump:
			stop_reason = "target seat P%d has no trump remaining after trick %d" % [target_seat, trick_num + 1]
			_log("  >>> STOP: %s" % stop_reason)
			break

		if winner_id != target_seat:
			stop_reason = "target seat P%d lost the lead after trick %d (winner was P%d)" % [target_seat, trick_num + 1, winner_id]
			_log("  >>> STOP: %s" % stop_reason)
			break

		# Re-check void status post-trick for informational purposes
		# (only meaningful for the partner path, which actually gates on this).
		var post_frame = PublicFrame.new(game.hand_history, null)
		var post_knowledge = PublicKnowledge.from_state(post_frame)
		var partner_id_for_target = (target_seat + 2) % 4
		var opposing_team_for_target = [0, 1, 2, 3].filter(func(p): return p != target_seat and p != partner_id_for_target)
		var all_void = opposing_team_for_target.all(func(opp): return post_knowledge.void_suits(opp).has(game.trump))
		if is_partner_target and all_void:
			stop_reason = "opposing team confirmed void in trump after trick %d (CONTROL_TRUMP objective satisfied)" % (trick_num + 1)
			_log("  >>> STOP: %s" % stop_reason)
			break

		leader = winner_id

	_log("")
	_log("SCENARIO %s RESULT: %s" % [name, stop_reason])
	return {"scenario": name, "target_seat": target_seat, "stop_reason": stop_reason, "tricks": trick_records}

func _init():
	trace_lines.clear()
	trace_records.clear()

	var result_a = _run_scenario("A (Partner control, P2 leads)", _scenario_a_hands(), PARTNER_SEAT, true)
	var result_b = _run_scenario("B (Opponent control, P1 leads)", _scenario_b_hands(), 1, false)

	trace_records.append(result_a)
	trace_records.append(result_b)

	var out = {
		"scenario_a": result_a,
		"scenario_b": result_b,
		"full_log": trace_lines,
	}
	var f = FileAccess.open("res://trump_control_trace_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()

	print("")
	print("Results written to res://trump_control_trace_results.json")
	quit(0)
