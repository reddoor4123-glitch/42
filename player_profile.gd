class_name PlayerProfile
extends RefCounted

var profile_id: String = ""      # stable, generated once, never shown or edited
var display_name: String = ""    # user-facing, freely editable

# Reserved for future phases — do not implement yet:
# var personality: Dictionary = {}
# var portrait_path: String = ""
# var sayings: Array[String] = []
# var stats: Dictionary = {}

const PROFILES_DIR := "user://profiles"

# ─── Serialization ────────────────────────────────────────────────────
static func to_dict(p: PlayerProfile) -> Dictionary:
	return {
		"profile_id": p.profile_id,
		"display_name": p.display_name,
	}

static func from_dict(d: Dictionary) -> PlayerProfile:
	var p = PlayerProfile.new()
	p.profile_id = d.get("profile_id", "")
	p.display_name = d.get("display_name", "")
	return p

# ─── ID generation (explicitly NOT name-derived) ─────────────────────
static func _generate_profile_id() -> String:
	var candidate := "profile_%d_%d" % [int(Time.get_unix_time_from_system()), randi()]
	# Collision check against existing files; regenerate on the (extremely
	# unlikely) chance of a clash rather than trusting uniqueness blindly.
	while FileAccess.file_exists("%s/%s.json" % [PROFILES_DIR, candidate]):
		candidate = "profile_%d_%d" % [int(Time.get_unix_time_from_system()), randi()]
	return candidate

# ─── Persistence (directory scan = the roster; no index file) ───────
static func create(display_name: String) -> PlayerProfile:
	var p = PlayerProfile.new()
	p.profile_id = _generate_profile_id()
	p.display_name = display_name
	save(p)
	return p

static func save(p: PlayerProfile) -> void:
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("profiles"):
		dir.make_dir("profiles")
	var f = FileAccess.open("%s/%s.json" % [PROFILES_DIR, p.profile_id], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict(p)))
		f.close()

# Returns null on any failure (missing file, unreadable, malformed JSON) —
# callers must treat null as "no profile" and fall back, never crash.
static func load(profile_id: String) -> PlayerProfile:
	if profile_id.is_empty():
		return null
	var f = FileAccess.open("%s/%s.json" % [PROFILES_DIR, profile_id], FileAccess.READ)
	if f == null:
		return null
	var text = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return from_dict(parsed)
	return null

static func delete(profile_id: String) -> void:
	var path = "%s/%s.json" % [PROFILES_DIR, profile_id]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# The roster: list of profile_ids currently on disk. Directory scan,
# mirroring the existing user://custom_rulesets/ listing pattern
# (game_table.gd:2589-2599) — no separate manifest file.
static func list_all() -> Array[String]:
	var ids: Array[String] = []
	var dir = DirAccess.open(PROFILES_DIR)
	if dir:
		dir.list_dir_begin()
		var fname = dir.get_next()
		while fname != "":
			if fname.ends_with(".json"):
				ids.append(fname.left(fname.length() - 5))
			fname = dir.get_next()
		dir.list_dir_end()
	ids.sort()
	return ids
