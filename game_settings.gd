class_name GameSettings
extends RefCounted

# Which of the five ruleset slots these settings came from — one of "teel",
# "standard", "tournament", "lechner", or "custom:Custom" (see
# game_table.gd's SLOT_KEYS). Set by _resolve_settings_for_slot(), not by any
# individual setting field, and carried through settings-screen tweaks via
# _copy_settings(). "" means no slot has been resolved yet (a fresh
# GameSettings.new()), which _persist_preset_tweaks() treats as "nowhere to
# save" — so anything that hands this object to the Settings screen must stamp
# a real key first.
#
# NOTE: to_dict() deliberately does not serialize this. A settings object read
# back from disk therefore arrives with preset_id == "" and must be re-stamped
# by whoever loaded it. It also no longer selects the domino back — that moved
# to a standalone display preference (July 29 2026) so the tile art stops
# changing whenever the ruleset does.
var preset_id: String = ""

# ─────────────────────────────────────────────
#  BIDDING RULES
# ─────────────────────────────────────────────
var bid_direction: String = "shaker_left_first"
# "shaker_left_first": shaker-1, shaker-2, shaker-3, shaker (standard — bidding starts to the dealer's left)
# "shaker_right_first": shaker+1, shaker+2, shaker+3, shaker
var allow_forced_bid: bool = true           # If all pass, shaker must bid minimum
var forced_bid_minimum: int = 30            # Common values: 30, 42
var minimum_bid: int = 30                   # Floor for all bids
var max_open_bid_marks: int = 2             # Cap on opening/non-special bids (marks); Plunge overrides this
var allow_jump_bids: bool = false           # Allow bidding more than 1 above current outside Plunge

var allow_plunge: bool = true
var plunge_minimum_doubles: int = 4
var plunge_minimum_bid_marks: int = 4       # Plunge must open at/jump to this many marks

var allow_splash: bool = false
var splash_minimum_doubles: int = 3
var splash_bid_marks: int = 2

# ─────────────────────────────────────────────
#  NELLO / NILLO
# ─────────────────────────────────────────────
var allow_nello: bool = true

var allow_nello_exchange: bool = true
var nello_exchange_bidder_gives: String = "any"   # "any", "high", "off_suit"
var nello_exchange_partner_gives: String = "low"  # "any", "low", "bidder_calls"

var nello_only_on_forced_bid: bool = false

var nello_doubles_mode: String = "high"
# "high"     — doubles are highest of their suit (standard)
# "low"      — doubles are lowest of their suit
# "own_suit" — doubles are a suit unto themselves
var nello_doubles_reversed: bool = false    # Within own_suit mode, double-blank is highest
# Ruleset toggle: whether "Own Suit (Reversed)" is offered as a doubles-mode
# choice at all. Does not represent live game state — see
# game.active_nello_doubles_reversed for that.

# ─────────────────────────────────────────────
#  FOLLOW ME / NO TRUMP
# ─────────────────────────────────────────────
var allow_follow_me: bool = true

# ─────────────────────────────────────────────
#  SEVENS
# ─────────────────────────────────────────────
var allow_sevens: bool = true
# Must hold a domino summing to 7 to call it. No longer user-facing (the
# settings-screen toggle was removed July 29 2026) — the rule is always on.
# from_dict() forces this true regardless of what a saved file says, so an
# externally-distributed save that stored false can't strand a player with a
# rule they have no control to change back.
var sevens_require_seven_in_hand: bool = true
var sevens_only_on_forced_bid: bool = false

# ─────────────────────────────────────────────
#  TRUMP & SUIT RULES
# ─────────────────────────────────────────────
var doubles_are_trump: bool = false         # "Doubles" as the declared trump choice (own suit, ranked as a suit)
var doubles_trump_reversed: bool = false    # 0-0 high -> 6-6 low, instead of the standard 6-6 high -> 0-0 low
var allow_small_end_opening_lead: bool = false # First trick only: lead a non-trump domino as its smaller-pip suit
var force_trump_opening_lead: bool = false     # If true, the very first lead must be a trump domino

