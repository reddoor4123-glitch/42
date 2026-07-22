extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# set_vs_make_path_b_trace.gd
#
# Follow-up to set_vs_make_trace.gd. That script confirmed Path A of
# _is_lead_safe_against_opponent() (opponent not void in suit, tile is a
# double — clears unconditionally). This script covers Path B: opponent
# PROVEN void in both suit and trump, established via real prior-trick
# history, not asserted.
#
# Two setup tricks precede the test trick:
#   Setup A — suit 2 led, seat1 (the eventual "remaining actor") holds
#     no suit-2 tile, revealing void_suits(1) ⊇ {2}.
#   Setup B — trump led, seat1 holds no trump, revealing
#     void_suits(1) ⊇ {6}.
# Test trick — seat0 leads 1:2 (suit 2, NOT a double — Path A's double
#   shortcut does not apply here, isolating Path B). Seat3 discards
#   (already established void in suit 2 from setup A, cannot beat it).
#   Partner (seat2) decides — the actual call under test.
#
# POSITIVE pair (both setup tricks run): seat1 proven void in suit AND
#   trump — _is_win_safe_against_remaining_actors() should return true.
# NEGATIVE pair (setup A only, B skipped): seat1 proven void in suit
#   but trump status is genuinely unestablished — the function should
#   return false, and Set-vs-Make must NOT dump even when defending.
#   This is the actual safety check: is_defending lowering the
#   threshold must never substitute for evaluation saying "unsafe".
#
# guaranteed_win is false throughout (verified by hand): candidate 1:2
# is not trump, and best_remaining_card_for_suit(2) resolves to 2:2 (a
# double, sitting in seat0's hand, unplayed) which outranks 1:2 and
# isn't in Partner's hand — ai_player.gd:1277-1282 returns false on
# that basis before the trump-gap check is even reached.
#
# IMPORTANT — everything below is DERIVED BY HAND, not yet run. The
# "expected" values in each scenario's log line are predictions to be
# checked against actual output, not asserted facts. In particular the
# forced-overtake branch's exact chosen tile (ai_player.gd:898-910)
# depends on highest_remaining_trump() at each decision point, which
# shifts between the positive and negative variants because setup B
# consumes an extra trump tile from Partner's hand in the positive
# case. Read the actual reason_log and chosen tile from the real run;
# don't assume the predictions here are correct just because they're
# written down.
#
# Run:
#   "$GODOT" --headless --path . --script res://set_vs_make_path_b_trace.gd
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

# Seat0: 0:6, 1:2 (test lead), 1:6 (held back, unplayed — part of why
#   guaranteed_win stays false), 2:2/2:3/2:4/2:5 (suit-2 fillers, kept
#   off every other seat so nobody else can accidentally follow/beat
#   suit 2, and 2:3 gets spent in setup A so it isn't sitting there
#   looking like an alternative lead).
# Seat1: no pip-2, no pip-6 tiles anywhere in hand — the seat whose
#   void status is under test.
# Seat2 (Partner): 0:2 (setup A lead), the 5 remaining trump, 5:5
#   (dumpable counter).
# Seat3: no pip-2, no pip-6 — can't beat 1:2 regardless of forced-follow.
func _hands() -> Array:
	var p0 = _hand_from_pairs([[0,6],[1,2],[1,6],[2,2],[2,3],[2,4],[2,5]])
	var p1 = _hand_from_pairs([[0,0],[0,1],[0,3],[1,1],[1,3],[3,3],[4,4]])
	var p2 = _hand_from_pairs([[0,2],[2,6],[3,6],[4,6],[5,6],[6,6],[5,5]])
	var p3 = _hand_from_pairs([[0,4],[0,5],[1,4],[1,5],[3,4],[3,5],[4,5]])
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

func _play_and_log(game: Game, seat: int, tile: Domino, label: String):
	var player = game.players[seat]
	game.play_domino(player, tile)
	_log("    P%d plays %s (%s)" % [seat, tile.debug_string(), label])

func _finish_trick(game: Game, trick_label: String):
	var winner_id = game.resolve_trick()
	game.record_trick(game.current_trick, winner_id, game.current_trick.plays)
	_log("  %s winner: P%d" % [trick_label, winner_id])

# Setup Trick A — Partner leads suit 2 (0:2). Order for leader=2 is
# [2,1,0,3]. Seat1 plays 2nd and is void in suit 2 by hand construction
# — this is the void reveal. Seat0 is NOT void (holds several suit-2
# tiles) so must deliberately avoid playing 1:2 here; we pick 2:3.
func _run_setup_a(game: Game):
	game.start_trick(PARTNER_SEAT)
	_log("  Setup A (lead suit 2, leader P2):")
	_play_and_log(game, 2, _find(game.players[2].hand, 0, 2), "lead")
	_play_and_log(game, 1, _find(game.players[1].hand, 0, 0), "void in suit 2 — reveal")
	_play_and_log(game, 0, _find(game.players[0].hand, 2, 3), "follows suit 2")
	_play_and_log(game, 3, _find(game.players[3].hand, 0, 4), "discard")
	_finish_trick(game, "Setup A")

