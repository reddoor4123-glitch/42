extends SceneTree
# Walks every combination of who held the contract and who won the hand, so the
# result banner's wording is checked against the case that actually produced it
# rather than against one screenshot. Also re-measures the bid reminder, which
# just grew a font size and is a fixed-left overlay near the player's hand.
# Run WITHOUT --headless:
#   godot --path . --script res://headless/result_banner_probe.gd -- <out_dir>

const BidScript = preload("res://bid.gd")

var _fail := 0

func _init():
	root.size = Vector2i(1152, 800)
	var table = load("res://control.tscn").instantiate()
	root.add_child(table)
	for i in range(10):
		await process_frame
	table._on_preset_chosen("teel")
	for i in range(20):
		await process_frame
	var game = table.game
	game.trump = 3

	# bidder_seat, winning team, expected banner. Human is seat 0 / team 0, so
	# seats 0 and 2 are our contracts and 1 and 3 are theirs.
	var cases := [
		[0, 0, "YOU WIN THIS HAND! 🎉", "we bid and made it"],
		[2, 0, "YOU WIN THIS HAND! 🎉", "partner bid and made it"],
		[1, 0, "YOU WIN THIS HAND! 🎉", "they bid and got set"],
		[3, 0, "YOU WIN THIS HAND! 🎉", "they bid and got set"],
		[0, 1, "Hand Lost",             "we bid and went down"],
		[2, 1, "Hand Lost",             "partner bid and went down"],
		[1, 1, "They Won",              "they bid and made it"],
		[3, 1, "They Won",              "they bid and made it"],
	]
	print("=== banner wording by contract holder and hand winner ===")
	for c in cases:
		game.current_bid = BidScript.new(BidScript.Type.POINTS, 32, c[0])
		table._show_hand_result({
			"winner": c[1], "reason": "probe",
			"team_marks": [0, 0], "team_points": [21, 21],
		})
		await process_frame
		var got: String = table._hand_result_banner.text
		var ok: bool = got == c[2]
		print("  bidder seat %d, team %d wins -> %-22s %s (%s)" % [
			c[0], c[1], "\"%s\"" % got, "ok" if ok else "WRONG, wanted \"%s\"" % c[2], c[3]])
		if not ok:
			_fail += 1

	# No bid on record must not crash or claim the wrong thing.
	game.current_bid = null
	table._show_hand_result({"winner": 1, "reason": "probe", "team_marks": [0, 0]})
	await process_frame
	print("  no bid on record, we lose -> \"%s\"" % table._hand_result_banner.text)
	if table._hand_result_banner.text != "Hand Lost":
		print("    FAIL: expected the Hand Lost fallback")
		_fail += 1

	# Reminder: centred, larger, and still clear of the player's hand at the
	# longest text the game can produce.
	print("")
	print("=== bid reminder ===")
	game.current_bid = BidScript.new(BidScript.Type.POINTS, 32, 1)
	table._update_bid_reminder()
	for i in range(6):
		await process_frame
	var lbl: Label = table.bid_reminder_label
	var rem: Rect2 = lbl.get_global_rect()
	print("  text: %s" % lbl.text.replace("\n", " / "))
	print("  align=%d  font_size=%d  rect x=%.1f..%.1f y=%.1f..%.1f" % [
		lbl.horizontal_alignment, lbl.get_theme_font_size("font_size"),
		rem.position.x, rem.end.x, rem.position.y, rem.end.y])
	if lbl.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER:
		print("  FAIL: reminder text is not centred")
		_fail += 1
	var hand_left := INF
	for ch in table.player_hand_container.get_children():
		if ch is Control:
			hand_left = min(hand_left, ch.get_global_rect().position.x)
	print("  width cap %.1f | leftmost hand tile x=%.1f" % [lbl.size.x, hand_left])

	# The one contract line that cannot fit on a single line at this size. It has
	# to wrap rather than run under the hand, and the block has to stay on screen
	# once it does.
	game.active_nello_doubles_mode = "own_suit"
	game.active_nello_doubles_reversed = true
	game.current_bid = BidScript.new(BidScript.Type.NELLO, 1, 3)
	table._update_bid_reminder()
	for i in range(6):
		await process_frame
	var wrapped: Rect2 = lbl.get_global_rect()
	print("")
	print("  worst case: %s" % lbl.text.replace("
", " / "))
	print("  rect x=%.1f..%.1f y=%.1f..%.1f (%d visible lines)" % [
		wrapped.position.x, wrapped.end.x, wrapped.position.y, wrapped.end.y,
		lbl.get_line_count()])
	if wrapped.end.x > hand_left:
		print("  FAIL: still runs under the player's hand (%.1f px over)" % (wrapped.end.x - hand_left))
		_fail += 1
	else:
		print("  ok: wraps inside the cap, clear of the hand")
	if wrapped.end.y > 800.0:
		print("  FAIL: wrapped block runs %.1f px off the bottom" % (wrapped.end.y - 800.0))
		_fail += 1
	else:
		print("  ok: wrapped block stays on screen")
	if lbl.get_line_count() < 4:
		print("  note: did not need to wrap at this size")

	print("")
	print("=== %s (%d failures) ===" % ["OK" if _fail == 0 else "FAILURES", _fail])

	# Leave the table in the case this change was actually about: they held the
	# contract and made it, so the banner reads "They Won".
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		game.active_nello_doubles_mode = ""
		game.active_nello_doubles_reversed = false
		game.trump = 3
		game.current_bid = BidScript.new(BidScript.Type.POINTS, 32, 1)
		game.team_points[0] = 10
		game.team_points[1] = 32
		table._update_bid_reminder()
		table._show_hand_result({
			"winner": 1, "reason": "Met point bid of 32",
			"team_marks": [0, 1], "team_points": [10, 32],
		})
		for i in range(10):
			await process_frame
		var img: Image = root.get_texture().get_image()
		if img != null:
			img.save_png(args[0] + "/they_won.png")
			print("saved %s/they_won.png" % args[0])
	quit(0)
