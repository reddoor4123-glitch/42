extends SceneTree
# Job 3, Step 1: find a real, organically-arrived-at, bid-worthy bidder hand.
# Deal a random 7-tile hand to seat 0, run it through AIPlayer.decide_bid()
# at Expert difficulty, keep the first hand where should_bid is true
# (final_score >= 28.0). No hand-picking, no searching for a "better" one.
#
# Run with: godot --headless --path . --script res://headless/job3_find_bidworthy_hand.gd

func _build_full_deck() -> Array:
	var pool: Array = []
	for a in range(0, 7):
		for b in range(a, 7):
			pool.append(Domino.new(a, b))
	return pool

func _init():
	var settings = GameSettings.new()
	var attempts = 0
	var found_hand: Array[Domino] = []
	var found_decision: Dictionary = {}
	var found_bid: RefCounted = null

	while true:
		attempts += 1
		var pool = _build_full_deck()
		pool.shuffle()
		var hand: Array[Domino] = []
		for i in range(7):
			hand.append(pool[i])

		var bid_decisions: Array = []
		var bid = AIPlayer.decide_bid(hand, 0, null, settings, false, "expert", bid_decisions)
		var decision = bid_decisions[0]

		if decision["should_bid"]:
			found_hand = hand
			found_decision = decision
			found_bid = bid
			break

		if attempts > 100000:
			push_error("No bid-worthy hand found in 100000 attempts — something is off.")
			quit(1)
			return

	var eval = found_decision["eval"]
	var tiles_str: Array = []
	for d in found_hand:
		tiles_str.append(d.debug_string())

	var out = {
		"attempts": attempts,
		"tiles": tiles_str,
		"trump": eval.get("trump", -1),
		"trump_count": eval.get("trump_count", 0),
		"has_double_trump": eval.get("has_double_trump", false),
		"estimated_points": eval.get("estimated_points", 0.0),
		"estimated_tricks": eval.get("estimated_tricks", 0.0),
		"auction_stance": eval.get("auction_stance", "unknown"),
		"stance_bias": eval.get("stance_bias", 0.0),
		"target_bid_logged": found_decision.get("target_bid", -1),
		"issued_bid_type": found_bid.type,
		"issued_bid_value": found_bid.value,
	}

	var f = FileAccess.open("res://headless/job3_fixed_hand.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()

	print("Found bid-worthy hand after %d attempts." % attempts)
	print("Tiles: ", tiles_str)
	print("Trump: %d  trump_count=%d  has_double_trump=%s" % [eval.get("trump", -1), eval.get("trump_count", 0), str(eval.get("has_double_trump", false))])
	print("estimated_points=%.2f  target_bid(logged)=%d  issued_bid=%d  auction_stance=%s" % [
		eval.get("estimated_points", 0.0), found_decision.get("target_bid", -1), found_bid.value, eval.get("auction_stance", "unknown")
	])
	print("Written to scripts/job3_fixed_hand.json")

	quit(0)
