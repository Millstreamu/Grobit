extends Node
## Autoload. RUN data — everything reset when a run starts.
##
## Current materials, installed recyclers, run seed and result live here. Live
## world nodes (beacons, generator) exist in the scene; RunState only owns the
## data that must survive room-to-room within a single run.

signal inventory_changed(resource_id: String, quantity: int)
signal run_started()
signal run_ended(result: String, summary: Dictionary)

const RESULT_NONE := ""
const RESULT_EXTRACTED := "extracted"
const RESULT_REPAIRED := "repaired"
const RESULT_LOST := "lost"

var area_id := ""
var run_seed := 0
var run_active := false
var result := RESULT_NONE

var inventory: Dictionary = {}
var installed_recyclers: Array[String] = []
var recycler_slots := 1


func begin_run(new_area_id: String, new_seed: int) -> void:
	area_id = new_area_id
	run_seed = new_seed
	result = RESULT_NONE
	run_active = true
	inventory.clear()
	installed_recyclers.clear()

	var area: Dictionary = GameData.area(area_id)
	recycler_slots = int(MetaState.effect_total("recycler_slots", 1))
	for rid: Variant in area.get("start_recyclers", []):
		if installed_recyclers.size() < recycler_slots:
			installed_recyclers.append(String(rid))
	run_started.emit()


func end_run(new_result: String) -> Dictionary:
	if not run_active:
		return {}
	run_active = false
	result = new_result
	var summary := {
		"result": new_result,
		"resources": inventory.duplicate(),
		"tech_data": get_quantity("tech_data"),
	}
	# Extracted / repaired runs bank their tech_data into permanent progression.
	if new_result != RESULT_LOST:
		var banked := get_quantity("tech_data")
		if banked > 0:
			MetaState.add_tech_data(banked)
	run_ended.emit(new_result, summary)
	return summary


func get_quantity(resource_id: String) -> int:
	return int(inventory.get(resource_id, 0))


func add(resource_id: String, amount := 1) -> void:
	if amount == 0:
		return
	inventory[resource_id] = maxi(0, get_quantity(resource_id) + amount)
	inventory_changed.emit(resource_id, inventory[resource_id])


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


func non_empty_resources() -> Array[String]:
	var ids: Array[String] = []
	for id: String in inventory:
		if int(inventory[id]) > 0:
			ids.append(id)
	ids.sort()
	return ids
