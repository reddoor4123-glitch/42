extends SceneTree
# Job 3, Steps 2-6: fixed bid-worthy bidder hand, per-tile empirical profile.
# Bidder's hand (from Step 1) is held fixed every trial; the other 21 tiles
# are reshuffled across Partner/Opponents each trial. Contract (Points,
# trump=5, bid=30) comes directly from Step 1's decide_bid() result.
#
# Run with: godot --headless --path . --script res://headless/job3_experiment.gd
#
# NOTE on record_trick(): Job 1/2's scripts passed [] as the
# plays_with_reasons argument, which leaves hand_history's "plays" field
# empty (game.gd stores whatever is passed in, not trick.plays itself).
# This script passes game.current_trick.plays directly — that array already
# holds {"player":..., "domino":...} per play, in order, which is exactly
# the plays_with_reasons shape record_trick expects.

const BidScript = preload("res://bid.gd")

const TRUMP_SUIT := 5           # fives trump — from Step 1's best_trump()
const BID_VALUE := 30           # target_bid from Step 1
const BIDDER_SEAT := 0
const PARTNER_SEAT := 2         # (BIDDER_SEAT + 2) % 4
const N_TRIALS := 1000
const DIFFICULTY := "expert"    # uniform across all 4 seats — see Job 3 brief Step 3

# Fixed bidder hand from Step 1 (scripts/job3_fixed_hand.json).
const FIXED_BIDDER_TILES := [[5,5],[3,5],[0,5],[2,4],[4,5],[3,4],[5,6]]

func _tile_key(d: Domino) -> String:
	return "%d:%d" % [d.left, d.right]

func _build_full_deck() -> Array:
	var pool: Array = []
	for a in range(0, 7):
		for b in range(a, 7):
			pool.append(Domino.new(a, b))
	return pool

func _take(pool: Array, a: int, b: int) -> Domino:
	var lo = min(a, b)
	var hi = max(a, b)
	for i in range(pool.size()):
		var d: Domino = pool[i]
		if d.left == lo and d.right == hi:
			pool.remove_at(i)
			return d
	push_error("Tile %d:%d not found in pool" % [a, b])
	return null

# Bidder's hand pinned to FIXED_BIDDER_TILES; the other 21 tiles shuffled
# randomly across Partner (seat 2) and both Opponents (seats 1, 3).
func _setup_game() -> Game:
	var game = Game.new()
	game.setup_players(0)
	game.deal_hands()  # per-hand resets; hands overwritten below

	var pool = _build_full_deck()
	var bidder_hand: Array[Domino] = []
	for pair in FIXED_BIDDER_TILES:
		bidder_hand.append(_take(pool, pair[0], pair[1]))
	pool.shuffle()

	game.players[BIDDER_SEAT].hand = bidder_hand
	var other_seats = [1, 2, 3]
	var idx = 0
	for s in other_seats:
		var h: Array[Domino] = []
		for k in range(7):
			h.append(pool[idx])
			idx += 1
		game.players[s].hand = h

	return game

# Same orchestration loop confirmed in Job 1/Job 2 — turn order via
# (current_player + 3) % 4, decide_play() called directly per seat/turn.
func _play_trial() -> Dictionary:
	var game = _setup_game()
	var bid = BidScript.new(BidScript.Type.POINTS, BID_VALUE, BIDDER_SEAT)
	game.current_bid = bid
	game.apply_bid_result(TRUMP_SUIT)

	var leader = BIDDER_SEAT
	for trick_num in range(7):
		game.start_trick(leader)
		for turn in range(4):
			var player = game.players[game.current_player]
			var legal = game.get_legal_moves(player)
			var partner_id = (player.id + 2) % 4
			var is_partner = (player.id == PARTNER_SEAT)
			var reason_log: Array = []
			var frame = PublicFrame.new(game.hand_history, game.current_trick)
			var knowledge = PublicKnowledge.from_state(frame)
			var chosen = AIPlayer.decide_play(
				legal, player.hand, game.current_trick,
				player.id, partner_id, game.trump, reason_log,
				DIFFICULTY,
				is_partner,
				game.variant,
				game.current_bid.player_id,
				knowledge,
				game.team_points,
				game.current_bid.value
			)
			game.play_domino(player, chosen)
			game.current_player = (game.current_player + 3) % 4
		var winner_id = game.resolve_trick()
		game.record_trick(game.current_trick, winner_id, game.current_trick.plays)
		leader = winner_id

	var result = game.resolve_hand()
	var bid_team = BIDDER_SEAT % 2
	var bid_points = result["team_points"][bid_team]

	return {
		"win": bid_points >= BID_VALUE,
		"margin": bid_points - BID_VALUE,
		"bid_points": bid_points,
		"hand_history": game.hand_history,
	}

