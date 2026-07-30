extends SceneTree

# UI smoke probe for the Menu / Rules / Settings merge. --check-only catches
# syntax; this catches the things it can't: a container property that doesn't
# exist, a signal bound to a renamed handler, a rebuild that throws halfway
# through. Drives every screen this feature restructured and reports node counts,
# so an empty-but-not-crashing panel shows up as a failure too.
#
# Structure note: the checks CANNOT run from _init(). Adding the scene to the
# root there leaves it un-readied — get_viewport() returns null and every UI
# member is still null, which reads as a pile of confusing nil errors rather
# than "you looked too early". _initialize() builds it, then _process() waits a
# frame for _ready() to have run before touching anything.
#
# Any engine error/warning goes to stderr — treat non-empty stderr as failure
# regardless of exit code.

var _table: Node = null
var _frame := 0
var _log: Array = []

# user:// in a headless run IS the live save directory (see
# Headless_Harness_Reference.md gotcha #9). This probe deletes last_used.json to
# exercise the first-launch route, which would take Profiles' seat_assignments
# with it — snapshot and put everything back.
const TOUCHED_PATHS := [
	"user://last_used.json",
	"user://slot_names.json",
	"user://display_prefs.json",
	"user://preset_overrides/teel.json",
	"user://custom_rulesets/Custom.json",
]
var _snapshot: Dictionary = {}

func _note(what: String, detail: String) -> void:
	_log.append({"step": what, "detail": detail})

func _snapshot_user_files() -> void:
	for path in TOUCHED_PATHS:
		var f = FileAccess.open(path, FileAccess.READ)
		if f == null:
			_snapshot[path] = null
		else:
			_snapshot[path] = f.get_as_text()
			f.close()

func _restore_user_files() -> void:
	var ok := true
	for path in TOUCHED_PATHS:
		var original = _snapshot.get(path, null)
		if original == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if FileAccess.file_exists(path):
				ok = false
		else:
			var f = FileAccess.open(path, FileAccess.WRITE)
			if f:
				f.store_string(original)
				f.close()
			var v = FileAccess.open(path, FileAccess.READ)
			if v == null or v.get_as_text() != original:
				ok = false
			if v:
				v.close()
	_note("user_data_restored", "ok" if ok else "MISMATCH — check your save data")

func _initialize() -> void:
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

