extends SceneTree

# Verification harness for the Menu / Rules / Settings merge (spec v2, §5).
#
# Covers the parts that are testable without a human at the screen: difficulty
# normalization at every read shape, the AI_MODES eager-default fix, from_dict's
# forced Sevens rule, per-preset difficulty defaults, slot resolution isolation,
# slot-name independence from rules content, and the domino-back preference's
# independence from preset_id.
#
# Writes into user:// — the caller is expected to have backed that up.
# Follows Headless_Harness_Reference.md conventions (results to JSON, stdout
# redirected by the caller).

const GameSettingsScript = preload("res://game_settings.gd")
const AIPlayer = preload("res://ai_player.gd")
const BidScript = preload("res://bid.gd")

var _results: Array = []
var _failures := 0

# Every user:// path this harness writes or deletes, snapshotted before the run
# and put back after. user:// in a headless run IS the live save directory (see
# Headless_Harness_Reference.md gotcha #9) — an earlier version of this file
# wrote and then deleted preset_overrides/teel.json to test that a rules reset
# preserves a custom name, and destroyed a real ruleset override doing it.
const TOUCHED_PATHS := [
	"user://last_used.json",
	"user://slot_names.json",
	"user://display_prefs.json",
	"user://preset_overrides/teel.json",
	"user://preset_overrides/tournament.json",
	"user://preset_overrides/custom.json",
	"user://custom_rulesets/Custom.json",
]
var _snapshot: Dictionary = {}   # path -> String contents, or null if absent

func _snapshot_user_files() -> void:
	for path in TOUCHED_PATHS:
		var f = FileAccess.open(path, FileAccess.READ)
		if f == null:
			_snapshot[path] = null
		else:
			_snapshot[path] = f.get_as_text()
			f.close()

func _restore_user_files() -> void:
	for path in TOUCHED_PATHS:
		var original = _snapshot.get(path, null)
		if original == null:
			# Wasn't there before — make sure the harness didn't leave one behind.
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var f = FileAccess.open(path, FileAccess.WRITE)
			if f:
				f.store_string(original)
				f.close()
	_check("user:// save data restored", _verify_restored())

func _verify_restored() -> bool:
	for path in TOUCHED_PATHS:
		var expected = _snapshot.get(path, null)
		var f = FileAccess.open(path, FileAccess.READ)
		if expected == null:
			if f != null:
				f.close()
				return false
		else:
			if f == null:
				return false
			var got := f.get_as_text()
			f.close()
			if got != expected:
				return false
	return true

func _check(name: String, ok: bool, detail: String = "") -> void:
	_results.append({"test": name, "pass": ok, "detail": detail})
	if not ok:
		_failures += 1

func _write_json(path: String, d: Dictionary) -> void:
	var dir = DirAccess.open("user://")
	if dir:
		dir.make_dir(path.get_base_dir().replace("user://", ""))
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, "\t"))
		f.close()

func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# ── 1. normalize_difficulty at every value shape ───────────────────────────────
func _test_normalize() -> void:
	var cases := {
		"standard": "expert",   # retired middle tier
		"beginner": "casual",   # pre-rename spelling
		"casual":   "casual",
		"expert":   "expert",
		"":         "expert",   # missing/blank
		"nonsense": "expert",   # hand-edited file
	}
	for input in cases:
		var got: String = GameSettingsScript.normalize_difficulty(input)
		_check("normalize(%s) -> %s" % [input if input != "" else "<empty>", cases[input]],
			got == cases[input], "got %s" % got)