# ─────────────────────────────────────────────
#  SCORING
# ─────────────────────────────────────────────
var marks_to_win: int = 7
var win_by_two: bool = false

# ─────────────────────────────────────────────
#  GAME FLOW / DISPLAY
# ─────────────────────────────────────────────
# "casual" | "expert" — see AIPlayer.AI_MODES.
#
# Player state that a ruleset merely seeds, not rule content. It has its own
# main-menu screen, commits the moment it's clicked (unlike every other field
# here, which waits for Play), and persists in last_used.json. Consequently it is
# NOT serialized by to_dict() and NOT read by from_dict() — the value each preset
# function sets below is the first-run seed for that slot, and
# game_table.gd's _resolve_settings_for_slot() is the single place that decides
# which difficulty a session actually runs at.
var ai_difficulty: String = "expert"

# ─────────────────────────────────────────────
#  LAY DOWN ("Can't Be Caught")
# ─────────────────────────────────────────────
var allow_laydown: bool = false
var laydown_mode: String = "assisted"       # "assisted" (button only appears once
											 # provably correct) | "authentic" (self-judged,
											 # verified silently, wrong claim forfeits)

# ─────────────────────────────────────────────
#  HAND-ENDS-EARLY
# ─────────────────────────────────────────────
var hand_ends_early_set: bool = true     # All-tricks contracts (Marks/Sevens/
										  # Nello/Plunge/Splash): stop the moment
										  # the contract is mathematically
										  # unrecoverable. Defaults true — matches
										  # current (previously toggle-less) behavior.
var hand_ends_early_points: bool = false # Points bids (incl. Follow Me): stop
										  # the moment the bid is either already
										  # achieved or already unreachable.
										  # New behavior — defaults off.

# ─────────────────────────────────────────────
#  PRESET HELPERS
# ─────────────────────────────────────────────
static func standard_42() -> GameSettings:
	# Baseline rules — "just learn the game" option
	var s = GameSettings.new()
	s.bid_direction = "shaker_left_first"
	s.allow_forced_bid = true
	s.forced_bid_minimum = 30
	s.minimum_bid = 30
	s.max_open_bid_marks = 2
	s.allow_jump_bids = false
	s.allow_nello = true
	s.nello_doubles_mode = "own_suit"
	s.allow_plunge = true
	s.plunge_minimum_doubles = 4
	s.plunge_minimum_bid_marks = 4
	s.allow_splash = true
	s.splash_minimum_doubles = 3
	s.splash_bid_marks = 2
	s.allow_follow_me = true
	s.allow_sevens = true
	s.sevens_require_seven_in_hand = true
	s.marks_to_win = 7
	s.ai_difficulty = "casual"
	return s

static func tournament_rules() -> GameSettings:
	# Strict tournament rules per texas42.net/tournamentsample.html
	# Key: no Plunge/Splash/Sevens; Nello only as forced bid; max open 2 marks
	var s = GameSettings.new()
	s.bid_direction = "shaker_left_first"
	s.allow_forced_bid = true
	s.forced_bid_minimum = 30
	s.minimum_bid = 30
	s.max_open_bid_marks = 2
	s.allow_jump_bids = false
	s.allow_nello = true
	s.nello_only_on_forced_bid = true
	s.nello_doubles_mode = "high"
	s.allow_plunge = false
	s.allow_splash = false
	s.allow_follow_me = true
	s.allow_sevens = false
	s.marks_to_win = 7
	s.ai_difficulty = "expert"
	return s

static func lechner_hall() -> GameSettings:
	# Aggie 42 — Lechner Hall Texas A&M rules per texas42.net/lechnerhall.html
	# Splash min is 3 marks (not 2); Nello doubles configurable; Follow Me / Sevens allowed
	# Lechner rules require win by 2 marks.
	var s = GameSettings.new()
	s.bid_direction = "shaker_left_first"
	s.allow_forced_bid = true
	s.forced_bid_minimum = 30
	s.minimum_bid = 30
	s.max_open_bid_marks = 2
	s.allow_jump_bids = false
	s.allow_nello = true
	s.nello_doubles_mode = "own_suit"
	s.nello_doubles_reversed = false
	s.allow_plunge = true
	s.plunge_minimum_doubles = 4
	s.plunge_minimum_bid_marks = 4
	s.allow_splash = true
	s.splash_minimum_doubles = 3
	s.splash_bid_marks = 3
	s.allow_follow_me = true
	s.allow_sevens = true
	s.sevens_require_seven_in_hand = true
	s.marks_to_win = 7
	s.win_by_two = true
	s.ai_difficulty = "expert"
	return s

