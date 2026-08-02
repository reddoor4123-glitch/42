extends SceneTree

# Probe for "the Call Trump screen was still up behind the Nello exchange".
#
# Question: can a picker panel abandoned mid-decision survive into the next hand?
# _start_hand() resets a dozen things but never touches bid_panel/trump_panel/
# nello_panel/nello_exchange_panel or the waiting_for_* flags, so the theory is
# that gear -> Play (a restart taken while the Call Trump screen is open) carries
# trump_panel.visible == true into the new hand.
#
# Drives the real handlers, not the flags, and measures the resulting layout
# against the viewport so the "picker pushed off the bottom" half of the report is
# demonstrated rather than assumed.
#
# Snapshots and restores user:// (see Headless_Harness_Reference.md gotcha #9).
#
# EXPECTED on stderr: "ObjectDB instances leaked at exit" — starts a real game
# whose bidding coroutine is still parked on a timer at exit. Judge the JSON.

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
var _obs: Array = []
var _sweep_cfgs: Array = []
var _sweep_i := -1
var _sweep_out: Array = []

func _note(label: String, value) -> void:
	_obs.append({"observation": label, "value": value})

func _snapshot_user_files() -> void:
	for p in TOUCHED_PATHS:
		var f = FileAccess.open(p, FileAccess.READ)
		_snapshot[p] = null if f == null else f.get_as_text()
		if f: f.close()

func _restore_user_files() -> void:
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

func _initialize() -> void:
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

func _open_pickers() -> Array:
	var t = _table
	var out: Array = []
	for p in [t.bid_panel, t.trump_panel, t.nello_panel, t.nello_exchange_panel]:
		if is_instance_valid(p) and p.visible:
			out.append(str(p.name))
	return out

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false
	if _frame == 4:
		_snapshot_user_files()
		_run_a()
		return false
	# Let the restart's deal/refresh settle and the layout re-solve.
	if _frame < 10:
		return false
	if _frame == 10:
		_run_b()
		return false
	# One sweep config per frame until the list is exhausted.
	if not _sweep_tick():
		return false
	_note("height sweep", _sweep_out)
	_restore_user_files()
	var f = FileAccess.open("res://headless/picker_panel_leak_probe_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"observations": _obs}, "\t"))
		f.close()
	quit(0)
	return true

func _run_a() -> void:
	var t = _table
	t.main_menu_panel.visible = false
	t._on_preset_chosen("teel")
	_note("game started", t.game != null)
	if t.game == null:
		return

	# Human wins the bid and the Call Trump screen opens.
	t._show_trump_panel()
	_note("pickers open after _show_trump_panel", _open_pickers())
	_note("waiting_for_trump", t.waiting_for_trump)

	# The player taps the gear and then Play, without ever calling a suit.
	# This is the exact call the Settings screen's Play button makes.
	t._restart_game_with_settings(t.game.settings)

func _run_b() -> void:
	var t = _table
	# THE QUESTION: did the abandoned Call Trump screen survive the restart?
	_note("pickers open in the NEW hand", _open_pickers())
	_note("trump_panel.visible after restart", t.trump_panel.visible)
	_note("waiting_for_trump after restart", t.waiting_for_trump)

	# Now walk the new hand into the Nello exchange, as the report describes.
	t._show_nello_exchange_panel()
	_note("pickers open once exchange opens", _open_pickers())

	# Layout consequence: is the interactive row inside the viewport?
	var vp_h = t.get_viewport().get_visible_rect().size.y
	var ex_rect = t.nello_exchange_panel.get_global_rect()
	var hand_rect = t.nello_exchange_hand_container.get_global_rect()
	_note("viewport height", vp_h)
	_note("exchange panel bottom", ex_rect.position.y + ex_rect.size.y)
	_note("exchange tile row bottom", hand_rect.position.y + hand_rect.size.y)
	_note("exchange tile row is off-screen",
		hand_rect.position.y + hand_rect.size.y > vp_h)
	_note("play_vbox height vs viewport",
		"%.0f vs %.0f" % [t.play_vbox.get_global_rect().size.y, vp_h])

	# The overflow is viewport-dependent, so sweep plausible window heights and
	# record where the exchange picker's interactive row lands — once with the
	# leaked trump_panel above it, once without, for the healthy baseline.
	for h in [520, 600, 680, 760, 840, 960]:
		_sweep_cfgs.append({"h": h, "trump": true})
		_sweep_cfgs.append({"h": h, "trump": false})

# One config per frame: measure the config applied last frame (layout has settled
# by now), then apply the next. Forcing a synchronous re-sort instead would only
# sort play_vbox itself, not the nested containers the tile row actually sits in.
func _sweep_tick() -> bool:
	var t = _table
	if _sweep_i >= 0:
		var cfg = _sweep_cfgs[_sweep_i]
		var vis_h = get_root().get_visible_rect().size.y
		var bottom = t.nello_exchange_hand_container.get_global_rect().end.y
		_sweep_out.append({
			"window_h": cfg["h"],
			"visible_h": vis_h,
			"trump_panel_leaked": cfg["trump"],
			"tile_row_bottom": bottom,
			"tile_row_offscreen": bottom > vis_h,
		})
	_sweep_i += 1
	if _sweep_i >= _sweep_cfgs.size():
		return true
	var nxt = _sweep_cfgs[_sweep_i]
	get_root().size = Vector2i(720, int(nxt["h"]))
	t.trump_panel.visible = bool(nxt["trump"])
	return false
