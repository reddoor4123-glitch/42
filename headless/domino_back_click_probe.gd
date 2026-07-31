extends SceneTree
# Traces the domino-back swatch click path end to end, to find where a real
# click is being lost.
#
# Phases are frame-separated on purpose. Containers lay out on the frame AFTER
# their children change, so anything that reads a rect in the same frame it
# rebuilt the form is reading stale coordinates — an earlier version of this
# probe did exactly that and "clicked" at a position the button had already
# left, then reported the click lost. The bug is real but that was not evidence
# of it.
#
# Touches user:// (writes the domino-back preference). Snapshots and restores.

const TOUCHED_PATHS := ["user://display_prefs.json", "user://last_used.json"]
var _snapshot: Dictionary = {}
var _table: Node = null
var _frames := 0
var _pref_before_click := ""
var _scroll_after_scrolling := 0
var _click_pt := Vector2.ZERO

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
	print("\nuser:// restored")

func _all_nodes(node: Node, out: Array) -> void:
	out.append(node)
	for c in node.get_children():
		_all_nodes(c, out)

func _swatches() -> Array:
	var all: Array = []
	_all_nodes(_table.settings_panel, all)
	var out: Array = []
	for n in all:
		if n is Button:
			for c in n.get_children():
				if c is DominoTile:
					out.append(n)
					break
	return out

func _scroll() -> ScrollContainer:
	var all: Array = []
	_all_nodes(_table.settings_panel, all)
	for n in all:
		if n is ScrollContainer:
			return n
	return null

# The topmost mouse-accepting Control containing `pt`, ignoring clip. Compared
# against the clip rect separately below, so "geometrically there" and
# "reachable" stay distinguishable.
func _hit_stack(pt: Vector2) -> Array:
	var all: Array = []
	_all_nodes(_table.settings_panel, all)
	var stack: Array = []
	for n in all:
		if n is Control and n.is_visible_in_tree() \
				and n.mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and n.get_global_rect().has_point(pt):
			stack.append("%s" % n.get_class())
	return stack

# A motion event first: Godot's BaseButton only reacts to a press on the control
# the mouse is considered to be OVER, and a synthetic press with no prior motion
# arrives with no hover established. Without this the probe reports every click
# lost regardless of the code under test.
# Press and release are pushed on SEPARATE frames. BaseButton latches an
# internal pressed state on the down event and only emits `pressed` when the up
# arrives while still latched; feeding both in one frame does not reliably give
# it that chance, and the probe then reports a lost click for a button that is
# working. The motion event first establishes hover, which the press needs.
func _press(pt: Vector2) -> void:
	var move = InputEventMouseMotion.new()
	move.position = pt
	move.global_position = pt
	get_root().push_input(move)
	var down = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pt
	get_root().push_input(down)

func _release(pt: Vector2) -> void:
	var up = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pt
	get_root().push_input(up)

func _initialize() -> void:
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false

	match _frames:
		4:
			_snap()
			_table._show_settings_panel()
		10:
			print("\n═══ DOMINO BACK CLICK PROBE ═══")
			print("viewport: %s" % get_root().get_visible_rect().size)
			var sc := _scroll()
			print("\n── scroll viewport (the clip rect) ──")
			print("  ScrollContainer rect = %s" % sc.get_global_rect())
			print("  v_scroll value=%.0f  max=%.0f  page=%.0f" % [
				sc.get_v_scroll_bar().value, sc.get_v_scroll_bar().max_value,
				sc.get_v_scroll_bar().page])

			var sw := _swatches()
			print("\n── swatch geometry ──  (%d found)" % sw.size())
			for i in range(sw.size()):
				var b: Button = sw[i]
				var r: Rect2 = b.get_global_rect()
				var inside: bool = sc.get_global_rect().encloses(r)
				var centre_in: bool = sc.get_global_rect().has_point(r.get_center())
				print("  [%d] rect=%s" % [i, r])
				print("      fully inside clip rect: %s   centre inside: %s" % [inside, centre_in])
				if not centre_in:
					print("      ^^ CENTRE IS OUTSIDE THE SCROLL VIEWPORT — a click there")
					print("         is clipped away and never reaches the button")
				print("      hit stack at centre: %s" % str(_hit_stack(r.get_center())))
		11:
			print("\n── handler invoked directly (bypasses hit-testing) ──")
			var sw := _swatches()
			var before: String = _table._load_domino_back_pref()
			print("  pref before       : '%s'" % before)
			sw[sw.size() - 1].emit_signal("pressed")
			var after: String = _table._load_domino_back_pref()
			print("  after emit_signal : '%s'  -> %s" % [
				after, "HANDLER WORKS" if after != before else "HANDLER BROKEN"])
		14:
			# Scroll to the bottom, which is what a player has to do to see these
			# at all. THIS is the state the bug actually happens in.
			var sc := _scroll()
			sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
			_scroll_after_scrolling = sc.scroll_vertical
			print("\n── scrolled to bottom: scroll_vertical=%d ──" % _scroll_after_scrolling)
		16:
			var sc := _scroll()
			var sw := _swatches()
			for i in range(sw.size()):
				print("  [%d] rect=%s  centre inside clip: %s" % [
					i, sw[i].get_global_rect(),
					sc.get_global_rect().has_point(sw[i].get_global_rect().get_center())])
			_pref_before_click = _table._load_domino_back_pref()
			var pt: Vector2 = sw[0].get_global_rect().get_center()
			print("\n── click 1: swatch[0] at %s ──" % pt)
			print("  pref before : '%s'" % _pref_before_click)
			_click_pt = pt
			_press(pt)
		17:
			_release(_click_pt)
		19:
			var sc := _scroll()
			var after: String = _table._load_domino_back_pref()
			print("  after click : '%s'  -> %s" % [
				after, "CLICK LANDED" if after != _pref_before_click else "CLICK LOST"])
			print("  scroll now  : %d  -> %s" % [sc.scroll_vertical,
				"POSITION HELD" if sc.scroll_vertical == _scroll_after_scrolling
				else "SCROLL RESET (the bug)"])
			# The reported symptom was "it worked once and I couldn't repeat it".
			# A second click on the OTHER swatch is the actual regression test.
			var sw := _swatches()
			_pref_before_click = after
			var pt: Vector2 = sw[1].get_global_rect().get_center()
			print("\n── click 2: swatch[1] at %s (the 'couldn't repeat it' case) ──" % pt)
			_click_pt = pt
			_press(pt)
		20:
			_release(_click_pt)
		22:
			var after2: String = _table._load_domino_back_pref()
			print("  after click : '%s'  -> %s" % [
				after2, "CLICK LANDED" if after2 != _pref_before_click else "CLICK LOST"])
			_restore()
			quit(0)
			return true
	return false
