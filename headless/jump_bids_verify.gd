extends SceneTree

# Verification suite for the jump-bid rule, written against the behaviour
# jump_bids_trace.gd found missing.
#
# The rule (Katy, July 30 2026):
#   * jump bids ON  — any marks value is legal at any point, including opening
#     at 4 marks.
#   * jump bids OFF — an opening marks bid is capped at max_open_bid_marks
#     (normally 2); a raise may go exactly one mark above what is standing. A
#     points bid is worth a fraction of a mark, so the first marks bid over one
#     is still an "opening" bid and takes the opening cap.
#   * Plunge and Splash are exempt: they keep their own minimums and may sit
#     above the cap.
#
# Covers all three layers the trace found broken independently — the rule, the
# human drum, and the submission path — because each failed on its own.
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

func _settings(jump: bool) -> GameSettings:
	var s = GameSettingsScript.standard_42()
	s.allow_jump_bids = jump
	s.max_open_bid_marks = 2
	s.allow_plunge = true
	s.plunge_minimum_bid_marks = 4
	s.plunge_minimum_doubles = 4
	s.allow_splash = true
	s.splash_bid_marks = 2
	s.splash_minimum_doubles = 3
	return s

func _marks(v: int) -> Bid:
	return BidScript.new(BidScript.Type.MARKS, v, 0)

func _legal_marks(current_high, s: GameSettings) -> Array:
	var out: Array = []
	for v in range(1, 8):
		if BidScript.is_valid(_marks(v), current_high, s):
			out.append(v)
	return out

func _initialize() -> void:
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false
	if _frame == 4:
		_snapshot_user_files()
		_test_rule()
		_test_panel()
		_test_submission_gate()
		return false
	if _frame < 9:
		return false
	_restore_user_files()
	var f = FileAccess.open("res://headless/jump_bids_verify_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"failures": _failures, "total": _results.size(), "results": _results,
		}, "\t"))
		f.close()
	quit(1 if _failures > 0 else 0)
	return true

# ── Layer 1: the rule ────────────────────────────────────────────────
func _test_rule() -> void:
	var off = _settings(false)
	var on = _settings(true)

	_eq("OFF: opening capped at max_open_bid_marks", _legal_marks(null, off), [1, 2])
	_eq("OFF: over 1 mark, only 2", _legal_marks(_marks(1), off), [2])
	_eq("OFF: over 2 marks, only 3", _legal_marks(_marks(2), off), [3])
	_eq("OFF: over 6 marks, only 7", _legal_marks(_marks(6), off), [7])
	_eq("OFF: over 7 marks, nothing", _legal_marks(_marks(7), off), [])

	# The gap the trace found: a points bid is worth <1 mark, so the first marks
	# bid over one is still an opening bid.
	var pts = BidScript.new(BidScript.Type.POINTS, 35, 1)
	_eq("OFF: over a 35-point bid, still the opening cap", _legal_marks(pts, off), [1, 2])
	var pts42 = BidScript.new(BidScript.Type.POINTS, 42, 1)
	_eq("OFF: over a 42-point bid, still the opening cap", _legal_marks(pts42, off), [1, 2])

	_eq("ON: opening unrestricted", _legal_marks(null, on), [1, 2, 3, 4, 5, 6, 7])
	_eq("ON: over 2 marks, anything higher", _legal_marks(_marks(2), on), [3, 4, 5, 6, 7])
	_eq("ON: over a points bid, anything", _legal_marks(pts, on), [1, 2, 3, 4, 5, 6, 7])

	# A different opening cap must actually be honoured, not just the default 2.
	var off3 = _settings(false)
	off3.max_open_bid_marks = 3
	_eq("OFF: max_open_bid_marks=3 respected", _legal_marks(null, off3), [1, 2, 3])

	# Special contracts keep their own minimums above the cap.
	var ctx := {"hand_doubles_count": 4}
	_check("OFF: Plunge 4 legal over a 1-mark bid",
		BidScript.is_valid(BidScript.new(BidScript.Type.PLUNGE, 4, 0), _marks(1), off, ctx))
	_check("OFF: Plunge 4 legal as an opening bid",
		BidScript.is_valid(BidScript.new(BidScript.Type.PLUNGE, 4, 0), null, off, ctx))
	_check("OFF: Splash 2 legal as an opening bid",
		BidScript.is_valid(BidScript.new(BidScript.Type.SPLASH, 2, 0), null, off, ctx))
	_check("OFF: Plunge below its minimum still rejected",
		not BidScript.is_valid(BidScript.new(BidScript.Type.PLUNGE, 3, 0), null, off, ctx))

