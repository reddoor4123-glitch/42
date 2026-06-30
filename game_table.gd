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
var _follow_me_sep: HSeparator = null
var _follow_me_btn: Button = null
var nello_panel: PanelContainer
var _nello_reversed_btn: Button = null
var preset_panel: PanelContainer
var status_label: Label

# Debug flag — set true to skip AI thinking pauses for faster testing.
# Wire this to a proper settings toggle later once the settings UI exists.
const DEBUG_FAST_MODE: bool = true

# Game state
var selected_tile: DominoTile = null
var human_seat: int = 0
var waiting_for_human: bool = false
var waiting_for_trump: bool = false
var waiting_for_nello_mode: bool = false
var waiting_for_bid: bool = false
var human_is_forced: bool = false
var waiting_for_continue: bool = false

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
	var top_row = HBoxContainer.new()
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
	opponent_top_container.custom_minimum_size = Vector2(0, 50)
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

	# --- Preset picker panel (shown on first launch, hides when a preset is chosen) ---
	preset_panel = PanelContainer.new()
	preset_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(preset_panel)

	var preset_vbox = VBoxContainer.new()
	preset_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	preset_vbox.add_theme_constant_override("separation", 12)
	preset_panel.add_child(preset_vbox)

	var preset_title = Label.new()
	preset_title.text = "Welcome to 42 — Choose Your Rules"
	preset_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preset_title.add_theme_font_size_override("font_size", 18)
	preset_title.add_theme_color_override("font_color", Color.WHITE)
	preset_vbox.add_child(preset_title)

	var preset_subtitle = Label.new()
	preset_subtitle.text = "You can change this anytime from the menu"
	preset_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preset_subtitle.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	preset_vbox.add_child(preset_subtitle)

	var preset_btn_row = VBoxContainer.new()
	preset_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	preset_btn_row.add_theme_constant_override("separation", 8)
	preset_vbox.add_child(preset_btn_row)

	var presets = [
		["Teel Rules",       "Our family's house rules",    "teel"],
		["Texas Standard",   "Common tournament-style rules", "texas"],
		["Pagat Tournament", "Strict tournament ruleset",   "pagat"],
	]
	for p in presets:
		var btn = Button.new()
		btn.text = "%s\n%s" % [p[0], p[1]]
		btn.custom_minimum_size = Vector2(200, 60)
		btn.pressed.connect(_on_preset_chosen.bind(p[2]))
		preset_btn_row.add_child(btn)

	# --- Middle row: left opponent | play area | right opponent ---
	var hbox_mid = HBoxContainer.new()
	hbox_mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox_mid.add_theme_constant_override("separation", 4)
	hbox_mid.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox_mid)

	opponent_left_container = VBoxContainer.new()
	opponent_left_container.alignment = BoxContainer.ALIGNMENT_CENTER
	opponent_left_container.custom_minimum_size = Vector2(50, 0)
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
	opponent_right_container.custom_minimum_size = Vector2(50, 0)
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

	# Follow Me / No Trump — built once, visibility toggled in _show_trump_panel()
	_follow_me_sep = HSeparator.new()
	_follow_me_sep.visible = false
	trump_vbox.add_child(_follow_me_sep)

	_follow_me_btn = Button.new()
	_follow_me_btn.text = "No Trump  (Follow Me)"
	_follow_me_btn.custom_minimum_size = Vector2(180, 40)
	_follow_me_btn.visible = false
	_follow_me_btn.pressed.connect(_on_trump_selected.bind(-1))
	trump_vbox.add_child(_follow_me_btn)

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
	_nello_reversed_btn.text = "Reversed"
	_nello_reversed_btn.custom_minimum_size = Vector2(110, 40)
	_nello_reversed_btn.visible = false
	_nello_reversed_btn.pressed.connect(_on_nello_mode_selected.bind("reversed"))
	nello_row.add_child(_nello_reversed_btn)

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

# ─── GAME FLOW ────────────────────────────────────────────────────────────────

func _start_game():
	preset_panel.visible = true

func _on_preset_chosen(key: String):
	preset_panel.visible = false
	var settings: GameSettings
	match key:
		"teel":  settings = GameSettingsScript.teel_rules()
		"texas": settings = GameSettingsScript.texas_standard()
		_:       settings = GameSettingsScript.pagat_tournament()
	game = Game.new(settings)
	game.setup_players(human_seat)
	_start_hand()

func _start_hand():
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
		_set_status("%s is thinking..." % _seat_label(pid))
		await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 1.0).timeout
		var player = game.players[pid]
		var is_forced = (i == 3 and game.current_bid == null and game.settings.allow_forced_bid)
		var ai_bid = AIPlayer.decide_bid(player.hand, pid, game.current_bid, game.settings, is_forced)
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
		marks_lbl.text = "Marks"
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
	_show_bid_bubble(human_seat, "You\n%s" % bid.debug_string())
	_set_status("You: %s" % bid.debug_string())
	await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 0.7).timeout
	await _run_post_human_bids()
	_finish_bidding([])

