extends Node
## Autoload. PERMANENT data that persists between runs.
##
## Holds banked tech_data and unlocked technologies, saved to user:// so future
## runs benefit from previous ones. Kept intentionally separate from RunState
## (per-run data) so restarting a run never touches progression.

const SAVE_PATH := "user://grobit_save.json"

signal changed()

var tech_data := 0
var unlocked: Array[String] = []
## Resources delivered home over all runs (id -> total count). This is the
## permanent progress the whole loop feeds — re-commissioning the Mars facility.
var mars_delivered: Dictionary = {}
## Modules the player owns, drafted at decode stations. Persists across runs (the
## factory resets each run, but your module arsenal does not).
var modules_owned: Dictionary = {}
## Machine ids unlocked by delivering resources home (locked machines become
## buildable once their unlock_requires is met). Persists across runs.
var machines_unlocked: Array[String] = []
## Locked module ids added to the decode pool by deliveries (the module library
## grows as you play). Base (unlocked) modules are always in the pool. Persists.
var module_library: Array[String] = []

## The player's PERSISTENT factory layout, carried between runs — `var_to_str` of
## FactoryGrid.to_data(). Empty means "no factory yet" (first run starts bare). Stored as a
## string because the layout contains Vector2i, which JSON can't represent.
var factory_blob := ""

## Permanent machine upgrades bought with banked tech_data (def_id -> level, default 1).
## Every placed machine of that type benefits (faster processing + higher recipe gate), and
## since the factory persists, so do the upgrades. Bought at a System Terminal.
var machine_levels: Dictionary = {}
const MAX_MACHINE_LEVEL := 5

## Persistent transport/cache STORAGE (id -> count). Fungible parts (conveyors, splitters,
## filters, caches) are found/crafted and stacked here (RunState.machine_stock links to it).
var machine_storage: Dictionary = {}

## Persistent MACHINE storage as per-instance records — each found machine keeps its OWN rolled
## layout (port sides / body), so collecting duplicates of a type is worthwhile (different
## layouts pack differently). Each record: {def_id, in_offsets, out_offsets, hold_offsets,
## body_offsets}. RunState.machine_instances links to this list. Stored as a var_to_str blob
## because the offsets are Vector2i (JSON can't represent them).
var machine_instances: Array = []


## The goblin lair's survival needs — the META GOAL. Each is filled by DELIVERING the matching
## bridge component on extraction. Fill all four to NEED_MAX to ready the distress beacon (the
## endgame: other goblins come to the rescue). Components are also spent on arm upgrades, so
## every run is a choice: climb the ladder, or fix the lair. Persists.
const LAIR_NEEDS := ["oxygen", "power", "water", "food"]
const NEED_MAX := 5
const NEED_COMPONENT := {
	"reinforced_frame": "oxygen",   # steel frame — seals the lair
	"power_coupling": "power",       # steel+copper — wiring
	"control_assembly": "water",     # copper+plastic — filtration
	"thermal_core": "food",          # copper+plastic — the grow-lamp core
}
var lair_needs: Dictionary = {}
var beacon_sent := false            # the distress beacon has been sent — you're rescued (win)


func need_amount(need: String) -> int:
	return int(lair_needs.get(need, 0))


## Delivers extracted components to their lair need (capped at NEED_MAX each). Returns a map of
## {need: amount_added} for the run summary.
func deliver_to_needs(items: Dictionary) -> Dictionary:
	var added := {}
	for id: String in items:
		var need := String(NEED_COMPONENT.get(id, ""))
		if need == "":
			continue
		var add := mini(int(items[id]), NEED_MAX - need_amount(need))
		if add > 0:
			lair_needs[need] = need_amount(need) + add
			added[need] = int(added.get(need, 0)) + add
	if not added.is_empty():
		save_game()
		changed.emit()
	return added


## True once every lair need is maxed — the lair is whole and the beacon can be sent.
func lair_restored() -> bool:
	for need: String in LAIR_NEEDS:
		if need_amount(need) < NEED_MAX:
			return false
	return true


## Fires the distress beacon (the win). One-way.
func send_beacon() -> void:
	beacon_sent = true
	save_game()
	changed.emit()


## The goblin lair's footprint — the grid-cell indices room 0 occupies (bottom-middle of
## the map). Frozen the first time a run generates and reused every run after, so the base
## room keeps the same size/shape (future meta upgrades edit this). `lair_grid` records the
## [grid_w, grid_h] it was authored for, so a generation-size change re-seeds it.
var lair_cells: Array = []
var lair_grid: Array = []


func has_lair() -> bool:
	return not lair_cells.is_empty()


## The saved lair footprint for a `w`×`h` cell grid, or [] if none is stored for that size.
func load_lair_cells(w: int, h: int) -> Array:
	if lair_cells.is_empty() or lair_grid != [w, h]:
		return []
	return lair_cells.duplicate()


## Freezes the lair footprint so every future run rebuilds the same base room.
func save_lair_cells(cells: Array, w: int, h: int) -> void:
	lair_cells = cells.duplicate()
	lair_grid = [w, h]
	save_game()


