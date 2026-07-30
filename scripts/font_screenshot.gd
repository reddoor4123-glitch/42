extends SceneTree
# Renders the real UI to PNGs so the typeface work can be judged by eye rather
# than by metrics. Must run WITHOUT --headless (needs a real rasterizer):
#   godot --path . --script res://scripts/font_screenshot.gd -- <out_dir>

func _grab(path: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("  (no image — renderer unavailable)")
		return
	var err := img.save_png(path)
	print("  saved %s (%dx%d) err=%d" % [path, img.get_width(), img.get_height(), err])

func _init():
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://"
	print("output dir: %s" % out_dir)

	root.size = Vector2i(900, 820)

	var table = load("res://control.tscn").instantiate()
	root.add_child(table)
	for i in range(12):
		await process_frame

	print("main menu:")
	await _grab(out_dir + "/01_main_menu.png")

	# A weight-comparison strip, so 400 vs 815 can be judged side by side in
	# the same render rather than across two screenshots.
	var strip := ColorRect.new()
	strip.color = Color(0.10, 0.10, 0.12)
	strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(strip)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 6)
	strip.add_child(col)
	var rows := [
		["Nunito wght 400  —  The National Game of Texas", table._font_nunito_regular, 26],
		["Nunito wght 815  —  The National Game of Texas", table._font_nunito_heavy, 26],
		["Nunito 400  Play / Choose Rules / Difficulty", table._font_nunito_regular, 30],
		["Nunito 815  Play / Choose Rules / Difficulty", table._font_nunito_heavy, 30],
		["Rye  42", table._font_rye, 64],
		["Rye  YOU WIN THIS HAND! 🎉", table._font_rye, 34],
		["Nunito 815  ▶ BIDDING  ▼ TRUMP & DOUBLES", table._font_nunito_heavy, 22],
		["fallback glyphs: ● ⚙ ✕ ⌂ ★ ← → ✓ … 🚩 🎉", table._font_nunito_regular, 24],
	]
	for r in rows:
		var l := Label.new()
		l.text = r[0]
		l.add_theme_font_override("font", r[1])
		l.add_theme_font_size_override("font_size", r[2])
		l.add_theme_color_override("font_color", Color(0.96, 0.95, 0.92))
		col.add_child(l)
	print("weight comparison strip:")
	await _grab(out_dir + "/02_weights.png")
	strip.queue_free()
	await process_frame

	# The diamond, with a full trick on the table.
	table.main_menu_panel.visible = false
	table._on_preset_chosen("standard")
	var waited := 0
	while (table.game == null or table.play_area_container.size.x <= 0.0) and waited < 600:
		await process_frame
		waited += 1
	table._clear_play_area()
	await process_frame
	for pid in range(4):
		table._add_to_play_area(pid, table.game.players[pid].hand[0])
	print("diamond trick layout:")
	await _grab(out_dir + "/03_diamond.png")

	quit(0)
