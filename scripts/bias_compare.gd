extends SceneTree
# Renders the trick area at several PLAY_SLOT_BIAS values so the diamond can be
# tuned by eye. Run WITHOUT --headless:
#   godot --path . --script res://scripts/bias_compare.gd -- <out_dir>
#
# Reproduces _play_area_slot_offset()'s formula with a variable bias rather than
# the const, so nothing in game_table.gd has to change to compare options.

func _offset(pid: int, human: int, tile: Vector2, bias: float) -> Vector2:
	var dx = tile.x * bias
	var dy = tile.y * bias * 0.5
	if pid == human:
		return Vector2(0, dy)
	elif pid == (human + 2) % 4:
		return Vector2(0, -dy)
	elif pid == (human + 1) % 4:
		return Vector2(dx, 0)
	else:
		return Vector2(-dx, 0)

func _init():
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://"
	root.size = Vector2i(900, 820)

	var table = load("res://control.tscn").instantiate()
	root.add_child(table)
	for i in range(12):
		await process_frame
	table.main_menu_panel.visible = false
	table._on_preset_chosen("standard")
	var waited := 0
	while (table.game == null or table.play_area_container.size.x <= 0.0) and waited < 600:
		await process_frame
		waited += 1

	var pac = table.play_area_container
	for bias in [0.4, 0.7, 1.0, 1.3]:
		table._clear_play_area()
		await process_frame
		for pid in range(4):
			table._add_to_play_area(pid, table.game.players[pid].hand[0])
		await process_frame
		# Give the container enough height for the larger biases so this
		# compares the bias itself, not clipping.
		var need: float = table.TILE_FULL.y * (1.0 + bias) + 60.0
		pac.custom_minimum_size = Vector2(0, need)
		pac.size = Vector2(pac.size.x, need)
		await process_frame
		for k in pac.get_children():
			if k is Control and k.has_meta("play_area_seat"):
				var pid := int(k.get_meta("play_area_seat"))
				var sz = k.get_combined_minimum_size()
				k.size = sz
				k.position = pac.size * 0.5 \
					+ _offset(pid, table.human_seat, table.TILE_FULL, bias) - sz * 0.5
		await process_frame
		await process_frame
		var img: Image = root.get_texture().get_image()
		var path := "%s/bias_%02d.png" % [out_dir, int(bias * 10)]
		print("bias %.1f -> %s (container h %.0f) err=%d" % [
			bias, path, need, img.save_png(path)])

	quit(0)
