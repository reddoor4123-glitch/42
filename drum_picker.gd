class_name DrumPicker
extends Control

signal value_changed(new_value: int)

var values: Array[int] = []
var current_index: int = 0
var label_prefix: String = ""
var font_scale: float = 1.0

const ITEM_WIDTH  := 56.0
const VISIBLE_ITEMS := 3
const HEIGHT := 52.0

const COLOR_BG         := Color(0.12, 0.12, 0.14)
const COLOR_SELECTED   := Color(0.95, 0.80, 0.15)
const COLOR_UNSELECTED := Color(0.55, 0.55, 0.55)
const COLOR_HIGHLIGHT  := Color(0.22, 0.22, 0.26)
const COLOR_BORDER     := Color(0.40, 0.40, 0.45)

var _drag_start_x: float = 0.0
var _dragging: bool = false
var _drag_accumulated: float = 0.0

func _ready():
	custom_minimum_size = Vector2(ITEM_WIDTH * VISIBLE_ITEMS, HEIGHT)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

func setup(vals: Array[int], start_index: int = 0, prefix: String = ""):
	values = vals
	current_index = clampi(start_index, 0, vals.size() - 1)
	label_prefix = prefix
	queue_redraw()

func get_value() -> int:
	if values.is_empty():
		return 0
	return values[current_index]

func scroll_left():
	if current_index > 0:
		current_index -= 1
		value_changed.emit(get_value())
		queue_redraw()

func scroll_right():
	if current_index < values.size() - 1:
		current_index += 1
		value_changed.emit(get_value())
		queue_redraw()

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			scroll_left()
		elif event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			scroll_right()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_start_x = event.position.x
				_drag_accumulated = 0.0
			else:
				_dragging = false
				# Tap left third = scroll left, right third = scroll right
				if abs(_drag_accumulated) < 5:
					var third = size.x / 3.0
					if event.position.x < third:
						scroll_left()
					elif event.position.x > third * 2:
						scroll_right()
	elif event is InputEventMouseMotion and _dragging:
		_drag_accumulated += event.relative.x
		if abs(_drag_accumulated) > ITEM_WIDTH * 0.6:
			if _drag_accumulated > 0:
				scroll_left()
			else:
				scroll_right()
			_drag_accumulated = 0.0

func _draw():
	var w = size.x
	var h = size.y
	var center_x = w / 2.0

	# Background
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)

	# Highlight band for selected item
	draw_rect(Rect2(center_x - ITEM_WIDTH / 2.0, 0, ITEM_WIDTH, h), COLOR_HIGHLIGHT)

	# Left/right divider lines
	draw_line(Vector2(center_x - ITEM_WIDTH / 2.0, 4),
			  Vector2(center_x - ITEM_WIDTH / 2.0, h - 4), COLOR_BORDER, 1.5)
	draw_line(Vector2(center_x + ITEM_WIDTH / 2.0, 4),
			  Vector2(center_x + ITEM_WIDTH / 2.0, h - 4), COLOR_BORDER, 1.5)

	# Draw visible items
	for offset in range(-1, 2):
		var idx = current_index + offset
		if idx < 0 or idx >= values.size():
			continue
		var item_center_x = center_x + offset * ITEM_WIDTH
		var text = label_prefix + str(values[idx])
		var is_selected = (offset == 0)
		var color = COLOR_SELECTED if is_selected else COLOR_UNSELECTED
		if not is_selected:
			color.a = 0.6
		var font_size = round((24 if is_selected else 17) * font_scale)
		var text_size = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos = Vector2(item_center_x - text_size.x / 2.0, h / 2.0 + text_size.y / 2.0 - 4)
		draw_string(ThemeDB.fallback_font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

	# Outer border
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BORDER, false, 1.5)

	# Scroll hint arrows
	var arrow_color = Color(COLOR_UNSELECTED, 0.4)
	if current_index > 0:
		draw_string(ThemeDB.fallback_font, Vector2(3, h / 2.0 + 7), "◀", HORIZONTAL_ALIGNMENT_LEFT, -1, round(13 * font_scale), arrow_color)
	if current_index < values.size() - 1:
		draw_string(ThemeDB.fallback_font, Vector2(w - 14, h / 2.0 + 7), "▶", HORIZONTAL_ALIGNMENT_LEFT, -1, round(13 * font_scale), arrow_color)
