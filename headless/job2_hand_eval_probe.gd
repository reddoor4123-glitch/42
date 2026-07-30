extends SceneTree
# Iteration helper: evaluate candidate Partner hands against AIPlayer.evaluate_hand()
# before committing to archetype definitions. Not part of the experiment itself.

const TRUMP_SUIT := 6

# Candidate hands to test: list of [name, tiles].
const CANDIDATES := [
	["original_run_ceiling_6+1", [[6,6],[6,1],[0,3],[1,2],[2,4],[3,4],[4,5]]],
	["original_run_quantity", [[6,5],[6,4],[6,3],[6,2],[6,1],[1,3],[2,5]]],
	["FINAL_ceiling_v11_3doubles", [[6,6],[6,5],[5,5],[4,4],[3,3],[4,5],[2,5]]],
	["FINAL_quantity_v2_with_double", [[6,5],[6,4],[6,3],[6,2],[6,1],[5,5],[2,5]]],
]

func _make(pairs: Array) -> Array[Domino]:
	var hand: Array[Domino] = []
	for p in pairs:
		hand.append(Domino.new(p[0], p[1]))
	return hand

func _init():
	for c in CANDIDATES:
		var name = c[0]
		var hand = _make(c[1])
		var eval = AIPlayer.evaluate_hand(hand, TRUMP_SUIT)
		print("%s: estimated_points=%.2f trump_count=%d has_double_trump=%s estimated_tricks=%.2f" % [
			name, eval["estimated_points"], eval["trump_count"], eval["has_double_trump"], eval["estimated_tricks"]
		])
	quit(0)
