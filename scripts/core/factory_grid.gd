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

## Extra slot cells claimed per level-up (RNG-shaped, must fit — no rotation).
## (Leveling no longer grows slots in-game; kept for the grid slot API + its test.)
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


## How many items a resource cell holds (stacks store a "count"; default 1). Non-resource
## cells hold 0.
func cell_count(c: Dictionary) -> int:
	if String(c.get("kind", "")) == "resource":
		return int(c.get("count", 1))
	return 0


## Removes one item from a resource cell, clearing it when the stack empties.
func _take_one(p: Vector2i) -> void:
	var c := get_cell(p)
	if String(c.get("kind", "")) != "resource":
		return
	var n := int(c.get("count", 1)) - 1
	if n <= 0:
		set_cell(p, {})
	else:
		c["count"] = n


func is_core(p: Vector2i) -> bool:
	return get_cell(p).get("kind", "") == "machine"


## A cell claimed by a machine — its core, an extra body tile, or a level slot.
## Nothing else may be placed/dropped there.
func is_machine_cell(p: Vector2i) -> bool:
	var kind := String(get_cell(p).get("kind", ""))
	return kind == "machine" or kind == "machine_slot" or kind == "machine_body"


## How many tiles a machine's core occupies — the more ports (complexity), the bigger.
## An explicit `core_size` in the def overrides the derived value.
func core_size_of(def_id: String) -> int:
	var def: Dictionary = GameData.machines.get(def_id, {})
	if def.has("core_size"):
		return maxi(1, int(def.core_size))
	var ports := (def.get("inputs", []) as Array).size() + (def.get("outputs", []) as Array).size()
	return clampi(ports - 1, 1, 4)  # 1–2 ports = 1 tile, 3 = 2, 4+ = 3


## A machine's extra body offsets (beyond the core), from the rolled layout.
func body_offsets_of(m: Dictionary) -> Array:
	return m.get("body_offsets", [])


# --------------------------------------------------------- machines ----

func _v(offset: Variant) -> Vector2i:
	return Vector2i(int(offset[0]), int(offset[1]))


## A machine's input offsets: the per-instance layout rolled when it was built (see
## roll_machine_layout), or the authored def offsets as a fallback (arm, tests).
func in_offsets_of(m: Dictionary) -> Array:
	if m.has("in_offsets"):
		return m["in_offsets"]
	var def: Dictionary = GameData.machines.get(String(m.get("def_id", "")), {})
	var out: Array = []
	for offset: Variant in def.get("inputs", []):
		out.append(_v(offset))
	return out


func out_offsets_of(m: Dictionary) -> Array:
	if m.has("out_offsets"):
		return m["out_offsets"]
	var def: Dictionary = GameData.machines.get(String(m.get("def_id", "")), {})
	var out: Array = []
	for offset: Variant in def.get("outputs", []):
		out.append(_v(offset))
	return out


## Absolute positions of a machine's input cells.
func input_positions(m: Dictionary) -> Array:
	var out: Array = []
	for offset: Vector2i in in_offsets_of(m):
		out.append(Vector2i(m.core) + offset)
	return out


## Absolute positions of a machine's output cells (products are distributed across
## whichever are free). Supports multi-output machines (recycler, separator).
func output_positions(m: Dictionary) -> Array:
	var out: Array = []
	for offset: Vector2i in out_offsets_of(m):
		out.append(Vector2i(m.core) + offset)
	return out


## The primary output cell (for the direction arrow) — the first output, or the core.
func output_position(m: Dictionary) -> Vector2i:
	var outs := output_positions(m)
	return outs[0] if not outs.is_empty() else Vector2i(m.core)


## An arm's holding offsets: the per-instance layout rolled when it was built, or the
## authored def offsets as a fallback (pre-placed arm, tests).
func hold_offsets_of(m: Dictionary) -> Array:
	if m.has("hold_offsets"):
		return m["hold_offsets"]
	var def: Dictionary = GameData.machines.get(String(m.get("def_id", "")), {})
	var out: Array = []
	for offset: Variant in def.get("holding", []):
		out.append(_v(offset))
	return out


## Absolute positions of an arm's holding cells (empty for machines without any).
func holding_positions(m: Dictionary) -> Array:
	var out: Array = []
	for offset: Vector2i in hold_offsets_of(m):
		out.append(Vector2i(m.core) + offset)
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


## Like can_place, but a loose item on the core cell is allowed — it gets shifted
## aside when the machine is placed (as long as there is a free cell to hold it).
func can_place_displacing(def_id: String, core: Vector2i) -> bool:
	if String(get_cell(core).get("kind", "")) != "resource":
		return can_place(def_id, core)
	if not has_empty():
		return false  # nowhere to shift the covered item
	# Temporarily treat the core as empty to reuse the normal check.
	var saved: Dictionary = get_cell(core)
	set_cell(core, {})
	var ok := can_place(def_id, core)
	set_cell(core, saved)
	return ok


