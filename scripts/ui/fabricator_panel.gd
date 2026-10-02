class_name FabricatorPanel
extends Control
## Crafting menu opened from a Fabricator station. Spend resources from the factory
## grid to craft transport parts and storage caches into your stock, then place them
## from the factory ([B] build). Pauses the world while open.

const PANEL := Rect2(Vector2(120, 70), Vector2(400, 300))
const ROW_H := 40.0
## What the Fabricator can make (cost comes from RunState.part_cost / the def).
const ITEMS := ["__conveyor", "__splitter", "__filter", "storage_cache"]

var _cursor := 0
var _message := ""
var _opened_frame := -1
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
	if visible:
		return
	_cursor = 0
	_message = ""
	_opened_frame = Engine.get_process_frames()
	visible = true
	get_tree().paused = true
	queue_redraw()


func close() -> void:
	visible = false
	get_tree().paused = false


func _process(_delta: float) -> void:
	if not visible:
		return
	if Engine.get_process_frames() != _opened_frame:
		_handle_input()
	queue_redraw()


func _handle_input() -> void:
	if Input.is_action_just_pressed("build_cancel"):
		close()
		return
	if Input.is_action_just_pressed("move_up"):
		_cursor = maxi(_cursor - 1, 0)
	if Input.is_action_just_pressed("move_down"):
		_cursor = mini(_cursor + 1, ITEMS.size() - 1)
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("confirm"):
		_craft()


func _craft() -> void:
	var id: String = ITEMS[_cursor]
	var cost := RunState.part_cost(id)
	if not RunState.can_afford(cost):
		_message = "Need %s." % _cost_text(cost)
		return
	RunState.spend(cost)
	RunState.add_to_stock(id)
	_message = "Crafted %s — now x%d in stock." % [_part_name(id), RunState.stock_count(id)]


func _draw() -> void:
	draw_rect(PANEL, Color(0.06, 0.06, 0.10, 0.97))
	draw_string(_font, PANEL.position + Vector2(14, 28), "FABRICATOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.85, 0.6))
	draw_string(_font, PANEL.position + Vector2(14, 48), "Spend factory resources to craft parts into stock.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.85, 0.9))

	for i in ITEMS.size():
		var id: String = ITEMS[i]
		var y := PANEL.position.y + 68 + i * ROW_H
		if i == _cursor:
			draw_rect(Rect2(PANEL.position.x + 8, y - 4, PANEL.size.x - 16, ROW_H - 4), Color(1, 1, 1, 0.10))
		var afford := RunState.can_afford(RunState.part_cost(id))
		var name_col := Color(0.92, 0.92, 0.96) if afford else Color(1, 0.6, 0.6)
		draw_string(_font, Vector2(PANEL.position.x + 16, y + 14), "%s   (have x%d)" % [_part_name(id), RunState.stock_count(id)], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, name_col)
		draw_string(_font, Vector2(PANEL.position.x + 16, y + 30), "cost: %s" % _cost_text(RunState.part_cost(id)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.8, 0.7) if afford else Color(0.85, 0.55, 0.55))

	if _message != "":
		draw_string(_font, PANEL.position + Vector2(14, PANEL.size.y - 34), _message, HORIZONTAL_ALIGNMENT_LEFT, PANEL.size.x - 28, 13, Color(1, 0.95, 0.7))
	draw_string(_font, PANEL.position + Vector2(14, PANEL.size.y - 14), "[W/S] pick   [Space] craft   [Esc] close", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.75))


func _part_name(id: String) -> String:
	match id:
		"__conveyor":
			return "Conveyor"
		"__splitter":
			return "Splitter"
		"__filter":
			return "Filter"
	return String(GameData.machines.get(id, {}).get("name", id))


func _cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"
	var parts: Array = []
	for res: String in cost:
		parts.append("%d× %s" % [int(cost[res]), GameData.resource_name(res)])
	return ", ".join(parts)
