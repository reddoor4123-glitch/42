extends SceneTree

# ═══════════════════════════════════════════════════════════════════════════
# Job 5 — Trump selection: classifying best_trump() disagreements across
# many bid-worthy hands, to learn what signals a real trump_selection_score()
# needs — NOT to re-prove the July 20, 2026 flagged-hand finding.
#
# Question this answers: when best_trump()'s #1 pick loses to another
# candidate in actual simulated play, what does the actual winner usually
# have that the chosen suit lacks — more trump control, fewer sacrificed
# off-suit doubles, a realization_bias swing, or no consistent pattern?
#
# Scope, per design discussion:
#   - Only hands where decide_bid() actually returns a POINTS bid (bid-worthy,
#     tied to a real declarer decision — same gating spirit as
#     job3_find_bidworthy_hand.gd).
#   - Most hands: simulate only the top 3 candidates by predicted
#     best_trump() score (cost control). A subsample of hands gets a full
#     7-suit sweep instead, as a spot check for whether the actual winner is
#     ever OUTSIDE the top 3 — top-3-only hands structurally cannot detect
#     that failure mode, and are logged as such.
#   - 500 trials/candidate (not 1000) — this experiment needs aggregate
#     patterns across hands, not per-hand precision.
#   - Every hand logs predicted_rank_of_actual_best (rank within the FULL
#     7-suit predicted ranking, always computable since evaluate_hand() is
#     cheap for all 7 suits regardless of simulation scope) — separates
#     "miscalibrated among close choices" from "confidently wrong."
#
# Per Headless_Harness_Reference.md conventions — DIFFICULTY="expert"
# everywhere, is_partner only true for PARTNER_SEAT, turn order is
# (current_player + 3) % 4, record_trick's 3rd arg is current_trick.plays,
# stdout unused, results written to JSON only.
# ═══════════════════════════════════════════════════════════════════════════

const BidScript = preload("res://bid.gd")

const BIDDER_SEAT := 0
const PARTNER_SEAT := 2
const DIFFICULTY := "expert"

const TRIALS_PER_CANDIDATE := 500
const N_QUALIFYING_HANDS_TARGET := 40
const N_FULL_SWEEP_TARGET := 15          # spot-check cap
const MAX_SEARCH_ATTEMPTS := 3000        # safety cap on the bid-worthy search
const REALIZATION_SHIFT_THRESHOLD := 1.0 # tag threshold, see classification below

func _build_full_deck() -> Array:
	var pool: Array = []
	for a in range(0, 7):
		for b in range(a, 7):
			pool.append(Domino.new(a, b))
	return pool

func _take(pool: Array, a: int, b: int) -> Domino:
	var lo = min(a, b); var hi = max(a, b)
	for i in range(pool.size()):
		var d: Domino = pool[i]
		if d.left == lo and d.right == hi:
			pool.remove_at(i)
			return d
	push_error("Tile %d:%d not found in pool" % [a, b])
	return null

func _tiles_to_hand(tiles: Array) -> Array[Domino]:
	var hand: Array[Domino] = []
	for t in tiles:
		hand.append(Domino.new(t[0], t[1]))
	return hand

func _random_hand_tiles() -> Array:
	var pool = _build_full_deck()
	pool.shuffle()
	var tiles := []
	for i in range(7):
		var d: Domino = pool[i]
		tiles.append([d.left, d.right])
	return tiles

func _off_suit_doubles_count(hand: Array[Domino], trump: int) -> int:
	var count := 0
	for d in hand:
		if d.is_double() and not d.is_trump(trump):
			count += 1
	return count

# Full 7-suit predicted ranking for a hand — cheap (no simulation), always
# computed regardless of how many candidates get actually simulated below.
func _full_predicted_ranking(hand: Array[Domino]) -> Array:
	var ranking := []
	for s in range(7):
		var eval = AIPlayer.evaluate_hand(hand, s)
		var score = eval["estimated_points"] + eval["trump_count"] * 2.0 \
			+ (3.0 if eval.get("has_double_trump", false) else 0.0)
		ranking.append({
			"trump": s,
			"score": score,
			"estimated_points": eval["estimated_points"],
			"trump_count": eval["trump_count"],
			"has_double_trump": eval.get("has_double_trump", false),
			"off_suit_doubles_count": _off_suit_doubles_count(hand, s),
			"realization_bias": eval["realization_bias"]
		})
	ranking.sort_custom(func(a, b): return a["score"] > b["score"])
	return ranking

