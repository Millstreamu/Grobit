class_name ProcessGrid
extends RefCounted
## The production model (Phase 4). Generic process-verb machines (heat/press/mold/fold) are wired into
## CHAINS: scrap enters at an INTAKE and is handed machine-to-machine ONLY where an out port meets the
## next machine's in port — no conveyors, so a misaligned chain is simply dead. The ORDERED verb
## sequence along a chain + its input scrap type decides the product (data-driven; see
## GameData.process_product). It's fluid — rearrange and it makes whatever the new order produces.
##
## MULTI-LINE (Phase 4 economy swap): one grid holds SEVERAL intakes, each its own independent chain,
## ticking in parallel (like the old parallel recyclers). Each intake is a dict
## {pos, dir, scrap, progress, status}. An item leaving a cell travelling `d` arrives at the next cell
## from the `-d` side, so that cell's machine must have in_dir == -d to accept it.

var cols: int
var rows: int
var intakes: Array = []           # each: {pos:Vector2i, dir:Vector2i, scrap:String, progress:float, status:String}
var _machines: Dictionary = {}    # Vector2i pos -> {verb, in_dir, out_dir}

var status := "idle"              # aggregate across lines: working | blocked | idle (for simple readouts)


func _init(c: int, r: int) -> void:
	cols = c
	rows = r


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < cols and p.y >= 0 and p.y < rows


# -------------------------------------------------------------- intakes ----

## Adds a scrap intake at `pos` feeding `scrap` out in `out_dir` (scrap enters the cell at pos+out_dir),
## or re-points the intake already on that cell. Leave `scrap` empty to lay an intake with no type yet.
func set_intake(pos: Vector2i, out_dir: Vector2i, scrap := "") -> void:
	var e := intake_at(pos)
	if e.is_empty():
		intakes.append({"pos": pos, "dir": out_dir, "scrap": scrap, "progress": 0.0, "status": "idle"})
	else:
		e["dir"] = out_dir
		e["scrap"] = scrap


func intake_at(pos: Vector2i) -> Dictionary:
	for e: Dictionary in intakes:
		if Vector2i(e.get("pos", Vector2i(-1, -1))) == pos:
			return e
	return {}


func has_intake() -> bool:
	return not intakes.is_empty()


func intake_count() -> int:
	return intakes.size()


## The first intake (convenience for single-line callers/tests), or {} if there are none.
func first_intake() -> Dictionary:
	return intakes[0] if not intakes.is_empty() else {}


func remove_intake(pos: Vector2i) -> void:
	for i in intakes.size():
		if Vector2i(intakes[i].get("pos", Vector2i(-1, -1))) == pos:
			intakes.remove_at(i)
			return


# ------------------------------------------------------------- machines ----

## Places a process machine. Fails if out of bounds or the cell is taken.
func place(verb: String, pos: Vector2i, in_dir: Vector2i, out_dir: Vector2i) -> bool:
	if not in_bounds(pos) or _machines.has(pos):
		return false
	_machines[pos] = {"verb": verb, "in_dir": in_dir, "out_dir": out_dir}
	return true


## Removes whatever is on a cell — a machine and/or an intake.
func remove(pos: Vector2i) -> void:
	_machines.erase(pos)
	remove_intake(pos)


func machine_at(pos: Vector2i) -> Dictionary:
	return _machines.get(pos, {})


func machine_count() -> int:
	return _machines.size()


## Rotates a placed machine 90° clockwise (straight-through: in stays opposite out). No-op on empty.
func rotate(pos: Vector2i) -> void:
	if not _machines.has(pos):
		return
	var m: Dictionary = _machines[pos]
	var o := Vector2i(m.get("out_dir", Vector2i(1, 0)))
	var no := Vector2i(-o.y, o.x)  # 90° CW
	m["out_dir"] = no
	m["in_dir"] = -no


# ----------------------------------------------------- per-line tracing ----

## Walks one intake's chain and returns its ordered verbs, following ONLY aligned ports. Stops at the
## first break (empty cell, misaligned port, edge, or a loop).
func trace_sequence(intake: Dictionary) -> Array:
	var seq: Array = []
	if intake.is_empty():
		return seq
	var travel := Vector2i(intake.get("dir", Vector2i.ZERO))
	var cur := Vector2i(intake.get("pos", Vector2i.ZERO)) + travel
	var seen: Dictionary = {}
	while in_bounds(cur) and _machines.has(cur) and not seen.has(cur):
		seen[cur] = true
		var m: Dictionary = _machines[cur]
		if Vector2i(m.get("in_dir", Vector2i.ZERO)) != -travel:
			break
		seq.append(String(m.get("verb", "")))
		travel = Vector2i(m.get("out_dir", Vector2i.ZERO))
		if travel == Vector2i.ZERO:
			break
		cur = cur + travel
	return seq


## The cell where one line's finished product drops out (one past the last machine), or (-1,-1).
func output_cell(intake: Dictionary) -> Vector2i:
	if intake.is_empty():
		return Vector2i(-1, -1)
	var travel := Vector2i(intake.get("dir", Vector2i.ZERO))
	var cur := Vector2i(intake.get("pos", Vector2i.ZERO)) + travel
	var seen: Dictionary = {}
	while in_bounds(cur) and _machines.has(cur) and not seen.has(cur):
		seen[cur] = true
		var m: Dictionary = _machines[cur]
		if Vector2i(m.get("in_dir", Vector2i.ZERO)) != -travel:
			return Vector2i(-1, -1)
		travel = Vector2i(m.get("out_dir", Vector2i.ZERO))
		if travel == Vector2i.ZERO:
			return Vector2i(-1, -1)
		cur = cur + travel
	return cur


