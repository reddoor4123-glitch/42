extends SceneTree

# Where does a click on the empty area beside the Settings dialog actually go?
#
# First pass established the static facts: the dimmer is STOP, the centring
# container is PASS, the inner dialog is STOP, and the gear is a lower root child
# than settings_panel so it sits behind the overlay. Wiring the dismiss to
# settings_panel.gui_input on the strength of that did not fire.
#
# So this pass instruments every candidate in the chain and pushes a real click at
# a point known to be outside the dialog, recording which handlers see it and in
# what order. Also names every root child, since the first pass showed one drawn
# ABOVE settings_panel that could be swallowing the event.

var _table: Node = null
var _frame := 0
var _log: Array = []
var _obs: Array = []

const FILTER_NAMES := ["STOP", "PASS", "IGNORE"]

func _initialize() -> void:
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

# Signal arg first, bound arg second — Callable.bind() APPENDS.
func _tap(event: InputEvent, label: String) -> void:
	if event is InputEventMouseButton and event.pressed:
		_log.append(label)

func _watch(c: Control, label: String) -> void:
	if is_instance_valid(c):
		c.gui_input.connect(_tap.bind(label))

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false
	var t = _table

	if _frame == 4:
		t.main_menu_panel.visible = false
		t._on_preset_chosen("teel")
		t._show_settings_panel()
		return false

	# Frame 6+: layout has settled, so the dialog's rect is real.
	if _frame == 6:
		var root_ctl: Node = t.settings_panel.get_parent()

		# Name every root child, with the overlay/gear marked, plus anything
		# drawn above the overlay that could intercept first.
		var order: Array = []
		for i in range(root_ctl.get_child_count()):
			var c = root_ctl.get_child(i)
			var nm := "%d: %s (%s)" % [i, c.get_class(), str(c.name)]
			if c == t.settings_panel:
				nm += "   <-- settings_panel"
			elif c is Button and str(c.text) == "⚙":
				nm += "   <-- GEAR"
			if c is Control:
				nm += " filter=%s visible=%s rect=%s" % [
					FILTER_NAMES[c.mouse_filter], c.visible, str(c.get_global_rect())]
			order.append(nm)
		_obs.append({"root children": order})

		# Instrument the whole candidate chain.
		_watch(t.settings_panel, "settings_panel")
		_watch(t.settings_panel.get_child(0), "s_dim")
		_watch(t.settings_panel.get_child(1), "s_center")
		_watch(t._settings_panel_inner, "inner_panel")
		for i in range(root_ctl.get_child_count()):
			var c = root_ctl.get_child(i)
			if c is Control and c != t.settings_panel:
				_watch(c, "ROOT_CHILD_%d_%s" % [i, c.get_class()])

		var inner = t._settings_panel_inner.get_global_rect()
		var outside := Vector2(inner.position.x + inner.size.x * 0.5,
			max(1.0, inner.position.y * 0.5))
		_obs.append({
			"inner rect": str(inner),
			"click point": str(outside),
			"point is outside inner": not inner.has_point(outside),
		})

		# push_input applies the viewport's final transform unless told the
		# coordinates are already local. The project stretches canvas_items, so
		# screen space and canvas space are NOT the same — try both.
		_obs.append({"final transform": str(get_root().get_final_transform())})

		for local in [false, true]:
			_log.clear()
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			ev.position = outside
			ev.global_position = outside
			get_root().push_input(ev, local)
			_obs.append({
				"in_local_coords": local,
				"handlers that saw the click": _log.duplicate(),
				"settings visible after": t.settings_panel.visible,
			})
			if not t.settings_panel.visible:
				t._show_settings_panel()

		# And a click ON the dialog, in whichever mode worked, to confirm the
		# inner panel absorbs it rather than the overlay seeing it.
		_log.clear()
		var inside_ev := InputEventMouseButton.new()
		inside_ev.button_index = MOUSE_BUTTON_LEFT
		inside_ev.pressed = true
		var inside_pt: Vector2 = inner.position + Vector2(3, 3)
		inside_ev.position = inside_pt
		inside_ev.global_position = inside_pt
		get_root().push_input(inside_ev, true)
		_obs.append({
			"click ON dialog (local coords)": str(inside_pt),
			"handlers that saw it": _log.duplicate(),
			"settings visible after": t.settings_panel.visible,
		})

		var f = FileAccess.open("res://headless/settings_dismiss_probe_results.json", FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"observations": _obs}, "\t"))
			f.close()
		quit(0)
		return true
	return false
