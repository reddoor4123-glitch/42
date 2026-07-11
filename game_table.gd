extends Node

const BidScript       = preload("res://bid.gd")
const GameSettingsScript = preload("res://game_settings.gd")
const DominoTileScript = preload("res://domino_tile.gd")
const AIPlayer = preload("res://ai_player.gd")
const MarksDisplayScript = preload("res://marks_display.gd")
const TrickPileScript = preload("res://trick_pile.gd")

var game: Game

# UI node references (assigned in _ready)
var player_hand_container: HBoxContainer
var play_area_container: HBoxContainer
var opponent_top_container: HBoxContainer
var opponent_left_container: VBoxContainer
var opponent_right_container: VBoxContainer
var info_label: Label
var bid_panel: PanelContainer
var bid_buttons: HBoxContainer
var _pts_picker: DrumPicker = null
var _marks_picker: DrumPicker = null
var _bid_panel_expanded: bool = false
var _selected_contract_type: int = BidScript.Type.MARKS
var _contract_marks_picker: DrumPicker = null
var _bid_bubbles: Dictionary = {}  # player_id -> Label
var _bubble_overlay: Control = null
var _us_marks: MarksDisplay = null
var _them_marks: MarksDisplay = null
var _us_tricks: TrickPile = null
var _them_tricks: TrickPile = null
var trump_panel: PanelContainer
var trump_buttons: HBoxContainer
var _special_trump_sep: HSeparator = null
var _doubles_trump_btn: Button = null
var _doubles_trump_reversed_btn: Button = null
var _follow_me_btn: Button = null
var nello_panel: PanelContainer
var _nello_reversed_btn: Button = null
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
var _preset_status_label: Label = null
var main_menu_panel: PanelContainer = null
var difficulty_panel: PanelContainer = null
var _difficulty_btn_container: VBoxContainer = null
var _game_top_row: HBoxContainer = null
var _game_mid_row: HBoxContainer = null

# Debug flag — set true to skip AI thinking pauses for faster testing.
# Wire this to a proper settings toggle later once the settings UI exists.
const DEBUG_FAST_MODE: bool = false

# Game state
var selected_tile: DominoTile = null
var human_seat: int = 0
var waiting_for_human: bool = false
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

# Viewport-proportional tile sizes — computed once in _build_ui()
var TILE_FULL: Vector2
var TILE_SMALL: Vector2
var TILE_REPLAY_HAND: Vector2
var TILE_REPLAY_PLAYED: Vector2

func _ready():
	_build_ui()
	_start_game()

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

