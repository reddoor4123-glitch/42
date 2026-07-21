extends SceneTree

# ═══════════════════════════════════════════════════════════════════════════
# Job 4 — Trump selection: predicted vs actual, for the flagged hand
# (Player 2's hand from the July 20, 2026 flag: called blanks as trump
# while holding only one non-double blank, itself a counter.)
#
# Question this answers: for THIS hand, does best_trump()'s chosen suit
# (blanks) actually produce the best outcomes when played by the current
# AI — or does another candidate suit outperform it in practice?
#
# Method: pin the bidder's hand. For each candidate trump, replay the SAME
# 1000 randomly-dealt opponent/partner hands (paired design — isolates
# trump quality from opponent-hand variance). Compare each candidate's
# actual mean/stddev of bidder-team points against evaluate_hand()'s
# predicted estimated_points, and compare predicted rank vs actual rank.
#
# Per Headless_Harness_Reference.md conventions:
#   - DIFFICULTY = "expert" everywhere (opportunism=1.0, fully deterministic
#     given hand/trick state — isolates trump quality from AI randomness)
#   - is_partner only true for PARTNER_SEAT (no auto-derivation)
#   - turn order is (current_player + 3) % 4
#   - record_trick's 3rd arg must be current_trick.plays, not []
#   - stdout must not be read for batch runs — results go to JSON only
# ═══════════════════════════════════════════════════════════════════════════

const BidScript = preload("res://bid.gd")

const BIDDER_SEAT := 0
const PARTNER_SEAT := 2   # (BIDDER_SEAT + 2) % 4
const N_TRIALS := 1000
const BID_VALUE := 31     # matches the flagged hand's actual bid
const DIFFICULTY := "expert"

# The exact flagged hand, as (left, right) pairs.
const BIDDER_HAND_TILES := [[6,6],[3,4],[1,6],[4,4],[0,5],[2,2],[3,3]]

# Candidates worth testing — established in the manual audit that suits
# 1 and 5 are not real contenders for this hand (both score far below
# these five under evaluate_hand()), so they're skipped to save trials.
const CANDIDATE_TRUMPS := [0, 2, 3, 4, 6]

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

# Pre-generate N_TRIALS deals for seats 1/2/3 ONCE, reused identically
# across every candidate trump (the paired design).
func _generate_deals() -> Array:
	var deals := []
	for t in range(N_TRIALS):
		var pool = _build_full_deck()
		for tile in BIDDER_HAND_TILES:
			_take(pool, tile[0], tile[1])   # remove bidder's fixed tiles
		pool.shuffle()
		var hand1 := []
		var hand2 := []
		var hand3 := []
		for i in range(7):
			var d: Domino = pool[i]
			hand1.append([d.left, d.right])
		for i in range(7, 14):
			var d: Domino = pool[i]
			hand2.append([d.left, d.right])
		for i in range(14, 21):
			var d: Domino = pool[i]
			hand3.append([d.left, d.right])
		deals.append({"seat1": hand1, "seat2": hand2, "seat3": hand3})
	return deals

func _tiles_to_hand(tiles: Array) -> Array[Domino]:
	var hand: Array[Domino] = []
	for t in tiles:
		hand.append(Domino.new(t[0], t[1]))
	return hand

func _play_trial(trump: int, deal: Dictionary) -> int:
	var game = Game.new()
	game.setup_players(0)
	game.deal_hands()   # resets team_points/tricks_played/etc.; hands overwritten below

	game.players[BIDDER_SEAT].hand = _tiles_to_hand(BIDDER_HAND_TILES)
	game.players[1].hand = _tiles_to_hand(deal["seat1"])
	game.players[PARTNER_SEAT].hand = _tiles_to_hand(deal["seat2"])
	game.players[3].hand = _tiles_to_hand(deal["seat3"])

	var bid = BidScript.new(BidScript.Type.POINTS, BID_VALUE, BIDDER_SEAT)
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
	var bidder_team = BIDDER_SEAT % 2
	return result["team_points"][bidder_team]

func _mean(arr: Array) -> float:
	var s := 0.0
	for x in arr: s += x
	return s / arr.size()

func _stddev(arr: Array, mean: float) -> float:
	var s := 0.0
	for x in arr: s += (x - mean) * (x - mean)
	return sqrt(s / arr.size())

func _init():
	var bidder_hand: Array[Domino] = _tiles_to_hand(BIDDER_HAND_TILES)
	var deals = _generate_deals()

	var results := {}
	for trump in CANDIDATE_TRUMPS:
		var predicted = AIPlayer.evaluate_hand(bidder_hand, trump)
		var predicted_score = predicted["estimated_points"] \
			+ predicted["trump_count"] * 2.0 \
			+ (3.0 if predicted.get("has_double_trump", false) else 0.0)

		var actual_points := []
		for deal in deals:
			actual_points.append(_play_trial(trump, deal))

		var mean = _mean(actual_points)
		var stddev = _stddev(actual_points, mean)

		results[str(trump)] = {
			"trump": trump,
			"predicted_estimated_points": predicted["estimated_points"],
			"predicted_trump_count": predicted["trump_count"],
			"predicted_has_double_trump": predicted.get("has_double_trump", false),
			"predicted_best_trump_score": predicted_score,
			"actual_mean_points": mean,
			"actual_stddev": stddev,
			"n_trials": N_TRIALS
		}

	# Rank by predicted best_trump() score vs rank by actual mean points.
	var by_predicted = CANDIDATE_TRUMPS.duplicate()
	by_predicted.sort_custom(func(a, b): return results[str(a)]["predicted_best_trump_score"] > results[str(b)]["predicted_best_trump_score"])
	var by_actual = CANDIDATE_TRUMPS.duplicate()
	by_actual.sort_custom(func(a, b): return results[str(a)]["actual_mean_points"] > results[str(b)]["actual_mean_points"])

	var output = {
		"bidder_hand": BIDDER_HAND_TILES,
		"n_trials_per_candidate": N_TRIALS,
		"paired_design": true,
		"results_by_trump": results,
		"predicted_rank_order": by_predicted,
		"actual_rank_order": by_actual,
		"best_trump_chosen": by_predicted[0],
		"actual_best_performer": by_actual[0],
		"chosen_matches_actual_best": by_predicted[0] == by_actual[0]
	}

	var f = FileAccess.open("res://scripts/job4_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(output, "\t"))
	f.close()
	quit(0)
