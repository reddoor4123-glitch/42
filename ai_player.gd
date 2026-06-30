class_name AIPlayer
extends RefCounted

# ─── HAND EVALUATION ─────────────────────────────────────────────────────────

# Score a hand assuming a given trump suit.
# Returns a dictionary with estimated points, tricks, and confidence.
static func evaluate_hand(hand: Array[Domino], trump: int) -> Dictionary:
	var trump_dominos: Array[Domino] = []
	var off_dominos: Array[Domino] = []
	var counter_points := 0      # Points from 5s and 10s we likely win
	var estimated_tricks := 0.0
	var has_double_trump := false

	for d in hand:
		if d.is_trump(trump):
			trump_dominos.append(d)
			if d.is_double():
				has_double_trump = true
		else:
			off_dominos.append(d)

	# Trump tricks: each trump domino is likely to win a trick
	# Double trump is almost guaranteed; others depend on how many we hold
	var trump_count = trump_dominos.size()
	if trump_count >= 1:
		estimated_tricks += trump_count * 0.85
	if has_double_trump:
		estimated_tricks += 0.15  # Bonus for certainty

	# Off-suit: high dominos in suits where we hold 2+ are stronger
	var suit_counts := {}
	for d in off_dominos:
		var suit = d.get_suit(trump)
		suit_counts[suit] = suit_counts.get(suit, 0) + 1

	for d in off_dominos:
		var suit = d.get_suit(trump)
		var rank = d.get_rank(trump)
		var count_in_suit = suit_counts.get(suit, 0)
		# Double off-suit: wins if no one else leads that suit with trump
		if d.is_double():
			estimated_tricks += 0.5
		# High rank in a suit we hold multiple of = likely winner
		elif rank >= 4 and count_in_suit >= 2:
			estimated_tricks += 0.4
		elif rank >= 5:
			estimated_tricks += 0.3

	# Count points we're likely to win
	# We win counters if we have the winning domino in that suit or can trump them
	for d in hand:
		var pip = d.pip_sum()
		if pip == 5 or pip == 10:
			if d.is_trump(trump):
				# Trump counters: very likely to win them
				counter_points += pip * 0.9
			elif d.get_rank(trump) >= 4:
				# High off-suit counter
				counter_points += pip * 0.6
			else:
				# Low counter — might lose it
				counter_points += pip * 0.3

	# Add trick points (1 per trick)
	var total_estimated_points = counter_points + estimated_tricks

	return {
		"trump": trump,
		"trump_count": trump_count,
		"has_double_trump": has_double_trump,
		"estimated_tricks": estimated_tricks,
		"estimated_points": total_estimated_points,
		"counter_points": counter_points,
	}

# Find the best trump suit for this hand
static func best_trump(hand: Array[Domino]) -> Dictionary:
	var best_eval := {}
	var best_score := -1.0
	for suit in range(7):
		var eval = evaluate_hand(hand, suit)
		var score = eval["estimated_points"] + eval["trump_count"] * 2.0
		if eval.get("has_double_trump", false):
			score += 3.0
		if score > best_score:
			best_score = score
			best_eval = eval
	return best_eval

# ─── BID DECISION ────────────────────────────────────────────────────────────

# Returns a Bid for this AI player given the current high bid and settings.
static func decide_bid(
	hand: Array[Domino],
	player_id: int,
	current_high: RefCounted,  # Bid or null
	settings: RefCounted,      # GameSettings
	is_forced: bool = false
) -> RefCounted:

	var BidScript = load("res://bid.gd")
	var eval = best_trump(hand)
	var est_pts = eval["estimated_points"]
	var trump_count = eval["trump_count"]

	# Determine what minimum bid we need to beat
	var min_points := 30
	var min_marks := 99  # Effectively disabled unless we want to bid marks
	var points_still_legal := true

	if current_high != null and current_high.type == BidScript.Type.POINTS:
		min_points = current_high.value + 1
		if min_points > 42:
			points_still_legal = false
	elif current_high != null and current_high.type == BidScript.Type.MARKS:
		points_still_legal = false
		min_marks = current_high.value + 1

	# Decide on a point bid
	# We bid if we think we can win at least that many points
	# Conservative buffer: bid about 80% of what we estimate
	var bid_points = int(est_pts * 0.80)
	bid_points = clampi(bid_points, 30, 42)

	# Only bid if our estimate clears the minimum with some confidence
	var confidence_threshold = 28.0  # Minimum estimated points to bid at all
	if is_forced:
		confidence_threshold = 0.0  # Forced bid — bid regardless

	if est_pts >= confidence_threshold and points_still_legal and bid_points >= min_points:
		return BidScript.new(BidScript.Type.POINTS, bid_points, player_id)

	# Consider a 1-mark bid if hand is very strong
	if trump_count >= 5 and eval["has_double_trump"] and min_marks <= 1:
		return BidScript.new(BidScript.Type.MARKS, 1, player_id)

	# Pass (or forced minimum)
	if is_forced:
		return BidScript.new(BidScript.Type.POINTS, 30, player_id)

	return BidScript.new(BidScript.Type.PASS, 0, player_id)

