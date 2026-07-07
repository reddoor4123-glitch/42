# PublicKnowledge
# The sole inference layer for information derivable from publicly
# observed play. An immutable snapshot, constructed fresh from a
# PublicFrame at each decision point — never mutated, never cached
# incrementally, never persisted on Game.
#
# Hard rule: if a fact is not derivable from a PublicFrame, it does not
# belong here. And the reverse: if code anywhere else (Trick, AIPlayer,
# game_table.gd) inspects trick.plays to reason about suit-following —
# even for a simple one-off check — that logic belongs here instead.
# Two implementations of the same inference is how this quietly breaks.
#
# PublicKnowledge is a vocabulary layer, not a decision layer.
#
# Every query answers an objective question with exactly one correct
# answer, derivable entirely from PublicFrame. It never evaluates those
# facts, assigns meaning to them, recommends a play, or varies its answer
# by AI difficulty or personality — different AIs may choose to ignore a
# fact, but they must never be given different facts.
#
# PublicKnowledge may compare values, but it must never define what those
# values mean. Any query whose answer depends on relative rank (e.g. a
# "highest remaining X" query) must delegate to the same comparison
# functions Trick and AIPlayer use (Domino.get_rank/get_suit, and by
# extension AIPlayer._beats) — never re-derive comparison logic locally.
# See ai_player.gd's ranking-unification fix for why this matters.
#
# Queries with no meaning under a given contract (e.g. "trump remaining"
# under Sevens) must return a defined sentinel/null/empty result — never
# a silently-computed number that happens not to mean anything.
class_name PublicKnowledge
extends RefCounted

const BidScript = preload("res://bid.gd")
const Deck = preload("res://deck.gd")

# player_id (int) -> Array[int] of suits (0-6) that player is known void in.
var _void_suits: Dictionary = {}

# tile-identity string ("left:right", left <= right, matching Domino's own
# normalization) -> true, for every domino seen in completed or in-progress
# tricks. Used by has_been_played() / remaining_count() / count_remaining_trump().
var _played_tiles: Dictionary = {}

# Context needed by the fact-derivation queries below. Sourced preferentially
# from the in-progress trick (current at construction time); falls back to
# the most recent completed trick's stored values if no trick is in progress;
# falls back to defaults (no meaningful answer) if neither exists. All of
# this is public information — trump, mode, and contract are known to every
# seat, never derived from a hand.
var _current_trick: RefCounted = null  # Trick, or null
var _trump: int = -1
var _nello_doubles: String = "high"
var _doubles_trump_reversed: bool = false
var _own_suit_reversed: bool = false
var _variant: int = -1  # Bid.Type int, or -1 if unknown

static func from_state(frame: PublicFrame) -> PublicKnowledge:
	var knowledge = PublicKnowledge.new()
	for record in frame.hand_history:
		knowledge._absorb_trick(
			record["plays"], record["lead_suit"], record["trump"],
			record.get("nello_doubles", "high")
		)
		knowledge._record_played(record["plays"])
		knowledge._trump = record["trump"]
		knowledge._nello_doubles = record.get("nello_doubles", "high")
		knowledge._doubles_trump_reversed = record.get("doubles_trump_reversed", false)
		knowledge._own_suit_reversed = record.get("own_suit_reversed", false)
	if frame.current_trick != null:
		var t = frame.current_trick
		knowledge._absorb_trick(t.plays, t.lead_suit, t.trump, t.nello_doubles)
		knowledge._record_played(t.plays)
		knowledge._current_trick = t
		knowledge._trump = t.trump
		knowledge._nello_doubles = t.nello_doubles
		knowledge._doubles_trump_reversed = t.doubles_trump_reversed
		knowledge._own_suit_reversed = t.own_suit_reversed
		knowledge._variant = t.variant
	return knowledge

# Records every domino played in one trick's plays (completed or in-progress),
# including the leader's — unlike _absorb_trick's void-detection loop, "has
# this tile been played" has no leader exemption, so this is a separate pass
# rather than folded into _absorb_trick.
func _record_played(plays: Array) -> void:
	for play in plays:
		var d: Domino = play["domino"]
		_played_tiles[d.debug_string()] = true

# Returns the suits (0-6) this player is currently known to be void in,
# based on everything visible in the frame this knowledge was built from.
func void_suits(player_id: int) -> Array:
	return _void_suits.get(player_id, []).duplicate()

# ─── FACT-DERIVATION QUERIES ───────────────────────────────────────────────
# Each of these has exactly one correct answer, derivable entirely from the
# frame this instance was built from. None of them evaluate, weigh, or
# recommend — see file header.

# Whether this exact tile (by face value, not object identity) has appeared
# in any completed or in-progress trick this hand.
func has_been_played(tile: Domino) -> bool:
	return _played_tiles.has(tile.debug_string())

# Whether `player_id` has shown out of `suit`. Thin wrapper over void_suits()
# for callers asking about one specific suit rather than the full list.
func is_void_in(player_id: int, suit: int) -> bool:
	return void_suits(player_id).has(suit)

