class_name FoundMachinePanel
extends Control
## A small card shown when you pick up a machine in a room: it reveals what you found,
## then [Space] takes you straight into the inventory to place it (or [Esc] to keep it
## in stock for later). Pauses the world while open.

const PANEL := Rect2(Vector2(200, 150), Vector2(240, 150))

var _id := ""
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


func open(machine_id: String) -> void:
	_id = machine_id
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
		# Repaired gear always goes to storage now — you place it at your next run setup, not
		# mid-run (the factory is locked in the field). Any key just dismisses the card.
		if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("build_cancel"):
			close()
	queue_redraw()


func _draw() -> void:
	draw_rect(PANEL.grow(3), Color(0.5, 0.85, 1.0, 0.5))
	draw_rect(PANEL, Color(0.07, 0.08, 0.12, 0.98))
	var def: Dictionary = GameData.machines.get(_id, {})
	draw_string(_font, PANEL.position + Vector2(14, 26), "REPAIRED", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.85, 1.0))
	var tex := ContentLibrary.get_icon(String(def.get("icon", _display_icon())), Vector2i(40, 40), String(def.get("color", "")))
	draw_texture_rect(tex, Rect2(PANEL.position + Vector2(16, 44), Vector2(40, 40)), false)
	draw_string(_font, PANEL.position + Vector2(66, 60), _display_name(), HORIZONTAL_ALIGNMENT_LEFT, PANEL.size.x - 74, 18, Color(0.95, 0.95, 0.98))
	draw_string(_font, PANEL.position + Vector2(66, 82), "sent to storage", HORIZONTAL_ALIGNMENT_LEFT, PANEL.size.x - 74, 12, Color(0.75, 0.8, 0.85))
	draw_string(_font, PANEL.position + Vector2(14, PANEL.size.y - 16), "Place it at your next run setup.   [Space]/[Esc] ok", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.75, 0.8))


## Friendly label — transport ids ("__conveyor") aren't in GameData.machines.
func _display_name() -> String:
	match _id:
		"__conveyor": return "Conveyor"
		"__splitter": return "Splitter"
		"__filter": return "Filter"
	return String(GameData.machines.get(_id, {}).get("name", _id))


func _display_icon() -> String:
	if _id.begins_with("__"):
		return "filter"  # a generic transport glyph until dedicated art exists
	return _id
