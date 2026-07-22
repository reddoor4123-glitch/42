extends SceneTree

# ═══════════════════════════════════════════════════════════════════════════
# laydown_check_trace.gd — smoke test for LaydownCheck.is_provable_laydown()
# (July 21, 2026), covering the accounting rule we worked out at the table:
# a domino held in the claimant's own hand is excluded from the threat pool
# the same way an already-played domino is, since it can't simultaneously
# be with an opponent.
#
# Run:
#   "$GODOT" --headless --path . --script res://laydown_check_trace.gd
# ═══════════════════════════════════════════════════════════════════════════

const LaydownCheckScript = preload("res://laydown_check.gd")

var failures: Array = []
var log_lines: Array = []

func _log(s: String):
	log_lines.append(s)
	print(s)

func _check(label: String, condition: bool, detail: String) -> void:
	if condition:
		_log("  PASS: %s — %s" % [label, detail])
	else:
		_log("  FAIL: %s — %s" % [label, detail])
		failures.append(label)

func _hand(pairs: Array) -> Array[Domino]:
	var h: Array[Domino] = []
	for p in pairs:
		h.append(Domino.new(p[0], p[1]))
	return h

# Builds a PublicKnowledge where every tile in `played_pairs` is recorded
# as already played, and nothing else. Trick shape/legality doesn't matter
# here — PublicKnowledge._record_played() just needs a "plays" array with
# {"player","domino"} entries; who played what and in what order is
# irrelevant to has_been_played().
func _knowledge(played_pairs: Array, trump: int, nello_doubles: String = "high") -> PublicKnowledge:
	var plays: Array = []
	for i in range(played_pairs.size()):
		var p = played_pairs[i]
		plays.append({"player": i % 4, "domino": Domino.new(p[0], p[1])})
	var record = {
		"plays": plays,
		"lead_suit": -1,  # irrelevant here — no void-inference used by v1
		"trump": trump,
		"nello_doubles": nello_doubles,
	}
	var history: Array = [record] if plays.size() > 0 else []
	var frame = PublicFrame.new(history, null)
	return PublicKnowledge.from_state(frame)

func _run_case(label: String, hand_pairs: Array, trump: int, played_pairs: Array, expected: bool) -> void:
	var hand = _hand(hand_pairs)
	var knowledge = _knowledge(played_pairs, trump)
	var result = LaydownCheckScript.is_provable_laydown(hand, trump, knowledge)
	_check(label, result == expected,
		"hand=%s trump=%d played=%s -> expected %s, got %s" % [
			hand_pairs, trump, played_pairs, expected, result
		])

func _init():
	_log("═══════════════════════════════════════════════════════════")
	_log("LaydownCheck.is_provable_laydown() — accounting rule coverage")
	_log("═══════════════════════════════════════════════════════════")

	# ── Katy's own example: holding 6:6 makes 6:5 safe even though 6:6 is
	# NOT recorded as played — it's accounted for by being in the same
	# claimed hand. trump=2 keeps 6:x tiles out of the trump suit entirely
	# (2:6 becomes trump instead of sixes) so this only exercises the
	# sixes-suit accounting, not trump logic. ──────────────────────────────
	_run_case("own_hand_excludes_6_6_makes_6_5_safe",
		[[6,6],[6,5]], 2, [], true)

	_run_case("without_6_6_held_or_played_6_5_is_unsafe",
		[[6,5]], 2, [], false)

	_run_case("6_5_safe_if_6_6_already_played_instead",
		[[6,5]], 2, [[6,6]], true)

	# ── Top three ranked trump, two lower ones already played. NOTE (found
	# by Claude Code during review, July 21, 2026): this case's name
	# overclaims — 6:5 and 6:4's safety here actually comes entirely from
	# 6:6 being self-held (same mechanism as the first case above); the two
	# plays are irrelevant since 6:3/6:2 rank below both candidates
	# regardless. Left in as a valid passing case, not removed, but the two
	# genuinely played-dependent cases directly below are what actually
	# close this coverage gap. ──────────────────────────────────────────────
	_run_case("top_three_trump_all_safe_self_held_double_does_the_work",
		[[6,6],[6,5],[6,4]], 6, [[6,3],[6,2]], true)

	# ── Genuine played-dependency: 6:4's only two possible threats (6:5
	# and 6:6) are NEITHER self-held here — the candidate hand holds only
	# 6:4 alone. Safety depends entirely on both being recorded as already
	# played; nothing else in the suit ranks above 6:4 regardless. ─────────
	_run_case("genuine_played_dependency_both_threats_played",
		[[6,4]], 6, [[6,5],[6,6]], true)

	# ── Same hand, same tile, neither threat played or held — the direct
	# negative contrast proving the case above really does depend on the
	# played list, not on some other accident of the hand shape. ───────────
	_run_case("genuine_played_dependency_negative_contrast",
		[[6,4]], 6, [], false)

	# ── False claim: looks like the same shape as above, but the actual
	# top trump (6:6) is neither played nor held — a real, live threat. ────
	_run_case("false_claim_top_trump_unaccounted_for",
		[[6,5],[6,4]], 6, [], false)

	# ── Mixed hand: one genuinely safe tile (6:6, trivially top trump)
	# alongside one unsafe tile (3:2, with 3:3 unaccounted for) — the whole
	# claim must fail even though most of the hand is fine. ────────────────
	_run_case("one_unsafe_tile_fails_the_whole_claim",
		[[6,6],[3,2]], 6, [], false)

	# ── Cross-suit independence: three different suits (ones/twos/threes
	# — recall a non-double's suit is its HIGH end when led, so these never
	# actually compete with each other), each individually safe via a mix
	# of "it's the double itself" and "the one real threat is in my own
	# hand." No suit here overlaps with trump. ──────────────────────────────
	_run_case("independent_suits_double_plus_own_hand_exclusion",
		[[2,2],[1,2],[3,3]], 5, [], true)

	_log("")
	_log("═══════════════════════════════════════════════════════════")
	if failures.is_empty():
		_log("ALL CHECKS PASSED")
	else:
		_log("FAILURES: %s" % [failures])
	_log("═══════════════════════════════════════════════════════════")

	var output = {
		"failures": failures,
		"full_log": log_lines,
	}
	var f = FileAccess.open("res://laydown_check_trace_results.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(output, "\t"))
	f.close()

	print("")
	print("Results written to res://laydown_check_trace_results.json")
	quit(0 if failures.is_empty() else 1)
