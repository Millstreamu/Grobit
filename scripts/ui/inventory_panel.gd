class_name InventoryPanel
extends Control
## Full-window, keyboard-driven grid inventory. Slots hold one item, but a player
## can select several units of the same resource before dropping them one at a
## time. Dropping raw scrap onto the Scrap Recycler module feeds one selected
## unit per press (the recycler then processes it into a free slot).
##
## Opening pauses the game so it acts as a modal screen. Placeholder art: cells
## are plain coloured squares until real slot/background art exists.

const PANEL_POS := Vector2(0, 0)
const PANEL_SIZE := Vector2(640, 448)
const CELL := 54.0
const GAP := 10.0

var _cursor := 0
var _sources: Array[int] = []
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = PANEL_POS
	size = PANEL_SIZE
	visible = false
	_font = ThemeDB.fallback_font
	if OS.has_environment("GROBIT_OPEN_INV"):
		_debug_open.call_deferred()


# Debug helper (env-gated): fills a few items and opens the panel for screenshots.
func _debug_open() -> void:
	RunState.add("raw_scrap", 3)
	RunState.add("electronics", 2)
	RunState.add("metal", 1)
	open()


func _process(_delta: float) -> void:
	if not visible:
		return
	_handle_input()
	queue_redraw()


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_cursor = 0
	_sources.clear()
	get_tree().paused = true
	queue_redraw()


func close() -> void:
	visible = false
	get_tree().paused = false


func _handle_input() -> void:
	if Input.is_action_just_pressed("build_cancel"):
		close()
		return
	var cols := RunState.COLUMNS
	var rows := RunState.ROWS
	var col := _cursor % cols
	var row := _cursor / cols
	if Input.is_action_just_pressed("move_up") and row > 0:
		_cursor -= cols
	if Input.is_action_just_pressed("move_down") and row < rows - 1:
		_cursor += cols
	if Input.is_action_just_pressed("move_left") and col > 0:
		_cursor -= 1
	if Input.is_action_just_pressed("move_right") and col < cols - 1:
		_cursor += 1
	if Input.is_action_just_pressed("attack"):
		_activate()


func _activate() -> void:
	var slot := RunState.get_slot(_cursor)
	if _sources.is_empty():
		if not slot.is_empty():
			_sources.append(_cursor)
		return

	# Pressing a selected cell again removes just that unit from the selection.
	if _sources.has(_cursor):
		_sources.erase(_cursor)
		return

	var selected := RunState.get_slot(_sources[0])
	# Matching resources join the current selection instead of swapping. Modules
	# remain single selections, since only resource units can be stacked.
	if selected.get("kind", "") == "resource" \
			and slot.get("kind", "") == "resource" \
			and String(selected.get("id", "")) == String(slot.get("id", "")):
		_sources.append(_cursor)
		return

	# A drop always moves one selected unit. Keeping the remaining source indexes
	# selected lets repeated Space presses feed a recycler one unit at a time.
	var source := _sources[0]
	if RunState.move_slot(source, _cursor):
		_sources.remove_at(0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, PANEL_SIZE), Color(0.06, 0.06, 0.09, 1.0))
	draw_string(_font, Vector2(20, 34), "INVENTORY", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.9, 0.95))

	var cols := RunState.COLUMNS
	var rows := RunState.ROWS
	var grid_w := cols * CELL + (cols - 1) * GAP
	var grid_h := rows * CELL + (rows - 1) * GAP
	var origin := Vector2((PANEL_SIZE.x - grid_w) * 0.5, 58)

	for i in RunState.slot_count():
		var c := i % cols
		var r := i / cols
		var cell := Rect2(origin + Vector2(c * (CELL + GAP), r * (CELL + GAP)), Vector2(CELL, CELL))
		_draw_cell(i, cell)

	# Info line for the slot under the cursor.
	draw_string(_font, Vector2(20, origin.y + grid_h + 40), _cursor_info(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.95, 0.7))
	var hint := "[WASD] move   [Space] select / drop one   select matching items to stack   [I]/[Esc] close"
	draw_string(_font, Vector2(20, PANEL_SIZE.y - 16), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.7, 0.75))


func _draw_cell(index: int, cell: Rect2) -> void:
	var slot := RunState.get_slot(index)
	var kind := String(slot.get("kind", ""))
	var bg := Color(0.12, 0.12, 0.15)
	if kind == "module":
		bg = Color(0.16, 0.22, 0.30)
	elif kind == "resource":
		bg = Color(0.20, 0.20, 0.24)
	draw_rect(cell, bg)

	if kind == "resource":
		var id := String(slot.id)
		var tex := ContentLibrary.get_icon(GameData.resource_icon(id), Vector2i(16, 16), GameData.resource_color(id))
		draw_texture_rect(tex, cell.grow(-10), false)
	elif kind == "module":
		var def: Dictionary = GameData.recyclers.get(String(slot.id), {})
		var tex := ContentLibrary.get_icon(String(def.get("icon", slot.id)), Vector2i(16, 16))
		draw_texture_rect(tex, cell.grow(-10), false)
		# Buffer count + a small progress bar.
		var buffer := int(slot.get("buffer", 0))
		var need := int(def.get("input_amount", 1))
		draw_string(_font, cell.position + Vector2(4, 14), "%d/%d" % [buffer, need], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1))
		var ratio := clampf(float(slot.get("progress", 0.0)) / maxf(0.01, float(def.get("seconds", 3.0))), 0.0, 1.0)
		draw_rect(Rect2(cell.position + Vector2(4, CELL - 8), Vector2((CELL - 8) * ratio, 4)), Color(0.4, 0.9, 0.5))

	if _sources.has(index):
		draw_rect(cell.grow(1), Color(1.0, 0.85, 0.2), false, 2.0)
	if index == _cursor:
		draw_rect(cell.grow(2), Color.WHITE, false, 2.0)


func _cursor_info() -> String:
	if not _sources.is_empty():
		var selected := RunState.get_slot(_sources[0])
		if selected.get("kind", "") == "resource":
			return "%s x%d selected — Space drops one" % [
				GameData.resource_name(String(selected.get("id", ""))), _sources.size()]
	var slot := RunState.get_slot(_cursor)
	var kind := String(slot.get("kind", ""))
	if kind == "resource":
		return GameData.resource_name(String(slot.id))
	if kind == "module":
		var def: Dictionary = GameData.recyclers.get(String(slot.id), {})
		return "%s: %s -> %s  (buffer %d/%d)" % [
			String(def.get("name", slot.id)),
			GameData.resource_name(String(def.get("input", ""))),
			GameData.resource_name(String(def.get("output", ""))),
			int(slot.get("buffer", 0)), int(def.get("input_amount", 1))]
	if not _sources.is_empty():
		return "Move here"
	return "Empty"
