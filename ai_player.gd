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
# "That partner plays like Uncle Ed." — that's the target.
# ═══════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════
#  DECISION GEOMETRY — VISIBLY DERIVABLE STRUCTURAL FACTS
# ═══════════════════════════════════════════════════════════════════
# Some decision-relevant facts are neither hidden information nor
# behavioral weighting — they are directly observable properties of
# the current decision moment, true for every seat regardless of
# difficulty. Examples: is this player last to act in the trick?
# How many legal moves exist? Is the partner currently winning?
#
# These are pure helper predicates over visible plays/legal state.
# They are NOT part of PublicKnowledge (no hidden info, no inference,
# no accumulation over hand_history) and they are NOT difficulty
# gates (every seat computes the same answer to the same question).
#
# Existing helpers already in this family (see HELPERS section below):
#   _current_winning_domino, _find_current_winner_id,
#   _partner_is_winning, _estimate_trick_value, _find_player_play,
#   _is_last_to_act
#
# IMPORTANT — do not prematurely unify these into a single
# "trick is decided" predicate. A trick can become locked for at
# least three structurally different reasons — a double led (rule
# of tiles), last-to-act (turn arithmetic, this file), or a known-
# safe high trump whose only beater has already fallen (hidden
# information — depends on Phase 4 knowledge/inference). They are
# not branches of one concept; they are three different subsystems
# that sometimes produce the same outcome. Do not write
# _trick_is_decided() until Phase 4 can actually supply the third
# case — see AI_Play_Behavior_Bug_Log.md, Pattern A / BUG-004.
# ═══════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════
#  DIFFICULTY DIFFERENCES — THE KNOWLEDGE/EVALUATION LITMUS TEST
# ═══════════════════════════════════════════════════════════════════
# The goal is for different difficulties to arrive at different decisions
# for understandable reasons — not because they run different games.
#
# Difficulty is not a library of special-case plays. All difficulties share
# one decision engine; they differ only in what a player knows and how they
# weigh what they know. Before adding an `if difficulty == "..."` branch,
# classify what's actually going on:
#
#   KNOWLEDGE  — What information is this player allowed to use? Genuine
#                information asymmetry (inference, derived facts like
#                voids, anything not equally available to every seat)
#                belongs behind the project's knowledge/inference layer,
#                not a difficulty string. That layer is PublicKnowledge —
#                see its header for the vocabulary-layer contract every
#                Knowledge-classified branch here ultimately defers to.
#
#   EVALUATION — Everyone can use the same information; difficulties differ
#                only in whether they act on it, or how they weigh it. This
#                belongs in the shared decision logic, parameterized by an
#                AI_MODES axis (risk_bias, cooperation_bias, opportunism,
#                ...) — not a bare difficulty check.
#
#   NEITHER    — No information- or evaluation-based model fits. Only then
#                is a direct difficulty branch acceptable, and it should be
#                treated as a last resort, not a default.
#
# If a proposed change starts with `if difficulty == ...`, stop first and
# classify it as a Knowledge difference, an Evaluation difference, or a
# genuine special case. The classification should drive the implementation
# — not the other way around.
# ═══════════════════════════════════════════════════════════════════

# ─── DIFFICULTY PROFILES ─────────────────────────────────────────────────────
# Single source of truth for all AI behavioral parameters.
# Add new modes here; decide_bid() and decide_play() read from this dict.
const AI_MODES := {
	"beginner": {
		"risk_bias":        -0.25,
		"max_overbid":      2,
		"opportunism":      "low",
		"cooperation_bias": "high",
	},
	"standard": {
		"risk_bias":        0.0,
		"max_overbid":      4,
		"opportunism":      "medium",
		"cooperation_bias": "medium",
	},
	"expert": {
		"risk_bias":        0.25,
		"max_overbid":      6,
		"opportunism":      "high",
		"cooperation_bias": "medium",
	},
}

# ─── HAND EVALUATION ─────────────────────────────────────────────────────────

