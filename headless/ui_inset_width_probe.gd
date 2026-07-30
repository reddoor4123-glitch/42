extends SceneTree
# The PLAY_AREA_INSET added to the top row costs 2x68 px of width that the
# US/THEM columns used to have. This sweeps narrow viewports to confirm the
# team columns and the partner hand between them still fit, and that the two
# bottom-corner overlays stay inside the window. Run WITHOUT --headless:
#   godot --path . --script res://headless/ui_inset_width_probe.gd

func _init():
	var table = load("res://control.tscn").instantiate()
	root.add_child(table)
	for i in range(10):
		await process_frame
	table._on_preset_chosen("teel")
	for i in range(20):
		await process_frame

	var fail := 0
	for w in [420, 480, 600, 720, 900, 1152, 1400]:
		root.size = Vector2i(w, 800)
		for i in range(6):
			await process_frame
		var vp: Vector2 = root.get_visible_rect().size
		var us: Rect2 = table._us_marks.get_parent().get_global_rect()
		var them: Rect2 = table._them_marks.get_parent().get_global_rect()
		var partner: Rect2 = table.opponent_top_container.get_global_rect()
		var panel: Rect2 = table.play_vbox.get_parent().get_global_rect()
		var lay: Rect2 = table.laydown_btn.get_global_rect()
		print("win %4d -> vp %.0fx%.0f | US %.0f..%.0f  partner w=%.0f  THEM %.0f..%.0f | panel %.0f..%.0f | lay %.0f..%.0f" % [
			w, vp.x, vp.y, us.position.x, us.end.x, partner.size.x,
			them.position.x, them.end.x, panel.position.x, panel.end.x,
			lay.position.x, lay.end.x])

		if us.end.x > them.position.x:
			print("    FAIL: US and THEM columns overlap")
			fail += 1
		if us.position.x < 0 or them.end.x > vp.x:
			print("    FAIL: a team column is off-screen")
			fail += 1
		if lay.position.x < 0 or lay.end.x > vp.x:
			print("    FAIL: Lay Down button is off-screen")
			fail += 1
		# The whole point of the inset: the columns sit on the play panel's
		# own verticals, so drift here means the two rows fell out of register.
		if abs(us.position.x - panel.position.x) > 0.5 or abs(them.end.x - panel.end.x) > 0.5:
			print("    FAIL: team columns no longer align with the play panel edges")
			fail += 1
		if abs(lay.end.x - panel.end.x) > 0.5:
			print("    FAIL: Lay Down right edge no longer on the panel's right vertical")
			fail += 1

	print("")
	print("=== %s (%d failures) ===" % ["ALL WIDTHS OK" if fail == 0 else "FAILURES", fail])
	quit(0)