func _build_ui():
	var vp_w: float = get_viewport().get_visible_rect().size.x
	var tile_w: float = min(64.0, floor(vp_w / 9.0))
	TILE_FULL         = Vector2(tile_w,        tile_w * 2.0)
	TILE_SMALL        = Vector2(tile_w * 0.85, tile_w * 2.0 * 0.85)
	TILE_REPLAY_HAND   = Vector2(tile_w * 0.65, tile_w * 2.0 * 0.65)
	TILE_REPLAY_PLAYED = Vector2(tile_w * 0.85, tile_w * 2.0 * 0.85)

	# Root Control that fills the window
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.set_offsets_preset(Control.PRESET_FULL_RECT)
	root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(root)

	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.13, 0.30, 0.18)  # Felt green
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	# Main vertical layout
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	root.add_child(vbox)

	# --- Top row: US panel | partner hand | THEM panel ---
	_game_top_row = HBoxContainer.new()
	var top_row = _game_top_row
	top_row.add_theme_constant_override("separation", 6)
	vbox.add_child(top_row)

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

	# Partner hand (center)
	opponent_top_container = HBoxContainer.new()
	opponent_top_container.alignment = BoxContainer.ALIGNMENT_CENTER
	opponent_top_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opponent_top_container.custom_minimum_size = Vector2(0, 80)
	top_row.add_child(opponent_top_container)

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
				dot.add_theme_font_size_override("font_size", 8)
				dot.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88, 0.55))
				half_row.add_child(dot)

	var menu_title = Label.new()
	menu_title.text = "42"
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_title.add_theme_font_size_override("font_size", 48)
	menu_title.add_theme_color_override("font_color", Color.WHITE)
	menu_vbox.add_child(menu_title)

	var menu_subtitle = Label.new()
	menu_subtitle.text = "The National Game of Texas"
	menu_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_subtitle.add_theme_font_size_override("font_size", 14)
	menu_subtitle.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	menu_vbox.add_child(menu_subtitle)

	var menu_spacer = Control.new()
	menu_spacer.custom_minimum_size = Vector2(0, 24)
	menu_vbox.add_child(menu_spacer)

	var play_btn = Button.new()
	play_btn.text = "Play"
	play_btn.custom_minimum_size = Vector2(220, 64)
	play_btn.pressed.connect(_on_menu_play_pressed)
	menu_vbox.add_child(play_btn)

	var rules_btn = Button.new()
	rules_btn.text = "Choose Rules"
	rules_btn.custom_minimum_size = Vector2(220, 64)
	rules_btn.pressed.connect(_on_menu_rules_pressed)
	menu_vbox.add_child(rules_btn)

	var diff_menu_btn = Button.new()
	diff_menu_btn.text = "Difficulty"
	diff_menu_btn.custom_minimum_size = Vector2(220, 64)
	diff_menu_btn.pressed.connect(_on_menu_difficulty_pressed)
	menu_vbox.add_child(diff_menu_btn)

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
	preset_title.add_theme_font_size_override("font_size", 28)
	preset_title.add_theme_color_override("font_color", Color.WHITE)
	preset_vbox.add_child(preset_title)

	var preset_subtitle = Label.new()
	preset_subtitle.text = "You can change this anytime from the menu"
	preset_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preset_subtitle.add_theme_font_size_override("font_size", 14)
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
	diff_title.add_theme_font_size_override("font_size", 22)
	diff_title.add_theme_color_override("font_color", Color.WHITE)
	diff_vbox.add_child(diff_title)

	var diff_subtitle = Label.new()
	diff_subtitle.text = "You can change this anytime from settings"
	diff_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	diff_subtitle.add_theme_font_size_override("font_size", 13)
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

	# --- Middle row: left opponent | play area | right opponent ---
	_game_mid_row = HBoxContainer.new()
	var hbox_mid = _game_mid_row
	hbox_mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox_mid.add_theme_constant_override("separation", 4)
	hbox_mid.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox_mid)

	opponent_left_container = VBoxContainer.new()
	opponent_left_container.alignment = BoxContainer.ALIGNMENT_CENTER
	opponent_left_container.custom_minimum_size = Vector2(60, 0)
	opponent_left_container.add_theme_constant_override("separation", -55)
	hbox_mid.add_child(opponent_left_container)

	# Play area (center)
	var play_area_panel = PanelContainer.new()
	play_area_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_mid.add_child(play_area_panel)

	var play_vbox = VBoxContainer.new()
	play_area_panel.add_child(play_vbox)

	info_label = Label.new()
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_color_override("font_color", Color.WHITE)
	play_vbox.add_child(info_label)

	play_area_container = HBoxContainer.new()
	play_area_container.alignment = BoxContainer.ALIGNMENT_CENTER
	play_area_container.add_theme_constant_override("separation", 8)
	play_area_container.custom_minimum_size = Vector2(0, 100)
	play_vbox.add_child(play_area_container)

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
	opponent_right_container.custom_minimum_size = Vector2(60, 0)
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
	trump_label.add_theme_font_size_override("font_size", 14)
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
	nello_label.add_theme_font_size_override("font_size", 14)
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

	# --- Human player hand ---
	player_hand_container = HBoxContainer.new()
	player_hand_container.alignment = BoxContainer.ALIGNMENT_CENTER
	player_hand_container.custom_minimum_size = Vector2(0, 100)

	# --- Small-end opening lead toggle — sits directly above the player's own
	# hand (not in the shared trick-display area) so it reads as the human's
	# control, not something ambiguous near the AI seats.
	var se_row = HBoxContainer.new()
	se_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(se_row)

	_small_end_toggle_btn = Button.new()
	_small_end_toggle_btn.text = "Open with Small End"
	_small_end_toggle_btn.toggle_mode = true
	_small_end_toggle_btn.custom_minimum_size = Vector2(160, 40)
	_small_end_toggle_btn.visible = false
	_small_end_toggle_btn.toggled.connect(_on_small_end_toggle_pressed)
	se_row.add_child(_small_end_toggle_btn)

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
	_replay_trick_label.add_theme_font_size_override("font_size", 16)
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
	flag_hint.add_theme_font_size_override("font_size", 13)
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
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var hand_hbox = HBoxContainer.new()
	hand_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_hbox.add_theme_constant_override("separation", 2)

	var played_hbox = HBoxContainer.new()
	played_hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var bubble_lbl = Label.new()
	bubble_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble_lbl.add_theme_font_size_override("font_size", 11)
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

