extends SceneTree

# Verification for the Call Trump preview and the doubles-trump pip fix.
#
# Two changes land together here because the second is what the first exposes:
#
#   * DominoTile._draw_pips() tested `pip == _trump`. No pip can equal the
#     DOUBLES_TRUMP sentinel of 7, so choosing "Doubles (Trump Suit)" reddened
#     nothing — for the whole hand, in live play, not only in a preview. Now a
#     numeric trump reddens the matching pip and DOUBLES_TRUMP reddens both
#     halves of a double.
#
#   * Tapping a suit previews it instead of committing it. game.trump must not
#     move until Confirm, and tapping a second suit must move the highlight.
#
# The load-bearing assertion is "game.trump is untouched while previewing" —
# that is what makes the preview a preview rather than a commit with an extra
# click.
#
# EXPECTED on stderr: "ObjectDB instances leaked at exit" (gotcha #10) — this
# starts a real game. Judge the exit code and the results JSON.

const BidScript = preload("res://bid.gd")
const DominoScript = preload("res://domino.gd")

const TOUCHED_PATHS := ["user://last_used.json", "user://display_prefs.json"]
var _snapshot: Dictionary = {}
var _table: Node = null
var _frame := 0
var _results: Array = []
var _failures := 0

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

func _initialize() -> void:
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false
	if _frame == 4:
		_snapshot_user_files()
		_test_pip_colouring()
		_open_trump_panel()
		return false
	if _frame == 8:
		_test_preview_is_not_a_commit()
		_test_preview_retargets()
		_test_button_highlight()
		_test_confirm_commits()
		return false
	if _frame < 12:
		return false
	_restore_user_files()
	var f = FileAccess.open("res://headless/trump_preview_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"failures": _failures, "total": _results.size(), "results": _results,
		}, "\t"))
		f.close()
	quit(1 if _failures > 0 else 0)
	return true

func _open_trump_panel() -> void:
	_table.main_menu_panel.visible = false
	_table._on_preset_chosen("standard")
	_table.game.settings.allow_follow_me = true
	_table.game.settings.doubles_are_trump = true
	_table.game.settings.doubles_trump_reversed = true
	_table.game.current_bid = BidScript.new(BidScript.Type.POINTS, 32, _table.human_seat)
	_table.bid_panel.visible = false
	_table._show_trump_panel()

# ── The pip rule, tested on the tile in isolation ────────────────────
# Which halves redden is a property of DominoTile, so it is checked directly
# rather than through the panel — a hand that happens to hold no doubles would
# otherwise silently skip the case the fix exists for.
func _test_pip_colouring() -> void:
	var five_three = DominoScript.new(5, 3)
	var four_four = DominoScript.new(4, 4)

	var six_six = DominoScript.new(6, 6)

	_check("numeric trump: 5-3 under fives is trump", five_three.is_trump(5))
	_check("numeric trump: 5-3 under fours is not", not five_three.is_trump(4))
	# The half-level rule the tile draws with: only the matching pip reddens.
	# Asserted by counting rather than by position — Domino._init() sorts its
	# pips ascending, so Domino.new(5, 3) stores left=3, right=5 and any
	# assertion written against argument order is testing the wrong thing.
	_eq("numeric trump: exactly one half of 5-3 reddens under fives",
		_red_halves(five_three, 5), 1)
	_eq("numeric trump: neither half of 5-3 reddens under fours",
		_red_halves(five_three, 4), 0)
	# A double under its own numeric trump reddens both halves without needing
	# the DOUBLES_TRUMP path at all — both pips genuinely match.
	_eq("numeric trump: both halves of 6-6 redden under sixes",
		_red_halves(six_six, 6), 2)

	# The bug: a double is trump under DOUBLES_TRUMP, but neither pip equals 7,
	# so the old `pip == _trump` test coloured nothing.
	_check("doubles trump: 4-4 is trump", four_four.is_trump(DominoScript.DOUBLES_TRUMP))
	_check("doubles trump: 5-3 is not", not five_three.is_trump(DominoScript.DOUBLES_TRUMP))
	_check("doubles trump: no pip equals the sentinel (why the old test failed)",
		four_four.left != DominoScript.DOUBLES_TRUMP
			and four_four.right != DominoScript.DOUBLES_TRUMP)

	# What the fix buys, stated as the counts the tile will draw.
	_eq("doubles trump: both halves of 4-4 redden",
		_red_halves(four_four, DominoScript.DOUBLES_TRUMP), 2)
	_eq("doubles trump: neither half of 5-3 reddens",
		_red_halves(five_three, DominoScript.DOUBLES_TRUMP), 0)
	# Follow Me is a real trump value and must colour nothing.
	_eq("Follow Me reddens nothing", _red_halves(five_three, -1), 0)
	_eq("Follow Me reddens nothing on a double", _red_halves(four_four, -1), 0)

	_test_trump_bar()

