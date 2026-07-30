extends SceneTree
# Instantiates the real main scene and inspects the live node tree, so the
# checks below cover the actual wiring in game_table.gd rather than a copy of
# it. Run with:
#   godot --headless --path . --script res://scripts/ui_font_layout_verify.gd

func _find(node: Node, pred: Callable, out: Array) -> void:
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		_find(c, pred, out)

func _font_id(f) -> String:
	if f == null:
		return "<null>"
	if f is FontVariation:
		var base = f.base_font
		var name = base.get_font_name() if base != null else "?"
		var coords = f.variation_opentype
		var wght = "-"
		for k in coords:
			wght = str(coords[k])
		return "%s wght=%s fallbacks=%d" % [name, wght, f.fallbacks.size()]
	if f is FontFile:
		return "%s (bare FontFile, no fallbacks)" % f.get_font_name()
	return f.get_class()

func _init():
	var fail := 0
	var scene = load("res://control.tscn")
	if scene == null:
		print("FAIL: could not load res://control.tscn")
		quit(1)
		return
	var table = scene.instantiate()
	root.add_child(table)

	# Let the UI settle so container layout has run.
	for i in range(8):
		await process_frame

	print("=== FONT WIRING (live tree) ===")

	# The Theme lives on the single root Control that game_table builds.
	var roots: Array = []
	_find(table, func(n): return n is Control and n.theme != null, roots)
	if roots.is_empty():
		print("FAIL: no Control in the tree carries a Theme")
		fail += 1
	else:
		var th: Theme = roots[0].theme
		print("root Theme.default_font : %s" % _font_id(th.default_font))
		if th.default_font is FontVariation and th.default_font.fallbacks.size() == 3:
			print("PASS: global default is a FontVariation with the 3-font fallback chain")
		else:
			print("FAIL: global default lost its fallback chain -> symbol/emoji tofu")
			fail += 1

	# Named spots: match on the text they carry.
	var checks := [
		["42",                          "Rye",    "menu title"],
		["Texas Dominos",               "Rye",    "menu subtitle"],
		["Play",                        "Nunito", "menu Play button"],
		["Choose Rules",                "Nunito", "menu Choose Rules button"],
		["Difficulty",                  "Nunito", "menu Difficulty button"],
		["Profiles",                    "Nunito", "menu Profiles button"],
	]
	print("")
	for chk in checks:
		var want_text: String = chk[0]
		var want_family: String = chk[1]
		var label: String = chk[2]
		var hits: Array = []
		_find(table, func(n): return (n is Label or n is Button) and n.text == want_text, hits)
		if hits.is_empty():
			print("FAIL: could not find node with text %s (%s)" % [want_text, label])
			fail += 1
			continue
		var node: Control = hits[0]
		if not node.has_theme_font_override("font"):
			print("FAIL: %-28s has NO font override" % label)
			fail += 1
			continue
		var f = node.get_theme_font("font")
		var id := _font_id(f)
		var ok := want_family in id
		print("%s %-28s %s" % ["PASS:" if ok else "FAIL:", label, id])
		if not ok:
			fail += 1

	# Section headers are built on demand. Go in through _show_settings_panel()
	# rather than _build_settings_content() directly — the former seeds
	# _pending_settings, which the section builders read.
	table.main_menu_panel.visible = false
	table._on_preset_chosen("standard")
	var boot := 0
	while table.game == null and boot < 600:
		await process_frame
		boot += 1
	print("\nframes waited for game init: %d" % boot)
	table._show_settings_panel()
	await process_frame

	# Section headers (settings/preset panels) should be heavy.
	var headers: Array = []
	_find(table, func(n): return n is Button and n.text.begins_with("▶  "), headers)
	print("\nsection headers found: %d" % headers.size())
	var hdr_bad := 0
	for h in headers:
		if not (h.has_theme_font_override("font") and "815" in _font_id(h.get_theme_font("font"))):
			hdr_bad += 1
	if headers.size() > 0 and hdr_bad == 0:
		print("PASS: all %d section headers carry wght 815" % headers.size())
	else:
		print("FAIL: %d of %d section headers missing wght 815" % [hdr_bad, headers.size()])
		fail += 1

	# The two hand-drawn Controls take their font by static var.
	print("\nDrumPicker.custom_font   : %s" % _font_id(DrumPicker.custom_font))
	print("MarksDisplay.custom_font : %s" % _font_id(MarksDisplay.custom_font))
	if DrumPicker.custom_font != null and MarksDisplay.custom_font != null:
		print("PASS: both _draw()-based Controls received a font")
	else:
		print("FAIL: a _draw()-based Control still falls back to ThemeDB")
		fail += 1

	# ── DIAMOND LAYOUT ───────────────────────────────────────────────────────
	print("\n=== DIAMOND LAYOUT (live) ===")
	var pac = table.play_area_container
	print("play_area_container class : %s" % pac.get_class())
	if pac.get_class() == "Control":
		print("PASS: container is a plain Control (no row-flow layout)")
	else:
		print("FAIL: container is still %s" % pac.get_class())
		fail += 1

	# The diamond maths depends on play_area_container.size being real, which
	# only happens once the table is visible and laid out.
	var waited := 0
	while (table.game == null or pac.size.x <= 0.0) and waited < 600:
		await process_frame
		waited += 1
	print("frames waited for table layout: %d" % waited)
	print("container size            : %s" % pac.size)
	print("container min height      : %.1f (derived from TILE_FULL.y=%.0f + label + bias span)" % [
		pac.custom_minimum_size.y, table.TILE_FULL.y])
	if pac.size.x > 0.0:
		print("PASS: container has a real width, so centring has something to centre on")
	else:
		print("FAIL: container width is still 0 — every tile would pile up at x=0")
		fail += 1
	if table.game == null:
		print("FAIL: game never initialised; cannot place tiles")
		print("\n=== FAILURES PRESENT (%d) ===" % (fail + 1))
		quit(1)
		return

	# Place one tile per seat and read the resulting geometry back.
	table._clear_play_area()
	for i in range(4):
		await process_frame
	var human: int = table.human_seat
	var centres := {}
	for pid in range(4):
		var d = table.game.players[pid].hand[0]
		table._add_to_play_area(pid, d)
	await process_frame

	var kids: Array = pac.get_children()
	print("\nchildren placed: %d" % kids.size())
	var order := []
	for i in range(kids.size()):
		var k: Control = kids[i]
		var c = k.position + k.size * 0.5
		centres[i] = c
		order.append(c)
		print("  child %d  pos %-22s size %-18s centre (%7.1f, %7.1f)" % [
			i, str(k.position), str(k.size), c.x, c.y])

	var expected_centre = pac.size * 0.5
	print("\ncontainer centre          : (%.1f, %.1f)" % [expected_centre.x, expected_centre.y])

	# Seats were added in id order 0..3; map each to its expected direction.
	var dir_ok := true
	for pid in range(4):
		var c: Vector2 = order[pid]
		var rel = c - expected_centre
		var want := ""
		var got := ""
		if pid == human:
			want = "below centre"
			got = "ok" if rel.y > 1.0 and abs(rel.x) < 1.0 else "WRONG"
		elif pid == (human + 2) % 4:
			want = "above centre"
			got = "ok" if rel.y < -1.0 and abs(rel.x) < 1.0 else "WRONG"
		elif pid == (human + 1) % 4:
			want = "right of centre"
			got = "ok" if rel.x > 1.0 and abs(rel.y) < 1.0 else "WRONG"
		else:
			want = "left of centre"
			got = "ok" if rel.x < -1.0 and abs(rel.y) < 1.0 else "WRONG"
		if got != "ok":
			dir_ok = false
		print("  P%d (%-15s) rel (%7.1f, %7.1f)  want %-16s %s" % [
			pid, table._seat_label(pid), rel.x, rel.y, want, got])
	if dir_ok:
		print("PASS: all four seats biased in the correct direction")
	else:
		print("FAIL: at least one seat is biased the wrong way")
		fail += 1

	# No two tiles should land on the same spot.
	var overlap := false
	for a in range(4):
		for b in range(a + 1, 4):
			if order[a].distance_to(order[b]) < 1.0:
				overlap = true
				print("FAIL: P%d and P%d occupy the same slot" % [a, b])
	if not overlap:
		print("PASS: four distinct slots, no two seats overlap")
	else:
		fail += 1

	# Tiles must stay inside the container vertically.
	var clipped := 0
	for i in range(kids.size()):
		var k: Control = kids[i]
		if k.position.y < -0.5 or k.position.y + k.size.y > pac.size.y + 0.5:
			clipped += 1
			print("  NOTE: child %d spans y %.1f..%.1f vs container height %.1f" % [
				i, k.position.y, k.position.y + k.size.y, pac.size.y])
	if clipped == 0:
		print("PASS: all four tiles fit within the container's height")
	else:
		print("FAIL: %d tile(s) overflow the container vertically" % clipped)
		fail += 1

	# ── RESIZE ───────────────────────────────────────────────────────────────
	# An HBoxContainer re-flowed its children for free; a plain Control does
	# not, so tiles already on the table must be re-placed on resize. Exercise
	# both viewport extremes (MIN_SCALE and MAX_SCALE clamp the font, and
	# TILE_FULL tracks width) with a trick already in progress.
	print("\n=== RESIZE WITH A TRICK IN PROGRESS ===")
	for w in [420, 1600, 1152]:
		root.size = Vector2i(w, 720)
		await process_frame
		table._on_viewport_resized()
		await process_frame
		var c_ok := true
		var v_ok := true
		var cen = pac.size * 0.5
		for k in pac.get_children():
			if not (k is Control):
				continue
			var seat := int(k.get_meta("play_area_seat", -1))
			if seat < 0:
				continue
			var want = table._play_area_slot_offset(seat)
			var got = (k.position + k.size * 0.5) - cen
			if got.distance_to(want) > 1.0:
				c_ok = false
			if k.position.y < -0.5 or k.position.y + k.size.y > pac.size.y + 0.5:
				v_ok = false
		print("  vp %4dpx  font_scale %.2f  TILE_FULL.y %5.1f  container %s" % [
			w, table.font_scale, table.TILE_FULL.y, str(pac.size)])
		if c_ok:
			print("    PASS: all seats still biased correctly after resize")
		else:
			print("    FAIL: a seat's offset is stale after resize")
			fail += 1
		if v_ok:
			print("    PASS: no vertical clipping at this viewport width")
		else:
			print("    FAIL: a tile clips the container at this width")
			fail += 1

	# ── SCALE SWEEP ──────────────────────────────────────────────────────────
	# The headless window would not shrink below ~1016px, so the resize block
	# above never actually reached MIN_SCALE. Drive font_scale/TILE_FULL
	# directly instead to cover both clamp extremes deterministically. This is
	# the mechanical half of the check — whether the bias *feels* right at each
	# extreme is a playtest judgement, not something asserted here.
	print("\n=== SCALE SWEEP (forced font_scale / TILE_FULL) ===")
	print("%-6s %-9s %-11s %-9s %-9s %s" % [
		"scale", "tile_w", "min_height", "slot_h", "dy", "verdict"])
	for scale in [0.75, 1.0, 1.25, 1.5]:
		# Mirror _build_ui()'s own derivation: tile_w = min(64, vp_w / 9).
		var vp_w: float = scale * 576.0
		var tile_w: float = min(64.0, floor(vp_w / 9.0))
		table.font_scale = scale
		table.TILE_FULL = Vector2(tile_w, tile_w * 2.0)
		# _on_viewport_resized() refreshes every registered font size BEFORE it
		# re-places the play area; mirror that order or the seat labels keep
		# their old height and the measurement below is meaningless.
		for entry in table._font_registry:
			entry["node"].add_theme_font_size_override(
				"font_size", round(entry["base_size"] * scale))
		var min_h: float = table._play_area_min_height()
		pac.custom_minimum_size = Vector2(0, min_h)
		pac.size = Vector2(pac.size.x, min_h)
		await process_frame

		# Re-place every tile at this scale, mirroring _on_viewport_resized().
		for k in pac.get_children():
			if k is Control:
				if k.has_meta("play_area_seat"):
					for t in k.get_children():
						if t is DominoTile:
							t.custom_minimum_size = table.TILE_PLAYED
				table._place_in_play_area(k, table._play_area_slot_offset_for(k))
		await process_frame

		var dy: float = table._play_area_slot_offset(table.human_seat).y
		var worst := 0.0
		var slot_h := 0.0
		for k in pac.get_children():
			if not (k is Control) or not k.has_meta("play_area_seat"):
				continue
			slot_h = max(slot_h, k.size.y)
			worst = max(worst, max(-k.position.y, k.position.y + k.size.y - pac.size.y))
		var ok := worst <= 0.5
		print("%-6s %-9.0f %-11.1f %-9.1f %-9.1f %s" % [
			str(scale), tile_w, min_h, slot_h, dy,
			"ok" if ok else "CLIPS by %.1fpx" % worst])
		if not ok:
			fail += 1
	if fail == 0:
		print("PASS: no clipping at any scale from MIN_SCALE %.2f to MAX_SCALE %.2f" % [
			table.MIN_SCALE, table.MAX_SCALE])

	# ── END-OF-HAND BUTTON COLUMN ────────────────────────────────────────────
	# This column used to get free centring from HBoxContainer's
	# ALIGNMENT_CENTER; with a plain Control it needs explicit placement.
	# Runs last because _show_hand_result() clears the played tiles.
	print("\n=== END-OF-HAND BUTTONS ===")
	table._show_hand_result({
		"winner": 0, "reason": "verification", "team_marks": [1, 0], "team_points": [42, 0],
	})
	await process_frame
	var cols: Array = []
	for k in pac.get_children():
		if k is VBoxContainer and not k.has_meta("play_area_seat"):
			cols.append(k)
	if cols.is_empty():
		print("FAIL: no button column found in the play area")
		fail += 1
	else:
		var col: Control = cols[0]
		var col_centre = col.position + col.size * 0.5
		var pac_centre = pac.size * 0.5
		var off = col_centre - pac_centre
		print("  column pos %s size %s" % [str(col.position), str(col.size)])
		print("  column centre %s vs container centre %s -> offset (%.1f, %.1f)" % [
			str(col_centre), str(pac_centre), off.x, off.y])
		var btns := 0
		for c in col.get_children():
			if c is Button:
				btns += 1
		print("  buttons in column: %d" % btns)
		if off.length() <= 1.0:
			print("PASS: button column is centred (no bias), replacing HBox's free centring")
		else:
			print("FAIL: button column is off-centre by %.1fpx" % off.length())
			fail += 1
		if btns > 0 and col.size.y > 0.0:
			print("PASS: column has real measured size, so centring used live geometry")
		else:
			print("FAIL: column measured empty — centring would be wrong")
			fail += 1

	print("\n=== %s (%d failure%s) ===" % [
		"ALL CHECKS PASSED" if fail == 0 else "FAILURES PRESENT",
		fail, "" if fail == 1 else "s"])
	quit(0 if fail == 0 else 1)