func _on_preset_chosen(key: String):
	preset_panel.visible = false
	_save_last_used(key)
	var s: GameSettings
	if key.begins_with("custom:"):
		var cname = key.substr(7)
		var cf = FileAccess.open("user://custom_rulesets/%s.json" % cname, FileAccess.READ)
		if cf:
			var data = JSON.parse_string(cf.get_as_text())
			cf.close()
			s = GameSettingsScript.from_dict(data)
		else:
			s = GameSettingsScript.standard_42()
	else:
		match key:
			"teel":       s = GameSettingsScript.teel_rules()
			"standard":   s = GameSettingsScript.standard_42()
			"tournament": s = GameSettingsScript.tournament_rules()
			"lechner":    s = GameSettingsScript.lechner_hall()
			_:            s = GameSettingsScript.standard_42()
	game = Game.new(s)
	game.setup_players(human_seat)
	_start_hand()

func _start_hand():
	_armed_domino = null
	_small_end_active = false
	if _small_end_toggle_btn:
		_small_end_toggle_btn.visible = false
		_small_end_toggle_btn.button_pressed = false
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
	_start_bidding()

func _start_bidding():
	_set_info("Marks: You %d | Them %d" % [game.team_marks[0], game.team_marks[1]])
	game.current_bid = null
	human_is_forced = false
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
		var ai_bid = AIPlayer.decide_bid(player.hand, pid, game.current_bid, game.settings, is_forced, game.settings.ai_difficulty, game.bid_decisions)
		if ai_bid.type != BidScript.Type.PASS:
			game.current_bid = ai_bid
		_show_bid_bubble(pid, "%s\n%s" % [_seat_label(pid), ai_bid.debug_string()])
		_set_status("%s: %s" % [_seat_label(pid), ai_bid.debug_string()])
		await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 0.7).timeout

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
	var eligible: Array = game.eligible_contracts(game.players[human_seat].hand)
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
		pts_lbl.add_theme_font_size_override("font_size", 13)
		pts_col.add_child(pts_lbl)

		_pts_picker = DrumPicker.new()
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
	var marks_floor = _contract_floor(_selected_contract_type, auction_floor) if _bid_panel_expanded else auction_floor
	if marks_floor <= 7:
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
		marks_lbl.add_theme_font_size_override("font_size", 13)
		marks_col.add_child(marks_lbl)

		_marks_picker = DrumPicker.new()
		_contract_marks_picker = _marks_picker
		var mark_vals: Array[int] = []
		for v in range(marks_floor, 8):
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
		var ai_bid = AIPlayer.decide_bid(player.hand, pid, game.current_bid, game.settings, is_forced, game.settings.ai_difficulty, game.bid_decisions)
		if ai_bid.type != BidScript.Type.PASS:
			game.current_bid = ai_bid
		_show_bid_bubble(pid, "%s\n%s" % [_seat_label(pid), ai_bid.debug_string()])
		_set_status("%s: %s" % [_seat_label(pid), ai_bid.debug_string()])
		await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 0.7).timeout

func _finish_bidding(_unused: Array):
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
			_set_info("Nello | Marks: You %d | Them %d" % [game.team_marks[0], game.team_marks[1]])
			_refresh_all_hands()
			await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 0.8).timeout
			_begin_play(winning.player_id)

	elif winning.type == BidScript.Type.SEVENS:
		# Sevens needs no trump selection from anyone
		game.apply_bid_result(-1)
		_set_info("Sevens | Marks: You %d | Them %d" % [game.team_marks[0], game.team_marks[1]])
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
			_set_info("Trump: %ds | Marks: You %d | Them %d" % [best_suit, game.team_marks[0], game.team_marks[1]])
			_refresh_all_hands()
			_set_status("%s called %s" % [_seat_label(partner_id), suit_names[best_suit]])
			await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 0.8).timeout
			_begin_play(partner_id)

	else:
		# Covers POINTS and MARKS (bid winner picks trump and leads).
		# FOLLOW_ME and LOW_NO also fall here for now — intentional pending their own panels.
		if not (winning.type == BidScript.Type.POINTS or winning.type == BidScript.Type.MARKS
				or winning.type == BidScript.Type.FOLLOW_ME or winning.type == BidScript.Type.LOW_NO):
			push_warning("_finish_bidding: unhandled bid type %d fell through to trump panel" % winning.type)
		if winning.player_id == human_seat:
			_show_trump_panel()
		else:
			var ai_eval = AIPlayer.best_trump(game.players[winning.player_id].hand)
			var best_suit = ai_eval["trump"]
			game.apply_bid_result(best_suit)
			_set_info("Trump: %ds | Marks: You %d | Them %d" % [best_suit, game.team_marks[0], game.team_marks[1]])
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
	_set_info("Trump: %ds | Marks: You %d | Them %d" % [suit, game.team_marks[0], game.team_marks[1]])
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
	_set_info("Nello | Marks: You %d | Them %d" % [game.team_marks[0], game.team_marks[1]])
	_refresh_all_hands()
	_begin_play()