func machine_level(def_id: String) -> int:
	return int(machine_levels.get(def_id, 1))


func can_upgrade_machine(def_id: String) -> bool:
	return machine_level(def_id) < MAX_MACHINE_LEVEL


## Tech Data to take a machine type from its current level to the next.
func machine_upgrade_cost(def_id: String) -> int:
	return 3 * machine_level(def_id)  # 1→2: 3, 2→3: 6, 3→4: 9, 4→5: 12


## Spends banked tech_data to raise a machine type's permanent level. Returns success.
func upgrade_machine(def_id: String) -> bool:
	if not can_upgrade_machine(def_id):
		return false
	var cost := machine_upgrade_cost(def_id)
	if tech_data < cost:
		return false
	tech_data -= cost
	machine_levels[def_id] = machine_level(def_id) + 1
	save_game()
	changed.emit()
	return true


func has_factory() -> bool:
	return factory_blob != ""


## Persists the current factory layout (called when a run ends).
func save_factory(grid: FactoryGrid) -> void:
	factory_blob = var_to_str(grid.to_data()) if grid != null else ""
	save_game()


## Rebuilds the persisted factory, or null if there isn't one.
func load_factory() -> FactoryGrid:
	if factory_blob == "":
		return null
	var data: Variant = str_to_var(factory_blob)
	return FactoryGrid.from_data(data) if data is Dictionary else null


## Persists the machine/transport storage (call after repairs or placements change it).
func save_storage() -> void:
	save_game()


## Wipes the saved factory (used by the big-machine extraction and by starting over).
func clear_factory() -> void:
	factory_blob = ""
	save_game()


func _ready() -> void:
	load_game()


func has_tech(tech_id: String) -> bool:
	return unlocked.has(tech_id)


## Attempts to buy a tech with banked tech_data. Returns true on success.
func unlock_tech(tech_id: String) -> bool:
	if has_tech(tech_id):
		return false
	var def: Dictionary = GameData.tech.get(tech_id, {})
	if def.is_empty():
		return false
	var cost := int(def.get("cost", 0))
	if tech_data < cost:
		return false
	tech_data -= cost
	unlocked.append(tech_id)
	save_game()
	changed.emit()
	return true


func add_tech_data(amount: int) -> void:
	tech_data += amount
	save_game()
	changed.emit()


## Banks a shipped delivery (id -> count) toward Mars re-commissioning. Permanent.
## Returns the names of any machines this delivery newly unlocked (for the summary).
func bank_delivery(items: Dictionary) -> Array:
	for id: String in items:
		mars_delivered[id] = int(mars_delivered.get(id, 0)) + int(items[id])
	var newly := _check_unlocks()
	save_game()
	changed.emit()
	return newly


## The nearest not-yet-earned unlock (machine or module) as a short hint like
## "ship 2 Circuit Board → Constructor", or "" if everything is unlocked.
func next_unlock_hint() -> String:
	var best_total := 1 << 30
	var best := ""
	for id: String in GameData.machines:
		var s := _unlock_remaining(GameData.machines[id], id, machines_unlocked)
		if s.total > 0 and s.total < best_total:
			best_total = s.total
			best = s.text
	for id: String in GameData.modules:
		var s := _unlock_remaining(GameData.modules[id], id, module_library)
		if s.total > 0 and s.total < best_total:
			best_total = s.total
			best = s.text
	return best


func _unlock_remaining(def: Dictionary, id: String, earned: Array) -> Dictionary:
	if not bool(def.get("locked", false)) or earned.has(id):
		return {"total": 0, "text": ""}
	var parts: Array = []
	var total := 0
	for res: String in def.get("unlock_requires", {}):
		var need := int(def.unlock_requires[res]) - int(mars_delivered.get(res, 0))
		if need > 0:
			parts.append("%d %s" % [need, GameData.resource_name(res)])
			total += need
	if total <= 0:
		return {"total": 0, "text": ""}
	return {"total": total, "text": "ship %s → %s" % [", ".join(parts), String(def.get("name", id))]}


## A machine is available if it isn't locked, or its unlock has been earned.
func is_machine_unlocked(machine_id: String) -> bool:
	var def: Dictionary = GameData.machines.get(machine_id, {})
	if not bool(def.get("locked", false)):
		return true
	return machines_unlocked.has(machine_id)


## Unlocks any locked machine whose cumulative delivery requirement is now met.
## Returns the display names newly unlocked.
func _check_unlocks() -> Array:
	var newly: Array = []
	for machine_id: String in GameData.machines:
		var def: Dictionary = GameData.machines[machine_id]
		if not bool(def.get("locked", false)) or machines_unlocked.has(machine_id):
			continue
		var met := true
		for res: String in def.get("unlock_requires", {}):
			if int(mars_delivered.get(res, 0)) < int(def.unlock_requires[res]):
				met = false
				break
		if met:
			machines_unlocked.append(machine_id)
			newly.append(String(def.get("name", machine_id)))
	# Modules join the decode library the same way.
	for module_id: String in GameData.modules:
		var mdef: Dictionary = GameData.modules[module_id]
		if not bool(mdef.get("locked", false)) or module_library.has(module_id):
			continue
		var mmet := true
		for res: String in mdef.get("unlock_requires", {}):
			if int(mars_delivered.get(res, 0)) < int(mdef.unlock_requires[res]):
				mmet = false
				break
		if mmet:
			module_library.append(module_id)
			newly.append(String(mdef.get("name", module_id)))
	return newly


