class_name Trick
extends RefCounted

const BidScript = preload("res://bid.gd")

var plays: Array = []
var lead_suit: int = -1
var trump: int = -1
var variant: int = 0
var nello_doubles: String = "high"
var doubles_trump_reversed: bool = false
var own_suit_reversed: bool = false

func setup(trump_suit: int, bid_type: int, doubles_mode: String = "high", doubles_trump_rev: bool = false, own_suit_rev: bool = false):
	trump = trump_suit
	variant = bid_type
	nello_doubles = doubles_mode
	doubles_trump_reversed = doubles_trump_rev
	own_suit_reversed = own_suit_rev

# `declared_suit` is only used for the very first play of the trick, and
# only matters when it's a deliberate override (the "small-end opening
# lead" variant: lead a non-trump, non-double domino but declare it as its
# SMALLER pip's suit instead of the default larger one). Pass -1 (default)
# for normal play. Callers are responsible for only allowing this on the
# hand's very first trick and only gating it behind
# settings.allow_small_end_opening_lead — Trick itself doesn't enforce
# either restriction since it has no notion of "which trick number" or
# settings.
func add_play(player_index: int, domino: Domino, declared_suit: int = -1):
	plays.append({"player": player_index, "domino": domino})
	if plays.size() == 1:
		if variant == BidScript.Type.SEVENS:
			lead_suit = -1
		elif declared_suit >= 0 and not domino.is_double() and not domino.is_trump(trump) \
				and (domino.left == declared_suit or domino.right == declared_suit):
			lead_suit = declared_suit
		else:
			# Lead suit: trump pip wins, otherwise higher pip
			lead_suit = domino.get_suit(trump, nello_doubles)

func get_legal_moves(hand: Array[Domino]) -> Array[Domino]:
	if variant == BidScript.Type.SEVENS:
		# Sevens has no suits, no trump, no follow-suit — the only legal
		# plays are whichever domino(es) in hand are closest to a pip-sum
		# of 7 right now. Recomputed fresh every call, since the answer
		# shifts as the hand shrinks trick to trick. Ties are legal together;
		# nothing picks a "winner" among them here — that's the player's choice.
		var best_dist := 999
		for d in hand:
			var dist = abs(d.pip_sum() - 7)
			if dist < best_dist:
				best_dist = dist
		var closest: Array[Domino] = []
		for d in hand:
			if abs(d.pip_sum() - 7) == best_dist:
				closest.append(d)
		return closest
	if plays.size() == 0:
		return hand
	var must_follow: Array[Domino] = []
	for d in hand:
		# Pass lead_suit so mixed dominoes are correctly identified
		if d.get_suit(trump, nello_doubles, lead_suit) == lead_suit:
			must_follow.append(d)
	if must_follow.size() > 0:
		return must_follow
	return hand

func determine_winner() -> int:
	if variant == BidScript.Type.SEVENS:
		return _determine_winner_sevens()
	return _determine_winner_standard()

func _determine_winner_standard() -> int:
	var best_play = plays[0]
	var best_domino: Domino = best_play["domino"]
	var best_suit = best_domino.get_suit(trump, nello_doubles, lead_suit)
	var best_rank = best_domino.get_rank(trump, nello_doubles, lead_suit, doubles_trump_reversed, own_suit_reversed)
	for i in range(1, plays.size()):
		var play = plays[i]
		var d: Domino = play["domino"]
		var d_suit = d.get_suit(trump, nello_doubles, lead_suit)
		var d_rank = d.get_rank(trump, nello_doubles, lead_suit, doubles_trump_reversed, own_suit_reversed)
		# Must match lead suit or be trump to win
		var can_win = (d_suit == lead_suit or d_suit == trump)
		if not can_win:
			continue
		var best_is_trump = (best_suit == trump)
		var d_is_trump = (d_suit == trump)
		if d_is_trump and not best_is_trump:
			best_play = play
			best_domino = d
			best_suit = d_suit
			best_rank = d_rank
		elif d_is_trump == best_is_trump and d_suit == best_suit:
			if d_rank > best_rank:
				best_play = play
				best_domino = d
				best_suit = d_suit
				best_rank = d_rank
	return best_play["player"]

# Sevens winner is whoever's domino is CLOSEST to a pip-sum of 7. This uses
# a strict "<" comparison, which already implements the family's confirmed
# tie rule: the first domino to reach the best distance holds the trick —
# a later domino merely TYING that distance does not overtake it. This is
# the only tie rule the engine implements; it isn't configurable (an
# orphaned settings.sevens_tie_rule string used to describe this exact
# behavior and nothing else — removed July 6, 2026, never actually
# consulted anywhere).
func _determine_winner_sevens() -> int:
	var best_play = plays[0]
	var best_distance = abs(7 - (best_play["domino"] as Domino).pip_sum())
	for i in range(1, plays.size()):
		var play = plays[i]
		var d: Domino = play["domino"]
		var distance = abs(7 - d.pip_sum())
		if distance < best_distance:
			best_play = play
			best_distance = distance
	return best_play["player"]

func calculate_points() -> int:
	var pts = 1
	for play in plays:
		var d: Domino = play["domino"]
		var s = d.pip_sum()
		if s == 5:
			pts += 5
		elif s == 10:
			pts += 10
	return pts

func debug_string() -> String:
	var result = ""
	for play in plays:
		result += "P" + str(play["player"]) + ":" + (play["domino"] as Domino).debug_string() + " "
	return result.strip_edges()
