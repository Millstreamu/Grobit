extends Node
## Autoload. RUN data — everything reset when a run starts.
##
## Inventory is a fixed GRID of single-item slots (no stacking): each slot is
## empty, holds one resource unit, or holds a module (e.g. the Scrap Recycler).
## The rest of the game still thinks in quantities, so this exposes count-based
## helpers (get_quantity / can_afford / spend) on top of the slot storage.
##
## Slot shape (a Dictionary):
##   {}                                                  -> empty
##   {"kind": "resource", "id": <resource_id>}           -> one resource unit
##   {"kind": "module", "id": <module_id>, "buffer": int, "progress": float}

signal inventory_changed(resource_id: String, quantity: int)
signal run_started()
signal run_ended(result: String, summary: Dictionary)

const RESULT_NONE := ""
const RESULT_EXTRACTED := "extracted"
const RESULT_REPAIRED := "repaired"
const RESULT_LOST := "lost"

const COLUMNS := 5
const ROWS := 4
const CAPACITY := COLUMNS * ROWS

var area_id := ""
var run_seed := 0
var run_active := false
var result := RESULT_NONE

## The single active ability chosen for this run (Space triggers it), and the set
## of abilities the player may choose/switch to. Structured so mid-run unlocks can
## grow `available_abilities` later.
var equipped_ability := ""
var available_abilities: Array[String] = []

var slots: Array = []


func begin_run(new_area_id: String, new_seed: int) -> void:
	area_id = new_area_id
	run_seed = new_seed
	result = RESULT_NONE
	run_active = true

	# Ability is chosen at the start of each run. Only "starter" abilities are
	# available up front; others are unlocked mid-run (e.g. by repairing equipment).
	equipped_ability = ""
	available_abilities.clear()
	for ability_id: String in GameData.abilities:
		if bool(GameData.abilities[ability_id].get("starter", true)):
			available_abilities.append(ability_id)

	slots.clear()
	for i in CAPACITY:
		slots.append({})

	# Install the area's starting recycler modules at the end of the grid so the
	# early slots stay clear for incoming pickups. Extra recycler slots unlocked
	# via tech add more copies of the last recycler.
	var area: Dictionary = GameData.area(area_id)
	var module_ids: Array = []
	for rid: Variant in area.get("start_recyclers", []):
		module_ids.append(String(rid))
	var recycler_slots := int(MetaState.effect_total("recycler_slots", 1))
	while not module_ids.is_empty() and module_ids.size() < recycler_slots:
		module_ids.append(module_ids.back())
	var index := CAPACITY - 1
	for module_id: String in module_ids:
		if index < 0:
			break
		slots[index] = {"kind": "module", "id": module_id, "buffer": 0, "progress": 0.0}
		index -= 1

	run_started.emit()


func end_run(new_result: String) -> Dictionary:
	if not run_active:
		return {}
	run_active = false
	result = new_result
	var summary := {
		"result": new_result,
		"resources": resource_counts(),
		"tech_data": get_quantity("tech_data"),
	}
	if new_result != RESULT_LOST:
		var banked := get_quantity("tech_data")
		if banked > 0:
			MetaState.add_tech_data(banked)
	run_ended.emit(new_result, summary)
	return summary


# --------------------------------------------------------------- slots ----

func slot_count() -> int:
	return slots.size()


func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {}
	return slots[index]


func slot_is_empty(index: int) -> bool:
	return get_slot(index).is_empty()


func first_empty() -> int:
	for i in slots.size():
		if slots[i].is_empty():
			return i
	return -1


func has_space() -> bool:
	return first_empty() != -1


## Moves/swaps slot contents. If the destination is a recycler module and the
## source is a resource that recycler accepts, the source is instead fed into the
## module's buffer (consumed). Returns true if anything changed.
func move_slot(from_index: int, to_index: int) -> bool:
	if from_index == to_index:
		return false
	if from_index < 0 or to_index < 0 or from_index >= slots.size() or to_index >= slots.size():
		return false
	var source: Dictionary = slots[from_index]
	var target: Dictionary = slots[to_index]
	if source.is_empty():
		return false
	if _feed_recycler(source, target, from_index):
		return true
	slots[from_index] = target
	slots[to_index] = source
	inventory_changed.emit("", 0)
	return true


func _feed_recycler(source: Dictionary, target: Dictionary, from_index: int) -> bool:
	if target.get("kind", "") != "module" or source.get("kind", "") != "resource":
		return false
	var def: Dictionary = GameData.recyclers.get(String(target.get("id", "")), {})
	if def.is_empty() or String(source.get("id", "")) != String(def.get("input", "")):
		return false
	target["buffer"] = int(target.get("buffer", 0)) + 1
	slots[from_index] = {}
	inventory_changed.emit(String(source.id), get_quantity(String(source.id)))
	return true


# --------------------------------------------------------- quantities ----

## Makes an ability choosable this run. Returns false if already available.
func unlock_ability(ability_id: String) -> bool:
	if ability_id.is_empty() or available_abilities.has(ability_id):
		return false
	available_abilities.append(ability_id)
	return true


## An ability id the player has NOT yet unlocked this run, or "" if none remain.
func first_locked_ability() -> String:
	for ability_id: String in GameData.abilities:
		if not available_abilities.has(ability_id):
			return ability_id
	return ""


func get_quantity(resource_id: String) -> int:
	var count := 0
	for slot: Dictionary in slots:
		if slot.get("kind", "") == "resource" and String(slot.get("id", "")) == resource_id:
			count += 1
	return count


func resource_counts() -> Dictionary:
	var counts := {}
	for slot: Dictionary in slots:
		if slot.get("kind", "") == "resource":
			var id := String(slot.id)
			counts[id] = int(counts.get(id, 0)) + 1
	return counts


## Adds (amount > 0) resource units into empty slots, or removes (amount < 0)
## units of that resource. Returns the number of units actually added/removed.
func add(resource_id: String, amount := 1) -> int:
	if amount > 0:
		var placed := 0
		for i in slots.size():
			if placed >= amount:
				break
			if slots[i].is_empty():
				slots[i] = {"kind": "resource", "id": resource_id}
				placed += 1
		if placed > 0:
			inventory_changed.emit(resource_id, get_quantity(resource_id))
		return placed
	elif amount < 0:
		var to_remove := -amount
		var removed := 0
		for i in slots.size():
			if removed >= to_remove:
				break
			if slots[i].get("kind", "") == "resource" and String(slots[i].get("id", "")) == resource_id:
				slots[i] = {}
				removed += 1
		if removed > 0:
			inventory_changed.emit(resource_id, get_quantity(resource_id))
		return removed
	return 0


func can_afford(cost: Dictionary) -> bool:
	for resource_id: String in cost:
		if get_quantity(resource_id) < int(cost[resource_id]):
			return false
	return true


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for resource_id: String in cost:
		add(resource_id, -int(cost[resource_id]))
	return true
