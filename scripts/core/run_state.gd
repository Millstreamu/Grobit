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
const RESULT_RESCUED := "rescued"  # the lair was fully restored and the distress beacon sent — win
const RESULT_LOST := "lost"

## Inventory-factory grid (the lair workshop / persistent base inventory). Persists across runs.
const FACTORY_COLS := 8
const FACTORY_ROWS := 8
var factory: FactoryGrid

## The scrapbot's CARGO HOLD — the Dredge-style finite space goblins deposit hauled loot into
## during a run (scrap packs small, recovered machines are bulky). Empty at run start; drains into
## the base inventory on extraction (see RunController._extract). See docs/DESIGN_SPEC.md §0.1.
const CARGO_COLS := 6
const CARGO_ROWS := 5
var cargo: CargoHold


## Current cargo-hold row count — base plus any persistent expansion bought at the terminal.
func cargo_rows() -> int:
	return CARGO_ROWS + MetaState.cargo_rows_bonus

## The scrapbot's MODULE BAY — the Dredge-style loadout grid you pack at the lair: weapons (which
## auto-fire in the field, fed ammo) and support modules, as shaped pieces. Persists across runs
## (MetaState.bay_blob). This is the bot's expedition kit, separate from the lair workshop (factory)
## and the cargo hold. See docs/DESIGN_SPEC.md §0.1.
const BAY_COLS := 6
const BAY_ROWS := 4
var bay: FactoryGrid

## The four typed scraps. Goblins haul scrap home and it feeds the inventory from the top-left
## (FactoryGrid.deposit_scrap), or into a scrap inserter pinned to that type; an adjacent recycler
## pulls it out. What a goblin can scrap is gated by its TOOL's tier, not by the factory.
const SCRAP_TYPES := ["copper_scrap", "steel_scrap", "plastic_scrap", "ceramic_scrap"]

## Tech Data is now a normal INVENTORY ITEM (scrapping machines yields it into the grid; the
## System Terminal spends it from the grid for recruiting / upgrades / hold expansion). No top-bar
## currency any more — BAR_CURRENCIES is empty, so get_quantity/add/spend all route to the grid.
const BAR_CURRENCIES := []
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

## False while you're still in the lair (goblin on foot); true once you've hopped in the
## scrapbot and driven out into the ruins. Drives the scrapbot's prompt (drive out / extract).
var driving := false

## Goblin names chosen to deploy this run (the pre-run squad, picked in the Scrapbot window's Crew
## tab). Empty means "deploy the whole colony". Reset each run in begin_run.
var deploy_squad: Array = []

## The bot's loaded AMMO reserve for this run ({ammo_id: count}). Ammo is MADE in the lair workshop
## (ammo makers are workshop machines now), stocked in the factory inventory, and loaded onto the bot
## at launch (load_ammo). The bay weapon draws from here as it fires; leftovers come home on extract.
var ammo: Dictionary = {}

## HEAT — run-wide presence/detection (docs/DESIGN_SPEC.md §0.2). Never decays in play; it rises while
## you're seen + engaging enemies (and when opening doors, later). Two staged thresholds escalate the
## threat: at HEAT_BOT_THREAT bigger, bot-damaging enemies appear; at HEAT_FULL_ALERT the facility is
## fully alerted (spawners won't stay dead). Resets every run.
enum { HEAT_CALM, HEAT_BOT_THREAT_TIER, HEAT_FULL_ALERT_TIER }
const HEAT_MAX := 100.0
const HEAT_BOT_THREAT := 55.0
const HEAT_FULL_ALERT := 80.0
var heat := 0.0

## Machine names newly unlocked by the shipment that ended this run (for the summary).
var last_run_unlocks: Array = []

## Lair needs filled by THIS run's extraction (need -> amount), for the end-of-run summary.
var needs_delivered: Dictionary = {}

## The single active ability chosen for this run (Space triggers it), and the set
## of abilities the player may choose/switch to. Structured so mid-run unlocks can
## grow `available_abilities` later.
var equipped_ability := ""
var available_abilities: Array[String] = []

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
	driving = false           # you start in the lair as the goblin, not yet in the scrapbot
	deploy_squad = []         # default to deploying the whole colony until you pick a squad
	ammo = {}                 # the bot carries no ammo until you load it at launch (load_ammo)
	heat = 0.0                # presence resets to calm at the start of every run
	exchange_machines_granted = 0

	# Ability is chosen at the start of each run. Only "starter" abilities are
	# available up front; others are unlocked mid-run (e.g. by repairing equipment).
	equipped_ability = ""
	available_abilities.clear()
	for ability_id: String in GameData.abilities:
		if bool(GameData.abilities[ability_id].get("starter", true)):
			available_abilities.append(ability_id)

	# Inventory-factory: a bare grid each run (the persistent layout is loaded over it by the
	# RunController). Harvested scrap feeds the grid from the top-left (or a matching scrap
	# inserter), and adjacent recyclers pull it out — see FactoryGrid.deposit_scrap.
	factory = FactoryGrid.new(FACTORY_COLS, FACTORY_ROWS)
	cargo = CargoHold.new(CARGO_COLS, cargo_rows())  # the bot's hold starts empty each run
	bay = FactoryGrid.new(BAY_COLS, BAY_ROWS)      # loadout; RunController loads the saved one over this

	currency = {}  # no top-bar currencies now — Tech Data is a grid item

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
	needs_delivered = {}

	run_started.emit()


