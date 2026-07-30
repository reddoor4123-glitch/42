extends SceneTree
# Job 1 headless viability check.
# Run with: godot --headless --script res://scripts/headless_test_job1.gd

const BidScript = preload("res://bid.gd")

func _init():
	var t0 = Time.get_ticks_msec()

	var game = Game.new()
	game.setup_players(0)
	game.deal_hands()

	print("Dealt hands:")
	for i in range(4):
		var hand_str = ""
		for d in game.players[i].hand:
			hand_str += d.debug_string() + " "
		print("  Player %d: %s" % [i, hand_str])

	# Hardcode contract: Points, bid value 30, player 0 is bidder.
	var trump_suit = 6  # sixes trump
	var bid = BidScript.new(BidScript.Type.POINTS, 30, 0)
	game.current_bid = bid
	game.apply_bid_result(trump_suit)

	print("\nContract: Points 30, bidder=Player 0, trump=%d" % trump_suit)

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
			if chosen == null:
				print("ERROR: AIPlayer.decide_play returned null for player %d, legal=%d" % [player.id, legal.size()])
				quit(1)
				return
			game.play_domino(player, chosen)
			game.current_player = (game.current_player + 3) % 4

		var winner_id = game.resolve_trick()
		game.record_trick(game.current_trick, winner_id, [])
		leader = winner_id

	var result = game.resolve_hand()
	print("\nHand result: ", result)

	var elapsed = Time.get_ticks_msec() - t0
	print("\nElapsed: %d ms" % elapsed)

	quit(0)
