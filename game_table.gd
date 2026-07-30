extends Node

const BidScript       = preload("res://bid.gd")
const GameSettingsScript = preload("res://game_settings.gd")
const AIPlayer = preload("res://ai_player.gd")
const LaydownCheckScript = preload("res://laydown_check.gd")
const PlayerProfileScript = preload("res://player_profile.gd")

# The four built-in rulesets that ship with the game (as opposed to a
# user-created "custom:<name>" ruleset) — used to gate the "Reset to
# Default" button and to decide whether a preset key should be looked up
# under user://preset_overrides/ before falling back to its hardcoded
# GameSettings.* function.
const BUILTIN_PRESET_KEYS: Array[String] = ["teel", "standard", "tournament", "lechner"]

# ─── RULESET SLOTS ────────────────────────────────────────────────────────────
# As of July 29 2026 the ruleset system is exactly five fixed slots rather than
# four built-ins plus an arbitrary-length user list. The fifth is Custom.
#
# Custom's key is "custom:Custom", not a bare "custom", specifically so it keeps
# matching the existing key.begins_with("custom:") discrimination used by
# _resolve_settings_for_slot(), _persist_preset_tweaks() and
# _on_menu_play_pressed(). That routes it to user://custom_rulesets/Custom.json
# — reusing the storage path custom rulesets already used — instead of inventing
# a third location, and keeps it out of BUILTIN_PRESET_KEYS so Reset to Default
# correctly never offers itself for a slot that has no hardcoded default.
const CUSTOM_SLOT_KEY := "custom:Custom"
const SLOT_KEYS: Array[String] = ["teel", "standard", "tournament", "lechner", CUSTOM_SLOT_KEY]

# Fallback label per slot, used when slot_names.json has no entry for it. These
# are defaults for a *renameable* display name, not the slot's identity — the
# key is the identity. Reset to Default restores one of these only when the
# operator ticks "Also reset the name".
const SLOT_DEFAULT_NAMES := {
	"teel":       "Teel Rules",
	"standard":   "Standard 42",
	"tournament": "Tournament",
	"lechner":    "Lechner Hall",
	CUSTOM_SLOT_KEY: "Custom",
}

# Flavor line under each slot's name on the Choose Rules screen. Fixed per slot
# (describes the *original* ruleset), so it isn't renamed along with the name.
const SLOT_BLURBS := {
	"teel":       "Our family's house rules",
	"standard":   "The classic game",
	"tournament": "Strict competitive rules",
	"lechner":    "Aggie 42 — A&M dorm rules",
	CUSTOM_SLOT_KEY: "Your own ruleset",
}

# ─── PERSISTENCE LAYOUT ───────────────────────────────────────────────────────
# Five separate files, each owning exactly one kind of thing. Keeping them
# separate is what lets "Reset to Default" throw away one slot's rules without
# touching its name, and lets the domino back survive a ruleset switch.
#
#   last_used.json         session + player state: which slot to resume,
#                          the committed difficulty, Profiles' seat assignments.
#                          NOT rules, and NOT presentation.
#   slot_names.json        presentation only: slot key -> display name.
#   display_prefs.json     visual preferences only: currently the domino back.
#   preset_overrides/<key>.json     rule content for a built-in slot.
#   custom_rulesets/<name>.json     rule content for a custom slot.
#
# Nothing outside this block should hardcode one of these paths — use the
# constants, or _slot_file_path() for the two rules directories, so a future
# layout change is one edit rather than a grep.
const LAST_USED_PATH := "user://last_used.json"
const SLOT_NAMES_PATH := "user://slot_names.json"
const DISPLAY_PREFS_PATH := "user://display_prefs.json"
const PRESET_OVERRIDES_DIR := "user://preset_overrides"
const CUSTOM_RULESETS_DIR := "user://custom_rulesets"

# Available domino backs as [label, resource_path]. An empty path means
# DominoTile's default procedural pattern. Table-wide display choice, fully
# independent of which ruleset slot is active — before July 29 2026 the Teel
# back was inferred from preset_id == "teel" instead of being chosen.
const DOMINO_BACKS := [
	["Default", ""],
	["Teel", "res://art/domino_back_teel.png"],
]

# Swatch size for the Settings picker: one DominoTile (64x128) plus a padding
# ring, so the gold selection border has somewhere to sit without covering art.
const SWATCH_PAD := 6
const SWATCH_W := 64 + SWATCH_PAD * 2
const SWATCH_H := 128 + SWATCH_PAD * 2

# The small-end toggle floats rather than sitting in a row, so its size has to be
# stated explicitly instead of coming from a container.
const SMALL_END_BTN_W := 180.0
const SMALL_END_BTN_H := 40.0

# --- Layout: one shared inset for everything that lines the felt's border ---
# The mid row is [left seat col | play-area panel | right seat col], so the
# panel's own edges land SIDE_SEAT_COL_W + MID_ROW_SEPARATION in from the
# window. The US/THEM columns above and the two bottom-corner overlays align
# to that same pair of verticals instead of hugging the border, which is why
# these are constants rather than literals at each site — move PLAY_AREA_INSET
# and all five elements stay in register.
const SIDE_SEAT_COL_W := 60
const MID_ROW_SEPARATION := 8
const PLAY_AREA_INSET := SIDE_SEAT_COL_W + MID_ROW_SEPARATION

# Team columns also come down off the top edge by this much.
const TEAM_COL_INSET_TOP := 24

# Seat bid bubbles ("Nanny / 30 points"). Down from 13 — at the old size they
# crowded the felt, and the left/right ones reached into the band the expanded
# trick lists now use.
const BID_BUBBLE_FONT_SIZE := 11

# Bottom-left winning-contract reminder. Base size, so it rides font_scale.
# At this size every contract line clears the player's hand except one —
# "Nello doubles own suit (reversed)" — which wraps rather than run under the
# tiles, hence the autowrap and the measured width cap.
#
# LINE_SPACING is negative because Font.get_height() here reports the tallest
# font in the fallback chain (NotoSansSymbols, 44px at this size), not Nunito's
# own ~30, and the surplus is pure padding. -14 lands the pitch back on Nunito's
# natural line height. Note Godot applies line_spacing BETWEEN lines, so a block
# is n*height + (n-1)*spacing — 104px at three lines, 134px at four.
const BID_REMINDER_FONT_SIZE := 14
const BID_REMINDER_LINE_SPACING := -14
const BID_REMINDER_SIDE_GAP := 8.0
const BID_REMINDER_BOTTOM := -3.0   # offset of the block's bottom from the window's

# Expanded trick list: a floating panel per team that replaces the little
# scrolling box in place, and the toggle that opens it. The toggle sits on the
# felt just medial of its column so it covers no domino and, like the panel,
# costs the surrounding layout nothing.
const TRICKS_BTN_SIZE := 24.0
const TRICKS_BTN_GAP := 6.0

# Main-menu wordmark: the Rye "42" and the subtitle under it. AIR is the space
# left between them after the title's dead descender band is closed up, so it
# reads as the gap the eye actually sees rather than a box-to-box separation.
const MENU_TITLE_SIZE := 48
const MENU_SUBTITLE_SIZE := 24
const MENU_WORDMARK_AIR := 0.0

# Top edge of the two bottom-corner overlays (Lay Down, bid reminder),
# measured up from the window's bottom — puts them level with the top of the
# player's own hand, clear of the play-area panel above.
const CORNER_OVERLAY_TOP := -115

var game: Game

# Typeface resources, built once by _build_fonts() before _build_ui() runs.
# Nunito carries the UI; Rye is reserved for the two display spots (the menu
# "42" and the end-of-hand banner).
var _font_nunito_regular: Font
var _font_nunito_heavy: Font
var _font_rye: Font

# UI node references (assigned in _ready)
var player_hand_container: HBoxContainer
var play_area_container: Control
var opponent_top_container: HBoxContainer
var opponent_left_container: VBoxContainer
var opponent_right_container: VBoxContainer
var info_label: Label
var trump_indicator_label: Label
var bid_reminder_label: Label
var play_vbox: VBoxContainer
var _hand_result_banner: Label = null
var bid_panel: PanelContainer
var bid_buttons: HBoxContainer
var _pts_picker: DrumPicker = null
var _marks_picker: DrumPicker = null
var _bid_panel_expanded: bool = false
var _selected_contract_type: int = BidScript.Type.MARKS
var _contract_marks_picker: DrumPicker = null
var _bid_bubbles: Dictionary = {}  # player_id -> Label
var _bubble_overlay: Control = null
var _drag_ghost: DominoTile = null
var _us_marks: MarksDisplay = null
var _them_marks: MarksDisplay = null
var _us_tricks: TrickPile = null
var _them_tricks: TrickPile = null
# Indexed by team (0 = US, 1 = THEM) so the expand/collapse code is written once
# instead of twice. The TrickPile itself is never duplicated — it is reparented
# between its scroll box and its overlay, so there is one pile and no sync.
var _tricks_scroll: Array[ScrollContainer] = [null, null]
var _tricks_overlay: Array[PanelContainer] = [null, null]
var _tricks_toggle_btn: Array[Button] = [null, null]
var _tricks_expanded: Array[bool] = [false, false]
var trump_panel: PanelContainer
var trump_buttons: HBoxContainer
var _special_trump_sep: HSeparator = null
var _doubles_trump_btn: Button = null
var _doubles_trump_reversed_btn: Button = null
var _follow_me_btn: Button = null
var nello_panel: PanelContainer
var _nello_reversed_btn: Button = null
var nello_exchange_panel: PanelContainer
var nello_exchange_hand_container: HBoxContainer
var _nello_exchange_partner_tile: DominoTile = null
var _pending_partner_give: Domino = null
var laydown_btn: Button = null
var _small_end_active: bool = false
var _small_end_toggle_btn: Button = null
var preset_panel: PanelContainer
var status_label: Label
var settings_panel: Control = null
var _settings_content_vbox: VBoxContainer = null
var _settings_panel_inner: PanelContainer = null
var _settings_scroll: ScrollContainer = null
var _pending_settings: GameSettings = null
var _preset_btn_container: VBoxContainer = null
# The open "…" drop-down on Choose Rules, and which slot it belongs to. Tracked
# rather than looked up because the toggle needs to know whether the press that
# just arrived is re-pressing the same slot's button.
var _slot_menu_popup: Control = null
var _slot_menu_key: String = ""
var _preset_status_label: Label = null
var main_menu_panel: PanelContainer = null
var difficulty_panel: PanelContainer = null
var _difficulty_btn_container: VBoxContainer = null
var profile_panel: PanelContainer = null
var _profile_content_vbox: VBoxContainer = null
var _game_top_row: MarginContainer = null
var _game_mid_row: HBoxContainer = null

# Debug flag — set true to skip AI thinking pauses for faster testing.
# Wire this to a proper settings toggle later once the settings UI exists.
const DEBUG_FAST_MODE: bool = false

# Game state
var selected_tile: DominoTile = null
var human_seat: int = 0
var seat_profiles: Dictionary = {}  # seat_id (int, 0-3) -> profile_id (String); never contains human_seat
var waiting_for_human: bool = false
# Set the moment a hand is decided, cleared when the next one is dealt. Play
# input is gated on this rather than on waiting_for_human alone, because a hand
# can end while the human still holds tiles — a lay-down claim, or either
# hand-ends-early toggle firing. Without it the result banner appears but the
# hand stays live underneath: the tiles are still hit-testable, so tapping one
# resumes the play chain on top of an already-resolved hand.
var _hand_over: bool = false
var _armed_domino: Domino = null   # human's pre-selected play for later this trick, if any
var _current_trick_reasons: Array = []  # accumulates {player, domino, reason} during a trick
var _last_play_reason: String = ""      # set by AI chooser; read by _execute_play
var replay_panel: Control = null
var _replay_trick_index: int = 0
var _replay_btn: Button = null
var _continue_btn: Button = null
var _replay_back_btn: Button = null
var _new_game_btn: Button = null
var _replay_trick_label: Label = null
var _replay_inner_panel: PanelContainer = null
var _replay_hand_containers: Array = []
var _replay_played_containers: Array = []
var _replay_bubble_labels: Array = []
var _flag_panel: PanelContainer = null
var _flag_toggle_bidding: Button = null
var _flag_toggle_gameplay: Button = null
var _flag_toggle_explanation: Button = null
var _flag_note_edit: LineEdit = null
var waiting_for_trump: bool = false
var waiting_for_nello_mode: bool = false
var waiting_for_bid: bool = false
var human_is_forced: bool = false
var _human_bid_position: int = -1

# Viewport-proportional tile sizes — recomputed on resize by _on_viewport_resized()
var TILE_FULL: Vector2
var TILE_SMALL: Vector2
var TILE_PLAYED: Vector2
var TILE_REPLAY_HAND: Vector2
var TILE_REPLAY_PLAYED: Vector2

# Proportional font scaling (Mechanism 1: registry for stock Controls)
const DESIGN_WIDTH: float = 576.0
const MIN_SCALE: float = 0.75
const MAX_SCALE: float = 1.5
var font_scale: float = 1.0
var _font_registry: Array = []

func _ready():
	_build_fonts()
	_build_ui()
	seat_profiles = _load_seat_assignments()
	# Apply the saved back before anything renders — it's a display preference
	# now, so it must be live even on screens reached without picking a ruleset.
	_update_domino_back_texture()
	_start_game()
	get_viewport().size_changed.connect(_on_viewport_resized)

# ─── UI CONSTRUCTION ──────────────────────────────────────────────────────────


func _player_label(pid: int) -> String:
	if pid == human_seat:
		return "You"
	elif pid == (human_seat + 2) % 4:
		return "Partner"
	elif pid == (human_seat + 1) % 4:
		return "Right Opponent"
	else:
		return "Left Opponent"

# ─── TYPEFACES ────────────────────────────────────────────────────────────────
# Nunito is a variable font whose wght axis runs 200–1000 with a DEFAULT of 200
# (ExtraLight), not 400 — so every weight has to be an explicit FontVariation
# or the whole UI renders hairline-thin.
#
# Every variation below re-attaches the same symbol/emoji fallback chain that
# fonts/default_font.tres (wired as project.godot's theme/custom_font) already
# supplies. That chain is load-bearing: the UI leans on glyphs no Latin
# text face carries — ● ⚙ ✕ ⌂ ★ ▶ ▼ ← → ✓ and the 🚩/🎉 emoji. Handing a bare
# FontFile to Theme.default_font drops the fallbacks and turns all of those
# into tofu boxes.
#
# One more trap, confirmed by measurement rather than by reading the API:
# FontVariation.variation_opentype keys must be INTEGER OpenType tags, not the
# axis name. {"wght": 815} is accepted and stored verbatim, but silently never
# applied — every weight then renders at the font's default instance, which for
# Nunito is 200. Widths for "MMMMMMMMMM" @40px make it plain:
#     {"wght": 400} -> 338.00      {"wght": 815} -> 338.00   (no-op)
#     {tag:    400} -> 342.00      {tag:    815} -> 351.00   (live)
# so the tag goes through TextServer.name_to_tag() below.
#
# FONT_WEIGHT_BASE is the lightest weight anything in this UI uses — the floor,
# not a typographic "regular". Nunito reads thin on dark felt at small sizes, so
# the body weight sits well above 400.
const FONT_WEIGHT_BASE  := 777
const FONT_WEIGHT_HEAVY := 815

func _build_fonts():
	var nunito_base: FontFile = load("res://fonts/Nunito-VariableFont_wght.ttf")
	var rye_base: FontFile = load("res://fonts/Rye-Regular.ttf")

	var fallbacks: Array[Font] = [
		load("res://fonts/NotoSansSymbols.ttf"),
		load("res://fonts/NotoSansSymbols2.ttf"),
		load("res://fonts/NotoEmoji.ttf"),
	]

	_font_nunito_regular = _make_variation(nunito_base, fallbacks, FONT_WEIGHT_BASE)
	_font_nunito_heavy   = _make_variation(nunito_base, fallbacks, FONT_WEIGHT_HEAVY)
	# Rye is a single static cut — no wght axis to sample, so no variation_opentype.
	_font_rye            = _make_variation(rye_base, fallbacks, 0)

	# The two hand-drawn Controls call ThemeDB.fallback_font in _draw() and so
	# never see a Theme on root — hand them the font directly (same static-var
	# pattern as DominoTile.custom_back_texture).
	DrumPicker.custom_font = _font_nunito_regular
	MarksDisplay.custom_font = _font_nunito_heavy
	MarksDisplay.label_font = _font_rye

func _make_variation(base: FontFile, fallbacks: Array[Font], weight: int) -> FontVariation:
	var fv = FontVariation.new()
	fv.base_font = base
	if weight > 0:
		var wght_tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
		fv.variation_opentype = {wght_tag: weight}
	fv.fallbacks = fallbacks
	return fv

