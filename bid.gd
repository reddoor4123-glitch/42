class_name Bid
extends RefCounted

# Bid types
enum Type { POINTS, MARKS, NELLO, PLUNGE, SPLASH, FOLLOW_ME, SEVENS, PASS }

var type: Type
var value: int      # Points (30-42) or marks (1-7) depending on type
var player_id: int

func _init(bid_type: Type, bid_value: int, bidder_id: int):
	type = bid_type
	value = bid_value
	player_id = bidder_id

# Returns true if this bid is higher than the previous bid
static func is_higher(new_bid: Bid, prev_bid: Bid) -> bool:
	if prev_bid == null or prev_bid.type == Type.PASS:
		return true
	var new_marks = to_mark_equivalent(new_bid)
	var prev_marks = to_mark_equivalent(prev_bid)
	return new_marks > prev_marks

# Convert any bid to a comparable mark-equivalent float for ordering.
# Points bids are fractional marks so a 42-point bid < 1 mark.
static func to_mark_equivalent(bid: Bid) -> float:
	match bid.type:
		Type.PASS:
			return 0.0
		Type.POINTS:
			# 30 pts = 0.30, 42 pts = 0.42 (all less than 1 mark)
			return bid.value / 100.0
		Type.MARKS:
			return float(bid.value)
		Type.NELLO, Type.FOLLOW_ME, Type.SEVENS:
			return float(bid.value)  # value holds the mark amount (always 1+)
		Type.PLUNGE, Type.SPLASH:
			return float(bid.value)
	return 0.0

# Validate whether a bid attempt is legal given the current highest bid and settings.
#
# `context` is an optional dictionary used by bids that need info beyond the
# bid itself to validate:
#   "hand_doubles_count": int   -> how many doubles are in the bidder's hand
#                                   (required for PLUNGE / SPLASH)
#   "is_dealer": bool           -> true if bidder is the shaker/dealer
#                                   (required for NELLO/SEVENS only-on-forced-bid)
#   "all_others_passed": bool   -> true if every other player already passed
#                                   (required for NELLO/SEVENS only-on-forced-bid)
static func is_valid(new_bid: Bid, current_high: Bid, settings: GameSettings, context: Dictionary = {}) -> bool:
	if new_bid.type == Type.PASS:
		return true

	if new_bid.type == Type.NELLO and not settings.allow_nello:
		return false
	if new_bid.type == Type.NELLO and settings.nello_only_on_forced_bid:
		if not context.get("is_dealer", false) or not context.get("all_others_passed", false):
			return false
	if new_bid.type == Type.FOLLOW_ME and not settings.allow_follow_me:
		return false
	if new_bid.type == Type.SEVENS and not settings.allow_sevens:
		return false
	if new_bid.type == Type.SEVENS and settings.sevens_only_on_forced_bid:
		if not context.get("is_dealer", false) or not context.get("all_others_passed", false):
			return false

	if new_bid.type == Type.PLUNGE:
		if not settings.allow_plunge:
			return false
		if new_bid.value < settings.plunge_minimum_bid_marks:
			return false
		if context.has("hand_doubles_count") and context["hand_doubles_count"] < settings.plunge_minimum_doubles:
			return false

	if new_bid.type == Type.SPLASH:
		if not settings.allow_splash:
			return false
		if new_bid.value < settings.splash_bid_marks:
			return false
		if context.has("hand_doubles_count") and context["hand_doubles_count"] < settings.splash_minimum_doubles:
			return false

	if new_bid.type == Type.POINTS:
		if new_bid.value < settings.minimum_bid or new_bid.value > 42:
			return false

	# Marks ceiling. Without allow_jump_bids a marks bid may either OPEN the
	# auction at up to max_open_bid_marks, or step exactly one mark above what is
	# already standing — never more. With jump bids on there is no ceiling at all
	# and a player may go straight to seven.
	#
	# Plunge and Splash are exempt and never reach here: this is gated on
	# Type.MARKS, and each carries its own fixed minimum checked above. That is
	# what lets a 4-mark Plunge land on top of a 1-mark auction.
	if new_bid.type == Type.MARKS and not settings.allow_jump_bids:
		var standing := 0.0 if current_high == null else to_mark_equivalent(current_high)
		if standing < 1.0:
			# Nothing bid yet, or only a points bid — points are worth a fraction
			# of a mark, so this is still the auction's FIRST marks bid and the
			# opening cap applies. This used to test `current_high == null`, which
			# let a jump straight to seven marks through unchallenged as long as
			# somebody had bid points first.
			if new_bid.value > settings.max_open_bid_marks:
				return false
		elif new_bid.value > int(standing) + 1:
			return false

	return is_higher(new_bid, current_high)

func debug_string() -> String:
	match type:
		Type.PASS: return "Pass"
		Type.POINTS: return str(value) + " points"
		Type.MARKS: return str(value) + " mark(s)"
		Type.NELLO: return "Nello (" + str(value) + " mark)"
		Type.PLUNGE: return "Plunge (" + str(value) + " marks)"
		Type.SPLASH: return "Splash (" + str(value) + " marks)"
		Type.FOLLOW_ME: return "Follow Me"
		Type.SEVENS: return "Sevens"
	return "Unknown"