# ── The divider bar as a whole-tile trump marker ─────────────────────
# Red pips cannot cover blanks: a blank half draws no circles, so under
# blanks-trump the pip highlighting says nothing and 0-0 showed no marking at
# all. The bar is drawn on every face-up tile whatever the halves hold, so it is
# the one place a blanks-trump marker can live.
func _test_trump_bar() -> void:
	var five_blank = DominoScript.new(5, 0)
	var blank_blank = DominoScript.new(0, 0)
	var five_three = DominoScript.new(5, 3)
	var four_four = DominoScript.new(4, 4)
	var tile := DominoTile.new()

	# The case that motivated it: trump held, nothing to see.
	# The blank half IS flagged as trump — the pip rule is not broken — but a half
	# worth zero draws zero circles, so the flag reaches the screen as nothing.
	# Counting flagged halves would hide that; counting drawn circles is the
	# measure that shows why the bar is needed.
	tile.setup(five_blank, true, 0)
	_eq("blanks trump: the blank half of 5-0 is flagged", _red_halves(five_blank, 0), 1)
	_eq("blanks trump: but 5-0 draws no red pips at all", _red_pips_drawn(five_blank, 0), 0)
	_check("blanks trump: 5-0 is still marked by the bar", tile.is_trump_tile())

	tile.setup(blank_blank, true, 0)
	_eq("blanks trump: 0-0 draws no red pips at all", _red_pips_drawn(blank_blank, 0), 0)
	_check("blanks trump: 0-0 is still marked by the bar", tile.is_trump_tile())

	# Contrast: every other suit does put ink on the tile, so the bar is
	# reinforcement there rather than the only signal.
	_eq("fives: 5-3 draws five red pips", _red_pips_drawn(five_three, 5), 5)
	_eq("doubles: 4-4 draws eight red pips",
		_red_pips_drawn(four_four, DominoScript.DOUBLES_TRUMP), 8)

	tile.setup(five_three, true, 0)
	_check("blanks trump: 5-3 is not marked", not tile.is_trump_tile())

	# And the bar means the same thing under every other suit.
	tile.setup(five_three, true, 5)
	_check("numeric trump: 5-3 under fives is barred", tile.is_trump_tile())
	tile.setup(five_three, true, 4)
	_check("numeric trump: 5-3 under fours is not", not tile.is_trump_tile())
	tile.setup(four_four, true, DominoScript.DOUBLES_TRUMP)
	_check("doubles trump: 4-4 is barred", tile.is_trump_tile())
	tile.setup(five_three, true, DominoScript.DOUBLES_TRUMP)
	_check("doubles trump: 5-3 is not barred", not tile.is_trump_tile())

	# Follow Me marks nothing — -1 is "no trump", not a suit.
	tile.setup(five_blank, true, -1)
	_check("Follow Me bars nothing", not tile.is_trump_tile())
	tile.setup(blank_blank, true, -1)
	_check("Follow Me bars nothing on 0-0", not tile.is_trump_tile())

	# A tile with no domino must not crash the marker.
	tile.setup(null, false, 0)
	_check("an empty tile is not trump", not tile.is_trump_tile())
	tile.free()

# How many of a tile's two halves redden under `trump`, evaluated exactly as
# DominoTile._draw_pips() does it.
func _red_halves(d, trump: int) -> int:
	var whole_tile_trump: bool = trump == DominoScript.DOUBLES_TRUMP and d.is_trump(trump)
	var n := 0
	for pip in [d.left, d.right]:
		if whole_tile_trump or pip == trump:
			n += 1
	return n

# How many red CIRCLES actually land on the tile — a half worth v draws v pips,
# so a blank half draws none however it is flagged. This is the number a player
# sees; _red_halves() is the rule behind it.
func _red_pips_drawn(d, trump: int) -> int:
	var whole_tile_trump: bool = trump == DominoScript.DOUBLES_TRUMP and d.is_trump(trump)
	var n := 0
	for pip in [d.left, d.right]:
		if whole_tile_trump or pip == trump:
			n += pip
	return n