# ─── PLAY DECISION ───────────────────────────────────────────────────────────

# Choose a domino to play. Basic strategy — will be expanded later.
static func decide_play(
	legal: Array[Domino],
	hand: Array[Domino],
	trick: RefCounted,        # Trick
	player_id: int,
	partner_id: int,
	trump: int,
	reason_log: Array         # Pass an array to receive the reasoning string
) -> Domino:

	var plays = trick.plays
	var is_leading = plays.size() == 0
	var lead_suit = trick.lead_suit

	# ── LEADING ──────────────────────────────────────────────────────────────
	if is_leading:
		# Lead highest trump if we have the double (we likely control trump)
		var trumps = legal.filter(func(d): return d.is_trump(trump))
		if trumps.size() >= 3:
			var best = _highest_in(trumps, trump, lead_suit)
			reason_log.append("Led trump — holding %d trumps, drew out opponents" % trumps.size())
			return best

		# Lead a counter if we have a strong one (high rank in suit)
		var counters = legal.filter(func(d): return d.pip_sum() == 5 or d.pip_sum() == 10)
		for c in counters:
			if c.get_rank(trump, "high", lead_suit) >= 4:
				reason_log.append("Led high counter %s to secure points" % c.debug_string())
				return c

		# Lead highest off-suit domino
		var best = _highest_in(legal, trump, lead_suit)
		reason_log.append("Led high domino %s" % best.debug_string())
		return best

	# ── FOLLOWING ────────────────────────────────────────────────────────────
	var partner_winning = _partner_is_winning(plays, partner_id, trump, lead_suit)

	# If partner is winning, don't waste high cards — play lowest legal
	if partner_winning:
		var lowest = _lowest_in(legal, trump, lead_suit)
		reason_log.append("Partner winning — played low %s to save strength" % lowest.debug_string())
		return lowest

	# Try to win the trick — play lowest winning card
	var current_winner_domino = _current_winning_domino(plays, trump, lead_suit)
	var can_win = legal.filter(func(d): return _beats(d, current_winner_domino, trump, lead_suit))

	if can_win.size() > 0:
		# Prefer winning with a counter if possible
		var counter_wins = can_win.filter(func(d): return d.pip_sum() == 5 or d.pip_sum() == 10)
		if counter_wins.size() > 0:
			var chosen = _lowest_in(counter_wins, trump, lead_suit)
			reason_log.append("Won trick with counter %s" % chosen.debug_string())
			return chosen
		var chosen = _lowest_in(can_win, trump, lead_suit)
		reason_log.append("Won trick with %s" % chosen.debug_string())
		return chosen

	# Can't win — discard lowest value non-counter
	var non_counters = legal.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
	if non_counters.size() > 0:
		var discard = _lowest_in(non_counters, trump, lead_suit)
		reason_log.append("Couldn't win — discarded low %s" % discard.debug_string())
		return discard

	var discard = _lowest_in(legal, trump, lead_suit)
	reason_log.append("Couldn't win — discarded %s to avoid giving points" % discard.debug_string())
	return discard

# ─── HELPERS ─────────────────────────────────────────────────────────────────

static func _highest_in(dominos: Array, trump: int, lead_suit: int) -> Domino:
	var best: Domino = dominos[0]
	for d in dominos:
		if d.get_rank(trump, "high", lead_suit) > best.get_rank(trump, "high", lead_suit):
			best = d
	return best

static func _lowest_in(dominos: Array, trump: int, lead_suit: int) -> Domino:
	var lowest: Domino = dominos[0]
	for d in dominos:
		if d.get_rank(trump, "high", lead_suit) < lowest.get_rank(trump, "high", lead_suit):
			lowest = d
	return lowest

static func _partner_is_winning(plays: Array, partner_id: int, trump: int, lead_suit: int) -> bool:
	if plays.size() == 0:
		return false
	var best_play = plays[0]
	var best_d: Domino = best_play["domino"]
	for play in plays:
		var d: Domino = play["domino"]
		if _beats(d, best_d, trump, lead_suit):
			best_play = play
			best_d = d
	return best_play["player"] == partner_id

static func _current_winning_domino(plays: Array, trump: int, lead_suit: int) -> Domino:
	var best: Domino = plays[0]["domino"]
	for play in plays:
		var d: Domino = play["domino"]
		if _beats(d, best, trump, lead_suit):
			best = d
	return best

static func _beats(challenger: Domino, current: Domino, trump: int, lead_suit: int) -> bool:
	var c_suit = challenger.get_suit(trump, "high", lead_suit)
	var b_suit = current.get_suit(trump, "high", lead_suit)
	var c_rank = challenger.get_rank(trump, "high", lead_suit)
	var b_rank = current.get_rank(trump, "high", lead_suit)

	var c_is_trump = (c_suit == trump)
	var b_is_trump = (b_suit == trump)

	if c_is_trump and not b_is_trump:
		return true
	if not c_is_trump and b_is_trump:
		return false
	if c_suit != b_suit:
		return false  # Different non-trump suits — can't beat
	return c_rank > b_rank