# ── Layer 2: the human drum ──────────────────────────────────────────
func _test_panel() -> void:
	var t = _table
	t.main_menu_panel.visible = false
	t._on_preset_chosen("standard")
	if t.game == null:
		_check("game started for panel test", false)
		return
	t._human_bid_position = 1
	t._bid_panel_expanded = false
	t._selected_contract_type = BidScript.Type.MARKS

	var g = t.game
	g.settings.max_open_bid_marks = 2

	g.settings.allow_jump_bids = false
	g.current_bid = null
	t._show_bid_panel()
	_eq("drum OFF: opening offers only the legal values", _drum(t), [1, 2])

	g.current_bid = _marks(2)
	t._show_bid_panel()
	_eq("drum OFF: over 2 marks offers only 3", _drum(t), [3])

	g.current_bid = BidScript.new(BidScript.Type.POINTS, 35, 1)
	t._show_bid_panel()
	_eq("drum OFF: over a points bid uses the opening cap", _drum(t), [1, 2])

	g.current_bid = _marks(7)
	t._show_bid_panel()
	_check("drum OFF: no marks drum at all over 7 marks", t._marks_picker == null,
		"drum offered %s" % [_drum(t)])

	g.settings.allow_jump_bids = true
	g.current_bid = null
	t._show_bid_panel()
	_eq("drum ON: opening offers everything", _drum(t), [1, 2, 3, 4, 5, 6, 7])
	g.current_bid = _marks(2)
	t._show_bid_panel()
	_eq("drum ON: over 2 marks offers everything above", _drum(t), [3, 4, 5, 6, 7])

	# The drum must agree with the rule, not merely look plausible.
	g.settings.allow_jump_bids = false
	for high in [null, _marks(1), _marks(3), BidScript.new(BidScript.Type.POINTS, 31, 1)]:
		g.current_bid = high
		t._show_bid_panel()
		_eq("drum matches Bid.is_valid() for high=%s"
			% ["none" if high == null else high.debug_string()],
			_drum(t), _legal_marks(high, g.settings))

func _drum(t) -> Array:
	return [] if t._marks_picker == null else Array(t._marks_picker.values)

# ── Layer 3: the submission path ─────────────────────────────────────
# The rule was correct all along and simply never ran, so the fix has to be
# proven on the path a real bid takes, not just in the validator.
func _test_submission_gate() -> void:
	var t = _table
	var g = t.game
	g.settings.allow_jump_bids = false
	g.settings.max_open_bid_marks = 2
	g.current_bid = null
	t.waiting_for_bid = true
	t.human_is_forced = false

	# An illegal bid handed straight to the submit handler must not stand.
	t._on_bid_submitted(_marks(7))
	_check("illegal bid rejected at submission", g.current_bid == null,
		"current_bid=%s" % ["null" if g.current_bid == null else g.current_bid.debug_string()])

	# A legal one still goes through.
	g.current_bid = null
	t.waiting_for_bid = true
	t._on_bid_submitted(_marks(2))
	_check("legal bid still accepted",
		g.current_bid != null and g.current_bid.value == 2,
		"current_bid=%s" % ["null" if g.current_bid == null else g.current_bid.debug_string()])
