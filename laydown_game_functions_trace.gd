extends SceneTree

# ═══════════════════════════════════════════════════════════════════════════
# laydown_game_functions_trace.gd — smoke test for game.gd's two new
# lay-down functions (July 22, 2026): is_contract_already_lost() and
# resolve_hand_via_laydown(). Covers the parts of the spec's suggested
# smoke test that are headlessly testable — button visibility/UI wiring
# needs an interactive session and isn't covered here.
#
# Run:
#   "$GODOT" --headless --path . --script res://laydown_game_functions_trace.gd
# ═══════════════════════════════════════════════════════════════════════════

const BidScript = preload("res://bid.gd")

var failures: Array = []
var log_lines: Array = []

func _log(s: String):
	log_lines.append(s)
	print(s)

func _check(label: String, condition: bool, detail: String) -> void:
	if condition:
		_log("  PASS: %s — %s" % [label, detail])
	else:
		_log("  FAIL: %s — %s" % [label, detail])
		failures.append(label)

# Builds a Game with a fabricated hand_history — enough for
# is_contract_already_lost() to read winner_id off each record. Trick
# contents don't matter (never read), only the "winner_id" key.
func _game_with_history(bid_type: int, bid_value: int, bidder_id: int, winner_ids: Array) -> Game:
	var game = Game.new()
	game.setup_players(0)
	var bid = BidScript.new(bid_type, bid_value, bidder_id)
	game.current_bid = bid
	game.variant = bid_type
	for wid in winner_ids:
		game.hand_history.append({"winner_id": wid})
	return game