# ── 2. AI_MODES shape + the eager-default fix ─────────────────────────────────
func _test_ai_modes() -> void:
	_check("AI_MODES has no 'standard' key", not AIPlayer.AI_MODES.has("standard"))
	_check("AI_MODES has 'casual'", AIPlayer.AI_MODES.has("casual"))
	_check("AI_MODES has 'expert'", AIPlayer.AI_MODES.has("expert"))
	_check("AI_MODES has exactly 2 tiers", AIPlayer.AI_MODES.size() == 2,
		"size %d" % AIPlayer.AI_MODES.size())

	# Casual must carry the old Beginner numbers verbatim (spec §4: no numeric
	# changes), Expert unchanged.
	var casual = AIPlayer.AI_MODES.get("casual", {})
	_check("casual keeps beginner's numbers",
		casual.get("risk_bias") == -0.25 and casual.get("max_overbid") == 2
		and casual.get("vigilance") == "none" and casual.get("opportunism") == 0.0,
		str(casual))
	var expert = AIPlayer.AI_MODES.get("expert", {})
	_check("expert numbers unchanged",
		expert.get("risk_bias") == 0.25 and expert.get("max_overbid") == 6
		and expert.get("vigilance") == "full" and expert.get("opportunism") == 1.0,
		str(expert))

# ── 3. A real bid/play cycle at each tier, plus a stale "standard" ────────────
# This is the test that would have caught the eager-default-argument trap: the
# AI_MODES.get() fallback is evaluated on every call, so a missing key throws
# regardless of what `difficulty` holds.
func _test_bid_play_cycle() -> void:
	for difficulty in ["casual", "expert", "standard"]:
		var game = Game.new(GameSettingsScript.standard_42())
		game.setup_players(0)
		game.deal_hands()

		var bid_decisions: Array = []
		var bid = AIPlayer.decide_bid(game.players[1].hand, 1, null, game.settings,
			false, difficulty, bid_decisions, 0, 0)
		_check("decide_bid survives difficulty=%s" % difficulty, bid != null,
			"returned null")

		var fixed = BidScript.new(BidScript.Type.POINTS, 30, 0)
		game.current_bid = fixed
		game.apply_bid_result(6)
		game.start_trick(0)

		var player = game.players[game.current_player]
		var legal = game.get_legal_moves(player)
		var reason_log: Array = []
		var frame = PublicFrame.new(game.hand_history, game.current_trick)
		var knowledge = PublicKnowledge.from_state(frame)
		var chosen = AIPlayer.decide_play(
			legal, player.hand, game.current_trick,
			player.id, (player.id + 2) % 4, game.trump, reason_log,
			difficulty, false, game.variant,
			game.current_bid.player_id, knowledge,
			game.team_points, game.current_bid.value
		)
		_check("decide_play survives difficulty=%s" % difficulty, chosen != null,
			"returned null")

# ── 4. from_dict: difficulty migration + forced Sevens ────────────────────────
func _test_from_dict() -> void:
	var stale = GameSettingsScript.to_dict(GameSettingsScript.standard_42())
	stale["ai_difficulty"] = "standard"
	stale["sevens_require_seven_in_hand"] = false
	var loaded = GameSettingsScript.from_dict(stale)
	_check("from_dict migrates 'standard' -> expert", loaded.ai_difficulty == "expert",
		"got %s" % loaded.ai_difficulty)
	_check("from_dict forces sevens_require_seven_in_hand true",
		loaded.sevens_require_seven_in_hand == true, "got false")

	# from_dict no longer reads ai_difficulty at all — ruleset files stopped
	# carrying it when difficulty was reclassified as player state. Whatever a
	# file says must not survive deserialization; _resolve_settings_for_slot()
	# supplies the value instead.
	stale["ai_difficulty"] = "casual"
	var from_legacy_file := GameSettingsScript.from_dict(stale)
	_check("from_dict ignores a file's ai_difficulty entirely",
		from_legacy_file.ai_difficulty == GameSettings.new().ai_difficulty,
		"got '%s' — from_dict should leave the field at its declared default"
			% from_legacy_file.ai_difficulty)

