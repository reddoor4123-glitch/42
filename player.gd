class_name Player
extends RefCounted

var id: int
var team: int        # 0 = players 0 & 2, 1 = players 1 & 3
var is_human: bool
var hand: Array[Domino] = []
var tricks_won: int = 0
var points_won: int = 0

func _init(player_id: int, starting_hand: Array, human: bool = false):
	id = player_id
	team = player_id % 2  # Players 0 & 2 are team 0; players 1 & 3 are team 1
	is_human = human
	for d in starting_hand:
		hand.append(d)

func reset_round():
	tricks_won = 0
	points_won = 0

# Basic AI: plays the first legal domino (placeholder for smarter logic later)
func choose_domino(legal_moves: Array[Domino]) -> Domino:
	return legal_moves[0]