func _on_small_end_toggle_pressed(pressed: bool):
	_small_end_active = pressed
	_update_small_end_button_style()

func _update_small_end_button_style():
	_small_end_toggle_btn.modulate = Color(0.95, 0.80, 0.15) if _small_end_active else Color(1, 1, 1)

func _update_small_end_button_visibility():
	var is_opening_lead = game.tricks_played == 0 and game.current_trick.plays.size() == 0
	var eligible = game.settings.allow_small_end_opening_lead and is_opening_lead
	_small_end_toggle_btn.visible = eligible
	if not eligible:
		_small_end_active = false
		_small_end_toggle_btn.button_pressed = false
		_update_small_end_button_style()

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
	_refresh_hand(player)

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

	# Check if the bid is already mathematically lost
	if _is_bid_mathematically_set(winner_id):
		_resolve_hand()
		return

	if game.tricks_played < 7:
		_play_trick(winner_id)
	else:
		_resolve_hand()

# Returns true if the bid is already mathematically unwinnable and play can stop early.
# Nello: bidder catching any trick fails immediately (partner winning is fine).
# Marks/Sevens: any trick won by the non-bidding team ends it.
func _is_bid_mathematically_set(winner_id: int) -> bool:
	if game.current_bid == null:
		return false
	if game.variant == BidScript.Type.NELLO:
		return winner_id == game.current_bid.player_id
	var needs_all_tricks = game.current_bid.type == BidScript.Type.MARKS or game.current_bid.type == BidScript.Type.SEVENS
	if not needs_all_tricks:
		return false
	var bid_team = game.current_bid.player_id % 2
	return (winner_id % 2) != bid_team

func _resolve_hand():
	var result = game.resolve_hand()
	var winner_team = result.get("winner", 0)
	var team_str = "Your team" if winner_team == 0 else "Their team"
	var marks = result.get("team_marks", [0,0])
	_set_status("Hand over! %s wins — %s" % [team_str, result.get("reason", "")])

	_us_marks.set_marks(marks[0])
	_them_marks.set_marks(marks[1])
	_set_info("Marks: You %d | Them %d" % [marks[0], marks[1]])

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
			_continue_btn.queue_free()
			_continue_btn = null
		_new_game_btn = Button.new()
		_new_game_btn.text = "New Game"
		_new_game_btn.custom_minimum_size = Vector2(160, 48)
		_new_game_btn.modulate = Color(0.95, 0.80, 0.15)
		_new_game_btn.pressed.connect(_on_new_game_pressed)
		btn_vbox.add_child(_new_game_btn)
		return

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

func _add_to_play_area(player_id: int, domino: Domino):
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	play_area_container.add_child(vb)

	var tile = DominoTile.new()
	tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(tile)
	tile.setup(domino, true, game.trump)
	tile.custom_minimum_size = TILE_FULL

	var lbl = Label.new()
	lbl.text = _seat_label(player_id)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_font_size_override("font_size", 13)
	vb.add_child(lbl)

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

func _set_status(text: String):
	status_label.text = text
	print(text)

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
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10, 0.90)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
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
	elif pid == (human_seat + 2) % 4:
		return "Partner"
	elif pid == (human_seat + 1) % 4:
		return "Right Opponent"
	else:
		return "Left Opponent"



# ─── SETTINGS OVERLAY ────────────────────────────────────────────────────────

func _show_settings_panel(from_create: bool = false):
	_pending_settings = GameSettingsScript.standard_42() if game == null else _copy_settings(game.settings)
	var vp = get_viewport().get_visible_rect().size
	_settings_panel_inner.custom_minimum_size = vp * 0.92
	_build_settings_content(from_create)
	settings_panel.visible = true

