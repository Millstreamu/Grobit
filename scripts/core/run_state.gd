extends Node
## Autoload. RUN data — everything reset when a run starts.
##
## The inventory IS the factory (see docs/INVENTORY_FACTORY_DIRECTION.md): resources
## live as items in the `factory` grid. Count-based helpers (get_quantity /
## can_afford / spend / add) operate on that grid, so drops, repair costs and build
## costs all read and write the same storage the player sees.

signal inventory_changed(resource_id: String, quantity: int)
signal run_started()
signal run_ended(result: String, summary: Dictionary)

const RESULT_NONE := ""
const RESULT_EXTRACTED := "extracted"
const RESULT_REPAIRED := "repaired"
const RESULT_SHIPPED := "shipped"
const RESULT_LOST := "lost"

## Inventory-factory grid (see docs/INVENTORY_FACTORY_DIRECTION.md). Bare each run
## with the scrapper arm pre-placed.
const FACTORY_COLS := 5
const FACTORY_ROWS := 4
var factory: FactoryGrid

var area_id := ""
var run_seed := 0
var run_active := false
var result := RESULT_NONE

## Set true when the map objective is completed; the retrieval pad only ships once
## this is on (see docs/INVENTORY_FACTORY_DIRECTION.md — objective gates shipping).
var shipping_unlocked := false

## Machine names newly unlocked by the shipment that ended this run (for the summary).
var last_run_unlocks: Array = []

## The single active ability chosen for this run (Space triggers it), and the set
## of abilities the player may choose/switch to. Structured so mid-run unlocks can
## grow `available_abilities` later.
var equipped_ability := ""
var available_abilities: Array[String] = []

## Reshuffles left this run for re-rolling a machine level-up's RNG slot shape.
## Starts small and (later, via meta) grows with progress. Per-run budget.
var reshuffles := 1

## Machines built this run but not currently placed (id -> count). Placing from the
## stock is free (you already own it); picking a machine up returns it here. This is
## what makes sequential batch play work in a small grid — build a line, run it,
## pick the machines up, and re-lay them for the next batch.
var machine_stock: Dictionary = {}


func begin_run(new_area_id: String, new_seed: int) -> void:
	area_id = new_area_id
	run_seed = new_seed
	result = RESULT_NONE
	run_active = true
	shipping_unlocked = false
	reshuffles = 1 + int(MetaState.effect_total("reshuffles", 0.0))

	# Ability is chosen at the start of each run. Only "starter" abilities are
	# available up front; others are unlocked mid-run (e.g. by repairing equipment).
	equipped_ability = ""
	available_abilities.clear()
	for ability_id: String in GameData.abilities:
		if bool(GameData.abilities[ability_id].get("starter", true)):
			available_abilities.append(ability_id)

	# Inventory-factory: a bare grid each run with the scrapper arm pre-placed
	# top-left (its output/holding cells face into the grid to build lines from).
	factory = FactoryGrid.new(FACTORY_COLS, FACTORY_ROWS)
	factory.place_machine("scrapper_arm", Vector2i(0, 0))

	# Start with a Scrap Recycler in stock so junk can be processed from the first run.
	machine_stock = {"scrap_recycler": 1}

	run_started.emit()


func unlock_shipping() -> void:
	shipping_unlocked = true


## Cost to raise a machine from `level` to `level + 1` (paid from the factory).
func level_cost(level: int) -> Dictionary:
	return {"scrap_metal": level + 1}


## Resource cost to place a machine or transport part (paid from the factory).
func part_cost(id: String) -> Dictionary:
	match id:
		"__conveyor":
			return {"scrap_metal": 1}
		"__splitter":
			return {"scrap_metal": 2}
	return GameData.machines.get(id, {}).get("cost", {})


# --------------------------------------------------------- machine stock ----

func stock_count(id: String) -> int:
	return int(machine_stock.get(id, 0))


func take_from_stock(id: String) -> bool:
	if stock_count(id) <= 0:
		return false
	machine_stock[id] = stock_count(id) - 1
	return true


func add_to_stock(id: String) -> void:
	machine_stock[id] = stock_count(id) + 1


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


# --------------------------------------------------------- quantities ----

## True if the factory grid has at least one free cell for an incoming item.
func has_space() -> bool:
	return factory != null and factory.has_empty()


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
	return int(resource_counts().get(resource_id, 0))


func resource_counts() -> Dictionary:
	return factory.resource_counts() if factory != null else {}


## Adds (amount > 0) resource items into free factory cells, or removes (amount < 0)
## items of that resource. Returns the number actually added/removed.
func add(resource_id: String, amount := 1) -> int:
	if factory == null:
		return 0
	if amount > 0:
		var placed := 0
		for _i in amount:
			if factory.add_resource(resource_id):
				placed += 1
			else:
				break
		if placed > 0:
			inventory_changed.emit(resource_id, get_quantity(resource_id))
		return placed
	elif amount < 0:
		var removed := factory.remove_resource(resource_id, -amount)
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
