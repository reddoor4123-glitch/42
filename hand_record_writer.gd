class_name HandRecordWriter
extends RefCounted

# ─── Per-hand bookkeeping ────────────────────────────────────────────────
# This is the ONLY state this class holds. It is bookkeeping about the
# writer's own job (has it already committed something for this hand, and
# under what filename), never a copy of hand data. Reset every new hand
# from the same place game.gd already resets hand_history/deal_snapshot/etc.
static var _has_persisted_this_hand: bool = false
static var _active_filename: String = ""

const OUTPUT_DIR := "user://flagged_hands"

# Call from game.gd::deal_hands(), alongside the existing per-hand reset
# block (hand_history.clear(), deal_snapshot.clear(), flags.clear(), etc.).
# This is the single, obvious, same-place-per-hand reset call — do not add
# a second reset path elsewhere.
static func reset_for_new_hand() -> void:
	_has_persisted_this_hand = false
	_active_filename = ""

# Entry point called from game.gd::flag_hand() on every flag event, with a
# freshly-built record (game.build_hand_record()) each time. This function
# decides whether this is a first-persist or a subsequent update, and
# branches by platform accordingly. It never holds on to `record` past the
# end of this call.
static func on_flag(record: Dictionary) -> void:
	var safe_record = _to_json_safe(record)
	var json_string = JSON.stringify(safe_record, "\t")

	if not _has_persisted_this_hand:
		_active_filename = _make_filename()
		_persist(json_string, _active_filename, true)
		_has_persisted_this_hand = true
		return

	# Subsequent flags in the same hand:
	if OS.get_name() == "Web":
		# Capture-once on web — a second browser download per additional
		# flag is UX noise, not a data-integrity improvement. The first
		# download already has the full hand plus at least one annotation.
		return
	else:
		# Desktop: cheap and safe to keep the file fully current.
		_persist(json_string, _active_filename, false)

# ─── Filename ────────────────────────────────────────────────────────────

static func _make_filename() -> String:
	var ts = Time.get_datetime_string_from_system(false, true).replace(":", "-")
	return "flagged_hand_%s.json" % ts

# ─── Platform-specific persistence ───────────────────────────────────────

static func _persist(json_string: String, filename: String, is_first_write: bool) -> void:
	if OS.get_name() == "Web":
		var buffer = json_string.to_utf8_buffer()
		JavaScriptBridge.download_buffer(buffer, filename, "application/json")
		return

	if is_first_write:
		DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)

	var path = "%s/%s" % [OUTPUT_DIR, filename]
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("HandRecordWriter: failed to open %s for write (error %d)" % [
			path, FileAccess.get_open_error()
		])
		return
	file.store_string(json_string)
	file.close()

# ─── Serialization ────────────────────────────────────────────────────────
# Recursively converts a build_hand_record() tree into JSON-safe primitives.
# Handles Domino and Bid explicitly (the two custom RefCounted types known
# to appear in the record). Anything else non-primitive gets a defensive
# fallback with a warning, rather than silently corrupting the exported
# file — a new object type showing up here later should be loud, not silent.
static func _to_json_safe(value):
	if value is Dictionary:
		var out = {}
		for key in value.keys():
			out[key] = _to_json_safe(value[key])
		return out

	if value is Array:
		var out = []
		for item in value:
			out.append(_to_json_safe(item))
		return out

	if value is Domino:
		return {"left": value.left, "right": value.right}

	if value is Bid:
		return {
			"type":      value.type,
			"value":     value.value,
			"player_id": value.player_id,
		}

	if value == null or value is int or value is float or value is String or value is bool:
		return value

	# Defensive fallback: an unrecognized non-primitive reached here. Rather
	# than let JSON.stringify choke on it or silently drop it, surface it.
	push_warning("HandRecordWriter: unrecognized type in hand record (%s), stringifying" % [
		typeof(value)
	])
	return str(value)
