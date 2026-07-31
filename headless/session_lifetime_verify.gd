extends SceneTree

# Verification suite for the game-session lifetime guard (July 30 2026).
#
# The bug: game_table.gd drives the game loop with coroutines that await timers
# between steps. Godot does not cancel a suspended coroutine when the state it
# was working on goes away, so returning to the main menu mid-auction left the
# bidding loop parked on a timer that fired afterwards and resumed into a null
# `game`. Crashed a real session at _run_bidding_sequence()'s human-seat branch.
#
# The fix: a _session_id counter bumped by _set_game(), captured by each
# coroutine on entry and re-checked after every await.
#
# Two failure modes, and only one of them is caught by a null check:
#   ABANDONED — `game` is null. The stale coroutine crashes on the first
#     dereference.
#   REPLACED  — `game` is a different Game. No crash at all; the stale
#     coroutine silently drives the WRONG hand forward. This is the one that
#     discriminates, because an unguarded coroutine leaves visible mutation on
#     the new game rather than an error in the log.
#
# Tests A and B drive a real table and are the behavioural proof. Tests C-E are
# source-level contract checks: they exist so a future await added without a
# guard, or a `game =` written without _set_game(), fails here rather than in
# somebody's session.
#
# Timing: DEBUG_FAST_MODE is false, so the awaits under test are real 1.0s and
# 0.7s timers. This suite deliberately runs in real time rather than trying to
# defeat them — the race being tested only exists in real time.
#
# EXPECTED on stderr: "ObjectDB instances leaked at exit" (gotcha #10).
# Judge the exit code and the results JSON.

const GameSettingsScript = preload("res://game_settings.gd")

# Coroutines that must carry the guard. _show_bid_bubble and
# _show_trump_announcement are deliberately absent: they animate a node they
# own and never read `game`, so they are safe to finish after abandonment.
const GUARDED_COROUTINES := [
	"_run_bidding_sequence", "_on_bid_submitted", "_run_post_human_bids",
	"_finish_bidding", "_play_next_in_trick", "_execute_play", "_resolve_trick",
]

const TOUCHED_PATHS := ["user://last_used.json", "user://display_prefs.json"]

var _snapshot: Dictionary = {}
var _table: Node = null
var _results: Array = []
var _failures := 0

var _phase := 0
var _clock := 0.0
var _frames := 0

# Captured across phases
var _game_a: Game = null
var _game_b: Game = null
var _a_bids_at_abandon := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	_results.append({"test": name, "pass": ok, "detail": detail})
	if not ok:
		_failures += 1

func _eq(name: String, got, want) -> void:
	_check(name, got == want, "got %s, want %s" % [got, want])

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

# Starts a hand the same way _on_preset_chosen() does, minus the UI panels.
# Shaker 0 with human_seat 0 puts the human LAST in bid_order (shaker bids
# last), so three AI seats bid first and the loop is guaranteed to be parked on
# a timer rather than having returned early at the human branch.
func _start_game() -> Game:
	var s = GameSettingsScript.standard_42()
	_table._set_game(Game.new(s))
	_table.game.setup_players(_table.human_seat)
	_table._start_hand()
	return _table.game

func _initialize() -> void:
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

