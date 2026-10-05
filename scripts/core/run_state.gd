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

## The four typed scraps. The Scrapper Arm is a 5-cell GRID MACHINE now (core + one slot per
## type); harvested scrap stacks into its matching slot (FactoryGrid.deposit_harvest) and an
## adjacent recycler pulls it out. There is no top bar any more.
const ARM_SCRAP_TYPES := ["copper_scrap", "steel_scrap", "plastic_scrap", "ceramic_scrap"]

## Tech Data is the one run CURRENCY shown on the top bar, not a grid item — it never takes an
## inventory cell. get_quantity/add/can_afford/spend route it here; every other resource
## (typed scrap in the arm's slots, refined materials/components in the grid) lives elsewhere.
## There is no generic 'junk' any more — repairs are paid in refined materials from the grid.
const BAR_CURRENCIES := ["tech_data"]
var currency: Dictionary = {}


func currency_count(id: String) -> int:
	return int(currency.get(id, 0))

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

## False while you're still in the lair (goblin on foot); true once you've hopped in the
## scrapbot and driven out into the ruins. Drives the scrapbot's prompt (drive out / extract).
var driving := false

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

## The Component Exchange gives only a limited number of machines per run, then goes
## dormant. Base-cap is 1; meta progression can raise it (the "exchange_machines" effect).
var exchange_machines_granted := 0


func exchange_machine_cap() -> int:
	return 1 + int(MetaState.effect_total("exchange_machines", 0.0))


func exchange_dormant() -> bool:
	return exchange_machines_granted >= exchange_machine_cap()

## Machines built this run but not currently placed (id -> count). Placing from the
## stock is free (you already own it); picking a machine up returns it here. This is
## what makes sequential batch play work in a small grid — build a line, run it,
## pick the machines up, and re-lay them for the next batch.
var machine_stock: Dictionary = {}

## Per-instance MACHINE storage (each with its own rolled layout). Links to
## MetaState.machine_instances in begin_run so it persists across runs.
var machine_instances: Array = []


func begin_run(new_area_id: String, new_seed: int) -> void:
	area_id = new_area_id
	run_seed = new_seed
	result = RESULT_NONE
	run_active = true
	shipping_unlocked = true  # extraction is ungated now — just return to the start point
	driving = false           # you start in the lair as the goblin, not yet in the scrapbot
	exchange_machines_granted = 0
	reshuffles = int(MetaState.effect_total("reshuffles", 0.0))

	# Ability is chosen at the start of each run. Only "starter" abilities are
	# available up front; others are unlocked mid-run (e.g. by repairing equipment).
	equipped_ability = ""
	available_abilities.clear()
	for ability_id: String in GameData.abilities:
		if bool(GameData.abilities[ability_id].get("starter", true)):
			available_abilities.append(ability_id)

	# Inventory-factory: a bare grid each run (the persistent layout is loaded over it by the
	# RunController). Harvested scrap stacks into the Scrapper Arm machine's typed slots, and
	# adjacent recyclers pull it out — see FactoryGrid.deposit_harvest / _consume_available.
	factory = FactoryGrid.new(FACTORY_COLS, FACTORY_ROWS)

	# Top-bar currency starts empty (Tech Data comes from scrapping machines, uploaded at a Terminal).
	currency = {"tech_data": 0}

	# Machine/transport STORAGE persists across runs (Slice C): repaired gear lives in
	# MetaState.machine_storage and is placed at run-start setup. Link the run's stock to it so
	# add/take_from_stock mutate the persistent store directly (saved on end_run).
	machine_stock = MetaState.machine_storage
	machine_instances = MetaState.machine_instances

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


## Resource cost to place a machine or transport part (paid from the factory). Transport and
## Scrap Insert points are FREE to place now — they're set up in the lair (Slice A) and will
## become found-and-repaired items (Slice C). Machines are placed from stock, never bought.
func part_cost(id: String) -> Dictionary:
	if id.begins_with("__"):
		return {}  # transport (__conveyor/__splitter/__filter) is free to place
	return GameData.machines.get(id, {}).get("cost", {})


# --------------------------------------------------------- machine stock ----
# Fungible parts (transport/caches) are counted in machine_stock; found MACHINES are kept as
# per-instance records in machine_instances (each with its own rolled layout).

func stock_count(id: String) -> int:
	return int(machine_stock.get(id, 0))


func take_from_stock(id: String) -> bool:
	if stock_count(id) <= 0:
		return false
	machine_stock[id] = stock_count(id) - 1
	return true


func add_to_stock(id: String) -> void:
	machine_stock[id] = stock_count(id) + 1


# ----------------------------------------------- machine instances (dupes) ----
# machine_instances links to MetaState.machine_instances (set in begin_run) so repairs persist.

func instance_count() -> int:
	return machine_instances.size()


## Stores a machine instance with an explicit layout (used when STASHING a placed machine — its
## current layout is preserved, not re-rolled).
func store_instance(def_id: String, layout: Dictionary) -> void:
	machine_instances.append({
		"def_id": def_id,
		"in_offsets": (layout.get("in_offsets", []) as Array).duplicate(),
		"out_offsets": (layout.get("out_offsets", []) as Array).duplicate(),
		"hold_offsets": (layout.get("hold_offsets", []) as Array).duplicate(),
		"body_offsets": (layout.get("body_offsets", []) as Array).duplicate(),
	})


## Adds a freshly FOUND machine: rolls a brand-new layout so duplicates of a type differ. The
## rolled port sides / body are frozen on the instance and reused when it's placed.
func add_machine_instance(def_id: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var layout := FactoryGrid.new(8, 8).roll_machine_layout(def_id, rng)
	store_instance(def_id, layout)


## Removes and returns the instance at `index` (when it's actually placed or scrapped), or {}.
func take_instance(index: int) -> Dictionary:
	if index < 0 or index >= machine_instances.size():
		return {}
	return machine_instances.pop_at(index)


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
	# Tech Data is NO LONGER auto-banked at run end — you must upload it at a System Terminal
	# during the run (see TerminalPanel). Un-uploaded Tech Data is lost on extraction/death.
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


## Deposits a harvested/dropped item into its home: the four typed scraps stack into the Scrapper
## Arm machine's matching slot, Tech Data on the top bar, everything else into the factory grid.
## Returns amount accepted (0 if the arm is full/absent, etc.).
func deposit(id: String, amount := 1) -> int:
	if ARM_SCRAP_TYPES.has(id):
		if factory == null:
			return 0
		var placed := 0
		for _i in amount:
			if factory.deposit_harvest(id):
				placed += 1
			else:
				break
		return placed
	return add(id, amount)


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
