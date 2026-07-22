extends SceneTree

# â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=
# set_vs_make_trace.gd
#
# Direct, single-decision-point trace for the Set-vs-Make policy change
# (Edits 1-3, July 22 2026 session). Unlike trump_control_trace*.gd,
# this does NOT run a full autonomous 4-player trick loop for the seats
# whose plays don't matter to the test â€” predicting what an AI would
# autonomously lead is a separate question from what we're verifying
# here. Instead we construct exactly one trick directly: human (seat0)
# leads 4:4 (a non-trump double), seat3 discards, then AIPlayer.decide_play()
# is called ONCE for Partner (seat2) â€” the actual decision under test.
# Everything about the board is held fixed between the two runs; only
# bidder_id (and therefore is_defending) changes.
#
# Hand design, chosen so the exact evaluation gates in ai_player.gd are
# forced deterministically, not left to autonomous AI judgment:
#   - Trump = 6 (sixes).
#   - Seat0 (human) holds 0:6 and 1:6 (2 of the 7 trump tiles) â€” held
#     back, unplayed. This is what keeps _is_guaranteed_win() false:
#     Partner does NOT hold all remaining trump, so the trump-outstanding
#     gate (ai_player.gd:1283-1284) reports a gap, even though in
#     reality that trump is harmlessly sitting in the leading human's
#     own hand. This is the exact shape of the July 20 traced bug.
#   - Partner (seat2) holds the other 5 trump tiles, plus 5:5 (a
#     10-count, NOT suit-4, safe to dump if the policy allows it) and
#     2:2 (a non-counter, non-trump alternative, so Partner has more
#     than one legal option and isn't forced into a single move).
#   - Seat1 holds a suit-4 tile (0:4, 1:4) and zero trump; seat3 holds
#     several suit-4 tiles and zero trump. Neither can beat a non-trump
#     double regardless of suit/void status, since 4:4 is unbeatable
#     within its own suit and neither holds trump to override it.
#
# _is_win_safe_against_remaining_actors() is expected to return true via
# Path A of _is_lead_safe_against_opponent(): seat1 (the only remaining
# actor after Partner's play, since play order for a seat0 lead is
# P0 -> P3 -> P2 -> P1) is not yet proven void in suit 4, and 4:4 is a
# double â€” Path A clears unconditionally for a non-void opponent facing
# a double, independent of trump. NOTE: this trace exercises Path A
# only. Path B (opponent proven void in both suit and trump via an
# earlier trick) is not covered here â€” a reasonable follow-up trace
# once this one is confirmed, not attempted in this pass.
#
# What this trace does NOT predict: the exact tile Partner discards in
# the MAKE case. The fallthrough "protect" logic (ai_player.gd:889-928,
# unmodified by this change) filters candidates by counter-status only
# and delegates the final pick to _pick_partner_discard(), which this
# trace does not independently verify. What's reliable regardless: 5:5
# is a counter, so it's excluded from that fallback pool entirely and
# can only be the result if the new dump path fires. The comparison
# this trace is built around is "did Partner dump 5:5", not "which
# exact tile did Partner protect with".
#
# Run:
#   "$GODOT" --headless --path . --script res://set_vs_make_trace.gd
# â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=

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

# Seat0 (human): 0:6, 1:6 held back (unplayed trump), 4:4 (trick lead),
#   plus 4 non-trump, non-suit-4 fillers.
# Seat1: no trump, holds suit-4 tiles (0:4, 1:4) â€” not void in suit 4.
# Seat2 (Partner): 5 of the remaining trump tiles, plus 5:5 (counter,
#   dumpable) and 2:2 (non-counter alternative).
# Seat3: no trump, holds several suit-4 tiles â€” irrelevant to the
#   decision point since they act before Partner and can't beat 4:4.
func _hands() -> Array:
	var p0 = _hand_from_pairs([[0,6],[1,6],[4,4],[0,0],[0,1],[0,2],[1,1]])
	var p1 = _hand_from_pairs([[0,3],[0,4],[0,5],[1,2],[1,3],[1,4],[1,5]])
	var p2 = _hand_from_pairs([[2,6],[3,6],[4,6],[5,6],[6,6],[5,5],[2,2]])
	var p3 = _hand_from_pairs([[2,3],[2,4],[2,5],[3,3],[3,4],[3,5],[4,5]])
	return [p0, p1, p2, p3]

func _setup_game(hands: Array, bidder_seat: int) -> Game:
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

func _run_scenario(label: String, bidder_seat: int) -> Dictionary:
	_log("")
	_log("â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=")
	_log("SCENARIO %s â€” bidder_seat=P%d" % [label, bidder_seat])
	_log("â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=â•=")

	var game = _setup_game(_hands(), bidder_seat)
	game.start_trick(HUMAN_SEAT)

	# P0 (human) leads 4:4 directly â€” this trick's shape is a fixed
	# input to the test, not something under test, so we don't route it
	# through decide_play()'s own (unpredictable-to-us) lead judgment.
	var human = game.players[HUMAN_SEAT]
	var lead_candidates = human.hand.filter(func(d): return d.left == 4 and d.right == 4)
	var lead_tile = lead_candidates[0]
	game.play_domino(human, lead_tile)
	_log("  P0 leads: %s" % lead_tile.debug_string())

	# P3 discards directly â€” any legal tile; none can beat a non-trump
	# double they can't trump over (P3 holds zero trump in this setup).
	var p3 = game.players[3]
	var p3_legal = game.get_legal_moves(p3)
	var p3_tile = p3_legal[0]
	game.play_domino(p3, p3_tile)
	_log("  P3 plays: %s" % p3_tile.debug_string())

	# The actual decision under test: Partner (seat2), via the real,
	# unmodified-elsewhere decide_play() call.
	var partner = game.players[PARTNER_SEAT]
	var legal = game.get_legal_moves(partner)
	var reason_log: Array = []
	var frame = PublicFrame.new(game.hand_history, game.current_trick)
	var knowledge = PublicKnowledge.from_state(frame)

	_log("  Partner (P2) hand: %s" % ", ".join(partner.hand.map(func(d): return d.debug_string())))
	_log("  Partner legal moves: %s" % ", ".join(legal.map(func(d): return d.debug_string())))
	var our_team = PARTNER_SEAT % 2
	var bidder_team = bidder_seat % 2
	_log("  bid_value=%d  bidder_seat=P%d  our_team(P2)=%d  bidder_team=%d  is_defending=%s" % [
		BID_VALUE, bidder_seat, our_team, bidder_team, our_team != bidder_team
	])

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

	# MAKE â€” bidder on Partner's own team (team 0: seats 0, 2).
	# Expected: guaranteed_win=false, is_defending=false, so the new
	# win_safe_against_remaining path is never consulted â€” behavior
	# should be identical to before this change (dumped_5_5 == false).
	results["make_bidder_team0"] = _run_scenario("MAKE (bidder=P0, our own team)", 0)

	# SET â€” bidder on the opposing team (team 1: seats 1, 3).
	# Expected: guaranteed_win=false, is_defending=true,
	# win_safe_against_remaining=true (Path A, double vs. non-void
	# opponent) â€” the new path should fire (dumped_5_5 == true).
	results["set_bidder_team1"] = _run_scenario("SET (bidder=P1, opposing team)", 1)

	results["full_log"] = trace_lines

	var f = FileAccess.open("res://set_vs_make_trace_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "\t"))
	f.close()

	print("")
	print("Results written to res://set_vs_make_trace_results.json")
	quit(0)