func _build_ui():
	var vp_w: float = get_viewport().get_visible_rect().size.x
	var tile_w: float = min(64.0, floor(vp_w / 9.0))
	TILE_FULL         = Vector2(tile_w,        tile_w * 2.0)
	TILE_SMALL        = Vector2(tile_w * 0.85, tile_w * 2.0 * 0.85)
	TILE_PLAYED       = Vector2(tile_w * PLAY_TILE_SCALE, tile_w * 2.0 * PLAY_TILE_SCALE)
	TILE_REPLAY_HAND   = Vector2(tile_w * 0.65, tile_w * 2.0 * 0.65)
	TILE_REPLAY_PLAYED = Vector2(tile_w * 0.85, tile_w * 2.0 * 0.85)
	font_scale = clamp(vp_w / DESIGN_WIDTH, MIN_SCALE, MAX_SCALE)

	# Root Control that fills the window
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.set_offsets_preset(Control.PRESET_FULL_RECT)
	root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.grow_vertical = Control.GROW_DIRECTION_BOTH

	# One Theme on root is the whole delivery mechanism — every stock Control
	# below inherits Nunito through Godot's ancestor theme lookup, so
	# _scaled_font() keeps owning size only and none of its call sites change.
	var theme = Theme.new()
	theme.default_font = _font_nunito_regular
	root.theme = theme

	add_child(root)

	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.13, 0.30, 0.18)  # Felt green
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	# Bottom-left current-bid reminder — a floating overlay, independent of
	# the main vbox layout below, so it stays put regardless of what's
	# happening in the play area. Hidden (empty text) until a bid is won;
	# see _update_bid_reminder().
	bid_reminder_label = Label.new()
	bid_reminder_label.text = ""
	bid_reminder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bid_reminder_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	bid_reminder_label.add_theme_color_override("font_color", Color(0.90, 0.90, 0.85))
	bid_reminder_label.add_theme_constant_override("line_spacing", BID_REMINDER_LINE_SPACING)
	# Sized on its own account now rather than borrowed from status_label — the
	# contract is worth reading at a glance, so it runs deliberately larger.
	# _scaled_font() also registers it, so it tracks font_scale on a resize,
	# which the old copied literal never did.
	_scaled_font(bid_reminder_label, BID_REMINDER_FONT_SIZE)
	bid_reminder_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	# Bottom-pinned, growing upward. Normally three lines, but the longest
	# contract wording wraps to four, and a fourth line growing DOWNWARD from a
	# fixed top ran off the bottom of the window. Pinning the bottom puts the
	# extra line above instead, into the empty felt below the play panel.
	# Offsets are set directly rather than through `position`, which under this
	# grow direction folds the label's current line count into what it computes.
	bid_reminder_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bid_reminder_label.offset_left = PLAY_AREA_INSET
	bid_reminder_label.offset_bottom = BID_REMINDER_BOTTOM
	bid_reminder_label.offset_top = BID_REMINDER_BOTTOM - 1.0
	root.add_child(bid_reminder_label)
	_refresh_bid_reminder_width()

	# Main vertical layout
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	root.add_child(vbox)

	# --- Top row: US panel | partner hand | THEM panel ---
	# The MarginContainer is the row as far as _show_game_board() cares (it
	# toggles _game_top_row), so hiding the board takes the inset with it
	# rather than leaving a strip of dead margin above the menu.
	_game_top_row = MarginContainer.new()
	_game_top_row.add_theme_constant_override("margin_left", PLAY_AREA_INSET)
	_game_top_row.add_theme_constant_override("margin_right", PLAY_AREA_INSET)
	_game_top_row.add_theme_constant_override("margin_top", TEAM_COL_INSET_TOP)
	vbox.add_child(_game_top_row)

	var top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	_game_top_row.add_child(top_row)

	# US side (team 0 = player 0 & 2)
	var us_vbox = VBoxContainer.new()
	us_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	us_vbox.custom_minimum_size = Vector2(132, 0)
	top_row.add_child(us_vbox)

	_us_marks = MarksDisplay.new()
	_us_marks.set_team(Color(0.35, 0.85, 0.45), "US")
	us_vbox.add_child(_us_marks)

	var us_scroll = ScrollContainer.new()
	us_scroll.custom_minimum_size = Vector2(132, 100)
	us_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	us_vbox.add_child(us_scroll)
	_us_tricks = TrickPile.new()
	us_scroll.add_child(_us_tricks)
	_tricks_scroll[0] = us_scroll

	# Partner hand (center), with the points readout tucked under it. This band's
	# height is set by the US/THEM columns beside it, and the partner's tiles are
	# shorter than that, so the readout rides in slack that already existed —
	# it costs the play area below nothing, which is the whole point of moving it
	# out of play_vbox. The tiles take the leftover room via EXPAND_FILL so they
	# stay centred in the band and the readout stays pinned to its bottom edge.
	var partner_col = VBoxContainer.new()
	partner_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(partner_col)

	opponent_top_container = HBoxContainer.new()
	opponent_top_container.alignment = BoxContainer.ALIGNMENT_CENTER
	opponent_top_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opponent_top_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	opponent_top_container.custom_minimum_size = Vector2(0, 80)
	partner_col.add_child(opponent_top_container)

	info_label = Label.new()
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_color_override("font_color", Color.WHITE)
	partner_col.add_child(info_label)

	# THEM side (team 1 = player 1 & 3)
	var them_vbox = VBoxContainer.new()
	them_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	them_vbox.custom_minimum_size = Vector2(132, 0)
	top_row.add_child(them_vbox)

	_them_marks = MarksDisplay.new()
	_them_marks.set_team(Color(0.85, 0.35, 0.35), "THEM")
	them_vbox.add_child(_them_marks)

	var them_scroll = ScrollContainer.new()
	them_scroll.custom_minimum_size = Vector2(132, 100)
	them_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	them_vbox.add_child(them_scroll)
	_them_tricks = TrickPile.new()
	them_scroll.add_child(_them_tricks)
	_tricks_scroll[1] = them_scroll

	# Both scroll boxes exist now, so the floating half of the trick lists can be
	# built. Added to root at this point on purpose: after vbox, so the expanded
	# panel draws over the play area, but before _bubble_overlay, so the seat bid
	# bubbles stay on top of it.
	_build_tricks_overlays(root)

	# --- Main menu panel — dark card centered over the felt ---
	main_menu_panel = PanelContainer.new()
	main_menu_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main_menu_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_menu_panel.custom_minimum_size = Vector2(480, 0)
	main_menu_panel.visible = false
	var menu_style = StyleBoxFlat.new()
	menu_style.bg_color = Color(0.06, 0.06, 0.09, 0.82)
	menu_style.corner_radius_top_left = 10
	menu_style.corner_radius_top_right = 10
	menu_style.corner_radius_bottom_left = 10
	menu_style.corner_radius_bottom_right = 10
	menu_style.content_margin_left = 32
	menu_style.content_margin_right = 32
	menu_style.content_margin_top = 40
	menu_style.content_margin_bottom = 40
	main_menu_panel.add_theme_stylebox_override("panel", menu_style)
	vbox.add_child(main_menu_panel)

	var menu_vbox = VBoxContainer.new()
	menu_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_vbox.add_theme_constant_override("separation", 16)
	main_menu_panel.add_child(menu_vbox)

	# Decorative domino pip row
	var pip_row = HBoxContainer.new()
	pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pip_row.add_theme_constant_override("separation", 20)
	menu_vbox.add_child(pip_row)
	for pip_counts in [[1, 2], [3, 4], [2, 6]]:
		var dom_vbox = VBoxContainer.new()
		dom_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		dom_vbox.add_theme_constant_override("separation", 2)
		pip_row.add_child(dom_vbox)
		for half in pip_counts:
			var half_row = HBoxContainer.new()
			half_row.alignment = BoxContainer.ALIGNMENT_CENTER
			half_row.add_theme_constant_override("separation", 3)
			dom_vbox.add_child(half_row)
			for _p in range(half if half <= 3 else 3):
				var dot = Label.new()
				dot.text = "●"
				_scaled_font(dot, 8)
				dot.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88, 0.55))
				half_row.add_child(dot)

	# "42" and its subtitle read as one wordmark, so they get their own box with
	# its own separation instead of inheriting menu_vbox's 16px. Rye reserves a
	# descender band under the title (46px at this size) that the digits never
	# use, and it dwarfs any separation constant — which is why the subtitle sat
	# adrift below the title. Close that band up and keep MENU_WORDMARK_AIR of
	# real space, derived from the live metric so it holds at any font_scale.
	var title_px: int = int(round(MENU_TITLE_SIZE * font_scale))
	var wordmark = VBoxContainer.new()
	wordmark.add_theme_constant_override("separation",
		int(round(MENU_WORDMARK_AIR - _font_rye.get_descent(title_px))))
	menu_vbox.add_child(wordmark)

	var menu_title = Label.new()
	menu_title.text = "42"
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scaled_font(menu_title, MENU_TITLE_SIZE)
	menu_title.add_theme_font_override("font", _font_rye)
	menu_title.add_theme_color_override("font_color", Color.WHITE)
	wordmark.add_child(menu_title)

	var menu_subtitle = Label.new()
	menu_subtitle.text = "Texas Dominos"
	menu_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scaled_font(menu_subtitle, MENU_SUBTITLE_SIZE)
	menu_subtitle.add_theme_font_override("font", _font_rye)
	menu_subtitle.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	wordmark.add_child(menu_subtitle)

	var menu_spacer = Control.new()
	menu_spacer.custom_minimum_size = Vector2(0, 24)
	menu_vbox.add_child(menu_spacer)

	var play_btn = Button.new()
	play_btn.text = "Play"
	play_btn.custom_minimum_size = Vector2(220, 64)
	play_btn.add_theme_font_override("font", _font_nunito_heavy)
	play_btn.pressed.connect(_on_menu_play_pressed)
	menu_vbox.add_child(play_btn)

	var rules_btn = Button.new()
	rules_btn.text = "Choose Rules"
	rules_btn.custom_minimum_size = Vector2(220, 64)
	rules_btn.add_theme_font_override("font", _font_nunito_heavy)
	rules_btn.pressed.connect(_on_menu_rules_pressed)
	menu_vbox.add_child(rules_btn)

	var diff_menu_btn = Button.new()
	diff_menu_btn.text = "Difficulty"
	diff_menu_btn.custom_minimum_size = Vector2(220, 64)
	diff_menu_btn.add_theme_font_override("font", _font_nunito_heavy)
	diff_menu_btn.pressed.connect(_on_menu_difficulty_pressed)
	menu_vbox.add_child(diff_menu_btn)

	var profiles_menu_btn = Button.new()
	profiles_menu_btn.text = "Profiles"
	profiles_menu_btn.custom_minimum_size = Vector2(220, 64)
	profiles_menu_btn.add_theme_font_override("font", _font_nunito_heavy)
	profiles_menu_btn.pressed.connect(_on_menu_profiles_pressed)
	menu_vbox.add_child(profiles_menu_btn)

	# --- Preset picker panel ---
	preset_panel = PanelContainer.new()
	preset_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	preset_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preset_panel.custom_minimum_size = Vector2(480, 0)
	preset_panel.visible = false
	var preset_style = StyleBoxFlat.new()
	preset_style.bg_color = Color(0.06, 0.06, 0.09, 0.82)
	preset_style.corner_radius_top_left = 10
	preset_style.corner_radius_top_right = 10
	preset_style.corner_radius_bottom_left = 10
	preset_style.corner_radius_bottom_right = 10
	preset_style.content_margin_left = 32
	preset_style.content_margin_right = 32
	preset_style.content_margin_top = 40
	preset_style.content_margin_bottom = 40
	preset_panel.add_theme_stylebox_override("panel", preset_style)
	vbox.add_child(preset_panel)

	var preset_vbox = VBoxContainer.new()
	preset_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	preset_vbox.add_theme_constant_override("separation", 16)
	preset_panel.add_child(preset_vbox)

	var preset_title = Label.new()
	preset_title.text = "Choose Your Rules"
	preset_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scaled_font(preset_title, 28)
	preset_title.add_theme_color_override("font_color", Color.WHITE)
	preset_vbox.add_child(preset_title)

	var preset_subtitle = Label.new()
	preset_subtitle.text = "You can change this anytime from the menu"
	preset_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scaled_font(preset_subtitle, 14)
	preset_subtitle.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	preset_vbox.add_child(preset_subtitle)

	_preset_status_label = Label.new()
	_preset_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preset_status_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	_preset_status_label.visible = false
	preset_vbox.add_child(_preset_status_label)

	var preset_scroll = ScrollContainer.new()
	preset_scroll.custom_minimum_size = Vector2(240, 340)
	preset_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preset_vbox.add_child(preset_scroll)

	_preset_btn_container = VBoxContainer.new()
	_preset_btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_preset_btn_container.add_theme_constant_override("separation", 8)
	_preset_btn_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_scroll.add_child(_preset_btn_container)

	var preset_back_btn = Button.new()
	preset_back_btn.text = "← Menu"
	preset_back_btn.custom_minimum_size = Vector2(160, 48)
	preset_back_btn.pressed.connect(func():
		_close_slot_options_menu()
		preset_panel.visible = false
		main_menu_panel.visible = true
	)
	preset_vbox.add_child(preset_back_btn)

	# --- Difficulty picker panel ---
	difficulty_panel = PanelContainer.new()
	difficulty_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	difficulty_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	difficulty_panel.custom_minimum_size = Vector2(480, 0)
	difficulty_panel.visible = false
	var diff_style = StyleBoxFlat.new()
	diff_style.bg_color = Color(0.06, 0.06, 0.09, 0.82)
	diff_style.corner_radius_top_left = 10
	diff_style.corner_radius_top_right = 10
	diff_style.corner_radius_bottom_left = 10
	diff_style.corner_radius_bottom_right = 10
	diff_style.content_margin_left = 32
	diff_style.content_margin_right = 32
	diff_style.content_margin_top = 32
	diff_style.content_margin_bottom = 32
	difficulty_panel.add_theme_stylebox_override("panel", diff_style)
	vbox.add_child(difficulty_panel)

	var diff_vbox = VBoxContainer.new()
	diff_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_vbox.add_theme_constant_override("separation", 16)
	difficulty_panel.add_child(diff_vbox)

	var diff_title = Label.new()
	diff_title.text = "Choose Your Experience"
	diff_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scaled_font(diff_title, 22)
	diff_title.add_theme_color_override("font_color", Color.WHITE)
	diff_vbox.add_child(diff_title)

	var diff_subtitle = Label.new()
	diff_subtitle.text = "You can change this anytime from settings"
	diff_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scaled_font(diff_subtitle, 13)
	diff_subtitle.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	diff_vbox.add_child(diff_subtitle)

	var diff_scroll = ScrollContainer.new()
	diff_scroll.custom_minimum_size = Vector2(240, 260)
	diff_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	diff_vbox.add_child(diff_scroll)

	_difficulty_btn_container = VBoxContainer.new()
	_difficulty_btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_difficulty_btn_container.add_theme_constant_override("separation", 8)
	_difficulty_btn_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_scroll.add_child(_difficulty_btn_container)

	var diff_back_btn = Button.new()
	diff_back_btn.text = "← Menu"
	diff_back_btn.custom_minimum_size = Vector2(100, 40)
	diff_back_btn.pressed.connect(func():
		difficulty_panel.visible = false
		main_menu_panel.visible = true
	)
	diff_vbox.add_child(diff_back_btn)

	# --- Profiles panel — create profiles, assign to non-human seats ---
	profile_panel = PanelContainer.new()
	profile_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	profile_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	profile_panel.custom_minimum_size = Vector2(480, 0)
	profile_panel.visible = false
	var profile_style = StyleBoxFlat.new()
	profile_style.bg_color = Color(0.06, 0.06, 0.09, 0.82)
	profile_style.corner_radius_top_left = 10
	profile_style.corner_radius_top_right = 10
	profile_style.corner_radius_bottom_left = 10
	profile_style.corner_radius_bottom_right = 10
	profile_style.content_margin_left = 32
	profile_style.content_margin_right = 32
	profile_style.content_margin_top = 32
	profile_style.content_margin_bottom = 32
	profile_panel.add_theme_stylebox_override("panel", profile_style)
	vbox.add_child(profile_panel)

	var profile_outer_vbox = VBoxContainer.new()
	profile_outer_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	profile_outer_vbox.add_theme_constant_override("separation", 16)
	profile_panel.add_child(profile_outer_vbox)

	var profile_title = Label.new()
	profile_title.text = "Profiles"
	profile_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scaled_font(profile_title, 22)
	profile_title.add_theme_color_override("font_color", Color.WHITE)
	profile_outer_vbox.add_child(profile_title)

	var profile_subtitle = Label.new()
	profile_subtitle.text = "Name your AI opponents and partner"
	profile_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scaled_font(profile_subtitle, 13)
	profile_subtitle.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	profile_outer_vbox.add_child(profile_subtitle)

	# No ScrollContainer. There are exactly four rows (New Profile + three seats),
	# so the list is a known, small, fixed height — the scroll box was clipping the
	# last seat behind a scrollbar for no benefit. Added straight to the column and
	# allowed to size itself, which pushes the Menu button down to make room.
	_profile_content_vbox = VBoxContainer.new()
	_profile_content_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_profile_content_vbox.add_theme_constant_override("separation", 12)
	_profile_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_outer_vbox.add_child(_profile_content_vbox)

	var profile_back_spacer = Control.new()
	profile_back_spacer.custom_minimum_size = Vector2(0, 8)
	profile_outer_vbox.add_child(profile_back_spacer)

	var profile_back_btn = Button.new()
	profile_back_btn.text = "← Menu"
	profile_back_btn.custom_minimum_size = Vector2(100, 40)
	profile_back_btn.pressed.connect(func():
		profile_panel.visible = false
		main_menu_panel.visible = true
	)
	profile_outer_vbox.add_child(profile_back_btn)

	# --- Middle row: left opponent | play area | right opponent ---
	_game_mid_row = HBoxContainer.new()
	var hbox_mid = _game_mid_row
	hbox_mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox_mid.add_theme_constant_override("separation", MID_ROW_SEPARATION)
	vbox.add_child(hbox_mid)

	opponent_left_container = VBoxContainer.new()
	opponent_left_container.alignment = BoxContainer.ALIGNMENT_CENTER
	opponent_left_container.custom_minimum_size = Vector2(SIDE_SEAT_COL_W, 0)
	opponent_left_container.add_theme_constant_override("separation", -55)
	hbox_mid.add_child(opponent_left_container)

	# Play area (center)
	var play_area_panel = PanelContainer.new()
	play_area_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_mid.add_child(play_area_panel)

	play_vbox = VBoxContainer.new()
	play_area_panel.add_child(play_vbox)

	# First child of the play area now that the points readout has moved up into
	# the top band — the trump call takes over the spot points used to hold.
	trump_indicator_label = Label.new()
	trump_indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trump_indicator_label.add_theme_color_override("font_color", Color(0.95, 0.80, 0.15))
	_scaled_font(trump_indicator_label, 20)
	play_vbox.add_child(trump_indicator_label)

	# Plain Control, not an HBoxContainer: _add_to_play_area() positions each
	# played tile toward the seat that played it, so no row-flow layout wanted.
	play_area_container = Control.new()
	play_area_container.custom_minimum_size = Vector2(0, _play_area_min_height())
	# Takes up whatever the play panel has left over, so collapsing the
	# reservation below (see _refresh_play_area_reservation) frees height for
	# the player's hand without the pickers jumping to the top of the felt.
	play_area_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# _place_in_play_area() centres against the container's size as it is at
	# call time, so every child goes stale the moment the container changes
	# height — which it now does whenever a picker opens or closes, not just on
	# a window resize. Re-place on the container's own resized signal so there
	# is one owner for that, whatever the cause.
	play_area_container.resized.connect(_replace_play_area_children)
	play_vbox.add_child(play_area_container)

	# --- Small-end opening lead toggle ---
	# Floats immediately above the yellow status line, and costs the layout
	# nothing.
	#
	# That second part is the whole point. A hidden Control contributes no minimum
	# size to its container, so a button that merely *appears* grows the column it
	# lives in — which is why the player's hand slid off the bottom of the screen
	# the moment this became visible, and why simply moving it between containers
	# didn't help. The holder below is a zero-height Control: plain Controls don't
	# lay their children out, so the button keeps the offsets set here and the
	# holder adds nothing to play_vbox's minimum height whether it's shown or not.
	# It renders over the empty felt above the status line, exactly where it sat
	# before, but the hand no longer moves when it toggles.
	var se_holder = Control.new()
	se_holder.custom_minimum_size = Vector2(0, 0)
	se_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE   # children still get input
	play_vbox.add_child(se_holder)

	_small_end_toggle_btn = Button.new()
	_small_end_toggle_btn.text = "Open with Small End"
	_small_end_toggle_btn.toggle_mode = true
	_small_end_toggle_btn.visible = false
	# Centred on the holder's width and lifted clear of it, so it sits in the felt
	# rather than on top of the status text.
	_small_end_toggle_btn.anchor_left = 0.5
	_small_end_toggle_btn.anchor_right = 0.5
	_small_end_toggle_btn.anchor_top = 0.0
	_small_end_toggle_btn.anchor_bottom = 0.0
	_small_end_toggle_btn.offset_left = -SMALL_END_BTN_W / 2.0
	_small_end_toggle_btn.offset_right = SMALL_END_BTN_W / 2.0
	_small_end_toggle_btn.offset_top = -SMALL_END_BTN_H - 6.0
	_small_end_toggle_btn.offset_bottom = -6.0
	_small_end_toggle_btn.toggled.connect(_on_small_end_toggle_pressed)
	se_holder.add_child(_small_end_toggle_btn)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color.YELLOW)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	play_vbox.add_child(status_label)

	# --- Bid panel lives inside the play area ---
	bid_panel = PanelContainer.new()
	bid_panel.visible = false
	play_vbox.add_child(bid_panel)

	var bid_vbox = VBoxContainer.new()
	bid_panel.add_child(bid_vbox)

	var bid_label = Label.new()
	bid_label.text = "Your Bid:"
	bid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bid_vbox.add_child(bid_label)

	bid_buttons = HBoxContainer.new()
	bid_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	bid_vbox.add_child(bid_buttons)

	opponent_right_container = VBoxContainer.new()
	opponent_right_container.alignment = BoxContainer.ALIGNMENT_CENTER
	opponent_right_container.custom_minimum_size = Vector2(SIDE_SEAT_COL_W, 0)
	opponent_right_container.add_theme_constant_override("separation", -55)
	hbox_mid.add_child(opponent_right_container)

	# --- Trump panel lives inside the play area ---
	trump_panel = PanelContainer.new()
	trump_panel.visible = false
	play_vbox.add_child(trump_panel)

	var trump_vbox = VBoxContainer.new()
	trump_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	trump_vbox.add_theme_constant_override("separation", 6)
	trump_panel.add_child(trump_vbox)

	var trump_label = Label.new()
	trump_label.text = "Call Trump Suit:"
	trump_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scaled_font(trump_label, 14)
	trump_vbox.add_child(trump_label)

	# Two rows of compact suit buttons so they don't overflow
	var row1 = HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.add_theme_constant_override("separation", 8)
	trump_vbox.add_child(row1)
	var row2 = HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 8)
	trump_vbox.add_child(row2)

	var suit_names = ["Blanks", "Ones", "Twos", "Threes", "Fours", "Fives", "Sixes"]
	trump_buttons = row1  # keep ref for compatibility
	for suit in range(7):
		var btn = Button.new()
		btn.text = "%d  %s" % [suit, suit_names[suit]]
		btn.custom_minimum_size = Vector2(100, 40)
		btn.pressed.connect(_on_trump_selected.bind(suit))
		if suit < 4:
			row1.add_child(btn)
		else:
			row2.add_child(btn)

	# Special trump options (Doubles, Doubles Reversed, Follow Me) — share one row
	_special_trump_sep = HSeparator.new()
	_special_trump_sep.visible = false
	trump_vbox.add_child(_special_trump_sep)

	var special_row = HBoxContainer.new()
	special_row.alignment = BoxContainer.ALIGNMENT_CENTER
	special_row.add_theme_constant_override("separation", 8)
	trump_vbox.add_child(special_row)

	_doubles_trump_btn = Button.new()
	_doubles_trump_btn.text = "Doubles  (Trump Suit)"
	_doubles_trump_btn.custom_minimum_size = Vector2(150, 40)
	_doubles_trump_btn.visible = false
	_doubles_trump_btn.pressed.connect(func():
		game.active_doubles_trump_reversed = false
		_on_trump_selected(Domino.DOUBLES_TRUMP)
	)
	special_row.add_child(_doubles_trump_btn)

	_doubles_trump_reversed_btn = Button.new()
	_doubles_trump_reversed_btn.text = "Doubles  (Reversed)"
	_doubles_trump_reversed_btn.custom_minimum_size = Vector2(150, 40)
	_doubles_trump_reversed_btn.visible = false
	_doubles_trump_reversed_btn.pressed.connect(func():
		game.active_doubles_trump_reversed = true
		_on_trump_selected(Domino.DOUBLES_TRUMP)
	)
	special_row.add_child(_doubles_trump_reversed_btn)

	_follow_me_btn = Button.new()
	_follow_me_btn.text = "No Trump  (Follow Me)"
	_follow_me_btn.custom_minimum_size = Vector2(150, 40)
	_follow_me_btn.visible = false
	_follow_me_btn.pressed.connect(_on_trump_selected.bind(-1))
	special_row.add_child(_follow_me_btn)

	# --- Nello doubles-mode panel ---
	nello_panel = PanelContainer.new()
	nello_panel.visible = false
	play_vbox.add_child(nello_panel)

	var nello_vbox = VBoxContainer.new()
	nello_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	nello_vbox.add_theme_constant_override("separation", 6)
	nello_panel.add_child(nello_vbox)

	var nello_label = Label.new()
	nello_label.text = "How do doubles play?"
	nello_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scaled_font(nello_label, 14)
	nello_vbox.add_child(nello_label)

	var nello_row = HBoxContainer.new()
	nello_row.alignment = BoxContainer.ALIGNMENT_CENTER
	nello_row.add_theme_constant_override("separation", 8)
	nello_vbox.add_child(nello_row)

	for ml in [["Doubles High", "high"], ["Doubles Low", "low"], ["Own Suit", "own_suit"]]:
		var btn = Button.new()
		btn.text = ml[0]
		btn.custom_minimum_size = Vector2(110, 40)
		btn.pressed.connect(_on_nello_mode_selected.bind(ml[1]))
		nello_row.add_child(btn)

	_nello_reversed_btn = Button.new()
	_nello_reversed_btn.text = "Own Suit (Reversed)"
	_nello_reversed_btn.custom_minimum_size = Vector2(140, 40)
	_nello_reversed_btn.visible = false
	_nello_reversed_btn.pressed.connect(_on_nello_mode_selected.bind("own_suit_reversed"))
	nello_row.add_child(_nello_reversed_btn)

	# --- Nello blind-exchange panel ---
	nello_exchange_panel = PanelContainer.new()
	nello_exchange_panel.visible = false
	play_vbox.add_child(nello_exchange_panel)

	var exchange_vbox = VBoxContainer.new()
	exchange_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	exchange_vbox.add_theme_constant_override("separation", 6)
	nello_exchange_panel.add_child(exchange_vbox)

	var exchange_label = Label.new()
	exchange_label.text = "Exchange a domino with your partner — tap one to send, or decline."
	exchange_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scaled_font(exchange_label, 14)
	exchange_vbox.add_child(exchange_label)

	# Partner's already-committed blind pick — face-down, cosmetic only.
	# Any placeholder Domino works since the face never shows; not wired to
	# _pending_partner_give so the value can never leak visually.
	var partner_pick_row = HBoxContainer.new()
	partner_pick_row.alignment = BoxContainer.ALIGNMENT_CENTER
	exchange_vbox.add_child(partner_pick_row)
	_nello_exchange_partner_tile = DominoTile.new()
	_nello_exchange_partner_tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_nello_exchange_partner_tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	partner_pick_row.add_child(_nello_exchange_partner_tile)
	_nello_exchange_partner_tile.setup(Domino.new(0, 0), false)
	_nello_exchange_partner_tile.custom_minimum_size = TILE_FULL

	nello_exchange_hand_container = HBoxContainer.new()
	nello_exchange_hand_container.alignment = BoxContainer.ALIGNMENT_CENTER
	exchange_vbox.add_child(nello_exchange_hand_container)

	# All four pickers exist by now, so wire the one hook that keeps the play
	# area's height reservation honest no matter which of them opens or closes.
	for picker in [bid_panel, trump_panel, nello_panel, nello_exchange_panel]:
		picker.visibility_changed.connect(_refresh_play_area_reservation)

	# --- Human player hand ---
	player_hand_container = HBoxContainer.new()
	player_hand_container.alignment = BoxContainer.ALIGNMENT_CENTER
	player_hand_container.custom_minimum_size = Vector2(0, 100)
	vbox.add_child(player_hand_container)

	# Overlay for bid bubbles — sits on top of everything, ignores mouse
	_bubble_overlay = Control.new()
	_bubble_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bubble_overlay.set_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bubble_overlay)

	# --- Gear button (top-right, always visible) ---
	var gear_btn = Button.new()
	gear_btn.text = "⚙"
	gear_btn.custom_minimum_size = Vector2(40, 40)
	gear_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	gear_btn.position = Vector2(-48, 8)
	gear_btn.pressed.connect(_show_settings_panel)
	root.add_child(gear_btn)

	# --- Lay Down button (bottom-right, near the player's own hand) —
	# right edge on the play-area panel's right vertical, top level with the
	# bid reminder in the opposite corner, so the two bottom-corner overlays
	# read as a matched pair framing the player's hand.
	# Visibility is driven entirely by _update_laydown_button_visibility(),
	# called whenever it becomes the human's turn (_play_next_in_trick()).
	const LAYDOWN_BTN_W := 120
	laydown_btn = Button.new()
	laydown_btn.text = "Lay Down"
	laydown_btn.custom_minimum_size = Vector2(LAYDOWN_BTN_W, 44)
	laydown_btn.visible = false
	laydown_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	laydown_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	laydown_btn.grow_vertical = Control.GROW_DIRECTION_END
	laydown_btn.position = Vector2(-(LAYDOWN_BTN_W + PLAY_AREA_INSET), CORNER_OVERLAY_TOP)
	laydown_btn.pressed.connect(_on_laydown_button_pressed)
	root.add_child(laydown_btn)

	# --- Settings overlay (shell built once; content rebuilt on open) ---
	settings_panel = Control.new()
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.visible = false
	root.add_child(settings_panel)

	var s_dim = ColorRect.new()
	s_dim.color = Color(0, 0, 0, 0.65)
	s_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.add_child(s_dim)

	var s_center = CenterContainer.new()
	s_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.add_child(s_center)

	_settings_panel_inner = PanelContainer.new()
	var s_style = StyleBoxFlat.new()
	s_style.bg_color = Color(0.06, 0.06, 0.09, 0.95)
	s_style.corner_radius_top_left = 6
	s_style.corner_radius_top_right = 6
	s_style.corner_radius_bottom_left = 6
	s_style.corner_radius_bottom_right = 6
	_settings_panel_inner.add_theme_stylebox_override("panel", s_style)
	s_center.add_child(_settings_panel_inner)

	var s_margin = MarginContainer.new()
	s_margin.add_theme_constant_override("margin_left", 12)
	s_margin.add_theme_constant_override("margin_right", 12)
	s_margin.add_theme_constant_override("margin_top", 12)
	s_margin.add_theme_constant_override("margin_bottom", 12)
	s_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings_panel_inner.add_child(s_margin)

	_settings_scroll = ScrollContainer.new()
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s_margin.add_child(_settings_scroll)

	_settings_content_vbox = VBoxContainer.new()
	_settings_content_vbox.add_theme_constant_override("separation", 10)
	_settings_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_scroll.add_child(_settings_content_vbox)

	# --- Replay overlay (full-rect, sits on top of everything) ---
	replay_panel = Control.new()
	replay_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	replay_panel.visible = false
	root.add_child(replay_panel)

	var r_dim = ColorRect.new()
	r_dim.color = Color(0, 0, 0, 0.75)
	r_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	replay_panel.add_child(r_dim)

	var r_center = CenterContainer.new()
	r_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	replay_panel.add_child(r_center)

	_replay_inner_panel = PanelContainer.new()
	var r_style = StyleBoxFlat.new()
	r_style.bg_color = Color(0.06, 0.06, 0.09, 0.95)
	r_style.corner_radius_top_left = 6
	r_style.corner_radius_top_right = 6
	r_style.corner_radius_bottom_left = 6
	r_style.corner_radius_bottom_right = 6
	r_style.content_margin_left = 12
	r_style.content_margin_right = 12
	r_style.content_margin_top = 12
	r_style.content_margin_bottom = 12
	_replay_inner_panel.add_theme_stylebox_override("panel", r_style)
	r_center.add_child(_replay_inner_panel)

	var r_vbox = VBoxContainer.new()
	r_vbox.add_theme_constant_override("separation", 4)
	_replay_inner_panel.add_child(r_vbox)

	# Top bar: trick counter + close button
	var r_top_bar = HBoxContainer.new()
	r_top_bar.add_theme_constant_override("separation", 4)
	r_vbox.add_child(r_top_bar)

	_replay_trick_label = Label.new()
	_replay_trick_label.text = "Replay — Trick 1 of 7"
	_scaled_font(_replay_trick_label, 16)
	_replay_trick_label.add_theme_color_override("font_color", Color.WHITE)
	_replay_trick_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_top_bar.add_child(_replay_trick_label)

	var r_flag_btn = Button.new()
	r_flag_btn.text = "🚩 Flag"
	r_flag_btn.custom_minimum_size = Vector2(70, 36)
	r_flag_btn.pressed.connect(_toggle_flag_panel)
	r_top_bar.add_child(r_flag_btn)

	var r_close_btn = Button.new()
	r_close_btn.text = "✕"
	r_close_btn.custom_minimum_size = Vector2(36, 36)
	r_close_btn.pressed.connect(_exit_replay)
	r_top_bar.add_child(r_close_btn)

	r_vbox.add_child(HSeparator.new())

	# ── Flag panel (hidden by default; toggled by the Flag button) ──
	_flag_panel = PanelContainer.new()
	_flag_panel.visible = false
	var flag_style = StyleBoxFlat.new()
	flag_style.bg_color = Color(0.12, 0.10, 0.05, 0.95)
	flag_style.corner_radius_top_left = 4
	flag_style.corner_radius_top_right = 4
	flag_style.corner_radius_bottom_left = 4
	flag_style.corner_radius_bottom_right = 4
	flag_style.content_margin_left = 10
	flag_style.content_margin_right = 10
	flag_style.content_margin_top = 8
	flag_style.content_margin_bottom = 8
	_flag_panel.add_theme_stylebox_override("panel", flag_style)
	r_vbox.add_child(_flag_panel)

	var flag_vbox = VBoxContainer.new()
	flag_vbox.add_theme_constant_override("separation", 6)
	_flag_panel.add_child(flag_vbox)

	var flag_hint = Label.new()
	flag_hint.text = "What felt off about this trick?"
	_scaled_font(flag_hint, 13)
	flag_hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	flag_vbox.add_child(flag_hint)

	var flag_toggle_row = HBoxContainer.new()
	flag_toggle_row.add_theme_constant_override("separation", 6)
	flag_vbox.add_child(flag_toggle_row)

	_flag_toggle_bidding = _make_flag_toggle("Bidding")
	flag_toggle_row.add_child(_flag_toggle_bidding)
	_flag_toggle_gameplay = _make_flag_toggle("Gameplay")
	flag_toggle_row.add_child(_flag_toggle_gameplay)
	_flag_toggle_explanation = _make_flag_toggle("Explanation")
	flag_toggle_row.add_child(_flag_toggle_explanation)

	_flag_note_edit = LineEdit.new()
	_flag_note_edit.placeholder_text = "Optional note..."
	_flag_note_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flag_vbox.add_child(_flag_note_edit)

	var flag_submit_btn = Button.new()
	flag_submit_btn.text = "Submit Flag"
	flag_submit_btn.custom_minimum_size = Vector2(0, 40)
	flag_submit_btn.pressed.connect(_submit_flag)
	flag_vbox.add_child(flag_submit_btn)

	# Table area — wrapped in a ScrollContainer so it degrades gracefully on small screens
	var r_scroll = ScrollContainer.new()
	r_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	r_vbox.add_child(r_scroll)

	var r_table = VBoxContainer.new()
	r_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_table.add_theme_constant_override("separation", 4)
	r_scroll.add_child(r_table)

	# Pre-fill arrays so indices 0-3 exist before we assign them
	for _i in range(4):
		_replay_hand_containers.append(null)
		_replay_played_containers.append(null)
		_replay_bubble_labels.append(null)

	# ── Partner (player 2) — top ──
	var p2_sec = _build_replay_player_section("Partner")
	r_table.add_child(p2_sec[0])
	_replay_hand_containers[2]   = p2_sec[1]
	_replay_played_containers[2] = p2_sec[2]
	_replay_bubble_labels[2]     = p2_sec[3]

	# ── Middle row: Left Opponent (player 3) | center spacer | Right Opponent (player 1) ──
	var r_mid = HBoxContainer.new()
	r_mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_mid.add_theme_constant_override("separation", 4)
	r_table.add_child(r_mid)

	var p3_sec = _build_replay_player_section("Left Opponent")
	r_mid.add_child(p3_sec[0])
	_replay_hand_containers[3]   = p3_sec[1]
	_replay_played_containers[3] = p3_sec[2]
	_replay_bubble_labels[3]     = p3_sec[3]

	var r_spacer = Control.new()
	r_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_mid.add_child(r_spacer)

	var p1_sec = _build_replay_player_section("Right Opponent")
	r_mid.add_child(p1_sec[0])
	_replay_hand_containers[1]   = p1_sec[1]
	_replay_played_containers[1] = p1_sec[2]
	_replay_bubble_labels[1]     = p1_sec[3]

	# ── Human (player 0) — bottom ──
	var p0_sec = _build_replay_player_section("You", true)
	r_table.add_child(p0_sec[0])
	_replay_hand_containers[0]   = p0_sec[1]
	_replay_played_containers[0] = p0_sec[2]
	_replay_bubble_labels[0]     = p0_sec[3]

	r_vbox.add_child(HSeparator.new())

	# Bottom bar: navigation button
	var r_bot_bar = HBoxContainer.new()
	r_bot_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	r_bot_bar.add_theme_constant_override("separation", 16)
	r_vbox.add_child(r_bot_bar)

	_replay_back_btn = Button.new()
	_replay_back_btn.text = "← Back"
	_replay_back_btn.custom_minimum_size = Vector2(140, 44)
	_replay_back_btn.pressed.connect(_replay_prev_trick)
	r_bot_bar.add_child(_replay_back_btn)

	var r_next_btn = Button.new()
	r_next_btn.text = "Continue →"
	r_next_btn.custom_minimum_size = Vector2(140, 44)
	r_next_btn.pressed.connect(_replay_next_trick)
	r_bot_bar.add_child(r_next_btn)