static func teel_rules() -> GameSettings:
	# Built directly from the family house-rules document.
	var s = GameSettings.new()
	s.bid_direction = "shaker_left_first"   # left of shaker bids first, shaker bids last, going right
	s.allow_forced_bid = true
	s.forced_bid_minimum = 30
	s.minimum_bid = 30
	s.allow_jump_bids = false                # confirmed off, July 21 2026

	s.allow_plunge = true
	s.plunge_minimum_doubles = 4
	s.plunge_minimum_bid_marks = 4
	s.allow_splash = true                   # confirmed on, July 21 2026

	s.allow_nello = true
	s.allow_nello_exchange = true
	s.nello_exchange_bidder_gives = "high"
	s.nello_exchange_partner_gives = "low"
	s.nello_doubles_mode = "own_suit"       # bidder's choice in practice; this is the default selection
	s.nello_doubles_reversed = false

	s.allow_follow_me = true

	s.allow_sevens = true
	s.sevens_require_seven_in_hand = true

	s.marks_to_win = 7
	s.ai_difficulty = "casual"
	return s

# ─────────────────────────────────────────────
#  DIFFICULTY NORMALIZATION
# ─────────────────────────────────────────────
# The middle tier "standard" was retired July 29 2026 when difficulty dropped
# from three tiers to two (casual/expert). Saved files written before then can
# still carry it, and they live in three shapes: preset_overrides/*.json and
# custom_rulesets/*.json (both go through from_dict) AND last_used.json, which
# is NOT a serialized GameSettings — it's {last_preset, ai_difficulty,
# seat_assignments} and its ai_difficulty is read directly, bypassing from_dict
# entirely. So this has to be a shared function callable from those direct read
# sites too, not a fixup buried inside from_dict.
#
# Retired "standard" resolves to "expert", not "casual": it sat above the old
# beginner tier, so rounding it down would quietly make a returning player's
# opponents worse than they left them.
static func normalize_difficulty(value: String) -> String:
	if value == "standard" or value == "beginner":
		# "beginner" is the pre-rename spelling of "casual"; "standard" is the
		# retired middle tier.
		return "casual" if value == "beginner" else "expert"
	if value == "casual" or value == "expert":
		return value
	# Unrecognized (hand-edited file, future tier that got rolled back) — fall
	# to the same place the AI_MODES lookup defaults to.
	return "expert"

# ─────────────────────────────────────────────
#  SERIALIZATION
# ─────────────────────────────────────────────
static func to_dict(s: GameSettings) -> Dictionary:
	return {
		"bid_direction": s.bid_direction,
		"allow_forced_bid": s.allow_forced_bid,
		"forced_bid_minimum": s.forced_bid_minimum,
		"minimum_bid": s.minimum_bid,
		"max_open_bid_marks": s.max_open_bid_marks,
		"allow_jump_bids": s.allow_jump_bids,
		"allow_plunge": s.allow_plunge,
		"plunge_minimum_doubles": s.plunge_minimum_doubles,
		"plunge_minimum_bid_marks": s.plunge_minimum_bid_marks,
		"allow_splash": s.allow_splash,
		"splash_minimum_doubles": s.splash_minimum_doubles,
		"splash_bid_marks": s.splash_bid_marks,
		"allow_nello": s.allow_nello,
		"allow_nello_exchange": s.allow_nello_exchange,
		"nello_exchange_bidder_gives": s.nello_exchange_bidder_gives,
		"nello_exchange_partner_gives": s.nello_exchange_partner_gives,
		"nello_only_on_forced_bid": s.nello_only_on_forced_bid,
		"nello_doubles_mode": s.nello_doubles_mode,
		"nello_doubles_reversed": s.nello_doubles_reversed,
		"allow_follow_me": s.allow_follow_me,
		"allow_sevens": s.allow_sevens,
		"sevens_require_seven_in_hand": s.sevens_require_seven_in_hand,
		"sevens_only_on_forced_bid": s.sevens_only_on_forced_bid,
		"doubles_are_trump": s.doubles_are_trump,
		"doubles_trump_reversed": s.doubles_trump_reversed,
		"allow_small_end_opening_lead": s.allow_small_end_opening_lead,
		"force_trump_opening_lead": s.force_trump_opening_lead,
		"marks_to_win": s.marks_to_win,
		"win_by_two": s.win_by_two,
		# ai_difficulty is deliberately absent — see the field's own comment.
		# Ruleset files hold rule content only; the chosen difficulty is player
		# state and lives in last_used.json.
		"allow_laydown": s.allow_laydown,
		"laydown_mode": s.laydown_mode,
		"hand_ends_early_set": s.hand_ends_early_set,
		"hand_ends_early_points": s.hand_ends_early_points,
	}