# ── 5. Per-preset difficulty defaults (spec §3.1) ─────────────────────────────
func _test_preset_defaults() -> void:
	var expected := {
		"teel": "casual", "standard": "casual",
		"tournament": "expert", "lechner": "expert",
	}
	var fns := {
		"teel": GameSettingsScript.teel_rules(),
		"standard": GameSettingsScript.standard_42(),
		"tournament": GameSettingsScript.tournament_rules(),
		"lechner": GameSettingsScript.lechner_hall(),
	}
	for key in expected:
		var s: GameSettings = fns[key]
		_check("%s defaults to %s" % [key, expected[key]],
			s.ai_difficulty == expected[key], "got %s" % s.ai_difficulty)

# ── 6-8. Live-node tests: slot resolution, names, domino back ─────────────────
# These call game_table.gd's own helpers on a real instance rather than
# reimplementing them, so a drift between test and production can't hide.
func _test_with_table() -> void:
	var table = _table
	# Proof the node is actually live, not just constructed: adding a scene to
	# the root does not run _ready() until the main loop turns a frame, and an
	# un-readied game_table has null UI members and a null viewport. See the
	# _initialize()/_process() structure at the bottom of this file.
	_check("game_table is readied (UI built, viewport resolved)",
		table.settings_panel != null and table.get_viewport() != null,
		"settings_panel=%s viewport=%s" % [
			"null" if table.settings_panel == null else "ok",
			"null" if table.get_viewport() == null else "ok"])

	# ── Slot isolation (§5): each switch must fully re-resolve. Give one slot a
	# distinctive saved override, then confirm switching away and back doesn't
	# leak either direction.
	_write_json("user://preset_overrides/tournament.json", {
		"minimum_bid": 41, "marks_to_win": 3, "allow_plunge": true,
	})
	var tourn: GameSettings = table._resolve_settings_for_slot("tournament")
	_check("slot loads its saved override", tourn.minimum_bid == 41 and tourn.marks_to_win == 3,
		"min_bid=%d marks=%d" % [tourn.minimum_bid, tourn.marks_to_win])
	_check("resolved slot re-stamps preset_id", tourn.preset_id == "tournament",
		"got '%s'" % tourn.preset_id)

	var lech: GameSettings = table._resolve_settings_for_slot("lechner")
	_check("switching slots does not leak minimum_bid", lech.minimum_bid != 41,
		"leaked 41 into lechner")
	_check("switching slots does not leak marks_to_win", lech.marks_to_win != 3,
		"leaked 3 into lechner")
	_check("lechner re-stamps its own preset_id", lech.preset_id == "lechner",
		"got '%s'" % lech.preset_id)

	# Switching back must still see the override, not the mutated neighbour.
	var tourn2: GameSettings = table._resolve_settings_for_slot("tournament")
	_check("switching back re-reads from disk", tourn2.minimum_bid == 41,
		"got %d" % tourn2.minimum_bid)
	_check("re-resolve returns a fresh object", not is_same(tourn, tourn2))
	_rm("user://preset_overrides/tournament.json")

	# ── Custom slot: key shape and storage location (§5) ──────────────────────
	_check("CUSTOM_SLOT_KEY is 'custom:Custom'", table.CUSTOM_SLOT_KEY == "custom:Custom",
		"got '%s'" % table.CUSTOM_SLOT_KEY)
	_check("SLOT_KEYS has exactly 5 entries", table.SLOT_KEYS.size() == 5,
		"got %d" % table.SLOT_KEYS.size())
	_check("Custom is not in BUILTIN_PRESET_KEYS (so Reset stays hidden)",
		not table.BUILTIN_PRESET_KEYS.has(table.CUSTOM_SLOT_KEY))

	_rm("user://custom_rulesets/Custom.json")
	var fresh_custom: GameSettings = table._resolve_settings_for_slot(table.CUSTOM_SLOT_KEY)
	var baseline = GameSettingsScript.standard_42()
	_check("unsaved Custom seeds from Standard 42",
		fresh_custom.minimum_bid == baseline.minimum_bid
		and fresh_custom.allow_splash == baseline.allow_splash
		and fresh_custom.nello_doubles_mode == baseline.nello_doubles_mode)
	_check("Custom re-stamps its key", fresh_custom.preset_id == table.CUSTOM_SLOT_KEY,
		"got '%s'" % fresh_custom.preset_id)

	# Persist it and confirm it lands in custom_rulesets/, not preset_overrides/.
	fresh_custom.minimum_bid = 35
	table._persist_preset_tweaks(fresh_custom)
	_check("Custom persists to custom_rulesets/Custom.json",
		FileAccess.file_exists("user://custom_rulesets/Custom.json"))
	_check("Custom did NOT create preset_overrides/custom.json",
		not FileAccess.file_exists("user://preset_overrides/custom.json"))
	var reloaded: GameSettings = table._resolve_settings_for_slot(table.CUSTOM_SLOT_KEY)
	_check("Custom reloads its own saved state", reloaded.minimum_bid == 35,
		"got %d" % reloaded.minimum_bid)

	# ── Slot names independent of rules content (§5) ──────────────────────────
	_rm(table.SLOT_NAMES_PATH)
	_check("slot name defaults to built-in label",
		table._slot_display_name("teel") == "Teel Rules",
		"got '%s'" % table._slot_display_name("teel"))
	table._set_slot_display_name("teel", "Grandma's Rules")
	_check("rename persists", table._slot_display_name("teel") == "Grandma's Rules",
		"got '%s'" % table._slot_display_name("teel"))
	_check("rename does not touch other slots",
		table._slot_display_name("standard") == "Standard 42")

	# Reset-to-Default's rules half: deleting the override must leave the name.
	_write_json("user://preset_overrides/teel.json", {"minimum_bid": 42})
	_rm("user://preset_overrides/teel.json")
	_check("deleting rules override preserves a custom name",
		table._slot_display_name("teel") == "Grandma's Rules",
		"got '%s'" % table._slot_display_name("teel"))
	# ...and the opt-in half restores the label.
	table._reset_slot_display_name("teel")
	_check("explicit name reset restores built-in label",
		table._slot_display_name("teel") == "Teel Rules",
		"got '%s'" % table._slot_display_name("teel"))

	# ── Domino back independent of preset_id (§5) ────────────────────────────
	_rm(table.DISPLAY_PREFS_PATH)
	_check("no back preference by default", table._load_domino_back_pref() == "")
	table._save_domino_back_pref("res://art/domino_back_teel.png")
	# Resolve a non-Teel slot, which under the old preset_id inference would have
	# cleared the texture.
	table._resolve_settings_for_slot("lechner")
	table._update_domino_back_texture()
	_check("chosen back survives switching to a non-Teel slot",
		table._load_domino_back_pref() == "res://art/domino_back_teel.png"
		and DominoTile.custom_back_texture != null,
		"pref='%s' texture=%s" % [table._load_domino_back_pref(),
			"set" if DominoTile.custom_back_texture != null else "null"])
	table._save_domino_back_pref("")
	table._update_domino_back_texture()
	_check("Default back clears the texture even on the Teel slot",
		DominoTile.custom_back_texture == null)

	# ── Single-source-of-truth invariants ────────────────────────────────────
	# SLOT_KEYS and BUILTIN_PRESET_KEYS can't be derived from one another (GDScript
	# rejects array concatenation in a const expression), so assert the
	# relationship instead of letting the two lists drift apart silently.
	var expected_slots: Array = []
	expected_slots.append_array(table.BUILTIN_PRESET_KEYS)
	expected_slots.append(table.CUSTOM_SLOT_KEY)
	_check("SLOT_KEYS == BUILTIN_PRESET_KEYS + [CUSTOM_SLOT_KEY]",
		Array(table.SLOT_KEYS) == expected_slots,
		"%s vs %s" % [table.SLOT_KEYS, expected_slots])

	# Every slot needs a label, a blurb, and resolvable rules — a new slot added
	# to SLOT_KEYS without its companion dictionary entries should fail here
	# rather than render a button captioned with its raw key.
	for key in table.SLOT_KEYS:
		_check("slot '%s' has a default name" % key,
			table.SLOT_DEFAULT_NAMES.has(key))
		_check("slot '%s' has a blurb" % key, table.SLOT_BLURBS.has(key))
		var resolved: GameSettings = table._resolve_settings_for_slot(key)
		_check("slot '%s' resolves and stamps itself" % key,
			resolved != null and resolved.preset_id == key)
		_check("slot '%s' resolves a valid difficulty" % key,
			AIPlayer.AI_MODES.has(resolved.ai_difficulty),
			"got '%s'" % resolved.ai_difficulty)

	# _slot_file_path is the only thing that should know the custom/built-in split.
	_check("built-in slot path lands in preset_overrides",
		table._slot_file_path("teel") == "user://preset_overrides/teel.json",
		table._slot_file_path("teel"))
	_check("custom slot path lands in custom_rulesets",
		table._slot_file_path(table.CUSTOM_SLOT_KEY) == "user://custom_rulesets/Custom.json",
		table._slot_file_path(table.CUSTOM_SLOT_KEY))

	# ── Ownership: ruleset files hold rule content only ──────────────────────
	var serialized := GameSettingsScript.to_dict(GameSettingsScript.teel_rules())
	_check("to_dict omits ai_difficulty (player state, not rule content)",
		not serialized.has("ai_difficulty"))
	_check("to_dict omits preset_id (identity, not content)",
		not serialized.has("preset_id"))

	# A pre-existing file that still carries ai_difficulty must not be able to
	# dictate the session's difficulty.
	var legacy := GameSettingsScript.to_dict(GameSettingsScript.tournament_rules())
	legacy["ai_difficulty"] = "casual"
	_write_json("user://preset_overrides/tournament.json", legacy)
	_write_json("user://last_used.json", {"last_preset": "tournament"})
	_check("a legacy ai_difficulty in a ruleset file is ignored",
		table._resolve_settings_for_slot("tournament").ai_difficulty == "expert",
		"tournament's shipped seed is expert; the file said casual")
	# ...while the slot's shipped seed still applies when nothing is committed.
	_check("shipped seed applies when no difficulty is committed",
		table._resolve_settings_for_slot("teel").ai_difficulty == "casual",
		"got '%s'" % table._resolve_settings_for_slot("teel").ai_difficulty)
	_rm("user://preset_overrides/tournament.json")

	# ── last_used routing signal (§3.5) ──────────────────────────────────────
	# Profiles writes seat_assignments into last_used.json before any ruleset is
	# ever chosen — that must NOT read as "saved rules exist".
	_write_json("user://last_used.json", {"seat_assignments": {"1": "profile_x"}})
	_check("seat_assignments alone does not count as saved rules",
		table._last_used_preset_key() == "",
		"got '%s'" % table._last_used_preset_key())
	_write_json("user://last_used.json", {"last_preset": "custom:Old Ruleset"})
	_check("retired custom:<name> key is not resumed",
		table._last_used_preset_key() == "",
		"got '%s'" % table._last_used_preset_key())
	_write_json("user://last_used.json", {"last_preset": "lechner"})
	_check("a real slot key resumes", table._last_used_preset_key() == "lechner",
		"got '%s'" % table._last_used_preset_key())

	# Difficulty read from last_used.json bypasses from_dict entirely — this is
	# the read path spec v1 would have missed.
	_write_json("user://last_used.json",
		{"last_preset": "lechner", "ai_difficulty": "standard"})
	_check("last_used 'standard' normalizes to expert",
		table._last_used_difficulty() == "expert",
		"got '%s'" % table._last_used_difficulty())
	_check("committed difficulty overrides the slot's stored value",
		table._resolve_settings_for_slot("teel").ai_difficulty == "expert",
		"teel default casual should be overridden by committed expert")

