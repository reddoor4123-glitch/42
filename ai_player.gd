class_name AIPlayer
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
#  AI DESIGN PHILOSOPHY
# ═══════════════════════════════════════════════════════════════════
# The goal is not technical perfection. The goal is emotional authenticity.
#
# Partner trusts the human player and plays for the team's contract.
# Opponents play solid, honest 42 — not bloodthirsty, not stupid.
#
# Decision axes (implemented progressively):
#   Phase 1: Cooperation — partner behavior, team-first decisions  ← YOU ARE HERE
#   Phase 2: Risk       — bidding personality and play aggression
#   Phase 3: Opportunism — expert ability to capitalize on mistakes
#   Phase 4: Awareness  — inference, void tracking, pattern recognition
#
# Future: Confidence (decision certainty influencing play selection)
# Future: Named personalities as presets over these axes
# Future: Family-observed behaviors as personality templates
#
# "That partner plays just like my uncle." — that's the target.
# ═══════════════════════════════════════════════════════════════════

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
	is_forced: bool = false,
	difficulty: String = "standard"
) -> RefCounted:

	var BidScript = load("res://bid.gd")
	var eval = best_trump(hand)
	var est_pts = eval["estimated_points"]
	var trump_count = eval["trump_count"]

	# Behavioral profile — difficulty adjusts social tone, not intelligence.
	# Easy: underestimates hand, needs more cushion, won't push auctions hard.
	# Hard: slight optimism, bids more readily, competes harder.
	var confidence_multiplier: float
	var bid_conservatism: float
	var aggression_cap: int
	match difficulty:
		"easy":
			confidence_multiplier = 0.75
			bid_conservatism = 4.0
			aggression_cap = 2
		"hard":
			confidence_multiplier = 1.1
			bid_conservatism = 1.0
			aggression_cap = 5
		_:  # "standard"
			confidence_multiplier = 1.0
			bid_conservatism = 2.0
			aggression_cap = 3
	est_pts = est_pts * confidence_multiplier

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

	# Compute bid points — aggression_cap limits how far above minimum we'll push.
	var bid_points = int(est_pts * 0.80)
	bid_points = clampi(bid_points, min_points, min(min_points + aggression_cap, 42))

	# Only bid if our estimate clears the threshold with enough confidence.
	var confidence_threshold = 28.0 + bid_conservatism
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

