class_name FactoryGrid
extends RefCounted
## The inventory-factory data model (Step 0 of the inventory-factory redesign — see
## docs/SLICE_1_SCOPE.md). A `cols`×`rows` grid of cells; machines placed on it
## process resources in real time. Pure logic, no scene/UI — so it can be unit
## tested headless and later driven by the inventory panel.
##
## Coordinates are Vector2i(x, y) with x = column, y = row.
##
## Cell shapes:
##   {}                                     -> empty
##   {"kind":"resource", "id":<res_id>}     -> one resource item
##   {"kind":"machine", "mi":<index>}       -> a machine's CORE cell
##
## A machine occupies exactly one core cell. Its `inputs` and `output` name nearby
## cells (offsets from the core) that it reads/writes; those cells are ordinary grid
## cells that may hold resource items. Because a machine writes its product into the
## `output` cell and another machine can read from that same cell as one of its
## `inputs`, placing an output cell against the next input cell makes items flow
## automatically (adjacency auto-chaining) with natural back-pressure: a full output
## cell blocks the machine until it is cleared.

## Each level makes a recipe machine process this much faster (multiplies seconds).
const SPEED_PER_LEVEL := 0.8
## Extra slot cells claimed per level-up (RNG-shaped, must fit — no rotation).
const SLOTS_PER_LEVEL := 2
## Seconds between conveyor/splitter transport steps (item moves one cell per step).
const CONVEYOR_INTERVAL := 0.35

var cols: int
var rows: int
var cells: Array = []      # flat, size cols*rows, each a Dictionary
var machines: Array = []   # each: {def_id, core:Vector2i, progress, working, level, slots}
var _transport_accum := 0.0


func _init(grid_cols: int, grid_rows: int) -> void:
	cols = grid_cols
	rows = grid_rows
	cells.resize(cols * rows)
	for i in cells.size():
		cells[i] = {}


# ------------------------------------------------------------- cells ----

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < cols and p.y < rows


func _index(p: Vector2i) -> int:
	return p.y * cols + p.x


func get_cell(p: Vector2i) -> Dictionary:
	if not in_bounds(p):
		return {}
	return cells[_index(p)]


func set_cell(p: Vector2i, value: Dictionary) -> void:
	if in_bounds(p):
		cells[_index(p)] = value


func is_core(p: Vector2i) -> bool:
	return get_cell(p).get("kind", "") == "machine"


## A cell claimed by a machine (its core or one of its extra slot cells) — nothing
## else may be placed/dropped there.
func is_machine_cell(p: Vector2i) -> bool:
	var kind := String(get_cell(p).get("kind", ""))
	return kind == "machine" or kind == "machine_slot"


# --------------------------------------------------------- machines ----

func _v(offset: Variant) -> Vector2i:
	return Vector2i(int(offset[0]), int(offset[1]))


## Absolute positions of a machine's input cells, in `inputs` order.
func input_positions(m: Dictionary) -> Array:
	var def: Dictionary = GameData.machines.get(String(m.get("def_id", "")), {})
	var out: Array = []
	for offset: Variant in def.get("inputs", []):
		out.append(Vector2i(m.core) + _v(offset))
	return out


## Absolute positions of a machine's output cells (products are distributed across
## whichever are free). Supports multi-output machines (recycler, separator).
func output_positions(m: Dictionary) -> Array:
	var def: Dictionary = GameData.machines.get(String(m.get("def_id", "")), {})
	var out: Array = []
	for offset: Variant in def.get("outputs", []):
		out.append(Vector2i(m.core) + _v(offset))
	return out


## The primary output cell (for the direction arrow) — the first output, or the core.
func output_position(m: Dictionary) -> Vector2i:
	var outs := output_positions(m)
	return outs[0] if not outs.is_empty() else Vector2i(m.core)


## Absolute positions of an arm's holding cells (empty for machines without any).
func holding_positions(m: Dictionary) -> Array:
	var def: Dictionary = GameData.machines.get(String(m.get("def_id", "")), {})
	var out: Array = []
	for offset: Variant in def.get("holding", []):
		out.append(Vector2i(m.core) + _v(offset))
	return out


