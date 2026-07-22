extends SceneTree

# ═══════════════════════════════════════════════════════════════════
# player_profile_trace.gd
#
# Smoke test for player_profile.gd (Player Profile Foundation, Phase 1,
# July 22 2026). All test profiles use a "trace_test_" id/name prefix
# that can never collide with a real user-created profile, and every
# created file is deleted at the end regardless of pass/fail, since
# user://profiles/ is real, persistent game-data storage.
#
# Run:
#   "$GODOT" --headless --path . --script res://player_profile_trace.gd
# ═══════════════════════════════════════════════════════════════════

const PlayerProfileScript = preload("res://player_profile.gd")

var failures: Array = []
var log_lines: Array = []
var _created_ids: Array = []   # tracked for guaranteed cleanup

func _log(s: String):
	log_lines.append(s)
	print(s)

func _check(label: String, condition: bool, detail: String) -> void:
	if condition:
		_log("  PASS: %s — %s" % [label, detail])
	else:
		_log("  FAIL: %s — %s" % [label, detail])
		failures.append(label)

func _init():
	_log("═══════════════════════════════════════════════════════════")
	_log("PlayerProfile — create / save / load / delete / list_all")
	_log("═══════════════════════════════════════════════════════════")

	# ── create() ──
	var p1 = PlayerProfileScript.create("trace_test_Pop")
	_created_ids.append(p1.profile_id)
	_check("create_returns_nonnull", p1 != null, "create() returned a PlayerProfile instance")
	_check("create_sets_display_name", p1.display_name == "trace_test_Pop", "got '%s'" % p1.display_name)
	_check("create_generates_nonempty_id", not p1.profile_id.is_empty(), "profile_id='%s'" % p1.profile_id)
	_check("id_is_not_name_derived", not p1.profile_id.contains("Pop"), "profile_id='%s' contains no trace of the display name" % p1.profile_id)
	_check("file_exists_after_create", FileAccess.file_exists("user://profiles/%s.json" % p1.profile_id),
		"file written to disk immediately by create()->save()")

	# ── a second profile, to test list_all() with more than one entry ──
	var p2 = PlayerProfileScript.create("trace_test_Nana")
	_created_ids.append(p2.profile_id)
	_check("second_create_gets_different_id", p2.profile_id != p1.profile_id,
		"p1=%s p2=%s" % [p1.profile_id, p2.profile_id])

	# ── load() round-trip ──
	var loaded = PlayerProfileScript.load(p1.profile_id)
	_check("load_returns_nonnull_for_real_id", loaded != null, "load() found the file just created")
	_check("load_round_trips_display_name", loaded != null and loaded.display_name == "trace_test_Pop",
		"got '%s'" % [loaded.display_name if loaded else "null"])
	_check("load_round_trips_profile_id", loaded != null and loaded.profile_id == p1.profile_id,
		"got '%s'" % [loaded.profile_id if loaded else "null"])

	# ── load() failure modes — must return null, never crash ──
	var missing = PlayerProfileScript.load("trace_test_this_id_was_never_created")
	_check("load_missing_file_returns_null", missing == null, "nonexistent profile_id -> null, no crash")

	var empty_id = PlayerProfileScript.load("")
	_check("load_empty_id_returns_null", empty_id == null, "empty profile_id -> null, no crash")

	# Malformed JSON on disk -> from_dict never even called, load() must
	# still return null cleanly.
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("profiles"):
		dir.make_dir("profiles")
	var bad_id = "trace_test_malformed"
	var bad_f = FileAccess.open("user://profiles/%s.json" % bad_id, FileAccess.WRITE)
	if bad_f:
		bad_f.store_string("{not valid json,,,")
		bad_f.close()
	var malformed_result = PlayerProfileScript.load(bad_id)
	_check("load_malformed_json_returns_null", malformed_result == null, "malformed file on disk -> null, no crash")
	if FileAccess.file_exists("user://profiles/%s.json" % bad_id):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://profiles/%s.json" % bad_id))

	# ── list_all() ──
	var ids = PlayerProfileScript.list_all()
	_check("list_all_includes_p1", ids.has(p1.profile_id), "roster includes the first created profile")
	_check("list_all_includes_p2", ids.has(p2.profile_id), "roster includes the second created profile")
	_check("list_all_is_sorted", _is_sorted(ids),
		"ids come back in sorted order, matching the directory-scan pattern's files.sort()")

	# ── delete() ──
	PlayerProfileScript.delete(p1.profile_id)
	_check("file_gone_after_delete", not FileAccess.file_exists("user://profiles/%s.json" % p1.profile_id),
		"delete() actually removed the file")
	var reload_after_delete = PlayerProfileScript.load(p1.profile_id)
	_check("load_after_delete_returns_null", reload_after_delete == null,
		"a since-deleted profile_id resolves to null, not a crash — the exact scenario _seat_label()'s fallback depends on")
	var ids_after_delete = PlayerProfileScript.list_all()
	_check("list_all_excludes_deleted", not ids_after_delete.has(p1.profile_id),
		"deleted profile no longer appears in the roster")

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
	var out_f = FileAccess.open("res://player_profile_trace_results.json", FileAccess.WRITE)
	out_f.store_string(JSON.stringify(output, "\t"))
	out_f.close()

	# Final safety net — clean up every profile this trace created,
	# regardless of pass/fail, since user:// is real persistent storage.
	for pid in _created_ids:
		var path = "user://profiles/%s.json" % pid
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("")
	print("Results written to res://player_profile_trace_results.json")
	quit(0 if failures.is_empty() else 1)

func _is_sorted(arr: Array) -> bool:
	for i in range(1, arr.size()):
		if arr[i - 1] > arr[i]:
			return false
	return true
