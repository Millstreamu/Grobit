class_name FactoryPanel
extends Control
## Full-window view of the inventory-factory grid (Step 1 of the redesign — see
## docs/SLICE_1_SCOPE.md). Renders cells, machines (icon + output-direction arrow,
## with input/output/holding cells marked), resource items, and a keyboard cursor.
##
## Controls while open:
##   [WASD]      move cursor
##   [B]         toggle place-machine mode
##     (in place mode) [Tab] cycle machine, [Space] place, [B]/[Esc] exit place mode
##   [Space]     (not placing) pick up / drop a resource item under the cursor
##   [I]/[Esc]   close
##
## Opening pauses the world for planning; the factory keeps ticking because its
## processor runs in PROCESS_MODE_ALWAYS (wired in Step 2). Placeholder art: cells
## are flat coloured rects with the machine/resource icon until real art exists.

const PANEL_SIZE := Vector2(640, 448)
const CELL := 64.0
const GAP := 8.0
const ARROWS := {Vector2i(1, 0): "▶", Vector2i(-1, 0): "◀", Vector2i(0, 1): "▼", Vector2i(0, -1): "▲"}

var _cursor := Vector2i.ZERO
var _place_mode := false
var _place_index := 0
var _place_dir := Vector2i(1, 0)  # direction for conveyor/splitter placement
var _carried: Dictionary = {}
# Level-up sub-mode: a rolled RNG slot shape awaiting fit/confirm/reshuffle.
var _level_mode := false
var _level_mi := -1
var _level_shape: Array = []
var _level_rng := RandomNumberGenerator.new()
# Module install sub-mode: choosing which owned module to slot into a MOD cell.
var _install_mode := false
var _install_slot := Vector2i.ZERO
var _install_opts: Array = []
var _install_index := 0
var _message := ""
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2.ZERO
	size = PANEL_SIZE
	visible = false
	_font = ThemeDB.fallback_font
	if OS.has_environment("GROBIT_OPEN_FACTORY"):
		_debug_open.call_deferred()


func _debug_open() -> void:
	# Seed a couple of items so rendering/moving can be inspected before the
	# minigame (Step 3) feeds the arm for real.
	var f := RunState.factory
	if f != null:
		f.set_cell(Vector2i(1, 0), {"kind": "resource", "id": "scrap_metal"})
		f.set_cell(Vector2i(3, 3), {"kind": "resource", "id": "metal_bar"})
	open()
	var mode := OS.get_environment("GROBIT_OPEN_FACTORY")
	# GROBIT_OPEN_FACTORY=place → show placement preview for a screenshot.
	if mode == "place":
		_place_mode = true
		_cursor = Vector2i(2, 2)
	# GROBIT_OPEN_FACTORY=flow → a smelter with scrap queued, to watch it process
	# live while the panel is open (the processor ticks under pause).
	elif mode == "flow" and f != null:
		f.place_machine("smelter", Vector2i(3, 0))  # input (2,0), output (4,0)
		f.set_cell(Vector2i(2, 0), {"kind": "resource", "id": "scrap_metal"})
		_cursor = Vector2i(3, 0)  # on the machine core → status line shows
	# GROBIT_OPEN_FACTORY=level → a smelter + stock, mid level-up (shape preview).
	elif mode == "level" and f != null:
		f.place_machine("smelter", Vector2i(2, 2))
		RunState.add("scrap_metal", 4)
		_cursor = Vector2i(2, 2)
		_begin_level()


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_cursor = Vector2i.ZERO
	_place_mode = false
	_level_mode = false
	_install_mode = false
	_carried = {}
	_message = ""
	get_tree().paused = true
	queue_redraw()


func close() -> void:
	visible = false
	_place_mode = false
	_level_mode = false
	_install_mode = false
	_carried = {}
	get_tree().paused = false


func _cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for id: String in cost:
		parts.append("%d %s" % [int(cost[id]), GameData.resource_name(id)])
	return ", ".join(parts)


func _process(_delta: float) -> void:
	if not visible:
		return
	_handle_input()
	queue_redraw()


# --------------------------------------------------------------- input ----

