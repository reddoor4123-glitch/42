extends SceneTree

# Verification for the human points drum honouring settings.minimum_bid.
#
# The bug (Aug 1 2026): _show_bid_panel() opened `min_points` at a hardcoded 30,
# so raising Minimum Bid in the settings menu changed the auction rules but not
# the wheel the human spins. On a table with minimum_bid = 35 the drum still
# started at 30, and picking 30 was thrown out by Bid.is_valid() at submission —
# tripping the push_error in _on_bid_submitted() that exists precisely to catch
# "the panel offered something illegal".
#
# Two layers, because the drum and the validator failed independently before:
#   1. the drum's value list == the set of points values Bid.is_valid() accepts
#   2. the value the drum lands on by default is itself legal
#
# Extended the same day to cover forced_bid_minimum, which had the same shape:
# game_table.gd told a forced shaker "you must bid at least 42" while
# Bid.is_valid() checked only minimum_bid and let a 30 through, and
# Game.resolve_bidding() built its all-pass forced bid from forced_bid_minimum
# with no clamp, so forced_bid_minimum < minimum_bid manufactured a standing bid
# under the table's own floor. Both now read Bid.points_floor().
#
# EXPECTED on stderr: "ObjectDB instances leaked at exit" (gotcha #10) — this
# starts a real game. Judge the exit code and the results JSON.

const BidScript = preload("res://bid.gd")
const GameSettingsScript = preload("res://game_settings.gd")

const TOUCHED_PATHS := [
	"user://last_used.json",
	"user://display_prefs.json",
	"user://preset_overrides/standard.json",
]
var _snapshot: Dictionary = {}
var _table: Node = null
var _frame := 0
var _results: Array = []
var _failures := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	_results.append({"test": name, "pass": ok, "detail": detail})
	if not ok:
		_failures += 1

func _eq(name: String, got, want) -> void:
	_check(name, got == want, "got %s, want %s" % [got, want])

func _snapshot_user_files() -> void:
	for p in TOUCHED_PATHS:
		var f = FileAccess.open(p, FileAccess.READ)
		_snapshot[p] = null if f == null else f.get_as_text()
		if f: f.close()

func _restore_user_files() -> void:
	var ok := true
	for p in TOUCHED_PATHS:
		var original = _snapshot.get(p, null)
		if original == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
			if FileAccess.file_exists(p): ok = false
		else:
			var f = FileAccess.open(p, FileAccess.WRITE)
			if f:
				f.store_string(original)
				f.close()
	_check("user:// save data restored", ok)

func _points(v: int) -> Bid:
	return BidScript.new(BidScript.Type.POINTS, v, 0)

# Every points value the rule accepts, for comparison against the drum.
func _legal_points(current_high, s: GameSettings) -> Array:
	var out: Array = []
	for v in range(30, 43):
		if BidScript.is_valid(_points(v), current_high, s):
			out.append(v)
	return out

func _drum(t) -> Array:
	return [] if t._pts_picker == null else Array(t._pts_picker.values)

func _initialize() -> void:
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false
	if _frame == 4:
		_snapshot_user_files()
		_test_drum_floor()
		_test_default_selection()
		_test_submission_gate()
		_test_forced_floor_rule()
		_test_forced_drum_and_submission()
		_test_resolve_bidding_clamp()
		return false
	if _frame < 9:
		return false
	_restore_user_files()
	var f = FileAccess.open("res://headless/bid_drum_minimum_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"failures": _failures, "total": _results.size(), "results": _results,
		}, "\t"))
		f.close()
	quit(1 if _failures > 0 else 0)
	return true

func _start_table():
	var t = _table
	t.main_menu_panel.visible = false
	t._on_preset_chosen("standard")
	t._human_bid_position = 1
	t._bid_panel_expanded = false
	t._selected_contract_type = BidScript.Type.MARKS
	return t