static func from_dict(d: Dictionary) -> GameSettings:
	var s = GameSettings.new()
	s.bid_direction = d.get("bid_direction", "shaker_left_first")
	s.allow_forced_bid = d.get("allow_forced_bid", true)
	s.forced_bid_minimum = d.get("forced_bid_minimum", 30)
	s.minimum_bid = d.get("minimum_bid", 30)
	s.max_open_bid_marks = d.get("max_open_bid_marks", 2)
	s.allow_jump_bids = d.get("allow_jump_bids", false)
	s.allow_plunge = d.get("allow_plunge", true)
	s.plunge_minimum_doubles = d.get("plunge_minimum_doubles", 4)
	s.plunge_minimum_bid_marks = d.get("plunge_minimum_bid_marks", 4)
	s.allow_splash = d.get("allow_splash", false)
	s.splash_minimum_doubles = d.get("splash_minimum_doubles", 3)
	s.splash_bid_marks = d.get("splash_bid_marks", 2)
	s.allow_nello = d.get("allow_nello", true)
	s.allow_nello_exchange = d.get("allow_nello_exchange", true)
	s.nello_exchange_bidder_gives = d.get("nello_exchange_bidder_gives", "any")
	s.nello_exchange_partner_gives = d.get("nello_exchange_partner_gives", "low")
	s.nello_only_on_forced_bid = d.get("nello_only_on_forced_bid", false)
	s.nello_doubles_mode = d.get("nello_doubles_mode", "high")
	s.nello_doubles_reversed = d.get("nello_doubles_reversed", false)
	s.allow_follow_me = d.get("allow_follow_me", true)
	s.allow_sevens = d.get("allow_sevens", true)
	# Deliberately ignores the saved value — the rule is always on and has no UI
	# control any more, so honoring a stored false would be unfixable in-game.
	s.sevens_require_seven_in_hand = true
	s.sevens_only_on_forced_bid = d.get("sevens_only_on_forced_bid", false)
	s.doubles_are_trump = d.get("doubles_are_trump", false)
	s.doubles_trump_reversed = d.get("doubles_trump_reversed", false)
	s.allow_small_end_opening_lead = d.get("allow_small_end_opening_lead", false)
	s.force_trump_opening_lead = d.get("force_trump_opening_lead", false)
	s.marks_to_win = d.get("marks_to_win", 7)
	s.win_by_two = d.get("win_by_two", false)
	# ai_difficulty is intentionally NOT read back. to_dict() stopped writing it,
	# and files written before that carry a value that the resolver overwrites
	# anyway — reading it would only make a stale number look authoritative to
	# anyone stepping through here. game_table.gd's _resolve_settings_for_slot()
	# supplies difficulty: the slot's shipped default as a seed, overridden by the
	# player's committed choice from last_used.json.
	s.allow_laydown = d.get("allow_laydown", false)
	s.laydown_mode = d.get("laydown_mode", "assisted")
	s.hand_ends_early_set = d.get("hand_ends_early_set", true)
	s.hand_ends_early_points = d.get("hand_ends_early_points", false)
	return s