func _handle_input() -> void:
	# Esc backs out of the active sub-mode, else closes. The [I] toggle is owned by
	# the HUD (reading the same just-pressed key here would open-then-close us).
	if Input.is_action_just_pressed("build_cancel"):
		if _install_mode:
			_install_mode = false
		elif _level_mode:
			_level_mode = false
		elif _place_mode:
			_place_mode = false
		else:
			close()
		return

	# Sub-modes own input while active.
	if _install_mode:
		_handle_install_input()
		return
	if _level_mode:
		_handle_level_input()
		return

	_move_cursor()

	if Input.is_action_just_pressed("toggle_build"):
		_place_mode = not _place_mode
		if _place_mode:
			_place_index = 0
		return

	if _place_mode:
		if Input.is_action_just_pressed("cycle_target"):
			var ids := _placeable_ids()
			if not ids.is_empty():
				_place_index = (_place_index + 1) % ids.size()
		if Input.is_action_just_pressed("reshuffle"):
			_place_dir = Vector2i(-_place_dir.y, _place_dir.x)  # rotate 90° CW
		if Input.is_action_just_pressed("attack"):
			_try_place()
		return

	if Input.is_action_just_pressed("level_up"):
		_begin_level()
		return
	if Input.is_action_just_pressed("reshuffle"):
		_pickup_machine()  # reclaim a machine to your stock (repositioning for batch play)
		return
	if Input.is_action_just_pressed("attack"):
		# On a MOD slot: install / remove a module. Otherwise move resources.
		if RunState.factory.get_cell(_cursor).get("kind", "") == "machine_slot":
			_slot_action()
		else:
			_pick_or_drop()


func _pickup_machine() -> void:
	var f := RunState.factory
	var mi := f.machine_at(_cursor)
	if mi < 0:
		return
	var did := String(f.machines[mi].get("def_id", ""))
	if did == "scrapper_arm":
		_message = "Can't pick up the Scrapper Arm."
		return
	f.pickup_machine(mi)
	RunState.add_to_stock(did)
	_message = "Picked up %s → stock (%d)." % [_part_name(did), RunState.stock_count(did)]


func _slot_action() -> void:
	var f := RunState.factory
	if not f.module_at(_cursor).is_empty():
		var removed := f.remove_module(_cursor)
		_message = "Removed %s." % GameData.modules.get(removed, {}).get("name", removed)
		return
	# Build the list of owned modules that still have an uninstalled copy.
	_install_opts.clear()
	for id: String in MetaState.modules_owned:
		if MetaState.module_count(id) - f.installed_count(id) > 0:
			_install_opts.append(id)
	if _install_opts.is_empty():
		_message = "No modules available — decode some at a station."
		return
	_install_slot = _cursor
	_install_index = 0
	_install_mode = true
	_message = ""


func _handle_install_input() -> void:
	if Input.is_action_just_pressed("move_left"):
		_install_index = maxi(_install_index - 1, 0)
	if Input.is_action_just_pressed("move_right"):
		_install_index = mini(_install_index + 1, _install_opts.size() - 1)
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("confirm"):
		var id: String = _install_opts[_install_index]
		if RunState.factory.install_module(_install_slot, id):
			_message = "Installed %s." % GameData.modules.get(id, {}).get("name", id)
		_install_mode = false


func _begin_level() -> void:
	var f := RunState.factory
	var mi := f.machine_at(_cursor)
	if mi < 0:
		_message = "Put the cursor on a machine's core to level it."
		return
	var cost := RunState.level_cost(f.level_of(mi))
	if not RunState.can_afford(cost):
		_message = "Need %s to level this machine." % _cost_text(cost)
		return
	_level_mi = mi
	_level_rng.randomize()
	_level_shape = f.roll_upgrade(mi, FactoryGrid.SLOTS_PER_LEVEL, _level_rng)
	_level_mode = true
	_message = ""


func _handle_level_input() -> void:
	var f := RunState.factory
	if Input.is_action_just_pressed("reshuffle"):
		if RunState.reshuffles > 0:
			RunState.reshuffles -= 1
			_level_shape = f.roll_upgrade(_level_mi, FactoryGrid.SLOTS_PER_LEVEL, _level_rng)
		else:
			_message = "No reshuffles left this run."
		return
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("confirm"):
		if not f.upgrade_fits(_level_shape, FactoryGrid.SLOTS_PER_LEVEL):
			_message = "The new slots don't fit — reshuffle [R] or clear space."
			return
		var cost := RunState.level_cost(f.level_of(_level_mi))
		if not RunState.spend(cost):
			_message = "Need %s to level this machine." % _cost_text(cost)
			return
		f.apply_upgrade(_level_mi, _level_shape)
		_message = "Machine leveled to %d." % f.level_of(_level_mi)
		_level_mode = false


