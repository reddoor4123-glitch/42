extends SceneTree
# Two questions in one run:
#  1. When the human's bid panel opens, does the main VBoxContainer's combined
#     minimum height exceed the viewport and push the player's own hand off the
#     bottom of the screen?
#  2. Do the in-game table Labels ("Your turn to bid", "Your Bid:", the points
#     readout) actually resolve to Nunito through the root Theme?
# Run WITHOUT --headless (both answers depend on real text metrics):
#   godot --path . --script res://scripts/ui_bid_panel_fit_probe.gd

func _font_id(f) -> String:
	if f == null:
		return "<null>"
	if f is FontVariation:
		var base = f.base_font
		var nm = base.get_font_name() if base != null else "?"
		var wght = "-"
		for k in f.variation_opentype:
			wght = str(f.variation_opentype[k])
		return "%s wght=%s fallbacks=%d" % [nm, wght, f.fallbacks.size()]
	if f is FontFile:
		return "%s (bare FontFile)" % f.get_font_name()
	return f.get_class()

func _init():
	root.size = Vector2i(1152, 800)
	var table = load("res://control.tscn").instantiate()
	root.add_child(table)
	for i in range(10):
		await process_frame
	table._on_preset_chosen("teel")

	# Bidding is a real-time sequence (1.0s per AI seat); spin frames until the
	# human's own turn comes up rather than guessing a frame count.
	var waited := 0
	while not table.bid_panel.visible and waited < 3000:
		await process_frame
		waited += 1
	print("bid panel visible after %d frames: %s" % [waited, str(table.bid_panel.visible)])
	for i in range(8):
		await process_frame

	var vp: Vector2 = root.get_visible_rect().size
	var vbox: VBoxContainer = table._game_top_row.get_parent()
	print("")
	print("viewport %.0fx%.0f | vbox combined min height = %.1f" % [
		vp.x, vp.y, vbox.get_combined_minimum_size().y])
	print("=== vbox children (top to bottom) ===")
	var total_min := 0.0
	for c in vbox.get_children():
		if not (c is Control):
			continue
		var r: Rect2 = c.get_global_rect()
		var m: Vector2 = c.get_combined_minimum_size()
		if c.visible:
			total_min += m.y
		print("  %-22s vis=%-5s y=%7.1f..%7.1f  h=%6.1f  min_h=%6.1f  vflags=%d" % [
			c.get_class() + ("/" + c.name if c.name != c.get_class() else ""),
			str(c.visible), r.position.y, r.end.y, r.size.y, m.y, c.size_flags_vertical])
	print("  sum of visible min heights = %.1f  (viewport height %.0f)" % [total_min, vp.y])

	var hand: Rect2 = table.player_hand_container.get_global_rect()
	print("")
	print("player hand: y=%.1f..%.1f  (viewport bottom %.0f)" % [hand.position.y, hand.end.y, vp.y])
	var off: float = hand.end.y - vp.y
	if off > 0.5:
		print("FAIL: player's hand runs %.1f px past the bottom of the screen" % off)
	else:
		print("PASS: player's hand is fully on screen")

	# Play-area internals, to see what is actually claiming the height.
	print("")
	print("=== play area internals ===")
	for c in table.play_vbox.get_children():
		if not (c is Control) or not c.visible:
			continue
		var r2: Rect2 = c.get_global_rect()
		print("  %-24s y=%7.1f..%7.1f  h=%6.1f  min_h=%6.1f" % [
			c.get_class(), r2.position.y, r2.end.y, r2.size.y, c.get_combined_minimum_size().y])

	print("")
	print("=== TABLE TEXT FONTS (resolved through the theme chain) ===")
	var named := {
		"info_label (points readout)": table.info_label,
		"status_label (Your turn to bid)": table.status_label,
		"trump_indicator_label": table.trump_indicator_label,
		"bid_reminder_label": table.bid_reminder_label,
	}
	for k in named:
		var n: Label = named[k]
		print("  %-34s override=%-5s font=%s" % [
			k, str(n.has_theme_font_override("font")), _font_id(n.get_theme_font("font"))])

	# Everything inside the bid panel, by text, so "Your Bid:" and the button
	# faces are checked as the player sees them.
	var found: Array = []
	_collect(table.bid_panel, found)
	for n in found:
		print("  %-34s override=%-5s font=%s" % [
			"\"%s\"" % n.text.substr(0, 24), str(n.has_theme_font_override("font")),
			_font_id(n.get_theme_font("font"))])

	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var img: Image = root.get_texture().get_image()
		if img != null:
			img.save_png(args[0] + "/bid_panel_fit.png")
			print("saved %s/bid_panel_fit.png" % args[0])

	quit(0)

func _collect(n: Node, out: Array) -> void:
	if (n is Label or n is Button) and not n.text.is_empty():
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