func _scaled_font(node: Control, base_size: int) -> void:
	node.add_theme_font_size_override("font_size", round(base_size * font_scale))
	var entry = {"node": node, "base_size": base_size}
	_font_registry.append(entry)
	node.tree_exiting.connect(func(): _font_registry.erase(entry))

func _on_viewport_resized():
	var vp_w: float = get_viewport().get_visible_rect().size.x
	var tile_w: float = min(64.0, floor(vp_w / 9.0))
	TILE_FULL          = Vector2(tile_w,        tile_w * 2.0)
	TILE_SMALL         = Vector2(tile_w * 0.85, tile_w * 2.0 * 0.85)
	TILE_PLAYED        = Vector2(tile_w * PLAY_TILE_SCALE, tile_w * 2.0 * PLAY_TILE_SCALE)
	TILE_REPLAY_HAND   = Vector2(tile_w * 0.65, tile_w * 2.0 * 0.65)
	TILE_REPLAY_PLAYED = Vector2(tile_w * 0.85, tile_w * 2.0 * 0.85)

	font_scale = clamp(vp_w / DESIGN_WIDTH, MIN_SCALE, MAX_SCALE)
	for entry in _font_registry:
		entry["node"].add_theme_font_size_override("font_size", round(entry["base_size"] * font_scale))

	# Must come after the font-size refresh above: the diamond's vertical room
	# depends on the seat label's height, which rides on font_scale.
	_refresh_bid_reminder_width()

	if is_instance_valid(play_area_container):
		_refresh_play_area_reservation()
		_replace_play_area_children()

	if is_instance_valid(_pts_picker):
		_pts_picker.font_scale = font_scale
		_pts_picker.queue_redraw()
	if is_instance_valid(_marks_picker):
		_marks_picker.font_scale = font_scale
		_marks_picker.queue_redraw()
	if is_instance_valid(_us_marks):
		_us_marks.font_scale = font_scale
		_us_marks.queue_redraw()
	if is_instance_valid(_them_marks):
		_them_marks.font_scale = font_scale
		_them_marks.queue_redraw()

func _make_flag_toggle(label_text: String) -> Button:
	var btn = Button.new()
	btn.text = label_text
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(0, 32)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return btn

func _build_replay_player_section(label_text: String, invert: bool = false) -> Array:
	var name_lbl = Label.new()
	name_lbl.text = label_text
	_scaled_font(name_lbl, 12)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var hand_hbox = HBoxContainer.new()
	hand_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_hbox.add_theme_constant_override("separation", 2)

	var played_hbox = HBoxContainer.new()
	played_hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var bubble_lbl = Label.new()
	bubble_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scaled_font(bubble_lbl, 11)
	bubble_lbl.add_theme_color_override("font_color", Color.WHITE)
	bubble_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	bubble_lbl.custom_minimum_size = Vector2(160, 0)
	var bubble_style = StyleBoxFlat.new()
	bubble_style.bg_color = Color(0.08, 0.08, 0.10, 0.90)
	bubble_style.corner_radius_top_left = 6
	bubble_style.corner_radius_top_right = 6
	bubble_style.corner_radius_bottom_left = 6
	bubble_style.corner_radius_bottom_right = 6
	bubble_style.content_margin_left = 6
	bubble_style.content_margin_right = 6
	bubble_style.content_margin_top = 4
	bubble_style.content_margin_bottom = 4
	bubble_lbl.add_theme_stylebox_override("normal", bubble_style)
	bubble_lbl.visible = false

	var section = VBoxContainer.new()
	section.alignment = BoxContainer.ALIGNMENT_CENTER
	section.add_theme_constant_override("separation", 4)

	if invert:
		section.add_child(played_hbox)
		section.add_child(bubble_lbl)
		section.add_child(name_lbl)
		section.add_child(hand_hbox)
	else:
		section.add_child(name_lbl)
		section.add_child(hand_hbox)
		section.add_child(played_hbox)
		section.add_child(bubble_lbl)

	return [section, hand_hbox, played_hbox, bubble_lbl]

# ─── GAME FLOW ────────────────────────────────────────────────────────────────

func _start_game():
	_show_game_board(false)
	main_menu_panel.visible = true

# Table-wide domino back. Now a stored display preference rather than something
# inferred from the active ruleset — before July 29 2026 this read
# preset_id == "teel", which meant picking a different ruleset silently changed
# the tile art and no other combination was reachable at all. Reads
# display_prefs.json, so it takes no argument and stays correct no matter which
# slot is loaded.
func _update_domino_back_texture():
	var res_path := _load_domino_back_pref()
	if res_path.is_empty() or not ResourceLoader.exists(res_path):
		DominoTile.custom_back_texture = null
	else:
		DominoTile.custom_back_texture = load(res_path)

# Resolves a slot key to a fresh GameSettings without starting a game: saved
# override if one exists, else the hardcoded default (Standard 42 for a Custom
# slot that has never been saved). Extracted from _on_preset_chosen() so the
# Settings screen's slot buttons and Choose Rules' instant-apply share one
# source of truth for what a slot means.
#
# Always returns a NEW object and always re-stamps preset_id. Both matter:
# building fresh is what keeps switching slots from carrying the previous slot's
# tweaks along, and re-stamping is required because to_dict() does not serialize
# preset_id — a settings object loaded from disk comes back with preset_id == ""
# and would silently no-op _persist_preset_tweaks() and hide Reset to Default.
# Where a slot's rule content lives. The ONLY place that knows a "custom:" key
# maps to custom_rulesets/ and everything else to preset_overrides/ — previously
# this same begins_with() test was spelled out separately in the resolver and in
# _persist_preset_tweaks(), which is exactly the pair you'd want to stay in step.
func _slot_file_path(key: String) -> String:
	if key.begins_with("custom:"):
		return "%s/%s.json" % [CUSTOM_RULESETS_DIR, key.substr(7)]
	return "%s/%s.json" % [PRESET_OVERRIDES_DIR, key]

# Creates the directory a slot's file will live in. Split out of the path lookup
# so reads don't have the side effect of making directories.
func _ensure_slot_dir(key: String) -> void:
	var d = DirAccess.open("user://")
	if d == null:
		return
	d.make_dir(_slot_file_path(key).get_base_dir().replace("user://", ""))

# A slot's shipped rules, ignoring anything saved on disk. Single source of truth
# for the key -> preset-function mapping, shared by the resolver and by Reset to
# Default; those two used to carry separate `match key:` statements that had to
# be kept identical by hand.
func _hardcoded_defaults_for_slot(key: String) -> GameSettings:
	match key:
		"teel":       return GameSettingsScript.teel_rules()
		"standard":   return GameSettingsScript.standard_42()
		"tournament": return GameSettingsScript.tournament_rules()
		"lechner":    return GameSettingsScript.lechner_hall()
		# Custom ships no rules of its own — Standard 42 is its first-run seed,
		# after which its saved file is its default.
		_:            return GameSettingsScript.standard_42()

func _resolve_settings_for_slot(key: String) -> GameSettings:
	var defaults := _hardcoded_defaults_for_slot(key)
	var s: GameSettings = null
	var f = FileAccess.open(_slot_file_path(key), FileAccess.READ)
	if f:
		var data = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Dictionary:
			s = GameSettingsScript.from_dict(data)
	if s == null:
		s = defaults
	s.preset_id = key

	# ── Difficulty is player state, not rule content ──────────────────────────
	# It has its own main-menu screen, commits the instant it's clicked, and
	# lives in last_used.json. Ruleset files therefore don't serialize it (see
	# GameSettings.to_dict()), and this is where it gets supplied instead:
	#
	#   1. the slot's shipped default is the seed, for a player who has never
	#      chosen — this is what makes Tournament/Lechner start at Expert and
	#      Teel/Standard at Casual even when a saved override exists;
	#   2. an explicit choice overrides it, so setting Expert and then tapping a
	#      Casual-defaulting slot doesn't silently downgrade the opponents.
	s.ai_difficulty = defaults.ai_difficulty
	var chosen_difficulty := _last_used_difficulty()
	if not chosen_difficulty.is_empty():
		s.ai_difficulty = chosen_difficulty
	return s

func _on_preset_chosen(key: String):
	# Tapping a slot row while its "…" menu is open should not leave the menu
	# parked on a hidden panel, waiting to reappear next time Choose Rules opens.
	_close_slot_options_menu()
	preset_panel.visible = false
	_save_last_used(key)
	var s := _resolve_settings_for_slot(key)
	_update_domino_back_texture()
	game = Game.new(s)
	game.setup_players(human_seat)
	_start_hand()

func _start_hand():
	_hand_over = false
	_armed_domino = null
	_small_end_active = false
	if _small_end_toggle_btn:
		_small_end_toggle_btn.visible = false
		_small_end_toggle_btn.button_pressed = false
	if laydown_btn:
		laydown_btn.visible = false
	main_menu_panel.visible = false
	preset_panel.visible = false
	if _replay_btn and is_instance_valid(_replay_btn):
		_replay_btn.queue_free()
		_replay_btn = null
	if _continue_btn and is_instance_valid(_continue_btn):
		_continue_btn.queue_free()
		_continue_btn = null
	if _new_game_btn and is_instance_valid(_new_game_btn):
		_new_game_btn.queue_free()
		_new_game_btn = null
	if replay_panel:
		replay_panel.visible = false
	_show_game_board(true)
	game.deal_hands()
	_refresh_all_hands()
	_us_tricks.clear_tricks()
	_them_tricks.clear_tricks()
	# Carry each list's expanded/collapsed state into the new hand instead of
	# folding both back. This used to force them shut on the grounds that an
	# expanded empty list is a panel of nothing — true, but it's the player's
	# call: anyone who wants the trick lists open wants them open every hand, and
	# having to re-open them after every deal is the worse annoyance.
	#
	# Re-applying the current state rather than simply leaving it alone is what
	# keeps the geometry honest: _set_tricks_expanded() snaps an open panel back
	# to its content's minimum, so a list left open at the end of a seven-trick
	# hand doesn't reopen at that height over a pile that's just been cleared.
	_set_tricks_expanded(0, _tricks_expanded[0])
	_set_tricks_expanded(1, _tricks_expanded[1])
	_start_bidding()

func _start_bidding():
	_update_points_readout()
	trump_indicator_label.text = ""
	bid_reminder_label.text = ""
	if is_instance_valid(_hand_result_banner):
		_hand_result_banner.queue_free()
		_hand_result_banner = null
		_refresh_play_area_reservation()   # banner gone — diamond needs its room back
	game.current_bid = null
	human_is_forced = false
	_human_bid_position = -1
	_bid_panel_expanded = false
	_selected_contract_type = BidScript.Type.MARKS
	_clear_bid_bubbles()
	_run_bidding_sequence()

func _run_bidding_sequence():
	# Bidding order comes from Game.bid_order(), which respects
	# settings.bid_direction ("clockwise" or "counterclockwise").
	# The shaker always bids last regardless of direction.
	var bid_order: Array = game.bid_order()

	for i in range(4):
		var pid = bid_order[i]
		if pid == human_seat:
			_human_bid_position = i
			if i == 3 and game.current_bid == null and game.settings.allow_forced_bid:
				human_is_forced = true
				_set_status("Everyone passed — you must bid at least %d!" % game.settings.forced_bid_minimum)
			else:
				_set_status("Your turn to bid")
			waiting_for_bid = true
			_show_bid_panel()
			return
		status_label.text = "%s is thinking..." % _seat_label(pid)
		await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 1.0).timeout
		var player = game.players[pid]
		var is_forced = (i == 3 and game.current_bid == null and game.settings.allow_forced_bid)
		var ai_bid = AIPlayer.decide_bid(player.hand, pid, game.current_bid, game.settings, is_forced, game.settings.ai_difficulty, game.bid_decisions, game.shaker, human_seat)
		ai_bid = _accept_ai_bid(ai_bid, pid, i)
		_show_bid_bubble(pid, "%s\n%s" % [_seat_label(pid), ai_bid.debug_string()])
		_set_status("%s: %s" % [_seat_label(pid), ai_bid.debug_string()])
		await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 0.7).timeout

