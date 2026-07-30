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
const BidScript = preload("res://bid.gd")

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

# ═══════════════════════════════════════════════════════════════════════════
#  NELLO LAY-DOWN
# ═══════════════════════════════════════════════════════════════════════════
#
# The take-tricks proof above asks "does every tile I hold WIN?". Nello asks the
# opposite, and it is NOT that question with the comparison flipped — that was
# the first design and it is wrong. "Every tile I hold is the lowest remaining in
# its suit" is neither sufficient nor necessary:
#
#   * not sufficient — lead a suit both opponents are void in and your lowest
#     tile takes the trick; Nello is no-trump, so nothing can over-ruff you;
#   * not necessary — holding the 1st and 3rd lowest of a suit is perfectly safe,
#     because you duck under whichever tile is led and keep the other in reserve.
#     A static rank comparison rejects that hand.
#
# PRECONDITION, enforced by the CALLER: the claimant must NOT be on lead. That
# inverts the take-tricks precondition above, and it is what makes the question
# answerable at all — a Nello bidder who is still alive never leads after trick 1
# (leading trick N means having won trick N-1, i.e. already being set), so the
# search never has to model the claimant choosing which suit to lead.
#
# Answers the real question: does there EXIST a line of play for the claimant
# that loses every remaining trick against EVERY line the two opponents can play?
# Claimant maximises, both opponents minimise together. That matches how a
# lay-down actually resolves — resolve_hand_via_laydown() awards the hand
# immediately rather than playing it out, so the claim is "a safe line exists",
# not "this particular heuristic survives".
#
# Reads the opponents' ACTUAL hands rather than PublicKnowledge, deliberately.
# The Nello partner sits out holding seven dominoes that never reach the table,
# and nothing can identify which unseen tiles are theirs — treating every unseen
# tile as a threat would reject hands that are genuinely safe. The partner is
# simply absent from `hands`, so those seven correctly influence nothing.
#
# All four doubles modes (high / low / own_suit / own_suit reversed) work with no
# special-casing here: every suit and rank question is delegated to Trick and
# Domino with the mode threaded through, so this search and live trick resolution
# cannot disagree about what beats what.
# ═══════════════════════════════════════════════════════════════════════════

# Search cap. A blown budget returns "not provable" rather than a wrong answer or
# a stalled UI — the claim is refused, never wrongly granted. Sized far above
# what a real position needs: the search starts at trick 2 at the earliest, so at
# most six tricks remain, and the move ordering below reaches a decision almost
# immediately in practice.
const NELLO_NODE_BUDGET := 300000

# `hands`        : seat (int) -> Array of Domino, for the three ACTIVE seats only.
#                  The sitting-out Nello partner must not appear.
# `plays_so_far` : the current trick's plays, [{player, domino}], in play order.
# `leader_seat`  : who led the current trick.
static func is_provable_nello_laydown(claimant_seat: int, hands: Dictionary,
		plays_so_far: Array, leader_seat: int, nello_doubles: String = "high",
		own_suit_reversed: bool = false) -> bool:
	if not hands.has(claimant_seat):
		return false
	var work := {}
	for seat in hands:
		work[seat] = (hands[seat] as Array).duplicate()
	# Tiles already on the table are no longer held. Callers pass live hands, and
	# whether a played tile has been removed from its owner's hand yet depends on
	# where in the turn cycle we are, so normalise here rather than trusting it.
	for p in plays_so_far:
		var seat: int = p["player"]
		if work.has(seat):
			var i: int = (work[seat] as Array).find(p["domino"])
			if i >= 0:
				(work[seat] as Array).remove_at(i)
	if (work[claimant_seat] as Array).is_empty() and plays_so_far.size() == 0:
		return true   # nothing left to be caught with
	var budget := [NELLO_NODE_BUDGET]
	return _nello_node(claimant_seat, work, plays_so_far.duplicate(),
		_active_order(work.keys(), leader_seat), plays_so_far.size(),
		nello_doubles, own_suit_reversed, budget)

