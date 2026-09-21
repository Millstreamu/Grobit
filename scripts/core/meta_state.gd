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