var _table: Node = null
var _frame := 0

func _initialize() -> void:
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

# ── Rebuild lifetime under repeated cycles (#3) ───────────────────────────────
# Rapid open / switch-every-slot / rename / reset / cancel / reopen, watching the
# engine's live node count. _clear_children() detaches before freeing, so the
# count should come back to where it started rather than climbing per cycle.
#
# The measurement has to straddle frames: queue_free() only takes effect at
# end-of-frame, so counting nodes in the same frame that ran the cycles would
# just measure garbage awaiting collection. Hence the phased _process() below —
# cycles on one frame, count several frames later.
const STRESS_CYCLES := 12
var _nodes_before_stress := 0
var _stress_form_sizes: Array = []

# Dismisses any open ConfirmationDialog by firing the same signal its Cancel
# button does, so the real handler runs rather than the test reaching in and
# freeing the node itself. Reset no longer uses one (it's a themed in-house popup
# now — AcceptDialog wouldn't lay out the extra checkbox); this still covers
# _on_settings_home_pressed()'s "Return to Menu?" dialog.
func _cancel_open_dialogs() -> void:
	for c in _table.get_children():
		if c is ConfirmationDialog:
			c.canceled.emit()

# Dismisses the topmost modal popup on a panel, the way its own Cancel button
# does. Used for the rename and reset popups, which are full-rect Controls
# parented to whichever panel raised them.
func _dismiss_top_popup(panel: Control) -> void:
	for i in range(panel.get_child_count() - 1, -1, -1):
		var c := panel.get_child(i)
		if c.is_queued_for_deletion():
			continue
		# Skip the panel's own content container; only free raised popups.
		if c is Container:
			continue
		c.queue_free()
		return

