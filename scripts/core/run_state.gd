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
## Emitted when an incoming item couldn't fit in the factory grid (and was lost).
signal overflow(resource_id: String, lost: int)

const RESULT_NONE := ""
const RESULT_EXTRACTED := "extracted"
const RESULT_REPAIRED := "repaired"
const RESULT_SHIPPED := "shipped"
const RESULT_LOST := "lost"

## Inventory-factory grid (see docs/INVENTORY_FACTORY_DIRECTION.md). Starts bare each run.
const FACTORY_COLS := 8
const FACTORY_ROWS := 8
var factory: FactoryGrid

## The Scrapper Arm is a permanent 4-slot bar above the grid — one slot per scrap type,
## each stacking to ARM_STACK_MAX. Harvesting scrap fills it; Scrap Insert points (built
## with [B]) pull from it and spawn the scrap into the grid. It is NOT a grid machine.
const ARM_SCRAP_TYPES := ["copper_scrap", "steel_scrap", "plastic_scrap", "ceramic_scrap"]
const ARM_STACK_MAX := 99
var arm_scrap: Dictionary = {}

## Scrap (junk) and Tech Data are run CURRENCIES shown on the top bar, not grid items — they
## never take inventory cells. get_quantity/add/can_afford/spend route these ids here; every
## other resource lives in the factory grid.
const BAR_CURRENCIES := ["junk", "tech_data"]
var currency: Dictionary = {}


func currency_count(id: String) -> int:
	return int(currency.get(id, 0))


func arm_count(id: String) -> int:
	return int(arm_scrap.get(id, 0))


## Free space left in a scrap slot (0 if the id isn't an arm scrap type).
func arm_space(id: String) -> int:
	if not ARM_SCRAP_TYPES.has(id):
		return 0
	return ARM_STACK_MAX - arm_count(id)


## Stacks up to `n` of a scrap type into the arm bar; returns how many fit.
func arm_add(id: String, n := 1) -> int:
	var added := mini(n, arm_space(id))
	if added > 0:
		arm_scrap[id] = arm_count(id) + added
	return added


## Pulls up to `n` of a scrap type out of the arm bar; returns how many were available.
func arm_take(id: String, n := 1) -> int:
	var took := mini(n, arm_count(id))
	if took > 0:
		arm_scrap[id] = arm_count(id) - took
	return took

var area_id := ""
var run_seed := 0
var run_active := false
var result := RESULT_NONE

## The run's weapon is randomly tied to one material family (see GameData.families).
## `weapon_ammo` is the resource it consumes to fire — produced by the matching Ammo
## Maker. A run may lack a compatible Ammo Maker / material (intentionally; we observe).
var weapon_family := ""
var weapon_ammo := ""

## The run's GUARANTEED production chain (decided at generation): category -> concrete
## machine def id (e.g. {"Recycler":"copper_recycler", "Ammo Maker":"steel_ammo_maker",
## "Component Maker":"coupling_maker"}). The debug/run-info panel reads this to reveal
## what the run rolled and whether the weapon can actually be fed. Rolled INDEPENDENTLY
## of the weapon family — compatibility is NOT guaranteed (by design).
var run_chain: Dictionary = {}

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

## Reshuffles left this run for re-rolling a machine's RNG layout (build port roll and
## level-up slot shape). Defaults to 0 — you live with what you roll — and only meta
## progression grants more (MetaState "reshuffles" effect). Per-run budget.
var reshuffles := 0

## Per-run credit accumulated at the Component Exchange by selling components. Each
## full ExchangePanel.MACHINE_COST worth grants a random machine into `machine_stock`.
## Resets every run (it's spent in-run to get a machine you use now, not banked meta).
var exchange_credit := 0

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
	reshuffles = int(MetaState.effect_total("reshuffles", 0.0))

	# Ability is chosen at the start of each run. Only "starter" abilities are
	# available up front; others are unlocked mid-run (e.g. by repairing equipment).
	equipped_ability = ""
	available_abilities.clear()
	for ability_id: String in GameData.abilities:
		if bool(GameData.abilities[ability_id].get("starter", true)):
			available_abilities.append(ability_id)

	# Inventory-factory: a bare grid each run. Scrap enters through Scrap Insert points you
	# build from the Scrapper Arm bar (see arm_scrap), not a pre-placed machine.
	factory = FactoryGrid.new(FACTORY_COLS, FACTORY_ROWS)

	# The Scrapper Arm bar starts empty — one slot per scrap type.
	arm_scrap = {}
	for scrap_type: String in ARM_SCRAP_TYPES:
		arm_scrap[scrap_type] = 0

	# Top-bar currencies start empty (you find Scrap; Tech Data comes from scrapping).
	currency = {"junk": 0, "tech_data": 0}

	# Machines are found broken in the world and repaired — you start with none in stock
	# (only the pre-placed Scrapper Arm). Explore to find and repair a Recycler.
	machine_stock = {}

	# Component Exchange credit starts empty each run.
	exchange_credit = 0

	# Random weapon family for the run (may not match the Ammo Makers you find).
	var fams: Array = GameData.families.keys()
	if not fams.is_empty():
		weapon_family = String(fams[randi() % fams.size()])
		weapon_ammo = String(GameData.families[weapon_family].get("ammo", ""))

	# The generator fills run_chain when it spawns the guaranteed machines.
	run_chain = {}

	run_started.emit()


func unlock_shipping() -> void:
	shipping_unlocked = true


## Cost to raise a machine from `level` to `level + 1` (paid from the factory). Tech Data
## is earned by scrapping machines you can't place (see FactoryPanel scrap), so leveling
## up is fed by breaking down spare machines.
func level_cost(level: int) -> Dictionary:
	return {"tech_data": level + 1}


## Resource cost to place a machine or transport part (paid from the factory).
func part_cost(id: String) -> Dictionary:
	match id:
		"__conveyor":
			return {"junk": 1}
		"__splitter":
			return {"junk": 2}
		"__filter":
			return {"junk": 3}
	if id.begins_with("__insert_"):
		return {"junk": 1}  # a Scrap Insert point
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
	if resource_id in BAR_CURRENCIES:
		return int(currency.get(resource_id, 0))
	return int(resource_counts().get(resource_id, 0))


func resource_counts() -> Dictionary:
	return factory.resource_counts() if factory != null else {}


## Adds (amount > 0) or removes (amount < 0) a resource. Scrap/Tech Data go to the top-bar
## currency store (uncapped, no grid cell needed); everything else goes into free factory
## cells. Returns the number actually added/removed.
func add(resource_id: String, amount := 1) -> int:
	if resource_id in BAR_CURRENCIES:
		var cur := int(currency.get(resource_id, 0))
		var new_val := maxi(0, cur + amount)
		currency[resource_id] = new_val
		var delta := absi(new_val - cur)
		if delta > 0:
			inventory_changed.emit(resource_id, new_val)
		return delta
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
		if placed < amount:
			overflow.emit(resource_id, amount - placed)
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