## Total resources delivered home across all runs.
func mars_total() -> int:
	var total := 0
	for id: String in mars_delivered:
		total += int(mars_delivered[id])
	return total


# ---------------------------------------------------------- modules ----

func module_count(module_id: String) -> int:
	return int(modules_owned.get(module_id, 0))


## A module type is draftable if it isn't locked, or its library unlock is earned.
func is_module_unlocked(module_id: String) -> bool:
	var def: Dictionary = GameData.modules.get(module_id, {})
	if not bool(def.get("locked", false)):
		return true
	return module_library.has(module_id)


## Rolls up to `count` distinct module ids to offer at a decode station, drawn from
## the currently-unlocked library (which grows via deliveries).
func decode_options(count: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array = []
	for id: String in GameData.modules:
		if is_module_unlocked(id):
			pool.append(id)
	if rng != null:
		pool = _seeded_shuffle(pool, rng)
	else:
		pool.shuffle()
	return pool.slice(0, mini(count, pool.size()))


func _seeded_shuffle(arr: Array, rng: RandomNumberGenerator) -> Array:
	var a := arr.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a


## Adds a decoded module to the permanent collection.
func grant_module(module_id: String) -> void:
	modules_owned[module_id] = int(modules_owned.get(module_id, 0)) + 1
	save_game()
	changed.emit()


## Sums the 'value' of every unlocked tech whose effect matches. Numeric effects.
func effect_total(effect: String, default_value: float) -> float:
	var total := default_value
	for tech_id: String in unlocked:
		var def: Dictionary = GameData.tech.get(tech_id, {})
		if String(def.get("effect", "")) == effect:
			total += float(def.get("value", 0.0))
	return total


## Returns the first matching unlocked effect value, or the default.
func effect_value(effect: String, default_value: Variant) -> Variant:
	for tech_id: String in unlocked:
		var def: Dictionary = GameData.tech.get(tech_id, {})
		if String(def.get("effect", "")) == effect:
			return def.get("value", default_value)
	return default_value


func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("MetaState could not write save file.")
		return
	file.store_string(JSON.stringify({
		"tech_data": tech_data,
		"unlocked": unlocked,
		"mars_delivered": mars_delivered,
		"modules_owned": modules_owned,
		"machines_unlocked": machines_unlocked,
		"module_library": module_library,
		"factory": factory_blob,
		"machine_levels": machine_levels,
		"lair_cells": lair_cells,
		"lair_grid": lair_grid,
		"machine_storage": machine_storage,
		"machine_instances": var_to_str(machine_instances),
		"lair_needs": lair_needs,
		"beacon_sent": beacon_sent,
	}, "  "))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_warning("MetaState save file was unreadable; ignoring.")
		return
	var data: Dictionary = json.data
	tech_data = int(data.get("tech_data", 0))
	unlocked.clear()
	for id: Variant in data.get("unlocked", []):
		unlocked.append(String(id))
	mars_delivered.clear()
	var saved: Dictionary = data.get("mars_delivered", {})
	for id: Variant in saved:
		mars_delivered[String(id)] = int(saved[id])
	modules_owned.clear()
	var saved_mods: Dictionary = data.get("modules_owned", {})
	for id: Variant in saved_mods:
		modules_owned[String(id)] = int(saved_mods[id])
	machines_unlocked.clear()
	for id: Variant in data.get("machines_unlocked", []):
		machines_unlocked.append(String(id))
	module_library.clear()
	for id: Variant in data.get("module_library", []):
		module_library.append(String(id))
	factory_blob = String(data.get("factory", ""))
	machine_levels.clear()
	var saved_levels: Dictionary = data.get("machine_levels", {})
	for id: Variant in saved_levels:
		machine_levels[String(id)] = int(saved_levels[id])
	lair_cells.clear()
	for c: Variant in data.get("lair_cells", []):
		lair_cells.append(int(c))
	lair_grid.clear()
	for d: Variant in data.get("lair_grid", []):
		lair_grid.append(int(d))
	machine_storage.clear()
	var saved_storage: Dictionary = data.get("machine_storage", {})
	for id: Variant in saved_storage:
		machine_storage[String(id)] = int(saved_storage[id])
	machine_instances.clear()
	var inst: Variant = str_to_var(String(data.get("machine_instances", "")))
	if inst is Array:
		for rec: Variant in inst:
			if rec is Dictionary:
				machine_instances.append(rec)
	lair_needs.clear()
	var saved_needs: Dictionary = data.get("lair_needs", {})
	for need: Variant in saved_needs:
		lair_needs[String(need)] = int(saved_needs[need])
	beacon_sent = bool(data.get("beacon_sent", false))