## True if `def_id` can be placed with its core at `core`: the core cell is empty
## and every referenced cell (inputs / output / holding) is in bounds and not
## another machine's core. No rotation — the footprint is used as authored.
func can_place(def_id: String, core: Vector2i) -> bool:
	if not in_bounds(core) or not get_cell(core).is_empty():
		return false
	var def: Dictionary = GameData.machines.get(def_id, {})
	if def.is_empty():
		return false
	var referenced: Array = []
	for offset: Variant in def.get("inputs", []):
		referenced.append(_v(offset))
	for offset: Variant in def.get("outputs", []):
		referenced.append(_v(offset))
	for offset: Variant in def.get("holding", []):
		referenced.append(_v(offset))
	for offset: Vector2i in referenced:
		var p := core + offset
		if not in_bounds(p) or is_machine_cell(p):
			return false
	return true


## Places a machine; returns its index, or -1 if it doesn't fit.
func place_machine(def_id: String, core: Vector2i) -> int:
	if not can_place(def_id, core):
		return -1
	machines.append({"def_id": def_id, "core": core, "progress": 0.0, "working": false, "level": 1, "slots": [], "modules": [], "status": "idle", "status_detail": ""})
	var mi := machines.size() - 1
	set_cell(core, {"kind": "machine", "mi": mi})
	return mi


## Picks a machine up off the grid (clears its core + slot cells; its modules free
## up, level resets). Returns its def_id so the caller can return it to stock. The
## machine entry becomes a tombstone so existing cell 'mi' indices stay valid.
func pickup_machine(mi: int) -> String:
	if mi < 0 or mi >= machines.size():
		return ""
	var m: Dictionary = machines[mi]
	if bool(m.get("removed", false)):
		return ""
	var did := String(m.get("def_id", ""))
	set_cell(Vector2i(m.core), {})
	for p: Variant in m.get("slots", []):
		set_cell(Vector2i(p), {})
	machines[mi] = {"removed": true}
	return did


# ------------------------------------------------------- leveling ----

## Index of the machine whose CORE sits at `p`, or -1.
func machine_at(p: Vector2i) -> int:
	var cell := get_cell(p)
	if cell.get("kind", "") == "machine":
		return int(cell.mi)
	return -1


func level_of(mi: int) -> int:
	return int(machines[mi].get("level", 1)) if mi >= 0 and mi < machines.size() else 0


## Absolute positions of a machine's extra slot cells (claimed by leveling).
func slot_positions(m: Dictionary) -> Array:
	var out: Array = []
	for p: Variant in m.get("slots", []):
		out.append(p)
	return out


## Rolls a connected RNG-shaped blob of `count` empty cells adjacent to the
## machine's claimed body (core + existing slots). Returns the chosen absolute
## cells (fewer than `count` if the machine is boxed in). No rotation: the shape is
## whatever the roll produced; the player reshuffles or fits it as-is.
func roll_upgrade(mi: int, count: int, rng: RandomNumberGenerator) -> Array:
	var m: Dictionary = machines[mi]
	var body: Array = [Vector2i(m.core)]
	for p: Variant in m.get("slots", []):
		body.append(p)
	# Never grow into any machine's input/output/holding cells — claiming those
	# would break an assembly line. (Empty resource cells are fair game.)
	var reserved := {}
	for other: Dictionary in machines:
		if bool(other.get("removed", false)):
			continue
		for p: Vector2i in input_positions(other):
			reserved[p] = true
		for p: Vector2i in output_positions(other):
			reserved[p] = true
		for p: Vector2i in holding_positions(other):
			reserved[p] = true
	var shape: Array = []
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for _n in count:
		var frontier: Array = []
		for base: Vector2i in body + shape:
			for d: Vector2i in dirs:
				var p: Vector2i = base + d
				if in_bounds(p) and get_cell(p).is_empty() and not reserved.has(p) and not shape.has(p) and not frontier.has(p):
					frontier.append(p)
		if frontier.is_empty():
			break
		shape.append(frontier[rng.randi() % frontier.size()])
	return shape


