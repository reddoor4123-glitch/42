class_name Domino
extends RefCounted

# Sentinel trump value meaning "doubles are trump" (their own suit),
# as opposed to a real numeric suit (0-6). Safe since real pips cap at 6.
const DOUBLES_TRUMP := 7

var left: int
var right: int

func _init(a: int, b: int):
	if a <= b:
		left = a
		right = b
	else:
		left = b
		right = a

func is_double() -> bool:
	return left == right

func pip_sum() -> int:
	return left + right

# Returns the suit of this domino in context.
# Trump dominoes always return trump as their suit — this now also covers
# the DOUBLES_TRUMP sentinel automatically via is_trump(), no special-casing
# needed here: a double under doubles-trump reports suit = DOUBLES_TRUMP,
# and a non-double under doubles-trump falls through to normal suit logic
# below since is_trump(DOUBLES_TRUMP) is false for it.
func get_suit(trump: int, nello_doubles: String = "high", lead_suit: int = -1) -> int:
	if trump >= 0 and is_trump(trump):
		return trump
	if is_double():
		if nello_doubles == "own_suit":
			return -2  # Special "doubles" suit (Nello doubles-as-own-suit mode)
		return left  # left == right for doubles
	# If one end matches the lead suit, that end defines the suit
	if lead_suit >= 0:
		if left == lead_suit:
			return left
		if right == lead_suit:
			return right
	return max(left, right)

# Returns the rank of this domino within its suit.
# Trump: double-of-trump is highest (13), then by the non-trump pip.
# DOUBLES_TRUMP: ranked by pip value directly (6-6 high -> 0-0 low),
#   or reversed (0-0 high -> 6-6 low) if doubles_trump_reversed is set.
# Non-trump: the pip that is NOT the suit pip is the rank.
# Nello "low": doubles rank lowest (-1).
# Nello "own_suit": doubles rank by pip value (6-6 high -> 0-0 low),
#   or reversed (0-0 high -> 6-6 low) if own_suit_reversed is set —
#   same shape as doubles_trump_reversed above, deliberately.
func get_rank(trump: int, nello_doubles: String = "high", lead_suit: int = -1, doubles_trump_reversed: bool = false, own_suit_reversed: bool = false) -> int:
	if trump >= 0 and is_trump(trump):
		if trump == DOUBLES_TRUMP:
			return (6 - left) if doubles_trump_reversed else left
		if is_double():
			return 13
		return left if right == trump else right
	if is_double():
		if nello_doubles == "low":
			return -1
		if nello_doubles == "own_suit":
			return (6 - left) if own_suit_reversed else left
		return 13
	var suit = get_suit(trump, nello_doubles, lead_suit)
	return left if right == suit else right

# A domino is trump if it contains the trump pip — OR, under the
# DOUBLES_TRUMP sentinel, if it's a double at all (doubles form their
# own trump suit instead of a numeric one).
func is_trump(trump: int) -> bool:
	if trump == DOUBLES_TRUMP:
		return is_double()
	return left == trump or right == trump

func debug_string() -> String:
	return str(left) + ":" + str(right)
