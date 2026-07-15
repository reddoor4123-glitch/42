class_name AIPlayer
extends RefCounted

# ═══════════════════════════════════════════════════════════════════
#  AI DESIGN DOCTRINE — see AI_Design_Doctrine.md
# ═══════════════════════════════════════════════════════════════════
# The full design philosophy, the Decision Geometry concept, the
# Knowledge/Evaluation difficulty litmus test, and the Trick Objectives
# naming convention all live in AI_Design_Doctrine.md now — read it
# before proposing a change to decide_bid() or decide_play(). Kept out
# of this file so the doctrine (which should barely ever change) stops
# drifting out of sync with the code (which changes constantly) — see
# that document's own note on why CONTEST_IF_WORTHWHILE sat in this
# header for weeks after it was actually retired.
#
# For the current, exact branch-by-branch state of decide_play(), see
# Phase3_Objective_Audit_REWRITE_July14_2026.md instead of either of the
# above — this comment and AI_Design_Doctrine.md both intentionally
# avoid branch-level detail that would go stale.
# ═══════════════════════════════════════════════════════════════════

# ─── DIFFICULTY PROFILES ─────────────────────────────────────────────────────
# Single source of truth for all AI behavioral parameters.
# Add new modes here; decide_bid() and decide_play() read from this dict.
const AI_MODES := {
	"beginner": {
		"risk_bias":        -0.25,
		"max_overbid":      2,
		"vigilance":        "none",
		"opportunism":      0.0,
	},
	"standard": {
		"risk_bias":        0.0,
		"max_overbid":      4,
		"vigilance":        "none",
		"opportunism":      0.6,
	},
	"expert": {
		"risk_bias":        0.25,
		"max_overbid":      6,
		"vigilance":        "full",
		"opportunism":      1.0,
	},
}

# ─── HAND EVALUATION ─────────────────────────────────────────────────────────

# Score a hand assuming a given trump suit.
# Returns a dictionary with estimated points and tricks.
static func evaluate_hand(hand: Array[Domino], trump: int) -> Dictionary:
	var trump_dominos: Array[Domino] = []
	var off_dominos: Array[Domino] = []
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
	# Score each trump tile individually based on its rank within the suit.
	# Flat per-trump rates ignored rank entirely — a rank-6 trump and a rank-1
	# trump scored identically. This caused best_trump() to select wrong suits
	# on marginal hands where off-suit accidents broke the tie.
	#
	# Scale: double=0.95, rank 6=0.85, rank 3=0.60, rank 0=0.35.
	# The has_double_trump bonus is removed — the double earns its extra weight
	# through the rank calculation (0.95 vs 0.85), not a separate addend.
	for d in trump_dominos:
		var rank = d.get_rank(trump)
		var win_prob: float
		if d.is_double():
			win_prob = 0.95
		else:
			win_prob = 0.35 + (rank / 6.0) * 0.50
		estimated_tricks += win_prob

	# Off-suit: high dominos in suits where we hold 2+ are stronger
	var suit_counts := {}
	for d in off_dominos:
		var suit = d.get_suit(trump)
		suit_counts[suit] = suit_counts.get(suit, 0) + 1

	# Off-suit doubles are collected separately and scored as a group below —
	# individual rank-scaling plus a compounding multi-double bonus, rather
	# than each double being scored independently inline. The trump double
	# (if any) is never in off_dominos, so it is naturally excluded from all
	# of this — it's already credited via the trump scoring block above.
	var off_suit_doubles: Array[Domino] = []

	for d in off_dominos:
		var suit = d.get_suit(trump)
		var rank = d.get_rank(trump)
		var count_in_suit = suit_counts.get(suit, 0)
		if d.is_double():
			off_suit_doubles.append(d)
			continue
		# High rank in a suit we hold multiple of = likely winner
		elif rank >= 4 and count_in_suit >= 2:
			estimated_tricks += 0.4
		elif rank >= 5:
			estimated_tricks += 0.3
		elif rank >= 4:
			estimated_tricks += 0.2

	# ── OFF-SUIT DOUBLES SCORING ────────────────────────────────────────────
	# Doubles are always strong leads; higher doubles are additionally able
	# to recapture the lead if lost, which lower doubles cannot. Multiple
	# held doubles compound in value beyond a flat per-double sum, since
	# each additional double increases how often the hand can dictate play.
	#
	# NOTE: a domino's pip value (d.left, since left == right for doubles)
	# is used directly for rank-scaling here, NOT Domino.get_rank() — that
	# function returns a flat 13 for any non-trump double by convention,
	# which is correct for play-order ranking but not usable as a strength
	# scale here.
	for i in range(off_suit_doubles.size()):
		var d = off_suit_doubles[i]
		var pip_value = d.left
		var win_prob = 0.55 + (pip_value / 6.0) * 0.25
		estimated_tricks += win_prob

		# Compounding bonus for each double beyond the first.
		match i:
			1: estimated_tricks += 0.3
			2: estimated_tricks += 0.5
			3: estimated_tricks += 0.7

	# Specific bracket bonus: holding both 4:4 and 6:6 means the 6:4 (a
	# 10-count) cannot hide from this hand in either direction. This is the
	# only double-pairing that brackets a counter worth calling out — other
	# double pairs either bracket a non-counter or bracket the same 5-count
	# in a way that's already true of nearly every double-heavy hand, so it
	# isn't a distinguishing signal. Deliberately narrow by design.
	var has_44 = off_suit_doubles.any(func(d): return d.left == 4 and d.right == 4)
	var has_66 = off_suit_doubles.any(func(d): return d.left == 6 and d.right == 6)
	if has_44 and has_66:
		estimated_tricks += 0.2

	# ── CAPTURE MODEL ─────────────────────────────────────────────────────────
	# Primary axis: expected tricks → expected points captured from the table.
	# This is the ONLY value signal used for bidding strength.
	var expected_capture := estimated_tricks * 6.0

	# ── REALIZATION SIGNAL ─────────────────────────────────────────────────────
	# Measures how well known counter positions align with expected trick wins:
	# positive when counters are protected (likely to land in tricks this hand
	# wins), negative when they're exposed (likely to leak to opponents). Folded
	# into estimated_points below — full inclusion, no scaling factor,
	# benchmark-verified July 11-12, 2026 (see AI_Bid_Behavior_Bug_Log.md,
	# finding #2).
	var baseline_share := estimated_tricks / 7.0
	var realization_bias := 0.0
	var counter_points := 0.0  # logging only

	for d in hand:
		var pip := d.pip_sum()
		if pip == 5 or pip == 10:
			var win_prob: float
			if d.is_trump(trump):
				win_prob = 0.9
			elif d.get_rank(trump) >= 4:
				win_prob = 0.6
			else:
				win_prob = 0.3
			counter_points += pip * win_prob
			realization_bias += (win_prob - baseline_share) * pip

	# Counters the hand can realize (or is likely to leak) shift real
	# contract points away from the flat 6-per-trick average. Full
	# inclusion benchmark-verified July 11-12, 2026.
	var estimated_points := expected_capture + realization_bias

	return {
		"trump":            trump,
		"trump_count":      trump_count,
		"has_double_trump": has_double_trump,
		"estimated_tricks": estimated_tricks,
		"expected_capture": expected_capture,   # primary bidding signal
		"counter_points":   counter_points,     # diagnostic only
		"realization_bias": realization_bias,   # folded into estimated_points below
		"estimated_points": estimated_points,   # used by best_trump / logging / bidding
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
	difficulty: String = "standard",
	bid_decisions: Array = []   # out-parameter, mirrors reason_log convention
) -> RefCounted:

	var BidScript = load("res://bid.gd")

	# ── LAYER 1: EVALUATION (truth — do not modify) ───────────────────────────
	var eval = best_trump(hand)
	var est_pts: float = eval["estimated_points"]
	var trump_count: int = eval["trump_count"]

	# ── LAYER 2: SIGNAL COMBINER ─────────────────────────────────────────────
	# Layer 2 does not score the hand — Layer 1 already did that.
	# Layer 2 combines three independent signals into a single bid confidence:
	#   (A) EV signal      — what is this hand worth?       (Layer 1 output)
	#   (B) Control signal — how reliable is that value?    (structural shape)
	#   (C) Risk signal    — how aggressive is this player? (AI_MODES personality)
	# No signal overrides another. All three add. The threshold is fixed at 28.

	var mode = AI_MODES.get(difficulty, AI_MODES["standard"])
	var risk_bias: float = mode["risk_bias"]
	var max_overbid: int = mode["max_overbid"]

	# (A) EV signal — direct from Layer 1, shifted by personality
	var ev_score := est_pts + risk_bias * 4.0

	# (B) Control signal — structural confidence, capped and smooth
	#     Scales trick expectation lightly, then adds structure bonuses.
	#     Does not replace EV; only nudges confidence upward.
	var est_tricks: float = eval.get("estimated_tricks", 0.0)
	var control_score := est_tricks * 6.0 * 0.12
	if eval.get("has_double_trump", false):
		control_score += 2.5
	if eval.get("trump_count", 0) >= 4:
		control_score += 1.5
	if eval.get("trump_count", 0) >= 5:
		control_score += 3.0
	if eval.get("trump_count", 0) >= 6:
		control_score += 2.0

	# (C) Auction stance — classifies bid intent before finalizing target
	# This is a shape modifier on decision pressure, not a replacement of EV.
	# Stance biases the final score and target upward or downward to express
	# role (opener vs anchor vs defensive) without changing evaluation truth.
	var has_double_trump: bool = eval.get("has_double_trump", false)
	var auction_stance := "anchor"
	if est_tricks >= 4.3 and has_double_trump:
		auction_stance = "pressure_opener"
	elif est_tricks >= 4.0 and eval.get("trump_count", 0) >= 4:
		auction_stance = "solid_opener"
	elif ev_score >= 24.0:
		auction_stance = "competitive"
	else:
		auction_stance = "defensive"

	var stance_bias := 0.0
	match auction_stance:
		"pressure_opener": stance_bias = 2.0
		"solid_opener":    stance_bias = 1.0
		"competitive":     stance_bias = 0.0
		"defensive":       stance_bias = -1.5

	# (D) Final unified decision score
	var final_score := ev_score + control_score + stance_bias
	var should_bid: bool = final_score >= 28.0
	var target_bid: int = roundi(est_pts + risk_bias * 3.0 + stance_bias)
	target_bid = max(28, target_bid)
	target_bid = min(target_bid, roundi(est_pts) + max_overbid)

	eval["auction_stance"] = auction_stance
	eval["stance_bias"]    = stance_bias

	var control_hand := false  # kept for logging continuity

	# ── LAYER 3: EXECUTION (auction rules — no re-evaluation here) ───────────
	# - respect current highest bid
	# - respect legal minimum increments
	# - enforce max_overbid cap
	# - do NOT re-score the hand here

	var points_still_legal := true
	var min_points := 30

	if current_high != null and current_high.type == BidScript.Type.POINTS:
		min_points = current_high.value + 1
		if min_points > 42:
			points_still_legal = false
	elif current_high != null and current_high.type != BidScript.Type.POINTS:
		# Any non-points bid on the table (MARKS, NELLO, SEVENS, PLUNGE, SPLASH)
		# already has a mark-equivalent of at least 0.42 — a points bid
		# (max 42 = 0.42) can never legally raise it. Points is the only bid
		# type that gets a "raise by value" path; everything else closes points
		# off entirely.
		points_still_legal = false

	if is_forced:
		should_bid = true
		target_bid = max(target_bid, 30)

	# If Layer 2 decided to bid but target is below the legal minimum, raise it.
	# should_bid is already true — this preserves intent rather than silently passing.
	if should_bid and target_bid < min_points:
		target_bid = min_points

	# Marks bid — evaluated BEFORE the points return (Defect 1: marks was
	# previously unreachable on any hand strong enough to trigger should_bid).
	# Requires trump control (5+ trump, holds the double) AND off-suit
	# viability — an off-suit double, or trump_count >= 6 as an alternative
	# path that bypasses the off-suit requirement entirely (Defect 2: the old
	# gate only checked trump shape, with no way to see exposed off-suit risk).
	# See AI_Bid_Behavior_Bug_Log.md, Pattern A.
	var off_suit_has_double: bool = hand.any(func(d): return d.is_double() and not d.is_trump(eval["trump"]))
	if trump_count >= 5 and eval["has_double_trump"] \
	   and (off_suit_has_double or trump_count >= 6) \
	   and (current_high == null or current_high.type != BidScript.Type.MARKS):
		var marks_bid = BidScript.new(BidScript.Type.MARKS, 1, player_id)
		_log_bid_decision(hand, eval, difficulty, risk_bias, max_overbid,
			should_bid, target_bid, est_pts, current_high, marks_bid, control_hand, bid_decisions)
		return marks_bid

	if should_bid and points_still_legal:
		if min_points <= target_bid:
			var final_bid = min(target_bid, min_points + max_overbid)
			final_bid = max(final_bid, min_points)
			final_bid = min(final_bid, 42)
			var pts_bid = BidScript.new(BidScript.Type.POINTS, final_bid, player_id)
			_log_bid_decision(hand, eval, difficulty, risk_bias, max_overbid,
				should_bid, target_bid, est_pts, current_high, pts_bid, control_hand, bid_decisions)
			return pts_bid

	# Forced minimum fallback
	if is_forced:
		var forced_bid = BidScript.new(BidScript.Type.POINTS, 30, player_id)
		_log_bid_decision(hand, eval, difficulty, risk_bias, max_overbid,
			should_bid, target_bid, est_pts, current_high, forced_bid, control_hand, bid_decisions)
		return forced_bid

	var pass_bid = BidScript.new(BidScript.Type.PASS, 0, player_id)
	_log_bid_decision(hand, eval, difficulty, risk_bias, max_overbid,
		should_bid, target_bid, est_pts, current_high, pass_bid, control_hand, bid_decisions)
	return pass_bid