func _move_cursor() -> void:
	var step := Vector2i.ZERO
	if Input.is_action_just_pressed("move_up"):
		step.y -= 1
	if Input.is_action_just_pressed("move_down"):
		step.y += 1
	if Input.is_action_just_pressed("move_left"):
		step.x -= 1
	if Input.is_action_just_pressed("move_right"):
		step.x += 1
	if step == Vector2i.ZERO:
		return
	var candidate := _cursor + step
	if RunState.factory != null and RunState.factory.in_bounds(candidate):
		_cursor = candidate


func _pick_or_drop() -> void:
	var f := RunState.factory
	if f == null:
		return
	var cell := f.get_cell(_cursor)
	if _carried.is_empty():
		# Pick up a loose resource item (never a machine core).
		if cell.get("kind", "") == "resource":
			_carried = cell
			f.set_cell(_cursor, {})
	else:
		# Drop onto an empty, non-core cell.
		if cell.is_empty():
			f.set_cell(_cursor, _carried)
			_carried = {}


func _try_place() -> void:
	var ids := _placeable_ids()
	if ids.is_empty():
		return
	var id: String = ids[_place_index]
	var f := RunState.factory
	# Validate the spot before spending, so a bad placement never costs resources.
	var valid := f.get_cell(_cursor).is_empty() if id.begins_with("__") else f.can_place(id, _cursor)
	if not valid:
		_message = "Can't place there."
		return
	if id == "__conveyor" or id == "__splitter":
		if not RunState.can_afford(RunState.part_cost(id)):
			_message = "Need %s." % _cost_text(RunState.part_cost(id))
			return
		RunState.spend(RunState.part_cost(id))
		if id == "__conveyor":
			f.place_conveyor(_cursor, _place_dir)
		else:
			f.place_splitter(_cursor, _place_dir)
		return  # stay in place mode to lay a line
	# A machine: place free from stock if owned, else build new for its cost.
	if RunState.stock_count(id) > 0:
		RunState.take_from_stock(id)
		f.place_machine(id, _cursor)
	else:
		var cost := RunState.part_cost(id)
		if not RunState.can_afford(cost):
			_message = "Need %s (or none in stock)." % _cost_text(cost)
			return
		RunState.spend(cost)
		f.place_machine(id, _cursor)
	_place_mode = false


func _placeable_ids() -> Array:
	# Unlocked machines (except the pre-placed arm) plus the transport parts.
	var ids: Array = []
	for id: String in GameData.machines:
		if id != "scrapper_arm" and MetaState.is_machine_unlocked(id):
			ids.append(id)
	ids.append("__conveyor")
	ids.append("__splitter")
	return ids


func _part_name(id: String) -> String:
	if id == "__conveyor":
		return "Conveyor"
	if id == "__splitter":
		return "Splitter"
	return String(GameData.machines.get(id, {}).get("name", id))


# ---------------------------------------------------------------- draw ----

func _draw() -> void:
	var f := RunState.factory
	draw_rect(Rect2(Vector2.ZERO, PANEL_SIZE), Color(0.06, 0.06, 0.09, 1.0))
	draw_string(_font, Vector2(20, 32), "FACTORY", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.9, 0.95))
	if f == null:
		return

	var grid_w := f.cols * CELL + (f.cols - 1) * GAP
	var grid_h := f.rows * CELL + (f.rows - 1) * GAP
	var origin := Vector2((PANEL_SIZE.x - grid_w) * 0.5, 56)

	# Precompute which cells are inputs / outputs / holding of some machine.
	var role := {}
	for m: Dictionary in f.machines:
		if bool(m.get("removed", false)):
			continue
		for p: Vector2i in f.input_positions(m):
			role[p] = "input"
		for p: Vector2i in f.output_positions(m):
			role[p] = "output"
		for p: Vector2i in f.holding_positions(m):
			if not role.has(p):
				role[p] = "holding"

	var preview := _preview_cells(f)

	for y in f.rows:
		for x in f.cols:
			var pos := Vector2i(x, y)
			var rect := Rect2(origin + Vector2(x * (CELL + GAP), y * (CELL + GAP)), Vector2(CELL, CELL))
			_draw_cell(f, pos, rect, String(role.get(pos, "")), preview)

	# Level-up: highlight the pending RNG slot shape (green if it fits, else red).
	if _level_mode:
		var fits := f.upgrade_fits(_level_shape, FactoryGrid.SLOTS_PER_LEVEL)
		for p: Vector2i in _level_shape:
			var r := Rect2(origin + Vector2(p.x * (CELL + GAP), p.y * (CELL + GAP)), Vector2(CELL, CELL))
			draw_rect(r, Color(0.4, 1, 0.4, 0.45) if fits else Color(1, 0.4, 0.4, 0.45))
			draw_rect(r.grow(1), Color(0.6, 1, 0.6) if fits else Color(1, 0.5, 0.5), false, 2.0)

	# Placement preview: conveyor/splitter show a direction arrow; a machine shows its
	# icon at the core plus IN/OUT labels + output arrow so its footprint reads.
	if _place_mode:
		var pid: String = _placeable_ids()[_place_index]
		if pid.begins_with("__"):
			var cr := origin + Vector2(_cursor.x * (CELL + GAP), _cursor.y * (CELL + GAP))
			draw_string(_font, cr + Vector2(CELL * 0.5 - 8, CELL * 0.5 + 8), String(ARROWS.get(_place_dir, "•")), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 0.6))
		else:
			_draw_machine_preview(f, origin, pid)

	_draw_footer(origin + Vector2(0, grid_h + 16), grid_w)


