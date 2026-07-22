class_name LaydownCheck
extends RefCounted

# ═══════════════════════════════════════════════════════════════════════════
# "Can't Be Caught" / Lay-Down verification (first pass — Points/Marks/
# Plunge/Splash only; Nello and Sevens explicitly out of scope, see
# Alpha_Roadmap.md).
#
# PRECONDITION, enforced by the CALLER, not this function: it must be the
# claimant's turn to LEAD the current trick. The proof below is only valid
# under that precondition — if every tile the claimant holds is provably
# safe-to-lead, they win trick 1 (therefore lead trick 2), win that
# (therefore lead trick 3), and so on until the hand is empty. This
# function has no notion of whose turn it is; that's real game state the
# caller already has and must check before calling this.
# ═══════════════════════════════════════════════════════════════════════════

const Deck = preload("res://deck.gd")

# Whether `hand` is a provable lay-down: every remaining domino in it is
# guaranteed to win whichever trick it's eventually played into, regardless
# of what any opponent holds or what gets led.
static func is_provable_laydown(hand: Array[Domino], trump: int,
		public_knowledge: PublicKnowledge, nello_doubles: String = "high",
		doubles_trump_reversed: bool = false, own_suit_reversed: bool = false) -> bool:
	if public_knowledge == null or hand.is_empty():
		return false
	for candidate in hand:
		if not _is_safe_excluding_own_hand(candidate, hand, trump, public_knowledge,
				nello_doubles, doubles_trump_reversed, own_suit_reversed):
			return false
	return true

# Whether `candidate` (a tile in `hand`) is safe once every OTHER tile in
# `hand` is ALSO treated as accounted-for, alongside everything
# public_knowledge already knows was played.
#
# Accounting rule: a domino is a real threat only if it is neither (a)
# already recorded as played, nor (b) currently sitting in `hand` itself —
# the claimant's own tiles can never simultaneously be held by an
# opponent, so holding a domino removes it from the threat pool the same
# way playing it would (Katy's 6:6/6:5 example: holding 6:6 makes 6:5
# provably safe even though 6:6 hasn't officially been played).
#
# This is a STATIC check against a fixed excluded pool (played + own
# hand), computed once per candidate — no trick-by-trick simulation, no
# play-order dependency. That's not a simplifying assumption; it's exactly
# correct, because every tile in `hand` is excluded from the threat pool
# simultaneously and unconditionally, regardless of what order the hand
# eventually gets played in.
#
# Deliberately conservative for this first pass: does NOT use void_suits()
# to infer that an unaccounted-for tile must be sitting with partner
# (rather than an opponent) even when both opponents are already proven
# void in its suit. That's a real, valid strengthening — untraced tiles
# genuinely are safe if only partner could hold them — but it's scoped out
# here to keep this pass to the simpler, more obviously-correct rule.
# Named candidate for a v2 pass, not forgotten.
static func _is_safe_excluding_own_hand(candidate: Domino, hand: Array[Domino], trump: int,
		public_knowledge: PublicKnowledge, nello_doubles: String, doubles_trump_reversed: bool,
		own_suit_reversed: bool) -> bool:
	var candidate_suit = candidate.get_suit(trump, nello_doubles)
	var candidate_rank = candidate.get_rank(trump, nello_doubles, -1, doubles_trump_reversed, own_suit_reversed)

	var deck = Deck.new()
	deck.build_deck()
	for d in deck.dominoes:
		if d.debug_string() == candidate.debug_string():
			continue  # never compare the candidate against itself
		if public_knowledge.has_been_played(d):
			continue  # already accounted for
		if _hand_contains(hand, d):
			continue  # in the claimant's own hand — can't also threaten it
		if d.get_suit(trump, nello_doubles) != candidate_suit:
			continue  # different suit, no rank comparison applies
		if d.get_rank(trump, nello_doubles, -1, doubles_trump_reversed, own_suit_reversed) > candidate_rank:
			return false  # a real, unaccounted-for threat exists
	return true

static func _hand_contains(hand: Array[Domino], d: Domino) -> bool:
	for h in hand:
		if h.debug_string() == d.debug_string():
			return true
	return false