func _init():
	_log("═══════════════════════════════════════════════════════════")
	_log("is_contract_already_lost()")
	_log("═══════════════════════════════════════════════════════════")

	# Points: no equivalent concept — always false regardless of history.
	var g1 = _game_with_history(BidScript.Type.POINTS, 31, 0, [1, 1, 1])
	_check("points_always_false", g1.is_contract_already_lost(0) == false,
		"Points bid, opposing team won every trick so far, still false (no early-loss concept for Points)")

	# Marks: bidder's team (0, i.e. seats 0/2) must win ALL 7 -- one trick
	# won by the other team (winner_id=1, team 1) already ends it.
	var g2 = _game_with_history(BidScript.Type.MARKS, 2, 0, [0, 2, 1])
	_check("marks_lost_after_one_opposing_trick", g2.is_contract_already_lost(0) == true,
		"seat 0 (team 0) claims, but trick 3 was won by seat 1 (team 1) -- already lost")

	var g3 = _game_with_history(BidScript.Type.MARKS, 2, 0, [0, 2, 0])
	_check("marks_not_lost_if_all_tricks_stayed_with_bidding_team", g3.is_contract_already_lost(0) == false,
		"every trick so far won by team 0 (seats 0/2) -- not lost yet")

	# Sevens: same all-7-tricks shape as Marks.
	var g4 = _game_with_history(BidScript.Type.SEVENS, 1, 0, [3])
	_check("sevens_lost_after_one_opposing_trick", g4.is_contract_already_lost(0) == true,
		"seat 3 (team 1) won a trick against team 0's Sevens claim -- already lost")

	# Plunge/Splash: the actual gap this function exists to close --
	# _is_bid_mathematically_set() doesn't check these today.
	var g5 = _game_with_history(BidScript.Type.PLUNGE, 4, 2, [2, 1, 2])
	_check("plunge_lost_after_one_opposing_trick", g5.is_contract_already_lost(2) == true,
		"bidder seat 2 (team 0), but trick 2 won by seat 1 (team 1) -- Plunge needs all 7, already lost")

	var g6 = _game_with_history(BidScript.Type.SPLASH, 3, 2, [0, 2, 0])
	_check("splash_not_lost_if_all_tricks_stayed_with_bidding_team", g6.is_contract_already_lost(2) == false,
		"every trick so far won by team 0 -- Splash still alive")

	# Nello: bidder catching ANY trick (not the opposing team) is the loss
	# condition -- inverted shape from Marks/Sevens/Plunge/Splash.
	var g7 = _game_with_history(BidScript.Type.NELLO, 1, 1, [1])
	_check("nello_lost_if_bidder_catches_a_trick", g7.is_contract_already_lost(1) == true,
		"Nello bidder (seat 1) caught a trick -- fails immediately")

	var g8 = _game_with_history(BidScript.Type.NELLO, 1, 1, [0, 2, 3])
	_check("nello_not_lost_if_bidder_never_caught_a_trick", g8.is_contract_already_lost(1) == false,
		"bidder (seat 1) never won a trick -- Nello still alive")

	# Null bid -- defensive default.
	var g9 = Game.new()
	g9.setup_players(0)
	_check("null_current_bid_returns_false", g9.is_contract_already_lost(0) == false,
		"no current_bid at all -- defensively false, not a crash")

	_log("")
	_log("═══════════════════════════════════════════════════════════")
	_log("resolve_hand_via_laydown()")
	_log("═══════════════════════════════════════════════════════════")

	# Points: mark value is always exactly 1, regardless of the bid's point value.
	var p1 = _game_with_history(BidScript.Type.POINTS, 31, 0, [])
	var r1 = p1.resolve_hand_via_laydown(0, true)
	_check("points_correct_claim_awards_1_mark_to_claimant_team",
		r1["winner"] == 0 and r1["team_marks"][0] == 1 and r1["team_marks"][1] == 0,
		"claimant seat 0 (team 0) correct -> team_marks=%s, winner=%s" % [r1["team_marks"], r1["winner"]])

	var p2 = _game_with_history(BidScript.Type.POINTS, 31, 0, [])
	var r2 = p2.resolve_hand_via_laydown(0, false)
	_check("points_incorrect_claim_awards_1_mark_to_other_team",
		r2["winner"] == 1 and r2["team_marks"][1] == 1 and r2["team_marks"][0] == 0,
		"claimant seat 0 wrong -> team_marks=%s, winner=%s" % [r2["team_marks"], r2["winner"]])

	# Marks/Nello/Sevens/Plunge/Splash: mark value matches current_bid.value.
	for case in [
		{"type": BidScript.Type.MARKS, "value": 3},
		{"type": BidScript.Type.NELLO, "value": 1},
		{"type": BidScript.Type.SEVENS, "value": 1},
		{"type": BidScript.Type.PLUNGE, "value": 4},
		{"type": BidScript.Type.SPLASH, "value": 2},
	]:
		var g_correct = _game_with_history(case["type"], case["value"], 2, [])
		var res_correct = g_correct.resolve_hand_via_laydown(2, true)
		_check("mark_value_matches_bid_value_correct_type_%d" % case["type"],
			res_correct["winner"] == 0 and res_correct["team_marks"][0] == case["value"],
			"type=%d value=%d, claimant seat 2 (team 0) correct -> team_marks=%s" % [case["type"], case["value"], res_correct["team_marks"]])

		var g_wrong = _game_with_history(case["type"], case["value"], 2, [])
		var res_wrong = g_wrong.resolve_hand_via_laydown(2, false)
		_check("mark_value_matches_bid_value_wrong_type_%d" % case["type"],
			res_wrong["winner"] == 1 and res_wrong["team_marks"][1] == case["value"],
			"type=%d value=%d, claimant seat 2 wrong -> team_marks=%s" % [case["type"], case["value"], res_wrong["team_marks"]])

	# Result dict shape sanity -- both team_marks and team_points present
	# (team_points untouched, per spec: "left untouched").
	var g10 = _game_with_history(BidScript.Type.POINTS, 30, 0, [])
	var r10 = g10.resolve_hand_via_laydown(0, true)
	_check("result_shape_has_all_expected_keys",
		r10.has("winner") and r10.has("reason") and r10.has("team_marks") and r10.has("team_points"),
		"keys present: %s" % [r10.keys()])
	_check("team_points_left_untouched",
		r10["team_points"][0] == 0 and r10["team_points"][1] == 0,
		"team_points=%s (should be untouched, still [0,0])" % [r10["team_points"]])

	# Claimant on the "Them" side (team 1) -- confirms team math isn't
	# hardcoded to team 0.
	var g11 = _game_with_history(BidScript.Type.MARKS, 2, 1, [])
	var r11 = g11.resolve_hand_via_laydown(3, true)
	_check("claimant_from_team_1_wins_for_team_1",
		r11["winner"] == 1 and r11["team_marks"][1] == 2 and r11["team_marks"][0] == 0,
		"claimant seat 3 (team 1) correct -> team_marks=%s, winner=%s" % [r11["team_marks"], r11["winner"]])

	_log("")
	_log("═══════════════════════════════════════════════════════════")
	if failures.is_empty():
		_log("ALL CHECKS PASSED")
	else:
		_log("FAILURES: %s" % [failures])
	_log("═══════════════════════════════════════════════════════════")

	var output = {
		"failures": failures,
		"full_log": log_lines,
	}
	var f = FileAccess.open("res://laydown_game_functions_trace_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(output, "\t"))
	f.close()

	print("")
	print("Results written to res://laydown_game_functions_trace_results.json")
	quit(0 if failures.is_empty() else 1)