## True if a rolled shape can be applied (right size and every cell still free).
func upgrade_fits(shape: Array, count: int) -> bool:
	if shape.size() != count:
		return false
	for p: Vector2i in shape:
		if not in_bounds(p) or not get_cell(p).is_empty():
			return false
	return true


## Claims the shape's cells for the machine and bumps its level.
func apply_upgrade(mi: int, shape: Array) -> void:
	var m: Dictionary = machines[mi]
	for p: Vector2i in shape:
		set_cell(p, {"kind": "machine_slot", "mi": mi})
		m.slots.append(p)
	m.level = int(m.get("level", 1)) + 1


# -------------------------------------------------------- modules ----

## How many of a module id are currently installed across all machines (so the UI
## can cap installs at the owned count — installed modules are never consumed, they
## free up when the factory resets each run).
func installed_count(module_id: String) -> int:
	var n := 0
	for m: Dictionary in machines:
		for entry: Dictionary in m.get("modules", []):
			if String(entry.get("id", "")) == module_id:
				n += 1
	return n


func module_at(pos: Vector2i) -> String:
	var mi := int(get_cell(pos).get("mi", -1))
	if get_cell(pos).get("kind", "") != "machine_slot" or mi < 0:
		return ""
	for entry: Dictionary in machines[mi].get("modules", []):
		if Vector2i(entry.get("pos", Vector2i.ZERO)) == pos:
			return String(entry.get("id", ""))
	return ""


## Installs a module into an empty machine_slot cell. Returns false if the cell is
## not an empty slot.
func install_module(pos: Vector2i, module_id: String) -> bool:
	var cell := get_cell(pos)
	if cell.get("kind", "") != "machine_slot":
		return false
	if not module_at(pos).is_empty():
		return false
	var mi := int(cell.mi)
	machines[mi].modules.append({"pos": pos, "id": module_id})
	return true


## Removes a module from a slot cell. Returns the removed id, or "".
func remove_module(pos: Vector2i) -> String:
	var mi := int(get_cell(pos).get("mi", -1))
	if mi < 0:
		return ""
	var mods: Array = machines[mi].get("modules", [])
	for i in mods.size():
		if Vector2i(mods[i].get("pos", Vector2i.ZERO)) == pos:
			var id := String(mods[i].get("id", ""))
			mods.remove_at(i)
			return id
	return ""


## Combined speed multiplier from a machine's installed 'speed' modules (stacks).
func _module_speed_mult(m: Dictionary) -> float:
	var mult := 1.0
	for entry: Dictionary in m.get("modules", []):
		var def: Dictionary = GameData.modules.get(String(entry.get("id", "")), {})
		if String(def.get("effect", "")) == "speed":
			mult *= float(def.get("value", 1.0))
	return mult


## Total bonus output items per craft from a machine's 'yield' modules.
func _module_yield(m: Dictionary) -> int:
	var bonus := 0
	for entry: Dictionary in m.get("modules", []):
		var def: Dictionary = GameData.modules.get(String(entry.get("id", "")), {})
		if String(def.get("effect", "")) == "yield":
			bonus += int(def.get("value", 0))
	return bonus


# ------------------------------------------------------------- tick ----

## Advances every machine by `delta` seconds. A machine runs the first recipe (for
## its type) whose needs are present across its input cells (set-based) and whose
## products all have a free output cell; otherwise it holds (blocked) or resets.
func tick(delta: float) -> void:
	for m: Dictionary in machines:
		if bool(m.get("removed", false)):
			continue
		var recipes := GameData.recipes_for(String(m.def_id))
		if recipes.is_empty():
			continue  # e.g. the scrapper arm (no recipes)

		var have := _input_multiset(m)
		var recipe: Dictionary = {}
		for r: Dictionary in recipes:
			if _needs_met(have, r.get("needs", {})):
				recipe = r
				break
		if recipe.is_empty():
			m.working = false
			m.progress = 0.0
			m.status = "idle"
			m.status_detail = _closest_missing(m, recipes)
			continue

		var free_out := _free_output_cells(m)
		var total_out := 0
		for id: String in recipe.get("produces", {}):
			total_out += int(recipe.produces[id])
		if free_out.size() < total_out:
			m.working = false  # blocked: no room for all outputs; hold progress
			m.status = "blocked"
			m.status_detail = "output full"
			continue

		m.status = "working"
		m.status_detail = ""
		var seconds := float(recipe.get("seconds", 3.0)) * pow(SPEED_PER_LEVEL, int(m.get("level", 1)) - 1) * _module_speed_mult(m)
		m.working = true
		m.progress = float(m.progress) + delta
		if m.progress >= seconds:
			_consume(m, recipe.get("needs", {}))
			var slots := _free_output_cells(m)
			var si := 0
			for id: String in recipe.get("produces", {}):
				for _n in int(recipe.produces[id]):
					if si < slots.size():
						_deliver(slots[si], id)
						si += 1
			# 'yield' modules add a bonus of each product into any free cells.
			for _y in _module_yield(m):
				for id: String in recipe.get("produces", {}):
					add_resource(id)
			m.progress = 0.0
			m.working = false

	# Conveyors/splitters carry items one cell per CONVEYOR_INTERVAL.
	_transport_accum += delta
	while _transport_accum >= CONVEYOR_INTERVAL:
		_transport_accum -= CONVEYOR_INTERVAL
		_transport_step()