# ONE cycle per frame, deliberately. Running all twelve inside a single frame
# measures nothing useful: queue_free() is deferred to end-of-frame, so every
# dialog and popup the loop dismissed is still alive and still counted, and each
# fresh popup_centered() trips Godot's "parent window already has another
# exclusive child" error against the dialog that hasn't been collected yet. Both
# are artifacts of the test compressing time, not of the code under test — a real
# player gets a frame boundary between clicks.
func _run_one_stress_cycle(cycle: int) -> void:
	var table = _table
	# Open, switch through every slot, close — the pure rebuild path.
	table._show_settings_panel()
	for key in table.SLOT_KEYS:
		table._on_settings_slot_pressed(key)
	_stress_form_sizes.append(table._settings_content_vbox.get_child_count())

	# Rename, reset, domino back, and both dialog types — each dismissed the way
	# a user would, by firing the signal its Cancel button fires.
	table._on_settings_slot_pressed("teel")
	table._set_slot_display_name("teel", "Cycle %d" % cycle)
	table._on_reset_to_default_pressed()
	_dismiss_top_popup(table.settings_panel)   # reset popup lives on Settings
	_cancel_open_dialogs()
	table._on_domino_back_pressed("res://art/domino_back_teel.png")
	table._on_domino_back_pressed("")
	table._rebuild_preset_buttons()
	table._show_slot_rename_popup("teel")
	_dismiss_top_popup(table.preset_panel)
	# The "…" drop-down and the Choose Rules reset popup, both raised and cleared.
	var opts := _find_options_button("teel")
	if opts != null:
		table._on_slot_options_pressed("teel", opts)
		table._on_slot_options_pressed("teel", opts)   # toggle shut
	table._show_reset_confirm_popup("teel", table.preset_panel, func(): pass)
	_dismiss_top_popup(table.preset_panel)
	table.settings_panel.visible = false

