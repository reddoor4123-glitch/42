extends SceneTree

# Regression suite for tap-outside / gear-toggle dismissal of the Settings screen.
#
# Pushes real InputEventMouseButtons through the viewport rather than calling the
# handler directly, because the whole design rests on a routing assumption that a
# direct call would not exercise: the centring container is MOUSE_FILTER_PASS, so
# clicks on empty space forward up to settings_panel, while _settings_panel_inner
# is MOUSE_FILTER_STOP and absorbs clicks on the dialog. Reaching the handler is
# itself the test for "outside" — if that routing ever changes, the dismiss either
# stops firing or starts firing on the dialog, and only pushed input catches it.
#
# The "inside" click deliberately lands in the dialog's own 12px margin rather
# than its centre, so it proves non-dismissal without activating a real widget.
#
# Snapshots and restores user:// (see Headless_Harness_Reference.md gotcha #9).
#
# EXPECTED on stderr: "ObjectDB instances leaked at exit" — starts a real game
# whose bidding coroutine is parked on a timer at exit. Judge the JSON.

const TOUCHED_PATHS := [
	"user://last_used.json",
	"user://display_prefs.json",
	"user://preset_overrides/teel.json",
	"user://slot_names.json",
	"user://custom_rulesets/Custom.json",
]
var _snapshot: Dictionary = {}
var _table: Node = null
var _frame := 0
var _results: Array = []
var _failures := 0
# Steps run two frames apart. CenterContainer sorts deferred, so the dialog's
# global rect is meaningless on the frame it was shown — measured that early it
# reads (0,0) at full size, and a point computed from it lands INSIDE the dialog.
var _steps: Array = []
var _next_step_frame := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	_results.append({"test": name, "pass": ok, "detail": detail})
	if not ok:
		_failures += 1

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

func _initialize() -> void:
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

# in_local_coords MUST be true. The project stretches canvas_items, so the root
# viewport carries a content-scale transform (~1/18 headless) that push_input
# would otherwise apply to these coordinates — the click then lands nowhere near
# the intended point and silently hits nothing at all.
func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		get_root().push_input(ev, true)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false
	if _frame == 4:
		_snapshot_user_files()
		_steps = [_step_open, _step_outside, _step_inside_and_toggles]
		_next_step_frame = _frame
	if not _steps.is_empty():
		if _frame >= _next_step_frame:
			var step: Callable = _steps.pop_front()
			step.call()
			_next_step_frame = _frame + 2
		return false
	if _frame < _next_step_frame:
		return false
	_restore_user_files()
	var f = FileAccess.open("res://headless/settings_dismiss_verify_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"failures": _failures, "total": _results.size(), "results": _results,
		}, "\t"))
		f.close()
	quit(1 if _failures > 0 else 0)
	return true

func _step_open() -> void:
	var t = _table
	t.main_menu_panel.visible = false
	t._on_preset_chosen("teel")
	_check("game started", t.game != null)
	# Opened via _show_settings_panel() rather than the gear on purpose: this one
	# exists both before and after the change, so the outside-click check below
	# still runs when the suite is pointed at pre-fix code. Gear toggling is
	# asserted in its own section further down.
	t._show_settings_panel()
	_check("the settings screen opens", t.settings_panel.visible)

# ── 1. Click outside the dialog dismisses ───────────────────────────────────
func _step_outside() -> void:
	var t = _table
	var vp = get_root().get_visible_rect().size
	var inner = t._settings_panel_inner.get_global_rect()
	# The dialog is sized to 92% of the viewport, so a margin must exist for
	# "outside" to be reachable at all. If this ever fails the feature is
	# unusable regardless of how the handler is wired.
	_check("a clickable region exists outside the dialog",
		inner.position.y > 2.0 or inner.position.x > 2.0,
		"inner=%s viewport=%s" % [str(inner), str(vp)])

	var outside := Vector2(inner.position.x + inner.size.x * 0.5,
		max(1.0, inner.position.y * 0.5))
	_click(outside)
	_check("click outside the dialog dismisses it",
		not t.settings_panel.visible, "clicked=%s inner=%s" % [str(outside), str(inner)])
	t._show_settings_panel()

# ── 2. Clicks on the dialog do NOT dismiss, and the gear toggles ────────────
func _step_inside_and_toggles() -> void:
	var t = _table
	var inner = t._settings_panel_inner.get_global_rect()
	# Inside the panel but within its own 12px margin, so no real widget is hit.
	var inside: Vector2 = inner.position + Vector2(3, 3)
	_click(inside)
	_check("click on the dialog does not dismiss it",
		t.settings_panel.visible, "clicked=%s inner=%s" % [str(inside), str(inner)])

	# A click deeper into the content must not dismiss either.
	var inside_content: Vector2 = inner.position + Vector2(inner.size.x * 0.5, 6)
	_click(inside_content)
	_check("click inside the dialog body does not dismiss it",
		t.settings_panel.visible, "clicked=%s" % str(inside_content))

	# ── 3. The gear toggles ──────────────────────────────────────────────────
	_check("settings still open before toggle test", t.settings_panel.visible)
	t._on_gear_pressed()
	_check("gear closes an open settings screen", not t.settings_panel.visible)
	t._on_gear_pressed()
	_check("gear reopens a closed settings screen", t.settings_panel.visible)

	# ── 4. Cancel still works, and shares the one close path ─────────────────
	t._close_settings_panel()
	_check("close helper hides the screen", not t.settings_panel.visible)

	# ── 5. Reopening rebuilds pending settings ───────────────────────────────
	# Dismissing abandons _pending_settings rather than committing it; the next
	# open must not inherit anything from the abandoned visit.
	t._show_settings_panel()
	t._pending_settings.minimum_bid = 41
	t._close_settings_panel()
	t._show_settings_panel()
	_check("a dismissed edit does not survive reopening",
		t._pending_settings.minimum_bid != 41,
		"minimum_bid=%d" % t._pending_settings.minimum_bid)
	_check("game settings untouched by the abandoned edit",
		t.game.settings.minimum_bid != 41,
		"minimum_bid=%d" % t.game.settings.minimum_bid)
	t._close_settings_panel()
