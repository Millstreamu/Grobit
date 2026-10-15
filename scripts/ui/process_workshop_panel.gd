class_name ProcessWorkshopPanel
extends Control
## Phase 4 Workshop editor — build PROCESS CHAINS. Place verb-machines (Heater/Presser/Molder/Folder),
## drop one or more scrap INTAKES, and line the ports up so scrap flows machine-to-machine. Each intake
## is its own LINE running in parallel; a line's ordered verbs + its intake scrap resolve to a product
## (shown live), and making a new one logs it in the recipe book. No conveyors — misaligned ports = a
## dead line. Drives a ProcessGrid.
##
## Controls: [WASD] cursor · [Tab] pick tool (Intake / verbs / Erase) · [Space] place/apply · [R] rotate
## (machine under cursor, else placement facing) · [Enter] cycle the intake's scrap · [Esc] close.

const PANEL := Vector2(640, 448)
const COLS := 8
const ROWS := 6
const CELL := 34.0
const GAP := 3.0
const ORIGIN := Vector2(14, 72)
const RX := 320.0
const TOOLS := ["__intake", "heat", "press", "mold", "fold", "__erase"]
const SCRAPS := ["steel_scrap", "copper_scrap", "plastic_scrap", "ceramic_scrap"]
const ARROWS := {Vector2i(1, 0): "▶", Vector2i(-1, 0): "◀", Vector2i(0, 1): "▼", Vector2i(0, -1): "▲"}

var grid: ProcessGrid
var _cursor := Vector2i.ZERO
var _tool_i := 0
var _out_dir := Vector2i(1, 0)
var _intake_scrap := "steel_scrap"   # scrap the NEXT placed intake uses (and shown in the header)
var _message := ""
var _opened_frame := -1
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2.ZERO
	size = PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = ThemeDB.fallback_font
	if grid == null:
		grid = ProcessGrid.new(COLS, ROWS)


func is_open() -> bool:
	return visible


func open(g: ProcessGrid = null) -> void:
	if g != null:
		grid = g
	elif grid == null:
		grid = ProcessGrid.new(COLS, ROWS)
	_cursor = Vector2i.ZERO
	_message = ""
	# Re-opening a saved layout: default the placement scrap to the first line's scrap.
	if grid.has_intake():
		var s := String(grid.intakes[0].get("scrap", ""))
		if SCRAPS.has(s):
			_intake_scrap = s
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
	_move_cursor()
	if Input.is_action_just_pressed("cycle_target"):
		_tool_i = (_tool_i + 1) % TOOLS.size()
	if Input.is_action_just_pressed("reshuffle"):
		_rotate()
	if Input.is_action_just_pressed("confirm"):
		var e := grid.intake_at(_cursor)
		if not e.is_empty():
			e["scrap"] = _next_scrap(String(e.get("scrap", "")))   # re-type the intake under the cursor
			_intake_scrap = String(e["scrap"])
		else:
			_intake_scrap = _next_scrap(_intake_scrap)             # change what the next intake will use
	if Input.is_action_just_pressed("attack"):
		_apply()


func _next_scrap(s: String) -> String:
	var i := SCRAPS.find(s)
	return SCRAPS[(i + 1) % SCRAPS.size()] if i >= 0 else SCRAPS[0]


func _move_cursor() -> void:
	var s := Vector2i.ZERO
	if Input.is_action_just_pressed("move_up"): s.y -= 1
	if Input.is_action_just_pressed("move_down"): s.y += 1
	if Input.is_action_just_pressed("move_left"): s.x -= 1
	if Input.is_action_just_pressed("move_right"): s.x += 1
	var c := _cursor + s
	if grid.in_bounds(c):
		_cursor = c


## [R]: rotate the machine under the cursor, or (on an empty cell) the placement facing.
func _rotate() -> void:
	if not grid.machine_at(_cursor).is_empty():
		grid.rotate(_cursor)
	else:
		_out_dir = Vector2i(-_out_dir.y, _out_dir.x)  # 90° CW