# The "…" Button on the row for `key`, or null if the list isn't built yet.
func _find_options_button(key: String) -> Button:
	var idx: int = Array(_table.SLOT_KEYS).find(key)
	if idx < 0 or idx >= _table._preset_btn_container.get_child_count():
		return null
	var row: Node = _table._preset_btn_container.get_child(idx)
	for c in row.get_children():
		if c is Button and c.text == "…":
			return c
	return null

func _check_stress_results() -> void:
	var after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var growth := after - _nodes_before_stress
	# Everything each cycle builds is also dismissed, so the live node count
	# should land back near where it started. Judged per-cycle so the bound
	# scales with STRESS_CYCLES rather than needing a magic total.
	var per_cycle := float(growth) / float(STRESS_CYCLES)
	_check("%d full open/switch/rename/reset/cancel cycles leak nothing (< 2 nodes/cycle)"
		% STRESS_CYCLES, per_cycle < 2.0,
		"before=%d after=%d growth=%d (%.1f/cycle)"
			% [_nodes_before_stress, after, growth, per_cycle])
	# The form must be rebuilt to the same size every time, not grown.
	var stable := true
	for c in _stress_form_sizes:
		if c != _stress_form_sizes[0]:
			stable = false
	_check("settings form size identical on every cycle", stable,
		str(_stress_form_sizes))
	# And nothing should be left parented on either panel afterwards. Both panels
	# keep exactly their own content container; every raised popup is a
	# non-Container child, so any survivor shows up as an extra.
	_check("no orphaned popups left on preset_panel",
		_table.preset_panel.get_child_count() <= 1,
		"%d children remain" % _table.preset_panel.get_child_count())
	var settings_extras := 0
	for c in _table.settings_panel.get_children():
		if not c.is_queued_for_deletion() and not (c is Container) and not (c is ColorRect):
			settings_extras += 1
	_check("no orphaned popups left on settings_panel", settings_extras == 0,
		"%d non-container children remain" % settings_extras)
	var dialogs := 0
	for c in _table.get_children():
		if c is ConfirmationDialog and not c.is_queued_for_deletion():
			dialogs += 1
	_check("no ConfirmationDialogs left parented", dialogs == 0,
		"%d remain" % dialogs)

