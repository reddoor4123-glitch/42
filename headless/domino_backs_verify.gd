extends SceneTree

# Verification for the DOMINO_BACKS table and the Settings back picker.
#
# Written when the Texas back was added (Aug 1 2026). The picker loops
# DOMINO_BACKS and needs no per-entry code, so the risk in adding a back is not
# wiring — it is the ART. DominoTile._draw() paints the back with
# draw_texture_rect(back_tex, inner, false), which STRETCHES to fill and does
# not preserve aspect, so a landscape source is silently squashed into the tile
# instead of being letterboxed or rejected. Nothing in the game complains; it
# just looks wrong, and only on the table.
#
# Hence the aspect guard below: every back must be authored portrait at the
# tile's inner-rect ratio. That is the check that would have caught dropping the
# 3:2 Texas flag photo straight in.
#
# Touches user://display_prefs.json (the picker writes it). Snapshots/restores.
#
# EXPECTED on stderr: "ObjectDB instances leaked at exit" (gotcha #10) — this
# instantiates the real scene. Judge the exit code and the results JSON.

const TOUCHED_PATHS := ["user://display_prefs.json", "user://last_used.json"]

# The rect DominoTile actually paints the back into: 64x128 grown by -3 on every
# side. Derived here rather than hardcoded so retuning the tile moves the guard
# with it.
const INNER_W := DominoTile.DOMINO_WIDTH - 6.0
const INNER_H := DominoTile.DOMINO_HEIGHT - 6.0
const TARGET_ASPECT := INNER_W / INNER_H          # 58/122 = 0.4754
# Loose enough for reasonable authoring slack, tight enough that landscape
# (1.5), square (1.0) or a half-turned portrait (0.667) all fail.
const ASPECT_TOLERANCE := 0.03

var _snapshot: Dictionary = {}
var _table: Node = null
var _frame := 0
var _results: Array = []
var _failures := 0
var _pref_at_start := ""

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

func _all_nodes(node: Node, out: Array) -> void:
	out.append(node)
	for c in node.get_children():
		_all_nodes(c, out)

# The picker's swatch Buttons, identified the way the click probe identifies
# them: a Button with a DominoTile child.
func _swatches() -> Array:
	var all: Array = []
	_all_nodes(_table.settings_panel, all)
	var out: Array = []
	for n in all:
		if n is Button:
			for c in n.get_children():
				if c is DominoTile:
					out.append(n)
					break
	return out

func _swatch_for(res_path: String):
	for b in _swatches():
		if b.has_meta("domino_back_path") and str(b.get_meta("domino_back_path")) == res_path:
			return b
	return null

func _initialize() -> void:
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false
	match _frame:
		4:
			_snapshot_user_files()
			_pref_at_start = _table._load_domino_back_pref()
			_test_table_entries()
			_test_art_dimensions()
			_table._show_settings_panel()
		10:
			# Containers lay out the frame AFTER their children change, so the
			# picker is only readable a few frames past _show_settings_panel().
			_test_picker_rows()
			_test_selection()
		14:
			# Put the player's own choice back before restoring the file, so a
			# live DominoTile.custom_back_texture doesn't outlive the run.
			_table._on_domino_back_pressed(_pref_at_start)
			_restore_user_files()
			var f = FileAccess.open("res://headless/domino_backs_results.json", FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify({
					"failures": _failures, "total": _results.size(), "results": _results,
				}, "\t"))
				f.close()
			quit(1 if _failures > 0 else 0)
			return true
	return false

# ── The table itself ─────────────────────────────────────────────────
func _test_table_entries() -> void:
	var backs: Array = _table.DOMINO_BACKS
	_check("DOMINO_BACKS has entries", backs.size() >= 2, "%d entries" % backs.size())

	var labels: Array = []
	var paths: Array = []
	for entry in backs:
		labels.append(str(entry[0]))
		paths.append(str(entry[1]))

	_check("Default is present and is the procedural fallback",
		paths.has(""), "paths=%s" % [paths])
	_check("Texas back is registered", labels.has("Texas"), "labels=%s" % [labels])
	_check("Texas points at the installed art",
		paths.has("res://art/domino_back_texas.png"), "paths=%s" % [paths])

	# Duplicate labels or paths would give the picker two indistinguishable
	# swatches and make the saved preference ambiguous.
	var seen_paths: Dictionary = {}
	var seen_labels: Dictionary = {}
	var dup := false
	for i in range(paths.size()):
		if seen_paths.has(paths[i]) or seen_labels.has(labels[i]):
			dup = true
		seen_paths[paths[i]] = true
		seen_labels[labels[i]] = true
	_check("no duplicate labels or paths", not dup, "labels=%s paths=%s" % [labels, paths])

	for i in range(paths.size()):
		var p: String = paths[i]
		if p.is_empty():
			continue
		_check("%s: resource exists" % labels[i], ResourceLoader.exists(p), p)
		_check("%s: loads as a Texture2D" % labels[i], load(p) is Texture2D, p)

