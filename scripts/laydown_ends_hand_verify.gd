extends SceneTree

# Regression suite for "Lay Down shows the result banner but the hand keeps
# playing underneath".
#
# The bug: _show_hand_result() drew the banner and the Next Hand button, but left
# waiting_for_human true and the human's tiles hit-testable. Tapping one ran
# _on_human_domino_pressed() and restarted the play chain on an already-resolved
# hand. Reachable from any ending that leaves tiles in hand — a lay-down claim,
# or either hand-ends-early toggle.
#
# Drives the real handlers rather than asserting on flags alone, so a future
# change that re-opens the input path fails here even if the flag survives.
#
# Snapshots and restores user:// (see Headless_Harness_Reference.md gotcha #9).
#
# EXPECTED on stderr: "ObjectDB instances leaked at exit". Unlike the other
# harnesses, this one starts a real game, which kicks off the bidding coroutine;
# that coroutine parks on a 1-second timer (DEBUG_FAST_MODE is a const and can't
# be flipped at runtime) and is still suspended when the harness exits. Benign,
# and not something free() clears. For THIS script judge the exit code and the
# results JSON, not stderr.

const BidScript = preload("res://bid.gd")

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
		if c is DominoTile:
			out.append(c)
	return out

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
	# Quitting the same frame leaves them uncollected and Godot reports leaked
	# ObjectDB instances on stderr, which these harnesses treat as failure.
	if _frame < 9:
		return false
	_restore_user_files()
	var f = FileAccess.open("res://scripts/laydown_ends_hand_verify_results.json", FileAccess.WRITE)
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

	# Put the table into the exact state a mid-hand claim happens in: a contract
	# is live, it is the human's turn, and the human still holds tiles.
	g.settings.allow_laydown = true
	g.current_bid = BidScript.new(BidScript.Type.NELLO, 1, t.human_seat)
	g.variant = BidScript.Type.NELLO
	g.trump = -1
	g.tricks_played = 2
	g.start_trick(t.human_seat)
	t.waiting_for_human = true
	t._hand_over = false
	t._highlight_legal_moves()

	var tiles := _human_tiles()
	_check("human is holding tiles mid-hand", tiles.size() > 0,
		"%d tiles" % tiles.size())
	var hand_before: int = (g.players[t.human_seat].hand as Array).size()

	# The claim.
	t._on_laydown_button_pressed()

	_check("hand is marked over", t._hand_over)
	_check("no longer waiting for a human play", t.waiting_for_human == false)
	_check("laydown button hidden", t.laydown_btn.visible == false)
	_check("result banner shown", t._hand_result_banner != null
		and is_instance_valid(t._hand_result_banner))
	_check("Next Hand button offered", t._continue_btn != null
		and is_instance_valid(t._continue_btn))

	# The actual bug: tap a tile the way a player would after the banner appears.
	# Before the fix this ran _execute_play() and the hand carried on.
	var tapped := false
	for tile in tiles:
		if is_instance_valid(tile):
			t._on_human_domino_pressed(tile)
			tapped = true
			break
	_check("a tile was available to tap", tapped)
	var hand_after: int = (g.players[t.human_seat].hand as Array).size()
	_check("tapping a tile after the banner does not play it",
		hand_after == hand_before,
		"hand went %d -> %d" % [hand_before, hand_after])
	_check("still marked over after the tap", t._hand_over)

	# Arming during an "AI turn" must not re-light the hand either — that path
	# runs whenever waiting_for_human is false, which it now always is.
	t._update_armable_highlights()
	var relit := 0
	for tile in _human_tiles():
		if tile.is_playable:
			relit += 1
	_check("armable-highlight pass does not re-light the hand", relit == 0,
		"%d tiles re-lit" % relit)

	# Dealing the next hand must clear the flag, or the table stays dead.
	t._start_hand()
	_check("next hand clears the over flag", t._hand_over == false)
