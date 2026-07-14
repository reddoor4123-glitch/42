class_name DominoTile
extends Control

# Emitted when human player taps this domino
signal domino_pressed(tile)
# Drag-to-reorder signals (mirrors TrickPile's release-gated, distance-
# threshold drag detection). domino_pressed now fires on a clean release
# rather than on press, so a genuine drag never also fires a play/arm.
signal domino_drag_started(tile)
signal domino_drag_moved(tile, global_position: Vector2)
signal domino_drag_ended(tile, was_drag: bool)

var domino: Domino = null
var face_up: bool = true
var is_playable: bool = false   # Highlighted as a legal move
var is_selected: bool = false

var _press_pos: Vector2 = Vector2.ZERO
var _dragging: bool = false

# Visual constants — change these to tune look/feel
const DOMINO_WIDTH   := 64.0
const DOMINO_HEIGHT  := 128.0
const CORNER_RADIUS  := 8.0
const PIP_RADIUS     := 5.0
const DIVIDER_MARGIN := 8.0

# Colors — swap these out when you have real art
const COLOR_FACE      := Color(0.95, 0.93, 0.88)   # Ivory
const COLOR_BACK      := Color(0.18, 0.38, 0.22)   # Dark green
const COLOR_PIP       := Color(0.10, 0.10, 0.10)   # Near-black
const COLOR_BORDER    := Color(0.25, 0.22, 0.18)   # Dark brown
const COLOR_PLAYABLE  := Color(0.25, 0.75, 0.35)   # Green highlight
const COLOR_SELECTED  := Color(0.95, 0.80, 0.15)   # Gold highlight
const COLOR_TRUMP_PIP := Color(0.75, 0.15, 0.15)   # Red for trump pips

var _trump: int = -1  # Set by parent so trump pips can be colored

func _ready():
	custom_minimum_size = Vector2(DOMINO_WIDTH, DOMINO_HEIGHT)
	size = Vector2(DOMINO_WIDTH, DOMINO_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

func setup(d: Domino, show_face: bool = true, trump: int = -1):
	domino = d
	face_up = show_face
	_trump = trump
	queue_redraw()

func set_playable(playable: bool):
	is_playable = playable
	queue_redraw()

func set_selected(selected: bool):
	is_selected = selected
	queue_redraw()

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_pos = event.position
			_dragging = false
		else:
			if _dragging:
				domino_drag_ended.emit(self, true)
			else:
				if face_up:
					domino_pressed.emit(self)
				domino_drag_ended.emit(self, false)
			_dragging = false
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if not _dragging and event.position.distance_to(_press_pos) > 6:
			_dragging = true
			domino_drag_started.emit(self)
		if _dragging:
			domino_drag_moved.emit(self, get_global_mouse_position())

func _draw():
	var w := size.x
	var h := size.y
	var s := h / DOMINO_HEIGHT

	var rect = Rect2(Vector2.ZERO, Vector2(w, h))

	var border_color = COLOR_BORDER
	if is_selected:
		border_color = COLOR_SELECTED
	elif is_playable:
		border_color = COLOR_PLAYABLE

	draw_rect(Rect2(rect.position + Vector2(2, 3) * s, rect.size), Color(0, 0, 0, 0.3))
	draw_rect(rect, border_color)

	var inner = rect.grow(-3.0 * s)
	if face_up and domino != null:
		draw_rect(inner, COLOR_FACE)
		_draw_pips(inner, s)
		_draw_divider(inner, s)
	else:
		draw_rect(inner, COLOR_BACK)
		_draw_back_pattern(inner, s)

func _draw_divider(rect: Rect2, s: float):
	var mid_y = rect.position.y + rect.size.y * 0.5
	draw_line(
		Vector2(rect.position.x + DIVIDER_MARGIN * s, mid_y),
		Vector2(rect.position.x + rect.size.x - DIVIDER_MARGIN * s, mid_y),
		COLOR_BORDER, max(1.0, 1.5 * s)
	)

func _draw_pips(rect: Rect2, s: float):
	if domino == null:
		return
	var top_half = Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.5 - 1))
	var bot_half = Rect2(
		Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + 1),
		Vector2(rect.size.x, rect.size.y * 0.5 - 1)
	)
	_draw_pip_value(domino.left, bot_half, domino.left == _trump, s)
	_draw_pip_value(domino.right, top_half, domino.right == _trump, s)

func _draw_pip_value(value: int, rect: Rect2, is_trump_pip: bool, s: float):
	var color = COLOR_TRUMP_PIP if is_trump_pip else COLOR_PIP
	var positions = _pip_positions(value, rect)
	for pos in positions:
		draw_circle(pos, max(1.0, PIP_RADIUS * s), color)

func _pip_positions(value: int, rect: Rect2) -> Array:
	var cx = rect.position.x + rect.size.x * 0.5
	var cy = rect.position.y + rect.size.y * 0.5
	var ox = rect.size.x * 0.25
	var oy = rect.size.y * 0.28

	match value:
		0: return []
		1: return [Vector2(cx, cy)]
		2: return [Vector2(cx - ox, cy - oy), Vector2(cx + ox, cy + oy)]
		3: return [Vector2(cx - ox, cy - oy), Vector2(cx, cy), Vector2(cx + ox, cy + oy)]
		4: return [Vector2(cx - ox, cy - oy), Vector2(cx + ox, cy - oy),
				   Vector2(cx - ox, cy + oy), Vector2(cx + ox, cy + oy)]
		5: return [Vector2(cx - ox, cy - oy), Vector2(cx + ox, cy - oy), Vector2(cx, cy),
				   Vector2(cx - ox, cy + oy), Vector2(cx + ox, cy + oy)]
		6: return [Vector2(cx - ox, cy - oy), Vector2(cx + ox, cy - oy),
				   Vector2(cx - ox, cy),      Vector2(cx + ox, cy),
				   Vector2(cx - ox, cy + oy), Vector2(cx + ox, cy + oy)]
	return []

func _draw_back_pattern(rect: Rect2, s: float):
	var step = max(4.0, 8.0 * s)
	var line_color = Color(COLOR_BACK.r + 0.08, COLOR_BACK.g + 0.08, COLOR_BACK.b + 0.08)
	var x = rect.position.x
	while x < rect.position.x + rect.size.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.position.y + rect.size.y), line_color, 1)
		x += step
