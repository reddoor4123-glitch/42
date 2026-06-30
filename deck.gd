class_name Deck
extends RefCounted

var dominoes: Array[Domino] = []

func build_deck():
	dominoes.clear()
	for left in range(0, 7):
		for right in range(left, 7):
			dominoes.append(Domino.new(left, right))

func count() -> int:
	return dominoes.size()

func shuffle():
	dominoes.shuffle()

func deal(num_players: int, hand_size: int) -> Array:
	var hands = []
	for i in range(num_players):
		hands.append([])
	for i in range(num_players * hand_size):
		var player_index = i % num_players
		hands[player_index].append(dominoes[i])
	return hands