## Multiset (id -> count) of resources currently in a machine's input cells.
func _input_multiset(m: Dictionary) -> Dictionary:
	var ms := {}
	for p: Vector2i in input_positions(m):
		var c := get_cell(p)
		if c.get("kind", "") == "resource":
			var id := String(c.id)
			ms[id] = int(ms.get(id, 0)) + 1
	return ms


func _needs_met(have: Dictionary, needs: Dictionary) -> bool:
	for id: String in needs:
		if int(have.get(id, 0)) < int(needs[id]):
			return false
	return true


## Consumes `needs` (id -> count) from a machine's input cells.
func _consume(m: Dictionary, needs: Dictionary) -> void:
	var left := needs.duplicate()
	for p: Vector2i in input_positions(m):
		var c := get_cell(p)
		if c.get("kind", "") != "resource":
			continue
		var id := String(c.id)
		if int(left.get(id, 0)) > 0:
			set_cell(p, {})
			left[id] = int(left[id]) - 1


## Output cells that can currently receive an item.
func _free_output_cells(m: Dictionary) -> Array:
	var out: Array = []
	for p: Vector2i in output_positions(m):
		if _can_receive(p):
			out.append(p)
	return out


## For an idle machine, the resource name it most needs (closest to completing one
## of its recipes), or "" if nothing is partially satisfiable.
func _closest_missing(m: Dictionary, recipes: Array) -> String:
	var have := _input_multiset(m)
	var best := 9999
	var name := ""
	for r: Dictionary in recipes:
		var miss := 0
		var first := ""
		for id: String in r.get("needs", {}):
			var lack := int(r.needs[id]) - int(have.get(id, 0))
			if lack > 0:
				miss += lack
				if first == "":
					first = id
		if miss > 0 and miss < best:
			best = miss
			name = first
	return GameData.resource_name(name) if name != "" else ""


## Human-readable status for the machine whose core is at `pos` ("" if none / arm).
func status_at(pos: Vector2i) -> String:
	var mi := machine_at(pos)
	if mi < 0:
		return ""
	var m: Dictionary = machines[mi]
	match String(m.get("status", "")):
		"working":
			return "working"
		"blocked":
			return "blocked (%s)" % String(m.get("status_detail", ""))
		"idle":
			var d := String(m.get("status_detail", ""))
			return "waiting — needs %s" % d if d != "" else "idle"
	return "idle"


# ------------------------------------------------------ arm intake ----

## Drops a harvested item into the first free holding cell of a machine that has
## holding cells (the scrapper arm). Returns false if there is no room (arm full).
func deposit_harvest(id: String) -> bool:
	for m: Dictionary in machines:
		for p: Vector2i in holding_positions(m):
			if get_cell(p).is_empty():
				set_cell(p, {"kind": "resource", "id": id})
				return true
	return false


## Drops one resource item into a free cell (scanning from the bottom-right so loose
## drops tend to stay clear of the arm/machines clustered near the top-left).
## Returns false if the grid is full.
func add_resource(id: String) -> bool:
	for i in range(cells.size() - 1, -1, -1):
		if cells[i].is_empty():
			cells[i] = {"kind": "resource", "id": id}
			return true
	return false