func _apply() -> void:
	var tool: String = TOOLS[_tool_i]
	if tool == "__erase":
		grid.remove(_cursor)   # removes a machine and/or an intake on this cell
		return
	if tool == "__intake":
		grid.set_intake(_cursor, _out_dir, _intake_scrap)
		_message = "Intake — %s flows %s." % [GameData.resource_name(_intake_scrap), String(ARROWS.get(_out_dir, "?"))]
		return
	# A process machine: straight-through (in faces back from out). Fails on an occupied cell.
	if not grid.machine_at(_cursor).is_empty():
		_message = "Cell occupied — [R] to rotate it, or erase first."
		return
	if not grid.intake_at(_cursor).is_empty():
		_message = "That's an intake cell."
		return
	grid.place(tool, _cursor, -_out_dir, _out_dir)


# ---------------------------------------------------------------- draw ----

func _cell_rect(p: Vector2i) -> Rect2:
	return Rect2(ORIGIN + Vector2(p.x * (CELL + GAP), p.y * (CELL + GAP)), Vector2(CELL, CELL))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, PANEL), Color(0.06, 0.07, 0.1, 0.98))
	draw_string(_font, Vector2(14, 30), "WORKSHOP — process lines", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.6, 0.82, 1.0))
	draw_string(_font, Vector2(14, 52), "Next intake: %s  ([Enter] change)   Lines: %d" % [GameData.resource_name(_intake_scrap), grid.intake_count()], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.88, 0.95))

	var chain := grid.chain_cells()
	var out_cells: Dictionary = {}
	for e: Dictionary in grid.intakes:
		var oc := grid.output_cell(e)
		if oc != Vector2i(-1, -1):
			out_cells[oc] = true
	# Grid + contents.
	for y in ROWS:
		for x in COLS:
			var p := Vector2i(x, y)
			var r := _cell_rect(p)
			draw_rect(r, Color(0.12, 0.13, 0.17))
			if p in chain:
				draw_rect(r, Color(0.3, 0.9, 0.5, 0.16))  # cells a live chain runs through
			var m := grid.machine_at(p)
			if not m.is_empty():
				_draw_machine(r, m)
			var intake := grid.intake_at(p)
			if not intake.is_empty():
				_draw_intake(r, intake)
			if out_cells.has(p):
				draw_rect(r.grow(-6), Color(0.5, 1.0, 0.7, 0.5), false, 2.0)
				draw_string(_font, r.position + Vector2(3, 13), "OUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 1.0, 0.75))

	# Cursor + placement ghost.
	var cr := _cell_rect(_cursor)
	draw_rect(cr.grow(2), Color.WHITE, false, 2.0)
	var tool: String = TOOLS[_tool_i]
	if (tool != "__erase") and grid.machine_at(_cursor).is_empty() and grid.intake_at(_cursor).is_empty():
		draw_string(_font, cr.position + Vector2(CELL * 0.5 - 6, CELL * 0.5 + 8), String(ARROWS.get(_out_dir, "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 0.6, 0.8))

	_draw_right()
	draw_string(_font, Vector2(14, PANEL.y - 26), _message, HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 28, 12, Color(1, 0.92, 0.7))
	draw_string(_font, Vector2(14, PANEL.y - 8), "[WASD] move  [Tab] tool  [Space] place  [R] rotate  [Enter] scrap  [Esc] close", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.62, 0.64, 0.7))


func _draw_machine(r: Rect2, m: Dictionary) -> void:
	var verb := String(m.get("verb", ""))
	var def: Dictionary = GameData.process_verbs.get(verb, {})
	var tex := ContentLibrary.get_icon(String(def.get("icon", "proc_" + verb)), Vector2i(24, 24), String(def.get("color", "")))
	draw_texture_rect(tex, r.grow(-5), false)
	draw_string(_font, r.position + Vector2(r.size.x - 12, 12), String(ARROWS.get(Vector2i(m.get("out_dir", Vector2i.RIGHT)), "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 1.0, 0.7))
	draw_string(_font, r.position + Vector2(2, r.size.y - 4), String(ARROWS.get(Vector2i(m.get("in_dir", Vector2i.LEFT)), "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.7, 1.0))


func _draw_intake(r: Rect2, intake: Dictionary) -> void:
	var scrap := String(intake.get("scrap", ""))
	draw_rect(r, Color(0.16, 0.2, 0.14))
	draw_rect(r.grow(-2), Color(GameData.resource_color(scrap), 0.7), false, 2.0)
	draw_texture_rect(ContentLibrary.get_icon(GameData.resource_icon(scrap), Vector2i(18, 18), GameData.resource_color(scrap)), r.grow(-8), false)
	draw_string(_font, r.position + Vector2(r.size.x - 12, 12), String(ARROWS.get(Vector2i(intake.get("dir", Vector2i.ZERO)), "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.9, 0.5))


func _draw_right() -> void:
	var x := RX + 10
	var w := PANEL.x - RX - 24
	draw_line(Vector2(RX, 24), Vector2(RX, PANEL.y - 34), Color(0.2, 0.22, 0.28), 1.0)
	# Tool palette.
	draw_string(_font, Vector2(x, 40), "Tool", HORIZONTAL_ALIGNMENT_LEFT, w, 13, Color(0.8, 0.85, 0.92))
	for i in TOOLS.size():
		var ty := 52.0 + i * 18.0
		if i == _tool_i:
			draw_rect(Rect2(x - 2, ty - 1, w, 17), Color(1, 1, 1, 0.12))
		draw_string(_font, Vector2(x + 4, ty + 12), _tool_label(String(TOOLS[i])), HORIZONTAL_ALIGNMENT_LEFT, w, 12, _tool_color(String(TOOLS[i])))
	# Per-line readout: each intake → its product.
	var yy := 164.0
	draw_string(_font, Vector2(x, yy), "Lines", HORIZONTAL_ALIGNMENT_LEFT, w, 13, Color(0.8, 0.85, 0.92))
	yy += 16.0
	if grid.intakes.is_empty():
		draw_string(_font, Vector2(x, yy), "(place an intake)", HORIZONTAL_ALIGNMENT_LEFT, w, 11, Color(0.6, 0.63, 0.7))
		yy += 16.0
	for e: Dictionary in grid.intakes:
		if yy > 300.0:
			break
		var seq := grid.trace_sequence(e)
		var recipe := grid.product_recipe(e)
		var prod := "—" if recipe.is_empty() else GameData.resource_name(String(recipe.get("product", "")))
		var col := Color(0.6, 1.0, 0.7) if not recipe.is_empty() else Color(0.9, 0.62, 0.55)
		var seq_txt: String = "→".join(seq) if not seq.is_empty() else "(dead)"
		draw_string(_font, Vector2(x, yy), "%s: %s" % [_scrap_short(String(e.get("scrap", ""))), seq_txt], HORIZONTAL_ALIGNMENT_LEFT, w, 11, Color(0.82, 0.86, 0.78))
		draw_string(_font, Vector2(x, yy + 13), "  → %s" % prod, HORIZONTAL_ALIGNMENT_LEFT, w, 12, col)
		yy += 30.0
	# Recipe book.
	draw_string(_font, Vector2(x, yy + 4), "Recipe book", HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.8, 0.85, 0.92))
	var by := yy + 20.0
	for r: Dictionary in MetaState.known_recipes():
		if by > PANEL.y - 38:
			break
		var line := "%s: %s → %s" % [_scrap_short(String(r.get("scrap", ""))), "→".join(r.get("sequence", [])), GameData.resource_name(String(r.get("product", "")))]
		draw_string(_font, Vector2(x, by), line, HORIZONTAL_ALIGNMENT_LEFT, w, 10, Color(0.75, 0.8, 0.88))
		by += 14.0


func _scrap_short(id: String) -> String:
	return GameData.resource_name(id).replace(" Scrap", "")


func _tool_label(t: String) -> String:
	match t:
		"__intake": return "▦ Intake (scrap in)"
		"__erase": return "✖ Erase"
	return "▣ " + String(GameData.process_verbs.get(t, {}).get("name", t))


func _tool_color(t: String) -> Color:
	if t.begins_with("__"):
		return Color(0.85, 0.88, 0.95)
	return Color.from_string("#" + String(GameData.process_verbs.get(t, {}).get("color", "cccccc")), Color(0.8, 0.8, 0.8))