func _build_settings_content(from_create: bool = false):
	for c in _settings_content_vbox.get_children():
		c.queue_free()

	var title = Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color.WHITE)
	_settings_content_vbox.add_child(title)

	_add_option_row(_settings_content_vbox, "AI Difficulty", [
		["Beginner", "beginner"],
		["Standard", "standard"],
		["Expert",   "expert"],
	], _pending_settings.ai_difficulty, func(v): _pending_settings.ai_difficulty = v)
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
	_add_option_row(nello_sub, "Doubles Mode", [
		["High (standard)", "high"], ["Low", "low"], ["Own Suit", "own_suit"]
	], _pending_settings.nello_doubles_mode, func(v): _pending_settings.nello_doubles_mode = v)
	_add_checkbox_row(nello_sub, "Allow Own Suit (Reversed)", _pending_settings.nello_doubles_reversed,
		func(v): _pending_settings.nello_doubles_reversed = v)

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
	_add_checkbox_row(sevens_sub, "Require 7-pip Domino in Hand", _pending_settings.sevens_require_seven_in_hand,
		func(v): _pending_settings.sevens_require_seven_in_hand = v)

	_add_checkbox_row(sc_body, "Allow Follow Me / No Trump", _pending_settings.allow_follow_me,
		func(v): _pending_settings.allow_follow_me = v)

	# ── TRUMP & DOUBLES ──
	var trump_body = _make_section(_settings_content_vbox, "TRUMP & DOUBLES")
	_add_checkbox_row(trump_body, "Doubles Are a Trump Suit", _pending_settings.doubles_are_trump,
		func(v): _pending_settings.doubles_are_trump = v)
	_add_checkbox_row(trump_body, "Force Trump on Opening Lead", _pending_settings.force_trump_opening_lead,
		func(v): _pending_settings.force_trump_opening_lead = v)
	_add_checkbox_row(trump_body, "Allow Small-End Opening Lead", _pending_settings.allow_small_end_opening_lead,
		func(v): _pending_settings.allow_small_end_opening_lead = v)

	# ── Save as preset ──
	var save_sep = HSeparator.new()
	_settings_content_vbox.add_child(save_sep)

	var save_btn = Button.new()
	save_btn.text = "Save as New Ruleset..."
	save_btn.custom_minimum_size = Vector2(220, 44)
	save_btn.pressed.connect(_show_save_preset_popup)
	_settings_content_vbox.add_child(save_btn)

	# ── Bottom buttons ──
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

	if from_create:
		# Arrived from "Create New Ruleset" — intent is to save, not start a game.
		var back_btn = Button.new()
		back_btn.text = "← Back"
		back_btn.custom_minimum_size = Vector2(120, 44)
		back_btn.pressed.connect(func():
			settings_panel.visible = false
			preset_panel.visible = true
		)
		btn_row.add_child(back_btn)

		var save_btn_bottom = Button.new()
		save_btn_bottom.text = "Save Ruleset"
		save_btn_bottom.custom_minimum_size = Vector2(180, 44)
		save_btn_bottom.pressed.connect(_show_save_preset_popup)
		btn_row.add_child(save_btn_bottom)
	else:
		# Arrived from gear icon mid-game — intent is to modify and restart.
		var cancel_btn = Button.new()
		cancel_btn.text = "Cancel"
		cancel_btn.custom_minimum_size = Vector2(120, 44)
		cancel_btn.pressed.connect(func(): settings_panel.visible = false)
		btn_row.add_child(cancel_btn)

		var confirm_btn = Button.new()
		confirm_btn.text = "Confirm & Restart"
		confirm_btn.custom_minimum_size = Vector2(180, 44)
		confirm_btn.pressed.connect(func(): _restart_game_with_settings(_pending_settings))
		btn_row.add_child(confirm_btn)

func _make_section(parent: VBoxContainer, title: String) -> VBoxContainer:
	var header = Button.new()
	header.text = "▶  " + title
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	cb.add_theme_font_size_override("font_size", 15)
	cb.toggled.connect(setter)
	parent.add_child(cb)
	return cb

func _add_sub_container(parent: VBoxContainer, toggle_cb: CheckBox) -> VBoxContainer:
	var sub = VBoxContainer.new()
	sub.add_theme_constant_override("separation", 4)
	sub.visible = toggle_cb.button_pressed
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.visible = sub.visible
	parent.add_child(margin)
	margin.add_child(sub)
	toggle_cb.toggled.connect(func(v): margin.visible = v)
	return sub