## Every machine cell any live line runs through (for highlighting). Unions all lines.
func chain_cells() -> Array:
	var out: Array = []
	for e: Dictionary in intakes:
		var travel := Vector2i(e.get("dir", Vector2i.ZERO))
		var cur := Vector2i(e.get("pos", Vector2i.ZERO)) + travel
		var seen: Dictionary = {}
		while in_bounds(cur) and _machines.has(cur) and not seen.has(cur):
			seen[cur] = true
			var m: Dictionary = _machines[cur]
			if Vector2i(m.get("in_dir", Vector2i.ZERO)) != -travel:
				break
			if not out.has(cur):
				out.append(cur)
			travel = Vector2i(m.get("out_dir", Vector2i.ZERO))
			if travel == Vector2i.ZERO:
				break
			cur = cur + travel
	return out


## The product one line makes (the full recipe, or {} if its sequence makes nothing).
func product_recipe(intake: Dictionary) -> Dictionary:
	return GameData.process_recipe(String(intake.get("scrap", "")), trace_sequence(intake))


func product_for(intake: Dictionary) -> String:
	return GameData.process_product(String(intake.get("scrap", "")), trace_sequence(intake))


func progress_ratio(intake: Dictionary) -> float:
	var recipe := product_recipe(intake)
	if recipe.is_empty():
		return 0.0
	return clampf(float(intake.get("progress", 0.0)) / maxf(float(recipe.get("seconds", 2.5)), 0.01), 0.0, 1.0)


# --------------------------------------------------------------- running ----

## Advances EVERY line by `delta` against inventory `inv` (needs get_quantity(id)/add(id,n)). Each valid,
## fed line consumes one scrap and makes one product per cycle. Returns true if ANY line produced this
## tick. Updates each line's `status` and the aggregate `status`. Ticked at the lair only (FactoryProcessor).
func tick(delta: float, inv: Object) -> bool:
	var produced := false
	var any_working := false
	var any_blocked := false
	for e: Dictionary in intakes:
		if _tick_line(e, delta, inv):
			produced = true
		match String(e.get("status", "idle")):
			"working": any_working = true
			"blocked": any_blocked = true
	status = "working" if any_working else ("blocked" if any_blocked else "idle")
	return produced


func _tick_line(e: Dictionary, delta: float, inv: Object) -> bool:
	var scrap := String(e.get("scrap", ""))
	var recipe := GameData.process_recipe(scrap, trace_sequence(e))
	if scrap == "" or recipe.is_empty():
		e["status"] = "idle"
		e["progress"] = 0.0
		return false
	if inv.get_quantity(scrap) <= 0:
		e["status"] = "blocked"
		return false
	e["status"] = "working"
	e["progress"] = float(e.get("progress", 0.0)) + delta
	var secs := maxf(float(recipe.get("seconds", 2.5)), 0.01)
	if float(e["progress"]) < secs:
		return false
	e["progress"] = 0.0
	if inv.get_quantity(scrap) <= 0:
		e["status"] = "blocked"
		return false
	var product := String(recipe.get("product", ""))
	inv.add(scrap, -1)
	inv.add(product, 1)
	MetaState.discover_recipe(product)  # first make logs it in the recipe book (hybrid)
	return true


# ----------------------------------------------------------- persistence ----
# Serialized via var_to_str in MetaState (Vector2i can't go through JSON) so the lines survive runs.

func to_data() -> Dictionary:
	var machs: Dictionary = {}
	for pos: Vector2i in _machines:
		var m: Dictionary = _machines[pos]
		machs[pos] = {"verb": String(m.get("verb", "")), "in_dir": Vector2i(m.get("in_dir", Vector2i.LEFT)), "out_dir": Vector2i(m.get("out_dir", Vector2i.RIGHT))}
	var ins: Array = []
	for e: Dictionary in intakes:
		ins.append({"pos": Vector2i(e.get("pos", Vector2i(-1, -1))), "dir": Vector2i(e.get("dir", Vector2i.ZERO)), "scrap": String(e.get("scrap", ""))})
	return {"cols": cols, "rows": rows, "intakes": ins, "machines": machs}


static func from_data(data: Dictionary) -> ProcessGrid:
	var g := ProcessGrid.new(int(data.get("cols", 8)), int(data.get("rows", 6)))
	var machs: Dictionary = data.get("machines", {})
	for pos: Variant in machs:
		var m: Dictionary = machs[pos]
		g._machines[Vector2i(pos)] = {"verb": String(m.get("verb", "")), "in_dir": Vector2i(m.get("in_dir", Vector2i.LEFT)), "out_dir": Vector2i(m.get("out_dir", Vector2i.RIGHT))}
	if data.has("intakes"):
		for e: Variant in data.get("intakes", []):
			g.intakes.append({"pos": Vector2i(e.get("pos", Vector2i(-1, -1))), "dir": Vector2i(e.get("dir", Vector2i.ZERO)), "scrap": String(e.get("scrap", "")), "progress": 0.0, "status": "idle"})
	elif data.has("intake_pos"):  # migrate an old single-intake blob
		var ip := Vector2i(data.get("intake_pos", Vector2i(-1, -1)))
		if ip != Vector2i(-1, -1):
			g.intakes.append({"pos": ip, "dir": Vector2i(data.get("intake_dir", Vector2i.ZERO)), "scrap": String(data.get("intake_scrap", "")), "progress": 0.0, "status": "idle"})
	return g
