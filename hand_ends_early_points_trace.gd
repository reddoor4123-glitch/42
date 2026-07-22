extends SceneTree

# ═══════════════════════════════════════════════════════════════════════════
# hand_ends_early_points_trace.gd — smoke test for game.gd's
# is_points_bid_decided() (July 22, 2026). Covers the headless-testable
# cases from the Hand-Ends-Early spec's suggested smoke test. The
# game_table.gd-level cases (toggle-off behavior, the Plunge/Splash gap
# actually closing) need an interactive session or a scripted full-play
# SceneTree and aren't covered here.
#
# Run:
#   "$GODOT" --headless --path . --script res://hand_ends_early_points_trace.gd
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

func _game_with_points(bid_value: int, bidder_id: int, team0_points: int, team1_points: int, trump: int = 6) -> Game:
	var game = Game.new()
	game.setup_players(0)
	var bid = BidScript.new(BidScript.Type.POINTS, bid_value, bidder_id)
	game.current_bid = bid
	game.variant = BidScript.Type.POINTS
	game.trump = trump
	game.team_points[0] = team0_points
	game.team_points[1] = team1_points
	return game

func _init():
	_log("═══════════════════════════════════════════════════════════")
	_log("is_points_bid_decided()")
	_log("═══════════════════════════════════════════════════════════")

	# Achieved early: bid 30, bidding team (seat 0, team 0) already at 31.
	var g1 = _game_with_points(30, 0, 31, 5)
	_check("points_achieved_early", g1.is_points_bid_decided() == true,
		"bid=30, team0=31, team1=5 -- already achieved (31 >= 30)")

	# Set early: bid 42, bidding team at 5, other team at 30. Remaining =
	# 42-5-30=7. bid_team(5) + remaining(7) = 12 < 42 -- can never reach it.
	var g2 = _game_with_points(42, 0, 5, 30)
	_check("points_set_early", g2.is_points_bid_decided() == true,
		"bid=42, team0=5, team1=30, remaining=7 -- 5+7=12 < 42, already set")

	# Genuinely undecided: bid 30, team0=10, team1=10. Remaining=22.
	# team0 could still reach 30 (10+22=32>=30) and hasn't already (10<30).
	var g3 = _game_with_points(30, 0, 10, 10)
	_check("points_genuinely_undecided", g3.is_points_bid_decided() == false,
		"bid=30, team0=10, team1=10, remaining=22 -- neither threshold crossed")

	# Follow Me sanity check: trump=-1 (no-trump), otherwise identical to a
	# normal Points bid. is_points_bid_decided() never reads trump at all,
	# so this must behave identically to g1/g2/g3 above.
	var g4 = _game_with_points(30, 0, 31, 5, -1)
	_check("follow_me_achieved_early_no_special_casing_needed", g4.is_points_bid_decided() == true,
		"same as points_achieved_early but trump=-1 (Follow Me) -- identical result")

	var g5 = _game_with_points(30, 0, 10, 10, -1)
	_check("follow_me_undecided_no_special_casing_needed", g5.is_points_bid_decided() == false,
		"same as points_genuinely_undecided but trump=-1 (Follow Me) -- identical result")

	# Claimant/bidder on team 1 -- confirms bid_team math isn't hardcoded to team 0.
	var g6 = _game_with_points(31, 1, 5, 32)
	_check("bidder_on_team_1_achieved_early", g6.is_points_bid_decided() == true,
		"bidder seat 1 (team 1), team1=32 -- already achieved (32 >= 31)")

	var g7 = _game_with_points(35, 3, 20, 2)
	_check("bidder_on_team_1_set_early", g7.is_points_bid_decided() == true,
		"bidder seat 3 (team 1), team1=2, team0=20, remaining=20 -- 2+20=22 < 35, already set")

	# Non-Points bids: no equivalent concept, always false regardless of points.
	var g8 = Game.new()
	g8.setup_players(0)
	g8.current_bid = BidScript.new(BidScript.Type.MARKS, 2, 0)
	g8.variant = BidScript.Type.MARKS
	g8.team_points[0] = 42
	_check("marks_bid_always_false", g8.is_points_bid_decided() == false,
		"Marks bid, even with team_points maxed out -- Points-only check doesn't apply")

	# Null bid -- defensive default.
	var g9 = Game.new()
	g9.setup_players(0)
	_check("null_current_bid_returns_false", g9.is_points_bid_decided() == false,
		"no current_bid at all -- defensively false, not a crash")

	# Exact-boundary cases: right at the threshold, not past it.
	var g10 = _game_with_points(30, 0, 30, 5)
	_check("exactly_at_bid_value_counts_as_achieved", g10.is_points_bid_decided() == true,
		"team0=30, bid=30 -- >= comparison means exactly hitting the bid counts as achieved")

	var g11 = _game_with_points(42, 0, 0, 0)
	_check("exact_boundary_not_yet_set_when_still_reachable", g11.is_points_bid_decided() == false,
		"bid=42, team0=0, team1=0, remaining=42 -- 0+42=42, not < 42, still reachable")

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
	var f = FileAccess.open("res://hand_ends_early_points_trace_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(output, "\t"))
	f.close()

	print("")
	print("Results written to res://hand_ends_early_points_trace_results.json")
	quit(0 if failures.is_empty() else 1)
