extends SceneTree

# Isolates WHICH nodes survive a settings-screen rebuild cycle, by class name.
# A bare OBJECT_NODE_COUNT delta says "something leaked"; this says what.

var _table: Node = null
var _frame := 0
var _before: Dictionary = {}
var _out: Array = []

func _initialize() -> void:
	_table = load("res://control.tscn").instantiate()
	get_root().add_child(_table)

func _census() -> Dictionary:
	var counts := {}
	var stack: Array = [get_root()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var cls := n.get_class()
		counts[cls] = int(counts.get(cls, 0)) + 1
		for c in n.get_children():
			stack.append(c)
	return counts

func _diff(before: Dictionary, after: Dictionary) -> Array:
	var rows: Array = []
	var keys := {}
	for k in before: keys[k] = true
	for k in after: keys[k] = true
	for k in keys:
		var b := int(before.get(k, 0))
		var a := int(after.get(k, 0))
		if a != b:
			rows.append({"class": k, "before": b, "after": a, "delta": a - b})
	rows.sort_custom(func(x, y): return abs(x["delta"]) > abs(y["delta"]))
	return rows

func _one_cycle() -> void:
	_table._show_settings_panel()
	for key in _table.SLOT_KEYS:
		_table._on_settings_slot_pressed(key)
	_table.settings_panel.visible = false

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	# Warm up with one cycle so first-time allocations aren't counted as growth.
	if _frame == 3:
		_one_cycle()
		return false
	if _frame == 5:
		_before = _census()
		_out.append({"note": "baseline taken", "tree_nodes": _sum(_before),
			"perf_node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))})
		return false
	# Six more cycles, one per frame.
	if _frame >= 6 and _frame <= 11:
		_one_cycle()
		return false
	if _frame < 16:
		return false
	var after := _census()
	_out.append({"note": "after 6 cycles", "tree_nodes": _sum(after),
		"perf_node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))})
	_out.append({"note": "in-tree delta by class", "rows": _diff(_before, after)})
	var f = FileAccess.open("res://scripts/node_leak_probe_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"report": _out}, "\t"))
		f.close()
	return true

func _sum(d: Dictionary) -> int:
	var t := 0
	for k in d:
		t += int(d[k])
	return t
