extends SceneTree

# Assertion suite for LaydownCheck.is_provable_nello_laydown().
#
# Pure logic over constructed hands — no scene, no user:// access. Each case
# states the position and the expected verdict, so a disagreement points at the
# rule rather than at the harness.
#
# Seating: claimant (Nello bidder) = 0, opponents = 1 and 3, partner = 2 sits out
# and never appears in `hands`. Turn order is -1 mod 4, so from leader 1 the
# order is 1, 0, 3.

const LaydownCheckScript = preload("res://laydown_check.gd")

var _results: Array = []
var _failures := 0

func _check(name: String, got: bool, want: bool, note: String = "") -> void:
	var ok := got == want
	_results.append({"test": name, "pass": ok, "want": want, "got": got, "note": note})
	if not ok:
		_failures += 1

func _d(a: int, b: int) -> Domino:
	return Domino.new(a, b)

func _hand(pairs: Array) -> Array:
	var out: Array = []
	for p in pairs:
		out.append(_d(p[0], p[1]))
	return out

# Runs a position with no trick in progress yet (opponent 1 about to lead).
func _run(claimant: Array, opp1: Array, opp3: Array, mode: String = "high",
		rev: bool = false, leader: int = 1) -> bool:
	var hands := {0: claimant, 1: opp1, 3: opp3}
	return LaydownCheckScript.is_provable_nello_laydown(0, hands, [], leader, mode, rev)

