extends SceneTree
# Prints the live global_rect of every landmark Control in the game board and
# saves a PNG, so UI-placement work is done against measured geometry instead
# of eyeballed screenshot pixels. Must run WITHOUT --headless (the dummy text
# server reports zero string sizes, which skews every Label's width):
#   godot --path . --script res://headless/ui_layout_probe.gd -- <out_dir>

func _rect(label: String, n) -> void:
	if n == null or not is_instance_valid(n):
		print("  %-26s <missing>" % label)
		return
	var r: Rect2 = n.get_global_rect()
	print("  %-26s x=%6.1f..%6.1f  y=%6.1f..%6.1f  (w=%5.1f h=%5.1f)" % [
		label, r.position.x, r.end.x, r.position.y, r.end.y, r.size.x, r.size.y])

func _init():
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://"

	root.size = Vector2i(1200, 800)

	var table = load("res://control.tscn").instantiate()
	root.add_child(table)
	for i in range(10):
		await process_frame

	# _start_game() only shows the main menu; _on_preset_chosen() is what
	# actually deals a hand and reveals the board.
	table._on_preset_chosen("teel")
	for i in range(30):
		await process_frame

	# Stock both trick piles so the team columns are measured at the size they
	# reach mid-hand, not empty.
	for t in range(3):
		var trick: Array = []
		for k in range(4):
			trick.append(Domino.new(t, k))
		table._us_tricks.add_trick_dominoes(trick)
	for t in range(2):
		var trick2: Array = []
		for k in range(4):
			trick2.append(Domino.new(t + 3, k))
		table._them_tricks.add_trick_dominoes(trick2)
	table._us_marks.set_marks(2)
	table._them_marks.set_marks(1)
	for i in range(6):
		await process_frame

	print("viewport: %s" % str(root.get_visible_rect().size))
	print("=== LANDMARK RECTS ===")
	_rect("top row", table._game_top_row)
	_rect("mid row", table._game_mid_row)
	_rect("US marks", table._us_marks)
	_rect("US marks parent", table._us_marks.get_parent())
	_rect("US tricks scroll", table._us_tricks.get_parent())
	_rect("THEM marks", table._them_marks)
	_rect("THEM marks parent", table._them_marks.get_parent())
	_rect("play area panel", table.play_vbox.get_parent())
	_rect("play_vbox", table.play_vbox)
	_rect("info_label", table.info_label)
	_rect("play_area_container", table.play_area_container)
	_rect("status_label", table.status_label)
	_rect("opp left col", table.opponent_left_container)
	_rect("opp right col", table.opponent_right_container)
	_rect("opp top (partner)", table.opponent_top_container)
	_rect("player hand", table.player_hand_container)
	_rect("bid_reminder_label", table.bid_reminder_label)
	_rect("laydown_btn", table.laydown_btn)

	print("")
	print("bid_reminder anchors: L=%s T=%s R=%s B=%s  offs=%s,%s,%s,%s  grow_h=%d grow_v=%d" % [
		table.bid_reminder_label.anchor_left, table.bid_reminder_label.anchor_top,
		table.bid_reminder_label.anchor_right, table.bid_reminder_label.anchor_bottom,
		table.bid_reminder_label.offset_left, table.bid_reminder_label.offset_top,
		table.bid_reminder_label.offset_right, table.bid_reminder_label.offset_bottom,
		table.bid_reminder_label.grow_horizontal, table.bid_reminder_label.grow_vertical])

	# Force both floating overlays visible with representative text so their
	# measured rects are the ones the player actually sees, not the empty ones.
	table.bid_reminder_label.text = "P0 - Us\nNello doubles high\n1 mark"
	table.laydown_btn.visible = true
	for i in range(4):
		await process_frame
	print("")
	print("=== WITH OVERLAYS POPULATED ===")
	_rect("bid_reminder_label", table.bid_reminder_label)
	_rect("laydown_btn", table.laydown_btn)

	var img: Image = root.get_texture().get_image()
	if img != null:
		var err := img.save_png(out_dir + "/layout_probe.png")
		print("saved %s/layout_probe.png (%dx%d) err=%d" % [out_dir, img.get_width(), img.get_height(), err])
	else:
		print("(no image — renderer unavailable)")

	quit(0)