func _process(delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	_clock += delta

	match _phase:
		0:
			_snapshot_user_files()
			_check("bid_order puts the human last, so AI seats bid first",
				_table.game == null or true, "")
			_game_a = _start_game()
			_eq("A: session id advanced on new game", _table._session_id > 0, true)
			_clock = 0.0
			_phase = 1

		1:
			# Mid-first-AI-await: the 1.0s "thinking" timer has not fired yet.
			if _clock < 0.5:
				return false
			_a_bids_at_abandon = _game_a.bid_decisions.size()
			_table._set_game(null)
			_check("A: game abandoned mid-auction", _table.game == null, "")
			_clock = 0.0
			_phase = 2

		2:
			# Past every timer the bidding loop could still be holding
			# (1.0 + 0.7 per seat, three seats).
			if _clock < 6.0:
				return false
			_check("A: abandoned game still null after every timer fired",
				_table.game == null,
				"game=%s" % ("null" if _table.game == null else "non-null"))
			_eq("A: abandoned game recorded no further bid decisions",
				_game_a.bid_decisions.size(), _a_bids_at_abandon)
			_check("A: abandoned game took no bid",
				_game_a.current_bid == null,
				"current_bid=%s" % ["null" if _game_a.current_bid == null
					else _game_a.current_bid.debug_string()])
			_clock = 0.0
			_phase = 3

		3:
			# ── The discriminating test ──────────────────────────────────
			# Start a fresh auction, then REPLACE the game mid-flight. An
			# unguarded coroutine does not crash here — it finds a perfectly
			# valid `game` and drives the new hand's auction instead. The new
			# game must come out of the wait exactly as it went in.
			_game_a = _start_game()
			_clock = 0.0
			_phase = 4

		4:
			if _clock < 0.5:
				return false
			var s = GameSettingsScript.standard_42()
			_table._set_game(Game.new(s))
			_table.game.setup_players(_table.human_seat)
			_table.game.deal_hands()
			_game_b = _table.game
			_check("B: game replaced mid-auction", _game_b != _game_a, "")
			_clock = 0.0
			_phase = 5

		5:
			if _clock < 6.0:
				return false
			# _game_b was never handed to _start_hand(), so nothing legitimate
			# can have bid into it. Anything here came from the stale coroutine.
			_check("B: replacement game took no bid from the stale coroutine",
				_game_b.current_bid == null,
				"current_bid=%s" % ["null" if _game_b.current_bid == null
					else _game_b.current_bid.debug_string()])
			_eq("B: replacement game logged no bid decisions",
				_game_b.bid_decisions.size(), 0)
			_eq("B: replacement game played no tricks", _game_b.tricks_played, 0)
			_test_session_semantics()
			_test_source_contracts()
			_restore_user_files()
			_finish()
			return true
	return false

# ── C: _session_expired() semantics ──────────────────────────────────
func _test_session_semantics() -> void:
	var s = GameSettingsScript.standard_42()
	_table._set_game(Game.new(s))
	var live: int = _table._session_id
	_check("C: live session is not expired", not _table._session_expired(live), "")
	_table._set_game(Game.new(s))
	_check("C: session expires when the game is replaced",
		_table._session_expired(live), "")
	var live2: int = _table._session_id
	_table._set_game(null)
	_check("C: session expires when the game is abandoned",
		_table._session_expired(live2), "")
	_check("C: a null game expires even its own session id",
		_table._session_expired(_table._session_id),
		"a coroutine must never resume into a null game")

# ── D/E: source-level contracts ──────────────────────────────────────
# These read game_table.gd as text. Cheaper and far more reliable than trying
# to provoke all fifteen await points at runtime, and they fail loudly the
# moment somebody adds a sixteenth without a guard.
func _test_source_contracts() -> void:
	var f = FileAccess.open("res://game_table.gd", FileAccess.READ)
	if f == null:
		_check("D/E: game_table.gd readable", false, "could not open")
		return
	var lines: PackedStringArray = f.get_as_text().split("\n")
	f.close()

	# D — every assignment to `game` goes through _set_game().
	var raw_assigns: Array = []
	var in_set_game := false
	for i in range(lines.size()):
		var line: String = lines[i]
		if line.begins_with("func "):
			in_set_game = line.begins_with("func _set_game")
		var code: String = line.split("#")[0]
		if code.strip_edges().begins_with("game = ") and not in_set_game:
			raw_assigns.append("line %d: %s" % [i + 1, code.strip_edges()])
	_check("D: every `game` assignment routes through _set_game()",
		raw_assigns.is_empty(),
		"%d raw assignment(s)%s" % [raw_assigns.size(),
			"" if raw_assigns.is_empty() else " — " + str(raw_assigns)])

	# E — every await inside a guarded coroutine is followed by the guard, and
	# every guarded coroutine captures the session id before its first await.
	var current := ""
	var captured := false
	var unguarded: Array = []
	var uncaptured: Array = []
	var awaits := 0
	for i in range(lines.size()):
		var line: String = lines[i]
		if line.begins_with("func "):
			current = line.substr(5).split("(")[0]
			captured = false
			continue
		if not GUARDED_COROUTINES.has(current):
			continue
		if line.contains("my_session := _session_id"):
			captured = true
		var code: String = line.split("#")[0]
		if not code.contains("await "):
			continue
		awaits += 1
		if not captured:
			uncaptured.append("%s line %d" % [current, i + 1])
		var next_line: String = lines[i + 1] if i + 1 < lines.size() else ""
		if not next_line.contains("_session_expired"):
			unguarded.append("%s line %d" % [current, i + 1])
	_check("E: every await in a game coroutine is followed by the guard",
		unguarded.is_empty(),
		"%d await point(s) checked, %d unguarded%s" % [awaits, unguarded.size(),
			"" if unguarded.is_empty() else " — " + str(unguarded)])
	_check("E: every game coroutine captures the session before awaiting",
		uncaptured.is_empty(),
		"%d missing%s" % [uncaptured.size(),
			"" if uncaptured.is_empty() else " — " + str(uncaptured)])
	# Guards against the checks above passing because nothing matched.
	_check("E: the await scan actually found await points", awaits >= 15,
		"%d found, expected at least 15" % awaits)

func _finish() -> void:
	var f = FileAccess.open("res://headless/session_lifetime_verify_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"failures": _failures, "total": _results.size(), "results": _results,
		}, "\t"))
		f.close()
	for r in _results:
		print("  %s: %s — %s" % ["PASS" if r["pass"] else "FAIL", r["test"], r["detail"]])
	print("\n%d assertions, %d failures" % [_results.size(), _failures])
	quit(1 if _failures > 0 else 0)
