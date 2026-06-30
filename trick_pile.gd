class_name TrickPile
extends Control

# Shows every domino from every trick this team has won, face-up,
# stacked in rows of 4 in the order they were played. No trump logic,
# no special-casing — just a simple visual record.

var dominoes: Array[Domino] = []
var face_up: bool = true

const MINI_W  := 32.0
const MINI_H  := 56.0
const PAD     := 4.0
const ROW_H   := MINI_H + PAD
const COL_W   := MINI_W + PAD
const PER_ROW := 4

const COLOR_FACE   := Color(0.95, 0.93, 0.88)
const COLOR_BACK   := Color(0.18, 0.38, 0.22)
const COLOR_BORDER := Color(0.25, 0.22, 0.18)
const COLOR_PIP    := Color(0.10, 0.10, 0.10)

func _ready():
	custom_minimum_size = Vector2(COL_W * PER_ROW + PAD, ROW_H * 2)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

# Add all 4 dominoes from a won trick, in the order they were played
func add_trick_dominoes(trick_dominoes: Array):
	for d in trick_dominoes:
		dominoes.append(d)
	var rows_needed = max(2, ceili(float(dominoes.size()) / PER_ROW))
	custom_minimum_size = Vector2(COL_W * PER_ROW + PAD, ROW_H * rows_needed)
	queue_redraw()

func clear_tricks():
	dominoes.clear()
	custom_minimum_size = Vector2(COL_W * PER_ROW + PAD, ROW_H * 2)
	queue_redraw()

var _press_pos: Vector2 = Vector2.ZERO
var _was_drag: bool = false

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.pressed:
			_press_pos = event.position
			_was_drag = false
		else:
			# Only flip if this was a genuine click, not a drag/scroll
			if not _was_drag:
				face_up = !face_up
				queue_redraw()
	elif event is InputEventMouseMotion:
		if event.position.distance_to(_press_pos) > 6:
			_was_drag = true

func _draw():
	for i in range(dominoes.size()):
		var row = i / PER_ROW
		var col = i % PER_ROW
		var x = col * COL_W + PAD
		var y = row * ROW_H

		if not face_up:
			draw_rect(Rect2(x, y, MINI_W, MINI_H), COLOR_BACK)
			draw_rect(Rect2(x, y, MINI_W, MINI_H), COLOR_BORDER, false, 1.5)
		else:
			_draw_mini_domino(x, y, dominoes[i])

func _draw_mini_domino(x: float, y: float, domino: Domino):
	draw_rect(Rect2(x, y, MINI_W, MINI_H), COLOR_BORDER)
	draw_rect(Rect2(x + 1, y + 1, MINI_W - 2, MINI_H - 2), COLOR_FACE)

	var mid_y = y + MINI_H * 0.5
	draw_line(Vector2(x + 3, mid_y), Vector2(x + MINI_W - 3, mid_y), COLOR_BORDER, 1.0)

	var top_center = Vector2(x + MINI_W * 0.5, y + MINI_H * 0.25)
	var bot_center = Vector2(x + MINI_W * 0.5, y + MINI_H * 0.75)

	_draw_pips(top_center, domino.right)
	_draw_pips(bot_center, domino.left)

func _draw_pips(center: Vector2, value: int):
	if value == 0:
		return
	var r = 2.3
	var sp = 8.5

	var offsets: Array = []
	match value:
		1: offsets = [Vector2(0, 0)]
		2: offsets = [Vector2(-sp*0.5, -sp*0.5), Vector2(sp*0.5, sp*0.5)]
		3: offsets = [Vector2(-sp*0.5, -sp*0.5), Vector2(0, 0), Vector2(sp*0.5, sp*0.5)]
		4: offsets = [Vector2(-sp*0.5, -sp*0.5), Vector2(sp*0.5, -sp*0.5),
					  Vector2(-sp*0.5, sp*0.5), Vector2(sp*0.5, sp*0.5)]
		5: offsets = [Vector2(-sp*0.5, -sp*0.5), Vector2(sp*0.5, -sp*0.5), Vector2(0, 0),
					  Vector2(-sp*0.5, sp*0.5), Vector2(sp*0.5, sp*0.5)]
		6: offsets = [Vector2(-sp*0.5, -sp*0.6), Vector2(sp*0.5, -sp*0.6),
					  Vector2(-sp*0.5, 0), Vector2(sp*0.5, 0),
					  Vector2(-sp*0.5, sp*0.6), Vector2(sp*0.5, sp*0.6)]

	for o in offsets:
		draw_circle(center + o, r, COLOR_PIP)
