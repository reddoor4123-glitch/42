extends SceneTree

# Verification suite for two linked fixes (July 30 2026):
#
#   1. AIPlayer.decide_bid() reads settings.minimum_bid and
#      settings.forced_bid_minimum instead of a hardcoded 30 in three places.
#   2. game_table.gd routes both AI bid loops through _accept_ai_bid(), so
#      Bid.is_valid() actually runs on an AI bid the way it now does on the
#      human's.
#
# They ship together on purpose. Fix 2 alone would start rejecting the AI's
# own bids on any ruleset with minimum_bid > 30, because fix 1 is what makes
# those bids legal in the first place.
#
# The load-bearing test here is _test_every_ai_bid_is_legal(): rather than
# enumerating rules, it plays out whole auctions across several rulesets and
# asserts that every bid decide_bid() produced would have passed the
# validator. That is the invariant the two fixes exist to guarantee, and it
# stays meaningful as the bidding logic changes underneath it.
#
# Runs all four seats as AI (human_seat = -1) for maximum coverage of the
# paths a real game reaches only when the human is not in that chair.
#
# EXPECTED on stderr: "ObjectDB instances leaked at exit" (gotcha #10).
# Judge the exit code and the results JSON.

const BidScript = preload("res://bid.gd")
const GameSettingsScript = preload("res://game_settings.gd")
const AIPlayer = preload("res://ai_player.gd")

const DEALS_PER_RULESET := 60

var _results: Array = []
var _failures := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	_results.append({"test": name, "pass": ok, "detail": detail})
	if not ok:
		_failures += 1

func _eq(name: String, got, want) -> void:
	_check(name, got == want, "got %s, want %s" % [got, want])

# ── Ruleset shapes worth covering ────────────────────────────────────
# Named for what makes each one interesting, not for a preset — the point is
# the floor values, and only "baseline" matches anything shipped.
func _ruleset(label: String) -> GameSettings:
	var s = GameSettingsScript.standard_42()
	match label:
		"baseline":
			pass                                  # minimum_bid 30, forced 30
		"high_minimum":
			s.minimum_bid = 35
			s.forced_bid_minimum = 35
		"high_forced_only":
			s.minimum_bid = 30
			s.forced_bid_minimum = 42
		"inverted":                               # forced BELOW minimum — must clamp up
			s.minimum_bid = 35
			s.forced_bid_minimum = 30
	return s

func _hand_from(g: Game, pid: int) -> Array[Domino]:
	return g.players[pid].hand

# Plays one full four-seat auction and returns a record per bid.
func _run_auction(s: GameSettings, seed_val: int) -> Array:
	var g = Game.new(s)
	g.setup_players(0)
	seed(seed_val)
	g.deal_hands()
	var order: Array = g.bid_order()
	var out: Array = []
	for i in range(4):
		var pid: int = order[i]
		var is_forced: bool = (i == 3 and g.current_bid == null and s.allow_forced_bid)
		var high = g.current_bid
		var b = AIPlayer.decide_bid(
			_hand_from(g, pid), pid, high, s, is_forced,
			s.ai_difficulty, [], g.shaker, -1)
		out.append({
			"bid": b,
			"high_str": "none" if high == null else high.debug_string(),
			"legal": BidScript.is_valid(b, high, s, g.bid_context(pid, i)),
			"forced": is_forced,
		})
		if b.type != BidScript.Type.PASS:
			g.current_bid = b
	return out

# ── The invariant ────────────────────────────────────────────────────
func _test_every_ai_bid_is_legal() -> void:
	for label in ["baseline", "high_minimum", "high_forced_only", "inverted"]:
		var s = _ruleset(label)
		var illegal: Array = []
		var bids_seen := 0
		for d in range(DEALS_PER_RULESET):
			for rec in _run_auction(s, d * 977 + 13):
				if rec["bid"].type == BidScript.Type.PASS:
					continue
				bids_seen += 1
				if not rec["legal"]:
					illegal.append("%s over %s%s" % [
						rec["bid"].debug_string(), rec["high_str"],
						" (forced)" if rec["forced"] else ""])
		_check("%s: every AI bid passes Bid.is_valid()" % label,
			illegal.is_empty(),
			"%d bids checked, %d illegal%s" % [
				bids_seen, illegal.size(),
				"" if illegal.is_empty() else " — e.g. " + str(illegal.slice(0, 3))])
		# A ruleset that produced no bids at all would make the check above
		# vacuous, which is the failure mode gotcha #8 exists to warn about.
		_check("%s: auctions actually produced bids" % label, bids_seen > 0,
			"%d bids" % bids_seen)