func _cell_rect(origin: Vector2, pos: Vector2i) -> Rect2:
	return Rect2(origin + Vector2(pos.x * (CELL + GAP), pos.y * (CELL + GAP)), Vector2(CELL, CELL))


## Ghosts the selected machine over its footprint at the cursor: icon on the core,
## an output arrow, and IN/OUT labels on the cells it would read from / write to.
func _draw_machine_preview(f: FactoryGrid, origin: Vector2, id: String) -> void:
	var def: Dictionary = GameData.machines.get(id, {})
	if def.is_empty() or not f.in_bounds(_cursor):
		return
	var core := _cell_rect(origin, _cursor)
	var tex := ContentLibrary.get_icon(String(def.get("icon", id)), Vector2i(30, 30), String(def.get("color", "")))
	draw_texture_rect(tex, core.grow(-13), false, Color(1, 1, 1, 0.85))
	for off: Variant in def.get("inputs", []):
		var p := _cursor + Vector2i(int(off[0]), int(off[1]))
		if f.in_bounds(p):
			draw_string(_font, _cell_rect(origin, p).position + Vector2(6, 16), "IN", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.8, 1))
	for off: Variant in def.get("outputs", []):
		var p := _cursor + Vector2i(int(off[0]), int(off[1]))
		if f.in_bounds(p):
			var r := _cell_rect(origin, p)
			draw_string(_font, r.position + Vector2(4, 16), "OUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 1, 0.7))
			draw_string(_font, r.position + Vector2(r.size.x - 18, 18), String(ARROWS.get(p - _cursor, "•")), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 1, 0.7))