func _process(_delta: float) -> bool:
	_frame += 1
	# Phase 1 — let _ready()/_build_ui() complete first.
	if _frame < 3:
		return false
	# Phase 2 — drive every screen, and leave the reset popup open for phase 4.
	if _frame == 3:
		_snapshot_user_files()
		_run_checks()
		return false
	# Phase 3 — idle. Godot lays containers out and processes queue_free() at
	# frame boundaries, so anything asking "where is this control" or "did that
	# get freed" has to wait. Checking in phase 2 reported every row of the reset
	# popup at y=0 (overlapping) and counted already-freed menus as still open.
	if _frame < 6:
		return false
	# Phase 4 — the checks that need real layout and completed frees.
	_note("reset_popup_laid_out", _describe_reset_popup())
	_note("menus_freed_after_frames", "open_count=%d (expected 0)" % _count_menu_holders())
	_restore_user_files()
	var f = FileAccess.open("res://scripts/menu_merge_ui_probe_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"steps": _log}, "\t"))
		f.close()
	return true        # quit the main loop

func _count(node: Node) -> int:
	if node == null:
		return -1
	return node.get_child_count()

# The "…" Button on the row for `key`, found the way the player reaches it.
func _find_options_button(key: String) -> Button:
	var idx: int = Array(_table.SLOT_KEYS).find(key)
	var row: Node = _table._preset_btn_container.get_child(idx)
	for c in row.get_children():
		if c is Button and c.text == "…":
			return c
	return null

# Labels of the entries in the currently-open "…" menu, top to bottom.
func _menu_entries() -> Array:
	var out: Array = []
	if _table._slot_menu_popup == null:
		return out
	var stack: Array = [_table._slot_menu_popup]
	while not stack.is_empty():
		var n: Node = stack.pop_front()
		if n is Button:
			out.append(n.text)
		for c in n.get_children():
			stack.append(c)
	return out

# How many "…" menus are parented to preset_panel — should never exceed 1.
func _count_menu_holders() -> int:
	var n := 0
	for c in _table.preset_panel.get_children():
		# Skip nodes already condemned — queue_free() doesn't take effect until
		# the end of the frame, so within one frame a closed menu is still a child.
		if c.is_queued_for_deletion():
			continue
		# The menu is a top-level PanelContainer (top-level so PanelContainer's
		# layout skips it and its position stays global).
		if c is PanelContainer and c.is_set_as_top_level():
			n += 1
	return n

# Vertical bands of the reset popup's rows. Overlapping bands is exactly the
# ConfirmationDialog bug this popup replaced, so report them for inspection.
func _describe_reset_popup() -> String:
	var popup: Node = _table.preset_panel.get_child(_table.preset_panel.get_child_count() - 1)
	var rows: Array = []
	var vb: Node = null
	var stack: Array = [popup]
	while not stack.is_empty():
		var n: Node = stack.pop_front()
		if n is VBoxContainer:
			vb = n
			break
		for c in n.get_children():
			stack.append(c)
	if vb == null:
		return "NO VBOX FOUND"
	var overlap := false
	var prev_bottom := -1.0
	for c in vb.get_children():
		var r: Control = c
		var top := r.position.y
		var bot := r.position.y + r.size.y
		rows.append("%s[%.0f-%.0f]" % [r.get_class(), top, bot])
		if prev_bottom >= 0.0 and top < prev_bottom:
			overlap = true
		prev_bottom = bot
	return "rows=%s overlap=%s (expected false)" % [rows, overlap]

func _run_checks() -> void:
	var table = _table
	_note("ready_ran", "settings_panel=%s viewport=%s"
		% ["built" if table.settings_panel != null else "NULL",
		   "ok" if table.get_viewport() != null else "NULL"])

	# Settings screen, opened the way the gear icon opens it (no game running).
	table._show_settings_panel()
	_note("show_settings_panel", "visible=%s content_children=%d"
		% [table.settings_panel.visible, _count(table._settings_content_vbox)])

	# Every slot button, in sequence — the rebuild runs fully each time.
	for key in table.SLOT_KEYS:
		table._on_settings_slot_pressed(key)
		_note("slot_pressed:%s" % key, "preset_id=%s content_children=%d name='%s'"
			% [table._pending_settings.preset_id,
			   _count(table._settings_content_vbox),
			   table._slot_display_name(key)])

	# Reset dialog, including the added "Also reset the name" checkbox.
	table._on_settings_slot_pressed("teel")
	table._on_reset_to_default_pressed()
	_note("reset_dialog", "opened without error")

	# Domino back buttons.
	for entry in table.DOMINO_BACKS:
		table._on_domino_back_pressed(str(entry[1]))
		_note("domino_back:%s" % str(entry[0]),
			"pref='%s' texture=%s" % [table._load_domino_back_pref(),
				"set" if DominoTile.custom_back_texture != null else "null"])

	# Choose Rules screen — expect one row per slot.
	table._rebuild_preset_buttons()
	_note("rebuild_preset_buttons", "rows=%d (expected %d)"
		% [_count(table._preset_btn_container), table.SLOT_KEYS.size()])

	# Rename popup per slot, dismissed the way its own Cancel does.
	for key in table.SLOT_KEYS:
		table._show_slot_rename_popup(key)
		var kids: int = table.preset_panel.get_child_count()
		table.preset_panel.get_child(kids - 1).queue_free()
		_note("rename_popup:%s" % key, "built, panel_children=%d" % kids)

	# ── "…" options menu: contents, toggle behaviour, and cleanup ────────────
	table._rebuild_preset_buttons()
	for key in table.SLOT_KEYS:
		var opts: Button = _find_options_button(key)
		table._on_slot_options_pressed(key, opts)
		var entries := _menu_entries()
		# Reset only where there's a shipped default to go back to.
		var expect := ["Rename", "Reset"] if table.BUILTIN_PRESET_KEYS.has(key) else ["Rename"]
		_note("options_menu:%s" % key, "entries=%s expected=%s open=%s"
			% [entries, expect, table._slot_menu_popup != null])
		# Same button again must collapse it with no choice made.
		table._on_slot_options_pressed(key, opts)
		_note("options_menu_toggle:%s" % key, "closed=%s (expected true)"
			% [table._slot_menu_popup == null])

	# Opening one slot's menu then another's must move it, not stack two.
	var b0: Button = _find_options_button(table.SLOT_KEYS[0])
	var b1: Button = _find_options_button(table.SLOT_KEYS[1])
	table._on_slot_options_pressed(table.SLOT_KEYS[0], b0)
	table._on_slot_options_pressed(table.SLOT_KEYS[1], b1)
	_note("options_menu_switch", "key=%s open_count=%d (expected 1)"
		% [table._slot_menu_key, _count_menu_holders()])

	# A menu left open must not survive a rebuild or a slot being chosen —
	# it floats on preset_panel, outside the container that gets cleared.
	table._rebuild_preset_buttons()
	_note("options_menu_cleared_by_rebuild", "open_count=%d (expected 0)"
		% _count_menu_holders())

	# ── Reset confirmation popup: real layout, no overlapping text ───────────
	# This is what the ConfirmationDialog got wrong — the checkbox drew on top of
	# the message. Assert the rows actually occupy separate vertical bands.
	table._rebuild_preset_buttons()
	table._show_reset_confirm_popup("teel", table.preset_panel, func(): pass)
	_note("reset_popup", _describe_reset_popup())

	# Difficulty screen — expect exactly two tiers now.
	table._rebuild_difficulty_buttons()
	_note("rebuild_difficulty_buttons", "buttons=%d (expected 2)"
		% _count(table._difficulty_btn_container))

	# Profiles screen — untouched by this feature, but it shares last_used.json,
	# so prove it still builds after everything above wrote to that file.
	table._rebuild_profile_panel()
	_note("rebuild_profile_panel", "rows=%d" % _count(table._profile_content_vbox))

	# First-launch routing: no saved rules -> both Play and Choose Rules land on
	# Settings rather than the picker.
	if FileAccess.file_exists("user://last_used.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://last_used.json"))
	table.settings_panel.visible = false
	table.preset_panel.visible = false
	table._on_menu_play_pressed()
	_note("first_launch_play", "settings=%s preset=%s (expected true/false)"
		% [table.settings_panel.visible, table.preset_panel.visible])

	table.settings_panel.visible = false
	table._on_menu_rules_pressed()
	_note("first_launch_choose_rules", "settings=%s preset=%s (expected true/false)"
		% [table.settings_panel.visible, table.preset_panel.visible])

	# Returning player: Choose Rules opens the picker instead.
	table._save_last_used("lechner")
	table.settings_panel.visible = false
	table.preset_panel.visible = false
	table._on_menu_rules_pressed()
	_note("returning_choose_rules", "settings=%s preset=%s (expected false/true)"
		% [table.settings_panel.visible, table.preset_panel.visible])