static func _log_bid_decision(
	hand: Array[Domino],
	eval: Dictionary,
	difficulty: String,
	risk_bias: float,
	max_overbid: int,
	should_bid: bool,
	target_bid: int,
	est_pts: float,
	current_high: RefCounted,
	result: RefCounted,
	control_hand: bool = false,
	bid_decisions: Array = []
) -> void:
	var hand_str = ", ".join(hand.map(func(d): return d.debug_string()))
	var doubles_in_hand = hand.filter(func(d): return d.is_double()).size()
	var current_high_str = "none"
	if current_high != null:
		current_high_str = str(current_high.value) if current_high.value > 0 else "pass"

	print("── BID DECISION (player %d, %s) ─────────────────────" % [result.player_id, difficulty])
	print("  Hand:          %s" % hand_str)
	print("  Doubles:       %d" % doubles_in_hand)
	print("  Best trump:    suit=%d  trump_count=%d  double_trump=%s" % [
		eval.get("trump", -1),
		eval.get("trump_count", 0),
		str(eval.get("has_double_trump", false))
	])
	print("  Eval:          est_pts=%.1f  expected_capture=%.1f  est_tricks=%.2f  counter_bias=%.2f" % [
		eval.get("estimated_points", 0.0),
		eval.get("expected_capture", 0.0),
		eval.get("estimated_tricks", 0.0),
		eval.get("realization_bias", 0.0)
	])
	print("  Auction:       stance=%s  bias=%.1f" % [
		eval.get("auction_stance", "unknown"),
		eval.get("stance_bias", 0.0)
	])
	var ev_score_log := est_pts + risk_bias * 4.0
	var est_tricks_log: float = eval.get("estimated_tricks", 0.0)
	var control_score_log := est_tricks_log * 6.0 * 0.12
	if eval.get("has_double_trump", false): control_score_log += 2.5
	if eval.get("trump_count", 0) >= 4:    control_score_log += 1.5
	if eval.get("trump_count", 0) >= 5:    control_score_log += 3.0
	if eval.get("trump_count", 0) >= 6:    control_score_log += 2.0
	var stance_bias_log: float = eval.get("stance_bias", 0.0)
	var final_score_log := ev_score_log + control_score_log + stance_bias_log
	print("  Layer 2:       ev=%.1f  control=%.1f  stance=%.1f  final=%.1f  threshold=28.0  should_bid=%s  target=%d" % [
		ev_score_log, control_score_log, stance_bias_log, final_score_log, str(should_bid), target_bid
	])
	print("  Current high:  %s" % current_high_str)
	var BidScript2 = load("res://bid.gd")
	var result_str = "PASS"
	if result.type == BidScript2.Type.POINTS:
		result_str = "%d pts" % result.value
	elif result.type == BidScript2.Type.MARKS:
		result_str = "%d marks" % result.value
	print("  Result:        %s" % result_str)
	print("")

	# Structured capture for HandRecord — parallel to the prints above, not a
	# replacement. hand.duplicate() is a SHALLOW copy: it severs the alias to
	# player.hand (which decide_bid() receives by reference) so that later
	# play_domino() calls erasing dominoes from the live hand during tricks
	# don't retroactively shrink this "hand at bid time" snapshot. The Domino
	# objects inside are never mutated in place, so a shallow copy is enough.
	bid_decisions.append({
		"player_id":   result.player_id,
		"source":      "ai",
		"difficulty":  difficulty,
		"bid_type":    result.type,
		"bid_value":   result.value,
		"hand":        hand.duplicate(),
		"eval":        eval.duplicate(true),
		"should_bid":  should_bid,
		"target_bid":  target_bid,
	})

