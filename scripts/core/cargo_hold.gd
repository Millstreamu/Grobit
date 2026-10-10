class_name CargoHold
extends RefCounted
## The scrapbot's in-run CARGO HOLD (Dredge-style). Deployed goblins deposit what they haul here
## during a run: typed scrap packs into small 1×1 stacks, and recovered machines are BULKY shaped
## crates. When the hold fills, nothing more can be carried in — that's the "when do I leave?"
## pressure stacked on the siege clock. On extraction the hold drains into the persistent base
## inventory (see RunController._extract). Heavy refining happens at the lair, not here.

## Pieces of one scrap type per hold cell — deliberately small so a haul takes visible space.
const SCRAP_STACK := 10

var cols: int
var rows: int
## Each cell: {} empty · {"kind":"scrap","id","count"} · {"kind":"crate","def_id","anchor","w","h"}
var cells: Array = []


func _init(c := 6, r := 4) -> void:
	cols = c
	rows = r
	for _i in cols * rows:
		cells.append({})


func _idx(x: int, y: int) -> int:
	return y * cols + x


func capacity() -> int:
	return cols * rows


func used() -> int:
	var n := 0
	for c: Dictionary in cells:
		if not c.is_empty():
			n += 1
	return n


func is_full() -> bool:
	return used() >= capacity()


func fullness() -> float:
	return float(used()) / float(maxi(1, capacity()))


## Deposits up to `amount` scrap of `id` — stacking onto matching cells first, then filling empty
## cells from the top-left. Returns how many pieces were accepted (0 if the hold is full).
func deposit_scrap(id: String, amount := 1) -> int:
	var placed := 0
	for c: Dictionary in cells:
		if placed >= amount:
			break
		if String(c.get("kind", "")) == "scrap" and String(c.get("id", "")) == id:
			var take := mini(SCRAP_STACK - int(c.get("count", 0)), amount - placed)
			if take > 0:
				c["count"] = int(c.get("count", 0)) + take
				placed += take
	for i in cells.size():
		if placed >= amount:
			break
		if cells[i].is_empty():
			var take := mini(SCRAP_STACK, amount - placed)
			cells[i] = {"kind": "scrap", "id": id, "count": take}
			placed += take
	return placed


## The bulky footprint (w, h) a recovered machine occupies — bigger/more complex machines take
## more room. Transport parts are a single cell.
func footprint_for(def_id: String) -> Vector2i:
	if def_id.begins_with("__"):
		return Vector2i(1, 1)
	var def: Dictionary = GameData.machines.get(def_id, {})
	var n := 1
	for key in ["inputs", "outputs", "holding", "body"]:
		n += (def.get(key, []) as Array).size()
	if n <= 2:
		return Vector2i(1, 2)
	if n <= 4:
		return Vector2i(2, 2)
	return Vector2i(2, 3)


func can_fit_machine(def_id: String) -> bool:
	return _find_spot(footprint_for(def_id)) != Vector2i(-1, -1)


## Places a recovered machine as a bulky crate (first spot it fits, scanning top-left). Returns
## false if there's no room.
func deposit_machine(def_id: String) -> bool:
	var fp := footprint_for(def_id)
	var spot := _find_spot(fp)
	if spot == Vector2i(-1, -1):
		return false
	for dy in fp.y:
		for dx in fp.x:
			cells[_idx(spot.x + dx, spot.y + dy)] = {
				"kind": "crate", "def_id": def_id, "anchor": dx == 0 and dy == 0, "w": fp.x, "h": fp.y,
			}
	return true


func _find_spot(fp: Vector2i) -> Vector2i:
	for y in range(rows - fp.y + 1):
		for x in range(cols - fp.x + 1):
			if _rect_empty(x, y, fp.x, fp.y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _rect_empty(x: int, y: int, w: int, h: int) -> bool:
	for dy in h:
		for dx in w:
			if not cells[_idx(x + dx, y + dy)].is_empty():
				return false
	return true


## Totals for draining into the base inventory on extraction.
func scrap_counts() -> Dictionary:
	var out := {}
	for c: Dictionary in cells:
		if String(c.get("kind", "")) == "scrap":
			out[String(c.id)] = int(out.get(String(c.id), 0)) + int(c.get("count", 0))
	return out


func machine_list() -> Array:
	var out: Array = []
	for c: Dictionary in cells:
		if String(c.get("kind", "")) == "crate" and bool(c.get("anchor", false)):
			out.append(String(c.def_id))
	return out


func clear() -> void:
	for i in cells.size():
		cells[i] = {}