## The goblin names that will actually deploy this run: the chosen squad, filtered to the living
## colony, or the whole colony when nothing is chosen (never deploys nobody).
func squad_names() -> Array:
	var all := MetaState.colony_names()
	if deploy_squad.is_empty():
		return all
	var out: Array = []
	for who: Variant in all:
		if deploy_squad.has(who):
			out.append(who)
	return out if not out.is_empty() else all


## Whether a named goblin is in this run's deploy squad (treating "no squad chosen" as all-in).
func is_deploying(gob_name: String) -> bool:
	return deploy_squad.is_empty() or deploy_squad.has(gob_name)


## Toggles a goblin in/out of the deploy squad. Turning the last-remaining one off is refused
## (you always deploy at least one). Called from the Scrapbot window's Crew tab at base.
func toggle_deploy(gob_name: String) -> void:
	if deploy_squad.is_empty():
		# "all" → make the set explicit (everyone) so we can remove this one.
		for who: Variant in MetaState.colony_names():
			deploy_squad.append(String(who))
	if deploy_squad.has(gob_name):
		if deploy_squad.size() <= 1:
			return  # keep at least one goblin selected
		deploy_squad.erase(gob_name)
	else:
		deploy_squad.append(gob_name)


# ------------------------------------------------------------------- ammo ----

## Ammo packs tighter than loot — this many ammo per hold cell (its own density, below the scrap
## stack of 10, so ammo scarcity bites sooner). Tune this to make ammo more/less of a constraint.
const AMMO_PER_CELL := 5

## How much ammo the bot can carry — capped by the CARGO HOLD's size (so upgrading the hold also
## lets you carry more ammo), at AMMO_PER_CELL per hold cell.
func ammo_capacity() -> int:
	var cells := cargo.capacity() if cargo != null else CARGO_COLS * cargo_rows()
	return cells * AMMO_PER_CELL


## Loads the bot's ammo reserve at launch: for every weapon equipped in the bay, pull its ammo type
## out of the lair workshop inventory onto the bot — up to the hold-size cap (ammo_capacity). Ammo
## beyond the cap stays in the workshop for next time.
func load_ammo() -> void:
	ammo = {}
	if bay == null or factory == null:
		return
	var room := ammo_capacity()
	for m: Dictionary in bay.machines:
		if room <= 0:
			break
		if bool(m.get("removed", false)):
			continue
		var def: Dictionary = GameData.machines.get(String(m.get("def_id", "")), {})
		if not bool(def.get("weapon", false)):
			continue
		var id := String(def.get("ammo", ""))
		if id == "" or ammo.has(id):
			continue
		var take := mini(get_quantity(id), room)
		if take > 0:
			add(id, -take)                 # take it out of the workshop stock
			ammo[id] = take
			room -= take


func ammo_count(id: String) -> int:
	return int(ammo.get(id, 0))


## Spends one unit of the given ammo from the bot's reserve. Returns false (no shot) when empty.
func consume_ammo(id: String) -> bool:
	var n := int(ammo.get(id, 0))
	if n <= 0:
		return false
	ammo[id] = n - 1
	return true


## True if a weapon is equipped AND the bot still has ammo of its type loaded — i.e. it can fire.
func weapon_armed() -> bool:
	if bay == null or not bay.has_weapon():
		return false
	var stats := bay.weapon_stats()
	return ammo_count(String(stats.get("ammo", ""))) > 0


## Returns any unspent ammo to the workshop inventory (called on a successful extraction).
func return_ammo() -> void:
	if factory == null:
		return
	for id: String in ammo:
		var n := int(ammo[id])
		if n > 0:
			add(id, n)
	ammo = {}


# ------------------------------------------------------------------- heat ----

## Raises (or, for the later Reduce-Heat ability, lowers) the run-wide Heat, clamped to [0, HEAT_MAX].
func add_heat(amount: float) -> void:
	heat = clampf(heat + amount, 0.0, HEAT_MAX)


func heat_ratio() -> float:
	return heat / HEAT_MAX


## The current Heat tier: HEAT_CALM / HEAT_BOT_THREAT_TIER / HEAT_FULL_ALERT_TIER.
func heat_tier() -> int:
	if heat >= HEAT_FULL_ALERT:
		return HEAT_FULL_ALERT_TIER
	if heat >= HEAT_BOT_THREAT:
		return HEAT_BOT_THREAT_TIER
	return HEAT_CALM


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


## Deposits a harvested/dropped item into its home: the four typed scraps feed the inventory from
## the top-left (or into a matching scrap inserter), Tech Data on the top bar, everything else into
## the factory grid. Returns amount accepted (0 if the grid is full).
func deposit(id: String, amount := 1) -> int:
	if SCRAP_TYPES.has(id):
		if factory == null:
			return 0
		var placed := 0
		for _i in amount:
			if factory.deposit_scrap(id):
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