# Accept an AI bid only if it is legal, and return what actually happened.
# Both AI bid loops go through this instead of assigning game.current_bid
# directly. That direct assignment at four separate sites is the whole reason
# allow_jump_bids quietly did nothing for weeks: Bid.is_valid() was written
# correctly and simply never ran during a real auction. The human path was put
# behind the validator when that was found; this is the other half.
#
# A rejected bid becomes a pass. An illegal bid must never become the standing
# bid, and passing is the one response that is always legal. It is also a bug
# if this ever fires — decide_bid() is meant to produce legal bids, not to be
# filtered into producing them — so it reports loudly rather than silently
# correcting. The returned bid is what gets shown in the bubble and status
# line, so the table never announces a bid that wasn't accepted.
func _accept_ai_bid(ai_bid: RefCounted, pid: int, bid_position: int) -> RefCounted:
	if ai_bid.type == BidScript.Type.PASS:
		return ai_bid
	if BidScript.is_valid(ai_bid, game.current_bid, game.settings,
			game.bid_context(pid, bid_position)):
		game.current_bid = ai_bid
		return ai_bid
	push_error("AI seat %d produced an illegal bid: %s (high: %s) — treated as a pass"
		% [pid, ai_bid.debug_string(),
		   "none" if game.current_bid == null else game.current_bid.debug_string()])
	return BidScript.new(BidScript.Type.PASS, 0, pid)

# Highest marks value the human may legally pick right now — the drum's ceiling,
# deliberately mirroring Bid.is_valid()'s. The drum used to run to 7 unconditionally,
# which meant "Allow Jump Bids" and max_open_bid_marks changed nothing a player
# could see: every value was on the wheel, and nothing rejected the bid afterwards.
#
# Plunge and Splash are exempt and return the full range: they carry their own
# fixed minimums, which can legitimately sit ABOVE the cap — a 4-mark Plunge over
# a 1-mark auction would otherwise be filtered out of its own drum.
func _marks_ceiling(contract_type: int, current_high) -> int:
	if contract_type != BidScript.Type.MARKS or game.settings.allow_jump_bids:
		return 7
	var standing := 0.0 if current_high == null else BidScript.to_mark_equivalent(current_high)
	if standing < 1.0:
		# Nothing standing, or only a points bid — still the auction's first marks
		# bid, so the opening cap applies.
		return mini(7, game.settings.max_open_bid_marks)
	return mini(7, int(standing) + 1)

func _contract_floor(contract_type: int, auction_floor: int) -> int:
	match contract_type:
		BidScript.Type.PLUNGE:
			return max(game.settings.plunge_minimum_bid_marks, auction_floor)
		BidScript.Type.SPLASH:
			return max(game.settings.splash_bid_marks, auction_floor)
		_:
			return auction_floor

func _show_bid_panel():
	for child in bid_buttons.get_children():
		child.queue_free()
	_pts_picker = null
	_marks_picker = null
	_contract_marks_picker = null

	var current_high = game.current_bid
	var min_points = 30
	var points_available = true
	var auction_floor = 1

	if current_high != null and current_high.type == BidScript.Type.POINTS:
		min_points = current_high.value + 1
		if min_points > 42:
			points_available = false
	elif current_high != null and current_high.type == BidScript.Type.MARKS:
		points_available = false
		auction_floor = current_high.value + 1

	const CONTRACT_ORDER = [BidScript.Type.NELLO, BidScript.Type.SEVENS, BidScript.Type.PLUNGE, BidScript.Type.SPLASH]
	var bid_ctx = game.bid_context(human_seat, _human_bid_position)
	var eligible: Array = game.eligible_contracts(game.players[human_seat].hand, bid_ctx)
	var contracts: Array = []
	for t in CONTRACT_ORDER:
		if eligible.has(t):
			contracts.append(t)

	if _bid_panel_expanded and _selected_contract_type != BidScript.Type.MARKS and not contracts.has(_selected_contract_type):
		_selected_contract_type = BidScript.Type.MARKS

	# Outer vbox centers everything
	var center_vbox = VBoxContainer.new()
	center_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_vbox.add_theme_constant_override("separation", 6)
	bid_buttons.add_child(center_vbox)

	# Single row, slot order:
	#   collapsed: [Pass]      [Points] [Marks] [More]
	#   expanded:  [Back][Pass]         [Marks] [contract buttons]
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	center_vbox.add_child(row)

	# --- Back (expanded only, sits before Pass) ---
	if _bid_panel_expanded:
		var back_btn = Button.new()
		back_btn.text = "‹ Back"
		back_btn.custom_minimum_size = Vector2(64, 76)
		back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		back_btn.pressed.connect(func():
			_bid_panel_expanded = false
			_selected_contract_type = BidScript.Type.MARKS
			_show_bid_panel()
		)
		row.add_child(back_btn)

	# --- Pass (same slot in both states) ---
	var pass_btn = Button.new()
	pass_btn.text = "Pass"
	pass_btn.custom_minimum_size = Vector2(64, 76)
	pass_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pass_btn)
	pass_btn.pressed.connect(_on_bid_submitted.bind(BidScript.new(BidScript.Type.PASS, 0, human_seat)))

	# --- Points drum (collapsed only) ---
	if not _bid_panel_expanded and points_available:
		var sep = VSeparator.new()
		sep.custom_minimum_size = Vector2(2, 76)
		row.add_child(sep)

		var pts_col = VBoxContainer.new()
		pts_col.alignment = BoxContainer.ALIGNMENT_CENTER
		pts_col.add_theme_constant_override("separation", 4)
		row.add_child(pts_col)

		var pts_lbl = Label.new()
		pts_lbl.text = "Points"
		pts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pts_lbl.add_theme_color_override("font_color", Color.WHITE)
		_scaled_font(pts_lbl, 13)
		pts_col.add_child(pts_lbl)

		_pts_picker = DrumPicker.new()
		_pts_picker.font_scale = font_scale
		var pt_vals: Array[int] = []
		for v in range(min_points, 43):
			pt_vals.append(v)
		var default_pts_idx = pt_vals.find(31) if pt_vals.has(31) else 0
		_pts_picker.setup(pt_vals, default_pts_idx)
		pts_col.add_child(_pts_picker)

		var pts_bid_btn = Button.new()
		pts_bid_btn.text = "Bid"
		pts_bid_btn.custom_minimum_size = Vector2(DrumPicker.ITEM_WIDTH * DrumPicker.VISIBLE_ITEMS, 28)
		pts_bid_btn.pressed.connect(func():
			_on_bid_submitted(BidScript.new(BidScript.Type.POINTS, _pts_picker.get_value(), human_seat))
		)
		pts_col.add_child(pts_bid_btn)

	# --- Marks drum — same drum/slot in both states; re-floored when expanded ---
	var marks_type = _selected_contract_type if _bid_panel_expanded else BidScript.Type.MARKS
	var marks_floor = _contract_floor(marks_type, auction_floor)
	var marks_ceiling = _marks_ceiling(marks_type, current_high)
	if marks_floor <= marks_ceiling:
		var sep2 = VSeparator.new()
		sep2.custom_minimum_size = Vector2(2, 76)
		row.add_child(sep2)

		var marks_col = VBoxContainer.new()
		marks_col.alignment = BoxContainer.ALIGNMENT_CENTER
		marks_col.add_theme_constant_override("separation", 4)
		row.add_child(marks_col)

		var marks_lbl = Label.new()
		marks_lbl.text = _contract_label(_selected_contract_type) if (_bid_panel_expanded and _selected_contract_type != BidScript.Type.MARKS) else "Marks"
		marks_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marks_lbl.add_theme_color_override("font_color", Color.WHITE)
		_scaled_font(marks_lbl, 13)
		marks_col.add_child(marks_lbl)

		_marks_picker = DrumPicker.new()
		_marks_picker.font_scale = font_scale
		_contract_marks_picker = _marks_picker
		var mark_vals: Array[int] = []
		for v in range(marks_floor, marks_ceiling + 1):
			mark_vals.append(v)
		_marks_picker.setup(mark_vals, 0)
		marks_col.add_child(_marks_picker)

		var marks_bid_btn = Button.new()
		marks_bid_btn.text = "Bid"
		marks_bid_btn.custom_minimum_size = Vector2(DrumPicker.ITEM_WIDTH * DrumPicker.VISIBLE_ITEMS, 28)
		marks_bid_btn.pressed.connect(func():
			var bid_type = _selected_contract_type if _bid_panel_expanded else BidScript.Type.MARKS
			_on_bid_submitted(BidScript.new(bid_type, _marks_picker.get_value(), human_seat))
		)
		marks_col.add_child(marks_bid_btn)

	# --- More (collapsed) / contract buttons (expanded) ---
	if not _bid_panel_expanded:
		if not eligible.is_empty():
			var sep3 = VSeparator.new()
			sep3.custom_minimum_size = Vector2(2, 76)
			row.add_child(sep3)

			var more_btn = Button.new()
			more_btn.text = "More ▾"
			more_btn.custom_minimum_size = Vector2(64, 76)
			more_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			more_btn.pressed.connect(func():
				_bid_panel_expanded = true
				_show_bid_panel()
			)
			row.add_child(more_btn)
	else:
		var sep4 = VSeparator.new()
		sep4.custom_minimum_size = Vector2(2, 76)
		row.add_child(sep4)

		var contract_row = HBoxContainer.new()
		contract_row.alignment = BoxContainer.ALIGNMENT_CENTER
		contract_row.add_theme_constant_override("separation", 8)
		row.add_child(contract_row)

		var contract_buttons: Dictionary = {}  # type -> Button
		for t in contracts:
			var btn = Button.new()
			btn.text = _contract_label(t)
			contract_row.add_child(btn)
			contract_buttons[t] = btn
			btn.pressed.connect(func():
				_selected_contract_type = BidScript.Type.MARKS if _selected_contract_type == t else t
				_show_bid_panel()
			)

		_update_contract_button_visuals(contract_buttons)

	bid_panel.visible = true

func _contract_label(contract_type: int) -> String:
	match contract_type:
		BidScript.Type.NELLO:
			return "Nello"
		BidScript.Type.SEVENS:
			return "Sevens"
		BidScript.Type.PLUNGE:
			return "Plunge (%d)" % game.settings.plunge_minimum_bid_marks
		BidScript.Type.SPLASH:
			return "Splash (%d)" % game.settings.splash_bid_marks
		_:
			return ""

func _update_contract_button_visuals(contract_buttons: Dictionary):
	for t in contract_buttons:
		var btn: Button = contract_buttons[t]
		if t == _selected_contract_type:
			btn.modulate = Color(0.95, 0.80, 0.15)
		else:
			btn.modulate = Color(1, 1, 1)

func _on_bid_submitted(bid: RefCounted):
	if human_is_forced and bid.type == BidScript.Type.PASS:
		_set_status("You must bid — everyone passed and you're the shaker!")
		return
	# Validate before accepting. The drum above only offers legal values, so this
	# should never fire — but the UI being the ONLY gate is exactly how
	# allow_jump_bids came to do nothing: Bid.is_valid() was written correctly and
	# then never reached, because every bid site assigned game.current_bid
	# directly. Keep the rule on the path, not just in the widget.
	if not BidScript.is_valid(bid, game.current_bid, game.settings,
			game.bid_context(human_seat, _human_bid_position)):
		_set_status("That bid isn't legal here.")
		push_error("Rejected an illegal human bid that the panel offered: %s (high: %s)"
			% [bid.debug_string(),
			   "none" if game.current_bid == null else game.current_bid.debug_string()])
		return
	bid_panel.visible = false
	waiting_for_bid = false
	if bid.type != BidScript.Type.PASS:
		game.current_bid = bid
	game.bid_decisions.append({
		"player_id": human_seat,
		"source":    "human",
		"bid_type":  bid.type,
		"bid_value": bid.value,
	})
	_show_bid_bubble(human_seat, "You\n%s" % bid.debug_string())
	_set_status("You: %s" % bid.debug_string())
	await _run_post_human_bids()
	_finish_bidding([])

func _run_post_human_bids():
	var bid_order: Array = game.bid_order()
	var human_pos = bid_order.find(human_seat)
	for i in range(human_pos + 1, 4):
		var pid = bid_order[i]
		status_label.text = "%s is thinking..." % _seat_label(pid)
		await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 1.0).timeout
		var player = game.players[pid]
		var is_forced = (i == 3 and game.current_bid == null and game.settings.allow_forced_bid)
		var ai_bid = AIPlayer.decide_bid(player.hand, pid, game.current_bid, game.settings, is_forced, game.settings.ai_difficulty, game.bid_decisions, game.shaker, human_seat)
		ai_bid = _accept_ai_bid(ai_bid, pid, i)
		_show_bid_bubble(pid, "%s\n%s" % [_seat_label(pid), ai_bid.debug_string()])
		_set_status("%s: %s" % [_seat_label(pid), ai_bid.debug_string()])
		await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 0.7).timeout

func _finish_bidding(_unused: Array):
	_clear_bid_bubbles()
	var winning = game.current_bid
	if winning == null:
		_set_status("No bid — reshuffling...")
		await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 1.5).timeout
		_start_hand()
		return

	_set_status("Bid: Player %d — %s" % [winning.player_id, winning.debug_string()])

	if winning.type == BidScript.Type.NELLO:
		if winning.player_id == human_seat:
			# Human picks doubles mode, then leads
			_show_nello_panel()
		else:
			# AI Nello: use table default, bid winner leads
			game.active_nello_doubles_mode = game.settings.nello_doubles_mode
			game.apply_bid_result(-1)
			_update_points_readout()
			trump_indicator_label.text = ""
			_update_bid_reminder()
			_refresh_all_hands()
			await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 0.8).timeout
			_begin_play(winning.player_id)

	elif winning.type == BidScript.Type.SEVENS:
		# Sevens needs no trump selection from anyone
		game.apply_bid_result(-1)
		_update_points_readout()
		trump_indicator_label.text = ""
		_update_bid_reminder()
		_refresh_all_hands()
		await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 0.8).timeout
		_begin_play(winning.player_id)

	elif winning.type == BidScript.Type.PLUNGE or winning.type == BidScript.Type.SPLASH:
		# Plunge / Splash — partner of bid winner calls trump and leads
		var partner_id = (winning.player_id + 2) % 4
		var bid_label = "Plunge" if winning.type == BidScript.Type.PLUNGE else "Splash"
		if partner_id == human_seat:
			_show_trump_panel("%s bid %s — you call trump!" % [_seat_label(winning.player_id), bid_label])
		else:
			_set_status("%s is calling trump..." % _seat_label(partner_id))
			await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 1.0).timeout
			var suit_names = ["Blanks", "Ones", "Twos", "Threes", "Fours", "Fives", "Sixes"]
			var ai_eval = AIPlayer.best_trump(game.players[partner_id].hand)
			var best_suit = ai_eval["trump"]
			game.apply_bid_result(best_suit)
			_update_points_readout()
			trump_indicator_label.text = "Trump: %s" % _trump_display_name(best_suit)
			_update_bid_reminder()
			_show_trump_announcement(best_suit)
			_refresh_all_hands()
			_set_status("%s called %s" % [_seat_label(partner_id), suit_names[best_suit]])
			await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 0.8).timeout
			_begin_play(partner_id)

	else:
		# Covers POINTS and MARKS (bid winner picks trump and leads).
		# FOLLOW_ME also falls here for now — intentional pending its own panel.
		if not (winning.type == BidScript.Type.POINTS or winning.type == BidScript.Type.MARKS
				or winning.type == BidScript.Type.FOLLOW_ME):
			push_warning("_finish_bidding: unhandled bid type %d fell through to trump panel" % winning.type)
		if winning.player_id == human_seat:
			_show_trump_panel()
		else:
			var ai_eval = AIPlayer.best_trump(game.players[winning.player_id].hand)
			var best_suit = ai_eval["trump"]
			game.apply_bid_result(best_suit)
			_update_points_readout()
			trump_indicator_label.text = "Trump: %s" % _trump_display_name(best_suit)
			_update_bid_reminder()
			_show_trump_announcement(best_suit)
			_refresh_all_hands()
			await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 0.8).timeout
			_begin_play()

func _show_trump_panel(message: String = "You won the bid — call your trump suit"):
	waiting_for_trump = true
	var allow_follow = game.settings.allow_follow_me
	var allow_doubles = game.settings.doubles_are_trump
	_follow_me_btn.visible = allow_follow
	_doubles_trump_btn.visible = allow_doubles
	_doubles_trump_reversed_btn.visible = allow_doubles and game.settings.doubles_trump_reversed
	_special_trump_sep.visible = allow_follow or allow_doubles
	trump_panel.visible = true
	_set_status(message)

func _on_trump_selected(suit: int):
	trump_panel.visible = false
	waiting_for_trump = false
	game.apply_bid_result(suit)
	_update_points_readout()
	trump_indicator_label.text = "Trump: %s" % _trump_display_name(suit)
	_update_bid_reminder()
	_show_trump_announcement(suit)
	_refresh_all_hands()
	# Derive the correct leader from game state set by apply_bid_result():
	# for Plunge/Splash the partner leads, otherwise the bid winner leads.
	var is_ps = (game.variant == BidScript.Type.PLUNGE or game.variant == BidScript.Type.SPLASH)
	var leader = (game.current_bid.player_id + 2) % 4 if is_ps else game.current_bid.player_id
	_begin_play(leader)

func _show_nello_panel():
	waiting_for_nello_mode = true
	_nello_reversed_btn.visible = game.settings.nello_doubles_reversed
	nello_panel.visible = true
	_set_status("You won Nello — how do doubles play?")

func _on_nello_mode_selected(mode: String):
	nello_panel.visible = false
	waiting_for_nello_mode = false
	if mode == "own_suit_reversed":
		game.active_nello_doubles_mode = "own_suit"
		game.active_nello_doubles_reversed = true
	else:
		game.active_nello_doubles_mode = mode
		game.active_nello_doubles_reversed = false
	game.apply_bid_result(-1)
	_update_points_readout()
	trump_indicator_label.text = ""
	_update_bid_reminder()
	_refresh_all_hands()
	if game.settings.allow_nello_exchange:
		_start_nello_exchange()
	else:
		_begin_play()

func _start_nello_exchange():
	var partner_id = game.nello_solo_player  # set by apply_bid_result() just above
	_pending_partner_give = AIPlayer.select_nello_exchange_give(
		game.players[partner_id].hand,
		game.active_nello_doubles_mode,
		game.active_nello_doubles_reversed
	)
	_show_nello_exchange_panel()

func _show_nello_exchange_panel():
	_populate_nello_exchange_hand()
	nello_exchange_panel.visible = true
	_set_status("Exchange a domino with your partner, or decline.")

func _populate_nello_exchange_hand():
	for child in nello_exchange_hand_container.get_children():
		child.queue_free()
	for d in game.players[human_seat].hand:
		var tile = DominoTile.new()
		tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nello_exchange_hand_container.add_child(tile)
		tile.setup(d, true)
		tile.custom_minimum_size = TILE_FULL
		tile.domino_pressed.connect(func(t: DominoTile): _on_nello_exchange_domino_selected(t.domino))

	# "Don't Trade" — a domino-tile-shaped control in a distinct visual
	# state, appended to the end of the hand row. Implemented as a plain
	# Button (not a DominoTile draw-state extension) to keep the shared
	# DominoTile component untouched; reskin freely once this can be seen
	# in the editor.
	var decline_btn = Button.new()
	decline_btn.text = "Don't\nTrade"
	decline_btn.custom_minimum_size = TILE_FULL
	decline_btn.pressed.connect(_on_nello_exchange_declined)
	nello_exchange_hand_container.add_child(decline_btn)

func _on_nello_exchange_domino_selected(chosen: Domino):
	nello_exchange_panel.visible = false
	game.apply_nello_exchange(chosen, _pending_partner_give)
	_pending_partner_give = null
	_refresh_all_hands()
	_begin_play()

func _on_nello_exchange_declined():
	nello_exchange_panel.visible = false
	_pending_partner_give = null
	_begin_play()

func _on_small_end_toggle_pressed(pressed: bool):
	_small_end_active = pressed
	_update_small_end_button_style()

func _update_small_end_button_style():
	_small_end_toggle_btn.modulate = Color(0.95, 0.80, 0.15) if _small_end_active else Color(1, 1, 1)

func _update_small_end_button_visibility():
	var is_opening_lead = game.tricks_played == 0 and game.current_trick.plays.size() == 0
	# Trump contracts only. `game.trump >= 0` is the right test rather than a list
	# of variants: Nello and Sevens both apply_bid_result(-1), and so does a Follow
	# Me, which the live bidding flow issues as a POINTS bid with no trump rather
	# than as Bid.Type.FOLLOW_ME — a variant check would miss it. DOUBLES_TRUMP (7)
	# still counts as a trump suit and stays eligible.
	var eligible = game.settings.allow_small_end_opening_lead \
		and game.trump >= 0 \
		and is_opening_lead
	_small_end_toggle_btn.visible = eligible
	if not eligible:
		_small_end_active = false
		_small_end_toggle_btn.button_pressed = false
		_update_small_end_button_style()

# Contracts whose lay-down claim laydown_check.gd can actually verify. Its proof
# is "every tile I hold WINS the trick it's played into", which is only the right
# question for a take-tricks contract — see that file's header, which scopes Nello
# and Sevens out explicitly.
#
# Nello inverts the goal (the claim would be "every tile I hold LOSES"), so the
# existing proof reports the exact opposite of the truth: it says yes precisely
# when the player holds the top tiles and is therefore guaranteed to fail. Sevens
# ranks tiles by distance from 7 pips rather than by suit rank, so the comparison
# doesn't apply either. Neither is a near-miss that a visibility tweak fixes.
const LAYDOWN_SUPPORTED_VARIANTS := [
	BidScript.Type.POINTS,
	BidScript.Type.MARKS,
	BidScript.Type.PLUNGE,
	BidScript.Type.SPLASH,
	BidScript.Type.FOLLOW_ME,
]

# Nello is supported too, but by a different proof with the opposite
# precondition, so it routes through its own branch rather than joining the list
# above. Sevens remains genuinely unsupported: it ranks by distance from a pip
# sum of 7, so neither proof's suit-rank comparison applies to it at all.