func _init():
	# ── Trivial shapes ───────────────────────────────────────────────────────
	# One trick left. Claimant holds the lowest of the led suit; both opponents
	# hold higher tiles of it, so following is forced and loses.
	_check("single trick, claimant lowest of led suit",
		_run([_d(6, 0)], [_d(6, 5)], [_d(6, 4)]), true)

	# Same shape, claimant holds the highest — whatever is led they take it.
	_check("single trick, claimant highest of led suit",
		_run([_d(6, 5)], [_d(6, 0)], [_d(6, 1)]), false)

	# ── The void-discard case ────────────────────────────────────────────────
	# Claimant is void in the led suit, so the tile is a free discard and cannot
	# win: an off-suit tile never beats the led suit with no trump in play.
	_check("void in led suit is a free discard",
		_run([_d(2, 1)], [_d(6, 5)], [_d(6, 4)]), true)

	# ── The case a static rank test gets wrong ───────────────────────────────
	# Claimant holds the 1st and 3rd lowest of a suit; opponents hold the 2nd and
	# 4th. Every static "is my tile the lowest remaining" rule rejects this, but
	# it is genuinely safe: duck under whichever is led and keep the other back.
	_check("1st and 3rd lowest of a suit is safe (static rule rejects it)",
		_run([_d(6, 0), _d(6, 2)], [_d(6, 1), _d(5, 5)], [_d(6, 3), _d(4, 4)]), true)

	# The near-miss: claimant holds 2nd and 3rd lowest while an opponent holds
	# the very lowest and can lead it, and the other opponent is void in the suit
	# and simply discards — nobody is left to beat the claimant.
	_check("2nd/3rd lowest caught when the other opponent is void",
		_run([_d(6, 1), _d(6, 2)], [_d(6, 0), _d(5, 5)], [_d(3, 2), _d(4, 4)]), false)

	# ── Doubles: high ────────────────────────────────────────────────────────
	# In "high" a double is the top of its own pip suit, so holding one is fatal
	# the moment that suit is led.
	_check("doubles-high: holding 6:6 is fatal when sixes are led",
		_run([_d(6, 6)], [_d(6, 0)], [_d(6, 1)], "high"), false)

	# ── Doubles: low ─────────────────────────────────────────────────────────
	# The identical position is safe under "low", where the double ranks bottom.
	_check("doubles-low: the same 6:6 is safe",
		_run([_d(6, 6)], [_d(6, 0)], [_d(6, 1)], "low"), true)

	# ── Doubles: own suit ────────────────────────────────────────────────────
	# Doubles form their own suit ranked by pip. 0:0 is the bottom of it, so it
	# ducks under any other double led.
	_check("own_suit: 0:0 ducks under a led double",
		_run([_d(0, 0)], [_d(3, 3)], [_d(5, 5)], "own_suit"), true)
	# 6:6 is the top of the doubles suit and takes any doubles trick.
	_check("own_suit: 6:6 takes the doubles trick",
		_run([_d(6, 6)], [_d(3, 3)], [_d(5, 5)], "own_suit"), false)

	# ── Doubles: own suit reversed ───────────────────────────────────────────
	# Reversal swaps both verdicts and nothing else — the single clearest signal
	# that the mode is genuinely threaded through rather than assumed.
	_check("own_suit reversed: 0:0 now takes the trick",
		_run([_d(0, 0)], [_d(3, 3)], [_d(5, 5)], "own_suit", true), false)
	_check("own_suit reversed: 6:6 is now safe",
		_run([_d(6, 6)], [_d(3, 3)], [_d(5, 5)], "own_suit", true), true)

	# In own_suit a double does NOT follow its pip suit, so a claimant holding
	# only 3:3 is void when threes are led and discards it harmlessly.
	_check("own_suit: 3:3 does not follow a threes lead",
		_run([_d(3, 3)], [_d(3, 1)], [_d(3, 2)], "own_suit"), true)
	# Under "high" that same 3:3 does follow, and wins.
	_check("doubles-high: 3:3 does follow a threes lead and wins",
		_run([_d(3, 3)], [_d(3, 1)], [_d(3, 2)], "high"), false)

	# ── Both ends of a mixed tile ────────────────────────────────────────────
	# 5:3 is safe as a five (rank 3, under 5:6) but fatal as a three (rank 5,
	# over 3:0 and 3:1). A check that only looks at a tile's natural suit calls
	# this safe; it is not, because an opponent can choose to lead threes.
	_check("mixed tile judged on both ends, not just its natural suit",
		_run([_d(5, 3)], [_d(3, 0), _d(6, 5)], [_d(3, 1), _d(6, 4)]), false)

	# ── Multi-trick line requiring correct order of play ─────────────────────
	# Safe only if the claimant spends the right tile at the right time.
	_check("three-trick position with a single surviving line",
		_run([_d(6, 0), _d(5, 0), _d(4, 0)],
			 [_d(6, 1), _d(5, 1), _d(4, 1)],
			 [_d(6, 2), _d(5, 2), _d(4, 2)]), true)

	# ── Mid-trick entry ──────────────────────────────────────────────────────
	# The real call site: opponent 1 has already led and it is the claimant's
	# turn. The led tile must be excluded from opponent 1's remaining hand.
	var hands := {0: _hand([[6, 0]]), 1: _hand([[6, 5]]), 3: _hand([[6, 4]])}
	var mid_plays := [{"player": 1, "domino": (hands[1] as Array)[0]}]
	_check("mid-trick: led tile removed from its owner's hand",
		LaydownCheckScript.is_provable_nello_laydown(0, hands, mid_plays, 1, "high", false),
		true)

	# ── Claimant not in hands ────────────────────────────────────────────────
	_check("unknown claimant seat refuses to certify",
		LaydownCheckScript.is_provable_nello_laydown(
			2, {0: _hand([[6, 0]]), 1: _hand([[6, 5]]), 3: _hand([[6, 4]])}, [], 1),
		false)

	# ── The strand ───────────────────────────────────────────────────────────
	# The shape that makes "I hold the lowest of the suit" insufficient, and the
	# reason a static rank test can't answer this question. Claimant holds 2:0,
	# the lowest ORDINARY two. Opp3 leads 2:2, which under "low" ranks -1 and so
	# sits *below* it, and opp1 is void in twos and can only discard. Nothing is
	# left to beat the claimant and the lowest tile in the suit takes the trick.
	_check("stranded: led double ranks under the claimant, other opponent void",
		_run([_d(2, 0)], [_d(6, 5)], [_d(2, 2)], "low", false, 3), false)

	# ── Full seven-trick position ────────────────────────────────────────────
	# Claimant holds the blank of every suit plus 0:0. Reads as safe by every
	# per-suit rule — the claimant is lowest or near-lowest everywhere and no
	# opponent can lead blanks or ones — but it is NOT, because the twos above
	# can be engineered: the opponents burn opp1's only two as a discard, then
	# opp3 leads 2:2 into the strand. Verified by removing twos from all three
	# hands, which flips the verdict (the case immediately below).
	var t0 := Time.get_ticks_msec()
	var big := _run(
		_hand([[6, 0], [5, 0], [4, 0], [3, 0], [2, 0], [1, 0], [0, 0]]),
		_hand([[6, 1], [5, 1], [4, 1], [3, 1], [2, 1], [6, 6], [5, 5]]),
		_hand([[6, 2], [5, 2], [4, 2], [3, 2], [2, 2], [4, 4], [3, 3]]),
		"low")
	var elapsed := Time.get_ticks_msec() - t0
	_check("full seven-trick position: caught by the twos strand", big, false,
		"%d ms" % elapsed)

	# Same hands with every two removed — the strand is gone and the position is
	# safe. This pairing is what proves the twos are the actual cause rather than
	# some incidental feature of the deal.
	_check("...and safe once the twos are removed from all three hands",
		_run(_hand([[6, 0], [5, 0], [4, 0], [3, 0], [1, 0], [0, 0]]),
			 _hand([[6, 1], [5, 1], [4, 1], [3, 1], [6, 6], [5, 5]]),
			 _hand([[6, 2], [5, 2], [4, 2], [3, 2], [4, 4], [3, 3]]),
			 "low"), true)

	var f = FileAccess.open("res://scripts/nello_laydown_verify_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"failures": _failures, "total": _results.size(), "results": _results,
		}, "\t"))
		f.close()
	quit(1 if _failures > 0 else 0)
