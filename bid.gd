class_name Bid
extends RefCounted

# Bid types
enum Type { POINTS, MARKS, NELLO, PLUNGE, SPLASH, FOLLOW_ME, SEVENS, LOW_NO, PASS }

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
		Type.LOW_NO:
			# Low-No is a dealer-only escape valve, not a competitive bid that
			# gets overcalled in the normal sense — treat it like a 42-point
			# bid for ordering purposes (it can only ever be the LAST bid anyway).
			return 0.42
	return 0.0

# Validate whether a bid attempt is legal given the current highest bid and settings.
#
# `context` is an optional dictionary used by bids that need info beyond the
# bid itself to validate:
#   "hand_doubles_count": int   -> how many doubles are in the bidder's hand
#                                   (required for PLUNGE / SPLASH)
#   "is_dealer": bool           -> true if bidder is the shaker/dealer
#                                   (required for LOW_NO)
#   "all_others_passed": bool   -> true if every other player already passed
#                                   (required for LOW_NO)
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

	if new_bid.type == Type.LOW_NO:
		if not settings.allow_low_no:
			return false
		if not context.get("is_dealer", false):
			return false
		if not context.get("all_others_passed", false):
			return false
		# Low-No isn't "raised" over anything — it's only legal as the final
		# resort after three passes, so there's no current_high to compare to.
		return current_high == null

	if new_bid.type == Type.POINTS:
		if new_bid.value < settings.minimum_bid or new_bid.value > 42:
			return false

	# Opening-bid mark cap: e.g. you normally can't open at 5 marks unless
	# you're going for Plunge (which already passed its own check above) or
	# the table allows jump bids.
	if new_bid.type == Type.MARKS and current_high == null:
		if new_bid.value > settings.max_open_bid_marks and not settings.allow_jump_bids:
			return false

	# General raise cap: without allow_jump_bids, a MARKS bid can only step
	# up by one mark at a time over the previous MARKS bid (Plunge/Splash are
	# exempt since they have their own fixed-value rules above).
	if new_bid.type == Type.MARKS and current_high != null and current_high.type == Type.MARKS:
		if not settings.allow_jump_bids and new_bid.value > current_high.value + 1:
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
		Type.LOW_NO: return "Low-No"
	return "Unknown"