func _init():
	var t0 = Time.get_ticks_msec()

	var wins = 0
	var margins: Array = []

	# Per-tile accumulators, keyed by "lo:hi".
	var tile_stats: Dictionary = {}
	for pair in FIXED_BIDDER_TILES:
		var key = "%d:%d" % [min(pair[0], pair[1]), max(pair[0], pair[1])]
		tile_stats[key] = {
			"times_played": 0,
			"times_won": 0,
			"counter_points_total": 0,
			"times_led": 0,
			"times_led_opp_won": 0,
		}

	for i in range(N_TRIALS):
		var r = _play_trial()
		if r["win"]:
			wins += 1
		margins.append(r["margin"])

		for trick_record in r["hand_history"]:
			var plays: Array = trick_record["plays"]
			var winner_id: int = trick_record["winner_id"]
			var points: int = trick_record["points"]
			for j in range(plays.size()):
				var play = plays[j]
				if play["player"] != BIDDER_SEAT:
					continue
				var d: Domino = play["domino"]
				var key = _tile_key(d)
				if not tile_stats.has(key):
					continue  # shouldn't happen — bidder hand is fixed
				var stats = tile_stats[key]
				stats["times_played"] += 1
				if winner_id == BIDDER_SEAT:
					stats["times_won"] += 1
					stats["counter_points_total"] += (points - 1)
				if j == 0:  # this play led the trick
					stats["times_led"] += 1
					if winner_id % 2 != (BIDDER_SEAT % 2):
						stats["times_led_opp_won"] += 1

	margins.sort()
	var sum_m = 0
	for m in margins:
		sum_m += m
	var mean_margin = float(sum_m) / N_TRIALS

	var per_tile_report: Dictionary = {}
	for key in tile_stats.keys():
		var s = tile_stats[key]
		var win_rate = float(s["times_won"]) / s["times_played"] if s["times_played"] > 0 else 0.0
		var counter_avg_per_win = float(s["counter_points_total"]) / s["times_won"] if s["times_won"] > 0 else 0.0
		var lead_loss_rate = float(s["times_led_opp_won"]) / s["times_led"] if s["times_led"] > 0 else -1.0  # -1 = never led
		per_tile_report[key] = {
			"times_played": s["times_played"],
			"win_rate": win_rate,
			"counter_points_total": s["counter_points_total"],
			"counter_points_avg_per_win": counter_avg_per_win,
			"times_led": s["times_led"],
			"lead_loss_rate": lead_loss_rate,
		}

	var elapsed = Time.get_ticks_msec() - t0

	var out = {
		"trump_suit": TRUMP_SUIT,
		"bid_value": BID_VALUE,
		"bidder_seat": BIDDER_SEAT,
		"partner_seat": PARTNER_SEAT,
		"difficulty": DIFFICULTY,
		"fixed_bidder_tiles": FIXED_BIDDER_TILES,
		"n_trials": N_TRIALS,
		"elapsed_ms": elapsed,
		"team_win_rate": float(wins) / N_TRIALS,
		"wins": wins,
		"mean_margin": mean_margin,
		"median_margin": margins[N_TRIALS / 2],
		"min_margin": margins[0],
		"max_margin": margins[-1],
		"per_tile": per_tile_report,
	}

	var f = FileAccess.open("res://headless/job3_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()

	print("Done. Results written to scripts/job3_results.json")
	print("Team win rate: %.1f%% (%d/%d)  mean_margin=%.2f" % [out["team_win_rate"] * 100, wins, N_TRIALS, mean_margin])
	for key in per_tile_report.keys():
		var p = per_tile_report[key]
		print("%s: win_rate=%.1f%% counter_avg_per_win=%.2f lead_loss_rate=%s (led %d times)" % [
			key, p["win_rate"] * 100, p["counter_points_avg_per_win"],
			("%.1f%%" % (p["lead_loss_rate"] * 100)) if p["lead_loss_rate"] >= 0 else "N/A", p["times_led"]
		])
	print("Elapsed: %d ms" % elapsed)

	quit(0)
