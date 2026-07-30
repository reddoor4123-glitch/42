extends SceneTree

# Regression suite for "the trick lists collapse themselves every hand".
#
# _start_hand() used to force both lists shut on the grounds that an expanded
# empty list shows nothing. It now carries whatever state the player set. The
# risk in that change is geometry, not the flag: a panel left open at the end of
# a seven-trick hand must not reopen at seven tricks' height over a pile that has
# just been cleared, which is why _start_hand() re-applies the state rather than
# leaving it untouched.
#
# EXPECTED on stderr: "ObjectDB instances leaked at exit" — this harness starts a
# real game, so the bidding coroutine is still parked on a timer at exit. See
# Headless_Harness_Reference.md gotcha #10. Judge the exit code and the JSON.

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

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false
	# Phase 1 — set up and fill the open list.
	if _frame == 4:
		_snapshot_user_files()
		_run_setup()
		return false
	# Phase 2 — layout has run, so the grown panel's real `size` is now readable.
	# Measuring it in phase 1 read the pre-fill value and made the comparison in
	# phase 3 vacuous: both sides came out 128 and the assertion passed whatever
	# the code did.
	if _frame == 7:
		_record_grown_then_deal()
		return false
	# Phase 3 — layout has run again, after the deal.
	if _frame == 10:
		_run_after_layout()
		return false
	if _frame < 14:
		return false
	_restore_user_files()
	var f = FileAccess.open("res://scripts/tricks_expand_persist_verify_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"failures": _failures, "total": _results.size(), "results": _results,
		}, "\t"))
		f.close()
	quit(1 if _failures > 0 else 0)
	return true

var _grown_min := 0.0
var _grown_size := 0.0

func _run_setup() -> void:
	var t = _table
	t.main_menu_panel.visible = false
	t._on_preset_chosen("teel")
	_check("game started", t.game != null)
	if t.game == null:
		return

	# Both lists start closed.
	t._set_tricks_expanded(0, false)
	t._set_tricks_expanded(1, false)
	_check("baseline: both collapsed",
		t._tricks_expanded[0] == false and t._tricks_expanded[1] == false)

	# Open one via the real toggle handler, the way the button does.
	t._toggle_tricks_expanded(0)
	_check("toggle opens US", t._tricks_expanded[0] == true)
	_check("toggle leaves THEM alone", t._tricks_expanded[1] == false)
	_check("US button reads collapse", t._tricks_toggle_btn[0].text == "▲")
	_check("US panel visible", t._tricks_overlay[0].visible == true)

	# Fill the open list so its panel actually grows, then deal a new hand.
	# Seven full four-domino tricks: the grid is PER_ROW=4 wide with a 2-row floor,
	# so 28 dominoes is 7 rows. (Seven one-domino tricks would still be 2 rows and
	# the size assertion below would pass without proving anything.)
	for trick_no in range(7):
		var trick_dominoes: Array = []
		for j in range(4):
			trick_dominoes.append(Domino.new(trick_no % 7, j))
		t._us_tricks.add_trick_dominoes(trick_dominoes)

# Runs a frame after the fill, so the panel has actually been laid out at its
# seven-trick height before we deal the next hand out from under it.
func _record_grown_then_deal() -> void:
	var t = _table
	_grown_min = t._tricks_overlay[0].get_combined_minimum_size().y
	_grown_size = t._tricks_overlay[0].size.y
	_check("filling the list grew the panel", _grown_size > 200.0,
		"min %.0f, size %.0f" % [_grown_min, _grown_size])

	t._start_hand()

	# The state is the whole point.
	_check("US stays open across a new hand", t._tricks_expanded[0] == true)
	_check("THEM stays closed across a new hand", t._tricks_expanded[1] == false)
	_check("US button still reads collapse", t._tricks_toggle_btn[0].text == "▲")
	_check("US panel still visible", t._tricks_overlay[0].visible == true)
	_check("THEM panel still hidden", t._tricks_overlay[1].visible == false)

# Runs a frame after the deal, once layout has actually happened.
func _run_after_layout() -> void:
	var t = _table
	# The minimum tracks the cleared pile on its own — a PanelContainer follows
	# its child's minimum whatever else happens.
	var empty_min: float = t._tricks_overlay[0].get_combined_minimum_size().y
	_check("open panel's MINIMUM follows the cleared pile",
		empty_min < _grown_min,
		"min was %.0f with 7 tricks, now %.0f empty" % [_grown_min, empty_min])

	# The real size is the one that can go stale: a container grows to fit but
	# won't shrink a Control that is already larger, so without the explicit reset
	# in _set_tricks_expanded() the panel reopens at last hand's height over an
	# empty pile. This is what makes _start_hand() re-apply the state rather than
	# simply stop forcing it shut.
	var empty_size: float = t._tricks_overlay[0].size.y
	_check("open panel's actual SIZE shrinks to the cleared pile",
		empty_size < _grown_size,
		"size was %.0f with 7 tricks, now %.0f empty" % [_grown_size, empty_size])

	# Closing must still survive a deal too — the state is carried, not forced open.
	t._toggle_tricks_expanded(0)
	_check("toggle closes US again", t._tricks_expanded[0] == false)
	t._start_hand()
	_check("US stays closed across a new hand", t._tricks_expanded[0] == false)
	_check("US panel hidden after the deal", t._tricks_overlay[0].visible == false)
	_check("US button reads expand", t._tricks_toggle_btn[0].text == "▼")

	# Leaving the board must hide the overlay without forgetting the state.
	t._set_tricks_expanded(1, true)
	t._show_game_board(false)
	_check("leaving the board hides the panel", t._tricks_overlay[1].visible == false)
	_check("...but remembers it was open", t._tricks_expanded[1] == true)
	t._show_game_board(true)
	_check("returning to the board restores it", t._tricks_overlay[1].visible == true)