func _add_option_row(parent: VBoxContainer, label: String, options: Array, current: String, setter: Callable):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lbl = Label.new()
	lbl.text = label + ":"
	lbl.custom_minimum_size = Vector2(170, 0)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_font_size_override("font_size", 15)
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
	lbl.add_theme_font_size_override("font_size", 15)
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
	dst.allow_low_no = src.allow_low_no
	dst.allow_nello = src.allow_nello
	dst.allow_nello_exchange = src.allow_nello_exchange
	dst.nello_exchange_bidder_gives = src.nello_exchange_bidder_gives
	dst.nello_exchange_partner_gives = src.nello_exchange_partner_gives
	dst.nello_only_on_forced_bid = src.nello_only_on_forced_bid
	dst.nello_minimum_bid = src.nello_minimum_bid
	dst.nello_doubles_mode = src.nello_doubles_mode
	dst.nello_doubles_reversed = src.nello_doubles_reversed
	dst.nello_bid_value = src.nello_bid_value
	dst.nello_count_as_marks = src.nello_count_as_marks
	dst.nello_failure_penalty = src.nello_failure_penalty
	dst.nello_failure_fixed_points = src.nello_failure_fixed_points
	dst.allow_follow_me = src.allow_follow_me
	dst.follow_me_doubles_mode = src.follow_me_doubles_mode
	dst.follow_me_allow_as_points_bid = src.follow_me_allow_as_points_bid
	dst.allow_sevens = src.allow_sevens
	dst.sevens_require_minimum_bid = src.sevens_require_minimum_bid
	dst.sevens_minimum_bid = src.sevens_minimum_bid
	dst.sevens_require_seven_in_hand = src.sevens_require_seven_in_hand
	dst.doubles_are_trump = src.doubles_are_trump
	dst.doubles_trump_reversed = src.doubles_trump_reversed
	dst.default_trump_if_undeclared = src.default_trump_if_undeclared
	dst.allow_small_end_opening_lead = src.allow_small_end_opening_lead
	dst.force_trump_opening_lead = src.force_trump_opening_lead
	dst.marks_to_win = src.marks_to_win
	dst.shuffle_style = src.shuffle_style
	dst.allow_table_talk = src.allow_table_talk
	dst.ai_difficulty = src.ai_difficulty
	return dst

func _restart_game_with_settings(new_settings: GameSettings):
	settings_panel.visible = false
	preset_panel.visible = false
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

func _on_menu_play_pressed():
	var f = FileAccess.open("user://last_used.json", FileAccess.READ)
	if f:
		var data = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Dictionary and data.has("last_preset"):
			var key = str(data["last_preset"])
			var valid = true
			if key.begins_with("custom:"):
				valid = FileAccess.file_exists("user://custom_rulesets/%s.json" % key.substr(7))
			if valid:
				main_menu_panel.visible = false
				_on_preset_chosen(key)
				# Apply saved difficulty on top of preset default
				if game != null and data.has("ai_difficulty"):
					game.settings.ai_difficulty = str(data["ai_difficulty"])
				return
	_on_menu_rules_pressed()

func _on_menu_rules_pressed():
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

func _rebuild_preset_buttons():
	for c in _preset_btn_container.get_children():
		c.queue_free()

	var builtins = [
		["Teel Rules",   "Our family's house rules",       "teel"],
		["Standard 42",  "The classic game",               "standard"],
		["Tournament",   "Strict competitive rules",       "tournament"],
		["Lechner Hall", "Aggie 42 — A&M dorm rules",      "lechner"],
	]
	for p in builtins:
		var btn = Button.new()
		btn.text = "%s\n%s" % [p[0], p[1]]
		btn.custom_minimum_size = Vector2(220, 60)
		btn.pressed.connect(_on_preset_chosen.bind(p[2]))
		_preset_btn_container.add_child(btn)

	# Load custom presets from disk
	var dir = DirAccess.open("user://custom_rulesets")
	if dir:
		var files: Array[String] = []
		dir.list_dir_begin()
		var fname = dir.get_next()
		while fname != "":
			if fname.ends_with(".json"):
				files.append(fname)
			fname = dir.get_next()
		dir.list_dir_end()
		files.sort()
		if files.size() > 0:
			_preset_btn_container.add_child(HSeparator.new())
		for file_name in files:
			var cname = file_name.left(file_name.length() - 5)
			var row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			var btn = Button.new()
			btn.text = "★ %s\nCustom ruleset" % cname
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.custom_minimum_size = Vector2(0, 60)
			btn.pressed.connect(_on_preset_chosen.bind("custom:" + cname))
			row.add_child(btn)
			var opts_btn = Button.new()
			opts_btn.text = "…"
			opts_btn.custom_minimum_size = Vector2(36, 60)
			opts_btn.pressed.connect(_show_custom_preset_options.bind(cname))
			row.add_child(opts_btn)
			_preset_btn_container.add_child(row)

	_preset_btn_container.add_child(HSeparator.new())
	var create_btn = Button.new()
	create_btn.text = "+ Create New Ruleset"
	create_btn.custom_minimum_size = Vector2(220, 44)
	create_btn.pressed.connect(func():
		preset_panel.visible = false
		_show_settings_panel(true)
	)
	_preset_btn_container.add_child(create_btn)