# Lead-only, per Laydown_Session_Handoff_July21_2026.md — the proof is only
# valid when it's the claimant's turn to lead (see laydown_check.gd's own
# header comment). Assisted mode additionally requires the claim to already
# be provably correct before the button appears at all — no risk, nothing
# to get wrong. Authentic mode shows it any time it's the human's lead,
# self-judged; _on_laydown_button_pressed() re-verifies on press regardless.
func _update_laydown_button_visibility():
	if not game.settings.allow_laydown:
		laydown_btn.visible = false
		return
	if game.variant == BidScript.Type.NELLO:
		_update_laydown_button_visibility_nello()
		return
	var eligible = LAYDOWN_SUPPORTED_VARIANTS.has(game.variant) \
		and game.current_trick.plays.size() == 0
	if eligible and game.settings.laydown_mode == "assisted":
		eligible = _laydown_currently_provable() and not game.is_contract_already_lost(human_seat)
	laydown_btn.visible = eligible

# The mirror image of the rule above: for Nello the button appears only when the
# claimant is NOT on lead. That single condition also excludes trick 1 for free
# (the bidder leads it), and self-hides once the Nello is dead — catching a trick
# is exactly what puts you back on lead.
#
# Bidder only. A defender's equivalent claim would be "I can force the bidder to
# take a trick", which is a different proof this doesn't implement.
func _update_laydown_button_visibility_nello():
	var eligible = game.current_bid != null \
		and game.current_bid.player_id == human_seat \
		and game.current_trick.plays.size() > 0 \
		and not game.is_contract_already_lost(human_seat)
	if eligible and game.settings.laydown_mode == "assisted":
		eligible = _nello_laydown_provable()
	laydown_btn.visible = eligible

# Gathers live state for the Nello search. The sitting-out partner is left out of
# `hands` entirely — that absence is what lets the search ignore their seven
# dominoes instead of treating them as unseen threats.
func _nello_laydown_provable() -> bool:
	if game.current_bid == null:
		return false
	var partner_seat: int = (int(game.current_bid.player_id) + 2) % 4
	var hands := {}
	for p in game.players:
		if p.id != partner_seat:
			hands[p.id] = p.hand
	var leader_seat: int = game.current_player
	if game.current_trick.plays.size() > 0:
		leader_seat = int(game.current_trick.plays[0]["player"])
	# Mirrors game.gd's own fallback: an unset per-hand mode means "high".
	var mode: String = game.active_nello_doubles_mode if game.active_nello_doubles_mode != "" else "high"
	return LaydownCheckScript.is_provable_nello_laydown(
		human_seat, hands, game.current_trick.plays, leader_seat,
		mode, game.active_nello_doubles_reversed)

func _laydown_currently_provable() -> bool:
	var knowledge = PublicKnowledge.from_state(PublicFrame.new(game.hand_history, game.current_trick))
	# Always "high": Nello never reaches this proof. Both callers route it to
	# _nello_laydown_provable() instead (the take-tricks question this one asks
	# is the losing hand under Nello — see the Nello lay-down commit), so the
	# doubles mode here is only ever the non-Nello default. This used to read
	# `game.active_nello_doubles_mode if game.variant == NELLO ...`, a branch
	# that could not be taken and implied a routing that does not exist.
	return LaydownCheckScript.is_provable_laydown(
		game.players[human_seat].hand, game.trump, knowledge,
		"high", game.active_doubles_trump_reversed, game.active_nello_doubles_reversed
	)

func _on_laydown_button_pressed():
	laydown_btn.visible = false
	# Authentic mode shows the button without checking first, so this is the only
	# thing standing between a self-judged claim and a wrongly awarded hand — it
	# has to use the proof that matches the contract being played.
	var provable = _nello_laydown_provable() if game.variant == BidScript.Type.NELLO \
		else _laydown_currently_provable()
	var correct = provable and not game.is_contract_already_lost(human_seat)
	_reveal_all_hands_face_up()
	var result = game.resolve_hand_via_laydown(human_seat, correct)
	_show_hand_result(result)

func _reveal_all_hands_face_up():
	_populate_hand_container(opponent_top_container, game.players[2].hand, true, true)
	_populate_hand_container(opponent_left_container, game.players[3].hand, true, true)
	_populate_hand_container(opponent_right_container, game.players[1].hand, true, true)

func _begin_play(leader_override: int = -1):
	_clear_bid_bubbles()
	var leader: int
	if leader_override >= 0:
		leader = leader_override
	else:
		leader = game.current_bid.player_id if game.current_bid else 0
	_play_trick(leader)

func _play_trick(leader: int):
	_armed_domino = null
	_small_end_active = false
	_small_end_toggle_btn.visible = false
	_small_end_toggle_btn.button_pressed = false
	_update_small_end_button_style()
	game.start_trick(leader)
	_current_trick_reasons.clear()
	_clear_play_area()
	_set_status("%s leads the trick" % _seat_label(leader))
	_play_next_in_trick()

func _play_next_in_trick():
	var player = game.players[game.current_player]

	# Nello: partner sits out — skip their turn entirely
	if game.variant == BidScript.Type.NELLO:
		var nello_partner = (game.current_bid.player_id + 2) % 4
		if game.current_player == nello_partner:
			game.current_player = (game.current_player + 3) % 4
			if game.current_trick.plays.size() < 3:  # only 3 players in Nello
				_play_next_in_trick()
			else:
				await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 1.2).timeout
				_resolve_trick()
			return

	if player.is_human:
		if _armed_domino != null:
			var legal = game.get_legal_moves(game.players[human_seat])
			var armed = _armed_domino
			_armed_domino = null
			if legal.has(armed):
				_clear_highlights()
				_execute_play(game.players[human_seat], armed)
				return
			# Defensive fallback if it were ever somehow invalid — falls through
			# to the normal wait-for-tap path below instead of dropping the turn.
		_highlight_legal_moves()
		waiting_for_human = true
		_update_small_end_button_visibility()
		_update_laydown_button_visibility()
		_set_status("Your turn — tap a domino to play")
	else:
		status_label.text = "%s is thinking..." % _seat_label(player.id)
		await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 1.4).timeout
		var chosen = _ai_choose_domino(player)
		_animate_ai_play(player, chosen)

func _highlight_legal_moves():
	var legal = game.get_legal_moves(game.players[human_seat])
	for child in player_hand_container.get_children():
		if child is DominoTile:
			var playable = legal.has(child.domino)
			child.set_playable(playable)
			child.mouse_filter = Control.MOUSE_FILTER_STOP if playable else Control.MOUSE_FILTER_IGNORE

func _human_already_played_this_trick() -> bool:
	for play in game.current_trick.plays:
		if play["player"] == human_seat:
			return true
	return false

func _update_armable_highlights():
	if _hand_over:
		return  # hand's decided — nothing left to arm, and re-lighting tiles here
			# would undo the shutdown _show_hand_result() just performed
	if waiting_for_human:
		return  # your actual turn owns highlighting via _highlight_legal_moves()

	var can_arm := true
	if game.current_trick.plays.size() == 0:
		can_arm = false  # trick not led yet — led suit unknown
	elif _human_already_played_this_trick():
		can_arm = false
	elif game.variant == BidScript.Type.NELLO and human_seat == (game.current_bid.player_id + 2) % 4:
		can_arm = false  # Nello partner sits out this hand — nothing to arm

	var legal: Array[Domino] = []
	if can_arm:
		legal = game.get_legal_moves(game.players[human_seat])

	for child in player_hand_container.get_children():
		if child is DominoTile:
			var playable = can_arm and legal.has(child.domino)
			child.set_playable(playable)
			child.set_selected(playable and child.domino == _armed_domino)
			child.mouse_filter = Control.MOUSE_FILTER_STOP if playable else Control.MOUSE_FILTER_IGNORE

func _on_human_domino_pressed(tile: DominoTile):
	if _hand_over:
		return   # banner is up; the hand is decided and taps must not resume play
	if waiting_for_human:
		var legal = game.get_legal_moves(game.players[human_seat])
		if not legal.has(tile.domino):
			return
		var d = tile.domino
		var is_opening_lead = game.tricks_played == 0 and game.current_trick.plays.size() == 0
		var declared_suit = -1
		if _small_end_active and is_opening_lead and not d.is_double() and not d.is_trump(game.trump):
			declared_suit = min(d.left, d.right)
		waiting_for_human = false
		_armed_domino = null
		_small_end_active = false
		_small_end_toggle_btn.visible = false
		_small_end_toggle_btn.button_pressed = false
		_update_small_end_button_style()
		_clear_highlights()
		_execute_play(game.players[human_seat], d, declared_suit)
		return

	# Pre-arming: only once the trick has been led, and only before your turn.
	if game.current_trick.plays.size() == 0:
		return
	if _human_already_played_this_trick():
		return
	if game.variant == BidScript.Type.NELLO and human_seat == (game.current_bid.player_id + 2) % 4:
		return
	var legal = game.get_legal_moves(game.players[human_seat])
	if not legal.has(tile.domino):
		return

	if _armed_domino == tile.domino:
		_armed_domino = null   # tapping the armed tile again cancels it
	else:
		_armed_domino = tile.domino
	_update_armable_highlights()

# ── Drag-to-reorder hand (Katy, July 13, 2026) ──────────────────────────────
# Available anytime, pre-bid and during active play — not phase-restricted.
# Safe because nothing indexes into Player.hand by position (every consumer
# iterates/filters), and deal_snapshot captures deal-time order separately
# before any reordering could occur. Human seat only — opponent/partner
# hands render in their own containers, which never connect these signals.
func _on_hand_drag_started(tile: DominoTile):
	tile.modulate.a = 0.35  # original tile fades in place, marks the "source" slot
	_drag_ghost = DominoTile.new()
	_bubble_overlay.add_child(_drag_ghost)
	_drag_ghost.setup(tile.domino, true, game.trump)
	_drag_ghost.size = tile.size
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.modulate.a = 0.92

func _on_hand_drag_moved(tile: DominoTile, global_pos: Vector2):
	if not is_instance_valid(_drag_ghost):
		return
	_drag_ghost.position = _drag_ghost.get_parent().get_local_mouse_position() - _drag_ghost.size / 2.0

func _on_hand_drag_ended(tile: DominoTile, was_drag: bool):
	tile.modulate.a = 1.0
	if not was_drag:
		if is_instance_valid(_drag_ghost):
			_drag_ghost.queue_free()
		_drag_ghost = null
		return

	var drop_center_x = _drag_ghost.global_position.x + _drag_ghost.size.x / 2.0
	var siblings = player_hand_container.get_children()
	var new_index = siblings.size()
	for i in range(siblings.size()):
		var sib = siblings[i]
		if sib == tile:
			continue
		if drop_center_x < sib.global_position.x + sib.size.x / 2.0:
			new_index = i
			break

	var hand = game.players[human_seat].hand
	hand.erase(tile.domino)
	new_index = clampi(new_index, 0, hand.size())
	hand.insert(new_index, tile.domino)

	if is_instance_valid(_drag_ghost):
		_drag_ghost.queue_free()
	_drag_ghost = null

	_refresh_all_hands()

func _animate_ai_play(player: Player, domino: Domino):
	_execute_play(player, domino)

func _ai_choose_domino(player: Player) -> Domino:
	var legal = game.get_legal_moves(player)
	var partner_id = (player.id + 2) % 4
	var is_partner = (player.id == (human_seat + 2) % 4)
	var reason_log: Array = []
	var frame = PublicFrame.new(game.hand_history, game.current_trick)
	var knowledge = PublicKnowledge.from_state(frame)
	var chosen = AIPlayer.decide_play(
		legal, player.hand, game.current_trick,
		player.id, partner_id, game.trump, reason_log,
		game.settings.ai_difficulty,
		is_partner,
		game.variant,
		game.current_bid.player_id if game.current_bid != null else -1,
		knowledge,
		game.team_points,
		game.current_bid.value if game.current_bid != null else 0
	)
	if reason_log.size() > 0:
		_last_play_reason = reason_log[-1]
	else:
		_last_play_reason = ""
	return chosen

func _execute_play(player: Player, domino: Domino, declared_suit: int = -1):
	game.play_domino(player, domino, declared_suit)
	var reason = _last_play_reason if _last_play_reason != "" else ("You played this" if player.is_human else "")
	_current_trick_reasons.append({"player": player.id, "domino": domino, "reason": reason})
	print("  [Trick %d] [%s] %s" % [game.tricks_played + 1, _player_label(player.id), reason])
	_last_play_reason = ""
	_add_to_play_area(player.id, domino)
	_refresh_all_hands()

	game.current_player = (game.current_player + 3) % 4
	_update_armable_highlights()

	var trick_size = 3 if game.variant == BidScript.Type.NELLO else 4
	if game.current_trick.plays.size() < trick_size:
		_play_next_in_trick()
	else:
		await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 1.2).timeout
		_resolve_trick()

func _resolve_trick():
	var winner_id = game.resolve_trick()
	game.record_trick(game.current_trick, winner_id, _current_trick_reasons)
	var winner_team = winner_id % 2
	var win_verb = "win" if winner_id == human_seat else "wins"
	_set_status("%s %s the trick!" % [_seat_label(winner_id), win_verb])
	# game.resolve_trick() has already credited this trick's points, so the
	# readout ticks over at the same moment the trick is awarded.
	_update_points_readout()

	# All 4 dominoes from this trick, in play order
	var trick_dominoes: Array = []
	for play in game.current_trick.plays:
		trick_dominoes.append(play["domino"])

	if winner_team == 0:
		_us_tricks.add_trick_dominoes(trick_dominoes)
	else:
		_them_tricks.add_trick_dominoes(trick_dominoes)

	await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 2.2).timeout
	_clear_play_area()
	_clear_highlights()

	# Hand-Ends-Early: two independent checks, two independent toggles.
	# All-tricks contracts (Marks/Sevens/Nello/Plunge/Splash) only ever
	# check "set" — "achieved early" isn't possible for these by
	# definition, since winning requires literally every trick, only
	# confirmable at the actual 7th. Points bids (including Follow Me —
	# see is_points_bid_decided()'s own comment) check both directions,
	# since points accumulate rather than needing every trick.
	if game.settings.hand_ends_early_set and game.is_contract_already_lost(game.current_bid.player_id):
		_resolve_hand()
		return
	if game.settings.hand_ends_early_points and game.is_points_bid_decided():
		_resolve_hand()
		return

	if game.tricks_played < 7:
		_play_trick(winner_id)
	else:
		_resolve_hand()

func _resolve_hand():
	_show_hand_result(game.resolve_hand())

# Shared by both the normal end-of-hand path (_resolve_hand()) and the
# lay-down claim path (_on_laydown_button_pressed()) — same result-dict
# shape either way (winner/reason/team_marks/team_points), so the same
# banner/marks-update/Replay-and-Next-Hand UI applies regardless of how
# the hand actually ended.
func _show_hand_result(result: Dictionary):
	# Close the hand down before anything is drawn. A hand can end with tiles
	# still in the human's hand (lay-down, or either hand-ends-early toggle), and
	# those tiles stay hit-testable unless play input is explicitly shut off —
	# which is how a lay-down could show "YOU WIN THIS HAND!" and then carry on
	# playing the hand underneath the banner.
	_hand_over = true
	waiting_for_human = false
	_armed_domino = null
	_clear_highlights()
	if _small_end_toggle_btn:
		_small_end_active = false
		_small_end_toggle_btn.visible = false
		_small_end_toggle_btn.button_pressed = false
		_update_small_end_button_style()
	if laydown_btn:
		laydown_btn.visible = false

	var winner_team = result.get("winner", 0)
	var team_str = "Your team" if winner_team == 0 else "Their team"
	var marks = result.get("team_marks", [0,0])
	_set_status("Hand over! %s wins — %s" % [team_str, result.get("reason", "")])

	if is_instance_valid(_hand_result_banner):
		_hand_result_banner.queue_free()
	_hand_result_banner = Label.new()
	# Two different ways to lose, and they deserve different words: our own
	# contract going down is "Hand Lost", the opponents making theirs is "They
	# Won". Read off the bidder's seat rather than the result dict, which only
	# records who won the hand, not who was playing the contract. No bid on
	# record falls back to "Hand Lost" — the safer thing to claim.
	var lost_text := "Hand Lost"
	if game.current_bid != null and game.current_bid.player_id % 2 != 0:
		lost_text = "They Won"
	_hand_result_banner.text = "YOU WIN THIS HAND! 🎉" if winner_team == 0 else lost_text
	_hand_result_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scaled_font(_hand_result_banner, 36)
	_hand_result_banner.add_theme_font_override("font", _font_rye)
	_hand_result_banner.add_theme_color_override("font_color", Color(0.95, 0.80, 0.15) if winner_team == 0 else Color(0.85, 0.35, 0.30))
	play_vbox.add_child(_hand_result_banner)
	# The banner is a big Rye line, and the diamond below is about to be cleared
	# for the Replay/Next buttons — holding its full height open on top of the
	# banner overflowed play_vbox and shoved the player's hand off the bottom.
	_refresh_play_area_reservation()

	_us_marks.set_marks(marks[0])
	_them_marks.set_marks(marks[1])
	_update_points_readout()

	_clear_play_area()

	var btn_vbox = VBoxContainer.new()
	btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_vbox.add_theme_constant_override("separation", 12)
	play_area_container.add_child(btn_vbox)

	if game.hand_history.size() > 0:
		_replay_btn = Button.new()
		_replay_btn.text = "Replay Hand →"
		_replay_btn.custom_minimum_size = Vector2(180, 48)
		_replay_btn.pressed.connect(_show_replay)
		btn_vbox.add_child(_replay_btn)

	_continue_btn = Button.new()
	_continue_btn.text = "Next Hand →"
	_continue_btn.custom_minimum_size = Vector2(160, 48)
	_continue_btn.modulate = Color(0.95, 0.80, 0.15)
	_continue_btn.pressed.connect(_on_hand_continue)
	btn_vbox.add_child(_continue_btn)

	var game_winner = game.check_game_over()
	if game_winner >= 0:
		if game.settings.win_by_two and abs(game.team_marks[0] - game.team_marks[1]) == 1:
			var notice = AcceptDialog.new()
			notice.title = "Lechner Hall Rule"
			notice.dialog_text = "Traditional Lechner Hall rules require a team to win by two marks."
			notice.ok_button_text = "Got it"
			add_child(notice)
			notice.popup_centered()
			notice.confirmed.connect(func(): notice.queue_free())
		var winner_str = "YOU WIN! 🎉" if game_winner == 0 else "Opponents win."
		_set_status("GAME OVER — " + winner_str)
		if _continue_btn and is_instance_valid(_continue_btn):
			# remove_child before queue_free so btn_vbox's minimum size stops
			# counting this button this frame — queue_free alone defers the
			# unparenting to end-of-frame and would skew the centring below.
			btn_vbox.remove_child(_continue_btn)
			_continue_btn.queue_free()
			_continue_btn = null
		_new_game_btn = Button.new()
		_new_game_btn.text = "New Game"
		_new_game_btn.custom_minimum_size = Vector2(160, 48)
		_new_game_btn.modulate = Color(0.95, 0.80, 0.15)
		_new_game_btn.pressed.connect(_on_new_game_pressed)
		btn_vbox.add_child(_new_game_btn)
		# play_area_container no longer centres its children for us.
		_place_in_play_area(btn_vbox)
		return

	_place_in_play_area(btn_vbox)

# ─── DISPLAY HELPERS ─────────────────────────────────────────────────────────

func _refresh_all_hands():
	_refresh_hand(game.players[0])
	_refresh_opponent_hands()

func _refresh_hand(player: Player):
	if player.id == human_seat:
		_populate_hand_container(player_hand_container, player.hand, true)
	# Opponent hands refreshed via _refresh_opponent_hands

func _refresh_opponent_hands():
	# Top = player 2 (partner), left = player 3, right = player 1
	_populate_hand_container(opponent_top_container, game.players[2].hand, false, true)
	_populate_hand_container(opponent_left_container, game.players[3].hand, false, true)
	_populate_hand_container(opponent_right_container, game.players[1].hand, false, true)

func _populate_hand_container(container: Container, hand: Array, face: bool, small: bool = false):
	for child in container.get_children():
		child.queue_free()
	for d in hand:
		var tile = DominoTile.new()
		tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		container.add_child(tile)
		tile.setup(d, face, game.trump)
		tile.custom_minimum_size = TILE_SMALL if small else TILE_FULL
		if face:
			tile.domino_pressed.connect(_on_human_domino_pressed)
			# No .bind(tile) here — the drag signals already emit the tile
			# as their own first argument (mirrors domino_pressed's plain
			# connect above); binding it too would append a duplicate
			# trailing arg and throw an arity mismatch at emit time.
			tile.domino_drag_started.connect(_on_hand_drag_started)
			tile.domino_drag_moved.connect(_on_hand_drag_moved)
			tile.domino_drag_ended.connect(_on_hand_drag_ended)

# Played tiles ride smaller than the ones in your hand. Not cosmetic: four
# slots have to clear each other inside the play area's ~290px of height, and a
# slot at full tile size is 165px tall, so the top and bottom seats alone would
# need 338px. At 0.72 the four fit with room to spare.
const PLAY_TILE_SCALE := 0.85
const SEAT_LABEL_SIZE := 11
const SLOT_VBOX_SEPARATION := 2.0   # must match _add_to_play_area()'s override
const PLAY_SLOT_GAP := 8.0          # clear felt between neighbouring slots
const PLAY_AREA_PADDING := 8.0

