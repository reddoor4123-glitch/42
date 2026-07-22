extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# set_vs_make_path_a_negative_trace.gd
#
# Closes the last open case from the July 22 2026 Set-vs-Make session:
# Path A of _is_lead_safe_against_opponent() when it must correctly
# return false — opponent NOT void in the led suit, tile NOT a double,
# and NOT provably the highest remaining tile in that suit. Unlike
# Path B, this needs no historical setup trick: "not void" and "best
# remaining tile" are both real-time facts about current hands, not
# something that has to be revealed through prior-trick history.
#
# Construction: human (seat0) leads 1:3 (suit 3, non-double — a double
# would trigger Path A's unconditional clear, which is exactly what
# we're isolating away from here). Seat1 (the remaining actor) holds
# 2:3 — a genuine suit-3 tile, making them provably NOT void, so Path A
# takes the "not void" branch rather than Path B's void branch. Seat0
# ALSO holds 3:3 (a suit-3 double) unplayed, which best_remaining_card_
# for_suit(3) should identify as the actual highest remaining tile in
# suit 3 — outranking 1:3, and NOT in Partner's hand, so both
# guaranteed_win and win_safe_against_remaining should independently
# land on false via the same underlying fact (an unaccounted higher
# card exists outside Partner's hand).
#
# Expected (DERIVED BY HAND, not yet run — same caveat as the Path B
# script: read the actual output, don't assume this is correct):
#   guaranteed_win = false (best_in_suit = 3:3, outranks 1:3, not in
#     Partner's hand — ai_player.gd:1277-1282).
#   win_safe_against_remaining = false regardless of is_defending
#     (opponent not void, tile not double, best remaining tile 3:3 !=
#     candidate 1:3 — Path A's non-void branch correctly fails).
#   MAKE and SET should therefore behave IDENTICALLY — both falling to
#   the same pre-existing forced-overtake fallback (Partner is void in
#   suit 3, so legal = full hand, all non-counter candidates are trump
#   and all beat a non-trump lead). Partner holds 6:6 (the actual top
#   trump), so every trump candidate qualifies as "guaranteed" by the
#   forced-overtake sub-check (ai_player.gd:899, a DIFFERENT guaranteed_
#   win call than the one at the top of the human_is_winning branch —
#   evaluated per-candidate, not against the winning domino). Predicted
#   chosen tile: 1:6 (lowest-ranked of the guaranteed candidates).
#
# Run:
#   "$GODOT" --headless --path . --script res://set_vs_make_path_a_negative_trace.gd
# ═══════════════════════════════════════════════════════════════════

const BidScript = preload("res://bid.gd")
const TRUMP_SUIT := 6
const BID_VALUE := 30
const HUMAN_SEAT := 0
const PARTNER_SEAT := 2

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

# Seat0: 1:3 (test lead), 0:3/3:3/3:4/3:5 (other suit-3 tiles, kept off
#   every other seat so nothing else complicates the suit-3 picture),
#   0:6, 0:2 (arbitrary fillers).
# Seat1: 2:3 (the genuine, real threat — NOT the actual best, since
#   3:3 outranks it, but enough to make seat1 provably not void),
#   plus arbitrary fillers.
# Seat2 (Partner): all 6 remaining trump + 5:5 (the counter under
#   test) — void in suit 3 entirely, so legal = full hand.
# Seat3: no trump, no suit-3 tiles — cannot beat 1:3 regardless of
#   what it's forced to discard.
func _hands() -> Array:
	var p0 = _hand_from_pairs([[1,3],[0,3],[3,3],[3,4],[3,5],[0,6],[0,2]])
	var p1 = _hand_from_pairs([[2,3],[0,0],[0,1],[1,1],[1,2],[2,2],[2,4]])
	var p2 = _hand_from_pairs([[1,6],[2,6],[3,6],[4,6],[5,6],[6,6],[5,5]])
	var p3 = _hand_from_pairs([[0,4],[0,5],[1,4],[1,5],[2,5],[4,4],[4,5]])
	return [p0, p1, p2, p3]