# ─── PLAY DECISION ───────────────────────────────────────────────────────────

# Choose a domino to play.
# difficulty: "beginner" | "standard" | "expert" — wired to settings.
# is_partner: true when this AI player is the human's partner (seat +2 from human).

# ═══════════════════════════════════════════════════════════════════
#  TRICK OBJECTIVES — see AI_Design_Doctrine.md
# ═══════════════════════════════════════════════════════════════════
# The naming convention for what this function's branch structure
# already decides (PROTECT_PARTNER_WIN, SECURE_FOR_PARTNER, CONTROL_TRUMP,
# etc.) — the concept, not the current branch list — lives in
# AI_Design_Doctrine.md now. For the current, exact list of objectives
# and their branch-by-branch mechanics, see
# Phase3_Objective_Audit_REWRITE_July14_2026.md instead — this comment
# and the doctrine doc both intentionally avoid detail that would go
# stale as decide_play() itself changes.
# ═══════════════════════════════════════════════════════════════════
static func decide_play(
	legal: Array[Domino],
	hand: Array[Domino],
	trick: RefCounted,        # Trick
	player_id: int,
	partner_id: int,
	trump: int,
	reason_log: Array,        # Pass an array to receive the reasoning string
	difficulty: String = "standard",
	is_partner: bool = false,
	contract: int = -1,       # Bid.Type int; -1 = unknown/regular
	bidder_id: int = -1,      # player_id of whoever won the auction
	public_knowledge: PublicKnowledge = null,
	team_points: Array = [],      # [team0_points, team1_points]
	bid_value: int = 0            # 0 means "no margin data available"
) -> Domino:

	var plays = trick.plays
	var is_leading = plays.size() == 0
	var lead_suit = trick.lead_suit

	var BidScript = load("res://bid.gd")

	# ── SEVENS ────────────────────────────────────────────────────────────────────
	# Sevens is not a variation of standard trick play — it is a different game.
	# There are no suits, no trump, no counters, no cooperation strategy, no
	# long-term planning. Every player, every trick, one rule: play the domino
	# in hand whose pip sum is closest to 7. Holding anything back is never
	# correct — one lost trick sets the bid, so there is nothing to save for.
	# This block exits completely; none of the standard evaluation runs.
	if contract == BidScript.Type.SEVENS:
		var chosen = _closest_to_seven(legal)
		var distance = abs(chosen.pip_sum() - 7)
		var away_words = ["Seven.", "One away.", "Two away.", "Three away.", "Four away.", "Five away.", "Six away.", "Seven away."]
		reason_log.append(away_words[distance])
		return chosen

	# ── NELLO ─────────────────────────────────────────────────────────────────────
	# Nello is also a different game. The bidder is trying to lose every trick.
	# Opponents are trying to SET the bidder by ducking — playing low so the
	# bidder's high dominoes are forced to win. Both roles share the same action
	# (play lowest legal) for opposite reasons. Standard evaluation does not apply.
	# Note: the bidder's partner sits out and never reaches this code.
	if contract == BidScript.Type.NELLO:
		var lowest = _lowest_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
		if player_id == bidder_id:
			reason_log.append("Playing low to avoid taking this trick.")
		else:
			reason_log.append("Staying low to make the bidder take this one.")
		return lowest

	# ── MARKS / PLUNGE / SPLASH ──────────────────────────────────────────────────
	# All three share the same objective: win as many tricks as possible
	# (Plunge/Splash require ALL 7, same as Marks — resolve_hand() in game.gd
	# already scores them that way; this just makes play agree with scoring).
	# Counters have no special status — pip values are irrelevant.
	# No counter protection, no pip filtering, no counter preference.
	#
	# NOTE: The cardinal rule (never steal a trick the human is already winning)
	# is preserved here as a safe default. This needs revisit once examples of
	# when partner should override it under Marks are collected. See design notes.
	if contract == BidScript.Type.MARKS or contract == BidScript.Type.PLUNGE or contract == BidScript.Type.SPLASH:
		if is_leading:
			# Under Marks/Plunge/Splash every trick matters immediately — no
			# minimum trump count to wait for the way standard CONTROL_TRUMP
			# has. If any trump is held, lead the best of it to start drawing
			# opponents' trump out right away. Checking trump status first
			# avoids comparing get_rank() across suits, where a trump double
			# and an off-suit double both rank 13 and would otherwise tie.
			var trumps_held = legal.filter(func(d): return d.is_trump(trump))
			var best: Domino
			if trumps_held.size() > 0:
				best = _highest_in(trumps_held, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("Calling in trump — going for every trick.")
			else:
				best = _highest_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("Going for the trick.")
			return best

		var human_winning_marks = _partner_is_winning(plays, partner_id, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
		if is_partner and human_winning_marks:
			var winning_domino_marks = _current_winning_domino(plays, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
			var lowest = _lowest_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
			if _beats(lowest, winning_domino_marks, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed):
				reason_log.append("Nice hand!" if hand.size() == 1 else "I've got this one.")
			else:
				reason_log.append("Good job!" if hand.size() == 1 else "You've got it — saving my strength.")
			return lowest

		var current_winner_marks = _current_winning_domino(plays, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
		var can_win_marks = legal.filter(func(d): return _beats(d, current_winner_marks, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed))
		if can_win_marks.size() > 0:
			var chosen = _lowest_in(can_win_marks, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
			reason_log.append("Taking this trick.")
			return chosen

		# Can't win — discard lowest with no pip filtering.
		var lowest = _lowest_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
		reason_log.append("Can't win this one.")
		return lowest

	var mode = AI_MODES.get(difficulty, AI_MODES["standard"])

	# ── PARTNER BEHAVIOR ──────────────────────────────────────────────────────
	# When is_partner == true, partner_id == human_seat.
	# Every decision passes this test: "Does this increase our team's chance
	# of making the contract?" The most important single rule: never trump a
	# trick the human is already winning.
	if is_partner:
		if is_leading:
			# Give partner (human) a free discard when known void in a suit —
			# not a guaranteed win, a reasonable-confidence lead. If it's the
			# double or currently the highest remaining tile in that suit,
			# that's good enough to try; an opponent could still trump in,
			# and whether the human plays a counter into the resulting trick
			# isn't something we can know or need to control — we're just
			# creating the opening. No difficulty gate: cooperative judgment
			# is constant across difficulty, only knowledge access limits it.
			if public_knowledge != null:
				var human_void_leads = legal.filter(func(d):
					if d.is_trump(trump):
						return false
					var suit = d.get_suit(trump, trick.nello_doubles, -1)
					if not public_knowledge.void_suits(partner_id).has(suit):
						return false
					if d.is_double():
						return true
					var best_in_suit = public_knowledge.best_remaining_card_for_suit(suit)
					return best_in_suit != null and best_in_suit.debug_string() == d.debug_string())
				if human_void_leads.size() > 0:
					var chosen = _highest_in(human_void_leads, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
					reason_log.append("Giving you a free discard.")
					return chosen

			# ── Lead-safety priority stack (Katy + Claude, July 13, 2026) ──────
			# Steps below replace the old any-vs-all void-lead check (6b)
			# and the old #7/#9/#10 tiers with one coherent stack, each
			# returning immediately if it fires. See AI_Play_Behavior_Bug_Log.md,
			# BUG-007/BUG-012.
			#
			# CONTROL_TRUMP (and the low-trump heuristic below it) were moved
			# ahead of the SAFE tier the same night (Katy + Claude, July 13,
			# 2026, late session) — SAFE tier could otherwise preempt an
			# eligible trump-control lead with an off-trump double (e.g.
			# 5:5), which is exactly backwards: drawing trump when we
			# provably can takes priority over cashing an unrelated safe
			# double. See AI_Play_Behavior_Bug_Log.md, BUG-016.
			var opposing_team = [0, 1, 2, 3].filter(func(p): return p != player_id and p != partner_id)

			# Step 2 — trump control (#8). Lead high non-trump non-counter:
			# gives human a safe suit to follow without burning trump or
			# risking a vulnerable point card. Checked before the fallback
			# off-suit lead — a partner who holds enough trump to draw
			# opponents out should lead it before defaulting to a safe
			# off-suit tile. See AI_Play_Behavior_Bug_Log.md, BUG-003/003b.
			#
			# Eligibility (Katy + Claude, July 13, 2026) — replaces the old
			# trumps.size() >= 3/4 count threshold. Count was the wrong proxy
			# for the objective (drawing out opponent trump): two hands with
			# identical counts can have opposite real standing (top-ranked
			# trumps vs. low trumps while an opponent quietly holds the
			# actual highest). Eligible only when both hold:
			#   - Rank-safety: our best trump equals highest_remaining_trump()
			#     — this specific lead is provably unbeatable by anything
			#     remaining anywhere.
			#   - Objective-incomplete: the opposing team isn't already both
			#     confirmed void in trump — no point spending trump to draw
			#     out a threat that's already gone.
			# No loop or persistent state needed: decide_play() is
			# re-invoked fresh on every lead, so re-checking rank-safety
			# each time naturally stops a run the moment someone else holds
			# the true highest, without tracking anything across tricks.
			var trumps = legal.filter(func(d): return d.is_trump(trump))
			var holds_double_trump = trumps.any(func(d): return d.is_double())
			var trump_control = false
			if trumps.size() > 0:
				var best_trump_candidate = _highest_in(trumps, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				var top_remaining = public_knowledge.highest_remaining_trump() if public_knowledge != null else null
				var rank_safe = top_remaining != null and top_remaining.debug_string() == best_trump_candidate.debug_string()
				var objective_incomplete = public_knowledge == null or not opposing_team.all(func(opp): return public_knowledge.void_suits(opp).has(trump))
				trump_control = rank_safe and objective_incomplete
			if trump_control:
				var best: Domino
				var double_tile = Domino.new(trump, trump)
				var double_accounted_for = holds_double_trump or (public_knowledge != null and public_knowledge.has_been_played(double_tile))
				if double_accounted_for:
					best = _highest_in(trumps, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
					reason_log.append("I have trump control — drawing out the opponents.")
				else:
					# BUG-010: prefer a non-counter trump for the low lead if one exists —
					# it draws the double out just as well without risking 5 or 10 points
					# to a near-certain capture. Only fall back to a counter trump if
					# every trump candidate is a counter.
					var non_counter_trumps = trumps.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
					var draw_out_pool = non_counter_trumps if non_counter_trumps.size() > 0 else trumps
					best = _lowest_in(draw_out_pool, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
					reason_log.append("Leading low trump to draw out the double first.")
				return best

			# Step 3 — TEMPORARY HEURISTIC RESTORATION (BUG-016 follow-up,
			# Katy + Claude, July 13, 2026, late session) — old count
			# threshold, reinstated as its own branch rather than folded
			# back into CONTROL_TRUMP's now-correct rank-safety gate. The
			# double is always the top-ranked trump while in play, so
			# holding it already falls under the corrected CONTROL_TRUMP
			# above — no separate fix needed there. But strong trump
			# WITHOUT the double no longer triggers anything once
			# CONTROL_TRUMP requires provable rank-safety, which a non-double
			# holding essentially never has this early — the old
			# trumps.size() >= 4 no-double case had gone dead. This is NOT
			# the final trump-evaluation model (quantity/ceiling/continuity/
			# counter-cost) discussed this session — that's parked, designed
			# not built, pending calibration against real hands. This is a
			# stopgap to stop the regression, using the exact threshold that
			# was quietly serving this purpose before today's tightening.
			# `not trump_control` guard prevents overlap/duplicate firing
			# with CONTROL_TRUMP above. See AI_Play_Behavior_Bug_Log.md,
			# BUG-016.
			if not trump_control and trumps.size() >= 4 and not holds_double_trump:
				var objective_incomplete_heuristic = public_knowledge == null or not opposing_team.all(func(opp): return public_knowledge.void_suits(opp).has(trump))
				if objective_incomplete_heuristic:
					var non_counter_trumps_h = trumps.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
					var draw_out_pool_h = non_counter_trumps_h if non_counter_trumps_h.size() > 0 else trumps
					var best_h = _lowest_in(draw_out_pool_h, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
					reason_log.append("Leading low trump to draw out the double first.")
					return best_h

			# Step 4 — SAFE tier. Subsumes the old provably-highest check that
			# lived in OPEN_SAFE_SUIT (#7) and the safe half of the old
			# any-vs-all void-lead check (6b/FORCE_A_VOID's partner mirror).
			# A tile only qualifies if _is_lead_fully_safe() holds against BOTH
			# opponents independently (each may clear either safety path, they
			# don't need to clear the same one) — a strict proof, not a
			# confidence heuristic. These are free points; take them
			# confidently. Runs after trump control/the low-trump heuristic
			# — see the note above the priority-stack header for why.
			if public_knowledge != null:
				var safe_tier = legal.filter(func(d):
					if d.is_trump(trump):
						return false
					var suit = d.get_suit(trump, trick.nello_doubles, -1)
					return _is_lead_fully_safe(d, suit, opposing_team, trump, public_knowledge, trick.nello_doubles))
				if safe_tier.size() > 0:
					var chosen = _highest_in(safe_tier, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
					if chosen.is_double():
						reason_log.append("Leading my double — nothing left to beat it.")
					else:
						reason_log.append("Nothing can beat this.")
					return chosen

			# Step 5 — GAMBLE-tier void lead (moved above the off-suit lead,
			# July 13, 2026 — matches the original 6b's position relative to
			# OPEN_SAFE_SUIT/#7). Reached only if the SAFE tier and trump
			# control above found nothing. The opposing team has a known void
			# hit on the suit, but at least one void opponent's trump status
			# is live or unknown, so this isn't provably safe — a deliberate
			# gamble, sometimes worth taking, never guaranteed. Running this
			# before the off-suit lead means _lowest_cost_in() actually sees
			# non-counters when they exist in the void-informed pool, instead
			# of the off-suit tier claiming them first and leaving GAMBLE with
			# an all-counter pool by construction. Retires `we_are_strong`:
			# that self-assessment fork is deleted, not repaired — its two
			# inputs (trump control, safe off-suit availability) are now
			# checked upstream (trump control above; off-suit availability
			# no longer gates this tier at all, since it's just a fallback
			# below it now), making its old "lead highest, keep initiative"
			# branch unreachable dead code under this order. Its "lead
			# lowest, pass initiative" branch is preserved in spirit by
			# _lowest_cost_in().
			if public_knowledge != null:
				var void_leads = legal.filter(func(d):
					if d.is_trump(trump):
						return false
					var suit = d.get_suit(trump, trick.nello_doubles, -1)
					for opp in opposing_team:
						if public_knowledge.void_suits(opp).has(suit):
							return true
					return false)
				if void_leads.size() > 0:
					var chosen = _lowest_cost_in(void_leads, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
					reason_log.append("Trying to force a decision — hoping this doesn't get trumped.")
					return chosen

			# Step 6 — ordinary safe off-suit lead (#7, OPEN_SAFE_SUIT),
			# reasonable-confidence tier, only reached once trump control,
			# the SAFE tier, and the GAMBLE tier above all found nothing —
			# meaning nothing legal has ANY void information at all. This is
			# a generic "not a counter" catch-all, not a safety claim, which
			# is why it sits below an actually-informed gamble rather than
			# above it. A counter-double of a non-trump suit (5:5, standard
			# deck) is still led on reasonable confidence, not gated on
			# provable safety — Katy's ruling, July 11, 2026 (BUG-009/BUG-007).
			# It loses only to a trump-in; hiding it just delays an eventual
			# forced discard into a trick we don't control. Reason strings
			# here no longer claim provable safety — anything reaching this
			# tier already failed the SAFE tier's strict two-path test above,
			# so claiming "nothing can beat this" would be dishonest even for
			# a tile that's provably highest in its own suit: an unresolved
			# void opponent could still trump it.
			var off_safe = legal.filter(func(d):
				if d.is_trump(trump):
					return false
				if d.pip_sum() != 5 and d.pip_sum() != 10:
					return true
				return d.is_double())
			if off_safe.size() > 0:
				var best = _highest_in(off_safe, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				if best.pip_sum() == 5 or best.pip_sum() == 10:
					reason_log.append("Leading my double to cash it while I can.")
				else:
					reason_log.append("Opening this suit for you to build on.")
				return best

			# Step 7 — fully blind fallback (was #9/#10), reached only when no
			# void information exists on anything legal AND nothing off-suit
			# non-counter/double is available either. BUG-007's fix: the old
			# code led highest here with no regard for cost; this now uses
			# the same cost-minimization mechanism as the GAMBLE tier above,
			# just over the full legal pool instead of a void-informed subset.
			var chosen = _lowest_cost_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
			reason_log.append("Nothing safe to lead — keeping this as cheap as I can.")
			return chosen

		# ── FOLLOWING as Partner ──────────────────────────────────────────────
		var human_is_winning = _partner_is_winning(plays, partner_id, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)

		# THE cardinal rule: never steal a trick the human is winning.
		# Throw off lowest non-counter; only burn a counter if nothing else is available.
		if human_is_winning:
			var winning_domino = _current_winning_domino(plays, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
			var guaranteed_via_double = winning_domino.is_double()
			var guaranteed_win = _is_guaranteed_win(winning_domino, hand, trump, lead_suit, public_knowledge, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)

			if guaranteed_win:
				# Double is an unbeatable lead, OR the winning tile is provably
				# the highest remaining in its suit with no trump threat left.
				# Dump counters into the trick to secure the points — but only tiles
				# that actually stay a dump. If we're void in the lead suit and
				# holding trump, a trump counter doesn't yield to a non-trump winning
				# tile, it captures it outright — trump beats non-trump regardless of
				# rank. That's not a dump, it's an accidental, unplanned win with no
				# lead prepared for it.
				var counters_to_dump = legal.filter(func(d): return (d.pip_sum() == 5 or d.pip_sum() == 10) and not _beats(d, winning_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed))
				if counters_to_dump.size() > 0:
					var chosen = _highest_in(counters_to_dump, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
					reason_log.append("Good double — putting my points on your trick." if guaranteed_via_double else "Good play — putting my points on your trick.")
					return chosen
				var lowest = _lowest_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				if _beats(lowest, winning_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed):
					reason_log.append("Nice hand!" if hand.size() == 1 else "I've got this one.")
				else:
					reason_log.append("You've got this one — staying out of your way.")
				return lowest
			# Not a guaranteed win — protect counters as normal, UNLESS every
			# candidate beats the human's winning tile. When that's true,
			# "stay out of the way" is structurally impossible (BUG-008) —
			# escalate instead of taking the trick by accident with a fragile
			# low tile.
			var non_counters_follow = legal.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
			var candidates = non_counters_follow if non_counters_follow.size() > 0 else legal
			var forced_overtake = candidates.all(func(d): return _beats(d, winning_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed))

			if forced_overtake:
				var guaranteed = candidates.filter(func(d): return _is_guaranteed_win(d, hand, trump, lead_suit, public_knowledge, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed))
				var chosen: Domino
				if guaranteed.size() > 0:
					chosen = _lowest_in(guaranteed, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
					reason_log.append("Taking it with my double — nothing beats this.")
				elif _is_last_to_act(plays):
					chosen = _lowest_in(candidates, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
					reason_log.append("Had to take it — nobody left to answer.")
				else:
					chosen = _highest_in(candidates, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
					reason_log.append("Had to take it — playing my strongest to make it stick.")
				return chosen

			if non_counters_follow.size() > 0:
				var lowest = _pick_partner_discard(non_counters_follow, trump, lead_suit, public_knowledge, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				# The "lowest" legal tile can still end up winning if we're void
				# in the lead suit and every legal tile happens to be trump —
				# picking the smallest trump doesn't stop it from beating a
				# non-trump winner. Check before assuming this is a yield.
				if _beats(lowest, winning_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed):
					reason_log.append("Nice hand!" if hand.size() == 1 else "I've got this one.")
				else:
					reason_log.append("You've got this one — staying out of your way.")
				return lowest
			var lowest = _pick_partner_discard(legal, trump, lead_suit, public_knowledge, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
			if _beats(lowest, winning_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed):
				reason_log.append("Nice hand!" if hand.size() == 1 else "I've got this one.")
			else:
				reason_log.append("Putting my points on your trick.")
			return lowest

		# Human is not currently winning — try to win for the team.
		var current_winner_domino = _current_winning_domino(plays, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
		var can_win = legal.filter(func(d): return _beats(d, current_winner_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed))

		if can_win.size() > 0:
			# Partner always prefers non-trump winners to save trump — no
			# difficulty branching. A good partner plays its best game at
			# every difficulty; the old beginner-only reflexive-win shortcut
			# here had no real design intent behind it (see design doc) and
			# has been relocated to the opponent side — see Step 5.
			var non_trump_wins = can_win.filter(func(d): return not d.is_trump(trump))
			if non_trump_wins.size() > 0:
				var chosen = _lowest_in(non_trump_wins, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("You couldn't hold it — I've got this trick.")
				return chosen

			# Only trump can win. Partner always evaluates whether this
			# trick is worth spending trump on — no difficulty branching;
			# partner never skips this check.
			# Replaces the old turn-order-based check — see AI_Play_Behavior_Bug_Log.md,
			# BUG-005, for why that version was gated on the wrong fact.

			var acted_ids: Array = plays.map(func(p): return p["player"])
			acted_ids.append(player_id)
			var remaining_ids = [0, 1, 2, 3].filter(func(i): return not acted_ids.has(i))

			# Deterministic worst-case addition: the one specific counter (if any)
			# that could still land on THIS trick, capped at its own pip value —
			# not a probability, a bound on a single already-identified domino.
			var live_counter = null
			if is_partner or mode["vigilance"] == "full":
				live_counter = _live_counter_for_suit(lead_suit, hand, public_knowledge, trump, lead_suit, remaining_ids)
			var worst_case_addition = live_counter.pip_sum() if live_counter != null else _worst_case_counter_pip_estimate(lead_suit, hand, trump)
			var trick_value_worst_case = _estimate_trick_value(plays, trump) + worst_case_addition

			# Contract margin: can the side that needs bid_value still reach it, even
			# after conceding this trick at its worst case? Symmetric for both roles —
			# a 42-point hand is an exact zero-sum partition (25 counter points + 7
			# trick points = 42, always), so "can bidder still reach bid_value" and
			# "can defenders still hold bidder under bid_value" are the same reachable-
			# pool check evaluated from each side's own target.
			var margin_survivable = true  # default when bid_value == 0 (no margin data)
			if bid_value > 0:
				var our_team = player_id % 2
				var bidder_team = bidder_id % 2 if bidder_id >= 0 else our_team
				var our_target = bid_value if our_team == bidder_team else (43 - bid_value)

				var other_team = 1 - our_team
				var our_points = team_points[our_team] if team_points.size() > our_team else 0
				var their_points = team_points[other_team] if team_points.size() > other_team else 0
				var needed = our_target - our_points

				# Total undecided points remaining after conceding this one trick at
				# its worst case. Not a running multi-trick projection — just this
				# trick's single-event bound subtracted from the fixed 42-point total.
				var remaining_pool = 42 - our_points - their_points - trick_value_worst_case
				margin_survivable = remaining_pool >= needed

			if not margin_survivable:
				var chosen = _lowest_in(can_win, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("We need this one — can't afford to risk it.")
				return chosen

			# Margin is safe (or no data available) — lead economy decides whether
			# taking the trick is free or costly.
			var candidate = _lowest_in(can_win, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
			var hand_after_win: Array[Domino] = hand.duplicate()
			hand_after_win.erase(candidate)
			var safe_lead_exists = hand_after_win.any(func(d): return not d.is_trump(trump) and d.pip_sum() != 5 and d.pip_sum() != 10)

			if safe_lead_exists:
				reason_log.append("Trumping in — doesn't cost us anything and secures the trick.")
				return candidate

			var safe_discard = legal.filter(func(d):
				return d.pip_sum() != 5 and d.pip_sum() != 10 and not d.is_trump(trump))
			if safe_discard.size() > 0:
				var discard = _lowest_in(safe_discard, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("Holding back my trump — don't want to get stuck leading next.")
				return discard

			# No safe way to hold back — trump in anyway.
			reason_log.append("Trumping in to secure this trick for us.")
			return candidate

		# Can't win — discard to protect point cards.
		var non_counters_discard = legal.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
		if non_counters_discard.size() > 0:
			var discard = _pick_partner_discard(non_counters_discard, trump, lead_suit, public_knowledge, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
			var had_counter_to_avoid = non_counters_discard.size() < legal.size()
			var double_avoided = non_counters_discard.any(func(d): return d.is_double()) and not discard.is_double()
			if legal.size() == 1:
				reason_log.append("Had to follow suit.")
			elif hand.size() == 1:
				reason_log.append("No way to win this one.")
			elif had_counter_to_avoid and double_avoided:
				reason_log.append("Can't win this one — saving my count and my double for later.")
			elif had_counter_to_avoid:
				reason_log.append("Can't win this one — saving my count for later.")
			elif double_avoided:
				reason_log.append("Can't win this one — saving my double for later.")
			else:
				reason_log.append("Can't win this one — discarding low.")
			return discard
		var discard = _pick_partner_discard(legal, trump, lead_suit, public_knowledge, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
		if legal.size() == 1:
			reason_log.append("Had to follow suit.")
		elif hand.size() == 1:
			reason_log.append("No way to win this one.")
		else:
			reason_log.append("Nowhere to hide — had to let a count go.")
		return discard

	# ── OPPONENT BEHAVIOR ─────────────────────────────────────────────────────
	# Solid, honest 42 at every difficulty — no bare difficulty branching left
	# in this section. Two AI_MODES axes do the differentiating instead:
	# `vigilance` ("none"/"full") gates whether PublicKnowledge is consulted
	# at all; `opportunism` (0.0-1.0) is rolled fresh per eligible decision to
	# decide whether this opponent runs the real tactical evaluation or
	# commits reflexively. See Texas_42_Session_Summary_July_12_2026_
	# DifficultyModesDesign.md for the full design reasoning.
	# (The old "conservative opens" trump-avoidance rule for leading was removed
	# July 6, 2026 — no legitimate strategic basis; see Phase3_Objective_Audit.md
	# branch #19.)

	if is_leading:
		# Expert: target a suit that's genuinely safe against both opponents —
		# leading it forces the one who's still live to trump in (spending
		# trump) or discard (possibly a counter). Runs before the trump-control
		# check below, so a known-safe lead takes priority over a generic
		# trump-control lead when both are available.
		#
		# BUG-012 fix, July 13, 2026: this used to fire on ANY single opponent
		# being void in the suit, which isn't actually safe — a void opponent
		# with live trump can still trump in. Now uses the same two-path
		# safety test as partner's SAFE tier (_is_lead_fully_safe()): each
		# opponent must independently either be unable to beat this tile while
		# following suit (provably highest), or be void in both the suit and
		# trump. Deliberately narrower in scope than partner's fix — this only
		# corrects the false-safety defect in THIS check; it does not reorder
		# #20 relative to the opponent's other lead checks, and does not add
		# partner's SAFE/GAMBLE tier split on the opponent side. See
		# AI_Play_Behavior_Bug_Log.md, BUG-007/BUG-012.
		if mode["vigilance"] == "full" and public_knowledge != null:
			var opponents = [0, 1, 2, 3].filter(func(p): return p != player_id and p != partner_id)
			var void_leads = legal.filter(func(d):
				if d.is_trump(trump):
					return false
				var suit = d.get_suit(trump, trick.nello_doubles, -1)
				return _is_lead_fully_safe(d, suit, opponents, trump, public_knowledge, trick.nello_doubles))
			if void_leads.size() > 0:
				var best = _highest_in(void_leads, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("Leading a suit you can't beat.")
				return best

		# Lead highest trump if we hold enough to control the suit.
		var trumps = legal.filter(func(d): return d.is_trump(trump))
		if trumps.size() >= 3:
			var best = _highest_in(trumps, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
			reason_log.append("Drawing out trumps.")
			return best

		# Lead a strong counter if we're confident it will win.
		var counters = legal.filter(func(d): return d.pip_sum() == 5 or d.pip_sum() == 10)
		for c in counters:
			if c.get_rank(trump, trick.nello_doubles, lead_suit, trick.doubles_trump_reversed, trick.own_suit_reversed) >= 4:
				reason_log.append("Leading my strong count to lock in the points.")
				return c

		# Lead highest available domino.
		var best = _highest_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
		if hand.size() == 1:
			reason_log.append("Last domino.")
		elif best.is_double():
			reason_log.append("Leading my double.")
		else:
			reason_log.append("Leading my best domino.")
		return best

	# ── FOLLOWING as Opponent ──────────────────────────────────────────────────
	var partner_winning = _partner_is_winning(plays, partner_id, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)

	# Partner is winning — save strength, don't over-contribute.
	if partner_winning:
		var winning_domino = _current_winning_domino(plays, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
		var forced_overtake = legal.all(func(d): return _beats(d, winning_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed))
		if forced_overtake:
			var guaranteed = legal.filter(func(d): return _is_guaranteed_win(d, hand, trump, lead_suit, public_knowledge, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed))
			var chosen: Domino
			if guaranteed.size() > 0:
				chosen = _lowest_in(guaranteed, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("Taking it with my double — nothing beats this.")
			elif _is_last_to_act(plays):
				chosen = _lowest_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("Had to take it — nobody left to answer.")
			else:
				chosen = _highest_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("Had to take it — playing my strongest to make it stick.")
			return chosen
		var lowest = _lowest_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
		if _beats(lowest, winning_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed):
			reason_log.append("I've got this one.")
			return lowest

		# BUG-004: last to act means the trick's outcome is already fixed — no
		# one remains who could beat our partner's winning domino. A stranded
		# counter costs nothing to drop here rather than carrying it into a
		# future trick this side might not control. Same opportunism roll as
		# the can-win contest decision below — one shared "does this seat check
		# for exploitable table state" trait, not two.
		if _is_last_to_act(plays) and _should_evaluate_tactically(mode):
			var counters_to_dump = legal.filter(func(d): return (d.pip_sum() == 5 or d.pip_sum() == 10) and not _beats(d, winning_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed))
			if counters_to_dump.size() > 0:
				var chosen = _highest_in(counters_to_dump, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("Nothing left to answer — may as well drop my count.")
				return chosen

		reason_log.append("Nice hand!" if hand.size() == 1 else "My partner has this one — laying low.")
		return lowest

	# Try to win the trick.
	var current_winner_domino = _current_winning_domino(plays, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
	var can_win = legal.filter(func(d): return _beats(d, current_winner_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed))

	if can_win.size() > 0:
		if not _should_evaluate_tactically(mode):
			# Reflexive: take the trick with whatever's lowest, no
			# accounting for resource cost or follow-up plan. This is the
			# old beginner-only "secure without second-guessing" shape,
			# relocated from partner (see Step 3a) — it belongs here, not
			# there. Also retires the old value_gate (#25) threshold
			# entirely; that branch had the direction backwards (passing
			# on a cheap trick is the disciplined move, not the distracted
			# one) — see design doc.
			var chosen = _lowest_in(can_win, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
			reason_log.append("Taking this one.")
			return chosen

		# Evaluates: win with a counter if possible — pick up the points.
		var counter_wins = can_win.filter(func(d): return d.pip_sum() == 5 or d.pip_sum() == 10)
		if counter_wins.size() > 0:
			var chosen = _lowest_in(counter_wins, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
			reason_log.append("Winning the trick and picking up the points.")
			return chosen
		var chosen = _lowest_in(can_win, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
		reason_log.append("Winning the trick.")
		return chosen

	# Can't win — discard lowest non-counter to protect point cards.
	# NOTE: this whole block is only reached with can_win.size() == 0 — the
	# can_win.size() > 0 branch above always returns. A _beats(discard,
	# current_winner_domino, ...) check and a can_win.size() > 0 split both
	# used to live here (from when a beginner-only value_gate threshold could
	# decline a winnable trick and fall through to this block); both were
	# provably dead code once value_gate was retired (July 12, 2026) and are
	# removed here rather than left as unreachable branches. See
	# AI_Explanation_Bug_Log.md, Issue 9.
	var non_counters = legal.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
	if non_counters.size() > 0:
		var discard = _lowest_in(non_counters, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
		var had_counter_to_avoid = non_counters.size() < legal.size()
		var double_avoided = non_counters.any(func(d): return d.is_double()) and not discard.is_double()
		if legal.size() == 1:
			reason_log.append("Had to follow suit.")
		elif hand.size() == 1:
			reason_log.append("No way to win this one.")
		elif had_counter_to_avoid and double_avoided:
			reason_log.append("Can't win this one — protecting my count and my double.")
		elif had_counter_to_avoid:
			reason_log.append("Can't win this one — protecting my count.")
		elif double_avoided:
			reason_log.append("Can't win this one — protecting my double.")
		else:
			reason_log.append("Can't win this one — discarding low.")
		return discard
	var discard = _lowest_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
	if legal.size() == 1:
		reason_log.append("Had to follow suit.")
	elif hand.size() == 1:
		reason_log.append("No way to win this one.")
	else:
		reason_log.append("No way to win, and nothing safe to throw.")
	return discard

# ─── HELPERS ─────────────────────────────────────────────────────────────────

# The five counting dominoes in standard 42.
const COUNTING_DOMINOES := [[5,0], [4,1], [3,2], [6,4], [5,5]]

# Whether `candidate`, if played, is provably unbeatable by anything still
# in play — a double under no-trump (or a trump double), or the last live
# tile in its suit with trump provably exhausted per PublicKnowledge.
# Generalizes the guaranteed-win check that was inline in the human_is_winning
# block (branch #11) so BUG-008's forced-overtake escalation can reuse the
# identical test instead of duplicating it. See AI_Play_Behavior_Bug_Log.md,
# "guaranteed-win detection generalization" design notes.
static func _is_guaranteed_win(candidate: Domino, hand: Array[Domino], trump: int,
		lead_suit: int, public_knowledge: PublicKnowledge,
		nello_doubles: String = "high", doubles_trump_reversed: bool = false,
		own_suit_reversed: bool = false) -> bool:
	if candidate.is_double():
		var c_suit = candidate.get_suit(trump, nello_doubles, lead_suit)
		if trump < 0 or c_suit == trump:
			return true
	if public_knowledge == null:
		return false
	# NOTE: `candidate` may already be recorded as played in `public_knowledge`
	# (e.g. it's the tile currently winning the trick, already in
	# current_trick.plays) — best_remaining_card_for_suit()/
	# highest_remaining_trump() exclude played tiles, so they exclude
	# `candidate` itself from their own search and return the best of
	# whatever's left instead. Two things follow: (1) a null result means
	# nothing else of that suit/trump remains anywhere — safe, not unsafe;
	# (2) a non-null result is the TRUE highest-ranked remaining tile, so it
	# must be compared by RANK against candidate, not by identity — it can
	# easily be lower-ranked than candidate (e.g. candidate is the second-
	# highest trump and the top one was already played), in which case it's
	# harmless regardless of whose hand it's in. Only a result that both
	# outranks candidate AND isn't sitting in this player's own hand (a tile
	# they hold can't also be played by someone else this trick) is a real
	# threat.
	var candidate_rank = candidate.get_rank(trump, nello_doubles, lead_suit, doubles_trump_reversed, own_suit_reversed)
	if candidate.is_trump(trump):
		var highest_trump = public_knowledge.highest_remaining_trump()
		if highest_trump == null:
			return true
		var highest_rank = highest_trump.get_rank(trump, nello_doubles, lead_suit, doubles_trump_reversed, own_suit_reversed)
		if highest_rank <= candidate_rank:
			return true
		return hand.any(func(h): return h.debug_string() == highest_trump.debug_string())
	var suit = candidate.get_suit(trump, nello_doubles, lead_suit)
	var best_in_suit = public_knowledge.best_remaining_card_for_suit(suit)
	if best_in_suit != null:
		var best_rank = best_in_suit.get_rank(trump, nello_doubles, lead_suit, doubles_trump_reversed, own_suit_reversed)
		if best_rank > candidate_rank and not hand.any(func(h): return h.debug_string() == best_in_suit.debug_string()):
			return false
	var own_trump_count = hand.filter(func(d): return d.is_trump(trump)).size()
	return trump < 0 or public_knowledge.count_remaining_trump() - own_trump_count == 0

# ── Lead-safety two-path test (BUG-007/BUG-012, July 13, 2026) ─────────────
# A lead of `tile` in `suit` cannot be beaten by `opponent` if, and only if,
# one of two independent paths holds:
#   Path A — must follow: opponent isn't void in `suit`, and `tile` is
#     provably the highest remaining tile in that suit (a double always
#     qualifies within its own suit — nothing beats it there).
#   Path B — void in both: opponent is void in both `suit` and `trump`, so
#     nothing they hold can follow suit OR trump in.
# A void-in-suit-only opponent (trump live or unknown) clears neither path —
# that's the GAMBLE tier, handled by callers, not by this function.
static func _is_lead_safe_against_opponent(tile: Domino, suit: int, opponent: int,
		trump: int, public_knowledge: PublicKnowledge, nello_doubles: String = "high") -> bool:
	if public_knowledge == null:
		return false
	var opponent_void_in_suit = public_knowledge.void_suits(opponent).has(suit)
	if not opponent_void_in_suit:
		if tile.is_double():
			return true
		var best = public_knowledge.best_remaining_card_for_suit(suit)
		return best != null and best.debug_string() == tile.debug_string()
	else:
		# void_suits() records trump voids through the same general
		# mechanism as any other suit (a trump-led trick that a player
		# can't follow appends `trump` itself) — no special-casing needed.
		return public_knowledge.void_suits(opponent).has(trump)

# True only if `tile` is safe against every member of `opposing_team`
# independently — each opponent may clear either path, they don't need to
# clear the same one.
static func _is_lead_fully_safe(tile: Domino, suit: int, opposing_team: Array,
		trump: int, public_knowledge: PublicKnowledge, nello_doubles: String = "high") -> bool:
	for opp in opposing_team:
		if not _is_lead_safe_against_opponent(tile, suit, opp, trump, public_knowledge, nello_doubles):
			return false
	return true

# Is there still a live threat in `target_suit` that a remaining-to-act
# player could produce this trick? Returns the specific domino if so,
# null if the threat has been provably eliminated. Deterministic only —
# never estimates who holds what, only eliminates a specific known domino
# as a threat when it's provably out of reach (already played, in our own
# hand, or every remaining actor is known-void in the suit it would need
# to follow).
static func _live_counter_for_suit(
	target_suit: int, hand: Array[Domino], public_knowledge: PublicKnowledge,
	trump: int, lead_suit: int, remaining_ids: Array
) -> Domino:
	if public_knowledge == null or remaining_ids.is_empty():
		return null
	var all_void = true
	for pid in remaining_ids:
		if not public_knowledge.is_void_in(pid, target_suit):
			all_void = false
			break
	if all_void:
		return null
	var best: Domino = null
	for pair in COUNTING_DOMINOES:
		var d = Domino.new(pair[0], pair[1])
		if d.get_suit(trump, "high", lead_suit) != target_suit:
			continue
		if public_knowledge.has_been_played(d):
			continue
		var in_hand = false
		for h in hand:
			if h.left == d.left and h.right == d.right:
				in_hand = true
				break
		if in_hand:
			continue
		if best == null or d.pip_sum() > best.pip_sum():
			best = d
	return best

# Worst-case counter bound used when vigilance can't confirm a specific
# live counter via PublicKnowledge — assumes the standard counter value
# (10) could still land on this trick's suit rather than treating the
# threat as resolved. Deliberately conservative, not a probability.
static func _worst_case_counter_pip_estimate(_lead_suit: int, _hand: Array[Domino], _trump: int) -> int:
	return 10

static func _highest_in(dominos: Array, trump: int, lead_suit: int,
		nello_doubles: String = "high", doubles_trump_reversed: bool = false, own_suit_reversed: bool = false) -> Domino:
	var best: Domino = dominos[0]
	for d in dominos:
		if d.get_rank(trump, nello_doubles, lead_suit, doubles_trump_reversed, own_suit_reversed) > best.get_rank(trump, nello_doubles, lead_suit, doubles_trump_reversed, own_suit_reversed):
			best = d
	return best

# Returns the domino from `dominos` whose pip_sum is closest to 7.
# Used exclusively for Sevens hands. Ties broken by first encountered — arbitrary
# tie-breaking is correct per the rules (all same-distance dominos are equivalent).
static func _closest_to_seven(dominos: Array) -> Domino:
	var best: Domino = dominos[0]
	var best_dist: int = abs(best.pip_sum() - 7)
	for d in dominos:
		var dist = abs(d.pip_sum() - 7)
		if dist < best_dist:
			best = d
			best_dist = dist
	return best

static func _lowest_in(dominos: Array, trump: int, lead_suit: int,
		nello_doubles: String = "high", doubles_trump_reversed: bool = false, own_suit_reversed: bool = false) -> Domino:
	var lowest: Domino = dominos[0]
	for d in dominos:
		if d.get_rank(trump, nello_doubles, lead_suit, doubles_trump_reversed, own_suit_reversed) < lowest.get_rank(trump, nello_doubles, lead_suit, doubles_trump_reversed, own_suit_reversed):
			lowest = d
	return lowest

# Cost-minimization tie-break for the GAMBLE and fully-blind lead tiers
# (BUG-007/BUG-012, July 13, 2026): ranks by point cost at risk rather than
# domino rank — prefer a non-counter if any exists in the pool, only falling
# back to the full pool (and _lowest_in()'s rank ordering) if every
# candidate is a counter. Same non_counter_trumps pattern BUG-010 already
# established for the trump-control low lead.
static func _lowest_cost_in(pool: Array, trump: int, lead_suit: int,
		nello_doubles: String = "high", doubles_trump_reversed: bool = false, own_suit_reversed: bool = false) -> Domino:
	var non_counters = pool.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
	var draw_pool = non_counters if non_counters.size() > 0 else pool
	return _lowest_in(draw_pool, trump, lead_suit, nello_doubles, doubles_trump_reversed, own_suit_reversed)

# Picks the discard/yield candidate from `pool`, breaking the "all doubles tie
# at rank 13" artifact in _lowest_in() when every candidate is a double. In
# that case only, prefers to part with the double whose own suit has the
# least life left in it (fewest un-played tiles of that suit still
# unaccounted for), keeping the double most likely to still catch a trick
# later. Any pool containing even one non-double defers entirely to
# _lowest_in() — a non-double's rank (0-6) is always below a double's fixed
# 13, so that comparison is already correct and untouched.
static func _pick_partner_discard(pool: Array[Domino], trump: int, lead_suit: int,
		public_knowledge: PublicKnowledge, nello_doubles: String = "high",
		doubles_trump_reversed: bool = false, own_suit_reversed: bool = false) -> Domino:
	var all_doubles = pool.size() > 0 and pool.all(func(d): return d.is_double())
	if not all_doubles or public_knowledge == null or pool.size() <= 1:
		return _lowest_in(pool, trump, lead_suit, nello_doubles, doubles_trump_reversed, own_suit_reversed)

	var worst: Domino = pool[0]
	var worst_life: int = public_knowledge.remaining_count(worst.left)
	for d in pool:
		var life = public_knowledge.remaining_count(d.left)
		if life < 0:
			# Sentinel — no meaningful answer (Sevens has no suit concept).
			# Shouldn't be reachable here since Sevens bypasses decide_play()
			# entirely, but fall back defensively rather than trust a -1.
			return _lowest_in(pool, trump, lead_suit, nello_doubles, doubles_trump_reversed, own_suit_reversed)
		if life < worst_life:
			worst = d
			worst_life = life
	return worst

# Whether an opponent bothers running the real tactical evaluation (margin/
# counter/lead-economy) before committing to a trick, versus committing
# reflexively with no accounting. Rolled fresh per eligible decision point —
# not per hand, not per game — so a single opponent can play sharp on one
# trick and reflexive on the next. Named as a question rather than tied to
# "opportunism" specifically, so a future second evaluation context doesn't
# require renaming call sites — see design doc's Deferred Items.
static func _should_evaluate_tactically(mode: Dictionary) -> bool:
	return randf() < mode.get("opportunism", 1.0)

static func _partner_is_winning(plays: Array, partner_id: int, trump: int, lead_suit: int,
		nello_doubles: String = "high", doubles_trump_reversed: bool = false, own_suit_reversed: bool = false) -> bool:
	if plays.size() == 0:
		return false
	return _find_current_winner_id(plays, trump, lead_suit, nello_doubles, doubles_trump_reversed, own_suit_reversed) == partner_id

static func _current_winning_domino(plays: Array, trump: int, lead_suit: int,
		nello_doubles: String = "high", doubles_trump_reversed: bool = false, own_suit_reversed: bool = false) -> Domino:
	var best: Domino = plays[0]["domino"]
	for play in plays:
		var d: Domino = play["domino"]
		if _beats(d, best, trump, lead_suit, nello_doubles, doubles_trump_reversed, own_suit_reversed):
			best = d
	return best

# Returns the player_id of whoever is currently winning the trick.
static func _find_current_winner_id(plays: Array, trump: int, lead_suit: int,
		nello_doubles: String = "high", doubles_trump_reversed: bool = false, own_suit_reversed: bool = false) -> int:
	if plays.size() == 0:
		return -1
	var best_play = plays[0]
	var best_d: Domino = best_play["domino"]
	for play in plays:
		var d: Domino = play["domino"]
		if _beats(d, best_d, trump, lead_suit, nello_doubles, doubles_trump_reversed, own_suit_reversed):
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

# Decision geometry — visible turn arithmetic, not knowledge, not
# difficulty-gated. True for every seat regardless of AI_MODES.
# `plays` is the current trick's plays so far, BEFORE the acting
# player's own play is added (same contract as PublicFrame.current_trick).
static func _is_last_to_act(plays: Array) -> bool:
	return plays.size() == 3

# Estimate the point value already on the table in a trick.
# Returns 1 (base trick point) plus any counter pip values played so far.
# Used by beginner opponents to decide whether the trick is worth contesting.
static func _estimate_trick_value(plays: Array, trump: int) -> int:
	var pts = 1  # base 1 point for the trick itself
	for play in plays:
		var d: Domino = play["domino"]
		if d.pip_sum() == 5 or d.pip_sum() == 10:
			pts += d.pip_sum()
	return pts

static func _beats(challenger: Domino, current: Domino, trump: int, lead_suit: int,
		nello_doubles: String = "high", doubles_trump_reversed: bool = false, own_suit_reversed: bool = false) -> bool:
	var c_suit = challenger.get_suit(trump, nello_doubles, lead_suit)
	var b_suit = current.get_suit(trump, nello_doubles, lead_suit)
	var c_rank = challenger.get_rank(trump, nello_doubles, lead_suit, doubles_trump_reversed, own_suit_reversed)
	var b_rank = current.get_rank(trump, nello_doubles, lead_suit, doubles_trump_reversed, own_suit_reversed)

	var c_is_trump = (c_suit == trump)
	var b_is_trump = (b_suit == trump)

	if c_is_trump and not b_is_trump:
		return true
	if not c_is_trump and b_is_trump:
		return false
	if c_suit != b_suit:
		return false  # Different non-trump suits — can't beat
	return c_rank > b_rank
