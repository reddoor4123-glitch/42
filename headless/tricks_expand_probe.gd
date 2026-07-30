extends SceneTree
# Verifies the expandable trick lists: that a full seven-trick pile is actually
# all visible when expanded, that the panel covers its own scroll box rather
# than repeating it, that it clears everything it must not block (the played
# diamond, both opponents' hands, the points readout, the player's hand, the
# gear), that the surrounding layout does not move, and that it folds away on a
# new hand. Run WITHOUT --headless:
#   godot --path . --script res://headless/tricks_expand_probe.gd -- <out_dir>

var _fail := 0

func _hit(a: Rect2, b: Rect2) -> bool:
	return a.intersects(b)

func _check_clear(name: String, panel: Rect2, other: Rect2, other_name: String) -> void:
	if _hit(panel, other):
		var ov: Rect2 = panel.intersection(other)
		print("    FAIL: %s overlaps %s by %.0fx%.0f" % [name, other_name, ov.size.x, ov.size.y])
		_fail += 1
	else:
		print("    ok: %s clears %s" % [name, other_name])

func _init():
	root.size = Vector2i(1152, 800)
	var table = load("res://control.tscn").instantiate()
	root.add_child(table)
	for i in range(10):
		await process_frame
	table._on_preset_chosen("teel")
	for i in range(20):
		await process_frame

	# A full hand's worth: seven tricks to US, seven to THEM, so both panels are
	# measured at their largest possible size.
	for t in range(7):
		var a: Array = []
		var b: Array = []
		for k in range(4):
			a.append(Domino.new(t % 7, k))
			b.append(Domino.new((t + 1) % 7, k))
		table._us_tricks.add_trick_dominoes(a)
		table._them_tricks.add_trick_dominoes(b)
	# One played domino per seat, so the "does it block the table" check is made
	# against where tiles actually sit rather than against play_area_container,
	# which spans the whole play panel and would overlap any overlay at all.
	table.game.trump = 1
	for pid in range(4):
		table._add_to_play_area(pid, Domino.new(pid, 6))
	for i in range(6):
		await process_frame
	var slots: Array = []
	for c in table.play_area_container.get_children():
		if c is Control and c.has_meta("play_area_seat"):
			slots.append(c)

	# Layout must not budge when a panel opens — capture before and after.
	var before := {
		"top row": table._game_top_row.get_global_rect(),
		"play panel": table.play_vbox.get_parent().get_global_rect(),
		"player hand": table.player_hand_container.get_global_rect(),
		"points": table.info_label.get_global_rect(),
		"partner": table.opponent_top_container.get_global_rect(),
	}

	print("collapsed: us box %s | toggle %s" % [
		str(table._tricks_scroll[0].get_global_rect()),
		str(table._tricks_toggle_btn[0].get_global_rect())])

	table._set_tricks_expanded(0, true)
	table._set_tricks_expanded(1, true)
	for i in range(8):
		await process_frame

	var vp: Vector2 = root.get_visible_rect().size
	for team in range(2):
		var label: String = "US" if team == 0 else "THEM"
		var panel: PanelContainer = table._tricks_overlay[team]
		var pile: TrickPile = table._us_tricks if team == 0 else table._them_tricks
		var box: Rect2 = table._tricks_scroll[team].get_global_rect()
		var pr: Rect2 = panel.get_global_rect()
		print("")
		print("%s expanded: panel %s  (pile %d dominoes, needs %.0f tall)" % [
			label, str(pr), pile.dominoes.size(), pile.get_combined_minimum_size().y])
		if pile.get_parent() != panel:
			print("    FAIL: pile was not reparented into the panel")
			_fail += 1
		# All 28 visible means the panel is at least as tall as the pile wants.
		if pr.size.y + 0.5 < pile.get_combined_minimum_size().y:
			print("    FAIL: panel is shorter than the pile — rows still hidden")
			_fail += 1
		else:
			print("    ok: all %d dominoes fit with no scrolling" % pile.dominoes.size())
		# Covers its own box, so the first rows are not shown twice.
		if not pr.encloses(box.grow(-1.0)):
			print("    FAIL: panel does not cover its scroll box (rows would repeat)")
			_fail += 1
		else:
			print("    ok: panel covers its own box")
		if pr.position.x < 0.0 or pr.end.x > vp.x or pr.end.y > vp.y:
			print("    FAIL: panel runs off screen")
			_fail += 1

		for sl in slots:
			_check_clear(label, pr, sl.get_global_rect(),
				"played tile (%s)" % table._seat_label(int(sl.get_meta("play_area_seat"))))
		_check_clear(label, pr, table.player_hand_container.get_global_rect(), "player's hand")
		_check_clear(label, pr, table.opponent_left_container.get_global_rect(), "left opponent hand")
		_check_clear(label, pr, table.opponent_right_container.get_global_rect(), "right opponent hand")
		_check_clear(label, pr, table.info_label.get_global_rect(), "points readout")
		_check_clear(label, pr, table.opponent_top_container.get_global_rect(), "partner hand")
		# Toggle must stay reachable to collapse again.
		var btn: Rect2 = table._tricks_toggle_btn[team].get_global_rect()
		if _hit(btn, pr):
			print("    FAIL: toggle is underneath its own panel")
			_fail += 1
		else:
			print("    ok: toggle stays clickable outside the panel")

	print("")
	print("=== layout must not have moved ===")
	for k in before:
		var now: Rect2 = {
			"top row": table._game_top_row.get_global_rect(),
			"play panel": table.play_vbox.get_parent().get_global_rect(),
			"player hand": table.player_hand_container.get_global_rect(),
			"points": table.info_label.get_global_rect(),
			"partner": table.opponent_top_container.get_global_rect(),
		}[k]
		if now != before[k]:
			print("  FAIL: %s moved %s -> %s" % [k, str(before[k]), str(now)])
			_fail += 1
		else:
			print("  ok: %s unchanged" % k)

	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var img: Image = root.get_texture().get_image()
		if img != null:
			img.save_png(args[0] + "/tricks_expanded.png")
			print("saved %s/tricks_expanded.png" % args[0])

	# New hand folds them away.
	table._start_hand()
	for i in range(20):
		await process_frame
	print("")
	if table._tricks_expanded[0] or table._tricks_expanded[1]:
		print("FAIL: still expanded after a new hand was dealt")
		_fail += 1
	elif table._us_tricks.get_parent() != table._tricks_scroll[0]:
		print("FAIL: pile did not return to its scroll box")
		_fail += 1
	else:
		print("PASS: both lists folded back into their boxes on the new hand")

	print("")
	print("=== %s (%d failures) ===" % ["OK" if _fail == 0 else "FAILURES", _fail])
	quit(0)
