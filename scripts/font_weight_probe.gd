extends SceneTree
# Quantifies what raising FONT_WEIGHT_BASE actually costs in width, and how much
# visible separation is left between the base and heavy cuts. Heavier glyphs are
# wider, so this is also the early warning for label overflow. Run WITHOUT
# --headless (the dummy text server reports zero widths):
#   godot --path . --script res://scripts/font_weight_probe.gd

func _init():
	var table = load("res://control.tscn").instantiate()
	root.add_child(table)
	for i in range(10):
		await process_frame

	var base_font: FontFile = load("res://fonts/Nunito-VariableFont_wght.ttf")
	var tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	var sample := "Your turn to bid"

	print("=== width of \"%s\" @ 20px by wght ===" % sample)
	var w400 := 0.0
	for wght in [200, 400, 777, 815, 1000]:
		var fv := FontVariation.new()
		fv.base_font = base_font
		fv.variation_opentype = {tag: wght}
		var w: float = fv.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		if wght == 400:
			w400 = w
		print("  wght %4d -> %7.2f px%s" % [
			wght, w, ("   (+%.2f%% vs 400)" % ((w / w400 - 1.0) * 100.0)) if w400 > 0.0 else ""])

	# What the game is actually running now.
	print("")
	var live_base: float = table._font_nunito_regular.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var live_heavy: float = table._font_nunito_heavy.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	print("live base font  : %7.2f px" % live_base)
	print("live heavy font : %7.2f px" % live_heavy)
	print("base vs heavy   : %.2f px apart (%.2f%%)" % [
		live_heavy - live_base, (live_heavy / live_base - 1.0) * 100.0])
	if absf(live_heavy - live_base) < 1.0:
		print("NOTE: base and heavy are now within 1px at 20px — the two cuts will")
		print("      read as the same weight anywhere they sit side by side.")

	# The widest fixed-width UI text is the one most likely to overflow first.
	print("")
	print("=== longest labels vs the space they sit in ===")
	table._on_preset_chosen("teel")
	for i in range(20):
		await process_frame
	var worst := 0.0
	var worst_txt := ""
	var nodes: Array = []
	_collect(table, nodes)
	for n in nodes:
		var f: Font = n.get_theme_font("font")
		var fs: int = n.get_theme_font_size("font_size")
		var need: float = f.get_string_size(n.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var have: float = n.size.x
		if n is Button:
			have = n.size.x - 8.0
		if have > 1.0 and need > have and (need - have) > worst:
			worst = need - have
			worst_txt = n.text
	if worst > 0.0:
		print("  WORST overflow: \"%s\" needs %.1f px more than it has" % [worst_txt, worst])
	else:
		print("  PASS: no visible Label/Button text is wider than its own box")
	quit(0)

func _collect(n: Node, out: Array) -> void:
	if (n is Label or n is Button) and not n.text.is_empty() and n.is_visible_in_tree():
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
