extends SceneTree
# Job 2: Partner trump "ceiling" vs. "quantity" experiment.
# Run with: godot --headless --path . --script res://headless/job2_ceiling_vs_quantity.gd
#
# Read-only w.r.t. the live game files — only calls existing Game/AIPlayer
# APIs. Results are written to scripts/job2_results.json directly (not via
# stdout) so the batch run's stdout (which includes game.gd's unconditional
# per-trick print() calls) never needs to be captured/parsed.

const BidScript = preload("res://bid.gd")

const TRUMP_SUIT := 6          # sixes trump
const BID_VALUE := 30          # Points contract
const BIDDER_SEAT := 0
const PARTNER_SEAT := 2        # (BIDDER_SEAT + 2) % 4 — bidder's teammate
const N_TRIALS := 1000

# Ceiling: top 2 trump (double + next-highest rank) — 6:6, 6:5 — plus
# deliberate off-suit filler: 3 off-suit doubles (5:5, 4:4, 3:3) and 2
# suited-5 tiles (4:5, 2:5). Gated via AIPlayer.evaluate_hand(): 29.16
# estimated_points. 4 total doubles in hand (the trump double + 3 off-suit).
const CEILING_PARTNER_TILES := [[6,6],[6,5],[5,5],[4,4],[3,3],[4,5],[2,5]]

# Quantity: 5 trump (missing only the double 6:6) plus deliberate off-suit
# filler: 1 off-suit double (5:5) and one suited-5 tile (2:5). Gated via
# AIPlayer.evaluate_hand(): 26.81 estimated_points. 2 total doubles in hand
# (no trump double — 6:6 isn't held — plus the 1 off-suit double).
const QUANTITY_PARTNER_TILES := [[6,5],[6,4],[6,3],[6,2],[6,1],[5,5],[2,5]]

func _doubles_count(partner_tiles: Array) -> int:
	var n = 0
	for pair in partner_tiles:
		if pair[0] == pair[1]:
			n += 1
	return n

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

# Builds a Game with Partner's hand pinned to the archetype's tile list and
# the other three seats dealt randomly from the remaining 21 tiles.
func _setup_game(partner_tiles: Array) -> Game:
	var game = Game.new()
	game.setup_players(0)
	game.deal_hands()  # for the usual per-hand resets; hands overwritten below

	var pool = _build_full_deck()
	var partner_hand: Array[Domino] = []
	for pair in partner_tiles:
		partner_hand.append(_take(pool, pair[0], pair[1]))
	pool.shuffle()

	var other_seats: Array = []
	for s in range(4):
		if s != PARTNER_SEAT:
			other_seats.append(s)

	game.players[PARTNER_SEAT].hand = partner_hand
	var idx = 0
	for s in other_seats:
		var h: Array[Domino] = []
		for k in range(7):
			h.append(pool[idx])
			idx += 1
		game.players[s].hand = h

	return game

# Same orchestration loop confirmed viable in Job 1
# (scripts/headless_test_job1.gd / scripts/headless_timing_test.gd):
# turn order advances via (current_player + 3) % 4, decide_play() is called
# directly per seat per turn, resolve_trick()/record_trick() close out each
# trick, resolve_hand() scores at the end.
func _play_trial(partner_tiles: Array) -> Dictionary:
	var game = _setup_game(partner_tiles)
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
				game.settings.ai_difficulty,
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
		game.record_trick(game.current_trick, winner_id, [])
		leader = winner_id

	var result = game.resolve_hand()
	var bid_team = BIDDER_SEAT % 2
	var bid_points = result["team_points"][bid_team]
	return {
		"win": bid_points >= BID_VALUE,
		"margin": bid_points - BID_VALUE,
		"bid_points": bid_points,
	}

func _run_archetype(name: String, partner_tiles: Array, n: int) -> Dictionary:
	var wins = 0
	var margins: Array = []
	for i in range(n):
		var r = _play_trial(partner_tiles)
		if r["win"]:
			wins += 1
		margins.append(r["margin"])
	margins.sort()

	var sum_m = 0
	for m in margins:
		sum_m += m
	var mean_margin = float(sum_m) / n

	var buckets: Dictionary = {}
	for m in margins:
		var bucket = int(floor(float(m) / 5.0)) * 5
		var key = str(bucket)
		buckets[key] = buckets.get(key, 0) + 1

	return {
		"name": name,
		"n": n,
		"wins": wins,
		"win_rate": float(wins) / n,
		"mean_margin": mean_margin,
		"median_margin": margins[n / 2],
		"min_margin": margins[0],
		"max_margin": margins[-1],
		"margin_bucket_histogram": buckets,  # bucket key = bucket floor, width 5
	}

func _init():
	var t0 = Time.get_ticks_msec()
	var ceiling_eval = AIPlayer.evaluate_hand(_make_hand(CEILING_PARTNER_TILES), TRUMP_SUIT)
	var quantity_eval = AIPlayer.evaluate_hand(_make_hand(QUANTITY_PARTNER_TILES), TRUMP_SUIT)
	var ceiling_result = _run_archetype("ceiling", CEILING_PARTNER_TILES, N_TRIALS)
	var quantity_result = _run_archetype("quantity", QUANTITY_PARTNER_TILES, N_TRIALS)
	var elapsed = Time.get_ticks_msec() - t0

	ceiling_result["estimated_points"] = ceiling_eval["estimated_points"]
	ceiling_result["doubles_count"] = _doubles_count(CEILING_PARTNER_TILES)
	quantity_result["estimated_points"] = quantity_eval["estimated_points"]
	quantity_result["doubles_count"] = _doubles_count(QUANTITY_PARTNER_TILES)

	var out = {
		"trump_suit": TRUMP_SUIT,
		"bid_value": BID_VALUE,
		"bidder_seat": BIDDER_SEAT,
		"partner_seat": PARTNER_SEAT,
		"ceiling_partner_tiles": CEILING_PARTNER_TILES,
		"quantity_partner_tiles": QUANTITY_PARTNER_TILES,
		"n_trials_per_archetype": N_TRIALS,
		"elapsed_ms": elapsed,
		"ceiling": ceiling_result,
		"quantity": quantity_result,
	}

	var f = FileAccess.open("res://headless/job2_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()

	print("Done. Results written to scripts/job2_results.json")
	print("Ceiling:  win_rate=%.1f%% mean_margin=%.2f est_pts=%.2f doubles=%d (n=%d)" % [
		ceiling_result["win_rate"] * 100, ceiling_result["mean_margin"], ceiling_result["estimated_points"], ceiling_result["doubles_count"], N_TRIALS])
	print("Quantity: win_rate=%.1f%% mean_margin=%.2f est_pts=%.2f doubles=%d (n=%d)" % [
		quantity_result["win_rate"] * 100, quantity_result["mean_margin"], quantity_result["estimated_points"], quantity_result["doubles_count"], N_TRIALS])
	print("Elapsed: %d ms" % elapsed)

	quit(0)

func _make_hand(tiles: Array) -> Array[Domino]:
	var hand: Array[Domino] = []
	for pair in tiles:
		hand.append(Domino.new(pair[0], pair[1]))
	return hand
