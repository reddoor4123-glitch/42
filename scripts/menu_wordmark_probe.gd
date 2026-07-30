extends SceneTree
# Measures the main-menu wordmark: the "42" title, the subtitle under it, the
# gap between them, and how much width the panel actually gives them — so the
# subtitle can be sized and tightened against real numbers rather than guesses.
# Run WITHOUT --headless:
#   godot --path . --script res://scripts/menu_wordmark_probe.gd -- <out_dir>

func _find_label(n: Node, want: String) -> Label:
	if n is Label and n.text == want:
		return n
	for c in n.get_children():
		var hit := _find_label(c, want)
		if hit != null:
			return hit
	return null

func _init():
	root.size = Vector2i(1152, 800)
	var table = load("res://control.tscn").instantiate()
	root.add_child(table)
	for i in range(14):
		await process_frame

	var title := _find_label(table, "42")
	var sub := _find_label(table, "Texas Dominos")
	if title == null or sub == null:
		print("FAIL: title=%s subtitle=%s" % [str(title != null), str(sub != null)])
		quit(1)
		return

	var tr: Rect2 = title.get_global_rect()
	var sr: Rect2 = sub.get_global_rect()
	var panel: Rect2 = table.main_menu_panel.get_global_rect()

	print("font_scale = %.2f" % table.font_scale)
	print("panel            x=%7.1f..%7.1f (w=%.1f)" % [panel.position.x, panel.end.x, panel.size.x])
	print("\"42\"             y=%7.1f..%7.1f  h=%6.1f  font_size=%d" % [
		tr.position.y, tr.end.y, tr.size.y, title.get_theme_font_size("font_size")])
	print("subtitle         y=%7.1f..%7.1f  h=%6.1f  font_size=%d" % [
		sr.position.y, sr.end.y, sr.size.y, sub.get_theme_font_size("font_size")])
	print("gap title->sub   %.1f px" % (sr.position.y - tr.end.y))

	# Ink extents, not box extents: Rye carries a lot of internal leading, so the
	# visible gap is much bigger than the box gap. This is the number the eye
	# actually reads.
	var tf: Font = title.get_theme_font("font")
	var sf: Font = sub.get_theme_font("font")
	var t_px: int = title.get_theme_font_size("font_size")
	var s_px: int = sub.get_theme_font_size("font_size")
	var t_asc: float = tf.get_ascent(t_px)
	var t_desc: float = tf.get_descent(t_px)
	print("")
	print("\"42\" ascent=%.1f descent=%.1f  line_h=%.1f (box %.1f -> %.1f of slack)" % [
		t_asc, t_desc, tf.get_height(t_px), tr.size.y, tr.size.y - tf.get_height(t_px)])
	print("subtitle width   %.1f px  (panel inner ~%.1f)" % [
		sf.get_string_size(sub.text, HORIZONTAL_ALIGNMENT_LEFT, -1, s_px).x, panel.size.x - 64.0])

	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var img: Image = root.get_texture().get_image()
		if img != null:
			img.save_png(args[0] + "/menu_wordmark.png")
			print("saved %s/menu_wordmark.png" % args[0])
	quit(0)
