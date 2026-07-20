extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# trump_control_trace_v3.gd
#
# Acceptance criterion 4 of the Unified Trump-Control Lead Decision spec
# (July 20 2026, ai_player.gd): a harness built AFTER the code change,
# not before — to confirm the fix adds real capability, not just
# reorders existing checks.
#
# P1 (Opponent, Expert/full-vigilance) holds the top TWO ranked trump
# only (6:6, 5:6) — NOT three. Its five filler tiles are all
# non-double, non-counter (pip_sum != 5, 10), and touch no suit whose
# own-suit double P1 itself holds (P1 holds zero non-trump doubles at
# all), so none of them can pass _is_lead_fully_safe() at trick 1
# either (a non-double filler tile is only "safe" if it IS the
# best-remaining card for its suit, which the suit's own double —
# always rank 13 — trivially prevents whenever that double is still
# unplayed and held by someone else).
#
# Under the OLD code (both the plain Opponent `trumps.size() >= 3`
# check and its `>= 4` Step-3 heuristic), this hand fails BOTH: 2 < 3
# and 2 < 4. This seat would never lead trump via any trump-specific
# branch at all — trick 1 would fall through to the counters check
# (none of the filler are counters, by construction) and then the
# blind highest-tile fallback.
#
# Under the NEW code, `_control_trump_lead()`'s eligibility is rank-safe
# (best trump == highest_remaining_trump()) AND objective-incomplete
# (opposing team not yet confirmed void) — neither depends on holding
# 3+ trump. Holding the literal top-ranked trump (6:6) at trick 1 makes
# rank_safe trivially true regardless of count, so CONTROL_TRUMP should
# fire on trick 1 with only 2 trump in hand.
#
# Conventions per Headless_Harness_Reference.md: is_partner computed
# explicitly per seat, turn order (current_player + 3) % 4,
# record_trick() passed current_trick.plays, results written to JSON.
#
# Run:
#   "$GODOT" --headless --path . --script res://trump_control_trace_v3.gd
# ═══════════════════════════════════════════════════════════════════

const BidScript = preload("res://bid.gd")
const TRUMP_SUIT := 6
const BID_VALUE := 30
const BIDDER_SEAT := 0
const PARTNER_SEAT := 2
const DIFFICULTY := "expert"

var trace_lines: Array = []

func _log(s: String):
	trace_lines.append(s)
	print(s)

func _hand_from_pairs(pairs: Array) -> Array[Domino]:
	var h: Array[Domino] = []
	for p in pairs:
		h.append(Domino.new(p[0], p[1]))
	return h

func _validate_full_deck(all_hands: Array) -> void:
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

# P1 (target) holds only the TOP 2 ranked trump: 6:6 (rank 13, double)
# and 5:6 (rank 5) — ranks 4,3,2,1,0 (4:6,3:6,2:6,1:6,0:6) are held
# elsewhere. P1's 5 filler tiles are non-double, non-counter, and their
# own-suit doubles (0:0,1:1,2:2,3:3,4:4,5:5) all live in P0/P2/P3's hands.
func _hands_top2_trump() -> Array:
	var p0 = _hand_from_pairs([[0,0],[0,2],[0,3],[0,4],[0,5],[0,6],[1,3]])
	var p1 = _hand_from_pairs([[6,6],[5,6],[0,1],[1,2],[2,4],[3,4],[4,5]])
	var p2 = _hand_from_pairs([[1,1],[2,2],[1,4],[1,5],[2,3],[2,5],[1,6]])
	var p3 = _hand_from_pairs([[3,5],[3,3],[4,4],[5,5],[2,6],[3,6],[4,6]])
	return [p0, p1, p2, p3]

func _setup_game(hands: Array) -> Game:
	_validate_full_deck(hands)
	var game = Game.new()
	game.setup_players(0)
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

# Mirrors _control_trump_lead()'s eligibility test exactly (ai_player.gd),
# using only public PublicKnowledge methods — same discipline as v2.
func _compute_diagnostics(legal: Array, trump: int, player_id: int, partner_id: int, knowledge: PublicKnowledge) -> Dictionary:
	var opposing_team = [0, 1, 2, 3].filter(func(p): return p != player_id and p != partner_id)
	var trumps = legal.filter(func(d): return d.is_trump(trump))

	var rank_safe = false
	var best_trump_str = "none"
	var top_remaining_str = "none"
	if trumps.size() > 0:
		var best: Domino = trumps[0]
		for d in trumps:
			if d.get_rank(trump) > best.get_rank(trump):
				best = d
		best_trump_str = best.debug_string()
		var top_remaining = knowledge.highest_remaining_trump()
		if top_remaining != null:
			top_remaining_str = top_remaining.debug_string()
			rank_safe = top_remaining.debug_string() == best.debug_string()

	var objective_incomplete = not opposing_team.all(func(opp): return knowledge.void_suits(opp).has(trump))

	return {
		"opposing_team": opposing_team,
		"trumps_held": trumps.size(),
		"trumps_size_gte_3": trumps.size() >= 3,
		"trumps_size_gte_4": trumps.size() >= 4,
		"best_trump_in_hand": best_trump_str,
		"highest_remaining_trump": top_remaining_str,
		"rank_safe": rank_safe,
		"opposing_team_all_void_in_trump": not objective_incomplete,
		"old_code_would_ever_fire_trump_branch": trumps.size() >= 3,
		"new_code_control_trump_eligible": rank_safe and objective_incomplete,
	}

