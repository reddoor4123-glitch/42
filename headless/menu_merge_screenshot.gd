extends SceneTree
# Renders the reset popup and the Choose Rules "…" menu so they can be judged by
# eye. Must run WITHOUT --headless (needs a real rasterizer) — same constraint as
# scripts/font_screenshot.gd:
#   godot --path . --script res://headless/menu_merge_screenshot.gd -- <out_dir>
#
# Touches user:// (opening Choose Rules reads it; the reset popup can delete a
# ruleset file if Reset is ever pressed here — it isn't). Snapshots and restores
# regardless; see Headless_Harness_Reference.md gotcha #9.

const TOUCHED_PATHS := [
	"user://last_used.json",
	"user://slot_names.json",
	"user://display_prefs.json",
	"user://preset_overrides/teel.json",
	"user://custom_rulesets/Custom.json",
]
var _snapshot: Dictionary = {}

func _snap() -> void:
	for p in TOUCHED_PATHS:
		var f = FileAccess.open(p, FileAccess.READ)
		_snapshot[p] = null if f == null else f.get_as_text()
		if f: f.close()

func _restore() -> void:
	for p in TOUCHED_PATHS:
		var original = _snapshot.get(p, null)
		if original == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var f = FileAccess.open(p, FileAccess.WRITE)
			if f:
				f.store_string(original)
				f.close()
	print("user:// restored")

func _grab(path: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("  (no image — renderer unavailable; are you running with --headless?)")
		return
	var err := img.save_png(path)
	print("  saved %s (%dx%d) err=%d" % [path, img.get_width(), img.get_height(), err])

func _options_button(table, key: String) -> Button:
	var idx: int = Array(table.SLOT_KEYS).find(key)
	var row: Node = table._preset_btn_container.get_child(idx)
	for c in row.get_children():
		if c is Button and c.text == "…":
			return c
	return null

func _init():
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://"
	print("output dir: %s" % out_dir)
	_snap()

	root.size = Vector2i(1160, 820)
	var table = load("res://control.tscn").instantiate()
	root.add_child(table)
	for i in range(12):
		await process_frame

	# ── 1. Settings screen with the reset popup open ─────────────────────────
	# Give the slot a long custom name so the popup title has to wrap/fit.
	table._set_slot_display_name("teel", "Teel Rules")
	table._show_settings_panel()
	table._on_settings_slot_pressed("teel")
	for i in range(6):
		await process_frame
	table._on_reset_to_default_pressed()
	# Tick it so the screenshot shows the indicator in its checked state too.
	for c in table.settings_panel.get_children():
		if not (c is Container) and not (c is ColorRect):
			for n in c.find_children("*", "CheckBox", true, false):
				n.button_pressed = true
	print("settings + reset popup:")
	await _grab(out_dir + "/01_reset_popup.png")

	# Clear it and leave Settings.
	for c in table.settings_panel.get_children():
		if not (c is Container) and not (c is ColorRect):
			c.queue_free()
	table.settings_panel.visible = false
	for i in range(4):
		await process_frame

	# ── 2. Choose Rules with a built-in slot's "…" menu open ─────────────────
	table.main_menu_panel.visible = false
	table._save_last_used("lechner")
	table._rebuild_preset_buttons()
	table.preset_panel.visible = true
	for i in range(8):
		await process_frame     # let rows lay out so the anchor rect is real
	var b = _options_button(table, "teel")
	table._on_slot_options_pressed("teel", b)
	print("choose rules + options menu (built-in: Rename + Reset):")
	await _grab(out_dir + "/02_options_menu_builtin.png")

	# ── 3. Same for Custom, which should offer Rename only ───────────────────
	var bc = _options_button(table, table.CUSTOM_SLOT_KEY)
	table._on_slot_options_pressed(table.CUSTOM_SLOT_KEY, bc)
	for i in range(2):
		await process_frame
	print("choose rules + options menu (Custom: Rename only):")
	await _grab(out_dir + "/03_options_menu_custom.png")

	# ── 4. Reset popup raised from Choose Rules ──────────────────────────────
	table._close_slot_options_menu()
	table._show_reset_confirm_popup("teel", table.preset_panel, func(): pass)
	print("choose rules + reset popup:")
	await _grab(out_dir + "/04_reset_from_choose_rules.png")

	_restore()
	quit(0)