# The box one played tile occupies: the tile, the VBox separation, and the seat
# label beneath it. Width takes the WIDEST of the four live seat labels — they
# range from "You" to a profile name to the "Right Opponent" fallback — so one
# box describes every slot and the clearance maths below holds whoever is
# seated. Height is measured, not guessed: Font.get_height() reports the tallest
# font in the fallback chain (NotoSansSymbols, ~42px at size 20) rather than
# Nunito's own ~29px, and the Label really is that tall, so that is the number
# that matters.
func _play_area_slot_size() -> Vector2:
	var fs: int = int(round(SEAT_LABEL_SIZE * font_scale))
	var f: Font = _font_nunito_regular if _font_nunito_regular != null else ThemeDB.fallback_font
	var label_w: float = 0.0
	for pid in range(4):
		label_w = max(label_w, f.get_string_size(_seat_label(pid), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return Vector2(
		max(TILE_PLAYED.x, label_w),
		TILE_PLAYED.y + SLOT_VBOX_SEPARATION + f.get_height(fs))

# Vertical room the diamond needs: the top and bottom slots sit one slot-height
# plus a gap apart centre to centre, so the whole span is two slots plus the gap.
func _play_area_min_height() -> float:
	return _play_area_slot_size().y * 2.0 + PLAY_SLOT_GAP + PLAY_AREA_PADDING

# Whether the diamond needs its full height held open. While one of the picker
# panels is up, nothing has been played yet — the diamond is empty felt, and
# reserving room for it on top of the picker made play_vbox taller than the
# window, which pushed the player's own hand clean off the bottom of the
# screen. So the reservation is dropped for as long as a picker is showing.
func _play_area_reserves_height() -> bool:
	for p in [bid_panel, trump_panel, nello_panel, nello_exchange_panel]:
		if is_instance_valid(p) and p.visible:
			return false
	# Same story for the end-of-hand banner: it only ever shares play_vbox with
	# an emptied diamond (just the Replay/Next buttons), so the reservation is
	# dead weight while it is up. Checked for being in-tree as well as valid,
	# since queue_free() defers and the node outlives the call that dropped it.
	if is_instance_valid(_hand_result_banner) and _hand_result_banner.is_inside_tree():
		return false
	return true

# Driven off each picker's visibility_changed rather than called at the ~13
# sites that set .visible, so a future panel toggle can't silently reintroduce
# the overflow. Also the single owner of the reservation after a resize.
func _refresh_play_area_reservation():
	if not is_instance_valid(play_area_container):
		return
	var h: float = _play_area_min_height() if _play_area_reserves_height() else 0.0
	play_area_container.custom_minimum_size = Vector2(0, h)

# Re-derives a placed child's seat bias after a resize. An HBoxContainer used
# to re-flow its children for free; a plain Control does not, so anything
# already on the table has to be repositioned explicitly. Children tagged in
# _add_to_play_area() keep their seat bias; anything else (the end-of-hand
# button column) re-centres with none.
func _play_area_slot_offset_for(node: Control) -> Vector2:
	if node.has_meta("play_area_seat"):
		return _play_area_slot_offset(int(node.get_meta("play_area_seat")))
	return Vector2.ZERO


# Centre-to-centre offsets derived from the slot box, so the four slots are
# guaranteed to clear each other. The old fixed fraction of TILE_FULL
# (PLAY_SLOT_BIAS 0.4) gave 25.6px of bias against a 172px-tall slot, which is
# why all six pairs overlapped into an unreadable smear. Left and right clear
# the centre column horizontally, where the play area has width to spare; top
# and bottom clear each other vertically, which is the scarce axis.
func _play_area_slot_offset(player_id: int) -> Vector2:
	var slot: Vector2 = _play_area_slot_size()
	var dx: float = slot.x + PLAY_SLOT_GAP
	var dy: float = (slot.y + PLAY_SLOT_GAP) * 0.5
	if player_id == human_seat:
		return Vector2(0, dy)          # bottom — toward you
	elif player_id == (human_seat + 2) % 4:
		return Vector2(0, -dy)         # top — toward partner
	elif player_id == (human_seat + 1) % 4:
		return Vector2(dx, 0)          # right — toward right opponent
	else:
		return Vector2(-dx, 0)         # left — toward left opponent

# Centres a child of play_area_container, optionally biased toward a seat.
# Deliberately synchronous — _add_to_play_area() runs mid-sequence inside
# _execute_play(), which continues straight into turn-passing, so a frame-wait
# here would shift turn-order timing. get_combined_minimum_size() reads the
# properties set directly above (custom_minimum_size, font size) rather than
# the results of a layout pass, so it is accurate without waiting.
# Re-centres everything currently on the table. Setting a child's size/position
# can't change a plain Control's own size, so this can't re-trigger `resized`.
func _replace_play_area_children() -> void:
	if not is_instance_valid(play_area_container):
		return
	for child in play_area_container.get_children():
		if not (child is Control):
			continue
		# Tiles already on the table have to pick up the new TILE_PLAYED before
		# being re-placed, or the slot boxes and the offsets disagree.
		if child.has_meta("play_area_seat"):
			for t in child.get_children():
				if t is DominoTile:
					t.custom_minimum_size = TILE_PLAYED
		_place_in_play_area(child, _play_area_slot_offset_for(child))

func _place_in_play_area(node: Control, offset: Vector2 = Vector2.ZERO) -> void:
	var node_size = node.get_combined_minimum_size()
	node.size = node_size
	node.position = play_area_container.size * 0.5 + offset - node_size * 0.5

func _add_to_play_area(player_id: int, domino: Domino):
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(SLOT_VBOX_SEPARATION))
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.set_meta("play_area_seat", player_id)  # lets _on_viewport_resized re-place it
	play_area_container.add_child(vb)

	var tile = DominoTile.new()
	tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(tile)
	tile.setup(domino, true, game.trump)
	tile.custom_minimum_size = TILE_PLAYED

	var lbl = Label.new()
	lbl.text = _seat_label(player_id)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color.WHITE)
	_scaled_font(lbl, SEAT_LABEL_SIZE)
	vb.add_child(lbl)

	_place_in_play_area(vb, _play_area_slot_offset(player_id))

func _clear_play_area():
	for child in play_area_container.get_children():
		child.queue_free()

func _clear_highlights():
	for child in player_hand_container.get_children():
		if child is DominoTile:
			child.set_playable(false)
			child.set_selected(false)
			child.mouse_filter = Control.MOUSE_FILTER_STOP

func _set_info(text: String):
	info_label.text = text

# The readout at the top of the play area: points each team has taken in the
# hand currently being played, refreshed as each trick is awarded. Marks are
# already permanently on screen in the two ALL displays, and trump/contract in
# trump_indicator_label and the bid reminder, so this line is free to track the
# one number that actually moves trick to trick. game.team_points is zeroed by
# deal_hands() and accumulated by resolve_trick(), so it needs no reset here.
func _update_points_readout():
	var pts: Array = game.team_points if game != null else [0, 0]
	_set_info("You   %d   | POINTS |   Them   %d" % [pts[0], pts[1]])

func _set_status(text: String):
	status_label.text = text
	print(text)

# Maps a trump value to display text. Handles the two non-numeric-suit
# cases (-1 = Follow Me, Domino.DOUBLES_TRUMP = doubles-are-trump) that
# only the human's trump-panel buttons can produce — AI's best_trump()
# always returns 0-6 — so a plain suit_names[suit] index would crash on
# either of them.
func _trump_display_name(suit: int) -> String:
	var suit_names = ["Blanks", "Ones", "Twos", "Threes", "Fours", "Fives", "Sixes"]
	if suit == -1:
		return "No Trump (Follow Me)"
	if suit == Domino.DOUBLES_TRUMP:
		return "Doubles"
	return suit_names[suit]

# Bottom-left bid reminder — three lines: who bid + which team, the
# contract's trump/mode, and the bid's value. Call after every point where
# a contract's trump suit or Nello doubles mode is finalized (both the
# human panels' handlers and the inline AI branches in _finish_bidding()),
# so it never goes stale mid-hand. Cleared (empty text) at the start of a
# new auction in _start_bidding(), before any bid exists yet.
# How wide the reminder may run before it would sit under the player's own
# dominoes: from its own left edge across to where a full hand of seven starts.
# The hand is centred, so this is at its narrowest at the minimum viewport width
# and only opens up from there — which is why it is computed rather than fixed.
func _refresh_bid_reminder_width() -> void:
	if not is_instance_valid(bid_reminder_label):
		return
	var hand_w: float = 7.0 * TILE_FULL.x + 6.0 * 4.0   # tiles plus HBox separations
	var vp_w: float = get_viewport().get_visible_rect().size.x
	var avail: float = (vp_w - hand_w) * 0.5 - PLAY_AREA_INSET - BID_REMINDER_SIDE_GAP
	# offset_right, not size.x: the anchors are collapsed on the left edge, so the
	# width is these two offsets and setting it this way can't be undone by a
	# minimum-size recalculation.
	bid_reminder_label.offset_right = bid_reminder_label.offset_left + max(120.0, avail)

func _update_bid_reminder():
	var bid = game.current_bid
	if bid == null or bid.type == BidScript.Type.PASS:
		bid_reminder_label.text = ""
		return

	# Who won the bid, by the name on the table rather than a seat index. For the
	# human, _seat_label() already returns "You", and "You - Us" reads as noise,
	# so the team tag is dropped there and kept everywhere it actually tells you
	# something.
	var bidder_name = _seat_label(bid.player_id)
	var line1: String = bidder_name
	if bid.player_id != human_seat:
		var team_label = "Us" if bid.player_id % 2 == human_seat % 2 else "Them"
		line1 = "%s - %s" % [bidder_name, team_label]

	var line2: String
	if bid.type == BidScript.Type.NELLO:
		var mode_names = {"high": "high", "low": "low", "own_suit": "own suit"}
		var mode_label = mode_names.get(game.active_nello_doubles_mode, game.active_nello_doubles_mode)
		if game.active_nello_doubles_mode == "own_suit" and game.active_nello_doubles_reversed:
			mode_label = "own suit (reversed)"
		line2 = "Nello doubles %s" % mode_label
	elif bid.type == BidScript.Type.SEVENS:
		line2 = "Sevens"
	elif game.trump == -1:
		line2 = "No Trump (Follow Me)"
	elif game.trump == Domino.DOUBLES_TRUMP:
		line2 = "Doubles are trump"
	else:
		line2 = "trump suit %d" % game.trump

	var line3: String
	if bid.type == BidScript.Type.POINTS:
		line3 = "%d Points" % bid.value
	else:
		line3 = "%d mark%s" % [bid.value, "" if bid.value == 1 else "s"]

	bid_reminder_label.text = "%s\n%s\n%s" % [line1, line2, line3]

# Large, temporary center-screen banner announcing the chosen trump —
# fire-and-forget (callers don't await this) so it doesn't block the
# transition into the first trick; it just overlays on top of it briefly.
func _show_trump_announcement(suit: int):
	if _bubble_overlay == null:
		return
	var label = Label.new()
	label.text = "Trump: %s" % _trump_display_name(suit)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scaled_font(label, 42)
	label.add_theme_color_override("font_color", Color(0.95, 0.80, 0.15))
	_bubble_overlay.add_child(label)
	await get_tree().process_frame
	if not is_instance_valid(label):
		return
	label.size = label.get_minimum_size()
	# Centered on play_area_container (the empty trick-display zone at this
	# point in the flow) rather than the whole screen — dead-centering on
	# the full viewport put it right on top of status_label's turn-prompt
	# text just below it.
	var target_rect = play_area_container.get_global_rect()
	label.position = Vector2(target_rect.position.x + target_rect.size.x / 2 - label.size.x / 2, target_rect.position.y + target_rect.size.y / 2 - label.size.y / 2)
	await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 1.6).timeout
	if is_instance_valid(label):
		label.queue_free()

# Shows a small bid label floating near a player's area
func _show_bid_bubble(pid: int, text: String):
	if _bubble_overlay == null:
		return
	if _bid_bubbles.has(pid):
		if is_instance_valid(_bid_bubbles[pid]):
			_bid_bubbles[pid].queue_free()
		_bid_bubbles.erase(pid)

	var lbl = Label.new()
	lbl.text = text
	_scaled_font(lbl, BID_BUBBLE_FONT_SIZE)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10, 0.90)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.5, 0.5, 0.5, 0.5)
	lbl.add_theme_stylebox_override("normal", style)

	_bubble_overlay.add_child(lbl)
	_bid_bubbles[pid] = lbl

	# Position near each player area after one frame so sizes are known
	await get_tree().process_frame

	if not is_instance_valid(lbl):
		return

	lbl.size = lbl.get_minimum_size()
	var screen_size = _bubble_overlay.size

	if pid == human_seat:
		# Below hand, centered
		lbl.position = Vector2(screen_size.x / 2 - lbl.size.x / 2, screen_size.y - 160)
	elif pid == (human_seat + 2) % 4:
		# Partner — top center
		lbl.position = Vector2(screen_size.x / 2 - lbl.size.x / 2, 8)
	elif pid == (human_seat + 1) % 4:
		# Right opponent
		lbl.position = Vector2(screen_size.x - lbl.size.x - 12, screen_size.y / 2 - lbl.size.y / 2)
	else:
		# Left opponent
		lbl.position = Vector2(12, screen_size.y / 2 - lbl.size.y / 2)

func _clear_bid_bubbles():
	for pid in _bid_bubbles:
		if is_instance_valid(_bid_bubbles[pid]):
			_bid_bubbles[pid].queue_free()
	_bid_bubbles.clear()

func _seat_label(pid: int) -> String:
	if pid == human_seat:
		return "You"
	if seat_profiles.has(pid):
		var profile = PlayerProfileScript.load(seat_profiles[pid])
		if profile != null and not profile.display_name.is_empty():
			return profile.display_name
	# Falls through here on: no assignment, missing file, or empty name —
	# never crashes, always resolves to something displayable.
	if pid == (human_seat + 2) % 4:
		return "Partner"
	elif pid == (human_seat + 1) % 4:
		return "Right Opponent"
	else:
		return "Left Opponent"



# ─── SETTINGS OVERLAY ────────────────────────────────────────────────────────

func _show_settings_panel():
	if game != null:
		_pending_settings = _copy_settings(game.settings)
	else:
		# No game running: open on whichever slot was last played, falling back
		# to Standard 42 on a fresh install. Seeding a real slot rather than a
		# bare standard_42() with preset_id == "" is load-bearing — Play's
		# persistence and the Reset button's visibility are both keyed off
		# preset_id, so an empty one would make the screen quietly unable to save.
		var key := _last_used_preset_key()
		_pending_settings = _resolve_settings_for_slot(key if not key.is_empty() else "standard")
	var vp = get_viewport().get_visible_rect().size
	_settings_panel_inner.custom_minimum_size = vp * 0.92
	_build_settings_content()
	settings_panel.visible = true

# Switching slots rebuilds _pending_settings from scratch instead of patching the
# object in place, so no field from the previously selected slot can survive into
# the new one.
func _on_settings_slot_pressed(key: String):
	_pending_settings = _resolve_settings_for_slot(key)
	_build_settings_content()

# Detach before freeing. queue_free() on its own is deferred to end-of-frame, so
# a rebuild that clears and refills within one call leaves the old rows parented
# alongside the new ones until the frame ends. That was invisible while these
# panels were only built on open; the slot buttons and domino-back buttons now
# rebuild in place on a press, where it shows as the whole form briefly doubling.
func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