# Count of unplayed dominoes whose suit (under this hand's current trump and
# nello_doubles mode) equals `suit`. Suit classification always goes through
# Domino.get_suit() — never assumes static pip-based suit membership, since
# a domino's suit depends on trump/mode, not just its pip values.
# Returns -1 (no meaningful answer) if the current contract is Sevens, which
# has no suits at all.
func remaining_count(suit: int) -> int:
	if _variant == BidScript.Type.SEVENS:
		return -1
	var deck = Deck.new()
	deck.build_deck()
	var count = 0
	for d in deck.dominoes:
		if _played_tiles.has(d.debug_string()):
			continue
		if d.get_suit(_trump, _nello_doubles) == suit:
			count += 1
	return count

# Count of unplayed dominoes that are trump under this hand's current trump
# setting. Returns -1 under Sevens (no trump concept). Correctly returns 0
# under Follow Me (trump == -1, no domino qualifies) — that's a real answer,
# not a missing one, since "no trump suit" is exactly what Follow Me means.
func count_remaining_trump() -> int:
	if _variant == BidScript.Type.SEVENS:
		return -1
	var deck = Deck.new()
	deck.build_deck()
	var count = 0
	for d in deck.dominoes:
		if _played_tiles.has(d.debug_string()):
			continue
		if d.is_trump(_trump):
			count += 1
	return count

# Highest-ranked trump domino not yet played, or null if none remain / no
# trump concept applies (Sevens, or Follow Me where trump == -1). Ranking
# delegates entirely to Domino.get_rank() — never re-derived locally, per
# file header contract.
func highest_remaining_trump() -> Domino:
	if _variant == BidScript.Type.SEVENS or _trump < 0:
		return null
	var deck = Deck.new()
	deck.build_deck()
	var best: Domino = null
	var best_rank = -999
	for d in deck.dominoes:
		if _played_tiles.has(d.debug_string()):
			continue
		if not d.is_trump(_trump):
			continue
		var r = d.get_rank(_trump, _nello_doubles, -1, _doubles_trump_reversed, _own_suit_reversed)
		if r > best_rank:
			best_rank = r
			best = d
	return best

# Highest-ranked domino not yet played within `suit` (under this hand's
# current trump/mode). Returns null under Sevens (no suit concept), or if
# no unplayed domino currently classifies into that suit. Same delegation
# rule: ranking goes through Domino.get_rank()/get_suit(), never redefined
# here.
func best_remaining_card_for_suit(suit: int) -> Domino:
	if _variant == BidScript.Type.SEVENS:
		return null
	var deck = Deck.new()
	deck.build_deck()
	var best: Domino = null
	var best_rank = -999
	for d in deck.dominoes:
		if _played_tiles.has(d.debug_string()):
			continue
		if d.get_suit(_trump, _nello_doubles, suit) != suit:
			continue
		var r = d.get_rank(_trump, _nello_doubles, suit, _doubles_trump_reversed, _own_suit_reversed)
		if r > best_rank:
			best_rank = r
			best = d
	return best

# ─── SNAPSHOT ACCESSORS ─────────────────────────────────────────────────────
# These do no inference and derive no facts — they're pure encapsulation
# over frame data already public elsewhere. Kept here (rather than callers
# reaching into frame.current_trick directly) so every caller goes through
# one door, not because these require derivation.

# Duplicated snapshot of the current trick's plays so far, or an empty array
# if no trick is in progress. Duplicated on the way out, matching the
# duplication discipline already used everywhere else public state leaves
# its owner (hand_history, plays_with_reasons, build_hand_record()).
func current_trick_plays() -> Array:
	if _current_trick == null:
		return []
	return _current_trick.plays.duplicate(true)

# Player_id of whoever is currently winning the in-progress trick, or -1 if
# no trick is in progress or no one has led yet. This is a pure delegate to
# Trick.determine_winner() — the same authoritative resolution Trick uses
# to actually end a trick — never reimplemented here. Trick.determine_winner()
# already branches to its own Sevens-specific logic internally by its own
# `variant` field, so no Sevens special-case is needed at this call site.
func trick_leader_so_far() -> int:
	if _current_trick == null or _current_trick.plays.size() == 0:
		return -1
	return _current_trick.determine_winner()

# Scans one trick's plays (completed or in-progress) and records any suit
# a player revealed they couldn't follow. The leader (plays[0]) is exempt —
# leading carries no suit obligation, so it reveals nothing about that
# player's hand. Sevens tricks (lead_suit == -1) have no suits and are
# skipped entirely; this is the same signal that already distinguishes
# Sevens elsewhere in the codebase, so no extra contract-type check needed.
func _absorb_trick(plays: Array, lead_suit: int, trump: int, nello_doubles: String) -> void:
	if lead_suit < 0:
		return
	for i in range(1, plays.size()):
		var play = plays[i]
		var d: Domino = play["domino"]
		var suit = d.get_suit(trump, nello_doubles, lead_suit)
		if suit != lead_suit:
			var pid: int = play["player"]
			if not _void_suits.has(pid):
				_void_suits[pid] = []
			if not _void_suits[pid].has(lead_suit):
				_void_suits[pid].append(lead_suit)