# Pre-generate N deals for seats 1/2/3 once per hand, reused identically
# across every tested candidate for that hand (paired design).
func _generate_deals(bidder_tiles: Array, n: int) -> Array:
	var deals := []
	for t in range(n):
		var pool = _build_full_deck()
		for tile in bidder_tiles:
			_take(pool, tile[0], tile[1])
		pool.shuffle()
		var hand1 := []; var hand2 := []; var hand3 := []
		for i in range(7):
			var d: Domino = pool[i]; hand1.append([d.left, d.right])
		for i in range(7, 14):
			var d: Domino = pool[i]; hand2.append([d.left, d.right])
		for i in range(14, 21):
			var d: Domino = pool[i]; hand3.append([d.left, d.right])
		deals.append({"seat1": hand1, "seat2": hand2, "seat3": hand3})
	return deals

func _play_trial(bidder_tiles: Array, trump: int, bid_value: int, deal: Dictionary) -> int:
	var game = Game.new()
	game.setup_players(0)
	game.deal_hands()

	game.players[BIDDER_SEAT].hand = _tiles_to_hand(bidder_tiles)
	game.players[1].hand = _tiles_to_hand(deal["seat1"])
	game.players[PARTNER_SEAT].hand = _tiles_to_hand(deal["seat2"])
	game.players[3].hand = _tiles_to_hand(deal["seat3"])

	var bid = BidScript.new(BidScript.Type.POINTS, bid_value, BIDDER_SEAT)
	game.current_bid = bid
	game.apply_bid_result(trump)

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
				DIFFICULTY, is_partner, game.variant,
				game.current_bid.player_id, knowledge,
				game.team_points, game.current_bid.value
			)
			game.play_domino(player, chosen)
			game.current_player = (game.current_player + 3) % 4
		var winner_id = game.resolve_trick()
		game.record_trick(game.current_trick, winner_id, game.current_trick.plays)
		leader = winner_id

	var result = game.resolve_hand()
	return result["team_points"][BIDDER_SEAT % 2]

func _mean(arr: Array) -> float:
	var s := 0.0
	for x in arr: s += x
	return s / arr.size()

func _stddev(arr: Array, mean: float) -> float:
	var s := 0.0
	for x in arr: s += (x - mean) * (x - mean)
	return sqrt(s / arr.size())

func _find_qualifying_hands() -> Array:
	var qualifying := []
	var settings = GameSettings.new()
	var attempts := 0
	while qualifying.size() < N_QUALIFYING_HANDS_TARGET and attempts < MAX_SEARCH_ATTEMPTS:
		attempts += 1
		var tiles = _random_hand_tiles()
		var hand = _tiles_to_hand(tiles)
		var bid_decisions: Array = []
		var bid = AIPlayer.decide_bid(hand, BIDDER_SEAT, null, settings, false, DIFFICULTY, bid_decisions, -1, -1)
		if bid.type == BidScript.Type.POINTS:
			qualifying.append({"tiles": tiles, "bid_value": bid.value})
	print("Bid-worthy search: found ", qualifying.size(), " hands in ", attempts, " attempts")
	return qualifying