func _run_post_human_bids():
	var bid_order: Array = game.bid_order()
	var human_pos = bid_order.find(human_seat)
	for i in range(human_pos + 1, 4):
		var pid = bid_order[i]
		_set_status("%s is thinking..." % _seat_label(pid))
		await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 1.0).timeout
		var player = game.players[pid]
		var is_forced = (i == 3 and game.current_bid == null and game.settings.allow_forced_bid)
		var ai_bid = AIPlayer.decide_bid(player.hand, pid, game.current_bid, game.settings, is_forced)
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
	var allow = game.settings.allow_follow_me
	_follow_me_sep.visible = allow
	_follow_me_btn.visible = allow
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
	game.active_nello_doubles_mode = mode
	game.apply_bid_result(-1)
	_set_info("Nello | Marks: You %d | Them %d" % [game.team_marks[0], game.team_marks[1]])
	_refresh_all_hands()
	_begin_play()

func _begin_play(leader_override: int = -1):
	_clear_bid_bubbles()
	var leader: int
	if leader_override >= 0:
		leader = leader_override
	else:
		leader = game.current_bid.player_id if game.current_bid else 0
	_play_trick(leader)

func _play_trick(leader: int):
	game.start_trick(leader)
	_clear_play_area()
	_set_status("%s leads the trick" % _seat_label(leader))
	_play_next_in_trick()

func _play_next_in_trick():
	var player = game.players[game.current_player]

	# Nello: partner sits out — skip their turn entirely
	if game.variant == BidScript.Type.NELLO:
		var nello_partner = (game.current_bid.player_id + 2) % 4
		if game.current_player == nello_partner:
			game.current_player = (game.current_player + 1) % 4
			if game.current_trick.plays.size() < 3:  # only 3 players in Nello
				_play_next_in_trick()
			else:
				await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 1.2).timeout
				_resolve_trick()
			return

	if player.is_human:
		_highlight_legal_moves()
		waiting_for_human = true
		_set_status("Your turn — tap a domino to play")
	else:
		_set_status("%s is thinking..." % _seat_label(player.id))
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

func _on_human_domino_pressed(tile: DominoTile):
	if not waiting_for_human:
		return
	var legal = game.get_legal_moves(game.players[human_seat])
	if not legal.has(tile.domino):
		return

	waiting_for_human = false
	_clear_highlights()
	_execute_play(game.players[human_seat], tile.domino)

func _animate_ai_play(player: Player, domino: Domino):
	_execute_play(player, domino)

func _ai_choose_domino(player: Player) -> Domino:
	var legal = game.get_legal_moves(player)
	var partner_id = (player.id + 2) % 4
	var reason_log: Array = []
	var chosen = AIPlayer.decide_play(
		legal, player.hand, game.current_trick,
		player.id, partner_id, game.trump, reason_log
	)
	if reason_log.size() > 0:
		_set_status("%s: %s" % [_seat_label(player.id), reason_log[0]])
	return chosen

func _execute_play(player: Player, domino: Domino):
	game.play_domino(player, domino)
	_add_to_play_area(player.id, domino)
	_refresh_hand(player)

	game.current_player = (game.current_player + 1) % 4

	var trick_size = 3 if game.variant == BidScript.Type.NELLO else 4
	if game.current_trick.plays.size() < trick_size:
		_play_next_in_trick()
	else:
		await get_tree().create_timer(0.0 if DEBUG_FAST_MODE else 1.2).timeout
		_resolve_trick()

func _resolve_trick():
	var winner_id = game.resolve_trick()
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
	var msg = "Hand over! %s wins — %s\n\n(tap anywhere to continue)" % [team_str, result.get("reason", "")]
	_set_status(msg)

	_us_marks.set_marks(marks[0])
	_them_marks.set_marks(marks[1])
	_set_info("Marks: You %d | Them %d" % [marks[0], marks[1]])

	waiting_for_continue = true

	var game_winner = game.check_game_over()
	if game_winner >= 0:
		var winner_str = "YOU WIN! 🎉" if game_winner == 0 else "Opponents win."
		_set_status("GAME OVER — " + winner_str)
		waiting_for_continue = false
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
		container.add_child(tile)
		tile.setup(d, face, game.trump)
		if small:
			tile.scale = Vector2(0.45, 0.45)
			tile.custom_minimum_size = Vector2(
				DominoTile.DOMINO_WIDTH * 0.45,
				DominoTile.DOMINO_HEIGHT * 0.45
			)
		if face:
			tile.domino_pressed.connect(_on_human_domino_pressed)

func _add_to_play_area(player_id: int, domino: Domino):
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	play_area_container.add_child(vb)

	var tile = DominoTile.new()
	vb.add_child(tile)
	tile.setup(domino, true, game.trump)

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



func _input(event: InputEvent):
	if waiting_for_continue and event is InputEventMouseButton and event.pressed:
		waiting_for_continue = false
		game.advance_shaker()
		_start_hand()
