extends SceneTree

# Regression suite for "a domino you were dragging freezes on screen forever".
#
# The bug: _execute_play() calls _refresh_all_hands() after EVERY play, AI plays
# included, and that reaches _populate_hand_container(), which queue_free()s every
# tile in the human hand. The tile holding the drag is the only emitter of
# domino_drag_ended, so freeing it mid-drag meant _on_hand_drag_ended() never ran
# and _drag_ghost was never cleaned up. The ghost hangs off _bubble_overlay, which
# _build_ui() creates once per process and nothing ever clears, so it survived new
# games and settings — only closing the app removed it. Worse, the next drag
# reassigned _drag_ghost without freeing the old node, stranding it beyond any
# future cleanup: one permanently stuck tile per interrupted drag.
#
# Drives the real handlers rather than asserting on flags alone, so a future change
# that re-opens the leak fails here even if _drag_ghost itself looks tidy.
#
# Ghost counting ignores queue_free()'d nodes explicitly (is_queued_for_deletion),
# because queue_free() only lands at end of frame and every check here runs inside
# one frame.
#
# Snapshots and restores user:// (see Headless_Harness_Reference.md gotcha #9).
#
# EXPECTED on stderr: "ObjectDB instances leaked at exit" — this harness starts a
# real game, whose bidding coroutine parks on a timer that is still suspended at
# exit. Benign. Judge the exit code and the results JSON, not stderr.

const TOUCHED_PATHS := [
	"user://last_used.json",
	"user://display_prefs.json",
	"user://preset_overrides/teel.json",
	"user://slot_names.json",
	"user://custom_rulesets/Custom.json",
]
var _snapshot: Dictionary = {}
var _table: Node = null
var _frame := 0
var _results: Array = []
var _failures := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	_results.append({"test": name, "pass": ok, "detail": detail})
	if not ok:
		_failures += 1

func _snapshot_user_files() -> void:
	for p in TOUCHED_PATHS:
		var f = FileAccess.open(p, FileAccess.READ)
		_snapshot[p] = null if f == null else f.get_as_text()
		if f: f.close()

func _restore_user_files() -> void:
	var ok := true
	for p in TOUCHED_PATHS:
		var original = _snapshot.get(p, null)
		if original == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
			if FileAccess.file_exists(p): ok = false
		else:
			var f = FileAccess.open(p, FileAccess.WRITE)
			if f:
				f.store_string(original)
				f.close()
	_check("user:// save data restored", ok)

func _initialize() -> void:
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

func _human_tiles() -> Array:
	var out: Array = []
	for c in _table.player_hand_container.get_children():
		if c is DominoTile and not c.is_queued_for_deletion():
			out.append(c)
	return out

# Live ghost tiles parked on the overlay. This is the number that used to climb
# by one for every interrupted drag and never come back down.
func _ghost_count() -> int:
	var n := 0
	for c in _table._bubble_overlay.get_children():
		if c is DominoTile and not c.is_queued_for_deletion():
			n += 1
	return n

func _process(_delta: float) -> bool:
	_frame += 1
	# Phase 1 — let _ready()/_build_ui() finish.
	if _frame < 4:
		return false
	# Phase 2 — the checks.
	if _frame == 4:
		_snapshot_user_files()
		_run()
		return false
	# Phase 3 — idle so every queue_free() the run triggered actually lands.
	if _frame < 9:
		return false
	_restore_user_files()
	var f = FileAccess.open("res://headless/drag_ghost_cancel_verify_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"failures": _failures, "total": _results.size(), "results": _results,
		}, "\t"))
		f.close()
	# quit() carries the exit code; returning true from _process always exits 0,
	# which would report a failing suite as a clean run.
	quit(1 if _failures > 0 else 0)
	return true

func _run() -> void:
	var t = _table
	t.main_menu_panel.visible = false
	t._on_preset_chosen("teel")
	var g = t.game
	_check("game started", g != null)
	if g == null:
		return
	_check("bubble overlay exists", t._bubble_overlay != null)
	if t._bubble_overlay == null:
		return

	# ── 1. The reported bug: an AI play lands mid-drag ───────────────────────
	var tiles = _human_tiles()
	_check("human hand populated", tiles.size() > 0, "tiles=%d" % tiles.size())
	if tiles.is_empty():
		return

	t._on_hand_drag_started(tiles[0])
	_check("drag start creates a ghost", is_instance_valid(t._drag_ghost))
	_check("ghost is parented to the overlay",
		is_instance_valid(t._drag_ghost) and t._drag_ghost.get_parent() == t._bubble_overlay)
	_check("exactly one ghost while dragging", _ghost_count() == 1, "count=%d" % _ghost_count())

	# Exactly what _execute_play() does after any play, AI turns included.
	t._refresh_all_hands()
	_check("hand rebuild clears the ghost reference", t._drag_ghost == null)
	_check("hand rebuild leaves no ghost on the overlay",
		_ghost_count() == 0, "count=%d" % _ghost_count())

	# The release still arrives, from a tile that no longer exists in the hand.
	# It must not crash and must not reorder against stale sibling positions.
	var order_before = g.players[t.human_seat].hand.duplicate()
	t._on_hand_drag_ended(tiles[0], true)
	_check("late release after cancel does not reorder",
		g.players[t.human_seat].hand == order_before)
	_check("late release leaves no ghost", _ghost_count() == 0, "count=%d" % _ghost_count())

	# ── 2. Ghosts can never accumulate ───────────────────────────────────────
	# Pre-fix, each interrupted drag stranded one more node on the overlay.
	for i in range(5):
		var live = _human_tiles()
		if live.is_empty():
			break
		t._on_hand_drag_started(live[0])
		t._refresh_all_hands()   # interrupt, every time
	_check("five interrupted drags strand nothing",
		_ghost_count() == 0, "count=%d" % _ghost_count())

	# Back-to-back drag starts with no end in between must not orphan either.
	var live2 = _human_tiles()
	if live2.size() >= 2:
		t._on_hand_drag_started(live2[0])
		t._on_hand_drag_started(live2[1])
		_check("restarting a drag frees the previous ghost",
			_ghost_count() == 1, "count=%d" % _ghost_count())
		t._on_hand_drag_ended(live2[1], false)
		_check("cancelled drag cleans up", _ghost_count() == 0, "count=%d" % _ghost_count())

	# ── 3. Regression: an uninterrupted drag still reorders ──────────────────
	var tiles3 = _human_tiles()
	_check("hand still populated for reorder test", tiles3.size() >= 2,
		"tiles=%d" % tiles3.size())
	if tiles3.size() >= 2:
		var moved = tiles3[0].domino
		var expected = g.players[t.human_seat].hand.duplicate()
		expected.erase(moved)
		expected.append(moved)   # dropped past every sibling → lands last
		t._on_hand_drag_started(tiles3[0])
		# Park the ghost well right of the last tile so the drop index is
		# unambiguous regardless of headless layout metrics.
		var last = tiles3[tiles3.size() - 1]
		t._drag_ghost.global_position = Vector2(
			last.global_position.x + last.size.x + 500.0, last.global_position.y)
		t._on_hand_drag_ended(tiles3[0], true)
		_check("uninterrupted drag reorders the hand",
			g.players[t.human_seat].hand == expected,
			"got=%s" % str(g.players[t.human_seat].hand))
		_check("completed drag leaves no ghost", _ghost_count() == 0,
			"count=%d" % _ghost_count())