# ── Layer 1: the drum's value list ───────────────────────────────────
func _test_drum_floor() -> void:
	var t = _start_table()
	if t.game == null:
		_check("game started for drum test", false)
		return
	var g = t.game

	g.settings.minimum_bid = 30
	g.current_bid = null
	t._show_bid_panel()
	_eq("minimum_bid 30: drum opens at 30", _drum(t), range(30, 43))

	g.settings.minimum_bid = 35
	t._show_bid_panel()
	_eq("minimum_bid 35: drum opens at 35, not 30", _drum(t), range(35, 43))

	g.settings.minimum_bid = 42
	t._show_bid_panel()
	_eq("minimum_bid 42: drum offers only 42", _drum(t), [42])

	# A standing points bid still wins when it is above the floor, and the floor
	# still wins when the standing bid is below it (which the validator forbids,
	# so it can only happen if minimum_bid is raised mid-auction).
	g.settings.minimum_bid = 35
	g.current_bid = _points(38)
	t._show_bid_panel()
	_eq("standing bid above the floor raises the drum", _drum(t), range(39, 43))

	# The drum must agree with the rule across the whole settings range, not
	# merely look plausible at the two values a person would try by hand.
	for m in range(30, 43):
		g.settings.minimum_bid = m
		g.current_bid = null
		t._show_bid_panel()
		_eq("drum matches Bid.is_valid() for minimum_bid=%d" % m,
			_drum(t), _legal_points(null, g.settings))

# ── Layer 2: where the drum lands ────────────────────────────────────
# Offering only legal values is not enough — the value sitting under the
# highlight when the panel appears is what a player taps Bid on without
# scrolling, so it has to be legal too.
func _test_default_selection() -> void:
	var t = _table
	var g = t.game
	for m in range(30, 43):
		g.settings.minimum_bid = m
		g.current_bid = null
		t._show_bid_panel()
		if t._pts_picker == null:
			_check("points drum present for minimum_bid=%d" % m, false)
			continue
		var landed: int = t._pts_picker.get_value()
		_check("default pick legal for minimum_bid=%d" % m,
			BidScript.is_valid(_points(landed), null, g.settings),
			"landed on %d, floor %d" % [landed, m])

	# Default settings must be untouched by the fix: the wheel still opens on 31
	# with 30 visible to its left.
	g.settings.minimum_bid = 30
	t._show_bid_panel()
	_eq("minimum_bid 30: still lands on 31 as before", t._pts_picker.get_value(), 31)

# ── Layer 3: the submission path ─────────────────────────────────────
func _test_submission_gate() -> void:
	var t = _table
	var g = t.game
	g.settings.minimum_bid = 35
	g.current_bid = null
	t.waiting_for_bid = true
	t.human_is_forced = false

	t._on_bid_submitted(_points(30))
	_check("a 30 bid under minimum_bid 35 does not stand", g.current_bid == null,
		"current_bid=%s" % ["null" if g.current_bid == null else g.current_bid.debug_string()])

	g.current_bid = null
	t.waiting_for_bid = true
	t._on_bid_submitted(_points(35))
	_check("a 35 bid under minimum_bid 35 is accepted",
		g.current_bid != null and g.current_bid.value == 35,
		"current_bid=%s" % ["null" if g.current_bid == null else g.current_bid.debug_string()])

# ── forced_bid_minimum: the rule ─────────────────────────────────────
const FORCED := {"is_dealer": true, "all_others_passed": true}
const NOT_FORCED := {"is_dealer": true, "all_others_passed": false}

func _test_forced_floor_rule() -> void:
	var s = GameSettingsScript.standard_42()
	s.allow_forced_bid = true

	s.minimum_bid = 30
	s.forced_bid_minimum = 42
	_eq("forced shaker takes forced_bid_minimum", BidScript.points_floor(s, FORCED), 42)
	_eq("everyone else takes minimum_bid", BidScript.points_floor(s, NOT_FORCED), 30)
	_eq("no context means no forced moment", BidScript.points_floor(s), 30)

	# The clamp itself: forced_bid_minimum UNDER the table floor must not open a
	# hole beneath minimum_bid.
	s.minimum_bid = 38
	s.forced_bid_minimum = 30
	_eq("forced_bid_minimum below minimum_bid clamps up",
		BidScript.points_floor(s, FORCED), 38)

	# Turning the forced bid off removes the floor with it — the shaker may pass,
	# so there is no forced moment to raise anything.
	s.minimum_bid = 30
	s.forced_bid_minimum = 42
	s.allow_forced_bid = false
	_eq("allow_forced_bid off leaves the plain minimum",
		BidScript.points_floor(s, FORCED), 30)

	# And the validator has to actually read it, not just agree in principle.
	s.allow_forced_bid = true
	_check("is_valid rejects 30 from a forced shaker at floor 42",
		not BidScript.is_valid(_points(30), null, s, FORCED))
	_check("is_valid accepts 42 from a forced shaker at floor 42",
		BidScript.is_valid(_points(42), null, s, FORCED))
	_check("is_valid still accepts 30 from a non-forced bidder",
		BidScript.is_valid(_points(30), null, s, NOT_FORCED))
	# Marks and special contracts clear a mark-equivalent of 1.0 and were never
	# subject to a points floor — the forced shaker keeps those routes.
	_check("forced floor does not touch marks bids",
		BidScript.is_valid(BidScript.new(BidScript.Type.MARKS, 1, 0), null, s, FORCED))

