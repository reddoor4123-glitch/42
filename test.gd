extends Node

func _ready():
	var rect = ColorRect.new()
	rect.color = Color.RED
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