# Frame budget. The warm-up cycle before the baseline is essential, not padding:
# the settings form doesn't exist until something opens the panel, so a baseline
# taken beforehand counts the form's entire first construction (~147 nodes) as
# leaked growth. Build it once, let that settle, then start measuring.
const ASSERT_FRAME := 3
const WARMUP_FRAME := 4
const BASELINE_FRAME := 7
const STRESS_FIRST_FRAME := 8
const STRESS_LAST_FRAME := STRESS_FIRST_FRAME + STRESS_CYCLES - 1
const MEASURE_FRAME := STRESS_LAST_FRAME + 5

func _process(_delta: float) -> bool:
	_frame += 1
	# Phase 1 — let _ready()/_build_ui() complete before touching the node.
	if _frame < ASSERT_FRAME:
		return false
	# Phase 2 — the assertion suite.
	if _frame == ASSERT_FRAME:
		_snapshot_user_files()
		_test_normalize()
		_test_ai_modes()
		_test_bid_play_cycle()
		_test_from_dict()
		_test_preset_defaults()
		_test_with_table()
		return false
	# Phase 3 — one throwaway cycle so first-time construction isn't measured.
	if _frame == WARMUP_FRAME:
		_run_one_stress_cycle(-1)
		return false
	# Phase 4 — let the warm-up's frees land, then take the baseline.
	if _frame < BASELINE_FRAME:
		return false
	if _frame == BASELINE_FRAME:
		_nodes_before_stress = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		return false
	# Phase 5 — one full UI cycle per frame.
	if _frame <= STRESS_LAST_FRAME:
		_run_one_stress_cycle(_frame - STRESS_FIRST_FRAME)
		return false
	# Phase 6 — idle so the final cycle's queue_free()s land.
	if _frame < MEASURE_FRAME:
		return false
	# Phase 7 — measure what survived, restore save data, report.
	_table._reset_slot_display_name("teel")
	_check_stress_results()
	_restore_user_files()
	var f = FileAccess.open("res://scripts/menu_merge_verify_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"failures": _failures,
			"total": _results.size(),
			"results": _results,
		}, "\t"))
		f.close()
	return true        # quit the main loop
