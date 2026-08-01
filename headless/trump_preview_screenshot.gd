extends SceneTree
# Renders the Call Trump screen mid-preview so the pip highlighting can be
# judged by eye — how strong a suit looks is the whole point of the feature and
# no assertion can tell you that. Also grabs the reopened bid panel, where the
# thing to check by eye is that it reads as changing a contract rather than as a
# fresh auction.
#
# Must run WITHOUT --headless (needs a real rasterizer), same as the other
# *_screenshot.gd harnesses:
#   godot --path . --script res://headless/trump_preview_screenshot.gd -- <out_dir>
#
# Touches user:// (starting a game reads it). Snapshots and restores.

const BidScript = preload("res://bid.gd")
const DominoScript = preload("res://domino.gd")
const TOUCHED_PATHS := ["user://last_used.json", "user://display_prefs.json"]

var _snapshot: Dictionary = {}

func _snap() -> void:
	for p in TOUCHED_PATHS:
		var f = FileAccess.open(p, FileAccess.READ)
		_snapshot[p] = null if f == null else f.get_as_text()
		if f: f.close()

func _restore() -> void:
	for p in TOUCHED_PATHS:
		var original = _snapshot.get(p, null)
		if original == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var f = FileAccess.open(p, FileAccess.WRITE)
			if f:
				f.store_string(original)
				f.close()
	print("user:// restored")

func _grab(table, path: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("  (no image — renderer unavailable; are you running with --headless?)")
		return
	img.save_png(path)
	print("  saved %s" % path)

func _init():
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://"
	_snap()

	root.size = Vector2i(1152, 800)
	var table = load("res://control.tscn").instantiate()
	root.add_child(table)
	for i in range(10):
		await process_frame

	table.main_menu_panel.visible = false
	table._on_preset_chosen("standard")
	for i in range(20):
		await process_frame

	table.game.settings.allow_follow_me = true
	table.game.settings.doubles_are_trump = true
	table.game.settings.doubles_trump_reversed = true
	table.game.current_bid = BidScript.new(BidScript.Type.POINTS, 32, table.human_seat)
	table.bid_panel.visible = false
	table._show_trump_panel()
	for i in range(8):
		await process_frame

	# Strongest NUMERIC suit for the contrast shot. Blanks is shot explicitly
	# rather than opportunistically — it is the case the divider bar exists for,
	# and leaving it to whatever the deal happens to favour means the interesting
	# screenshot only appears sometimes.
	var counts := {}
	for d in table.game.players[table.human_seat].hand:
		for pip in [d.left, d.right]:
			counts[pip] = int(counts.get(pip, 0)) + 1
	var best := 1
	for pip in counts:
		if int(pip) > 0 and int(counts[pip]) > int(counts.get(best, 0)):
			best = int(pip)
	print("hand holds %d blanks; strongest numeric suit is %d (%d)"
		% [int(counts.get(0, 0)), best, int(counts.get(best, 0))])

	print("nothing previewed yet:")
	await _grab(table, out_dir + "/01_trump_no_preview.png")

	table._on_trump_previewed(0, false)
	for i in range(4):
		await process_frame
	print("previewing BLANKS — no pips to redden, so the bar carries it:")
	await _grab(table, out_dir + "/02_trump_preview_blanks.png")

	table._on_trump_previewed(best, false)
	for i in range(4):
		await process_frame
	print("previewing suit %d (pips and bar together):" % best)
	await _grab(table, out_dir + "/02b_trump_preview_suit.png")

	table._on_trump_previewed(DominoScript.DOUBLES_TRUMP, false)
	for i in range(4):
		await process_frame
	print("previewing doubles (the case that used to highlight nothing):")
	await _grab(table, out_dir + "/03_trump_preview_doubles.png")

	# The reopened bid panel, entered the way a player reaches it.
	table._human_bid_position = 1
	table._bid_before_human = BidScript.new(BidScript.Type.POINTS, 31, 1)
	table._open_bid_revisit("trump")
	for i in range(6):
		await process_frame
	print("bid reopened from the trump screen:")
	await _grab(table, out_dir + "/04_bid_revisit.png")

	_restore()
	quit(0)
