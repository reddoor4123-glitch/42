extends SceneTree

# ═══════════════════════════════════════════════════════════════════════════
# nello_exchange_trace.gd — smoke test for the Nello Blind Exchange spec
# (July 20-21, 2026): select_nello_exchange_give() (ai_player.gd) and
# apply_nello_exchange() (game.gd).
#
# Covers the spec's own suggested smoke test:
#   - Each of the four doubles-mode variants (high / low / own_suit /
#     own_suit-reversed), with hands engineered to force each tier in turn.
#   - A real trade leaves both hands at 7 tiles, correctly swapped.
# Does NOT cover the UI panel or the allow_nello_exchange=false skip-to-play
# path — those live in game_table.gd and need an interactive Godot session,
# not a headless SceneTree, to exercise.
#
# Run:
#   "$GODOT" --headless --path . --script res://nello_exchange_trace.gd
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

func _hand(pairs: Array) -> Array[Domino]:
	var h: Array[Domino] = []
	for p in pairs:
		h.append(Domino.new(p[0], p[1]))
	return h

func _d(a: int, b: int) -> String:
	return "%d:%d" % [min(a,b), max(a,b)]

func _run_case(label: String, mode: String, reversed: bool, hand_pairs: Array, expected: Array) -> void:
	var hand = _hand(hand_pairs)
	var result = AIPlayer.select_nello_exchange_give(hand, mode, reversed)
	var got = [result.left, result.right]
	var got_str = _d(got[0], got[1])
	var expected_str = _d(expected[0], expected[1])
	_check(label, got_str == expected_str,
		"mode=%s reversed=%s -> expected %s, got %s" % [mode, reversed, expected_str, got_str])