# Choose a domino to play.
# difficulty: "beginner" | "standard" | "expert" — Phase 2 wires this to settings.
# is_partner: true when this AI player is the human's partner (seat +2 from human).
static func decide_play(
	legal: Array[Domino],
	hand: Array[Domino],
	trick: RefCounted,        # Trick
	player_id: int,
	partner_id: int,
	trump: int,
	reason_log: Array,        # Pass an array to receive the reasoning string
	difficulty: String = "standard",
	is_partner: bool = false
) -> Domino:

	var plays = trick.plays
	var is_leading = plays.size() == 0
	var lead_suit = trick.lead_suit

	# ── PARTNER BEHAVIOR ──────────────────────────────────────────────────────
	# When is_partner == true, partner_id == human_seat.
	# Every decision passes this test: "Does this increase our team's chance
	# of making the contract?" The most important single rule: never trump a
	# trick the human is already winning.
	if is_partner:
		if is_leading:
			# Lead high non-trump non-counter: gives human a safe suit to follow
			# without burning trump or risking a vulnerable point card.
			var off_safe = legal.filter(func(d):
				return not d.is_trump(trump) and d.pip_sum() != 5 and d.pip_sum() != 10)
			if off_safe.size() > 0:
				var best = _highest_in(off_safe, trump, lead_suit)
				reason_log.append("Led to give partner a safe follow suit — played %s" % best.debug_string())
				return best

			# Draw out opponents' trump when we hold enough to control the suit.
			var trumps = legal.filter(func(d): return d.is_trump(trump))
			if trumps.size() >= 3:
				var best = _highest_in(trumps, trump, lead_suit)
				reason_log.append("Led trump — holding %d trumps, drawing out opponents — played %s" % [trumps.size(), best.debug_string()])
				return best

			# Counter protection: prefer non-counter leads even if that's all that's left.
			var non_counters_lead = legal.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
			if non_counters_lead.size() > 0:
				var best = _highest_in(non_counters_lead, trump, lead_suit)
				reason_log.append("Led high non-counter — played %s" % best.debug_string())
				return best

			var best = _highest_in(legal, trump, lead_suit)
			reason_log.append("Protecting counters — led best available — played %s" % best.debug_string())
			return best

		# ── FOLLOWING as Partner ──────────────────────────────────────────────
		var human_is_winning = _partner_is_winning(plays, partner_id, trump, lead_suit)

		# THE cardinal rule: never steal a trick the human is winning.
		# Throw off lowest non-counter; only burn a counter if nothing else is available.
		if human_is_winning:
			var non_counters_follow = legal.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
			if non_counters_follow.size() > 0:
				var lowest = _lowest_in(non_counters_follow, trump, lead_suit)
				reason_log.append("Partner winning — clearing the way, protecting counters — played %s" % lowest.debug_string())
				return lowest
			var lowest = _lowest_in(legal, trump, lead_suit)
			reason_log.append("Partner winning — no non-counter to spare — played %s" % lowest.debug_string())
			return lowest

		# Human is not currently winning — try to win for the team.
		var current_winner_domino = _current_winning_domino(plays, trump, lead_suit)
		var can_win = legal.filter(func(d): return _beats(d, current_winner_domino, trump, lead_suit))

		if can_win.size() > 0:
			if difficulty == "easy":
				# Easy Partner: always secure the trick without second-guessing card economy.
				# TODO Phase 2: Easy Partner should signal rescue bid availability
				var chosen = _lowest_in(can_win, trump, lead_suit)
				reason_log.append("Easy mode — securing trick for partner — played %s" % chosen.debug_string())
				return chosen

			# Standard and Hard: prefer non-trump winners to save trump.
			var non_trump_wins = can_win.filter(func(d): return not d.is_trump(trump))
			if non_trump_wins.size() > 0:
				var chosen = _lowest_in(non_trump_wins, trump, lead_suit)
				reason_log.append("Winning for team — human couldn't hold it — played %s" % chosen.debug_string())
				return chosen

			# Only trump can win.
			if difficulty == "hard":
				# Hard Partner: no trust rule — play optimally for the contract.
				var chosen = _lowest_in(can_win, trump, lead_suit)
				reason_log.append("Playing for contract — optimal play — played %s" % chosen.debug_string())
				return chosen

			# Standard trust rule: if the human already played and we're not last,
			# a later player might handle this — hold trump rather than overriding
			# what the human set up.
			var human_play = _find_player_play(plays, partner_id)
			var is_last_player = (plays.size() == 3)
			if human_play != null and not is_last_player:
				var trump_held = _lowest_in(can_win, trump, lead_suit)
				var safe_discard = legal.filter(func(d):
					return d.pip_sum() != 5 and d.pip_sum() != 10 and not d.is_trump(trump))
				if safe_discard.size() > 0:
					var discard = _lowest_in(safe_discard, trump, lead_suit)
					reason_log.append("Trusting partner's play — holding trump %s for later — played %s" % [trump_held.debug_string(), discard.debug_string()])
					return discard

			# Last player or no safe discard — trump in to secure the trick.
			var chosen = _lowest_in(can_win, trump, lead_suit)
			reason_log.append("Winning for team — trumping in for partner — played %s" % chosen.debug_string())
			return chosen

		# Can't win — discard to protect point cards.
		if difficulty == "easy":
			# Easy Partner: more aggressive counter protection — discard highest
			# non-counter non-trump first to protect every pip we have.
			var safe_high = legal.filter(func(d):
				return d.pip_sum() != 5 and d.pip_sum() != 10 and not d.is_trump(trump))
			if safe_high.size() > 0:
				var discard = _highest_in(safe_high, trump, lead_suit)
				reason_log.append("Easy mode — protecting team counters — played %s" % discard.debug_string())
				return discard

		var non_counters_discard = legal.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
		if non_counters_discard.size() > 0:
			var discard = _lowest_in(non_counters_discard, trump, lead_suit)
			reason_log.append("Can't win — protecting counter — played %s" % discard.debug_string())
			return discard
		var discard = _lowest_in(legal, trump, lead_suit)
		reason_log.append("No choice — discarding counter — played %s" % discard.debug_string())
		return discard

	# ── OPPONENT BEHAVIOR ─────────────────────────────────────────────────────
	# Standard: solid casual play — not bloodthirsty, not passive.
	# Easy: conservative opens, backs off human team tricks unless obvious.
	# Hard: compete harder (handled in bidding); play TODO Phase 3 opportunism.

	if is_leading:
		# Easy: never lead trump on the opening trick of the hand.
		if difficulty == "easy" and hand.size() == 7:
			var non_trumps_easy = legal.filter(func(d): return not d.is_trump(trump))
			if non_trumps_easy.size() > 0:
				var best = _highest_in(non_trumps_easy, trump, lead_suit)
				reason_log.append("Easy mode — conservative opening — played %s" % best.debug_string())
				return best

		# TODO Phase 3: Hard — target known voids from trick history here.

		# Lead highest trump if we hold enough to control the suit.
		var trumps = legal.filter(func(d): return d.is_trump(trump))
		if trumps.size() >= 3:
			var best = _highest_in(trumps, trump, lead_suit)
			reason_log.append("Led trump — holding %d trumps, drawing out opponents — played %s" % [trumps.size(), best.debug_string()])
			return best

		# Lead a strong counter if we're confident it will win.
		var counters = legal.filter(func(d): return d.pip_sum() == 5 or d.pip_sum() == 10)
		for c in counters:
			if c.get_rank(trump, "high", lead_suit) >= 4:
				reason_log.append("Led high counter %s to secure points" % c.debug_string())
				return c

		# Lead highest available domino.
		var best = _highest_in(legal, trump, lead_suit)
		reason_log.append("Led high domino — played %s" % best.debug_string())
		return best

	# ── FOLLOWING as Opponent ──────────────────────────────────────────────────
	var partner_winning = _partner_is_winning(plays, partner_id, trump, lead_suit)

	# Partner is winning — save strength, don't over-contribute.
	if partner_winning:
		var lowest = _lowest_in(legal, trump, lead_suit)
		reason_log.append("Partner winning — played low %s to save strength" % lowest.debug_string())
		return lowest

	# Easy: back off when the human's team is currently winning the trick.
	# Only attack if winner rank > 10 (impossible at rank 0-6, so effectively never).
	# This makes Easy opponents feel unintimidating — they don't pile on the human.
	if difficulty == "easy" and plays.size() > 0:
		var winner_id = _find_current_winner_id(plays, trump, lead_suit)
		var winner_is_human_team = (winner_id % 2 != player_id % 2)
		if winner_is_human_team:
			var winning_d = _current_winning_domino(plays, trump, lead_suit)
			if winning_d.get_rank(trump, "high", lead_suit) <= 10:
				var non_c = legal.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
				if non_c.size() > 0:
					var discard = _lowest_in(non_c, trump, lead_suit)
					reason_log.append("Easy mode — not pressing marginal advantage — played %s" % discard.debug_string())
					return discard
				var discard = _lowest_in(legal, trump, lead_suit)
				reason_log.append("Easy mode — not pressing advantage — played %s" % discard.debug_string())
				return discard

	# Try to win the trick.
	var current_winner_domino = _current_winning_domino(plays, trump, lead_suit)
	var can_win = legal.filter(func(d): return _beats(d, current_winner_domino, trump, lead_suit))

	if can_win.size() > 0:
		# Win with a counter if possible — pick up the points.
		var counter_wins = can_win.filter(func(d): return d.pip_sum() == 5 or d.pip_sum() == 10)
		if counter_wins.size() > 0:
			var chosen = _lowest_in(counter_wins, trump, lead_suit)
			reason_log.append("Won trick with counter — played %s" % chosen.debug_string())
			return chosen
		var chosen = _lowest_in(can_win, trump, lead_suit)
		reason_log.append("Won trick — played %s" % chosen.debug_string())
		return chosen

	# Can't win — discard lowest non-counter to protect point cards.
	var non_counters = legal.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
	if non_counters.size() > 0:
		var discard = _lowest_in(non_counters, trump, lead_suit)
		reason_log.append("Couldn't win — discarding low non-counter — played %s" % discard.debug_string())
		return discard
	var discard = _lowest_in(legal, trump, lead_suit)
	reason_log.append("Couldn't win — discarding counter — played %s" % discard.debug_string())
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

# Returns the player_id of whoever is currently winning the trick.
static func _find_current_winner_id(plays: Array, trump: int, lead_suit: int) -> int:
	if plays.size() == 0:
		return -1
	var best_play = plays[0]
	var best_d: Domino = best_play["domino"]
	for play in plays:
		var d: Domino = play["domino"]
		if _beats(d, best_d, trump, lead_suit):
			best_play = play
			best_d = d
	return best_play["player"]

# Returns the play dict for a given player in the current trick, or null if
# that player hasn't played yet.
static func _find_player_play(plays: Array, player_id: int):
	for play in plays:
		if play["player"] == player_id:
			return play
	return null

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
