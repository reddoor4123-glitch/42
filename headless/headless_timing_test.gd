extends SceneTree
# Timing probe: run N full hands in one process, report per-hand cost
# separately from engine startup, to estimate feasibility of large batches.

const BidScript = preload("res://bid.gd")

func _play_one_hand(seed_val: int) -> Dictionary:
	seed(seed_val)
	var game = Game.new()
	game.setup_players(0)
	game.deal_hands()

	var trump_suit = 6
	var bid = BidScript.new(BidScript.Type.POINTS, 30, 0)
	game.current_bid = bid
	game.apply_bid_result(trump_suit)

	var leader = game.current_bid.player_id
	for trick_num in range(7):
		game.start_trick(leader)
		for turn in range(4):
			var player = game.players[game.current_player]
			var legal = game.get_legal_moves(player)
			var partner_id = (player.id + 2) % 4
			var reason_log: Array = []
			var frame = PublicFrame.new(game.hand_history, game.current_trick)
			var knowledge = PublicKnowledge.from_state(frame)
			var chosen = AIPlayer.decide_play(
				legal, player.hand, game.current_trick,
				player.id, partner_id, game.trump, reason_log,
				game.settings.ai_difficulty,
				false,
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

	return game.resolve_hand()

func _init():
	var n = 1000
	var t0 = Time.get_ticks_msec()
	var wins = 0
	for i in range(n):
		var result = _play_one_hand(i * 7919 + 1)
		if result.get("winner", -1) == 0:
			wins += 1
	var elapsed = Time.get_ticks_msec() - t0
	print("Ran %d hands in %d ms (%.2f ms/hand avg)" % [n, elapsed, float(elapsed) / n])
	print("Bidding team win rate (sanity, not the real experiment): %d/%d" % [wins, n])
	quit(0)