func _draw_cell(f: FactoryGrid, pos: Vector2i, rect: Rect2, role: String, preview: Dictionary) -> void:
	var cell := f.get_cell(pos)
	var kind := String(cell.get("kind", ""))

	# Base colour: role tint, then machine tint.
	var bg := Color(0.12, 0.12, 0.15)
	match role:
		"input": bg = Color(0.12, 0.16, 0.24)
		"output": bg = Color(0.12, 0.22, 0.16)
		"holding": bg = Color(0.22, 0.18, 0.10)
	if kind == "machine":
		bg = Color(0.16, 0.18, 0.24)
	elif kind == "machine_slot":
		bg = Color(0.20, 0.20, 0.30)
	draw_rect(rect, bg)

	if kind == "machine":
		var m: Dictionary = f.machines[int(cell.mi)]
		var def: Dictionary = GameData.machines.get(String(m.def_id), {})
		var tex := ContentLibrary.get_icon(String(def.get("icon", m.def_id)), Vector2i(28, 28), String(def.get("color", "")))
		draw_texture_rect(tex, rect.grow(-14), false)
		# Output-direction arrow toward the machine's out cell.
		var arrow := String(ARROWS.get(f.output_position(m) - pos, "•"))
		draw_string(_font, rect.position + Vector2(rect.size.x - 18, 20), arrow, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 1, 0.7))
		# Level badge.
		draw_string(_font, rect.position + Vector2(4, rect.size.y - 6), "L%d" % f.level_of(int(cell.mi)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.9, 0.5))
		# Status dot: green = working, amber = blocked, grey = idle/waiting.
		var st := String(f.machines[int(cell.mi)].get("status", ""))
		var dot := Color(0.5, 0.5, 0.55)
		if st == "working":
			dot = Color(0.4, 0.9, 0.5)
		elif st == "blocked":
			dot = Color(0.95, 0.75, 0.3)
		draw_rect(Rect2(rect.position + Vector2(rect.size.x - 15, rect.size.y - 15), Vector2(9, 9)), dot)
	elif kind == "machine_slot":
		var mod := f.module_at(pos)
		if mod != "":
			var mdef: Dictionary = GameData.modules.get(mod, {})
			var mtex := ContentLibrary.get_icon(String(mdef.get("icon", mod)), Vector2i(24, 24), String(mdef.get("color", "")))
			draw_texture_rect(mtex, rect.grow(-16), false)
		else:
			draw_rect(rect.grow(-22), Color(0.35, 0.35, 0.5), false, 2.0)
			draw_string(_font, rect.position + Vector2(6, 16), "MOD", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.6, 0.75))
	elif kind == "conveyor" or kind == "splitter":
		draw_rect(rect, Color(0.10, 0.13, 0.13))
		var a1 := String(ARROWS.get(Vector2i(cell.get("dir", Vector2i.RIGHT)), "•"))
		draw_string(_font, rect.position + Vector2(6, rect.size.y - 8), a1, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.45, 0.75, 0.75))
		if kind == "splitter":
			var a2 := String(ARROWS.get(Vector2i(cell.get("dir2", Vector2i.DOWN)), "•"))
			draw_string(_font, rect.position + Vector2(rect.size.x - 22, rect.size.y - 8), a2, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.75, 0.6, 0.45))
		var carried := String(cell.get("item", ""))
		if carried != "":
			var itex := ContentLibrary.get_icon(GameData.resource_icon(carried), Vector2i(16, 16), GameData.resource_color(carried))
			draw_texture_rect(itex, rect.grow(-20), false)
	elif kind == "resource":
		var id := String(cell.id)
		var tex := ContentLibrary.get_icon(GameData.resource_icon(id), Vector2i(16, 16), GameData.resource_color(id))
		draw_texture_rect(tex, rect.grow(-16), false)

	# Small role label so footprints read at a glance.
	if role != "" and kind != "machine":
		draw_string(_font, rect.position + Vector2(4, 14), role.substr(0, 3).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.75, 0.8))

	# Placement preview overlay.
	if preview.has(pos):
		draw_rect(rect, Color(0.4, 1, 0.4, 0.30) if preview[pos] else Color(1, 0.4, 0.4, 0.30))

	if pos == _cursor:
		draw_rect(rect.grow(2), Color.WHITE, false, 2.0)


# Cells the previewed machine would occupy → true if placement is currently valid.
func _preview_cells(f: FactoryGrid) -> Dictionary:
	var out := {}
	if not _place_mode:
		return out
	var ids := _placeable_ids()
	if ids.is_empty():
		return out
	var id: String = ids[_place_index]
	var afford := RunState.can_afford(RunState.part_cost(id))
	if not id.begins_with("__") and RunState.stock_count(id) > 0:
		afford = true  # free from stock
	if id.begins_with("__"):  # conveyor / splitter occupy a single empty cell
		out[_cursor] = f.get_cell(_cursor).is_empty() and afford
		return out
	var def: Dictionary = GameData.machines.get(id, {})
	var ok := f.can_place(id, _cursor) and afford
	out[_cursor] = ok
	for key: String in ["inputs", "outputs", "holding"]:
		var raw: Variant = def.get(key, [])
		var list: Array = raw if raw is Array and (raw.is_empty() or raw[0] is Array) else [raw]
		for offset: Variant in list:
			out[_cursor + Vector2i(int(offset[0]), int(offset[1]))] = ok
	return out


