class_name Game
extends RefCounted

const BidScript = preload("res://bid.gd")
const GameSettingsScript = preload("res://game_settings.gd")

var players: Array[Player] = []
var settings: RefCounted
var shaker: int = 0
var current_player: int = 0

# Hand state
var current_bid: RefCounted = null   # Bid instance
var trump: int = -1
var variant: int = 0                 # BidScript.Type value
var nello_solo_player: int = -1
var active_nello_doubles_mode: String = ""  # set per-hand; "" means use settings default
var tricks_played: int = 0
var current_trick: Trick = null
var hand_history: Array = []         # Trick records for the current hand
var deal_snapshot: Array = []        # Each player's full hand at deal time

# Score tracking
var team_marks: Array[int] = [0, 0]
var team_points: Array[int] = [0, 0]

const MARKS_TO_WIN = 7

func _init(game_settings: RefCounted = null):
	settings = game_settings if game_settings else GameSettingsScript.new()

func setup_players(human_seat: int = 0):
	players.clear()
	for i in range(4):
		players.append(Player.new(i, [], i == human_seat))

# --- DEAL ---

func deal_hands():
	var deck = Deck.new()
	deck.build_deck()
	deck.shuffle()
	var hands = deck.deal(4, 7)
	for i in range(4):
		players[i].hand.clear()
		players[i].reset_round()
		for d in hands[i]:
			players[i].hand.append(d)
	team_points[0] = 0
	team_points[1] = 0
	tricks_played = 0
	current_bid = null
	trump = -1
	nello_solo_player = -1
	active_nello_doubles_mode = ""
	hand_history.clear()
	deal_snapshot.clear()
	for i in range(4):
		var snap: Array = []
		for d in players[i].hand:
			snap.append(d)
		deal_snapshot.append(snap)

# --- BIDDING ---

# Returns the seating order bidding follows this hand, ending with the
# shaker (who always bids last, regardless of direction).
# "shaker_left_first": shaker-1, shaker-2, shaker-3, shaker (standard)
# "shaker_right_first": shaker+1, shaker+2, shaker+3, shaker
func bid_order() -> Array:
	var order: Array = []
	var dir = -1 if settings.bid_direction == "shaker_left_first" else 1
	for i in range(1, 4):
		order.append((shaker + dir * i + 4) % 4)
	order.append(shaker)
	return order

func first_bidder() -> int:
	return bid_order()[0]

# Count how many doubles are in a hand (used to validate Plunge/Splash bids).
func count_doubles(hand: Array) -> int:
	var n = 0
	for d in hand:
		if d.is_double():
			n += 1
	return n

# Build the context dictionary Bid.is_valid() needs for context-sensitive
# bids (Plunge, Splash, Low-No). `bid_position` is this player's index
# (0-based) within bid_order() for this hand.
func bid_context(player_id: int, bid_position: int) -> Dictionary:
	return {
		"hand_doubles_count": count_doubles(players[player_id].hand),
		"is_dealer": player_id == shaker,
		"all_others_passed": (bid_position == 3 and current_bid == null),
	}

# Returns which special contract types are currently eligible given settings
# and the player's hand. Only checks NELLO, SEVENS, PLUNGE, and SPLASH.
func eligible_contracts(hand: Array) -> Array:
	var result: Array = []
	if settings.allow_nello:
		result.append(BidScript.Type.NELLO)
	if settings.allow_sevens and (not settings.sevens_require_seven_in_hand or _has_seven_domino(hand)):
		result.append(BidScript.Type.SEVENS)
	if settings.allow_plunge and count_doubles(hand) >= settings.plunge_minimum_doubles:
		result.append(BidScript.Type.PLUNGE)
	if settings.allow_splash and count_doubles(hand) >= settings.splash_minimum_doubles:
		result.append(BidScript.Type.SPLASH)
	return result

func _has_seven_domino(hand: Array) -> bool:
	for d in hand:
		if d.pip_sum() == 7:
			return true
	return false

