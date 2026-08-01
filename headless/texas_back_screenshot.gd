extends SceneTree
# Renders the Texas domino back so it can be judged by eye at the size it is
# actually played at — the art is authored at 437x914 but drawn into a ~58x122
# rect, and nothing about how it reads there is visible in the source PNG.
#
# Must run WITHOUT --headless (needs a real rasterizer) — same constraint as
# headless/menu_merge_screenshot.gd:
#   godot --path . --script res://headless/texas_back_screenshot.gd -- <out_dir>
#
# Touches user://display_prefs.json (selects a back). Snapshots and restores.

const TOUCHED_PATHS := ["user://display_prefs.json", "user://last_used.json"]
const TEXAS := "res://art/domino_back_texas.png"

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

	# ── 1. The table, once per back ──────────────────────────────────────────
	# All of them rather than just the flag: how a back reads at the size it is
	# actually played at is the only question worth asking of it, and the side
	# hands overlap so only the top of each tile shows there. A back that looks
	# fine at 437x914 can be mush at 58x122.
	table._on_domino_back_pressed(TEXAS)
	table.main_menu_panel.visible = false
	table._on_preset_chosen("standard")
	for i in range(20):
		await process_frame
	for entry in table.DOMINO_BACKS:
		var res_path := str(entry[1])
		if res_path.is_empty():
			continue
		table._on_domino_back_pressed(res_path)
		for i in range(6):
			await process_frame
		var slug := res_path.get_file().get_basename().replace("domino_back_", "")
		print("table with the %s back:" % str(entry[0]))
		await _grab(out_dir + "/01_table_" + slug + ".png")
	table._on_domino_back_pressed(TEXAS)
	for i in range(4):
		await process_frame

	# ── 2. The Settings picker, all three swatches side by side ──────────────
	table._show_settings_panel()
	for i in range(8):
		await process_frame
	# The back row is the last thing on the form, so scroll to it.
	for n in table.settings_panel.find_children("*", "ScrollContainer", true, false):
		n.scroll_vertical = int(n.get_v_scroll_bar().max_value)
	for i in range(6):
		await process_frame
	print("settings back picker:")
	await _grab(out_dir + "/02_back_picker.png")

	_restore()
	quit(0)
