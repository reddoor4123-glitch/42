extends Node2D

const BidScript = preload("res://bid.gd")
const GameSettingsScript = preload("res://game_settings.gd")
const GameScript = preload("res://game.gd")

func _ready():
	var settings = GameSettingsScript.new()
	var game = GameScript.new(settings)
	game.setup_players(0)

	print("=== DEALING ===")
	game.deal_hands()
	for i in range(4):
		var hand_str = ""
		for d in game.players[i].hand:
			hand_str += d.debug_string() + " "
		print("Player ", i, " (Team ", i % 2, "): ", hand_str)

	print("\n=== BIDDING ===")
	var bids = []
	var bid_order_start = game.first_bidder()
	for i in range(4):
		var pid = (bid_order_start + i) % 4
		if pid == 1:
			var b = BidScript.new(BidScript.Type.POINTS, 33, pid)
			game.submit_bid(b)
			bids.append(b)
			print("Player ", pid, " bids: ", b.debug_string())
		else:
			var b = BidScript.new(BidScript.Type.PASS, 0, pid)
			bids.append(b)
			print("Player ", pid, " passes")

	var winning_bid = game.resolve_bidding(bids)
	if winning_bid:
		print("Winning bid: Player ", winning_bid.player_id, " — ", winning_bid.debug_string())
		game.apply_bid_result(2)  # Call 2s as trump
		print("Trump called: ", game.trump)
	else:
		print("No bid resolved")
		return

	print("\n=== TRICKS ===")
	var leader = winning_bid.player_id
	for t in range(7):
		print("\n--- Trick ", t + 1, " ---")
		game.start_trick(leader)
		for i in range(4):
			var player = game.players[game.current_player]
			var legal = game.get_legal_moves(player)
			var chosen = player.choose_domino(legal)
			print("  Player ", player.id, " plays ", chosen.debug_string(),
				" (suit:", chosen.get_suit(game.trump, "high", game.current_trick.lead_suit if game.current_trick else -1), " rank:", chosen.get_rank(game.trump, "high", game.current_trick.lead_suit if game.current_trick else -1), ")")
			game.play_domino(player, chosen)
			game.current_player = (game.current_player + 1) % 4
		leader = game.resolve_trick()

	print("\n=== HAND RESULT ===")
	var result = game.resolve_hand()
	print("Team 0 points: ", result["team_points"][0])
	print("Team 1 points: ", result["team_points"][1])
	print("Winner: Team ", result["winner"], " — ", result["reason"])
	print("Marks — Team 0: ", result["team_marks"][0], " | Team 1: ", result["team_marks"][1])

	var game_winner = game.check_game_over()
	if game_winner >= 0:
		print("\n GAME OVER — Team ", game_winner, " wins!")
	else:
		print("\nGame continues...")