func submit_bid(bid: RefCounted, bid_position: int = -1) -> bool:
	var context = {}
	if bid_position >= 0:
		context = bid_context(bid.player_id, bid_position)
	if not BidScript.is_valid(bid, current_bid, settings, context):
		return false
	if bid.type != BidScript.Type.PASS:
		current_bid = bid
	return true

func resolve_bidding(all_bids: Array) -> RefCounted:
	# If bids were submitted via submit_bid(), current_bid is already set.
	# all_bids is only used when bids weren't pre-submitted (e.g. test node).
	if current_bid == null:
		for b in all_bids:
			if b.type != BidScript.Type.PASS:
				current_bid = b
	# Forced bid: if still no winner, shaker must bid minimum (unless the
	# table prefers to just reshake with no penalty)
	if current_bid == null and settings.allow_forced_bid and not settings.reshake_if_all_pass:
		current_bid = BidScript.new(BidScript.Type.POINTS, settings.forced_bid_minimum, shaker)
	return current_bid

func apply_bid_result(trump_suit: int = -1):
	if current_bid == null:
		return
	variant = current_bid.type
	match variant:
		BidScript.Type.POINTS, BidScript.Type.MARKS:
			trump = trump_suit
		BidScript.Type.NELLO:
			trump = trump_suit
			nello_solo_player = (current_bid.player_id + 2) % 4
		BidScript.Type.PLUNGE:
			trump = trump_suit
		BidScript.Type.SPLASH:
			trump = trump_suit
		BidScript.Type.FOLLOW_ME:
			trump = -1
		BidScript.Type.SEVENS:
			trump = -1
		BidScript.Type.LOW_NO:
			trump = -1

# --- TRICK PLAY ---

func start_trick(leading_player: int):
	current_player = leading_player
	current_trick = Trick.new()
	var doubles_mode = active_nello_doubles_mode if variant == BidScript.Type.NELLO and active_nello_doubles_mode != "" else "high"
	current_trick.setup(trump, variant, doubles_mode, settings.doubles_trump_reversed)

func get_legal_moves(player: Player) -> Array[Domino]:
	return current_trick.get_legal_moves(player.hand)

func play_domino(player: Player, domino: Domino):
	player.hand.erase(domino)
	current_trick.add_play(player.id, domino)

func resolve_trick() -> int:
	var winner_id = current_trick.determine_winner()
	var pts = current_trick.calculate_points()
	var winner_team = winner_id % 2
	team_points[winner_team] += pts
	players[winner_id].tricks_won += 1
	tricks_played += 1
	print("Trick won by Player ", winner_id, " (Team ", winner_team, ") for ", pts, " points [trump=", trump, "]")
	print("  Plays: ", current_trick.debug_string())
	return winner_id

# --- HAND SCORING ---