# ── forced_bid_minimum: the drum and the submit path ─────────────────
func _test_forced_drum_and_submission() -> void:
	var t = _table
	var g = t.game
	g.settings.allow_forced_bid = true
	g.settings.minimum_bid = 30
	g.settings.forced_bid_minimum = 42

	# The forced moment is shaker + bid position 3 + nothing standing.
	g.shaker = t.human_seat
	t._human_bid_position = 3
	t._bid_panel_expanded = false
	t._selected_contract_type = BidScript.Type.MARKS
	g.current_bid = null
	t._show_bid_panel()
	_eq("forced drum offers only the forced floor", _drum(t), [42])

	# Same seat, same settings, but someone has bid — no longer forced.
	g.current_bid = _points(31)
	t._show_bid_panel()
	_eq("not forced once a bid is standing", _drum(t), range(32, 43))

	# A forced shaker must not slip a 30 past the submit path.
	g.current_bid = null
	t.waiting_for_bid = true
	t.human_is_forced = true
	t._on_bid_submitted(_points(30))
	_check("forced shaker cannot bid under the forced floor", g.current_bid == null,
		"current_bid=%s" % ["null" if g.current_bid == null else g.current_bid.debug_string()])

	# Passing was already blocked and must stay blocked.
	t.waiting_for_bid = true
	t._on_bid_submitted(BidScript.new(BidScript.Type.PASS, 0, t.human_seat))
	_check("forced shaker still cannot pass", g.current_bid == null,
		"current_bid=%s" % ["null" if g.current_bid == null else g.current_bid.debug_string()])

	t.waiting_for_bid = true
	t._on_bid_submitted(_points(42))
	_check("forced shaker bidding the floor is accepted",
		g.current_bid != null and g.current_bid.value == 42,
		"current_bid=%s" % ["null" if g.current_bid == null else g.current_bid.debug_string()])
	t.human_is_forced = false

# ── forced_bid_minimum: the manufactured all-pass bid ────────────────
# resolve_bidding() builds a Bid nobody submitted, so it never passes through
# is_valid() — it has to clamp itself or it produces a contract the rest of the
# game considers illegal.
func _test_resolve_bidding_clamp() -> void:
	var g = _table.game
	g.settings.allow_forced_bid = true

	g.settings.minimum_bid = 38
	g.settings.forced_bid_minimum = 30
	g.current_bid = null
	var made = g.resolve_bidding([])
	_check("all-pass forced bid clamps up to minimum_bid",
		made != null and made.value == 38,
		"got %s" % ["null" if made == null else made.debug_string()])
	_check("and the bid it made is one is_valid() accepts",
		made != null and BidScript.is_valid(made, null, g.settings, FORCED))

	g.settings.minimum_bid = 30
	g.settings.forced_bid_minimum = 42
	g.current_bid = null
	var made42 = g.resolve_bidding([])
	_check("all-pass forced bid honours a raised forced_bid_minimum",
		made42 != null and made42.value == 42,
		"got %s" % ["null" if made42 == null else made42.debug_string()])

	g.settings.allow_forced_bid = false
	g.current_bid = null
	_check("no forced bid manufactured when the rule is off",
		g.resolve_bidding([]) == null)
	g.settings.allow_forced_bid = true
