# PublicFrame ("KnowledgeBox")
# Immutable snapshot of all publicly observable game information at a
# decision point. Used exclusively as input to PublicKnowledge inference.
#
# PublicFrame is data, not meaning — it performs no inference itself.
# It holds only facts that have already been recorded: completed tricks,
# plus the current trick as it stands so far.
#
# Construction contract: `current_trick` must reflect only plays that
# already happened THIS trick, before the acting player's own play is
# added. Build this BEFORE calling game.play_domino() for the current
# decision — never after. This is what gives mid-trick void detection
# (e.g. player 2 failing to follow suit on play 2 of 4) to players 3
# and 4 within the same trick, before it's ever written to hand_history.
class_name PublicFrame
extends RefCounted

var hand_history: Array
var current_trick: RefCounted  # Trick, or null if no trick is in progress

func _init(history: Array, trick_in_progress: RefCounted = null):
	hand_history = history
	current_trick = trick_in_progress