## Rolls a random layout for a freshly-built machine: a connected BODY blob of
## core_size tiles (more complex machines are bigger), then its input/output/holding
## ports placed on tiles orthogonally adjacent to that body. Returns offsets relative
## to the core: {body_offsets, in_offsets, out_offsets, hold_offsets}. Like leveling,
## each build is a spatial roll — the body shape and port sides land differently.
func roll_machine_layout(def_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var def: Dictionary = GameData.machines.get(def_id, {})
	var n_in := (def.get("inputs", []) as Array).size()
	var n_out := (def.get("outputs", []) as Array).size()
	var n_hold := (def.get("holding", []) as Array).size()
	var total := n_in + n_out + n_hold
	# Body blob (includes the core at ZERO); its extra tiles are body_offsets.
	var body := _grow_blob(rng, core_size_of(def_id))
	var body_extra := body.slice(1, body.size())
	# Ports go on the body's perimeter (orthogonal neighbours not in the body).
	var perim := _perimeter(body)
	for i in range(perim.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: Vector2i = perim[i]
		perim[i] = perim[j]
		perim[j] = tmp
	var chosen := perim.slice(0, mini(total, perim.size()))
	return {
		"body_offsets": body_extra,
		"in_offsets": chosen.slice(0, n_in),
		"out_offsets": chosen.slice(n_in, mini(n_in + n_out, chosen.size())),
		"hold_offsets": chosen.slice(mini(n_in + n_out, chosen.size()), chosen.size()),
	}


## A connected blob of `count` offsets starting at ZERO (the core), grown orthogonally.
func _grow_blob(rng: RandomNumberGenerator, count: int) -> Array:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var blob: Array = [Vector2i.ZERO]
	while blob.size() < count:
		var frontier: Array = []
		for base: Vector2i in blob:
			for d: Vector2i in dirs:
				var o := base + d
				if not blob.has(o) and not frontier.has(o):
					frontier.append(o)
		if frontier.is_empty():
			break
		blob.append(frontier[rng.randi() % frontier.size()])
	return blob


## Cells orthogonally adjacent to any cell in `blob`, excluding the blob itself.
func _perimeter(blob: Array) -> Array:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var out: Array = []
	for base: Vector2i in blob:
		for d: Vector2i in dirs:
			var o := base + d
			if not blob.has(o) and not out.has(o):
				out.append(o)
	return out


## can_place for a rolled layout (offsets given rather than read from the def). Loose
## items on the body tiles are allowed (shifted aside on place).
func can_place_layout(def_id: String, core: Vector2i, in_offsets: Array, out_offsets: Array, hold_offsets: Array = [], body_offsets: Array = []) -> bool:
	if not in_bounds(core):
		return false
	var covered := 0
	# Body tiles (core + extras) must land on empty/displaceable cells.
	for offset: Vector2i in [Vector2i.ZERO] + body_offsets:
		var p := core + offset
		if not in_bounds(p):
			return false
		var kk := String(get_cell(p).get("kind", ""))
		if kk == "resource":
			covered += 1
		elif kk != "":
			return false
	if covered > 0 and count_empty() < covered:
		return false  # nowhere to shift the items the body would cover
	# Port cells must be in bounds and off any machine.
	for offset: Vector2i in in_offsets + out_offsets + hold_offsets:
		var p := core + offset
		if not in_bounds(p) or is_machine_cell(p):
			return false
	return true


## Count of empty cells (for displacement checks).
func count_empty() -> int:
	var n := 0
	for cell: Dictionary in cells:
		if cell.is_empty():
			n += 1
	return n


## Places a machine with a rolled port layout (see roll_machine_layout), storing the
## layout on the instance. Returns its index, or -1 if it doesn't fit. An item on the
## core is shifted aside.
func place_machine_layout(def_id: String, core: Vector2i, in_offsets: Array, out_offsets: Array, hold_offsets: Array = [], body_offsets: Array = []) -> int:
	if not can_place_layout(def_id, core, in_offsets, out_offsets, hold_offsets, body_offsets):
		return -1
	machines.append({"def_id": def_id, "core": core, "progress": 0.0, "progress_ratio": 0.0, "working": false, "level": 1, "slots": [], "modules": [], "status": "idle", "status_detail": "", "in_offsets": in_offsets.duplicate(), "out_offsets": out_offsets.duplicate(), "hold_offsets": hold_offsets.duplicate(), "body_offsets": body_offsets.duplicate()})
	var mi := machines.size() - 1
	# Shift aside any items under the body, then claim the tiles (core + extras).
	for offset: Vector2i in [Vector2i.ZERO] + body_offsets:
		var p := core + offset
		if String(get_cell(p).get("kind", "")) == "resource":
			displace_item(p)
		set_cell(p, {"kind": "machine" if offset == Vector2i.ZERO else "machine_body", "mi": mi})
	return mi


## Places a machine; returns its index, or -1 if it doesn't fit. An item on the core
## cell is shifted aside rather than blocking the placement.
func place_machine(def_id: String, core: Vector2i) -> int:
	if String(get_cell(core).get("kind", "")) == "resource":
		if not can_place_displacing(def_id, core) or not displace_item(core):
			return -1
	if not can_place(def_id, core):
		return -1
	machines.append({"def_id": def_id, "core": core, "progress": 0.0, "progress_ratio": 0.0, "working": false, "level": 1, "slots": [], "modules": [], "status": "idle", "status_detail": ""})
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
	for offset: Vector2i in body_offsets_of(m):
		set_cell(Vector2i(m.core) + offset, {})
	for p: Variant in m.get("slots", []):
		set_cell(Vector2i(p), {})
	machines[mi] = {"removed": true}
	return did


# ------------------------------------------------------- leveling ----

## Index of the machine occupying `p` (its core or any body tile), or -1. Level and
## move act on the machine from any of its body tiles, not just the core.
func machine_at(p: Vector2i) -> int:
	var cell := get_cell(p)
	var kind := String(cell.get("kind", ""))
	if kind == "machine" or kind == "machine_body":
		return int(cell.mi)
	return -1


func level_of(mi: int) -> int:
	return int(machines[mi].get("level", 1)) if mi >= 0 and mi < machines.size() else 0


## Raises a machine's level by one IN PLACE — no footprint/slot change, no relocation.
## (Leveling used to grow the machine's slot shape; now it just bumps the number. What a
## higher level does beyond the current speed-up / recipe-gating is still to be designed.)
func level_up_in_place(mi: int) -> int:
	if mi < 0 or mi >= machines.size():
		return 0
	machines[mi]["level"] = level_of(mi) + 1
	return level_of(mi)


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


## Rolls the level-up's new slots as a connected blob of OFFSETS relative to the
## machine's core (attached to its body: core + existing slots), avoiding the
## machine's own input/output offsets. Unlike roll_upgrade this ignores the grid's
## current occupancy — it is a rigid shape the player then positions somewhere it
## fits (see can_relocate / relocate_upgraded), so a boxed-in machine can level by
## relocating instead of being stuck.
func roll_upgrade_offsets(mi: int, count: int, rng: RandomNumberGenerator) -> Array:
	var m: Dictionary = machines[mi]
	var body := {Vector2i.ZERO: true}
	for o: Vector2i in body_offsets_of(m):
		body[o] = true
	for p: Variant in m.get("slots", []):
		body[Vector2i(p) - Vector2i(m.core)] = true
	var reserved := {}  # never put a slot on an input/output offset
	for offset: Vector2i in in_offsets_of(m) + out_offsets_of(m):
		reserved[offset] = true
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var shape: Array = []
	for _n in count:
		var frontier: Array = []
		for base_v: Variant in body.keys() + shape:
			var base: Vector2i = base_v
			for d: Vector2i in dirs:
				var o := base + d
				if not body.has(o) and not reserved.has(o) and not shape.has(o) and not frontier.has(o):
					frontier.append(o)
		if frontier.is_empty():
			break
		shape.append(frontier[rng.randi() % frontier.size()])
	return shape


## Absolute cells a machine's solid footprint would occupy at `new_core`: the core,
## its extra body tiles, and its level slots.
func _relocate_footprint(new_core: Vector2i, slot_offsets: Array, body_offsets: Array = []) -> Dictionary:
	var footprint := {new_core: true}
	for o: Vector2i in slot_offsets:
		footprint[new_core + o] = true
	for o: Vector2i in body_offsets:
		footprint[new_core + o] = true
	return footprint


## True if machine `mi` (with the given full slot offsets) can be dropped with its
## core at `new_core`: body cells land on empty/its-own/displaceable-item cells,
## input/output cells stay in bounds and off other machines, and there is room to
## shift aside any items the body would cover.
func can_relocate(mi: int, new_core: Vector2i, slot_offsets: Array) -> bool:
	if mi < 0 or mi >= machines.size():
		return false
	var m: Dictionary = machines[mi]
	if bool(m.get("removed", false)):
		return false
	var own := {Vector2i(m.core): true}
	for p: Variant in m.get("slots", []):
		own[Vector2i(p)] = true
	for o: Vector2i in body_offsets_of(m):
		own[Vector2i(m.core) + o] = true
	var footprint := _relocate_footprint(new_core, slot_offsets, body_offsets_of(m))
	var displaced := 0
	for p: Vector2i in footprint:
		if not in_bounds(p):
			return false
		if own.has(p):
			continue
		var kind := String(get_cell(p).get("kind", ""))
		if kind == "resource":
			displaced += 1
		elif kind != "":
			return false  # any other machine/body/slot/transport blocks
	# Input/output/holding cells: in bounds and not on another machine (items are fine).
	var ports: Array = in_offsets_of(m) + out_offsets_of(m) + hold_offsets_of(m)
	for offset: Vector2i in ports:
		var p := new_core + offset
		if not in_bounds(p):
			return false
		if not own.has(p) and is_machine_cell(p):
			return false
	# Room to shift covered items aside: free cells outside the footprint, plus the
	# machine's own cells being vacated (they free up when it moves).
	if displaced > 0:
		var room := 0
		for y in rows:
			for x in cols:
				var q := Vector2i(x, y)
				if footprint.has(q):
					continue
				if get_cell(q).is_empty() or own.has(q):
					room += 1
		if room < displaced:
			return false
	return true


## Moves machine `mi` to `new_core`, claiming the given full slot offsets as its
## slots and bumping its level. Existing slots (and their modules) translate rigidly
## by the move delta; items under the new body are shifted to free cells. Caller must
## have checked can_relocate.
func relocate_upgraded(mi: int, new_core: Vector2i, slot_offsets: Array) -> void:
	_relocate(mi, new_core, slot_offsets)
	var m: Dictionary = machines[mi]
	m.level = int(m.get("level", 1)) + 1


## Moves machine `mi` to `new_core` keeping its current slots (and their modules) and
## its level — a plain relocation, no upgrade. Caller must have checked can_relocate
## with the machine's existing slot offsets (see move_offsets).
func move_machine(mi: int, new_core: Vector2i) -> void:
	_relocate(mi, new_core, move_offsets(mi))


## A machine's existing slot cells as offsets relative to its core (the shape a plain
## move keeps).
func move_offsets(mi: int) -> Array:
	var m: Dictionary = machines[mi]
	var out: Array = []
	for p: Variant in m.get("slots", []):
		out.append(Vector2i(p) - Vector2i(m.core))
	return out


## Shared relocation: vacates the old body, shifts aside covered items, lays the body
## at `new_core` with the given slot offsets, and remaps module positions by the move
## delta. Does NOT change the level (callers decide).
func _relocate(mi: int, new_core: Vector2i, slot_offsets: Array) -> void:
	var m: Dictionary = machines[mi]
	var old_core := Vector2i(m.core)
	var delta := new_core - old_core
	var body_offsets: Array = body_offsets_of(m)
	var footprint := _relocate_footprint(new_core, slot_offsets, body_offsets)
	# Vacate the old body (core + extras + slots) first so it can overlap the new spot.
	set_cell(old_core, {})
	for o: Vector2i in body_offsets:
		set_cell(old_core + o, {})
	for p: Variant in m.get("slots", []):
		set_cell(Vector2i(p), {})
	# Shift aside any items the new footprint would cover.
	for p: Vector2i in footprint:
		if String(get_cell(p).get("kind", "")) == "resource":
			var id := String(get_cell(p).id)
			set_cell(p, {})
			_add_resource_avoiding(id, footprint)
	# Lay the new body and remap module positions by the move delta.
	m.core = new_core
	set_cell(new_core, {"kind": "machine", "mi": mi})
	for o: Vector2i in body_offsets:
		set_cell(new_core + o, {"kind": "machine_body", "mi": mi})
	m.slots = []
	for o: Vector2i in slot_offsets:
		var p := new_core + o
		set_cell(p, {"kind": "machine_slot", "mi": mi})
		m.slots.append(p)
	for entry: Dictionary in m.get("modules", []):
		entry["pos"] = Vector2i(entry.get("pos", Vector2i.ZERO)) + delta


## Places a resource in the first free cell not in `avoid` (scanning bottom-right).
func _add_resource_avoiding(id: String, avoid: Dictionary) -> bool:
	var mx := GameData.stack_max(id)
	if mx > 1:
		for i in cells.size():
			var c: Dictionary = cells[i]
			if String(c.get("kind", "")) == "resource" and String(c.get("id", "")) == id and int(c.get("count", 1)) < mx and not avoid.has(Vector2i(i % cols, i / cols)):
				c["count"] = int(c.get("count", 1)) + 1
				return true
	for i in range(cells.size() - 1, -1, -1):
		if not cells[i].is_empty():
			continue
		var p := Vector2i(i % cols, i / cols)
		if avoid.has(p):
			continue
		cells[i] = {"kind": "resource", "id": id, "count": 1}
		return true
	return false


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
		var mdef: Dictionary = GameData.machines.get(String(m.def_id), {})
		if int(mdef.get("capacity", 0)) > 0:
			_cache_absorb(m, int(mdef.capacity))  # storage cache: stack items from its input
			continue
		var recipes := GameData.recipes_for(String(m.def_id))
		if recipes.is_empty():
			m.status = ""  # e.g. the scrapper arm (no recipes → no status/progress)
			continue

		var have := _input_multiset(m)
		var level := int(m.get("level", 1))
		var recipe: Dictionary = {}
		for r: Dictionary in recipes:
			# Higher-tier recipes are gated behind machine level (data-driven 'level').
			if level >= int(r.get("level", 1)) and _needs_met(have, r.get("needs", {})):
				recipe = r
				break
		if recipe.is_empty():
			m.working = false
			m.progress = 0.0
			m.progress_ratio = 0.0
			m.status = "idle"
			m.status_detail = _closest_missing(m, recipes)
			continue

		# Level no longer affects speed — leveling is a blank capability for now (its effect
		# is still to be designed). Modules can still change craft time.
		var seconds := float(recipe.get("seconds", 3.0)) * _module_speed_mult(m)
		m.progress_ratio = clampf(float(m.progress) / maxf(0.01, seconds), 0.0, 1.0)

		# Blocked unless every product can land (an empty output cell, or a same-id output
		# stack with room).
		if not _can_place_products(m, recipe.get("produces", {})):
			m.working = false
			m.status = "blocked"
			m.status_detail = "output full"
			continue

		m.status = "working"
		m.status_detail = ""
		m.working = true
		m.progress = float(m.progress) + delta
		if m.progress >= seconds:
			_consume(m, recipe.get("needs", {}))
			_place_products(m, recipe.get("produces", {}))
			# 'yield' modules add a bonus of each product into any free/stackable cells.
			for _y in _module_yield(m):
				for id: String in recipe.get("produces", {}):
					add_resource(id)
			m.progress = 0.0
			m.working = false

	# Conveyors/splitters carry items one cell per CONVEYOR_INTERVAL; arms trickle a
	# held item out to their (clear) output at the same cadence — a built-in conveyor.
	_transport_accum += delta
	while _transport_accum >= CONVEYOR_INTERVAL:
		_transport_accum -= CONVEYOR_INTERVAL
		_transport_step()
		_arm_feed_step()
		_inserter_step()


## Multiset (id -> count) of resources currently in a machine's input cells.
func _input_multiset(m: Dictionary) -> Dictionary:
	var ms := {}
	for p: Vector2i in input_positions(m):
		var c := get_cell(p)
		if c.get("kind", "") == "resource":
			var id := String(c.id)
			ms[id] = int(ms.get(id, 0)) + int(c.get("count", 1))
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
			var take := mini(int(left[id]), int(c.get("count", 1)))
			var rem := int(c.get("count", 1)) - take
			if rem <= 0:
				set_cell(p, {})
			else:
				c["count"] = rem
			left[id] = int(left[id]) - take


## Output cells that can currently receive an item (empty or a transport slot).
func _free_output_cells(m: Dictionary) -> Array:
	var out: Array = []
	for p: Vector2i in output_positions(m):
		if _can_receive(p):
			out.append(p)
	return out


## An output cell that can take one unit of `id` — a same-id stack with room, or an empty
## cell — honoring `reserved` (pos -> {id, count}) so a dry-run can fit several units.
func _find_output_slot(m: Dictionary, id: String, reserved: Dictionary) -> Vector2i:
	for p: Vector2i in output_positions(m):
		var c := get_cell(p)
		if String(c.get("kind", "")) == "resource" and String(c.id) == id:
			var r: Dictionary = reserved.get(p, {})
			if int(c.get("count", 1)) + int(r.get("count", 0)) < GameData.stack_max(id):
				return p
	for p: Vector2i in output_positions(m):
		var c := get_cell(p)
		if c.is_empty():
			var r: Dictionary = reserved.get(p, {})
			if r.is_empty():
				return p
			if String(r.get("id", "")) == id and int(r.get("count", 0)) < GameData.stack_max(id):
				return p
	# A conveyor/splitter/filter at an output can carry one item away (not stackable).
	for p: Vector2i in output_positions(m):
		var c := get_cell(p)
		if _is_transport_kind(String(c.get("kind", ""))) and String(c.get("item", "")) == "" and not reserved.has(p):
			return p
	return Vector2i(-1, -1)


## Dry-run: can every produced unit be placed (stacking included)?
func _can_place_products(m: Dictionary, produces: Dictionary) -> bool:
	var reserved := {}
	for id: String in produces:
		for _n in int(produces[id]):
			var p := _find_output_slot(m, id, reserved)
			if p == Vector2i(-1, -1):
				return false
			var r: Dictionary = reserved.get(p, {"id": id, "count": 0})
			r["id"] = id
			r["count"] = int(r.get("count", 0)) + 1
			reserved[p] = r
	return true


## Delivers every produced unit into output cells (stacking onto same-id cells).
func _place_products(m: Dictionary, produces: Dictionary) -> void:
	for id: String in produces:
		for _n in int(produces[id]):
			var p := _find_output_slot(m, id, {})  # live grid; previous unit already landed
			if p != Vector2i(-1, -1):
				_deliver(p, id)


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
	return ""  # recipe-less machine (e.g. the arm)


# ------------------------------------------------------ arm intake ----

## Drops a harvested item into the first free holding cell of a machine that has
## holding cells (the scrapper arm). Returns false if there is no room (arm full).
func deposit_harvest(id: String) -> bool:
	for m: Dictionary in machines:
		for p: Vector2i in holding_positions(m):
			if get_cell(p).is_empty():
				set_cell(p, {"kind": "resource", "id": id, "count": 1})
				return true
	return false


## Drops one resource item into a free cell (scanning from the bottom-right so loose
## drops tend to stay clear of the arm/machines clustered near the top-left).
## Returns false if the grid is full.
func add_resource(id: String) -> bool:
	var mx := GameData.stack_max(id)
	# Stack onto an existing cell of the same id first (if this resource stacks).
	if mx > 1:
		for cell: Dictionary in cells:
			if String(cell.get("kind", "")) == "resource" and String(cell.get("id", "")) == id and int(cell.get("count", 1)) < mx:
				cell["count"] = int(cell.get("count", 1)) + 1
				return true
	# Otherwise a fresh cell (scan from the bottom-right so loose drops stay clear).
	for i in range(cells.size() - 1, -1, -1):
		if cells[i].is_empty():
			cells[i] = {"kind": "resource", "id": id, "count": 1}
			return true
	return false


## Removes up to `count` items of a resource from the grid (draining stacks). Returns how
## many went.
func remove_resource(id: String, count: int) -> int:
	var removed := 0
	for i in cells.size():
		if removed >= count:
			break
		var cell: Dictionary = cells[i]
		if String(cell.get("kind", "")) == "resource" and String(cell.get("id", "")) == id:
			var take := mini(count - removed, int(cell.get("count", 1)))
			var left := int(cell.get("count", 1)) - take
			if left <= 0:
				cells[i] = {}
			else:
				cell["count"] = left
			removed += take
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
			counts[id] = int(counts.get(id, 0)) + int(cell.get("count", 1))
		elif _is_transport_kind(kind) and String(cell.get("item", "")) != "":
			var cid := String(cell.item)
			counts[cid] = int(counts.get(cid, 0)) + 1
	return counts


# ----------------------------------------------------- conveyors ----

## A cell that can accept an item right now: an empty cell, or a conveyor/splitter
## whose carry slot is free.
func _can_receive(pos: Vector2i, id := "") -> bool:
	if not in_bounds(pos):
		return false
	var c := get_cell(pos)
	if c.is_empty():
		return true
	var kind := String(c.get("kind", ""))
	if _is_transport_kind(kind):
		return String(c.get("item", "")) == ""
	# A resource cell can accept more of its own id if it stacks and has room.
	return kind == "resource" and id != "" and String(c.id) == id and int(c.get("count", 1)) < GameData.stack_max(id)


## Puts an item into a cell: an empty cell becomes a resource (count 1); a matching resource
## stack grows; a conveyor/splitter takes it onto its carry slot. Caller checked _can_receive.
func _deliver(pos: Vector2i, id: String) -> void:
	var c := get_cell(pos)
	if c.is_empty():
		set_cell(pos, {"kind": "resource", "id": id, "count": 1})
	elif String(c.get("kind", "")) == "resource" and String(c.id) == id:
		c["count"] = int(c.get("count", 1)) + 1  # stack (c is the stored dict reference)
	else:
		c["item"] = id  # transport carry slot


## An item sitting where transport/machine part is going down is shifted to a free
## cell rather than blocking the placement. Returns false only if the cell holds an
## item and there is nowhere free to move it to.
func displace_item(pos: Vector2i) -> bool:
	var cell := get_cell(pos)
	if String(cell.get("kind", "")) != "resource":
		return true
	var id := String(cell.id)
	var count := int(cell.get("count", 1))
	set_cell(pos, {})
	var moved := 0
	for _i in count:
		if _add_resource_avoiding(id, {pos: true}):
			moved += 1
		else:
			break
	if moved == count:
		return true
	set_cell(pos, {"kind": "resource", "id": id, "count": count - moved})  # couldn't move all
	return false


func place_conveyor(pos: Vector2i, dir: Vector2i) -> bool:
	if not _clear_for_transport(pos):
		return false
	set_cell(pos, {"kind": "conveyor", "dir": dir, "item": ""})
	return true


## A splitter alternates its output between `dir` and its 90°-CW perpendicular.
func place_splitter(pos: Vector2i, dir: Vector2i) -> bool:
	if not _clear_for_transport(pos):
		return false
	var dir2 := Vector2i(-dir.y, dir.x)
	set_cell(pos, {"kind": "splitter", "dir": dir, "dir2": dir2, "item": "", "toggle": false})
	return true


## A filter sends its `filter_id` item out the 90° side (`dir2`) and everything else
## straight (`dir`). `filter_id` "" means it passes everything straight (set it later).
func place_filter(pos: Vector2i, dir: Vector2i, filter_id := "") -> bool:
	if not _clear_for_transport(pos):
		return false
	var dir2 := Vector2i(-dir.y, dir.x)
	set_cell(pos, {"kind": "filter", "dir": dir, "dir2": dir2, "item": "", "filter_id": filter_id})
	return true


# ----------------------------------------------------- scrap inserters ----

## A Scrap Insert point: a 2-tall source. The TOP cell is the inserter (its art); each
## step it pulls one unit of its scrap type from the Scrapper Arm bar (RunState.arm_scrap)
## and drops it into the cell directly BELOW, ready to be carried or fed into a machine.
func can_place_inserter(pos: Vector2i) -> bool:
	var below := pos + Vector2i(0, 1)
	return in_bounds(pos) and in_bounds(below) and get_cell(pos).is_empty() and get_cell(below).is_empty()


func place_inserter(pos: Vector2i, scrap_type: String) -> bool:
	if not can_place_inserter(pos):
		return false
	set_cell(pos, {"kind": "inserter", "scrap": scrap_type})
	return true


## One pull per transport step: each inserter whose output cell can take an item, and whose
## scrap type is in the arm bar, spawns one unit of that scrap below it.
func _inserter_step() -> void:
	for i in cells.size():
		var c: Dictionary = cells[i]
		if String(c.get("kind", "")) != "inserter":
			continue
		var below := Vector2i(i % cols, i / cols) + Vector2i(0, 1)
		var scrap := String(c.get("scrap", ""))
		if not _can_receive(below, scrap):
			continue
		if RunState.arm_take(scrap, 1) > 0:
			_deliver(below, scrap)


## True (and clears the cell) if a conveyor/splitter can go at `pos`: empty cells and
## item cells (item shifted aside) are fine; machine/transport cells block.
func _clear_for_transport(pos: Vector2i) -> bool:
	if not in_bounds(pos):
		return false
	var kind := String(get_cell(pos).get("kind", ""))
	if kind == "":
		return true
	if kind == "resource":
		return displace_item(pos)
	return false


## Advances every conveyor/splitter by one cell where possible. Each carried item
## A storage cache pulls items from its input cell into its internal stack (one type,
## up to `capacity`). A full cache, or a different item than it holds, leaves the input
## cell occupied (back-pressure), so conveyors/arms stop feeding it.
func _cache_absorb(m: Dictionary, capacity: int) -> void:
	var count := int(m.get("cached_count", 0))
	var cid := String(m.get("cached_id", ""))
	m.status = ""  # no progress/status dot; the count badge shows its state
	for p: Vector2i in input_positions(m):
		var c := get_cell(p)
		if String(c.get("kind", "")) != "resource":
			continue
		var rid := String(c.id)
		if count == 0:
			cid = rid
			count = 1
			_take_one(p)
		elif rid == cid and count < capacity:
			count += 1
			_take_one(p)
		# else: full, or a different type — leave the item in the input (blocked)
	m["cached_id"] = cid
	m["cached_count"] = count


## A cache machine's stored contents: {"id":String, "count":int, "capacity":int}.
func cache_state(mi: int) -> Dictionary:
	if mi < 0 or mi >= machines.size():
		return {}
	var m: Dictionary = machines[mi]
	var capacity := int(GameData.machines.get(String(m.def_id), {}).get("capacity", 0))
	if capacity <= 0:
		return {}
	return {"id": String(m.get("cached_id", "")), "count": int(m.get("cached_count", 0)), "capacity": capacity}


## Empties a cache (after its stack is shipped), returning the count that was inside.
func take_cache(mi: int) -> int:
	var m: Dictionary = machines[mi]
	var n := int(m.get("cached_count", 0))
	m["cached_count"] = 0
	m["cached_id"] = ""
	return n


# --------------------------------------------------------------- weapons ----

## Combat hook: finds the first placed weapon whose input slot holds its ammo, consumes
## one unit of it, and returns that weapon's firing stats. Returns {} when no placed weapon
## is loaded (the player then falls back to Grobit's basic built-in gun).
func try_fire_weapon() -> Dictionary:
	for m: Dictionary in machines:
		if bool(m.get("removed", false)):
			continue
		var def: Dictionary = GameData.machines.get(String(m.def_id), {})
		if not bool(def.get("weapon", false)):
			continue
		var ammo := String(def.get("ammo", ""))
		for p: Vector2i in input_positions(m):
			var c := get_cell(p)
			if String(c.get("kind", "")) == "resource" and String(c.get("id", "")) == ammo:
				_take_one(p)  # consume one unit of ammo (from the stack)
				return {
					"family": String(def.get("family", "")),
					"name": String(def.get("name", "Weapon")),
					"damage": float(def.get("damage", 2)),
					"cooldown": float(def.get("cooldown", 0.4)),
					"projectile_speed": float(def.get("projectile_speed", 400)),
					"pellets": int(def.get("pellets", 1)),       # plastic spread
					"spread_deg": float(def.get("spread_deg", 0.0)),
					"pierce": int(def.get("pierce", 0)),         # ceramic pierce
				}
	return {}


## True if any placed weapon currently has its ammo loaded (read-only, for HUD/readouts).
func has_loaded_weapon() -> bool:
	for m: Dictionary in machines:
		if bool(m.get("removed", false)):
			continue
		var def: Dictionary = GameData.machines.get(String(m.def_id), {})
		if not bool(def.get("weapon", false)):
			continue
		var ammo := String(def.get("ammo", ""))
		for p: Vector2i in input_positions(m):
			var c := get_cell(p)
			if String(c.get("kind", "")) == "resource" and String(c.get("id", "")) == ammo:
				return true
	return false


## Each arm (a machine with holding cells) moves one held item into a free output cell
## per step, so harvested junk trickles out of the arm like it's on a conveyor.
func _arm_feed_step() -> void:
	for m: Dictionary in machines:
		if bool(m.get("removed", false)):
			continue
		var holds := holding_positions(m)
		if holds.is_empty():
			continue
		var target := Vector2i(-1, -1)
		for op: Vector2i in output_positions(m):
			if _can_receive(op):
				target = op
				break
		if target == Vector2i(-1, -1):
			continue  # output blocked — hold the items
		for hp: Vector2i in holds:
			var c := get_cell(hp)
			if String(c.get("kind", "")) == "resource":
				_deliver(target, String(c.id))
				set_cell(hp, {})
				break


## moves at most once per step (movers are snapshotted up front).
func _transport_step() -> void:
	var movers: Array = []
	for i in cells.size():
		var c: Dictionary = cells[i]
		var kind := String(c.get("kind", ""))
		if _is_transport_kind(kind) and String(c.get("item", "")) != "":
			movers.append(i)
	for i: int in movers:
		var c: Dictionary = cells[i]
		var kind := String(c.get("kind", ""))
		var pos := Vector2i(i % cols, i / cols)
		var id := String(c.item)
		var targets: Array = []
		if kind == "splitter":
			if bool(c.get("toggle", false)):
				targets = [pos + Vector2i(c.dir2), pos + Vector2i(c.dir)]
			else:
				targets = [pos + Vector2i(c.dir), pos + Vector2i(c.dir2)]
		elif kind == "filter":
			# The filtered item goes out the 90° side; everything else continues straight.
			# Strict — a matching item waits rather than taking the wrong exit.
			if id == String(c.get("filter_id", "")):
				targets = [pos + Vector2i(c.dir2)]
			else:
				targets = [pos + Vector2i(c.dir)]
		else:
			targets = [pos + Vector2i(c.dir)]
		for tgt: Vector2i in targets:
			if _can_receive(tgt, id):
				_deliver(tgt, id)
				c["item"] = ""
				if kind == "splitter":
					c["toggle"] = not bool(c.get("toggle", false))
				break


func _is_transport_kind(kind: String) -> bool:
	return kind == "conveyor" or kind == "splitter" or kind == "filter"


## Number of free holding cells across all arms — how many more items can be taken.
func harvest_space() -> int:
	var n := 0
	for m: Dictionary in machines:
		for p: Vector2i in holding_positions(m):
			if get_cell(p).is_empty():
				n += 1
	return n
