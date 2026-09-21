class_name DecodePanel
extends Control
## Decode draft screen (see docs/INVENTORY_FACTORY_DIRECTION.md). Spend Tech Data to
## pick 1 of 3 modules drawn from the catalogue; the pick joins the permanent
## collection (MetaState.modules_owned). Pauses the world while open.

const PANEL := Rect2(Vector2(120, 70), Vector2(400, 300))
const ROW_H := 74.0

var _cost: Dictionary = {}
var _options: Array = []
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


func open(cost: Dictionary) -> void:
	if visible:
		return
	_cost = cost
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_options = MetaState.decode_options(3, rng)
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
	if _options.is_empty():
		return
	if Input.is_action_just_pressed("move_up"):
		_cursor = maxi(_cursor - 1, 0)
	if Input.is_action_just_pressed("move_down"):
		_cursor = mini(_cursor + 1, _options.size() - 1)
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("confirm"):
		_pick()


func _pick() -> void:
	if not RunState.can_afford(_cost):
		_message = "Need %s to decode." % _cost_text()
		return
	RunState.spend(_cost)
	MetaState.grant_module(String(_options[_cursor]))
	close()


func _cost_text() -> String:
	var parts: Array = []
	for id: String in _cost:
		parts.append("%d %s" % [int(_cost[id]), GameData.resource_name(id)])
	return ", ".join(parts)


func _draw() -> void:
	draw_rect(PANEL, Color(0.06, 0.06, 0.11, 0.97))
	draw_string(_font, PANEL.position + Vector2(14, 28), "DECODE MODULE", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.9, 0.95))
	var can := RunState.can_afford(_cost)
	draw_string(_font, PANEL.position + Vector2(14, 48), "Cost: %s   (you have %d)" % [_cost_text(), RunState.get_quantity("tech_data")], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 1, 0.6) if can else Color(1, 0.5, 0.5))

	if _options.is_empty():
		draw_string(_font, PANEL.position + Vector2(14, 96), "No modules in the catalogue.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.8, 0.6, 0.6))
	for i in _options.size():
		var def: Dictionary = GameData.modules.get(String(_options[i]), {})
		var r := Rect2(PANEL.position + Vector2(12, 62 + i * ROW_H), Vector2(PANEL.size.x - 24, ROW_H - 8))
		draw_rect(r, Color(0.12, 0.13, 0.18))
		if i == _cursor:
			draw_rect(r.grow(2), Color.WHITE, false, 2.0)
		var tex := ContentLibrary.get_icon(String(def.get("icon", _options[i])), Vector2i(24, 24), String(def.get("color", "")))
		draw_texture_rect(tex, Rect2(r.position + Vector2(10, 10), Vector2(28, 28)), false)
		draw_string(_font, r.position + Vector2(48, 24), String(def.get("name", _options[i])), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.92, 0.92, 0.96))
		draw_string(_font, r.position + Vector2(48, 44), String(def.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 56, 12, Color(0.75, 0.78, 0.82))
		draw_string(_font, r.position + Vector2(r.size.x - 48, 24), "owned %d" % MetaState.module_count(String(_options[i])), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.75))

	draw_string(_font, PANEL.position + Vector2(14, PANEL.size.y - 14), "[W/S] choose   [Space] decode   [Esc] cancel", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.75))
	if _message != "":
		draw_string(_font, PANEL.position + Vector2(180, PANEL.size.y - 14), _message, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.9, 0.7))
