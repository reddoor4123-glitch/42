class_name MarksDisplay
extends Control

# Draws the word "ALL" as individual strokes, lighting up one per mark
# A = 3 strokes, L = 2 strokes, L = 2 strokes = 7 total

var marks: int = 0
var team_color: Color = Color.WHITE
var label_text: String = "US"

const STROKE_LIT    := Color(0.95, 0.90, 0.70)   # Warm white/gold when earned
const STROKE_UNLIT  := Color(0.25, 0.25, 0.25)   # Dark grey unearned
const STROKE_WIDTH  := 3.0
const W := 72.0
const H := 70.0

func _ready():
	custom_minimum_size = Vector2(W, H + 16)
	queue_redraw()

func set_marks(m: int):
	marks = clampi(m, 0, 7)
	queue_redraw()

func set_team(color: Color, label: String):
	team_color = color
	label_text = label
	queue_redraw()

# Stroke definitions: each is [x1,y1, x2,y2] in a 0-1 normalized space
# We'll define them in pixel coords relative to a letter box
# Letters are laid out left to right: A(0-22px), gap, L(26-44px), gap, L(48-66px)
# within the W=72 space, letter height ~60px starting at y=20

func _draw():
	var font = ThemeDB.fallback_font
	# Team label at top
	var lbl_size = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
	draw_string(font, Vector2(W/2 - lbl_size.x/2, 14), label_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, team_color)

	# Draw all 7 strokes
	var stroke_data = _get_strokes()
	for i in range(7):
		var color = STROKE_LIT if i < marks else STROKE_UNLIT
		var s = stroke_data[i]
		draw_line(Vector2(s[0], s[1]), Vector2(s[2], s[3]), color, STROKE_WIDTH, true)

func _get_strokes() -> Array:
	# Letter dimensions
	var lh = 40.0   # letter height
	var lw = 18.0   # letter width
	var top = 18.0
	var bot = top + lh
	var mid = top + lh * 0.48

	# A positions (left side)
	var ax = 2.0
	# L1 positions
	var l1x = ax + lw + 8
	# L2 positions
	var l2x = l1x + lw + 8

	return [
		# A stroke 1: left leg  / (bottom-left to top-center)
		[ax, bot,   ax + lw*0.5, top],
		# A stroke 2: right leg  \ (top-center to bottom-right)
		[ax + lw*0.5, top,   ax + lw, bot],
		# A stroke 3: crossbar  —
		[ax + lw*0.15, mid,  ax + lw*0.85, mid],

		# L1 stroke 1: vertical  |
		[l1x, top,   l1x, bot],
		# L1 stroke 2: base  _
		[l1x, bot,   l1x + lw, bot],

		# L2 stroke 1: vertical  |
		[l2x, top,   l2x, bot],
		# L2 stroke 2: base  _
		[l2x, bot,   l2x + lw, bot],
	]