func resolve_hand() -> Dictionary:
	if current_bid == null:
		return {}

	var bid_team = current_bid.player_id % 2
	var other_team = 1 - bid_team
	var result = {}

	match variant:
		BidScript.Type.POINTS:
			if team_points[bid_team] >= current_bid.value:
				team_marks[bid_team] += 1
				result = {"winner": bid_team, "reason": "Met point bid of " + str(current_bid.value)}
			else:
				team_marks[other_team] += 1
				result = {"winner": other_team, "reason": "Bidding team failed " + str(current_bid.value) + " point bid"}

		BidScript.Type.MARKS:
			# Must win ALL 7 tricks — any lost trick sets the bidding team
			var bid_tricks = players[current_bid.player_id].tricks_won
			var partner_id = (current_bid.player_id + 2) % 4
			bid_tricks += players[partner_id].tricks_won
			if bid_tricks == 7:
				team_marks[bid_team] += current_bid.value
				result = {"winner": bid_team, "reason": "Won " + str(current_bid.value) + " mark bid"}
			else:
				team_marks[other_team] += current_bid.value
				result = {"winner": other_team, "reason": "Set on mark bid — lost " + str(7 - bid_tricks) + " trick(s)"}

		BidScript.Type.NELLO:
			if players[current_bid.player_id].tricks_won == 0:
				team_marks[bid_team] += current_bid.value
				result = {"winner": bid_team, "reason": "Nello succeeded"}
			else:
				team_marks[other_team] += current_bid.value
				result = {"winner": other_team, "reason": "Nello failed — bidder caught a trick"}

		BidScript.Type.SEVENS:
			var partner_id = (current_bid.player_id + 2) % 4
			var bid_tricks = players[current_bid.player_id].tricks_won + players[partner_id].tricks_won
			if bid_tricks == 7:
				team_marks[bid_team] += current_bid.value
				result = {"winner": bid_team, "reason": "Sevens succeeded"}
			else:
				team_marks[other_team] += current_bid.value
				result = {"winner": other_team, "reason": "Sevens failed"}

		BidScript.Type.FOLLOW_ME, BidScript.Type.PLUNGE, BidScript.Type.SPLASH:
			# Plunge and Splash also require ALL 7 tricks, same as Marks.
			if variant == BidScript.Type.PLUNGE or variant == BidScript.Type.SPLASH:
				var p_id = current_bid.player_id
				var pt_id = (p_id + 2) % 4
				var tricks = players[p_id].tricks_won + players[pt_id].tricks_won
				if tricks == 7:
					team_marks[bid_team] += current_bid.value
					result = {"winner": bid_team, "reason": "Won all tricks"}
				else:
					team_marks[other_team] += current_bid.value
					result = {"winner": other_team, "reason": "Set — lost " + str(7 - tricks) + " trick(s)"}
			else:
				if team_points[bid_team] > team_points[other_team]:
					team_marks[bid_team] += current_bid.value
					result = {"winner": bid_team, "reason": "Won the hand"}
				else:
					team_marks[other_team] += current_bid.value
					result = {"winner": other_team, "reason": "Bidding team lost the hand"}

		BidScript.Type.LOW_NO:
			# Points-game equivalent of Nello: bidder's side scores 42 if they
			# avoid taking any trick; opponents score 42 if bidder is forced
			# to take even one trick.
			if players[current_bid.player_id].tricks_won == 0:
				team_marks[bid_team] += 1
				result = {"winner": bid_team, "reason": "Low-No succeeded"}
			else:
				team_marks[other_team] += 1
				result = {"winner": other_team, "reason": "Low-No failed — bidder caught a trick"}

	result["team_marks"] = team_marks.duplicate()
	result["team_points"] = team_points.duplicate()
	return result

func check_game_over() -> int:
	var target = settings.marks_to_win
	for t in [0, 1]:
		if team_marks[t] >= target:
			if not settings.win_by_two or (team_marks[t] - team_marks[1 - t] >= 2):
				return t
	return -1

func advance_shaker():
	shaker = (shaker + 3) % 4

# Record a completed trick into hand_history.
# Call AFTER resolve_trick() (to get winner_id and the incremented tricks_played),
# but while current_trick.plays is still populated.
# Reconstructs each player's hand-at-start-of-trick by adding back what they played.
func record_trick(trick: Trick, winner_id: int, plays_with_reasons: Array):
	var hand_states: Array = []
	for i in range(4):
		var snapshot: Array = []
		for d in players[i].hand:
			snapshot.append(d)
		for play in trick.plays:
			if play["player"] == i:
				snapshot.append(play["domino"])
		hand_states.append(snapshot)

	hand_history.append({
		"trick_number":  tricks_played,      # 1-based: resolve_trick() already incremented it
		"plays":         plays_with_reasons.duplicate(true),  # deep copy — caller clears the array
		"winner_id":     winner_id,
		"points":        trick.calculate_points(),
		"hand_states":   hand_states,
		"lead_suit":     trick.lead_suit,
		"trump":         trump,
	})
