extends SceneTree

# Does the trump panel fit, with room left for the controls it is about to grow?
#
# Step 1 of the trump-preview work (Aug 1 2026). Measured before touching
# anything, the panel left 16px of vertical slack at the design resolution and
# the human's hand sat with its bottom edge flush against the viewport bottom.
# A Back and a Confirm button need a row, and a row costs ~46px, so the panel
# has to give height back before it can take any.
#
# Measuring the height budget rather than the window slack turned that reading
# on its head. The 16px is slack in the WHOLE WINDOW, and the trump panel is not
# the term that consumes it:
#
#   vbox        214 (top row) + 426 (middle row) + 128 (hand) + gaps = 784 of 800
#   play_vbox   311 min — inside a middle row whose 426 is set by the SIDE
#               opponents' stacked hands, not by anything in the play column
#
# So the play column has ~115px of slack the window does not see, and the panel
# can grow into it without moving the layout at all. Freeing a row by reflowing
# the suit buttons would have bought nothing: play_vbox would drop 311 -> 265
# and the middle row would still be 426.
#
# Hence what this actually asserts, for every combination of trump-panel
# options: with a Back/Confirm row SIMULATED into the panel, the player's hand
# is still fully on screen and no tile is clipped. That is the real question —
# "can the panel take the controls" — and it is not answerable from a slack
# number. The failure it guards is the one documented at
# _play_area_reserves_height(): play_vbox outgrows the window and shoves the
# hand off the bottom.
#
# The combinations matter because the special-trump row (Doubles / Doubles
# Reversed / Follow Me) is settings-driven: the panel is at its tallest with
# every option enabled, which is not the default and so is not what you see
# playing a normal hand.
#
# MUST run WITHOUT --headless:
#   godot --path . --script res://headless/trump_panel_fit_verify.gd
#
# Under --headless there is no real window and `root.size` does not take: the
# viewport reports 1152x1152 instead of 1152x800, which hands the panel 352px of
# slack it will never have and turns every assertion here into a false pass.
# That is worse than no check at all, so the viewport is asserted first and the
# run aborts if it is wrong rather than reporting green.

const BidScript = preload("res://bid.gd")

# The design resolution. project.godot pins viewport_height=800 and leaves the
# width at Godot's 1152 default, with stretch/aspect="expand" and
# handheld/orientation=1 — so a landscape phone is the tight case and height is
# the scarce axis.
const VP := Vector2i(1152, 800)

var _table: Node = null
var _results: Array = []
var _failures := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	_results.append({"test": name, "pass": ok, "detail": detail})
	if not ok:
		_failures += 1

func _init():
	root.size = VP
	_table = load("res://control.tscn").instantiate()
	root.add_child(_table)
	for i in range(10):
		await process_frame

	# Everything below is a height measurement, so a viewport that is not the one
	# we asked for makes every result meaningless. Refuse rather than measure.
	var got: Vector2 = root.get_visible_rect().size
	if got != Vector2(VP):
		_check("viewport is the design resolution", false,
			"got %.0fx%.0f, want %dx%d — are you running with --headless? "
			% [got.x, got.y, VP.x, VP.y] + "This check needs a real window.")
		_write_results()
		quit(1)
		return
	_check("viewport is the design resolution", true, "%dx%d" % [VP.x, VP.y])

	_table.main_menu_panel.visible = false
	_table._on_preset_chosen("standard")
	for i in range(20):
		await process_frame

	# Force the human into the "you won the bid" state rather than waiting out a
	# real auction, and get the bid panel out of the way — only one picker is
	# ever up at a time, and its height would confound the measurement.
	_table.game.current_bid = BidScript.new(BidScript.Type.POINTS, 32, _table.human_seat)
	_table.bid_panel.visible = false
	for i in range(4):
		await process_frame

	# Every reachable shape of the panel, tallest last.
	for combo in [
		{"follow": false, "doubles": false, "rev": false, "label": "suits only"},
		{"follow": true,  "doubles": false, "rev": false, "label": "+ Follow Me"},
		{"follow": false, "doubles": true,  "rev": false, "label": "+ Doubles"},
		{"follow": false, "doubles": true,  "rev": true,  "label": "+ Doubles/Reversed"},
		{"follow": true,  "doubles": true,  "rev": true,  "label": "everything on"},
	]:
		await _measure(combo)

	# Budget is captured with the panel still up in its tallest configuration —
	# the state the assertions were made against.
	_write_results()
	quit(1 if _failures > 0 else 0)

