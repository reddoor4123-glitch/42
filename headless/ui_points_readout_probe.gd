extends SceneTree
# Drives real tricks through game_table._resolve_trick() and reads the live
# info_label after each one, so the points readout is verified against the
# actual UI path rather than by inspecting the source. Run WITHOUT --headless
# (Label text metrics need a real text server):
#   godot --path . --script res://headless/ui_points_readout_probe.gd

func _init():
	root.size = Vector2i(1200, 800)
	var table = load("res://control.tscn").instantiate()
	root.add_child(table)
	for i in range(10):
		await process_frame
	table._on_preset_chosen("teel")
	for i in range(30):
		await process_frame

	var game = table.game
	print("after deal, before any trick : %s" % table.info_label.text)
	print("game.team_points             : %s" % str(game.team_points))

	# Three tricks, each seat playing its first remaining domino in seat order.
	# _resolve_trick() credits points and refreshes the readout before its own
	# 2.2s await, so the label is current the moment the call returns.
	var leader := 0
	for t in range(3):
		game.start_trick(leader)
		for step in range(4):
			var seat: int = (leader + step) % 4
			var p = game.players[seat]
			if p.hand.is_empty():
				continue
			game.play_domino(p, p.hand[0])
		var before: Array = game.team_points.duplicate()
		table._resolve_trick()
		print("trick %d: points %s -> %s | label: %s" % [
			t + 1, str(before), str(game.team_points), table.info_label.text])
		leader = game.current_trick.determine_winner()
		for i in range(3):
			await process_frame

	# Checked by the pairing of each side's word with its number rather than
	# against the whole format string, so rewording or respacing the readout
	# doesn't fail this — but the two teams' numbers getting swapped still does.
	var flat := table.info_label.text
	while flat.contains("  "):
		flat = flat.replace("  ", " ")
	var want_us := "You %d" % game.team_points[0]
	var want_them := "Them %d" % game.team_points[1]
	if flat.contains(want_us) and flat.contains(want_them):
		print("PASS: readout carries \"%s\" and \"%s\" (%s)" % [want_us, want_them, table.info_label.text])
	else:
		print("FAIL: label %s is missing \"%s\" and/or \"%s\"" % [
			table.info_label.text, want_us, want_them])
	if game.team_points[0] + game.team_points[1] == 0:
		print("FAIL: three tricks resolved but no points were credited at all")
	quit(0)