## Removes up to `count` items of a resource from the grid. Returns how many went.
func remove_resource(id: String, count: int) -> int:
	var removed := 0
	for i in cells.size():
		if removed >= count:
			break
		var cell: Dictionary = cells[i]
		if cell.get("kind", "") == "resource" and String(cell.get("id", "")) == id:
			cells[i] = {}
			removed += 1
	return removed


func has_empty() -> bool:
	for cell: Dictionary in cells:
		if cell.is_empty():
			return true
	return false


## Counts of every resource item in the grid (id -> count), including items riding
## conveyors/splitters, for HUD/readouts.
func resource_counts() -> Dictionary:
	var counts := {}
	for cell: Dictionary in cells:
		var kind := String(cell.get("kind", ""))
		if kind == "resource":
			var id := String(cell.id)
			counts[id] = int(counts.get(id, 0)) + 1
		elif (kind == "conveyor" or kind == "splitter") and String(cell.get("item", "")) != "":
			var cid := String(cell.item)
			counts[cid] = int(counts.get(cid, 0)) + 1
	return counts


# ----------------------------------------------------- conveyors ----

## A cell that can accept an item right now: an empty cell, or a conveyor/splitter
## whose carry slot is free.
func _can_receive(pos: Vector2i) -> bool:
	if not in_bounds(pos):
		return false
	var c := get_cell(pos)
	if c.is_empty():
		return true
	var kind := String(c.get("kind", ""))
	return (kind == "conveyor" or kind == "splitter") and String(c.get("item", "")) == ""


## Puts an item into a cell: an empty cell becomes a resource; a conveyor/splitter
## takes it onto its carry slot. Caller must have checked _can_receive.
func _deliver(pos: Vector2i, id: String) -> void:
	var c := get_cell(pos)
	if c.is_empty():
		set_cell(pos, {"kind": "resource", "id": id})
	else:
		c["item"] = id  # c is the stored dict reference


func place_conveyor(pos: Vector2i, dir: Vector2i) -> bool:
	if not in_bounds(pos) or not get_cell(pos).is_empty():
		return false
	set_cell(pos, {"kind": "conveyor", "dir": dir, "item": ""})
	return true


## A splitter alternates its output between `dir` and its 90°-CW perpendicular.
func place_splitter(pos: Vector2i, dir: Vector2i) -> bool:
	if not in_bounds(pos) or not get_cell(pos).is_empty():
		return false
	var dir2 := Vector2i(-dir.y, dir.x)
	set_cell(pos, {"kind": "splitter", "dir": dir, "dir2": dir2, "item": "", "toggle": false})
	return true


## Advances every conveyor/splitter by one cell where possible. Each carried item
## moves at most once per step (movers are snapshotted up front).
func _transport_step() -> void:
	var movers: Array = []
	for i in cells.size():
		var c: Dictionary = cells[i]
		var kind := String(c.get("kind", ""))
		if (kind == "conveyor" or kind == "splitter") and String(c.get("item", "")) != "":
			movers.append(i)
	for i: int in movers:
		var c: Dictionary = cells[i]
		var pos := Vector2i(i % cols, i / cols)
		var id := String(c.item)
		var targets: Array = []
		if String(c.get("kind", "")) == "splitter":
			if bool(c.get("toggle", false)):
				targets = [pos + Vector2i(c.dir2), pos + Vector2i(c.dir)]
			else:
				targets = [pos + Vector2i(c.dir), pos + Vector2i(c.dir2)]
		else:
			targets = [pos + Vector2i(c.dir)]
		for tgt: Vector2i in targets:
			if _can_receive(tgt):
				_deliver(tgt, id)
				c["item"] = ""
				if String(c.get("kind", "")) == "splitter":
					c["toggle"] = not bool(c.get("toggle", false))
				break


## Number of free holding cells across all arms — how many more items can be taken.
func harvest_space() -> int:
	var n := 0
	for m: Dictionary in machines:
		for p: Vector2i in holding_positions(m):
			if get_cell(p).is_empty():
				n += 1
	return n