func _save_last_used(key: String):
	var data = {}
	var fr = FileAccess.open("user://last_used.json", FileAccess.READ)
	if fr:
		var existing = JSON.parse_string(fr.get_as_text())
		fr.close()
		if existing is Dictionary:
			data = existing
	data["last_preset"] = key
	var fw = FileAccess.open("user://last_used.json", FileAccess.WRITE)
	if fw:
		fw.store_string(JSON.stringify(data))
		fw.close()

func _show_save_preset_popup():
	var popup = Control.new()
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.add_child(popup)

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
	prompt_lbl.text = "Name your ruleset:"
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.add_theme_color_override("font_color", Color.WHITE)
	prompt_lbl.add_theme_font_size_override("font_size", 16)
	vb.add_child(prompt_lbl)

	var line_edit = LineEdit.new()
	line_edit.placeholder_text = "e.g. My Custom Rules"
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
	ok_btn.text = "Save"
	ok_btn.custom_minimum_size = Vector2(100, 40)
	btn_row.add_child(ok_btn)

	var do_save = func():
		var cname = line_edit.text.strip_edges()
		if cname.is_empty():
			return
		popup.queue_free()
		_save_custom_preset(cname)

	ok_btn.pressed.connect(do_save)
	line_edit.text_submitted.connect(func(_t): do_save.call())
	line_edit.grab_focus()

func _save_custom_preset(cname: String):
	var d = DirAccess.open("user://")
	if d:
		d.make_dir("custom_rulesets")
	var path = "user://custom_rulesets/%s.json" % cname
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(GameSettingsScript.to_dict(_pending_settings), "\t"))
		f.close()
	settings_panel.visible = false
	_rebuild_preset_buttons()
	preset_panel.visible = true

func _show_custom_preset_options(cname: String):
	var popup = Control.new()
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preset_panel.add_child(popup)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(dim)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)

	var box = PanelContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
	var box_style = StyleBoxFlat.new()
	box_style.bg_color = Color(0.12, 0.12, 0.16, 0.97)
	box_style.corner_radius_top_left = 8
	box_style.corner_radius_top_right = 8
	box_style.corner_radius_bottom_left = 8
	box_style.corner_radius_bottom_right = 8
	box.add_theme_stylebox_override("panel", box_style)
	center.add_child(box)

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	box.add_child(vb)

	var title = Label.new()
	title.text = cname
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_font_size_override("font_size", 16)
	vb.add_child(title)

	vb.add_child(HSeparator.new())

	var rename_btn = Button.new()
	rename_btn.text = "Rename…"
	rename_btn.custom_minimum_size = Vector2(0, 44)
	vb.add_child(rename_btn)

	var delete_btn = Button.new()
	delete_btn.text = "Delete"
	delete_btn.custom_minimum_size = Vector2(0, 44)
	vb.add_child(delete_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(0, 44)
	cancel_btn.pressed.connect(func(): popup.queue_free())
	vb.add_child(cancel_btn)

	rename_btn.pressed.connect(func():
		popup.queue_free()
		_show_rename_preset_popup(cname)
	)

	delete_btn.pressed.connect(func():
		popup.queue_free()
		_show_delete_preset_confirm(cname)
	)

func _show_rename_preset_popup(old_name: String):
	var popup = Control.new()
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preset_panel.add_child(popup)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
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
	prompt_lbl.text = "Rename \"%s\":" % old_name
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.add_theme_color_override("font_color", Color.WHITE)
	prompt_lbl.add_theme_font_size_override("font_size", 16)
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
		if new_name.is_empty() or new_name == old_name:
			popup.queue_free()
			return
		popup.queue_free()
		var old_path = "user://custom_rulesets/%s.json" % old_name
		var new_path = "user://custom_rulesets/%s.json" % new_name
		# Read old data
		var fr = FileAccess.open(old_path, FileAccess.READ)
		if fr:
			var content = fr.get_as_text()
			fr.close()
			var fw = FileAccess.open(new_path, FileAccess.WRITE)
			if fw:
				fw.store_string(content)
				fw.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))
		# Update last_used if it pointed to old name
		var lu_data = {}
		var lu_r = FileAccess.open("user://last_used.json", FileAccess.READ)
		if lu_r:
			var existing = JSON.parse_string(lu_r.get_as_text())
			lu_r.close()
			if existing is Dictionary:
				lu_data = existing
		if lu_data.get("last_preset", "") == "custom:" + old_name:
			lu_data["last_preset"] = "custom:" + new_name
			var lu_w = FileAccess.open("user://last_used.json", FileAccess.WRITE)
			if lu_w:
				lu_w.store_string(JSON.stringify(lu_data))
				lu_w.close()
		_rebuild_preset_buttons()

	ok_btn.pressed.connect(do_rename)
	line_edit.text_submitted.connect(func(_t): do_rename.call())
	line_edit.select_all()
	line_edit.grab_focus()