# Score a hand assuming a given trump suit.
# Returns a dictionary with estimated points, tricks, and confidence.
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

	# ── CAPTURE MODEL ─────────────────────────────────────────────────────────
	# Primary axis: expected tricks → expected points captured from the table.
	# This is the ONLY value signal used for bidding strength.
	var expected_capture := estimated_tricks * 6.0

	# ── REALIZATION SIGNAL (diagnostic only) ──────────────────────────────────
	# Measures how well known counter positions align with expected trick wins.
	# Does NOT increase expected value — counters in hand do not add EV,
	# they only indicate realization confidence for future use (Phase 2 risk).
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

	var estimated_points := expected_capture
	# Do NOT add realization_bias to estimated_points.

	return {
		"trump":            trump,
		"trump_count":      trump_count,
		"has_double_trump": has_double_trump,
		"estimated_tricks": estimated_tricks,
		"expected_capture": expected_capture,   # primary bidding signal
		"counter_points":   counter_points,     # diagnostic only
		"realization_bias": realization_bias,   # diagnostic only
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
		control_score += 1.0

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
		# Any non-points bid on the table (MARKS, NELLO, SEVENS, PLUNGE, SPLASH,
		# LOW_NO) already has a mark-equivalent of at least 0.42 — a points bid
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
	if eval.get("trump_count", 0) >= 5:    control_score_log += 1.0
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
#  TRICK OBJECTIVES — NAMING WHAT THE BRANCHES ALREADY DECIDE
# ═══════════════════════════════════════════════════════════════════
# This is not a new subsystem. No TrickObjective enum, no class, no
# stored state. It's a naming convention for something decide_play()
# already does implicitly: before comparing any dominoes, the branch
# structure has effectively already chosen a mission for the trick —
# decided before most domino comparison happens, not all of it
# (comparisons like "cheapest winner" or "highest available" still
# occur, but downstream of the mission, not in place of it). Naming
# these objectives makes the Phase 3 difficulty-branch collapse (see
# below) tractable — it gives each bare `difficulty ==` check a
# concrete thing to be evaluated against, instead of being judged in
# isolation.
#
# Two tiers exist. Don't conflate them:
#
#   CONTRACT-LEVEL intent — decided once, for the whole hand, at the
#   very top of decide_play(). Already fully explicit as the Sevens /
#   Nello / Marks early-return branches. Nothing to change here; this
#   *is* the pattern working correctly at a coarser grain.
#
#   TRICK-LEVEL intent — decided fresh every trick, inside standard
#   play. Currently implicit in branch order. This is the new naming.
#
# Objectives are read off decision geometry, not personality —
# partner_winning == true is geometry; "protect partner" is the
# objective that geometry implies. Evaluation (AI_MODES) then decides
# how well that objective gets executed. Geometry → objective →
# evaluation is the intended chain; personality never skips ahead to
# pick a different objective for the same geometry.
#
# The trick-level objectives that already exist in the code today:
#
#   PROTECT_PARTNER_WIN   — partner (human) is currently winning.
#                            Line ~570. Stay out of the way; dump
#                            counters only if the win is guaranteed
#                            (double led).
#   SECURE_FOR_PARTNER     — partner is not winning, we can win.
#                            Line ~594. Win it, preferring non-trump,
#                            with a trust-based hold-back for standard
#                            difficulty when someone else might cover.
#   CASH_COUNTERS          — (opponent side) can win, prefer winning
#                            with a counter over a plain domino.
#                            Line ~741.
#   CONTEST_IF_WORTHWHILE  — (opponent side, beginner only) can win,
#                            but only bother if the trick already
#                            holds enough value. Line ~727.
#   ESCAPE                 — can't win this trick. Discard to protect
#                            counters, cheapest safe tile first.
#                            Lines ~637, ~750.
#   CONTROL_TRUMP          — leading, hold enough trump to draw
#                            opponents out. Line ~733.
#   FORCE_A_VOID           — leading, PublicKnowledge-gated, target a
#                            suit a known-void opponent can't follow.
#                            Two instances: opponent-leading (expert
#                            only, Line ~937) and partner-leading (all
#                            difficulties, Line ~694 — see the
#                            difficulty-asymmetry note below).
#   GIFT_A_VOID            — leading, partner only, PublicKnowledge-
#                            gated, target a suit the HUMAN is known
#                            void in — the mirror image of
#                            FORCE_A_VOID: opening an opportunity for
#                            the human instead of forcing a cost onto
#                            an opponent. All difficulties. Line ~670.
#
# Note: these aren't all the same grain. PROTECT_PARTNER_WIN,
# SECURE_FOR_PARTNER, and ESCAPE are true objectives — what you're
# trying to accomplish. CONTROL_TRUMP, FORCE_A_VOID, and GIFT_A_VOID
# are closer to strategies/tactics in service of an objective ("gain
# control," "extend the lead," "create an opening") that isn't
# separately named here. Left as-is deliberately — naming that parent
# objective isn't needed for the Phase 3 collapse, and forcing
# everything to one grain would be taxonomy for its own sake.
#
# For each objective, the Phase 3 question is not "does difficulty
# change this play" but "does difficulty change which objective gets
# selected, or just how well the selected objective is executed":
#
#   - PROTECT_PARTNER_WIN, SECURE_FOR_PARTNER, ESCAPE, CONTROL_TRUMP
#     are difficulty-invariant in *selection* — every seat reaches
#     them from the same geometry (partner_winning, can_win, etc,
#     already Decision Geometry, not knowledge). Difficulty may only
#     change execution quality within the objective (e.g. the
#     standard trust-hold inside SECURE_FOR_PARTNER). That's
#     Evaluation, and it already lives where it should.
#   - CONTEST_IF_WORTHWHILE is a beginner-only *threshold* on top of
#     CASH_COUNTERS, not a separate mission — the objective is the
#     same ("win it if it's worth it"), difficulty only moves the bar
#     for "worth it." Also Evaluation.
#   - FORCE_A_VOID's opponent-leading instance is Knowledge-gated by
#     construction (requires PublicKnowledge) and is correctly
#     expert-only for that reason, not because lower difficulties have
#     a different mission when leading — they simply can't see the void.
#   - FORCE_A_VOID's partner-leading instance and GIFT_A_VOID are
#     deliberately NOT difficulty-gated (added July 6, 2026, gate
#     removed the same day) — cooperative judgment is constant across
#     difficulty per this file's own AI Design Philosophy header
#     ("partner cooperation intent is difficulty-invariant"); only
#     knowledge access limits it, not which difficulty was picked. This
#     is an intentional asymmetry, not an oversight: beginner/standard
#     partners now get void-awareness that beginner/standard opponents
#     still don't, because FORCE_A_VOID's opponent-leading instance
#     stays expert-gated above. Two instances of the same-shaped
#     predicate, two different difficulty rules — by design, not drift.
#
# Net effect for the Phase 3 collapse: of the six originally-flagged bare
# `difficulty ==` branches, five are Evaluation-tuning *within* a shared,
# difficulty-invariant objective, and belong as AI_MODES parameters
# (e.g. a "contest_threshold" or "trust_others" knob) rather than
# inline branches. The sixth, FEEL_OUT_THE_HAND (beginner-only opening-
# trick trump avoidance), was originally logged as "the one true
# exception" — a genuine mission difference, not just an execution
# difference. On closer inspection it wasn't: there was no legitimate
# strategic basis for unconditionally suppressing trump control on
# trick one regardless of hand strength, the same violation class as
# the also-removed beginner "discard highest first" branch (ESCAPE,
# following-as-partner). Both were removed entirely rather than
# reclassified — "goals change, not IQ" ruled them out, it didn't
# relocate them. No genuine Neither-category exception remains standing
# among the six; if one shows up later, it should clear the same bar
# these two failed before being treated as settled.
#
# This naming is documentation only. reason_log strings, branch
# order, and helper functions are unchanged by this section — it's a
# map for the collapse work, not a rewrite in itself.
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
			var best = _highest_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
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
	@warning_ignore("unused_variable")
	var opportunism: String      = mode["opportunism"]       # Phase 3
	@warning_ignore("unused_variable")
	var cooperation_bias: String = mode["cooperation_bias"]  # Phase 3

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

			# Expert: target a suit the opposing team is known void in — same
			# concept as the opponent-leading version (FORCE_A_VOID), mirrored
			# for partner leads. The opposing team can't follow suit here, so
			# only we or the human can win this trick naturally (an opponent
			# could still trump in — an acceptable risk, same as the
			# opponent-leading version accepts).
			#
			# High vs. low is a self-assessment gamble, not knowledge of the
			# human's hand: if we still have a strong lead available for next
			# trick (trump control, or a safe off-suit tile), take this one and
			# keep the initiative. If we don't, pass the lead low — either the
			# human wins it with something better, or we win it anyway by
			# accident, both fine outcomes.
			if public_knowledge != null:
				var opposing_team = [0, 1, 2, 3].filter(func(p): return p != player_id and p != partner_id)
				var void_leads = legal.filter(func(d):
					if d.is_trump(trump):
						return false
					var suit = d.get_suit(trump, trick.nello_doubles, -1)
					for opp in opposing_team:
						if public_knowledge.void_suits(opp).has(suit):
							return true
					return false)
				if void_leads.size() > 0:
					# Self-assessment: do we have a strong lead available next trick?
					var trumps_check = legal.filter(func(d): return d.is_trump(trump))
					var holds_double_check = trumps_check.any(func(d): return d.is_double())
					var have_trump_control = (trumps_check.size() >= 3 and holds_double_check) or trumps_check.size() >= 4
					var have_safe_off_suit = legal.any(func(d):
						return not d.is_trump(trump) and d.pip_sum() != 5 and d.pip_sum() != 10)
					var we_are_strong = have_trump_control or have_safe_off_suit

					var chosen: Domino
					if we_are_strong:
						chosen = _highest_in(void_leads, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
						reason_log.append("Leading a suit our opponents can't follow.")
					else:
						chosen = _lowest_in(void_leads, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
						reason_log.append("Opponents are void - hoping you can take the lead.")
					return chosen

			# Lead high non-trump non-counter: gives human a safe suit to follow
			# without burning trump or risking a vulnerable point card.
			# Trump control checked FIRST — a partner who holds enough trump to draw
			# opponents out should lead it before defaulting to a safe off-suit tile.
			# Threshold: 3+ trumps if the holding includes the double trump (the
			# double itself supplies the control), otherwise 4+ is required. See
			# AI_Play_Behavior_Bug_Log.md, BUG-003/003b.
			var trumps = legal.filter(func(d): return d.is_trump(trump))
			var holds_double_trump = trumps.any(func(d): return d.is_double())
			var trump_control = (trumps.size() >= 3 and holds_double_trump) or trumps.size() >= 4
			if trump_control:
				var best: Domino
				if difficulty == "beginner" or holds_double_trump:
					best = _highest_in(trumps, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
					reason_log.append("I have trump control — drawing out the opponents.")
				else:
					best = _lowest_in(trumps, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
					reason_log.append("Leading low trump to draw out the double first.")
				return best

			# Safe off-suit lead — now the fallback tier, only reached when trump
			# control doesn't apply.
			var off_safe = legal.filter(func(d):
				return not d.is_trump(trump) and d.pip_sum() != 5 and d.pip_sum() != 10)
			if off_safe.size() > 0:
				var best = _highest_in(off_safe, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("Opening a safe suit for you to follow.")
				return best

			# Counter protection: prefer non-counter leads even if that's all that's left.
			var non_counters_lead = legal.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
			if non_counters_lead.size() > 0:
				var best = _highest_in(non_counters_lead, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("Leading strong to set up a good trick for us.")
				return best

			var best = _highest_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
			reason_log.append("Nothing safe to lead — playing a count.")
			return best

		# ── FOLLOWING as Partner ──────────────────────────────────────────────
		var human_is_winning = _partner_is_winning(plays, partner_id, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)

		# THE cardinal rule: never steal a trick the human is winning.
		# Throw off lowest non-counter; only burn a counter if nothing else is available.
		if human_is_winning:
			var winning_domino = _current_winning_domino(plays, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
			var guaranteed_win = winning_domino.is_double()
			var guaranteed_via_double = guaranteed_win

			if not guaranteed_win and public_knowledge != null and not winning_domino.is_trump(trump):
				var winning_suit = winning_domino.get_suit(trump, trick.nello_doubles, lead_suit)
				var best_in_suit = public_knowledge.best_remaining_card_for_suit(winning_suit)
				if best_in_suit != null and best_in_suit.debug_string() == winning_domino.debug_string():
					var own_trump_count = hand.filter(func(d): return d.is_trump(trump)).size()
					var trump_exhausted = trump < 0 or public_knowledge.count_remaining_trump() - own_trump_count == 0
					if trump_exhausted:
						guaranteed_win = true
						guaranteed_via_double = false

			if guaranteed_win:
				# Double is an unbeatable lead, OR the winning tile is provably
				# the highest remaining in its suit with no trump threat left.
				# Dump counters into the trick to secure the points — but only tiles
				# that actually stay a dump. If we're void in the lead suit and
				# holding trump, a trump counter doesn't yield to a non-trump winning
				# tile, it captures it outright — trump beats non-trump regardless of
				# rank. That's not a dump, it's an accidental, unplanned win with no
				# lead prepared for it.
				var counters_to_dump = legal.filter(func(d):
					return (d.pip_sum() == 5 or d.pip_sum() == 10)
						and not _beats(d, winning_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed))
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
			# Not a guaranteed win — protect counters as normal.
			var non_counters_follow = legal.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
			if non_counters_follow.size() > 0:
				var lowest = _lowest_in(non_counters_follow, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				# The "lowest" legal tile can still end up winning if we're void
				# in the lead suit and every legal tile happens to be trump —
				# picking the smallest trump doesn't stop it from beating a
				# non-trump winner. Check before assuming this is a yield.
				if _beats(lowest, winning_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed):
					reason_log.append("Nice hand!" if hand.size() == 1 else "I've got this one.")
				else:
					reason_log.append("You've got this one — staying out of your way.")
				return lowest
			var lowest = _lowest_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
			if _beats(lowest, winning_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed):
				reason_log.append("Nice hand!" if hand.size() == 1 else "I've got this one.")
			else:
				reason_log.append("Putting my points on your trick.")
			return lowest

		# Human is not currently winning — try to win for the team.
		var current_winner_domino = _current_winning_domino(plays, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
		var can_win = legal.filter(func(d): return _beats(d, current_winner_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed))

		if can_win.size() > 0:
			if difficulty == "beginner":
				# Beginner Partner: always secure the trick without second-guessing card economy.
				var chosen = _lowest_in(can_win, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("Stepping in to win this for us.")
				return chosen

			# Standard and Expert: prefer non-trump winners to save trump.
			var non_trump_wins = can_win.filter(func(d): return not d.is_trump(trump))
			if non_trump_wins.size() > 0:
				var chosen = _lowest_in(non_trump_wins, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("You couldn't hold it — I've got this trick.")
				return chosen

			# Only trump can win.
			if difficulty == "expert":
				# Expert Partner: no trust rule — play optimally for the contract.
				var chosen = _lowest_in(can_win, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("Trumping in — the contract needs this trick.")
				return chosen

			# Standard: evaluate whether this trick is worth spending trump on.
			# Replaces the old turn-order-based check — see AI_Play_Behavior_Bug_Log.md,
			# BUG-005, for why that version was gated on the wrong fact.

			var acted_ids: Array = plays.map(func(p): return p["player"])
			acted_ids.append(player_id)
			var remaining_ids = [0, 1, 2, 3].filter(func(i): return not acted_ids.has(i))

			# Deterministic worst-case addition: the one specific counter (if any)
			# that could still land on THIS trick, capped at its own pip value —
			# not a probability, a bound on a single already-identified domino.
			var live_counter = _live_counter_for_suit(lead_suit, hand, public_knowledge, trump, lead_suit, remaining_ids)
			var worst_case_addition = live_counter.pip_sum() if live_counter != null else 0
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
			var discard = _lowest_in(non_counters_discard, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
			reason_log.append("Can't win this one — saving my count for later.")
			return discard
		var discard = _lowest_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
		reason_log.append("Nowhere to hide — had to let a count go.")
		return discard

	# ── OPPONENT BEHAVIOR ─────────────────────────────────────────────────────
	# Standard: solid casual play — not bloodthirsty, not passive.
	# Beginner: only contests tricks with counters already in them when following.
	# (The old "conservative opens" trump-avoidance rule for leading was removed
	# July 6, 2026 — no legitimate strategic basis; see Phase3_Objective_Audit.md
	# branch #19.)
	# Expert: compete harder (handled in bidding); TODO Phase 3 opportunism.

	if is_leading:
		# Expert: target a suit an opponent is known void in — leading it forces
		# them to trump in (spending trump) or discard (possibly a counter).
		# Runs before the trump-control check below, so a known void takes
		# priority over a generic trump-control lead when both are available.
		if difficulty == "expert" and public_knowledge != null:
			var opponents = [0, 1, 2, 3].filter(func(p): return p != player_id and p != partner_id)
			var void_leads = legal.filter(func(d):
				if d.is_trump(trump):
					return false
				var suit = d.get_suit(trump, trick.nello_doubles, -1)
				for opp in opponents:
					if public_knowledge.void_suits(opp).has(suit):
						return true
				return false)
			if void_leads.size() > 0:
				var best = _highest_in(void_leads, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("Leading a suit I know you're out of.")
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
		var lowest = _lowest_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
		if _beats(lowest, winning_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed):
			reason_log.append("I've got this one.")
		else:
			reason_log.append("Nice hand!" if hand.size() == 1 else "My partner has this one — laying low.")
		return lowest

	# Try to win the trick.
	var current_winner_domino = _current_winning_domino(plays, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
	var can_win = legal.filter(func(d): return _beats(d, current_winner_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed))

	if difficulty == "beginner":
		# Beginner: only contest the trick if counters are already on the table.
		# Low-value tricks aren't worth risking good cards over.
		if can_win.size() > 0:
			var trick_pts = _estimate_trick_value(plays, trump)
			if trick_pts >= 5:
				var chosen = _lowest_in(can_win, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("These points are worth contesting.")
				return chosen
			# Trick not worth contesting — fall through to discard
	else:
		# Standard / Expert: try to win the trick.
		if can_win.size() > 0:
			# Win with a counter if possible — pick up the points.
			var counter_wins = can_win.filter(func(d): return d.pip_sum() == 5 or d.pip_sum() == 10)
			if counter_wins.size() > 0:
				var chosen = _lowest_in(counter_wins, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
				reason_log.append("Winning the trick and picking up the points.")
				return chosen
			var chosen = _lowest_in(can_win, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
			reason_log.append("Winning the trick.")
			return chosen

	# Can't win — discard lowest non-counter to protect point cards.
	var non_counters = legal.filter(func(d): return d.pip_sum() != 5 and d.pip_sum() != 10)
	if non_counters.size() > 0:
		var discard = _lowest_in(non_counters, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
		if _beats(discard, current_winner_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed):
			reason_log.append("Taking this one.")
		elif legal.size() == 1:
			reason_log.append("Had to follow suit.")
		elif hand.size() == 1:
			reason_log.append("No way to win this one.")
		else:
			if can_win.size() > 0:
				reason_log.append("Not worth chasing — protecting my count instead.")
			else:
				reason_log.append("Can't win this one — protecting my count.")
		return discard
	var discard = _lowest_in(legal, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed)
	if _beats(discard, current_winner_domino, trump, lead_suit, trick.nello_doubles, trick.doubles_trump_reversed, trick.own_suit_reversed):
		reason_log.append("Taking this one.")
	elif legal.size() == 1:
		reason_log.append("Had to follow suit.")
	elif hand.size() == 1:
		reason_log.append("No way to win this one.")
	else:
		reason_log.append("No way to win, and nothing safe to throw.")
	return discard

# ─── HELPERS ─────────────────────────────────────────────────────────────────

# The five counting dominoes in standard 42.
const COUNTING_DOMINOES := [[5,0], [4,1], [3,2], [6,4], [5,5]]

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