# ── Points floor ─────────────────────────────────────────────────────
func _test_points_floor_respected() -> void:
	for label in ["baseline", "high_minimum", "inverted"]:
		var s = _ruleset(label)
		var below: Array = []
		for d in range(DEALS_PER_RULESET):
			for rec in _run_auction(s, d * 641 + 7):
				var b = rec["bid"]
				if b.type == BidScript.Type.POINTS and b.value < s.minimum_bid:
					below.append("%d < %d" % [b.value, s.minimum_bid])
		_check("%s: no points bid below settings.minimum_bid (%d)" % [label, s.minimum_bid],
			below.is_empty(),
			"%d violations%s" % [below.size(),
				"" if below.is_empty() else " — e.g. " + str(below.slice(0, 3))])

# ── Forced floor ─────────────────────────────────────────────────────
# is_forced sets should_bid true regardless of hand strength, so any hand
# exercises this path — no need to engineer an all-pass auction.
func _test_forced_floor() -> void:
	var weak: Array[Domino] = []
	for pair in [[0,1],[0,2],[1,2],[0,3],[1,3],[2,3],[0,4]]:
		weak.append(Domino.new(pair[0], pair[1]))

	for label in ["baseline", "high_minimum", "high_forced_only", "inverted"]:
		var s = _ruleset(label)
		var expected: int = max(s.forced_bid_minimum, s.minimum_bid)
		# player_id == shaker: the forced bidder is definitionally last to bid.
		var b = AIPlayer.decide_bid(weak, 0, null, s, true, s.ai_difficulty, [], 0, -1)
		_check("%s: forced bid is a points bid" % label,
			b.type == BidScript.Type.POINTS, "got %s" % b.debug_string())
		_eq("%s: forced bid == max(forced_bid_minimum, minimum_bid)" % label,
			b.value, expected)
		_check("%s: forced bid is legal" % label,
			BidScript.is_valid(b, null, s), "bid %s" % b.debug_string())

# ── Regression: the shipped presets must be unchanged ─────────────────
# Every preset sets minimum_bid = 30 and forced_bid_minimum = 30, so reading
# the settings has to reproduce exactly what the hardcoded 30s did. If this
# fails, the fix changed live behaviour rather than generalising it.
func _test_shipped_presets_unchanged() -> void:
	var presets := {
		"standard_42":      GameSettingsScript.standard_42(),
		"tournament_rules": GameSettingsScript.tournament_rules(),
		"lechner_hall":     GameSettingsScript.lechner_hall(),
		"teel_rules":       GameSettingsScript.teel_rules(),
	}
	for maker in presets.keys():
		var s: GameSettings = presets[maker]
		_eq("%s: minimum_bid still 30" % maker, s.minimum_bid, 30)
		_eq("%s: forced_bid_minimum still 30" % maker, s.forced_bid_minimum, 30)
		var weak: Array[Domino] = []
		for pair in [[0,1],[0,2],[1,2],[0,3],[1,3],[2,3],[0,4]]:
			weak.append(Domino.new(pair[0], pair[1]))
		var b = AIPlayer.decide_bid(weak, 0, null, s, true, s.ai_difficulty, [], 0, -1)
		_eq("%s: forced bid still opens at 30" % maker, b.value, 30)

func _init() -> void:
	_test_every_ai_bid_is_legal()
	_test_points_floor_respected()
	_test_forced_floor()
	_test_shipped_presets_unchanged()

	var f = FileAccess.open("res://headless/bid_minimums_verify_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"failures": _failures, "total": _results.size(), "results": _results,
		}, "\t"))
		f.close()
	for r in _results:
		print("  %s: %s — %s" % ["PASS" if r["pass"] else "FAIL", r["test"], r["detail"]])
	print("\n%d assertions, %d failures" % [_results.size(), _failures])
	quit(1 if _failures > 0 else 0)