func _build_settings_content():
	_clear_children(_settings_content_vbox)

	var title = Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scaled_font(title, 20)
	title.add_theme_color_override("font_color", Color.WHITE)
	_settings_content_vbox.add_child(title)

	# ── Header: which ruleset, and how hard ──────────────────────────────────
	# These two frame everything below rather than sitting among the rules: the
	# slot decides what the form is even showing, and difficulty is orthogonal to
	# every rule in it. The difficulty row used to be a lone full-width row here
	# with no space beside it, hence the container.
	var slot_lbl = Label.new()
	slot_lbl.text = "Ruleset:"
	slot_lbl.add_theme_color_override("font_color", Color.WHITE)
	slot_lbl.add_theme_font_override("font", _font_nunito_heavy)
	_scaled_font(slot_lbl, 15)
	_settings_content_vbox.add_child(slot_lbl)

	# Five fixed slots, wrapped rather than in one row — the names are
	# player-editable and can be much wider than the built-in labels.
	var slot_flow = HFlowContainer.new()
	slot_flow.add_theme_constant_override("h_separation", 6)
	slot_flow.add_theme_constant_override("v_separation", 6)
	_settings_content_vbox.add_child(slot_flow)

	for key in SLOT_KEYS:
		var slot_btn = Button.new()
		slot_btn.text = _slot_display_name(key)
		slot_btn.custom_minimum_size = Vector2(0, 40)
		_scaled_font(slot_btn, 14)
		if key == _pending_settings.preset_id:
			slot_btn.modulate = Color(0.95, 0.80, 0.15)
		slot_btn.pressed.connect(_on_settings_slot_pressed.bind(key))
		slot_flow.add_child(slot_btn)

	# AI Difficulty applies immediately, unlike every other row in this panel —
	# it's a pure AI-behavior parameter, not a ruleset/legality setting, so it
	# doesn't need to wait for Play. Still keeps _pending_settings in sync so a
	# later Play doesn't silently revert this to its pre-panel-open value.
	_add_option_row(_settings_content_vbox, "AI Difficulty", [
		["Casual", "casual"],
		["Expert", "expert"],
	], _pending_settings.ai_difficulty, func(v):
		_pending_settings.ai_difficulty = v
		_on_difficulty_chosen(v)
	)
	_settings_content_vbox.add_child(HSeparator.new())

	# ── BIDDING ──
	var bid_body = _make_section(_settings_content_vbox, "BIDDING")
	_add_option_row(bid_body, "Bid Direction", [
		["Left of shaker first", "shaker_left_first"],
		["Right of shaker first", "shaker_right_first"]
	], _pending_settings.bid_direction, func(v): _pending_settings.bid_direction = v)
	_add_spinbox_row(bid_body, "Minimum Bid", 30, 42, _pending_settings.minimum_bid,
		func(v): _pending_settings.minimum_bid = v)
	var forced_cb = _add_checkbox_row(bid_body, "Allow Forced Bid", _pending_settings.allow_forced_bid,
		func(v): _pending_settings.allow_forced_bid = v)
	var forced_sub = _add_sub_container(bid_body, forced_cb)
	_add_spinbox_row(forced_sub, "Forced Bid Minimum", 30, 42, _pending_settings.forced_bid_minimum,
		func(v): _pending_settings.forced_bid_minimum = v)
	_add_checkbox_row(bid_body, "Allow Jump Bids", _pending_settings.allow_jump_bids,
		func(v): _pending_settings.allow_jump_bids = v)

	# ── SPECIAL CONTRACTS ──
	var sc_body = _make_section(_settings_content_vbox, "SPECIAL CONTRACTS")

	var nello_cb = _add_checkbox_row(sc_body, "Allow Nello", _pending_settings.allow_nello,
		func(v): _pending_settings.allow_nello = v)
	var nello_sub = _add_sub_container(sc_body, nello_cb)
	# "Doubles Mode" dropdown hidden (July 21, 2026) — the bidder picks this
	# live in-game via nello_panel's buttons (High/Low/Own Suit) every hand,
	# so this settings-screen default was redundant and confusing. The
	# underlying nello_doubles_mode field is untouched — it's still read as
	# the AI-Nello fallback default (currently dead code; see
	# game_table.gd's _finish_bidding() Nello branch), just no longer
	# exposed here.
	_add_checkbox_row(nello_sub, "Allow Own Suit (Reversed)", _pending_settings.nello_doubles_reversed,
		func(v): _pending_settings.nello_doubles_reversed = v)
	_add_checkbox_row(nello_sub, "Only on Forced Bid", _pending_settings.nello_only_on_forced_bid,
		func(v): _pending_settings.nello_only_on_forced_bid = v)
	_add_checkbox_row(nello_sub, "Allow Blind Domino Exchange", _pending_settings.allow_nello_exchange,
		func(v): _pending_settings.allow_nello_exchange = v)

	var plunge_cb = _add_checkbox_row(sc_body, "Allow Plunge", _pending_settings.allow_plunge,
		func(v): _pending_settings.allow_plunge = v)
	var plunge_sub = _add_sub_container(sc_body, plunge_cb)
	_add_spinbox_row(plunge_sub, "Min Doubles Required", 2, 7, _pending_settings.plunge_minimum_doubles,
		func(v): _pending_settings.plunge_minimum_doubles = v)
	_add_spinbox_row(plunge_sub, "Min Bid (Marks)", 1, 7, _pending_settings.plunge_minimum_bid_marks,
		func(v): _pending_settings.plunge_minimum_bid_marks = v)

	var splash_cb = _add_checkbox_row(sc_body, "Allow Splash", _pending_settings.allow_splash,
		func(v): _pending_settings.allow_splash = v)
	var splash_sub = _add_sub_container(sc_body, splash_cb)
	_add_spinbox_row(splash_sub, "Min Doubles Required", 1, 6, _pending_settings.splash_minimum_doubles,
		func(v): _pending_settings.splash_minimum_doubles = v)
	_add_spinbox_row(splash_sub, "Bid Value (Marks)", 1, 7, _pending_settings.splash_bid_marks,
		func(v): _pending_settings.splash_bid_marks = v)

	var sevens_cb = _add_checkbox_row(sc_body, "Allow Sevens", _pending_settings.allow_sevens,
		func(v): _pending_settings.allow_sevens = v)
	var sevens_sub = _add_sub_container(sc_body, sevens_cb)
	# "Require 7-pip Domino in Hand" was removed here July 29 2026 — the rule is
	# now always on (from_dict() forces the field true), so there's nothing to
	# toggle. Only-on-forced-bid stays.
	_add_checkbox_row(sevens_sub, "Only on Forced Bid", _pending_settings.sevens_only_on_forced_bid,
		func(v): _pending_settings.sevens_only_on_forced_bid = v)

	_add_checkbox_row(sc_body, "Allow Follow Me / No Trump", _pending_settings.allow_follow_me,
		func(v): _pending_settings.allow_follow_me = v)

	# ── LAY DOWN ("Can't Be Caught") ──
	var laydown_body = _make_section(_settings_content_vbox, "LAY DOWN")
	var laydown_cb = _add_checkbox_row(laydown_body, "Allow Lay Down", _pending_settings.allow_laydown,
		func(v): _pending_settings.allow_laydown = v)
	var laydown_sub = _add_sub_container(laydown_body, laydown_cb)
	_add_option_row(laydown_sub, "Mode", [
		["Assisted (button only appears when correct)", "assisted"],
		["Authentic (self-judged, wrong claim forfeits)", "authentic"],
	], _pending_settings.laydown_mode, func(v): _pending_settings.laydown_mode = v)

	# ── HAND FLOW ──
	var flow_body = _make_section(_settings_content_vbox, "HAND FLOW")
	_add_checkbox_row(flow_body, "End Hand Early When Set (Marks/Sevens/Nello/Plunge/Splash)",
		_pending_settings.hand_ends_early_set,
		func(v): _pending_settings.hand_ends_early_set = v)
	_add_checkbox_row(flow_body, "End Hand Early When Points Bid Is Decided",
		_pending_settings.hand_ends_early_points,
		func(v): _pending_settings.hand_ends_early_points = v)

	# ── TRUMP & DOUBLES ──
	var trump_body = _make_section(_settings_content_vbox, "TRUMP & DOUBLES")
	_add_checkbox_row(trump_body, "Doubles Are a Trump Suit", _pending_settings.doubles_are_trump,
		func(v): _pending_settings.doubles_are_trump = v)
	_add_checkbox_row(trump_body, "Force Trump on Opening Lead", _pending_settings.force_trump_opening_lead,
		func(v): _pending_settings.force_trump_opening_lead = v)
	_add_checkbox_row(trump_body, "Allow Small-End Opening Lead", _pending_settings.allow_small_end_opening_lead,
		func(v): _pending_settings.allow_small_end_opening_lead = v)

	# ── Action row: Menu / Cancel / Play ──
	# Directly under the collapsed rule sections so all three are reachable without
	# scrolling. It used to sit last, but the domino-back picker below is ~140px of
	# always-open swatches and pushed the row off the fold — the one place in this
	# screen where "content, then actions" cost more than it was worth.
	var sep = HSeparator.new()
	_settings_content_vbox.add_child(sep)

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	_settings_content_vbox.add_child(btn_row)

	var home_btn = Button.new()
	home_btn.text = "⌂  Menu"
	home_btn.custom_minimum_size = Vector2(100, 44)
	home_btn.pressed.connect(_on_settings_home_pressed)
	btn_row.add_child(home_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(120, 44)
	cancel_btn.pressed.connect(func(): settings_panel.visible = false)
	btn_row.add_child(cancel_btn)

	# One action replaces both the old "Confirm & Restart" and "Save as New
	# Ruleset...": the active slot IS the save target, so there's nothing to name.
	# _save_last_used() matters here in a way it didn't for Confirm & Restart —
	# this screen can now switch slots, so the slot you actually pressed Play on
	# is what next launch should resume.
	var play_btn = Button.new()
	play_btn.text = "Play"
	play_btn.custom_minimum_size = Vector2(180, 44)
	play_btn.pressed.connect(func():
		_persist_preset_tweaks(_pending_settings)
		_save_last_used(_pending_settings.preset_id)
		_restart_game_with_settings(_pending_settings)
	)
	btn_row.add_child(play_btn)

	# ── Domino back ──
	# A table display preference, not part of the ruleset the action row above
	# commits: it saves on click rather than waiting for Play, and is deliberately
	# unaffected by which slot is selected.
	#
	# Not a collapsible _make_section() and not a list of names — the choice is
	# entirely visual, so it shows the actual backs, always open. Each swatch is a
	# real face-down DominoTile using its per-instance back override, so a new
	# entry in DOMINO_BACKS appears here correctly with no extra work.
	_settings_content_vbox.add_child(HSeparator.new())

	var back_header = Label.new()
	back_header.text = "DOMINO BACK"
	back_header.add_theme_font_override("font", _font_nunito_heavy)
	back_header.add_theme_color_override("font_color", Color.WHITE)
	_scaled_font(back_header, 15)
	_settings_content_vbox.add_child(back_header)

	var back_flow = HFlowContainer.new()
	back_flow.add_theme_constant_override("h_separation", 10)
	back_flow.add_theme_constant_override("v_separation", 10)
	_settings_content_vbox.add_child(back_flow)

	var current_back := _load_domino_back_pref()
	for entry in DOMINO_BACKS:
		var res_path := str(entry[1])
		var swatch = Button.new()
		swatch.custom_minimum_size = Vector2(SWATCH_W, SWATCH_H)
		# The name survives as a tooltip — useful for telling two similar patterns
		# apart, without putting a caption back under every tile.
		swatch.tooltip_text = str(entry[0])
		# Selection is a gold border, not modulate: modulate tints child nodes too,
		# which would recolour the very pattern the swatch exists to show.
		var sel_style = StyleBoxFlat.new()
		sel_style.bg_color = Color(0.10, 0.10, 0.13, 0.9)
		sel_style.set_border_width_all(3)
		sel_style.border_color = Color(0.95, 0.80, 0.15) if res_path == current_back \
			else Color(0.30, 0.30, 0.36)
		sel_style.corner_radius_top_left = 6
		sel_style.corner_radius_top_right = 6
		sel_style.corner_radius_bottom_left = 6
		sel_style.corner_radius_bottom_right = 6
		swatch.add_theme_stylebox_override("normal", sel_style)
		swatch.add_theme_stylebox_override("hover", sel_style)
		swatch.add_theme_stylebox_override("pressed", sel_style)
		swatch.pressed.connect(_on_domino_back_pressed.bind(res_path))
		back_flow.add_child(swatch)

		var tile = DominoTile.new()
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE   # let clicks reach the Button
		tile.use_back_override = true
		tile.back_texture_override = load(res_path) if not res_path.is_empty() \
			and ResourceLoader.exists(res_path) else null
		tile.setup(null, false, -1)                       # face down: no domino needed
		tile.position = Vector2(SWATCH_PAD, SWATCH_PAD)
		swatch.add_child(tile)

	# ── Reset to Default ──
	# Last on the screen deliberately. It is the one destructive control here, and
	# it is also the rarest — putting it below the action row keeps it out of reach
	# of a stray tap aimed at Play, and costs nothing since anyone who wants it
	# will go looking.
	#
	# Only the four built-in rulesets have a hardcoded "default" to reset to — the
	# Custom slot's saved file IS its default, so resetting it would be a no-op at
	# best and confusing at worst. CUSTOM_SLOT_KEY is deliberately absent from
	# BUILTIN_PRESET_KEYS so this gate covers it.
	if BUILTIN_PRESET_KEYS.has(_pending_settings.preset_id):
		_settings_content_vbox.add_child(HSeparator.new())
		var reset_btn = Button.new()
		reset_btn.text = "Reset to Default"
		reset_btn.custom_minimum_size = Vector2(220, 44)
		reset_btn.pressed.connect(_on_reset_to_default_pressed)
		_settings_content_vbox.add_child(reset_btn)

func _on_domino_back_pressed(res_path: String):
	_save_domino_back_pref(res_path)
	_update_domino_back_texture()
	# DominoTile reads the texture in _draw(), so tiles already on the table keep
	# the old art until they're rebuilt. Rebuild the hands now for immediate
	# feedback; everything else picks it up on the next hand.
	if game != null:
		_refresh_all_hands()
	_build_settings_content()

func _make_section(parent: VBoxContainer, title: String) -> VBoxContainer:
	var header = Button.new()
	header.text = "▶  " + title
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_font_override("font", _font_nunito_heavy)
	parent.add_child(header)

	var body = VBoxContainer.new()
	body.visible = false
	body.add_theme_constant_override("separation", 14)
	parent.add_child(body)

	header.pressed.connect(func():
		body.visible = not body.visible
		header.text = ("▼  " if body.visible else "▶  ") + title
	)
	return body

func _add_checkbox_row(parent: VBoxContainer, label: String, value: bool, setter: Callable) -> CheckBox:
	var cb = CheckBox.new()
	cb.text = label
	cb.button_pressed = value
	_scaled_font(cb, 15)
	cb.toggled.connect(setter)
	parent.add_child(cb)
	return cb

func _add_sub_container(parent: VBoxContainer, toggle_cb: CheckBox) -> VBoxContainer:
	var sub = VBoxContainer.new()
	sub.add_theme_constant_override("separation", 4)
	sub.visible = toggle_cb.button_pressed
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	parent.add_child(margin)
	margin.add_child(sub)
	# Toggle the actual content holder (sub), not the margin wrapper around
	# it — margin.visible was a second, separate copy of the same on/off
	# state that only ever got set once at construction time and never
	# updated again, so sub stayed permanently hidden until the whole panel
	# was rebuilt from scratch (closing and reopening Settings). One
	# variable tracking visibility instead of two that can drift apart.
	toggle_cb.toggled.connect(func(v): sub.visible = v)
	return sub

func _add_option_row(parent: VBoxContainer, label: String, options: Array, current: String, setter: Callable):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lbl = Label.new()
	lbl.text = label + ":"
	lbl.custom_minimum_size = Vector2(170, 0)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	_scaled_font(lbl, 15)
	row.add_child(lbl)
	var opt = OptionButton.new()
	var sel_idx = 0
	for i in range(options.size()):
		opt.add_item(options[i][0])
		if options[i][1] == current:
			sel_idx = i
	opt.select(sel_idx)
	opt.item_selected.connect(func(idx): setter.call(options[idx][1]))
	row.add_child(opt)

func _add_spinbox_row(parent: VBoxContainer, label: String, min_v: int, max_v: int, current: int, setter: Callable):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lbl = Label.new()
	lbl.text = label + ":"
	lbl.custom_minimum_size = Vector2(170, 0)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	_scaled_font(lbl, 15)
	row.add_child(lbl)
	var sb = SpinBox.new()
	sb.min_value = min_v
	sb.max_value = max_v
	sb.value = current
	sb.value_changed.connect(func(v): setter.call(int(v)))
	row.add_child(sb)

func _copy_settings(src: GameSettings) -> GameSettings:
	var dst = GameSettings.new()
	dst.bid_direction = src.bid_direction
	dst.allow_forced_bid = src.allow_forced_bid
	dst.forced_bid_minimum = src.forced_bid_minimum
	dst.minimum_bid = src.minimum_bid
	dst.max_open_bid_marks = src.max_open_bid_marks
	dst.allow_jump_bids = src.allow_jump_bids
	dst.allow_plunge = src.allow_plunge
	dst.plunge_minimum_doubles = src.plunge_minimum_doubles
	dst.plunge_minimum_bid_marks = src.plunge_minimum_bid_marks
	dst.allow_splash = src.allow_splash
	dst.splash_minimum_doubles = src.splash_minimum_doubles
	dst.splash_bid_marks = src.splash_bid_marks
	dst.allow_nello = src.allow_nello
	dst.allow_nello_exchange = src.allow_nello_exchange
	dst.nello_exchange_bidder_gives = src.nello_exchange_bidder_gives
	dst.nello_exchange_partner_gives = src.nello_exchange_partner_gives
	dst.nello_only_on_forced_bid = src.nello_only_on_forced_bid
	dst.nello_doubles_mode = src.nello_doubles_mode
	dst.nello_doubles_reversed = src.nello_doubles_reversed
	dst.allow_follow_me = src.allow_follow_me
	dst.allow_sevens = src.allow_sevens
	dst.sevens_require_seven_in_hand = src.sevens_require_seven_in_hand
	dst.sevens_only_on_forced_bid = src.sevens_only_on_forced_bid
	dst.doubles_are_trump = src.doubles_are_trump
	dst.doubles_trump_reversed = src.doubles_trump_reversed
	dst.allow_small_end_opening_lead = src.allow_small_end_opening_lead
	dst.force_trump_opening_lead = src.force_trump_opening_lead
	dst.marks_to_win = src.marks_to_win
	dst.ai_difficulty = src.ai_difficulty
	dst.preset_id = src.preset_id
	dst.allow_laydown = src.allow_laydown
	dst.laydown_mode = src.laydown_mode
	dst.hand_ends_early_set = src.hand_ends_early_set
	dst.hand_ends_early_points = src.hand_ends_early_points
	return dst

func _restart_game_with_settings(new_settings: GameSettings):
	settings_panel.visible = false
	preset_panel.visible = false
	_update_domino_back_texture()
	game = Game.new(new_settings)
	game.setup_players(human_seat)
	_us_marks.set_marks(0)
	_them_marks.set_marks(0)
	_us_tricks.clear_tricks()
	_them_tricks.clear_tricks()
	_start_hand()

func _show_game_board(visible: bool):
	_game_top_row.visible = visible
	_game_mid_row.visible = visible
	player_hand_container.visible = visible
	# The trick-list toggles and panels float on root rather than living in the
	# top row, so hiding the board doesn't take them with it — do it here.
	for team in range(2):
		if _tricks_toggle_btn[team] != null:
			_tricks_toggle_btn[team].visible = visible
		if _tricks_overlay[team] != null:
			_tricks_overlay[team].visible = visible and _tricks_expanded[team]

# ─── EXPANDED TRICK LISTS ─────────────────────────────────────────────────────
# The little scroll box only shows two rows of a pile that can reach seven, so
# each team gets a panel that opens in place over the felt and shows the lot.
# Two rules shape the implementation:
#   * It must not disturb the surrounding layout, so both the panel and its
#     toggle are absolutely-positioned children of root, tracked against the
#     scroll box's live rect rather than given a slot in the top row.
#   * There is only ever one TrickPile per team. Expanding reparents it into the
#     panel instead of mirroring it, so the two views can never disagree.
func _build_tricks_overlays(root_node: Control) -> void:
	for team in range(2):
		var panel := PanelContainer.new()
		panel.visible = false
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.06, 0.06, 0.09, 0.82)
		st.corner_radius_top_left = 8
		st.corner_radius_top_right = 8
		st.corner_radius_bottom_left = 8
		st.corner_radius_bottom_right = 8
		st.content_margin_left = 4
		st.content_margin_right = 4
		st.content_margin_top = 4
		st.content_margin_bottom = 4
		st.border_width_left = 1
		st.border_width_right = 1
		st.border_width_top = 1
		st.border_width_bottom = 1
		st.border_color = Color(0.55, 0.55, 0.55, 0.35)
		panel.add_theme_stylebox_override("panel", st)
		root_node.add_child(panel)
		_tricks_overlay[team] = panel

		var btn := Button.new()
		btn.text = "▼"
		btn.tooltip_text = "Show every domino this team has won"
		btn.custom_minimum_size = Vector2(TRICKS_BTN_SIZE, TRICKS_BTN_SIZE)
		btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
		btn.focus_mode = Control.FOCUS_NONE
		_scaled_font(btn, 10)
		btn.pressed.connect(_toggle_tricks_expanded.bind(team))
		root_node.add_child(btn)
		_tricks_toggle_btn[team] = btn

		# item_rect_changed, not resized: the columns move horizontally when the
		# viewport widens without their size changing at all, and the toggle has
		# to follow that too.
		_tricks_scroll[team].item_rect_changed.connect(_reposition_tricks_controls)

func _reposition_tricks_controls() -> void:
	for team in range(2):
		var scroll: ScrollContainer = _tricks_scroll[team]
		var btn: Button = _tricks_toggle_btn[team]
		var panel: PanelContainer = _tricks_overlay[team]
		if scroll == null or btn == null or panel == null or not scroll.is_inside_tree():
			continue
		var box: Rect2 = scroll.get_global_rect()
		# Medial edge: right of the US column, left of the THEM column.
		var bx: float = box.end.x + TRICKS_BTN_GAP
		if team == 1:
			bx = box.position.x - TRICKS_BTN_GAP - TRICKS_BTN_SIZE
		btn.position = Vector2(bx, box.position.y + (box.size.y - TRICKS_BTN_SIZE) * 0.5)
		# The panel opens exactly on the box so it hides it rather than repeating
		# the rows already visible there, and grows downward over the felt.
		panel.position = box.position

func _toggle_tricks_expanded(team: int) -> void:
	_set_tricks_expanded(team, not _tricks_expanded[team])

func _set_tricks_expanded(team: int, expanded: bool) -> void:
	var pile: TrickPile = _us_tricks if team == 0 else _them_tricks
	var scroll: ScrollContainer = _tricks_scroll[team]
	var panel: PanelContainer = _tricks_overlay[team]
	if pile == null or scroll == null or panel == null:
		return
	_tricks_expanded[team] = expanded

	if expanded:
		# Freeze the box's footprint before the pile leaves it. A ScrollContainer
		# sizes to its content, so an empty one collapses to its bare minimum,
		# the top row re-flows, and the points readout and partner hand slide
		# sideways — the exact layout disturbance this feature must not cause.
		scroll.custom_minimum_size.x = maxf(scroll.custom_minimum_size.x, scroll.size.x)

	var want_parent: Node = panel if expanded else scroll
	if pile.get_parent() != want_parent:
		pile.get_parent().remove_child(pile)
		want_parent.add_child(pile)

	panel.visible = expanded
	if expanded:
		# Snap back to the pile's current minimum. Without this the panel keeps
		# the height it reached with seven tricks in it and opens over empty felt
		# on a later hand that has won two.
		panel.size = Vector2.ZERO
	_tricks_toggle_btn[team].text = "▲" if expanded else "▼"
	_reposition_tricks_controls()

func _on_menu_play_pressed():
	var key := _last_used_preset_key()
	if key.is_empty():
		# Nothing saved to resume — send them to Settings to pick and tune a
		# ruleset rather than dropping them into an arbitrary default. Note this
		# is Settings, not the old fall-through to the rules picker: on a first
		# launch the merged screen is the one that can do everything.
		_show_settings_panel()
		return
	main_menu_panel.visible = false
	# _resolve_settings_for_slot() layers the saved difficulty on top of the
	# slot's own value, so there's no separate re-apply step here any more.
	_on_preset_chosen(key)

func _on_menu_rules_pressed():
	if _last_used_preset_key().is_empty():
		# First launch — the quick-switch picker has nothing to switch between
		# yet, so both menu buttons lead to the same place.
		_show_settings_panel()
		return
	main_menu_panel.visible = false
	_preset_status_label.visible = false
	_rebuild_preset_buttons()
	preset_panel.visible = true

func _on_settings_home_pressed():
	if game == null:
		# No game in progress — return directly, no confirmation needed.
		settings_panel.visible = false
		main_menu_panel.visible = true
		return

	var confirm = ConfirmationDialog.new()
	confirm.title = "Return to Menu?"
	confirm.dialog_text = "Current game will be lost. Return to main menu?"
	confirm.ok_button_text = "Return to Menu"
	confirm.cancel_button_text = "Stay"
	confirm.confirmed.connect(func():
		settings_panel.visible = false
		_show_game_board(false)
		main_menu_panel.visible = true
		game = null
		confirm.queue_free()
	)
	confirm.canceled.connect(func(): confirm.queue_free())
	add_child(confirm)
	confirm.popup_centered()

# The Choose Rules screen: quick-switch between the five slots, plus rename.
# Deliberately stays instant-apply (tapping a slot starts a hand) — full editing
# lives in the merged Settings screen, so this screen's only jobs are switching
# and naming. No directory scan any more: the slot list is fixed, and a slot with
# no saved file still resolves to its default.
func _rebuild_preset_buttons():
	# The menu floats on preset_panel, not inside the container being cleared, so
	# it would otherwise outlive the row it was anchored to.
	_close_slot_options_menu()
	_clear_children(_preset_btn_container)

	var active := _last_used_preset_key()
	for key in SLOT_KEYS:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var btn = Button.new()
		btn.text = "%s\n%s" % [_slot_display_name(key), str(SLOT_BLURBS.get(key, ""))]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 60)
		if key == active:
			btn.modulate = Color(0.95, 0.80, 0.15)
		btn.pressed.connect(_on_preset_chosen.bind(key))
		row.add_child(btn)

		# Same "…" affordance the old custom-ruleset rows had, but it opens
		# rename only — slots are fixed now, so there's nothing to delete.
		var opts_btn = Button.new()
		opts_btn.text = "…"
		opts_btn.custom_minimum_size = Vector2(36, 60)
		opts_btn.pressed.connect(_on_slot_options_pressed.bind(key, opts_btn))
		row.add_child(opts_btn)

		_preset_btn_container.add_child(row)

func _save_last_used(key: String):
	var data = {}
	var fr = FileAccess.open(LAST_USED_PATH, FileAccess.READ)
	if fr:
		var existing = JSON.parse_string(fr.get_as_text())
		fr.close()
		if existing is Dictionary:
			data = existing
	data["last_preset"] = key
	var fw = FileAccess.open(LAST_USED_PATH, FileAccess.WRITE)
	if fw:
		fw.store_string(JSON.stringify(data))
		fw.close()

# The slot key to resume into, or "" when there's nothing usable — which is the
# signal for "first launch" that routes Play and Choose Rules to Settings.
#
# Two things this deliberately does NOT do. It doesn't treat the existence of
# last_used.json as evidence of saved rules: that file also carries Profiles'
# seat_assignments and the difficulty choice, so a player who named their
# opponents before ever picking a ruleset has the file without having any rules.
# And it doesn't check for a file on disk the way the old inline check did —
# every slot in SLOT_KEYS resolves with or without one, so file existence is the
# wrong question. Validating against SLOT_KEYS also retires any pre-July-29-2026
# "custom:<name>" key that isn't the single Custom slot; those rulesets are no
# longer reachable from any screen, so resuming into one would drop the player
# into rules they can neither see nor edit.
func _last_used_preset_key() -> String:
	var f = FileAccess.open(LAST_USED_PATH, FileAccess.READ)
	if f == null:
		return ""
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary and data.has("last_preset"):
		var key := str(data["last_preset"])
		if SLOT_KEYS.has(key):
			return key
	return ""

# The player's committed difficulty, normalized, or "" if they've never chosen.
# Read directly from last_used.json — that file is not a serialized GameSettings,
# so GameSettingsScript.from_dict() (and its normalization) never sees it.
func _last_used_difficulty() -> String:
	var f = FileAccess.open(LAST_USED_PATH, FileAccess.READ)
	if f == null:
		return ""
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary and data.has("ai_difficulty"):
		return GameSettingsScript.normalize_difficulty(str(data["ai_difficulty"]))
	return ""

