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
class_name PublicKnowledge
extends RefCounted

# player_id (int) -> Array[int] of suits (0-6) that player is known void in.
var _void_suits: Dictionary = {}

static func from_state(frame: PublicFrame) -> PublicKnowledge:
	var knowledge = PublicKnowledge.new()
	for record in frame.hand_history:
		knowledge._absorb_trick(
			record["plays"], record["lead_suit"], record["trump"],
			record.get("nello_doubles", "high")
		)
	if frame.current_trick != null:
		var t = frame.current_trick
		knowledge._absorb_trick(t.plays, t.lead_suit, t.trump, t.nello_doubles)
	return knowledge

# Returns the suits (0-6) this player is currently known to be void in,
# based on everything visible in the frame this knowledge was built from.
func void_suits(player_id: int) -> Array:
	return _void_suits.get(player_id, []).duplicate()

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