func _label_objective(reason: String) -> String:
	match reason:
		"I have trump control — drawing out the opponents.": return "CONTROL_TRUMP"
		"Leading low trump to draw out the double first.": return "CONTROL_TRUMP_HEURISTIC_FALLBACK"
		"Leading a suit you can't beat.": return "OPPONENT_SAFE_LEAD"
		"Drawing out trumps.": return "OPPONENT_TRUMP_LEAD (trumps.size() >= 3)"
		"Leading my strong count to lock in the points.": return "OPPONENT_STRONG_COUNTER"
		"Last domino.", "Leading my double.", "Leading my best domino.": return "FALLBACK_BEST"
		_: return "UNMAPPED: " + reason

func _sorted_hand_str(hand: Array, trump: int) -> String:
	var copy = hand.duplicate()
	copy.sort_custom(func(a, b): return a.get_rank(trump) > b.get_rank(trump))
	var parts: Array = []
	for d in copy:
		parts.append(d.debug_string())
	return ", ".join(parts)

func _run_scenario(name: String, hands: Array, target_seat: int) -> Dictionary:
	_log("")
	_log("═══════════════════════════════════════════════════════════")
	_log("SCENARIO %s — target P%d, difficulty=%s (top-2-trump-only hand)" % [name, target_seat, DIFFICULTY])
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

		for turn in range(4):
			var player = game.players[game.current_player]
			var legal = game.get_legal_moves(player)
			var partner_id = (player.id + 2) % 4
			var is_partner_seat = (player.id == PARTNER_SEAT)
			var reason_log: Array = []
			var frame = PublicFrame.new(game.hand_history, game.current_trick)
			var knowledge = PublicKnowledge.from_state(frame)
			var is_leading_this_play = (game.current_trick.plays.size() == 0)

			var diag = {}
			if player.id == target_seat and is_leading_this_play:
				_log("  P%d hand (sorted by trump rank): %s" % [player.id, _sorted_hand_str(player.hand, game.trump)])
				diag = _compute_diagnostics(legal, game.trump, player.id, partner_id, knowledge)
				_log("  trumps held: %d   (old >=3 check: %s, old >=4 check: %s)" % [diag["trumps_held"], diag["trumps_size_gte_3"], diag["trumps_size_gte_4"]])
				_log("  best trump in hand: %s   highest_remaining_trump(): %s   rank_safe: %s" % [diag["best_trump_in_hand"], diag["highest_remaining_trump"], diag["rank_safe"]])
				_log("  opposing_team %s all void in trump: %s" % [diag["opposing_team"], diag["opposing_team_all_void_in_trump"]])
				_log("  NEW-code CONTROL_TRUMP eligible (rank_safe AND not-all-void): %s" % diag["new_code_control_trump_eligible"])
				_log("  OLD-code would ever fire a trump-specific branch here: %s" % diag["old_code_would_ever_fire_trump_branch"])

			var chosen = AIPlayer.decide_play(
				legal, player.hand, game.current_trick,
				player.id, partner_id, game.trump, reason_log,
				DIFFICULTY, is_partner_seat, game.variant,
				game.current_bid.player_id, knowledge,
				game.team_points, game.current_bid.value
			)

			if player.id == target_seat and is_leading_this_play:
				var reason = reason_log[-1] if reason_log.size() > 0 else "(no reason logged)"
				var label = _label_objective(reason)
				_log("  >>> CHOSE: %s   objective: %s" % [chosen.debug_string(), label])
				_log("  >>> reason_log: \"%s\"" % reason)
				this_trick_record["target_diagnostics"] = diag
				this_trick_record["target_chosen"] = chosen.debug_string()
				this_trick_record["target_reason"] = reason
				this_trick_record["target_objective_label"] = label
				this_trick_record["target_led_trump"] = chosen.is_trump(game.trump)

			game.play_domino(player, chosen)
			game.current_player = (game.current_player + 3) % 4

		var winner_id = game.resolve_trick()
		game.record_trick(game.current_trick, winner_id, game.current_trick.plays)
		_log("  Trick winner: P%d" % winner_id)
		this_trick_record["winner"] = winner_id
		trick_records.append(this_trick_record)

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

		leader = winner_id

	_log("")
	_log("SCENARIO %s RESULT: %s" % [name, stop_reason])
	return {"scenario": name, "target_seat": target_seat, "stop_reason": stop_reason, "tricks": trick_records}

func _init():
	trace_lines.clear()

	var result = _run_scenario("top2_trump_expert", _hands_top2_trump(), 1)

	var out = {
		"top2_trump_expert": result,
		"full_log": trace_lines,
	}
	var f = FileAccess.open("res://trump_control_trace_v3_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()

	print("")
	print("Results written to res://trump_control_trace_v3_results.json")
	quit(0)
