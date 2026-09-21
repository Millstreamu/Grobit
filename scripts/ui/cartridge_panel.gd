class_name CartridgePanel
extends Control
## Load-the-retrieval-cartridge screen (Step 4 — see docs/SLICE_1_SCOPE.md). Lists
## the resource items currently in the factory grid; you pick up to CAPACITY of them
## to load, then confirm to SHIP — which ends the map and banks them toward Mars.
## Unpicked resources are left behind (lost), so choosing your best is the decision.

const CAPACITY := 6
const PANEL := Rect2(Vector2(120, 60), Vector2(400, 328))
const ROW_H := 22.0

var _rows: Array = []       # [{pos:Vector2i, id:String}]
var _selected: Array = []   # indices into _rows
var _cursor := 0
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2.ZERO
	size = Vector2(640, 448)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = ThemeDB.fallback_font


func is_open() -> bool:
	return visible


func open() -> void:
	_gather()
	_cursor = 0
	_selected.clear()
	visible = true
	get_tree().paused = true
	queue_redraw()


func close() -> void:
	visible = false
	get_tree().paused = false


func _gather() -> void:
	_rows.clear()
	var f := RunState.factory
	if f == null:
		return
	for y in f.rows:
		for x in f.cols:
			var cell := f.get_cell(Vector2i(x, y))
			if cell.get("kind", "") == "resource":
				_rows.append({"pos": Vector2i(x, y), "id": String(cell.id)})


func _process(_delta: float) -> void:
	if not visible:
		return
	_handle_input()
	queue_redraw()


func _handle_input() -> void:
	if Input.is_action_just_pressed("build_cancel"):
		close()
		return
	if Input.is_action_just_pressed("move_up"):
		_cursor = maxi(_cursor - 1, 0)
	if Input.is_action_just_pressed("move_down"):
		_cursor = mini(_cursor + 1, maxi(_rows.size() - 1, 0))
	if Input.is_action_just_pressed("attack"):
		_toggle()
	if Input.is_action_just_pressed("confirm"):
		_ship()


func _toggle() -> void:
	if _rows.is_empty():
		return
	if _selected.has(_cursor):
		_selected.erase(_cursor)
	elif _selected.size() < CAPACITY:
		_selected.append(_cursor)


func _ship() -> void:
	if _selected.is_empty():
		return
	var items := {}
	for i: int in _selected:
		var id := String(_rows[i].id)
		items[id] = int(items.get(id, 0)) + 1
		RunState.factory.set_cell(_rows[i].pos, {})
	close()
	for controller: Node in get_tree().get_nodes_in_group("run_controller"):
		if controller.has_method("on_cartridge_shipped"):
			controller.on_cartridge_shipped(items)
			return


func _draw() -> void:
	draw_rect(PANEL, Color(0.06, 0.06, 0.10, 0.97))
	draw_string(_font, PANEL.position + Vector2(14, 28), "LOAD RETRIEVAL CARTRIDGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.9, 0.95))
	draw_string(_font, PANEL.position + Vector2(14, 50), "Loaded %d / %d   (unloaded resources are left behind)" % [_selected.size(), CAPACITY], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.85, 0.9))

	if _rows.is_empty():
		draw_string(_font, PANEL.position + Vector2(14, 96), "Nothing in the factory to load.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.6, 0.6))
	for i in _rows.size():
		var y := PANEL.position.y + 72 + i * ROW_H
		var picked := _selected.has(i)
		if i == _cursor:
			draw_rect(Rect2(PANEL.position.x + 8, y - 2, PANEL.size.x - 16, ROW_H), Color(1, 1, 1, 0.10))
		var mark := "[x]" if picked else "[ ]"
		var col := Color(0.6, 1, 0.7) if picked else Color(0.85, 0.85, 0.9)
		draw_string(_font, Vector2(PANEL.position.x + 16, y + 14), "%s %s" % [mark, GameData.resource_name(String(_rows[i].id))], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)

	draw_string(_font, PANEL.position + Vector2(14, PANEL.size.y - 14), "[W/S] move   [Space] load/unload   [Enter] ship & leave   [Esc] cancel", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.75))