# Setup Trick B — seat0 leads trump (0:6). Order for leader=0 is
# [0,3,2,1]. Seat1 plays last and is void in trump by hand construction
# — the second void reveal. Partner is NOT void in trump (holds 5) so
# is forced to follow — we pick 2:6 (arbitrary; must_follow leaves no
# other legal choice here anyway).
func _run_setup_b(game: Game):
	game.start_trick(HUMAN_SEAT)
	_log("  Setup B (lead trump, leader P0):")
	_play_and_log(game, 0, _find(game.players[0].hand, 0, 6), "lead trump")
	_play_and_log(game, 3, _find(game.players[3].hand, 0, 5), "void in trump — discard")
	_play_and_log(game, 2, _find(game.players[2].hand, 2, 6), "forced to follow trump")
	_play_and_log(game, 1, _find(game.players[1].hand, 0, 1), "void in trump — reveal")
	_finish_trick(game, "Setup B")

func _run_test_trick(game: Game, label: String) -> Dictionary:
	game.start_trick(HUMAN_SEAT)
	_log("  Test trick (lead 1:2, leader P0):")

	var lead_tile = _find(game.players[0].hand, 1, 2)
	_play_and_log(game, 0, lead_tile, "human leads")

	var p3_legal = game.get_legal_moves(game.players[3])
	var p3_tile = p3_legal[0]
	_play_and_log(game, 3, p3_tile, "discard")

	var partner = game.players[PARTNER_SEAT]
	var legal = game.get_legal_moves(partner)
	var reason_log: Array = []
	var frame = PublicFrame.new(game.hand_history, game.current_trick)
	var knowledge = PublicKnowledge.from_state(frame)

	_log("  Partner (P2) hand at decision: %s" % ", ".join(partner.hand.map(func(d): return d.debug_string())))
	_log("  Partner legal moves: %s" % ", ".join(legal.map(func(d): return d.debug_string())))
	_log("  void_suits(P1) per PublicKnowledge: %s" % [knowledge.void_suits(1)])

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
		"partner_chosen": chosen.debug_string(),
		"partner_reason": reason,
		"dumped_5_5": chosen.debug_string() == "5:5"
	}

func _run_scenario(label: String, bidder_seat: int, include_setup_b: bool) -> Dictionary:
	_log("")
	_log("═══════════════════════════════════════════════════════════")
	_log("SCENARIO %s — bidder_seat=P%d, setup_b=%s" % [label, bidder_seat, include_setup_b])
	_log("═══════════════════════════════════════════════════════════")

	var game = _setup_game(bidder_seat)
	_run_setup_a(game)
	if include_setup_b:
		_run_setup_b(game)

	var our_team = PARTNER_SEAT % 2
	var bidder_team = bidder_seat % 2
	_log("  our_team(P2)=%d  bidder_team=%d  is_defending=%s" % [our_team, bidder_team, our_team != bidder_team])

	var result = _run_test_trick(game, label)
	result["bidder_seat"] = bidder_seat
	result["is_defending"] = our_team != bidder_team
	result["setup_b_run"] = include_setup_b
	return result

func _init():
	trace_lines.clear()
	var results := {}

	# POSITIVE — seat1 proven void in BOTH suit 2 and trump.
	# Predicted (derived by hand, NOT confirmed): guaranteed_win false;
	# win_safe_against_remaining true via Path B. MAKE should stay
	# unaffected (is_defending gates it out regardless); SET should dump
	# 5:5 with the new reason string.
	results["path_b_positive_MAKE"] = _run_scenario("path_b_positive_MAKE", HUMAN_SEAT, true)
	results["path_b_positive_SET"] = _run_scenario("path_b_positive_SET", 1, true)

	# NEGATIVE — seat1 proven void in suit 2 ONLY; trump status unknown.
	# Predicted: win_safe_against_remaining false regardless of
	# is_defending, since Path B's trump check has nothing to confirm.
	# MAKE and SET should behave IDENTICALLY here — that identity is the
	# actual safety property under test.
	results["path_b_negative_MAKE"] = _run_scenario("path_b_negative_MAKE", HUMAN_SEAT, false)
	results["path_b_negative_SET"] = _run_scenario("path_b_negative_SET", 1, false)

	results["full_log"] = trace_lines

	var f = FileAccess.open("res://set_vs_make_path_b_trace_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "\t"))
	f.close()

	print("")
	print("Results written to res://set_vs_make_path_b_trace_results.json")
	quit(0)