func _draw_footer(pos: Vector2, width: float) -> void:
	if _place_mode:
		_draw_place_info(pos, width)
		return

	var line := ""
	if _install_mode:
		var id: String = _install_opts[_install_index] if not _install_opts.is_empty() else ""
		var mdef: Dictionary = GameData.modules.get(id, {})
		line = "INSTALL: %s — %s   [A/D] choose   [Space] install   [Esc] cancel" % [
			String(mdef.get("name", id)), String(mdef.get("desc", ""))]
	elif _level_mode:
		var f := RunState.factory
		var cost := RunState.level_cost(f.level_of(_level_mi))
		line = "LEVEL UP (%s)   [Space] confirm   [R] reshuffle (%d left)   [Esc] cancel" % [_cost_text(cost), RunState.reshuffles]
	elif not _carried.is_empty():
		line = "Carrying %s   [Space] drop   [I]/[Esc] close" % GameData.resource_name(String(_carried.get("id", "")))
	else:
		# On a machine core, show its live status; otherwise the general controls.
		var f := RunState.factory
		var st := f.status_at(_cursor) if f != null else ""
		if st != "":
			var mi := f.machine_at(_cursor)
			var col := Color(0.6, 1, 0.7) if st == "working" else (Color(1, 0.85, 0.45) if st.begins_with("blocked") else Color(0.85, 0.85, 0.7))
			draw_string(_font, pos, "%s L%d — %s     [L] level   [R] pick up" % [_part_name(String(f.machines[mi].def_id)), f.level_of(mi), st], HORIZONTAL_ALIGNMENT_LEFT, width, 14, col)
			return
		line = "[WASD] move   [Space] item/module   [L] level   [R] pick up machine   [B] build   [I]/[Esc] close"
	draw_string(_font, pos, line, HORIZONTAL_ALIGNMENT_LEFT, width, 14, Color(0.8, 0.8, 0.85))
	if _message != "":
		draw_string(_font, pos + Vector2(0, 20), _message, HORIZONTAL_ALIGNMENT_LEFT, width, 13, Color(1, 0.95, 0.7))


## Multi-line place-mode info: icon + name + cost/stock, what it makes, and controls.
func _draw_place_info(pos: Vector2, width: float) -> void:
	var id: String = _placeable_ids()[_place_index]
	# Header: icon + name + cost/stock/validity.
	var name := _part_name(id)
	var tag := ""
	if id.begins_with("__"):
		tag = "cost %s" % _cost_text(RunState.part_cost(id))
	elif RunState.stock_count(id) > 0:
		tag = "in stock: %d (free)" % RunState.stock_count(id)
	else:
		tag = "build cost %s" % _cost_text(RunState.part_cost(id))
	var x := pos.x
	if not id.begins_with("__"):
		var def: Dictionary = GameData.machines.get(id, {})
		var tex := ContentLibrary.get_icon(String(def.get("icon", id)), Vector2i(18, 18), String(def.get("color", "")))
		draw_texture_rect(tex, Rect2(pos.x, pos.y - 2, 18, 18), false)
		x = pos.x + 24
	draw_string(_font, Vector2(x, pos.y + 13), "%s   —   %s" % [name, tag], HORIZONTAL_ALIGNMENT_LEFT, width, 15, Color(0.92, 0.92, 0.96))

	# What it does (cap at 2 lines so tall recipe lists don't overflow the panel).
	var y := pos.y + 32
	var makes := _makes_lines(id)
	for i in mini(makes.size(), 2):
		var desc: String = makes[i]
		if i == 1 and makes.size() > 2:
			desc += "   (+%d more)" % (makes.size() - 2)
		draw_string(_font, Vector2(pos.x, y), desc, HORIZONTAL_ALIGNMENT_LEFT, width, 12, Color(0.72, 0.82, 0.78))
		y += 16

	var rot := "   [R] rotate" if id.begins_with("__") else ""
	draw_string(_font, Vector2(pos.x, pos.y + 76), "[Tab] cycle   [WASD] move   [Space] place%s   [B]/[Esc] cancel" % rot, HORIZONTAL_ALIGNMENT_LEFT, width, 12, Color(0.7, 0.7, 0.75))
	if _message != "":
		draw_string(_font, Vector2(pos.x, pos.y + 92), _message, HORIZONTAL_ALIGNMENT_LEFT, width, 12, Color(1, 0.95, 0.7))


## Human-readable "what this places does" lines: recipes for a machine, or a note.
func _makes_lines(id: String) -> Array:
	if id == "__conveyor":
		return ["Carries items one cell along its arrow (bridges gaps between machines)."]
	if id == "__splitter":
		return ["Sends items alternately to two outputs (its arrow + 90° from it)."]
	var lines: Array = []
	for r: Dictionary in GameData.recipes_for(id):
		lines.append("Makes:  %s  →  %s" % [_ingredients(r.get("needs", {})), _ingredients(r.get("produces", {}))])
	if lines.is_empty():
		lines.append("Receives harvested items.")
	return lines


func _ingredients(items: Dictionary) -> String:
	var parts: Array = []
	for res: String in items:
		var n := int(items[res])
		parts.append(("%d× %s" % [n, GameData.resource_name(res)]) if n > 1 else GameData.resource_name(res))
	return " + ".join(parts)