# ── The art, which is the part that can go wrong silently ────────────
func _test_art_dimensions() -> void:
	for entry in _table.DOMINO_BACKS:
		var label := str(entry[0])
		var p := str(entry[1])
		if p.is_empty() or not ResourceLoader.exists(p):
			continue
		var tex: Texture2D = load(p)
		var w := tex.get_width()
		var h := tex.get_height()
		var aspect := float(w) / float(h)

		_check("%s: portrait, not landscape" % label, h > w, "%dx%d" % [w, h])
		_check("%s: aspect %.4f within %.2f of the tile's %.4f" % [
				label, aspect, ASPECT_TOLERANCE, TARGET_ASPECT],
			absf(aspect - TARGET_ASPECT) <= ASPECT_TOLERANCE,
			"%dx%d -> %.4f, tile inner is %.0fx%.0f -> %.4f"
				% [w, h, aspect, INNER_W, INNER_H, TARGET_ASPECT])
		# Below the tile's on-screen size the stretch turns into visible
		# softening. The tile is 64x128 at scale 1 and grows with the viewport.
		_check("%s: resolution above the tile's native size" % label,
			w >= int(INNER_W) and h >= int(INNER_H), "%dx%d" % [w, h])

# ── The picker ───────────────────────────────────────────────────────
func _test_picker_rows() -> void:
	var backs: Array = _table.DOMINO_BACKS
	var sw := _swatches()
	_eq("picker builds one swatch per DOMINO_BACKS entry", sw.size(), backs.size())

	var swatch_paths: Array = []
	for b in sw:
		swatch_paths.append(str(b.get_meta("domino_back_path")) if b.has_meta("domino_back_path") else "<none>")
	var want_paths: Array = []
	for entry in backs:
		want_paths.append(str(entry[1]))
	_eq("swatches carry the DOMINO_BACKS paths, in order", swatch_paths, want_paths)

	var texas = _swatch_for("res://art/domino_back_texas.png")
	_check("a Texas swatch exists in the picker", texas != null)
	if texas != null:
		_eq("Texas swatch is tooltipped with its name", texas.tooltip_text, "Texas")
		# The swatch previews the real art, so an entry that failed to load
		# would show the procedural default and look like a picker bug.
		var tile = null
		for c in texas.get_children():
			if c is DominoTile:
				tile = c
		_check("Texas swatch previews its own texture",
			tile != null and tile.use_back_override and tile.back_texture_override != null)

# ── Selecting it ─────────────────────────────────────────────────────
func _test_selection() -> void:
	var texas_path := "res://art/domino_back_texas.png"
	var texas = _swatch_for(texas_path)
	if texas == null:
		_check("Texas selectable", false, "no swatch")
		return

	texas.emit_signal("pressed")
	_eq("selecting Texas saves the preference",
		_table._load_domino_back_pref(), texas_path)
	_check("selecting Texas sets the live tile texture",
		DominoTile.custom_back_texture != null
			and DominoTile.custom_back_texture.get_width() == 437,
		"tex=%s" % [DominoTile.custom_back_texture])

	# Selection is a gold border on the chosen swatch and only that one.
	var gold := Color(0.95, 0.80, 0.15)
	var gold_count := 0
	for b in _swatches():
		var style: StyleBox = b.get_theme_stylebox("normal")
		if style is StyleBoxFlat and style.border_color == gold:
			gold_count += 1
	_eq("exactly one swatch is marked selected", gold_count, 1)

	# And Default must still clear back to the procedural pattern — the entry
	# with an empty path is the one that has no texture to load.
	var default_sw = _swatch_for("")
	if default_sw != null:
		default_sw.emit_signal("pressed")
		_check("selecting Default clears the texture",
			DominoTile.custom_back_texture == null,
			"tex=%s" % [DominoTile.custom_back_texture])