func _init():
	_log("═══════════════════════════════════════════════════════════")
	_log("select_nello_exchange_give() — tier coverage across all 4 modes")
	_log("═══════════════════════════════════════════════════════════")

	# ── Universal Tier 1 (0:1) — fires regardless of mode ───────────────────
	_run_case("universal_tier1_high", "high", false,
		[[0,1],[2,3],[4,5],[3,6],[2,4],[5,6],[3,4]], [0,1])
	_run_case("universal_tier1_reversed_own_suit", "own_suit", true,
		[[0,1],[2,3],[4,5],[3,6],[2,4],[5,6],[3,4]], [0,1])

	# ── HIGH mode ────────────────────────────────────────────────────────────
	_run_case("high_tier2_0_0", "high", false,
		[[0,0],[2,3],[4,5],[3,6],[2,4],[5,6],[3,3]], [0,0])
	_run_case("high_tier3_blanks_lowest_pip", "high", false,
		[[0,3],[0,5],[2,4],[3,6],[4,6],[5,6],[2,2]], [0,3])
	_run_case("high_tier4_ones_lowest_pip", "high", false,
		[[1,4],[1,2],[2,4],[3,6],[4,6],[5,6],[2,2]], [1,2])
	_run_case("high_fallback_no_0_or_1", "high", false,
		[[2,2],[3,3],[4,4],[5,5],[6,6],[2,3],[2,4]], [2,2])

	# ── LOW mode ─────────────────────────────────────────────────────────────
	_run_case("low_tier2_0_0", "low", false,
		[[0,0],[2,3],[4,5],[3,6],[2,4],[5,6],[3,3]], [0,0])
	_run_case("low_tier3_1_1", "low", false,
		[[1,1],[2,3],[4,5],[3,6],[2,4],[5,6],[3,3]], [1,1])
	_run_case("low_tier4_blanks_lowest_pip", "low", false,
		[[0,4],[0,6],[2,4],[3,6],[4,6],[5,6],[2,2]], [0,4])
	_run_case("low_tier5_ones_nondouble_lowest_pip", "low", false,
		[[1,5],[1,3],[2,4],[3,6],[4,6],[5,6],[2,2]], [1,3])
	_run_case("low_fallback_no_0_or_1", "low", false,
		[[2,2],[3,3],[4,4],[5,5],[6,6],[2,3],[2,4]], [2,2])

	# ── OWN_SUIT (non-reversed) — same branch as LOW, string dispatch check ─
	_run_case("own_suit_tier2_0_0", "own_suit", false,
		[[0,0],[2,3],[4,5],[3,6],[2,4],[5,6],[3,3]], [0,0])
	_run_case("own_suit_tier3_1_1", "own_suit", false,
		[[1,1],[2,3],[4,5],[3,6],[2,4],[5,6],[3,3]], [1,1])
	_run_case("own_suit_tier4_blanks_lowest_pip", "own_suit", false,
		[[0,4],[0,6],[2,4],[3,6],[4,6],[5,6],[2,2]], [0,4])

	# ── OWN_SUIT REVERSED ────────────────────────────────────────────────────
	_run_case("reversed_tier2_6_6", "own_suit", true,
		[[6,6],[2,3],[4,5],[3,6],[2,4],[5,6],[3,3]], [6,6])
	_run_case("reversed_tier3_combined_pool_lowest_pip", "own_suit", true,
		[[0,4],[1,2],[2,3],[3,6],[4,6],[5,6],[2,2]], [1,2])  # 0:4(pip4) vs 1:2(pip3) -> 1:2 lower
	_run_case("reversed_fallback_no_0_1_at_all", "own_suit", true,
		[[2,2],[3,3],[4,4],[5,5],[2,3],[2,4],[2,5]], [2,2])

	# ── apply_nello_exchange() — swap correctness ───────────────────────────
	_log("")
	_log("═══════════════════════════════════════════════════════════")
	_log("apply_nello_exchange() — swap correctness")
	_log("═══════════════════════════════════════════════════════════")

	var game = Game.new()
	game.setup_players(0)
	game.deal_hands()

	var bidder_hand = _hand([[0,1],[2,3],[4,5],[3,6],[2,4],[5,6],[3,4]])
	var partner_hand = _hand([[0,0],[1,1],[2,2],[3,3],[4,4],[5,5],[6,6]])
	game.players[0].hand = bidder_hand
	game.players[2].hand = partner_hand

	var bid = BidScript.new(BidScript.Type.NELLO, 1, 0)
	game.current_bid = bid
	game.apply_bid_result(-1)

	_check("nello_solo_player_set_correctly", game.nello_solo_player == 2,
		"expected partner seat 2, got %d" % game.nello_solo_player)

	# Domino has no `==` override, so Array.erase() (used inside
	# apply_nello_exchange(), same as play_domino() elsewhere in game.gd)
	# relies on reference identity, not value equality. The real
	# game_table.gd flow always passes dominoes obtained by iterating the
	# hand itself (tile.domino from a tile built via `for d in hand:`), so
	# this test must do the same — reusing the ACTUAL object references
	# already in the hands, not constructing fresh value-equal copies.
	var bidder_give = bidder_hand.filter(func(d): return d.left == 0 and d.right == 1)[0]
	var partner_give = partner_hand.filter(func(d): return d.left == 6 and d.right == 6)[0]

	game.apply_nello_exchange(bidder_give, partner_give)

	var bidder_hand_after = game.players[0].hand
	var partner_hand_after = game.players[2].hand

	_check("bidder_hand_still_7_tiles", bidder_hand_after.size() == 7,
		"got %d tiles" % bidder_hand_after.size())
	_check("partner_hand_still_7_tiles", partner_hand_after.size() == 7,
		"got %d tiles" % partner_hand_after.size())

	var bidder_has_partner_give = bidder_hand_after.any(func(d): return d.left == 6 and d.right == 6)
	var bidder_lost_own_give = not bidder_hand_after.any(func(d): return d.left == 0 and d.right == 1)
	var partner_has_bidder_give = partner_hand_after.any(func(d): return d.left == 0 and d.right == 1)
	var partner_lost_own_give = not partner_hand_after.any(func(d): return d.left == 6 and d.right == 6)

	_check("bidder_received_partners_give_6_6", bidder_has_partner_give, "bidder hand now contains 6:6")
	_check("bidder_gave_away_0_1", bidder_lost_own_give, "bidder hand no longer contains 0:1")
	_check("partner_received_bidders_give_0_1", partner_has_bidder_give, "partner hand now contains 0:1")
	_check("partner_gave_away_6_6", partner_lost_own_give, "partner hand no longer contains 6:6")

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
	var f = FileAccess.open("res://nello_exchange_trace_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(output, "\t"))
	f.close()

	print("")
	print("Results written to res://nello_exchange_trace_results.json")
	quit(0 if failures.is_empty() else 1)
