class_name GameSettings
extends RefCounted

# ─────────────────────────────────────────────
#  BIDDING RULES
# ─────────────────────────────────────────────
var bid_direction: String = "clockwise"     # "clockwise" or "counterclockwise" (family plays CCW)
var allow_forced_bid: bool = true           # If all pass, shaker must bid minimum
var forced_bid_minimum: int = 30            # Common values: 30, 42
var reshake_if_all_pass: bool = false        # Alternative to forced bid: just reshake, no penalty
var minimum_bid: int = 30                   # Floor for all bids
var max_open_bid_marks: int = 2             # Cap on opening/non-special bids (marks); Plunge overrides this
var allow_jump_bids: bool = false           # Allow bidding more than 1 above current outside Plunge

var allow_plunge: bool = true
var plunge_minimum_doubles: int = 4
var plunge_minimum_bid_marks: int = 4       # Plunge must open at/jump to this many marks

var allow_splash: bool = false
var splash_minimum_doubles: int = 3
var splash_bid_marks: int = 2

var allow_low_no: bool = false              # Dealer-only "points" version of Nello; only legal if all 3 others passed

# ─────────────────────────────────────────────
#  NELLO / NILLO
# ─────────────────────────────────────────────
var allow_nello: bool = true

var nello_all_four_play: bool = false       # true = all 4 play; false = bidder + 2 opponents only
var nello_partner_sits_out: bool = true

var allow_nello_exchange: bool = true
var nello_exchange_bidder_gives: String = "any"   # "any", "high", "off_suit"
var nello_exchange_partner_gives: String = "low"  # "any", "low", "bidder_calls"

var nello_only_on_forced_bid: bool = false
var nello_minimum_bid: int = 42

var nello_doubles_mode: String = "high"
# "high"     — doubles are highest of their suit (standard)
# "low"      — doubles are lowest of their suit
# "own_suit" — doubles are a suit unto themselves
var nello_doubles_reversed: bool = false    # Within own_suit mode, double-blank is highest

var nello_bid_value: int = 42
var nello_count_as_marks: bool = true
var nello_failure_penalty: String = "bid"   # "bid" = opponents score bid; "double" = 2x; "set" = fixed
var nello_failure_fixed_points: int = 42

# ─────────────────────────────────────────────
#  FOLLOW ME / NO TRUMP
# ─────────────────────────────────────────────
var allow_follow_me: bool = true
var follow_me_doubles_mode: String = "high" # "high", "low", "own_suit"
var follow_me_allow_as_points_bid: bool = false  # If false, Follow Me requires a marks-level bid (42+)

# ─────────────────────────────────────────────
#  SEVENS
# ─────────────────────────────────────────────
var allow_sevens: bool = true
var sevens_require_minimum_bid: bool = false
var sevens_minimum_bid: int = 42
var sevens_require_seven_in_hand: bool = false   # Must hold a domino summing to 7 to call it
var sevens_tie_rule: String = "earliest"         # "earliest" = first domino to reach min distance wins;
												  # "all_played" = compare only after all 4 are down (still earliest wins ties)

# ─────────────────────────────────────────────
#  TRUMP & SUIT RULES
# ─────────────────────────────────────────────
var doubles_are_trump: bool = false         # "Doubles" as the declared trump choice (own suit, ranked as a suit)
var doubles_trump_reversed: bool = false    # 0-0 high -> 6-6 low, instead of the standard 6-6 high -> 0-0 low
var default_trump_if_undeclared: bool = false  # If true, first lead's suit becomes trump when none was named
var allow_small_end_opening_lead: bool = false # First trick only: lead a non-trump domino as its smaller-pip suit
var force_trump_opening_lead: bool = false     # If true, the very first lead must be a trump domino

# ─────────────────────────────────────────────
#  SCORING
# ─────────────────────────────────────────────
var score_by_marks: bool = true
var marks_to_win: int = 7
var points_to_win: int = 250
var set_penalty: String = "bid"             # "bid" or "all_points"
var count_dominos_in_tricks: bool = true
var winning_trick_bonus: int = 0

# ─────────────────────────────────────────────
#  GAME FLOW / DISPLAY
# ─────────────────────────────────────────────
var allow_renege_challenge: bool = true
var renege_penalty: String = "set"          # "set" or "points"
var shuffle_style: String = "random"
var allow_table_talk: bool = false
var allow_early_hand_end: bool = true       # Lay-down / early stop once outcome is locked in
var stack_tricks_display: bool = false      # Hide all but most recent 1-2 tricks per side instead of showing all flat

# ─────────────────────────────────────────────
#  PRESET HELPERS
# ─────────────────────────────────────────────
static func texas_standard() -> GameSettings:
	var s = GameSettings.new()
	s.bid_direction = "clockwise"
	s.allow_nello = true
	s.nello_partner_sits_out = true
	s.nello_doubles_mode = "high"
	s.allow_plunge = true
	s.allow_splash = false
	s.allow_follow_me = false
	s.allow_sevens = false
	s.allow_low_no = false
	s.score_by_marks = true
	s.marks_to_win = 7
	return s

static func pagat_tournament() -> GameSettings:
	# Closely follows pagat.com's "marks" ruleset (McLeod/Celko)
	var s = GameSettings.new()
	s.bid_direction = "clockwise"
	s.max_open_bid_marks = 2
	s.allow_plunge = true
	s.plunge_minimum_doubles = 4
	s.plunge_minimum_bid_marks = 4
	s.allow_splash = true
	s.splash_minimum_doubles = 3
	s.splash_bid_marks = 2
	s.allow_nello = true
	s.nello_partner_sits_out = true
	s.nello_doubles_mode = "own_suit"
	s.allow_follow_me = true
	s.follow_me_allow_as_points_bid = false
	s.allow_sevens = true
	s.sevens_require_seven_in_hand = false
	s.allow_low_no = false
	s.score_by_marks = true
	s.marks_to_win = 7
	return s

static func family_house_rules() -> GameSettings:
	# Built directly from the family house-rules document.
	var s = GameSettings.new()
	s.bid_direction = "counterclockwise"   # left of shaker bids first, shaker bids last, going right
	s.allow_forced_bid = true
	s.forced_bid_minimum = 30
	s.reshake_if_all_pass = false
	s.minimum_bid = 30
	s.allow_jump_bids = true                # "any amount up to one mark higher" per family rule

	s.allow_plunge = true
	s.plunge_minimum_doubles = 4
	s.plunge_minimum_bid_marks = 4
	s.allow_splash = false                  # not mentioned by family; default off until confirmed

	s.allow_nello = true
	s.nello_partner_sits_out = true
	s.allow_nello_exchange = true
	s.nello_exchange_bidder_gives = "high"
	s.nello_exchange_partner_gives = "low"
	s.nello_doubles_mode = "own_suit"       # bidder's choice in practice; this is the default selection
	s.nello_doubles_reversed = false

	s.allow_follow_me = true
	s.follow_me_allow_as_points_bid = false # treated as marks-only so far per family notes

	s.allow_sevens = true
	s.sevens_require_seven_in_hand = true
	s.sevens_tie_rule = "earliest"

	s.allow_low_no = false                  # not part of family rules

	s.score_by_marks = true
	s.marks_to_win = 7
	s.count_dominos_in_tricks = true
	s.set_penalty = "bid"

	s.allow_early_hand_end = true
	s.stack_tricks_display = false
	return s