# The active seats in play order starting from `leader`. Turn order is -1 mod 4
# (game_table.gd's _play_next_in_trick), and the sitting-out partner is simply
# not in `seats`, so walking all four and keeping those present drops them.
static func _active_order(seats: Array, leader: int) -> Array:
	var order: Array = []
	var s := leader
	for _i in range(4):
		if seats.has(s):
			order.append(s)
		s = (s + 3) % 4
	return order

static func _trick_from(plays: Array, nello_doubles: String, own_suit_reversed: bool) -> Trick:
	var t := Trick.new()
	# trump -1: Nello is no-trump — game.gd calls apply_bid_result(-1) for it.
	t.setup(-1, BidScript.Type.NELLO, nello_doubles, false, own_suit_reversed, false)
	for p in plays:
		t.add_play(p["player"], p["domino"])
	return t

# True if the claimant can still avoid taking every remaining trick.
static func _nello_node(claimant_seat: int, hands: Dictionary, plays: Array,
		order: Array, turn_idx: int, nello_doubles: String,
		own_suit_reversed: bool, budget: Array) -> bool:
	budget[0] -= 1
	if budget[0] <= 0:
		return false    # out of budget: refuse to certify, never guess

	if turn_idx >= order.size():
		# Trick complete — resolve it with the live rules, not a local copy.
		var winner: int = _trick_from(plays, nello_doubles, own_suit_reversed).determine_winner()
		if winner == claimant_seat:
			return false          # caught: this line fails
		var any_left := false
		for seat in hands:
			if not (hands[seat] as Array).is_empty():
				any_left = true
				break
		if not any_left:
			return true           # survived every trick
		return _nello_node(claimant_seat, hands, [],
			_active_order(hands.keys(), winner), 0,
			nello_doubles, own_suit_reversed, budget)

	var seat: int = order[turn_idx]
	var hand: Array = hands[seat]
	var is_claimant := seat == claimant_seat
	var legal := _nello_legal_moves(hand, plays, nello_doubles, own_suit_reversed)
	_order_moves(legal, plays, is_claimant, nello_doubles, own_suit_reversed)

	for d in legal:
		var idx: int = hand.find(d)
		hand.remove_at(idx)
		plays.append({"player": seat, "domino": d})
		var safe := _nello_node(claimant_seat, hands, plays, order, turn_idx + 1,
			nello_doubles, own_suit_reversed, budget)
		plays.pop_back()
		hand.insert(idx, d)
		if is_claimant and safe:
			return true      # claimant needs only one surviving line
		if not is_claimant and not safe:
			return false     # opponents need only one line that catches
	# Claimant exhausted every move without surviving; or opponents exhausted
	# every move without catching.
	return not is_claimant

static func _nello_legal_moves(hand: Array, plays: Array, nello_doubles: String,
		own_suit_reversed: bool) -> Array:
	var typed: Array[Domino] = []
	for d in hand:
		typed.append(d)
	var legal: Array = []
	for d in _trick_from(plays, nello_doubles, own_suit_reversed).get_legal_moves(typed):
		legal.append(d)
	return legal

# Move ordering only — it changes how fast an answer is reached, never what the
# answer is. Uses the two rules from the design pass: the claimant plays the
# highest tile that still loses (so try high first and let losing lines surface
# early), and the opponents duck low to strand the trick on the claimant (so try
# low first). Because correctness comes from the exhaustive search rather than
# from these, a bad ordering costs time and nothing else.
static func _order_moves(moves: Array, plays: Array, is_claimant: bool,
		nello_doubles: String, own_suit_reversed: bool) -> void:
	var lead_suit := -1
	if plays.size() > 0:
		lead_suit = _trick_from(plays, nello_doubles, own_suit_reversed).lead_suit
	var mode := nello_doubles
	var rev := own_suit_reversed
	if is_claimant:
		moves.sort_custom(func(a: Domino, b: Domino):
			return a.get_rank(-1, mode, lead_suit, false, rev) > b.get_rank(-1, mode, lead_suit, false, rev))
	else:
		moves.sort_custom(func(a: Domino, b: Domino):
			return a.get_rank(-1, mode, lead_suit, false, rev) < b.get_rank(-1, mode, lead_suit, false, rev))