func _init():
	var qualifying = _find_qualifying_hands()

	var hand_records := []
	var n_full_sweep := 0

	for i in range(qualifying.size()):
		var q = qualifying[i]
		var bidder_tiles = q["tiles"]
		var bidder_hand = _tiles_to_hand(bidder_tiles)
		var full_ranking = _full_predicted_ranking(bidder_hand)

		var do_full_sweep = (i % 3 == 0) and (n_full_sweep < N_FULL_SWEEP_TARGET)
		var tested_suits := []
		if do_full_sweep:
			n_full_sweep += 1
			for entry in full_ranking:
				tested_suits.append(entry["trump"])
		else:
			for k in range(3):
				tested_suits.append(full_ranking[k]["trump"])

		var deals = _generate_deals(bidder_tiles, TRIALS_PER_CANDIDATE)

		var actual := {}
		for suit in tested_suits:
			var points := []
			for deal in deals:
				points.append(_play_trial(bidder_tiles, suit, q["bid_value"], deal))
			var mean = _mean(points)
			actual[str(suit)] = {"mean": mean, "stddev": _stddev(points, mean)}

		var chosen_suit = full_ranking[0]["trump"]   # what best_trump() actually picks
		var actual_best_suit = tested_suits[0]
		var best_mean = actual[str(actual_best_suit)]["mean"]
		for suit in tested_suits:
			if actual[str(suit)]["mean"] > best_mean:
				best_mean = actual[str(suit)]["mean"]
				actual_best_suit = suit

		var disagreement = (chosen_suit != actual_best_suit)

		var predicted_rank_of_actual_best = -1
		for r in range(full_ranking.size()):
			if full_ranking[r]["trump"] == actual_best_suit:
				predicted_rank_of_actual_best = r + 1
				break

		var chosen_entry = full_ranking[0]
		var actual_best_entry = full_ranking[predicted_rank_of_actual_best - 1]

		var tags := []
		var severity = null
		if disagreement:
			var delta_trump_count = actual_best_entry["trump_count"] - chosen_entry["trump_count"]
			var delta_has_double = int(actual_best_entry["has_double_trump"]) - int(chosen_entry["has_double_trump"])
			var delta_off_suit_doubles = actual_best_entry["off_suit_doubles_count"] - chosen_entry["off_suit_doubles_count"]
			var delta_realization = actual_best_entry["realization_bias"] - chosen_entry["realization_bias"]

			if delta_trump_count > 0 or delta_has_double > 0:
				tags.append("control_gap")
			if delta_off_suit_doubles < 0:
				tags.append("off_suit_doubles_sacrifice")
			if abs(delta_realization) >= REALIZATION_SHIFT_THRESHOLD:
				tags.append("realization_shift")
			if predicted_rank_of_actual_best > 3:
				tags.append("outside_top3")
			if tags.is_empty():
				tags.append("no_clear_pattern")

			# Severity: calibration error (close ranks, small gaps) vs. wrong
			# objective (chosen looked clearly best but wasn't).
			severity = {
				"chosen_trump": chosen_suit,
				"actual_best_trump": actual_best_suit,
				"chosen_predicted_rank": 1,   # chosen_suit is always full_ranking[0] by construction
				"actual_best_predicted_rank": predicted_rank_of_actual_best,
				"predicted_score_gap": chosen_entry["score"] - actual_best_entry["score"],
				"actual_points_gap": actual[str(actual_best_suit)]["mean"] - actual[str(chosen_suit)]["mean"]
			}

		hand_records.append({
			"bidder_hand": bidder_tiles,
			"bid_value": q["bid_value"],
			"sweep_scope": "full7" if do_full_sweep else "top3",
			"tested_suits": tested_suits,
			"full_predicted_ranking": full_ranking,
			"actual_performance": actual,
			"chosen_suit": chosen_suit,
			"actual_best_suit": actual_best_suit,
			"disagreement": disagreement,
			"predicted_rank_of_actual_best": predicted_rank_of_actual_best,
			"classification_tags": tags,
			"disagreement_severity": severity
		})

	# ── Summary ──────────────────────────────────────────────────────────
	var n_disagreements := 0
	var tag_counts := {}
	var rank_histogram := {}
	var n_outside_top3_detected := 0
	var sum_predicted_gap := 0.0
	var sum_actual_gap := 0.0
	for rec in hand_records:
		if rec["disagreement"]:
			n_disagreements += 1
			for tag in rec["classification_tags"]:
				tag_counts[tag] = tag_counts.get(tag, 0) + 1
			if rec["sweep_scope"] == "full7" and rec["predicted_rank_of_actual_best"] > 3:
				n_outside_top3_detected += 1
			sum_predicted_gap += rec["disagreement_severity"]["predicted_score_gap"]
			sum_actual_gap += rec["disagreement_severity"]["actual_points_gap"]
		var rk = str(rec["predicted_rank_of_actual_best"])
		rank_histogram[rk] = rank_histogram.get(rk, 0) + 1

	var mean_predicted_gap = sum_predicted_gap / n_disagreements if n_disagreements > 0 else 0.0
	var mean_actual_gap = sum_actual_gap / n_disagreements if n_disagreements > 0 else 0.0

	var summary = {
		"n_qualifying_hands": hand_records.size(),
		"n_full_sweep_hands": n_full_sweep,
		"n_top3_hands": hand_records.size() - n_full_sweep,
		"n_disagreements": n_disagreements,
		"disagreement_rate": float(n_disagreements) / hand_records.size() if hand_records.size() > 0 else 0.0,
		"tag_counts": tag_counts,
		"predicted_rank_of_actual_best_histogram": rank_histogram,
		"n_outside_top3_detected": n_outside_top3_detected,
		"mean_predicted_score_gap_on_disagreement": mean_predicted_gap,
		"mean_actual_points_gap_on_disagreement": mean_actual_gap,
		"note": "outside_top3 can only be detected on full7-scope hands; top3-scope hands cannot show rank>3 by construction. Compare mean_predicted_score_gap vs mean_actual_points_gap: small/comparable gaps suggest calibration error, large predicted gap with the AI confidently wrong suggests a wrong-objective error."
	}

	var output = {
		"params": {
			"trials_per_candidate": TRIALS_PER_CANDIDATE,
			"n_qualifying_hands_target": N_QUALIFYING_HANDS_TARGET,
			"n_full_sweep_target": N_FULL_SWEEP_TARGET,
			"realization_shift_threshold": REALIZATION_SHIFT_THRESHOLD
		},
		"summary": summary,
		"hands": hand_records
	}

	var f = FileAccess.open("res://scripts/job5_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(output, "\t"))
	f.close()
	quit(0)