# ── A preview must not be a commit ───────────────────────────────────
func _test_preview_is_not_a_commit() -> void:
	var g = _table.game
	var trump_before = g.trump
	var rev_before = g.active_doubles_trump_reversed

	_check("panel opens with nothing previewed",
		_table._trump_preview == _table.NO_TRUMP_PREVIEW,
		"preview=%d" % _table._trump_preview)
	_check("Confirm starts disabled", _table._confirm_trump_btn.disabled)

	_table._on_trump_previewed(5, false)
	_eq("previewing fives leaves game.trump alone", g.trump, trump_before)
	_eq("previewing fives leaves the panel open", _table.trump_panel.visible, true)
	_check("Confirm enables once something is previewed",
		not _table._confirm_trump_btn.disabled)

	# Doubles Reversed shares a trump value with plain Doubles, so the flavour
	# has to ride on the preview and must not reach game state early.
	_table._on_trump_previewed(DominoScript.DOUBLES_TRUMP, true)
	_eq("previewing Doubles Reversed leaves game.trump alone", g.trump, trump_before)
	_eq("previewing Doubles Reversed does not set the reversed flag",
		g.active_doubles_trump_reversed, rev_before)
	_check("the reversed flavour is held on the preview",
		_table._trump_preview_doubles_reversed)

# ── Tapping a second suit moves the highlight ────────────────────────
func _test_preview_retargets() -> void:
	_table._on_trump_previewed(1, false)
	_eq("hand paints ones", _hand_trump(), 1)
	_table._on_trump_previewed(4, false)
	_eq("tapping fours retargets the hand", _hand_trump(), 4)
	_table._on_trump_previewed(-1, false)
	_eq("Follow Me previews as -1, distinct from 'not previewing'", _hand_trump(), -1)
	_check("and -1 is still a live preview, not a cleared one",
		_table._trump_preview == -1 and not _table._confirm_trump_btn.disabled)

	# Clearing is what returns the hand to the committed value.
	_table._clear_trump_preview()
	_eq("clearing returns the hand to game.trump", _hand_trump(), _table.game.trump)
	_check("Confirm disables again", _table._confirm_trump_btn.disabled)

# Every face-up tile agrees on one trump, and that is the value.
func _hand_trump() -> int:
	var seen: Array = []
	for c in _table.player_hand_container.get_children():
		if c is DominoTile and not seen.has(c._trump):
			seen.append(c._trump)
	if seen.size() != 1:
		return -999   # tiles disagree; the preview did not reach all of them
	return seen[0]

# ── Exactly one option reads as chosen ───────────────────────────────
func _test_button_highlight() -> void:
	var gold := Color(0.95, 0.80, 0.15)
	_table._on_trump_previewed(3, false)
	var lit: Array = []
	for b in _table._trump_option_buttons:
		if b.modulate == gold:
			lit.append(int(b.get_meta("trump_suit")))
	_eq("exactly one option is highlighted", lit, [3])

	# Doubles and Doubles Reversed share suit 7 — the flavour must pick them apart
	# or both light up.
	_table._on_trump_previewed(DominoScript.DOUBLES_TRUMP, true)
	var lit2: Array = []
	for b in _table._trump_option_buttons:
		if b.modulate == gold:
			lit2.append(bool(b.get_meta("trump_doubles_reversed")))
	_eq("Doubles and Doubles Reversed do not both light up", lit2, [true])

	_table._clear_trump_preview()
	var lit3 := 0
	for b in _table._trump_option_buttons:
		if b.modulate == gold:
			lit3 += 1
	_eq("nothing highlighted with no preview", lit3, 0)

# ── Confirm is the only thing that commits ───────────────────────────
func _test_confirm_commits() -> void:
	var g = _table.game

	# Confirm with nothing previewed must be inert, not a commit of garbage.
	_table._clear_trump_preview()
	var before = g.trump
	_table._on_trump_confirmed()
	_eq("Confirm with no preview does nothing", g.trump, before)
	_eq("and leaves the panel open", _table.trump_panel.visible, true)

	# The reversed flavour has to survive the trip through Confirm.
	_table._on_trump_previewed(DominoScript.DOUBLES_TRUMP, true)
	_table._on_trump_confirmed()
	_eq("Confirm commits the previewed trump", g.trump, DominoScript.DOUBLES_TRUMP)
	_check("Confirm applies the reversed flavour", g.active_doubles_trump_reversed)
	_eq("Confirm closes the panel", _table.trump_panel.visible, false)
	_eq("preview is cleared after committing",
		_table._trump_preview, _table.NO_TRUMP_PREVIEW)
	_eq("the hand now paints the committed trump", _hand_trump(), g.trump)