func _load_seat_assignments() -> Dictionary:
	var f = FileAccess.open(LAST_USED_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary and data.get("seat_assignments") is Dictionary:
		# JSON keys are always strings; normalize back to int seat ids.
		var raw: Dictionary = data["seat_assignments"]
		var result := {}
		for k in raw.keys():
			result[int(k)] = str(raw[k])
		return result
	return {}

func _save_seat_assignments() -> void:
	var data := {}
	var f = FileAccess.open(LAST_USED_PATH, FileAccess.READ)
	if f:
		var existing = JSON.parse_string(f.get_as_text())
		f.close()
		if existing is Dictionary:
			data = existing
	data["seat_assignments"] = seat_profiles
	var fw = FileAccess.open(LAST_USED_PATH, FileAccess.WRITE)
	if fw:
		fw.store_string(JSON.stringify(data))
		fw.close()

# The Settings screen's own Reset button. Resets the slot currently being edited
# and refreshes the form underneath.
func _on_reset_to_default_pressed():
	var key: String = _pending_settings.preset_id
	_show_reset_confirm_popup(key, settings_panel, func():
		# Re-resolve rather than re-deriving the defaults inline: with the saved
		# file now deleted, the resolver falls through to this slot's shipped
		# rules and handles preset_id and difficulty the same way every other
		# entry point does.
		_pending_settings = _resolve_settings_for_slot(key)
		_build_settings_content()
	)

# Reset-to-default confirmation, shared by the Settings screen's button and the
# Choose Rules "…" menu. `on_reset` runs after the files have been changed, so
# each caller can refresh whichever screen it's on.
func _show_reset_confirm_popup(key: String, parent: Control, on_reset: Callable):
	var shell := _make_modal_popup(parent, 340)
	var popup: Control = shell["root"]
	var vb: VBoxContainer = shell["body"]

	var title_lbl = Label.new()
	title_lbl.text = "Reset \"%s\"?" % _slot_display_name(key)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_lbl.add_theme_font_override("font", _font_nunito_heavy)
	_scaled_font(title_lbl, 16)
	vb.add_child(title_lbl)

	var body_lbl = Label.new()
	body_lbl.text = "This discards your saved changes to this ruleset and restores its original rules."
	body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.custom_minimum_size = Vector2(300, 0)
	body_lbl.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82))
	_scaled_font(body_lbl, 13)
	vb.add_child(body_lbl)

	# Rules and name are stored separately (slot_names.json vs. the rules file), so
	# resetting rules leaves a renamed slot renamed unless the player asks
	# otherwise. Opt-in, not opt-out: losing a name you chose is the more annoying
	# surprise of the two.
	# Centered in its own row rather than added straight to the VBox — a CheckBox
	# stretched to the full popup width puts its indicator hard against the left
	# edge, visually detached from the label it belongs to.
	var cb_row = HBoxContainer.new()
	cb_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(cb_row)

	var also_name_cb = CheckBox.new()
	also_name_cb.text = "Also reset the name"
	also_name_cb.button_pressed = false
	also_name_cb.add_theme_color_override("font_color", Color.WHITE)
	# The default theme's tick/box glyph is dark, which on this panel left the
	# indicator all but invisible — you could read the label but not tell whether
	# it was checked. Brighten it in every state so the box reads as a control.
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color",
			"icon_focus_color", "icon_hover_pressed_color"]:
		also_name_cb.add_theme_color_override(state, Color.WHITE)
	_scaled_font(also_name_cb, 14)
	cb_row.add_child(also_name_cb)

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vb.add_child(btn_row)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 40)
	cancel_btn.pressed.connect(func(): popup.queue_free())
	btn_row.add_child(cancel_btn)

	var reset_btn = Button.new()
	reset_btn.text = "Reset"
	reset_btn.custom_minimum_size = Vector2(100, 40)
	reset_btn.pressed.connect(func():
		popup.queue_free()
		var path := _slot_file_path(key)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if also_name_cb.button_pressed:
			_reset_slot_display_name(key)
		on_reset.call()
	)
	btn_row.add_child(reset_btn)

# Writes a slot's current settings back to its own file (located by
# _slot_file_path, which owns the built-in/custom split). Called by the Settings
# screen's Play button so tweaks to whichever ruleset you're playing stick around
# next time you pick that same slot, instead of resetting to its shipped rules.
# Writes rule content only — difficulty and the domino back are player/display
# state and live elsewhere; see the PERSISTENCE LAYOUT block at the top.
func _persist_preset_tweaks(s: GameSettings):
	if s.preset_id == "":
		# Reachable only via a bug, but it used to fail *silently*: Play would
		# look like it worked and simply never save. Every production path now
		# stamps preset_id (_resolve_settings_for_slot, _copy_settings, and Reset
		# to Default all do), yet Game's own constructor still falls back to a
		# bare GameSettings.new() when handed no settings (game.gd), so an
		# unstamped object remains constructible. Complain rather than no-op.
		push_error("_persist_preset_tweaks: settings have no preset_id; nothing saved. "
			+ "Whoever built these settings needs to stamp a slot key from SLOT_KEYS.")
		return
	# make_dir used to happen only in _save_custom_preset(), which created
	# custom_rulesets/ before anything wrote into it. That function is gone (five
	# fixed slots need no "save as new"), so the save path has to create its own
	# directory or the first save of the Custom slot on a fresh install no-ops.
	_ensure_slot_dir(s.preset_id)
	var f = FileAccess.open(_slot_file_path(s.preset_id), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(GameSettingsScript.to_dict(s), "\t"))
		f.close()

# ─── SLOT DISPLAY NAMES ───────────────────────────────────────────────────────
# Kept in their own tiny file rather than inside each ruleset's JSON so that the
# two are independently resettable: "Reset to Default" throws away rule content
# by deleting the override file, and a name stored in there would go with it.

func _load_slot_names() -> Dictionary:
	var f = FileAccess.open(SLOT_NAMES_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	return data if data is Dictionary else {}

func _save_slot_names(names: Dictionary) -> void:
	var f = FileAccess.open(SLOT_NAMES_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(names, "\t"))
		f.close()

func _slot_display_name(key: String) -> String:
	var names = _load_slot_names()
	var stored := str(names.get(key, ""))
	if not stored.is_empty():
		return stored
	return str(SLOT_DEFAULT_NAMES.get(key, key))

func _set_slot_display_name(key: String, new_name: String) -> void:
	var names = _load_slot_names()
	names[key] = new_name
	_save_slot_names(names)

func _reset_slot_display_name(key: String) -> void:
	var names = _load_slot_names()
	names.erase(key)
	_save_slot_names(names)

# ─── DOMINO BACK (display preference, not a rule) ──────────────────────────────

func _load_domino_back_pref() -> String:
	var f = FileAccess.open(DISPLAY_PREFS_PATH, FileAccess.READ)
	if f == null:
		return ""
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		return str(data.get("domino_back", ""))
	return ""

func _save_domino_back_pref(res_path: String) -> void:
	var data := {}
	var fr = FileAccess.open(DISPLAY_PREFS_PATH, FileAccess.READ)
	if fr:
		var existing = JSON.parse_string(fr.get_as_text())
		fr.close()
		if existing is Dictionary:
			data = existing
	data["domino_back"] = res_path
	var fw = FileAccess.open(DISPLAY_PREFS_PATH, FileAccess.WRITE)
	if fw:
		fw.store_string(JSON.stringify(data, "\t"))
		fw.close()

# Renames a slot's display name. Replaces the old custom-ruleset rename, which
# worked by moving files in user://custom_rulesets/ and patching last_used.json
# to follow the new filename — with fixed slots the key never changes, so this
# only touches the name mapping and no rules content moves anywhere.
# ─── SLOT "…" OPTIONS MENU (Choose Rules) ─────────────────────────────────────
# A small drop-down next to a slot row offering Rename and Reset. Pressing "…"
# again closes it; pressing a different slot's "…" moves it there. Unlike the
# rename/reset popups this one has no dimmed backdrop — a full-rect click-blocker
# would swallow the very press that's meant to toggle it shut.

func _close_slot_options_menu() -> void:
	if _slot_menu_popup != null and is_instance_valid(_slot_menu_popup):
		_slot_menu_popup.queue_free()
	_slot_menu_popup = null
	_slot_menu_key = ""

func _on_slot_options_pressed(key: String, anchor: Button) -> void:
	# Same button twice = collapse, with no choice made.
	if _slot_menu_key == key and _slot_menu_popup != null and is_instance_valid(_slot_menu_popup):
		_close_slot_options_menu()
		return
	_close_slot_options_menu()
	_slot_menu_key = key

	var menu = PanelContainer.new()
	# preset_panel is a PanelContainer, which would otherwise stretch this menu to
	# fill the whole panel. set_as_top_level() makes Container layout skip it AND
	# makes it ignore the parent's transform, so `position` below is plain global
	# coordinates.
	#
	# That second half is the important one. The first attempt wrapped the menu in
	# a full-rect Control and positioned it relative to that holder — but a
	# freshly-added child reports the panel's *outer* rect until layout runs, after
	# which PanelContainer insets it by its content margins (32, 40). The
	# arithmetic was right and the menu still landed 32px right and 40px low,
	# because the frame of reference moved underneath it a frame later. Anchoring
	# to a coordinate space nobody re-lays-out removes the whole class of problem.
	menu.set_as_top_level(true)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.16, 0.21, 0.98)
	style.border_color = Color(0.42, 0.42, 0.50)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	menu.add_theme_stylebox_override("panel", style)
	# Parented to preset_panel so it dies with that screen, but positioned in
	# global space thanks to set_as_top_level().
	preset_panel.add_child(menu)
	_slot_menu_popup = menu

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	menu.add_child(vb)

	var rename_btn = Button.new()
	rename_btn.text = "Rename"
	rename_btn.custom_minimum_size = Vector2(120, 36)
	_scaled_font(rename_btn, 14)
	rename_btn.pressed.connect(func():
		_close_slot_options_menu()
		_show_slot_rename_popup(key)
	)
	vb.add_child(rename_btn)

	# Reset is offered only where there's something to reset to. The Custom slot's
	# saved file IS its default — same gate the Settings screen's Reset button uses.
	if BUILTIN_PRESET_KEYS.has(key):
		var reset_btn = Button.new()
		reset_btn.text = "Reset"
		reset_btn.custom_minimum_size = Vector2(120, 36)
		_scaled_font(reset_btn, 14)
		reset_btn.pressed.connect(func():
			_close_slot_options_menu()
			_show_reset_confirm_popup(key, preset_panel, func():
				# Names and highlighting can both have changed — rebuild the list.
				_rebuild_preset_buttons()
			)
		)
		vb.add_child(reset_btn)

	# Sit under the "…" that opened it, right edges aligned, then pull back
	# on-screen if the slot sits near an edge.
	#
	# get_combined_minimum_size() rather than .size: the menu was created this
	# frame, so .size is still zero until layout runs, and waiting a frame to
	# position it would flash it in the corner first.
	var menu_size := menu.get_combined_minimum_size()
	menu.size = menu_size
	var anchor_rect := anchor.get_global_rect()
	var want := Vector2(
		anchor_rect.end.x - menu_size.x,
		anchor_rect.end.y + 2)
	var screen: Vector2 = get_viewport().get_visible_rect().size
	menu.position = Vector2(
		clampf(want.x, 4.0, maxf(4.0, screen.x - menu_size.x - 4.0)),
		clampf(want.y, 4.0, maxf(4.0, screen.y - menu_size.y - 4.0)))

# Shared chrome for the project's dimmed, centered modal popups (rename, reset).
# Returns {"root": the full-rect Control to free on dismiss, "body": the
# VBoxContainer to fill}. Parented to `parent` so a popup raised from Choose Rules
# lands over that panel and one raised from Settings lands over Settings.
#
# Deliberately NOT a ConfirmationDialog. AcceptDialog positions its own
# dialog_text label directly and does not re-flow for children added via
# add_child(), so the "Also reset the name" checkbox rendered on top of the
# message text — legible in neither. It also ignores this project's theme.
func _make_modal_popup(parent: Control, min_width: int) -> Dictionary:
	var popup = Control.new()
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(popup)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(dim)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)

	var box = PanelContainer.new()
	box.custom_minimum_size = Vector2(min_width, 0)
	var box_style = StyleBoxFlat.new()
	box_style.bg_color = Color(0.12, 0.12, 0.16, 0.97)
	box_style.corner_radius_top_left = 8
	box_style.corner_radius_top_right = 8
	box_style.corner_radius_bottom_left = 8
	box_style.corner_radius_bottom_right = 8
	box_style.content_margin_left = 20
	box_style.content_margin_right = 20
	box_style.content_margin_top = 18
	box_style.content_margin_bottom = 18
	box.add_theme_stylebox_override("panel", box_style)
	center.add_child(box)

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	box.add_child(vb)

	return {"root": popup, "body": vb}

func _show_slot_rename_popup(key: String):
	var old_name := _slot_display_name(key)
	var shell := _make_modal_popup(preset_panel, 320)
	var popup: Control = shell["root"]
	var vb: VBoxContainer = shell["body"]

	var prompt_lbl = Label.new()
	prompt_lbl.text = "Rename \"%s\":" % old_name
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.add_theme_color_override("font_color", Color.WHITE)
	prompt_lbl.add_theme_font_override("font", _font_nunito_heavy)
	_scaled_font(prompt_lbl, 16)
	vb.add_child(prompt_lbl)

	var line_edit = LineEdit.new()
	line_edit.text = old_name
	line_edit.custom_minimum_size = Vector2(280, 40)
	vb.add_child(line_edit)

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vb.add_child(btn_row)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 40)
	cancel_btn.pressed.connect(func(): popup.queue_free())
	btn_row.add_child(cancel_btn)

	var ok_btn = Button.new()
	ok_btn.text = "Rename"
	ok_btn.custom_minimum_size = Vector2(100, 40)
	btn_row.add_child(ok_btn)

	var do_rename = func():
		var new_name = line_edit.text.strip_edges()
		popup.queue_free()
		if new_name.is_empty() or new_name == old_name:
			return
		_set_slot_display_name(key, new_name)
		_rebuild_preset_buttons()

	ok_btn.pressed.connect(do_rename)
	line_edit.text_submitted.connect(func(_t): do_rename.call())
	line_edit.select_all()
	line_edit.grab_focus()

func _on_menu_difficulty_pressed():
	main_menu_panel.visible = false
	_rebuild_difficulty_buttons()
	difficulty_panel.visible = true

func _on_difficulty_chosen(key: String):
	# Persist the choice merged into last_used.json
	var data = {}
	var fr = FileAccess.open(LAST_USED_PATH, FileAccess.READ)
	if fr:
		var existing = JSON.parse_string(fr.get_as_text())
		fr.close()
		if existing is Dictionary:
			data = existing
	if not data is Dictionary:
		data = {}
	data["ai_difficulty"] = key
	var fw = FileAccess.open(LAST_USED_PATH, FileAccess.WRITE)
	if fw:
		fw.store_string(JSON.stringify(data))
		fw.close()
	# Apply immediately to a running game
	if game != null:
		game.settings.ai_difficulty = key
	_rebuild_difficulty_buttons()

func _rebuild_difficulty_buttons():
	_clear_children(_difficulty_btn_container)

	# Normalized on the way in — a saved "standard" from before the two-tier
	# change would otherwise highlight nothing and read as "no choice made".
	var current := "expert"
	if game != null:
		current = GameSettingsScript.normalize_difficulty(game.settings.ai_difficulty)
	else:
		var saved := _last_used_difficulty()
		if not saved.is_empty():
			current = saved

	var options = [
		["Casual", "Supportive partner, relaxed opponents", "casual"],
		["Expert", "Serious players, no mercy",             "expert"],
	]
	for opt in options:
		var btn = Button.new()
		btn.text = "%s\n%s" % [opt[0], opt[1]]
		btn.custom_minimum_size = Vector2(220, 72)
		if opt[2] == current:
			btn.modulate = Color(0.95, 0.80, 0.15)
		btn.pressed.connect(_on_difficulty_chosen.bind(opt[2]))
		_difficulty_btn_container.add_child(btn)

func _on_menu_profiles_pressed():
	main_menu_panel.visible = false
	_rebuild_profile_panel()
	profile_panel.visible = true

# The three non-human seats, in display order, paired with the same
# relational fallback name _seat_label() would show if nothing is
# assigned — used as the row label so you can always tell which seat
# you're assigning regardless of what's currently on it.
func _assignable_seats() -> Array:
	return [
		[(human_seat + 2) % 4, "Partner"],
		[(human_seat + 1) % 4, "Right Opponent"],
		[(human_seat + 3) % 4, "Left Opponent"],
	]

func _rebuild_profile_panel():
	_clear_children(_profile_content_vbox)

	var new_profile_btn = Button.new()
	new_profile_btn.text = "+ New Profile"
	new_profile_btn.custom_minimum_size = Vector2(220, 44)
	new_profile_btn.pressed.connect(_show_new_profile_popup)
	_profile_content_vbox.add_child(new_profile_btn)

	_profile_content_vbox.add_child(HSeparator.new())

	var ids = PlayerProfileScript.list_all()
	var profiles_by_id := {}
	for pid in ids:
		var profile = PlayerProfileScript.load(pid)
		if profile != null:
			profiles_by_id[pid] = profile

	for seat_info in _assignable_seats():
		var seat_id: int = seat_info[0]
		var seat_name: String = seat_info[1]

		var row = VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_profile_content_vbox.add_child(row)

		var lbl = Label.new()
		lbl.text = seat_name
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color.WHITE)
		_scaled_font(lbl, 14)
		row.add_child(lbl)

		var opt = OptionButton.new()
		opt.custom_minimum_size = Vector2(240, 40)
		var option_ids: Array[String] = [""]
		opt.add_item("None")
		var current_id: String = str(seat_profiles.get(seat_id, ""))
		var sel_idx = 0
		for pid in ids:
			option_ids.append(pid)
			var display = profiles_by_id[pid].display_name if profiles_by_id.has(pid) else pid
			opt.add_item(display)
			if pid == current_id:
				sel_idx = option_ids.size() - 1
		opt.select(sel_idx)
		opt.item_selected.connect(func(idx):
			var chosen_id = option_ids[idx]
			if chosen_id == "":
				seat_profiles.erase(seat_id)
			else:
				seat_profiles[seat_id] = chosen_id
			_save_seat_assignments()
		)
		row.add_child(opt)

func _show_new_profile_popup():
	var popup = Control.new()
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	profile_panel.add_child(popup)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(dim)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)

	var box = PanelContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	var box_style = StyleBoxFlat.new()
	box_style.bg_color = Color(0.12, 0.12, 0.16, 0.97)
	box_style.corner_radius_top_left = 8
	box_style.corner_radius_top_right = 8
	box_style.corner_radius_bottom_left = 8
	box_style.corner_radius_bottom_right = 8
	box.add_theme_stylebox_override("panel", box_style)
	center.add_child(box)

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	box.add_child(vb)

	var prompt_lbl = Label.new()
	prompt_lbl.text = "Name the profile:"
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.add_theme_color_override("font_color", Color.WHITE)
	prompt_lbl.add_theme_font_override("font", _font_nunito_heavy)
	_scaled_font(prompt_lbl, 16)
	vb.add_child(prompt_lbl)

	var line_edit = LineEdit.new()
	line_edit.placeholder_text = "e.g. Pop"
	line_edit.custom_minimum_size = Vector2(280, 40)
	vb.add_child(line_edit)

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vb.add_child(btn_row)

	var cancel_p = Button.new()
	cancel_p.text = "Cancel"
	cancel_p.custom_minimum_size = Vector2(100, 40)
	cancel_p.pressed.connect(func(): popup.queue_free())
	btn_row.add_child(cancel_p)

	var ok_btn = Button.new()
	ok_btn.text = "Create"
	ok_btn.custom_minimum_size = Vector2(100, 40)
	btn_row.add_child(ok_btn)

	var do_create = func():
		var pname = line_edit.text.strip_edges()
		if pname.is_empty():
			return
		popup.queue_free()
		PlayerProfileScript.create(pname)
		_rebuild_profile_panel()

	ok_btn.pressed.connect(do_create)
	line_edit.text_submitted.connect(func(_t): do_create.call())
	line_edit.grab_focus()

func _input(_event: InputEvent):
	pass  # tap-anywhere-to-continue replaced by explicit Next Hand button

# ─── REPLAY ───────────────────────────────────────────────────────────────────

func _on_hand_continue():
	game.advance_shaker()
	_start_hand()

func _on_new_game_pressed():
	_restart_game_with_settings(game.settings)

func _show_replay():
	if game.hand_history.is_empty():
		return
	_replay_trick_index = 0
	var vp = get_viewport().get_visible_rect().size
	_replay_inner_panel.custom_minimum_size = vp * 0.96
	replay_panel.visible = true
	_render_replay_trick()

func _render_replay_trick():
	if _replay_trick_index >= game.hand_history.size():
		_exit_replay()
		return

	var trick_record = game.hand_history[_replay_trick_index]

	_replay_trick_label.text = "Replay — Trick %d of %d" % [
		_replay_trick_index + 1,
		game.hand_history.size()
	]
	_replay_back_btn.disabled = (_replay_trick_index == 0)

	# Render each player's hand at the start of this trick (face-up, small)
	for pid in range(4):
		var container = _replay_hand_containers[pid]
		for child in container.get_children():
			child.queue_free()
		var hand_state = trick_record["hand_states"][pid]
		for d in hand_state:
			var tile = DominoTile.new()
			tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(tile)
			tile.setup(d, true, trick_record["trump"])
			tile.custom_minimum_size = TILE_REPLAY_HAND

	# Render each player's played domino and reasoning bubble
	for play in trick_record["plays"]:
		var pid = play["player"]

		var played_container = _replay_played_containers[pid]
		for child in played_container.get_children():
			child.queue_free()
		var played_tile = DominoTile.new()
		played_tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		played_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		played_container.add_child(played_tile)
		played_tile.setup(play["domino"], true, trick_record["trump"])
		played_tile.custom_minimum_size = TILE_REPLAY_PLAYED

		var bubble = _replay_bubble_labels[pid]
		bubble.text = play["reason"] if play["reason"] != "" else "—"
		bubble.visible = true

	# Clear slots for players who didn't play this trick (e.g. Nello partner)
	for pid in range(4):
		var played = trick_record["plays"].any(func(p): return p["player"] == pid)
		if not played:
			_replay_bubble_labels[pid].visible = false
			for child in _replay_played_containers[pid].get_children():
				child.queue_free()

	# Annotate the winner's bubble with trick value context
	var winner_id = trick_record["winner_id"]
	if _replay_bubble_labels[winner_id] != null:
		var trick_pts := 1  # base 1 point for the trick itself
		var has_counter := false
		for play in trick_record["plays"]:
			var pip: int = play["domino"].pip_sum()
			if pip == 5 or pip == 10:
				trick_pts += pip
				has_counter = true
		var value_str: String
		if trick_pts >= 10:
			value_str = "Won trick — %d pts" % trick_pts
		elif has_counter:
			value_str = "Won trick — %d pts" % trick_pts
		else:
			value_str = "Won trick"
		_replay_bubble_labels[winner_id].text += "\n✓ " + value_str

func _replay_next_trick():
	_reset_flag_panel()
	_replay_trick_index += 1
	if _replay_trick_index >= game.hand_history.size():
		_exit_replay()
	else:
		_render_replay_trick()

func _replay_prev_trick():
	if _replay_trick_index <= 0:
		return
	_reset_flag_panel()
	_replay_trick_index -= 1
	_render_replay_trick()

func _exit_replay():
	_reset_flag_panel()
	replay_panel.visible = false

func _toggle_flag_panel():
	_flag_panel.visible = not _flag_panel.visible

func _submit_flag():
	var categories: Array = []
	if _flag_toggle_bidding.button_pressed:
		categories.append("bidding")
	if _flag_toggle_gameplay.button_pressed:
		categories.append("gameplay")
	if _flag_toggle_explanation.button_pressed:
		categories.append("explanation")
	var note = _flag_note_edit.text

	game.flag_hand(_replay_trick_index, categories, note)

	_reset_flag_panel()

func _reset_flag_panel():
	_flag_toggle_bidding.button_pressed = false
	_flag_toggle_gameplay.button_pressed = false
	_flag_toggle_explanation.button_pressed = false
	_flag_note_edit.text = ""
	_flag_panel.visible = false
