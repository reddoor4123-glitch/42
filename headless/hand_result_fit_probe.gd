extends SceneTree
# The end-of-hand state is its own layout case: the win banner plus the
# Replay/Next buttons share play_vbox, and holding the diamond's full height
# open on top of them pushed the player's hand off the bottom. Checks the hand
# stays on screen with the banner up, and that the diamond gets its reservation
# back once the next hand starts. Run WITHOUT --headless:
#   godot --path . --script res://headless/hand_result_fit_probe.gd -- <out_dir>

func _init():
	root.size = Vector2i(1152, 800)
	var table = load("res://control.tscn").instantiate()
	root.add_child(table)
	for i in range(10):
		await process_frame
	table._on_preset_chosen("teel")
	for i in range(20):
		await process_frame

	# Same shape of result dict both real end-of-hand paths produce.
	table.bid_panel.visible = false
	table._show_hand_result({
		"winner": 0, "reason": "Met point bid of 30",
		"team_marks": [1, 0], "team_points": [35, 0],
	})
	for i in range(10):
		await process_frame

	var vp: Vector2 = root.get_visible_rect().size
	var vbox: VBoxContainer = table._game_top_row.get_parent()
	var hand: Rect2 = table.player_hand_container.get_global_rect()
	var banner: Rect2 = table._hand_result_banner.get_global_rect()
	var panel: Rect2 = table.play_vbox.get_parent().get_global_rect()
	var pac: Rect2 = table.play_area_container.get_global_rect()

	print("viewport %.0fx%.0f | vbox min height %.1f" % [
		vp.x, vp.y, vbox.get_combined_minimum_size().y])
	print("play panel   y=%.1f..%.1f (h=%.1f)" % [panel.position.y, panel.end.y, panel.size.y])
	print("diamond      y=%.1f..%.1f  reservation min_h=%.1f" % [
		pac.position.y, pac.end.y, table.play_area_container.get_combined_minimum_size().y])
	print("banner       y=%.1f..%.1f  \"%s\"" % [
		banner.position.y, banner.end.y, table._hand_result_banner.text])
	print("player hand  y=%.1f..%.1f  (viewport bottom %.0f)" % [
		hand.position.y, hand.end.y, vp.y])

	var fail := 0
	if hand.end.y > vp.y + 0.5:
		print("FAIL: hand runs %.1f px past the bottom of the screen" % (hand.end.y - vp.y))
		fail += 1
	else:
		print("PASS: player's hand is fully on screen with the banner up")
	if banner.end.y > panel.end.y + 0.5:
		print("FAIL: banner spills past the bottom of the play panel")
		fail += 1
	else:
		print("PASS: banner sits inside the play panel")

	# Buttons live in the diamond; make sure they are still there and centred.
	var cols := 0
	for c in table.play_area_container.get_children():
		if c is VBoxContainer and not c.has_meta("play_area_seat"):
			cols += 1
			var off: Vector2 = (c.position + c.size * 0.5) - table.play_area_container.size * 0.5
			print("button column offset from diamond centre: (%.1f, %.1f)" % [off.x, off.y])
			if off.length() > 1.0:
				print("FAIL: button column is off-centre by %.1fpx" % off.length())
				fail += 1
	if cols == 0:
		print("FAIL: no Replay/Next button column found")
		fail += 1

	# Grabbed before the next hand starts, or the banner is already gone.
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var img: Image = root.get_texture().get_image()
		if img != null:
			img.save_png(args[0] + "/hand_result.png")
			print("saved %s/hand_result.png" % args[0])

	# Next hand must hand the diamond its height back.
	table._start_hand()
	for i in range(20):
		await process_frame
	var restored: float = table.play_area_container.get_combined_minimum_size().y
	var want: float = table._play_area_min_height()
	print("")
	print("after next hand: reservation %.1f (expected %.1f, banner=%s)" % [
		restored, want, str(is_instance_valid(table._hand_result_banner))])
	if absf(restored - want) > 0.5:
		print("FAIL: diamond did not get its height reservation back")
		fail += 1
	else:
		print("PASS: reservation restored for the next hand")

	print("")
	print("=== %s (%d failures) ===" % ["OK" if fail == 0 else "FAILURES", fail])

	quit(0)
