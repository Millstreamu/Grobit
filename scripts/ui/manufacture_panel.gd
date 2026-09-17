class_name ManufacturePanel
extends Control
## Full-window, keyboard-driven manufacturing screen — same grid/cursor style as
## the inventory. Each cell is a recipe (output icon); move the cursor with WASD
## and press Space to build it (consumes inputs, queues, and outputs into a free
## inventory slot over time). Opening pauses the game like the inventory.

const PANEL_POS := Vector2(0, 0)
const PANEL_SIZE := Vector2(640, 448)
const COLUMNS := 5
const CELL := 54.0
const GAP := 12.0

var _cursor := 0
var _font: Font
var _recipe_ids: Array = []
var _manufacturing: Manufacturing


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = PANEL_POS
	size = PANEL_SIZE
	visible = false
	_font = ThemeDB.fallback_font
	_recipe_ids = GameData.recipes.keys()
	if OS.has_environment("GROBIT_OPEN_MFG"):
		_debug_open.call_deferred()


# Debug helper (env-gated): grants materials and opens the panel for screenshots.
func _debug_open() -> void:
	RunState.add("metal", 3)
	RunState.add("electronics", 3)
	open()


func _process(_delta: float) -> void:
	if not visible:
		return
	if _manufacturing == null:
		_manufacturing = get_tree().get_first_node_in_group("manufacturing") as Manufacturing
	_handle_input()
	queue_redraw()


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_cursor = 0
	get_tree().paused = true
	queue_redraw()


func close() -> void:
	visible = false
	get_tree().paused = false


func _handle_input() -> void:
	if Input.is_action_just_pressed("build_cancel"):
		close()
		return
	if Input.is_action_just_pressed("move_up"):
		_move(0, -1)
	if Input.is_action_just_pressed("move_down"):
		_move(0, 1)
	if Input.is_action_just_pressed("move_left"):
		_move(-1, 0)
	if Input.is_action_just_pressed("move_right"):
		_move(1, 0)
	if Input.is_action_just_pressed("attack"):
		_build_selected()


func _cols() -> int:
	return clampi(_recipe_ids.size(), 1, COLUMNS)


func _move(dx: int, dy: int) -> void:
	if _recipe_ids.is_empty():
		return
	var cols := _cols()
	var col: int = clampi(_cursor % cols + dx, 0, cols - 1)
	var row: int = maxi(_cursor / cols + dy, 0)
	var index := row * cols + col
	if index < _recipe_ids.size():
		_cursor = index


func _build_selected() -> void:
	if _cursor < 0 or _cursor >= _recipe_ids.size() or _manufacturing == null:
		return
	if not _manufacturing.start(String(_recipe_ids[_cursor])):
		var name: String = GameData.recipes[_recipe_ids[_cursor]].get("name", _recipe_ids[_cursor])
		for hud: Node in get_tree().get_nodes_in_group("hud"):
			if hud.has_method("log_message"):
				hud.log_message("Not enough materials for %s." % name)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, PANEL_SIZE), Color(0.06, 0.06, 0.09, 1.0))
	draw_string(_font, Vector2(20, 34), "MANUFACTURING", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.9, 0.95))
	draw_string(_font, Vector2(300, 34), _craft_status(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.85, 1.0))

	var cols := _cols()
	var origin := Vector2(24, 64)
	for i in _recipe_ids.size():
		var c := i % cols
		var r := i / cols
		var cell := Rect2(origin + Vector2(c * (CELL + GAP), r * (CELL + GAP)), Vector2(CELL, CELL))
		_draw_recipe(i, cell)

	draw_string(_font, Vector2(20, PANEL_SIZE.y - 46), _cursor_info(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.95, 0.7))
	var hint := "[WASD] move   [Space] build   [M]/[Esc] close"
	draw_string(_font, Vector2(20, PANEL_SIZE.y - 16), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.7, 0.75))


func _draw_recipe(index: int, cell: Rect2) -> void:
	var id := String(_recipe_ids[index])
	var def: Dictionary = GameData.recipes[id]
	var affordable := _manufacturing != null and _manufacturing.can_craft(id)
	draw_rect(cell, Color(0.18, 0.18, 0.22) if affordable else Color(0.14, 0.10, 0.10))
	var tex := ContentLibrary.get_icon(String(def.get("icon", def.get("output", id))), Vector2i(16, 16))
	draw_texture_rect(tex, cell.grow(-10), false, Color.WHITE if affordable else Color(1, 1, 1, 0.35))
	if index == _cursor:
		draw_rect(cell.grow(2), Color.WHITE, false, 2.0)


func _craft_status() -> String:
	if _manufacturing == null or _manufacturing.current_recipe().is_empty():
		return ""
	var name: String = GameData.recipes[_manufacturing.current_recipe()].get("name", "")
	return "Crafting %s  %d%%  (queue %d)" % [name, int(_manufacturing.current_ratio() * 100.0), _manufacturing.queue_size()]


func _cursor_info() -> String:
	if _cursor < 0 or _cursor >= _recipe_ids.size():
		return ""
	var id := String(_recipe_ids[_cursor])
	var def: Dictionary = GameData.recipes[id]
	var cost_parts: Array = []
	for res: String in def.get("inputs", {}):
		cost_parts.append("%d %s (have %d)" % [int(def.inputs[res]), GameData.resource_name(res), RunState.get_quantity(res)])
	var ready := "  — ready" if (_manufacturing != null and _manufacturing.can_craft(id)) else "  — need materials"
	return "%s = %s%s" % [String(def.get("name", id)), ", ".join(cost_parts), ready]