func _show_delete_preset_confirm(cname: String):
	var popup = Control.new()
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preset_panel.add_child(popup)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(dim)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)

	var box = PanelContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
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

	var lbl = Label.new()
	lbl.text = "Delete \"%s\"?" % cname
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_font_size_override("font_size", 16)
	vb.add_child(lbl)

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vb.add_child(btn_row)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 40)
	cancel_btn.pressed.connect(func(): popup.queue_free())
	btn_row.add_child(cancel_btn)

	var del_btn = Button.new()
	del_btn.text = "Delete"
	del_btn.custom_minimum_size = Vector2(100, 40)
	btn_row.add_child(del_btn)

	del_btn.pressed.connect(func():
		popup.queue_free()
		var path = "user://custom_rulesets/%s.json" % cname
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		# Clear last_used if it pointed here
		var lu_data = {}
		var lu_r = FileAccess.open("user://last_used.json", FileAccess.READ)
		if lu_r:
			var existing = JSON.parse_string(lu_r.get_as_text())
			lu_r.close()
			if existing is Dictionary:
				lu_data = existing
		if lu_data.get("last_preset", "") == "custom:" + cname:
			lu_data.erase("last_preset")
			var lu_w = FileAccess.open("user://last_used.json", FileAccess.WRITE)
			if lu_w:
				lu_w.store_string(JSON.stringify(lu_data))
				lu_w.close()
		_rebuild_preset_buttons()
	)

func _on_menu_difficulty_pressed():
	main_menu_panel.visible = false
	_rebuild_difficulty_buttons()
	difficulty_panel.visible = true

func _on_difficulty_chosen(key: String):
	# Persist the choice merged into last_used.json
	var data = {}
	var fr = FileAccess.open("user://last_used.json", FileAccess.READ)
	if fr:
		var existing = JSON.parse_string(fr.get_as_text())
		fr.close()
		if existing is Dictionary:
			data = existing
	if not data is Dictionary:
		data = {}
	data["ai_difficulty"] = key
	var fw = FileAccess.open("user://last_used.json", FileAccess.WRITE)
	if fw:
		fw.store_string(JSON.stringify(data))
		fw.close()
	# Apply immediately to a running game
	if game != null:
		game.settings.ai_difficulty = key
	_rebuild_difficulty_buttons()

func _rebuild_difficulty_buttons():
	for c in _difficulty_btn_container.get_children():
		c.queue_free()

	var current = "standard"
	if game != null:
		current = game.settings.ai_difficulty
	else:
		var f = FileAccess.open("user://last_used.json", FileAccess.READ)
		if f:
			var data = JSON.parse_string(f.get_as_text())
			f.close()
			if data is Dictionary and data.has("ai_difficulty"):
				current = str(data["ai_difficulty"])

	var options = [
		["Beginner", "Supportive partner, relaxed opponents", "beginner"],
		["Standard", "Balanced play — the real game",         "standard"],
		["Expert",   "Serious players, no mercy",             "expert"],
	]
	for opt in options:
		var btn = Button.new()
		btn.text = "%s\n%s" % [opt[0], opt[1]]
		btn.custom_minimum_size = Vector2(220, 72)
		if opt[2] == current:
			btn.modulate = Color(0.95, 0.80, 0.15)
		btn.pressed.connect(_on_difficulty_chosen.bind(opt[2]))
		_difficulty_btn_container.add_child(btn)

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
