extends SceneTree
# Puts a real four-domino trick on the table and measures whether the seat
# slots actually collide — tile-vs-tile and, more importantly, label-vs-label,
# which is what turns the diamond into an unreadable smear. Also reports how
# much vertical room the play area has to spread into. Run WITHOUT --headless:
#   godot --path . --script res://headless/diamond_overlap_probe.gd -- <out_dir>

func _overlap(a: Rect2, b: Rect2) -> Vector2:
	var x: float = min(a.end.x, b.end.x) - max(a.position.x, b.position.x)
	var y: float = min(a.end.y, b.end.y) - max(a.position.y, b.position.y)
	return Vector2(x, y)

func _init():
	root.size = Vector2i(1152, 800)
	var table = load("res://control.tscn").instantiate()
	root.add_child(table)
	for i in range(10):
		await process_frame
	table._on_preset_chosen("teel")
	for i in range(20):
		await process_frame

	# Skip the auction entirely and drop one domino per seat into the diamond,
	# which is exactly what _execute_play() does during a trick.
	table.bid_panel.visible = false
	table.trump_panel.visible = false
	table.nello_panel.visible = false
	table.nello_exchange_panel.visible = false
	table.game.trump = 1
	table.trump_indicator_label.text = "Trump: Ones"
	table._clear_play_area()
	for pid in range(4):
		table._add_to_play_area(pid, Domino.new(pid, 6))
	for i in range(8):
		await process_frame

	var pac: Rect2 = table.play_area_container.get_global_rect()
	print("play_area_container: y=%.1f..%.1f  h=%.1f  (min_h=%.1f)" % [
		pac.position.y, pac.end.y, pac.size.y,
		table.play_area_container.get_combined_minimum_size().y])
	print("TILE_FULL=%s  font_scale=%.2f" % [str(table.TILE_FULL), table.font_scale])
	print("")

	var slots: Array = []
	for c in table.play_area_container.get_children():
		if c is Control and c.has_meta("play_area_seat"):
			slots.append(c)
	print("=== slots (%d) ===" % slots.size())
	for s in slots:
		var seat: int = int(s.get_meta("play_area_seat"))
		var r: Rect2 = s.get_global_rect()
		var lbl: Label = null
		for c in s.get_children():
			if c is Label:
				lbl = c
		print("  seat %d %-12s slot x=%7.1f..%7.1f y=%7.1f..%7.1f | label \"%s\" w=%.1f" % [
			seat, table._seat_label(seat), r.position.x, r.end.x, r.position.y, r.end.y,
			lbl.text if lbl != null else "?", lbl.get_global_rect().size.x if lbl != null else 0.0])

	print("")
	print("=== pairwise collisions ===")
	var bad := 0
	for i in range(slots.size()):
		for j in range(i + 1, slots.size()):
			var a: Control = slots[i]
			var b: Control = slots[j]
			var ov: Vector2 = _overlap(a.get_global_rect(), b.get_global_rect())
			var la: Label = _label_of(a)
			var lb: Label = _label_of(b)
			var lov: Vector2 = _overlap(la.get_global_rect(), lb.get_global_rect())
			var slot_hit: bool = ov.x > 0.0 and ov.y > 0.0
			var lbl_hit: bool = lov.x > 0.0 and lov.y > 0.0
			if slot_hit or lbl_hit:
				bad += 1
				print("  COLLIDE seat %s vs %s : slot overlap %s | label overlap %s" % [
					str(a.get_meta("play_area_seat")), str(b.get_meta("play_area_seat")),
					("%.0fx%.0f" % [ov.x, ov.y]) if slot_hit else "none",
					("%.0fx%.0f" % [lov.x, lov.y]) if lbl_hit else "none"])
	if bad == 0:
		print("  PASS: all four slots and all four labels are clear of each other")
	else:
		print("  FAIL: %d colliding pair(s)" % bad)

	# What full separation would need, versus what the container has.
	var slot_h: float = slots[0].get_global_rect().size.y
	var widest := 0.0
	for s in slots:
		widest = max(widest, s.get_global_rect().size.x)
	print("")
	print("slot box: %.1f wide x %.1f tall (widest slot %.1f)" % [
		slots[0].get_global_rect().size.x, slot_h, widest])
	print("vertical room needed for top/bottom to clear: %.1f  |  container has %.1f" % [
		slot_h * 2.0, pac.size.y])

	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var img: Image = root.get_texture().get_image()
		if img != null:
			img.save_png(args[0] + "/diamond.png")
			print("saved %s/diamond.png" % args[0])
	quit(0)

func _label_of(n: Control) -> Label:
	for c in n.get_children():
		if c is Label:
			return c
	return null
