extends SceneTree
# Replay screen layout probe (July 30 2026 layout pass).
#
# Answers the one acceptance question the redesign was for: does the replay
# screen fit on a desktop-landscape window without scrolling? Reports the
# ScrollContainer's content height against its visible height — anything over
# 1.0 means a scrollbar, which is the thing being designed out.
#
# Also reports where each piece landed, so the arrangement can be checked
# without a screenshot, and grabs a PNG when a rasterizer is available.
#
# Measurement works under --headless. The screenshot does NOT — run without it
# to get the PNG, same constraint as headless/font_screenshot.gd:
#   godot --path . --script res://headless/replay_layout_probe.gd -- <out_dir>
#
# Touches user:// (starting a game reads it). Snapshots and restores; see
# Headless_Harness_Reference.md gotcha #9.

const GameSettingsScript = preload("res://game_settings.gd")
const TOUCHED_PATHS := ["user://last_used.json", "user://display_prefs.json"]

var _snapshot: Dictionary = {}
var _table: Node = null
var _frames := 0
var _out_dir := "."

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

# Six tricks of four plays, with reason strings at realistic lengths — the
# long one is what makes the bubble wrap to two lines, which is the case that
# actually threatens the height budget.
const REASONS := [
	"Leading my double — nothing left to beat it.",
	"Had to follow suit.",
	"Can't win this one — saving my count for later.",
	"Trumping in to secure this trick for us.",
]

func _fake_history(trump: int, trick_count: int) -> Array:
	var deck = Deck.new()
	deck.build_deck()
	var hands: Array = [[], [], [], []]
	for pid in range(4):
		for j in range(7):
			hands[pid].append(deck.dominoes[pid * 7 + j])

	var out: Array = []
	for t in range(trick_count):
		var states: Array = []
		for pid in range(4):
			states.append(hands[pid].duplicate())
		var plays: Array = []
		for pid in range(4):
			plays.append({
				"player": pid,
				"domino": hands[pid][0],
				"reason": REASONS[(pid + t) % REASONS.size()],
			})
		out.append({
			"trick_number": t + 1,
			"plays": plays,
			"winner_id": (t + 2) % 4,
			"points": 1,
			"hand_states": states,
			"lead_suit": trump,
			"trump": trump,
			"nello_doubles": "high",
			"doubles_trump_reversed": false,
			"own_suit_reversed": false,
		})
		for pid in range(4):
			hands[pid].remove_at(0)
	return out

func _find(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children():
		var hit = _find(c, cls)
		if hit != null:
			return hit
	return null

func _rect(label: String, n: Control) -> void:
	if n == null:
		print("  %-22s (null)" % label)
		return
	print("  %-22s pos=(%4d,%4d)  size=(%4d,%4d)%s" % [
		label, n.global_position.x, n.global_position.y, n.size.x, n.size.y,
		"" if n.visible else "   [hidden]"])

func _grab(path: String) -> void:
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("\n  (no image — run WITHOUT --headless for the screenshot)")
		return
	var err := img.save_png(path)
	print("\n  saved %s (%dx%d) err=%d" % [path, img.get_width(), img.get_height(), err])

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false

	if _frames == 4:
		_snap()
		var s = GameSettingsScript.standard_42()
		_table._set_game(Game.new(s))
		_table.game.setup_players(_table.human_seat)
		_table.game.deal_hands()
		_table.game.trump = 3
		_table.game.hand_history = _fake_history(3, 6)
		_table._show_replay()
		return false

	if _frames < 10:
		return false

	var vp: Vector2 = get_root().get_visible_rect().size
	print("\n═══ REPLAY LAYOUT PROBE ═══")
	print("viewport: %dx%d\n" % [vp.x, vp.y])

	var scroll := _find(_table.replay_panel, "ScrollContainer") as ScrollContainer
	if scroll == null:
		print("  ScrollContainer: none (removed)")
	else:
		var bar := scroll.get_v_scroll_bar()
		var content: float = bar.max_value
		var visible_h: float = scroll.size.y
		var ratio: float = content / max(visible_h, 1.0)
		print("  scroll content : %d px" % content)
		print("  scroll visible : %d px" % visible_h)
		print("  ratio          : %.3f  -> %s" % [
			ratio, "FITS, no scrollbar" if ratio <= 1.0 else "OVERFLOWS, scrollbar shows"])

	print("\n  placement:")
	_rect("inner panel", _table._replay_inner_panel)
	_rect("trick label", _table._replay_trick_label)
	_rect("partner hand", _table._replay_hand_containers[2])
	_rect("partner reason", _table._replay_bubble_labels[2])
	_rect("left opp hand", _table._replay_hand_containers[3])
	_rect("right opp hand", _table._replay_hand_containers[1])
	_rect("diamond", _table._replay_diamond)
	_rect("left opp reason", _table._replay_bubble_labels[3])
	_rect("right opp reason", _table._replay_bubble_labels[1])
	_rect("your hand", _table._replay_hand_containers[0])

	print("\n  diamond tiles (seat -> centre):")
	var d: Control = _table._replay_diamond
	for child in d.get_children():
		if child is Control and child.has_meta("replay_seat"):
			var c: Control = child
			print("    seat %d  centre=(%4d,%4d)  size=(%3d,%3d)" % [
				int(c.get_meta("replay_seat")),
				c.position.x + c.size.x * 0.5, c.position.y + c.size.y * 0.5,
				c.size.x, c.size.y])
	print("    (diamond box is %dx%d)" % [d.size.x, d.size.y])

	_grab(_out_dir + "/replay_layout.png")
	_restore()
	quit(0)
	return true