# Which node is actually setting the height, recorded as data rather than
# asserted. A failure here says "you are 30px short"; without this it does not
# say who is holding the 30px, and the answer turned out not to be the trump
# panel at all.
func _height_budget() -> Dictionary:
	var out := {}
	for pair in [["vbox", _table._game_top_row.get_parent()], ["play_vbox", _table.play_vbox]]:
		var rows: Array = []
		var parent: Node = pair[1]
		for c in parent.get_children():
			if c is Control:
				rows.append({
					"node": c.name, "class": c.get_class(), "visible": c.visible,
					"min_h": c.get_combined_minimum_size().y,
					"actual_h": c.get_global_rect().size.y,
					"v_flags": c.size_flags_vertical,
				})
		out[pair[0]] = {
			"own_min_h": (parent as Control).get_combined_minimum_size().y,
			"children": rows,
		}
	return out

func _write_results() -> void:
	var f = FileAccess.open("res://headless/trump_panel_fit_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"failures": _failures, "total": _results.size(),
			"viewport": "%dx%d" % [VP.x, VP.y],
			"height_budget": _height_budget() if _table != null and _table.is_inside_tree() else {},
			"results": _results,
		}, "\t"))
		f.close()

func _measure(combo: Dictionary) -> void:
	var label: String = combo["label"]
	_table.game.settings.allow_follow_me = combo["follow"]
	_table.game.settings.doubles_are_trump = combo["doubles"]
	_table.game.settings.doubles_trump_reversed = combo["rev"]
	_table.trump_panel.visible = false
	await process_frame
	_table._show_trump_panel()
	for i in range(6):
		await process_frame

	_assert_fits(label)

	# Now the question step 1 exists to answer: does it still fit once the panel
	# is carrying the Back/Confirm row? Simulated with a real row of real
	# buttons rather than a spacer, so it costs what the actual controls will.
	var sim := _add_simulated_row()
	for i in range(6):
		await process_frame
	_assert_fits("%s + Back/Confirm row" % label)
	sim.queue_free()
	for i in range(4):
		await process_frame

func _add_simulated_row() -> Control:
	var trump_vbox: Control = _table.trump_panel.get_child(0)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for t in ["‹ Back", "Confirm Trump"]:
		var b := Button.new()
		b.text = t
		b.custom_minimum_size = Vector2(120, 40)
		row.add_child(b)
	trump_vbox.add_child(row)
	return row

func _assert_fits(label: String) -> void:
	var vp: Vector2 = root.get_visible_rect().size
	var hand_box: Control = _table.player_hand_container
	var hand: Rect2 = hand_box.get_global_rect()

	_check("%s: hand fully on screen" % label,
		hand.position.y >= 0.0 and hand.end.y <= vp.y,
		"hand %.0f..%.0f, viewport height %.0f (overflow %.0f)"
			% [hand.position.y, hand.end.y, vp.y, maxf(0.0, hand.end.y - vp.y)])

	# On screen is not the same as usable — the preview is pointless if the pips
	# are clipped off the bottom.
	var tiles := 0
	var tiles_visible := 0
	for c in hand_box.get_children():
		if c is DominoTile:
			tiles += 1
			if c.get_global_rect().end.y <= vp.y:
				tiles_visible += 1
	_check("%s: every hand tile fully visible" % label,
		tiles > 0 and tiles_visible == tiles, "%d of %d" % [tiles_visible, tiles])

	# The play column must stay inside the middle row's height, which the side
	# opponents' hands set. Cross it and the row grows, and the growth comes out
	# of the hand at the bottom of the window.
	var middle_row: Control = _table.play_vbox.get_parent().get_parent()
	var col_min: float = _table.play_vbox.get_combined_minimum_size().y
	var row_min: float = middle_row.get_combined_minimum_size().y
	_check("%s: play column still fits the middle row" % label,
		col_min <= row_min,
		"play_vbox min %.0f vs middle row min %.0f (headroom %.0f)"
			% [col_min, row_min, row_min - col_min])