func _setup_game(bidder_seat: int) -> Game:
	var hands = _hands()
	_validate_full_deck(hands)
	var game = Game.new()
	game.setup_players(HUMAN_SEAT)
	for i in range(4):
		game.players[i].hand.clear()
		game.players[i].reset_round()
		for d in hands[i]:
			game.players[i].hand.append(d)
	game.team_points[0] = 0
	game.team_points[1] = 0
	game.tricks_played = 0
	game.hand_history.clear()
	var bid = BidScript.new(BidScript.Type.POINTS, BID_VALUE, bidder_seat)
	game.current_bid = bid
	game.apply_bid_result(TRUMP_SUIT)
	return game

func _find(hand: Array, l: int, r: int) -> Domino:
	for d in hand:
		if d.left == l and d.right == r:
			return d
	return null

func _run_scenario(label: String, bidder_seat: int) -> Dictionary:
	_log("")
	_log("═══════════════════════════════════════════════════════════")
	_log("SCENARIO %s — bidder_seat=P%d" % [label, bidder_seat])
	_log("═══════════════════════════════════════════════════════════")

	var game = _setup_game(bidder_seat)
	game.start_trick(HUMAN_SEAT)

	var human = game.players[HUMAN_SEAT]
	var lead_tile = _find(human.hand, 1, 3)
	game.play_domino(human, lead_tile)
	_log("  P0 leads: %s" % lead_tile.debug_string())

	var p3 = game.players[3]
	var p3_legal = game.get_legal_moves(p3)
	var p3_tile = p3_legal[0]
	game.play_domino(p3, p3_tile)
	_log("  P3 plays: %s" % p3_tile.debug_string())

	var partner = game.players[PARTNER_SEAT]
	var legal = game.get_legal_moves(partner)
	var reason_log: Array = []
	var frame = PublicFrame.new(game.hand_history, game.current_trick)
	var knowledge = PublicKnowledge.from_state(frame)

	_log("  Partner (P2) hand: %s" % ", ".join(partner.hand.map(func(d): return d.debug_string())))
	_log("  Partner legal moves: %s" % ", ".join(legal.map(func(d): return d.debug_string())))
	_log("  void_suits(P1) per PublicKnowledge: %s (expect empty — no history established)" % [knowledge.void_suits(1)])
	var our_team = PARTNER_SEAT % 2
	var bidder_team = bidder_seat % 2
	_log("  our_team(P2)=%d  bidder_team=%d  is_defending=%s" % [our_team, bidder_team, our_team != bidder_team])

	var chosen = AIPlayer.decide_play(
		legal, partner.hand, game.current_trick,
		PARTNER_SEAT, HUMAN_SEAT, game.trump, reason_log,
		"expert", true, game.variant,
		game.current_bid.player_id, knowledge,
		game.team_points, game.current_bid.value
	)

	var reason = reason_log[-1] if reason_log.size() > 0 else "(no reason logged)"
	_log("  >>> Partner CHOSE: %s" % chosen.debug_string())
	_log("  >>> reason_log: \"%s\"" % reason)

	return {
		"scenario": label,
		"bidder_seat": bidder_seat,
		"is_defending": our_team != bidder_team,
		"partner_chosen": chosen.debug_string(),
		"partner_reason": reason,
		"dumped_5_5": chosen.debug_string() == "5:5"
	}

func _init():
	trace_lines.clear()
	var results := {}

	results["path_a_negative_MAKE"] = _run_scenario("path_a_negative_MAKE", HUMAN_SEAT)
	results["path_a_negative_SET"] = _run_scenario("path_a_negative_SET", 1)

	results["full_log"] = trace_lines

	var f = FileAccess.open("res://set_vs_make_path_a_negative_trace_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "\t"))
	f.close()

	print("")
	print("Results written to res://set_vs_make_path_a_negative_trace_results.json")
	quit(0)
