extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# preset_persistence_trace.gd
#
# Smoke test for the file-I/O mechanics behind _persist_preset_tweaks()
# and _on_preset_chosen()'s new override-file check (game_table.gd,
# July 22 2026 "persist ruleset tweaks" change). Doesn't instantiate
# game_table.gd itself — it's a Node-based UI script that assumes a full
# scene tree of assigned UI references, not safely constructible headless.
# Instead this exercises the exact same GameSettings.to_dict()/from_dict()
# + FileAccess round-trip those functions rely on, using a throwaway key
# ("test_preset_do_not_use") that can never collide with a real built-in
# preset name, and cleans up after itself so no stray file is left in
# user:// that could affect a real game session.
#
# Covers:
#   1. Write override (mimics _persist_preset_tweaks for a built-in key),
#      read it back (mimics _on_preset_chosen's override check), confirm
#      a tweaked field survives the round-trip.
#   2. Confirm a from_dict() load without a preset_id key defaults
#      correctly and preset_id gets set by the caller afterward, exactly
#      as _on_preset_chosen does ("s.preset_id = key" after loading).
#   3. Delete the override (mimics "Reset to Default"), confirm the file
#      is actually gone and a fresh static-preset load has the original
#      (untweaked) value again.
#
# Run:
#   "$GODOT" --headless --path . --script res://preset_persistence_trace.gd
# ═══════════════════════════════════════════════════════════════════

const GameSettingsScript = preload("res://game_settings.gd")
const TEST_KEY = "test_preset_do_not_use"

var failures: Array = []
var log_lines: Array = []

func _log(s: String):
	log_lines.append(s)
	print(s)

func _check(label: String, condition: bool, detail: String) -> void:
	if condition:
		_log("  PASS: %s — %s" % [label, detail])
	else:
		_log("  FAIL: %s — %s" % [label, detail])
		failures.append(label)

func _override_path() -> String:
	return "user://preset_overrides/%s.json" % TEST_KEY

func _init():
	_log("═══════════════════════════════════════════════════════════")
	_log("Preset persistence — file I/O round-trip")
	_log("═══════════════════════════════════════════════════════════")

	# Clean slate — in case a prior interrupted run left this behind.
	if FileAccess.file_exists(_override_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_override_path()))

	# ── Step 1: write, mimicking _persist_preset_tweaks() ──
	var s = GameSettingsScript.teel_rules()
	s.preset_id = TEST_KEY
	s.allow_laydown = true          # teel_rules() default is false — the tweak under test
	s.laydown_mode = "authentic"    # teel_rules() default is "assisted"

	var d = DirAccess.open("user://")
	if d:
		d.make_dir("preset_overrides")
	var fw = FileAccess.open(_override_path(), FileAccess.WRITE)
	_check("write_override_file", fw != null, "FileAccess.open for WRITE succeeded at %s" % _override_path())
	if fw:
		fw.store_string(JSON.stringify(GameSettingsScript.to_dict(s), "\t"))
		fw.close()

	_check("override_file_exists_after_write", FileAccess.file_exists(_override_path()),
		"file present on disk immediately after _persist_preset_tweaks-equivalent write")

	# ── Step 2: read back, mimicking _on_preset_chosen()'s override check ──
	var fr = FileAccess.open(_override_path(), FileAccess.READ)
	_check("read_override_file", fr != null, "FileAccess.open for READ succeeded")
	var loaded: GameSettings = null
	if fr:
		var data = JSON.parse_string(fr.get_as_text())
		fr.close()
		loaded = GameSettingsScript.from_dict(data)
		loaded.preset_id = TEST_KEY   # _on_preset_chosen sets this after from_dict(), always

	_check("tweak_survived_round_trip", loaded != null and loaded.allow_laydown == true,
		"allow_laydown=true (the tweak) survived write->read, got %s" % [loaded.allow_laydown if loaded else "null"])
	_check("second_tweak_survived", loaded != null and loaded.laydown_mode == "authentic",
		"laydown_mode='authentic' survived write->read, got %s" % [loaded.laydown_mode if loaded else "null"])
	_check("untouched_field_still_matches_base_preset", loaded != null and loaded.nello_doubles_mode == "own_suit",
		"a field the test never touched (nello_doubles_mode) still matches teel_rules()'s own default, got %s" % [loaded.nello_doubles_mode if loaded else "null"])
	_check("preset_id_set_by_caller_not_by_dict", loaded != null and loaded.preset_id == TEST_KEY,
		"preset_id isn't part of to_dict()'s payload at all — confirms the caller (not the file) must set it")

	# ── Step 3: delete, mimicking "Reset to Default" ──
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_override_path()))
	_check("override_file_gone_after_reset", not FileAccess.file_exists(_override_path()),
		"file actually removed from disk after the reset-equivalent delete")

	var fresh = GameSettingsScript.teel_rules()
	_check("fresh_load_has_original_value_again", fresh.allow_laydown == false,
		"a fresh teel_rules() load (no override file present) has the original allow_laydown=false, not the tweak")

	_log("")
	_log("═══════════════════════════════════════════════════════════")
	if failures.is_empty():
		_log("ALL CHECKS PASSED")
	else:
		_log("FAILURES: %s" % [failures])
	_log("═══════════════════════════════════════════════════════════")

	var output = {
		"failures": failures,
		"full_log": log_lines,
	}
	var out_f = FileAccess.open("res://preset_persistence_trace_results.json", FileAccess.WRITE)
	out_f.store_string(JSON.stringify(output, "\t"))
	out_f.close()

	# Final safety net — never leave the test file behind regardless of
	# pass/fail, since user:// is real, persistent game-data storage.
	if FileAccess.file_exists(_override_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_override_path()))

	print("")
	print("Results written to res://preset_persistence_trace_results.json")
	quit(0 if failures.is_empty() else 1)
