extends Node
## Autoload. PERMANENT data that persists between runs.
##
## Holds banked tech_data and unlocked technologies, saved to user:// so future
## runs benefit from previous ones. Kept intentionally separate from RunState
## (per-run data) so restarting a run never touches progression.

const SAVE_PATH := "user://grobit_save.json"

signal changed()

var unlocked: Array[String] = []
## Resources delivered home over all runs (id -> total count). This is the
## permanent progress the whole loop feeds — re-commissioning the Mars facility.
var mars_delivered: Dictionary = {}
## Machine ids unlocked by delivering resources home (locked machines become
## buildable once their unlock_requires is met). Persists across runs.
var machines_unlocked: Array[String] = []

## The player's PERSISTENT factory layout, carried between runs — `var_to_str` of
## FactoryGrid.to_data(). Empty means "no factory yet" (first run starts bare). Stored as a
## string because the layout contains Vector2i, which JSON can't represent.
var factory_blob := ""

## The scrapbot's MODULE BAY loadout (weapons/support), carried between runs — same var_to_str
## blob format as factory_blob. Empty means an empty bay.
var bay_blob := ""

## The WORKSHOP PROCESS LINE layout (Phase 4 chains), carried between runs — `var_to_str` of
## ProcessGrid.to_data(). Empty means "no line laid out yet". Stored as a string because the layout
## holds Vector2i (ports/positions), which JSON can't represent.
var process_blob := ""

## Persistent CARGO HOLD expansion — extra rows bought at the terminal (Dredge "bigger hold").
var cargo_rows_bonus := 0
const CARGO_BONUS_MAX := 4


func can_expand_cargo() -> bool:
	return cargo_rows_bonus < CARGO_BONUS_MAX


## Chain products to add another row of cargo hold (climbs each time). Paid in steel plate + copper sheet.
func expand_cargo_cost() -> Dictionary:
	var n := cargo_rows_bonus + 1
	return {"steel_plate": 5 * n, "copper_sheet": 3 * n}


## Spends refined materials to enlarge the cargo hold one row. Returns success.
func expand_cargo() -> bool:
	if not can_expand_cargo():
		return false
	var cost := expand_cargo_cost()
	if not RunState.can_afford(cost) or not RunState.spend(cost):
		return false
	cargo_rows_bonus += 1
	save_game()
	changed.emit()
	return true


## Spends `cost` Tech Data from the inventory grid (it's a grid item now). Returns false — paying
## nothing — if there isn't enough. All base-side purchases route through here.
func _spend_tech(cost: int) -> bool:
	if RunState.get_quantity("tech_data") < cost:
		return false
	RunState.add("tech_data", -cost)
	return true


## How much Tech Data is on hand to spend (in the inventory grid).
func tech_data_on_hand() -> int:
	return RunState.get_quantity("tech_data")

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
const NEED_MAX := 10   # components to fully satisfy one need — the main "length of the game" dial
const NEED_COMPONENT := {
	"reinforced_frame": "oxygen",   # steel frame — seals the lair
	"power_coupling": "power",       # steel+copper — wiring
	"control_assembly": "water",     # copper+plastic — filtration
	"thermal_core": "food",          # copper+plastic — the grow-lamp core
}
var lair_needs: Dictionary = {}
var beacon_sent := false            # the distress beacon has been sent — you're rescued (win)

## The colony: the NAMED goblins you can deploy from the bot. Permadeath — a goblin lost in the
## field is moved to `fallen` for good (it never comes back). The colony regrows by RECRUITING
## at the System Terminal (spends banked Tech Data), capped at COLONY_MAX. `colony` is kept only
## as the legacy count for save migration + the first-run seed; `roster` is the source of truth.
const COLONY_MAX := 6
const GOBLIN_NAMES := [
	"Gruzzle", "Snik", "Borg", "Mo", "Krunk", "Zizz", "Grub", "Nix",
	"Wort", "Durp", "Skab", "Fizz", "Brak", "Hodd", "Lurk", "Pib",
]
var roster: Array = []   # living goblins: [{name:String, hauled:int, tool:String}]
var fallen: Array = []   # the memorial — goblins lost in the field: [{name:String, hauled:int}]
var colony := 3          # legacy / migration seed only (see roster)

## SCRAP TOOLS — what a goblin can scrap is gated by the tier of its equipped tool (not the
## factory). Tools are distinct items you SWAP between goblins, and better ones are FOUND in runs
## (added to `tools_found`, then equipped back home). Every goblin starts with the tier-1 tool so
## the game is playable from the first run. Tiers match FactoryGrid.SCRAP_ORDER (1 steel … 4 ceramic).
const TOOLS := {
	"scrap_claw": {"name": "Scrap Claw", "tier": 1},
	"copper_cutter": {"name": "Copper Cutter", "tier": 2},
	"poly_ripper": {"name": "Poly Ripper", "tier": 3},
	"ceramic_saw": {"name": "Ceramic Saw", "tier": 4},
}
const STARTER_TOOL := "scrap_claw"
## Base chain product per tier (the process-line output that replaced the recycler material).
## UPGRADING a tool to the next tier costs the CURRENT tier's base product — a self-gating ladder fed
## by what the colony brings home + refines on the process lines.
const TIER_MATERIAL := ["steel_plate", "copper_sheet", "plastic_casing", "ceramic_tile"]
const UPGRADE_TOOL_AMOUNT := 3
## Maps a machine's material FAMILY (still used for tier gating) to its base chain product (for costs).
const MATERIAL_PRODUCT := {"steel": "steel_plate", "copper": "copper_sheet", "plastic": "plastic_casing", "ceramic": "ceramic_tile"}
var tools_found: Array = []   # tool ids found but not yet equipped to a goblin (the swap pool)

## Colony quests (see data/game/quests.json): progress is computed live from this state; a finished
## quest is CLAIMED once for its reward. `quests_claimed` holds the ids already claimed (persisted).
var quests_claimed: Array = []

## Phase 4 recipe book (hybrid): product ids of process-chain recipes DISCOVERED by making them. Recipes
## flagged `known:true` in process.json are known from the start (not logged here); the rest reveal in
## the book the first time a chain produces them. Persisted across runs.
var discovered_recipes: Array = []

## Phase 6 cold-open / onboarding (persisted). `first_run_done` flips on the first successful return and
## stops the guided nudges; `seen_nudges` are the one-time contextual hint ids already shown; when
## `debug_pending` is set (via Debug Lair) RunController bootstraps a fully-stocked test lair on boot.
var first_run_done := false
var seen_nudges: Array = []
var debug_pending := false


## True if this contextual nudge should fire now (first run, not yet seen). Marks it seen + saves.
func should_nudge(id: String) -> bool:
	if first_run_done or seen_nudges.has(id):
		return false
	seen_nudges.append(id)
	save_game()
	return true


## Marks the first run complete (called on the first non-lost return) so the guide goes quiet.
func mark_first_run_done() -> void:
	if first_run_done:
		return
	first_run_done = true
	save_game()


## NEW GAME — wipe every persistent field back to a fresh colony and save. (Title screen → New Game.)
func reset_new_game() -> void:
	unlocked.clear()
	mars_delivered.clear()
	machines_unlocked.clear()
	factory_blob = ""
	bay_blob = ""
	process_blob = ""
	cargo_rows_bonus = 0
	machine_levels.clear()
	machine_storage.clear()
	machine_instances.clear()
	lair_cells.clear()
	lair_grid.clear()
	lair_stations.clear()
	lair_needs.clear()
	beacon_sent = false
	tools_found.clear()
	quests_claimed.clear()
	discovered_recipes.clear()
	first_run_done = false
	seen_nudges.clear()
	debug_pending = false
	roster.clear()
	fallen.clear()
	colony = 3
	ensure_roster()
	save_game()


## DEBUG LAIR — a fresh game pre-stocked for testing: a bigger colony, a couple of techs unlocked, and a
## flag telling RunController to place every station + drop a materials bundle on the next boot. Nudges
## are suppressed. (Title screen → Debug Lair.)
func start_debug_lair() -> void:
	reset_new_game()
	seed_colony(4)
	for tid: String in ["repair_t2", "tools_t2"]:
		if GameData.tech.has(tid) and not unlocked.has(tid):
			unlocked.append(tid)
	debug_pending = true
	first_run_done = true   # skip the guided nudges when testing
	save_game()


## True if the recipe for `product` is in the book: a starter (`known:true`) or already discovered.
func is_recipe_known(product: String) -> bool:
	if discovered_recipes.has(product):
		return true
	for r: Dictionary in GameData.process_recipes:
		if String(r.get("product", "")) == product:
			return bool(r.get("known", false))
	return false


## Logs a recipe the first time it's made (ignored if already known/discovered). Returns true if newly
## discovered (worth a "New recipe!" nudge).
func discover_recipe(product: String) -> bool:
	if product == "" or is_recipe_known(product):
		return false
	discovered_recipes.append(product)
	save_game()
	changed.emit()
	return true


## Every recipe currently in the book (starter-known + discovered), in process.json order — for the UI.
func known_recipes() -> Array:
	var out: Array = []
	for r: Dictionary in GameData.process_recipes:
		if is_recipe_known(String(r.get("product", ""))):
			out.append(r)
	return out


## Live progress toward a quest's goal (compared against goal.target). Pure read of current state.
func quest_current(goal: Dictionary) -> int:
	match String(goal.get("type", "")):
		"colony":
			return colony_size()
		"tool_tier":
			return best_tool_tier()
		"need":
			return need_amount(String(goal.get("key", "")))
		"need_total":
			var total := 0
			for need: String in LAIR_NEEDS:
				total += need_amount(need)
			return total
		"machine_level":
			return machine_level(String(goal.get("key", "")))
		"tech":
			return 1 if has_tech(String(goal.get("key", ""))) else 0
		"stations":
			return lair_stations.size()      # Phase 6 intro quest: build out the lair
		"recipes":
			return discovered_recipes.size() # Phase 6 intro quest: make/discover a product
	return 0


func quest_target(goal: Dictionary) -> int:
	return maxi(int(goal.get("target", 1)), 1)


func quest_done(q: Dictionary) -> bool:
	return quest_current(q.get("goal", {})) >= quest_target(q.get("goal", {}))


func quest_claimed(id: String) -> bool:
	return quests_claimed.has(id)


## Claims a finished, unclaimed quest: grants its reward (Tech Data into the run inventory) and
## records it so it can't be claimed twice. Returns true on a successful claim.
func claim_quest(q: Dictionary) -> bool:
	var id := String(q.get("id", ""))
	if id == "" or quest_claimed(id) or not quest_done(q):
		return false
	quests_claimed.append(id)
	var reward: Dictionary = q.get("reward", {})
	var td := int(reward.get("tech_data", 0))
	if td > 0:
		RunState.add("tech_data", td)
	save_game()
	changed.emit()
	return true


## A tool's tier (0 if it isn't a known tool / bare hands).
func tool_tier(tool_id: String) -> int:
	return int(TOOLS.get(tool_id, {}).get("tier", 0))


## The tool id at a given tier (1 steel … 4 ceramic), or "" if none.
func tool_id_for_tier(tier: int) -> String:
	for id: String in TOOLS:
		if int(TOOLS[id].get("tier", 0)) == tier:
			return id
	return ""


## The material + amount it costs to upgrade a goblin's tool one tier, or {} if it's maxed (tier 4)
## OR the next tier isn't unlocked yet (a Tech Data toolsmithing gate — see can_use_tool_tier).
func upgrade_tool_cost(gob_name: String) -> Dictionary:
	var t := goblin_tool_tier(gob_name)
	if t < 1 or t >= 4 or not can_use_tool_tier(t + 1):
		return {}
	return {TIER_MATERIAL[t - 1]: UPGRADE_TOOL_AMOUNT}


## Sets a living goblin's equipped tool outright (used by the terminal's upgrade). Saves.
func set_goblin_tool(gob_name: String, tool_id: String) -> bool:
	for g: Dictionary in roster:
		if String(g.get("name", "")) == gob_name:
			g["tool"] = tool_id
			save_game()
			changed.emit()
			return true
	return false


func tool_name(tool_id: String) -> String:
	return String(TOOLS.get(tool_id, {}).get("name", tool_id))


## The scrap tier a given goblin can reach, from its equipped tool (0 if the name is unknown).
func goblin_tool_tier(gob_name: String) -> int:
	for g: Dictionary in roster:
		if String(g.get("name", "")) == gob_name:
			return tool_tier(String(g.get("tool", "")))
	return 0


## The best tool tier anywhere in the colony — the progression frontier the field generator weights
## scrap/machine spawns around. At least 1 so a starter colony still finds steel.
func best_tool_tier() -> int:
	var best := 1
	for g: Dictionary in roster:
		best = maxi(best, tool_tier(String(g.get("tool", ""))))
	return best


## Banks a tool found in the field into the swap pool (equipped to a goblin back home).
func found_tool(tool_id: String) -> void:
	if not TOOLS.has(tool_id):
		return
	tools_found.append(tool_id)
	save_game()
	changed.emit()


## The highest-tier tool in the found pool that the colony is allowed to use (capped by the unlocked
## tool tier — a higher-tier tool sits in the pool until its toolsmithing is unlocked). "" if none.
func best_available_tool() -> String:
	var best := ""
	var best_tier := 0
	var cap := max_tool_tier()
	for id: String in tools_found:
		var t := tool_tier(id)
		if t > best_tier and t <= cap:
			best_tier = t
			best = id
	return best


## Equips `tool_id` (from the pool) onto a goblin, returning its previous tool to the pool. Returns
## true on success. A no-op if the goblin or tool isn't available.
func equip_tool(gob_name: String, tool_id: String) -> bool:
	if not tools_found.has(tool_id):
		return false
	for g: Dictionary in roster:
		if String(g.get("name", "")) == gob_name:
			tools_found.erase(tool_id)
			var old := String(g.get("tool", ""))
			if TOOLS.has(old) and old != STARTER_TOOL:
				tools_found.append(old)  # the swapped-out tool goes back to the pool
			g["tool"] = tool_id
			save_game()
			changed.emit()
			return true
	return false


## How many goblins you can deploy right now.
func colony_size() -> int:
	return roster.size()


## The living goblins' names, in roster order — one per goblin a deploy spawns.
func colony_names() -> Array:
	var names: Array = []
	for g: Dictionary in roster:
		names.append(String(g.get("name", "Goblin")))
	return names


## Ensures the roster exists: on a fresh save (or one from before named goblins) it seeds the
## roster from the legacy `colony` count. Safe to call repeatedly — a no-op once populated.
func ensure_roster() -> void:
	if roster.is_empty() and colony > 0:
		for _i in colony:
			_add_goblin()


## Rebuilds the roster to exactly `n` fresh goblins and clears the memorial (tests / debug).
func seed_colony(n: int) -> void:
	roster.clear()
	fallen.clear()
	colony = n
	for _i in n:
		_add_goblin()


func _add_goblin() -> void:
	roster.append({"name": _fresh_name(), "hauled": 0, "tool": STARTER_TOOL})


## A goblin name not already in use (living or fallen), falling back to a numbered one.
func _fresh_name() -> String:
	var used := {}
	for g: Dictionary in roster:
		used[String(g.get("name", ""))] = true
	for g: Dictionary in fallen:
		used[String(g.get("name", ""))] = true
	for n: String in GOBLIN_NAMES:
		if not used.has(n):
			return n
	return "Goblin-%d" % (roster.size() + fallen.size() + 1)


## Credits a living goblin with scrap it hauled home (flavour + a meaningful memorial).
func record_haul(gob_name: String, amount: int) -> void:
	for g: Dictionary in roster:
		if String(g.get("name", "")) == gob_name:
			g["hauled"] = int(g.get("hauled", 0)) + amount
			return


## A deployed goblin fell — move it from the roster to the memorial (permanent). Returns its
## record, or {} if the name wasn't on the roster.
func lose_goblin(gob_name: String) -> Dictionary:
	for i in roster.size():
		if String(roster[i].get("name", "")) == gob_name:
			var rec: Dictionary = roster[i]
			fallen.append(rec)
			roster.remove_at(i)
			colony = roster.size()
			save_game()
			changed.emit()
			return rec
	return {}


func can_recruit() -> bool:
	return colony_size() < COLONY_MAX


## FOOD to recruit the next goblin — you feed the colony to grow it. Climbs with every goblin
## already in the colony. (Recruiting no longer costs Tech Data — that's for progression unlocks.)
func recruit_cost() -> Dictionary:
	return {"food": 3 * maxi(1, colony_size())}  # size 2→6, 3→9, 4→12, 5→15 …


## Spends Food (from the run inventory) to add a fresh goblin to the colony. Returns the new
## goblin's record, or {} if at capacity or short on Food.
func recruit() -> Dictionary:
	if not can_recruit():
		return {}
	if not RunState.can_afford(recruit_cost()) or not RunState.spend(recruit_cost()):
		return {}
	_add_goblin()
	colony = roster.size()
	save_game()
	changed.emit()
	return roster.back()


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

## Phase 1 BUILDABLE LAIR layout — the stations the player has placed, as [{type, x, y}] in tile
## coords (JSON-native, no Vector2i). Empty on a brand-new lair; RunController seeds the free defaults
## (Workshop + Mission Board) the first time. Persisted; build mode adds/removes entries.
var lair_stations: Array = []


func has_lair() -> bool:
	return not lair_cells.is_empty()


func has_lair_stations() -> bool:
	return not lair_stations.is_empty()


## Records a placed station (tile coords) and saves. Call from build mode / the default seed.
func add_lair_station(type: String, tx: int, ty: int) -> void:
	lair_stations.append({"type": type, "x": tx, "y": ty})
	save_game()


## Removes the station at the given tile (if any) and saves. Returns true if one was removed.
func remove_lair_station_at(tx: int, ty: int) -> bool:
	for i in lair_stations.size():
		var s: Dictionary = lair_stations[i]
		if int(s.get("x", -9999)) == tx and int(s.get("y", -9999)) == ty:
			lair_stations.remove_at(i)
			save_game()
			return true
	return false


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


## REFINED MATERIALS to take a machine type from its current level to the next — paid in the
## machine's own family material (steel/copper/plastic/ceramic), or steel for family-less machines.
## (Machine upgrades no longer cost Tech Data — that's for progression unlocks.)
func machine_upgrade_cost(def_id: String) -> Dictionary:
	return {_upgrade_material(def_id): 2 * machine_level(def_id)}  # 1→2:2, 2→3:4, 3→4:6, 4→5:8


## The refined material a machine is associated with: its family material if it has one, else the
## material named in its id prefix (copper_recycler → copper), else "" (family-less, e.g. frame_maker).
func _machine_material(def_id: String) -> String:
	var fam := String(GameData.machines.get(def_id, {}).get("family", ""))
	if fam in ["steel", "copper", "plastic", "ceramic"]:
		return fam
	for mat: String in ["steel", "copper", "plastic", "ceramic"]:
		if def_id.begins_with(mat + "_"):
			return mat
	return ""


## The base chain PRODUCT a machine's upgrades are paid in (its family's product, else steel plate).
func _upgrade_material(def_id: String) -> String:
	return String(MATERIAL_PRODUCT.get(_machine_material(def_id), "steel_plate"))


## Spends refined materials (from the run inventory) to raise a machine type's permanent level.
func upgrade_machine(def_id: String) -> bool:
	if not can_upgrade_machine(def_id):
		return false
	var cost := machine_upgrade_cost(def_id)
	if not RunState.can_afford(cost) or not RunState.spend(cost):
		return false
	machine_levels[def_id] = machine_level(def_id) + 1
	save_game()
	changed.emit()
	return true


# ------------------------------------------------- progression (Tech Data) ----

## Material-tier order for machines + tools (steel 1 → copper 2 → plastic 3 → ceramic 4).
const FAMILY_TIER := {"steel": 1, "copper": 2, "plastic": 3, "ceramic": 4}


## A machine's material tier (for the repair gate): from its material (family or id prefix), or 1
## (always repairable) for family-less machines like component makers and the smelter.
func machine_tier(def_id: String) -> int:
	return int(FAMILY_TIER.get(_machine_material(def_id), 1))


## The highest machine tier goblins may repair — tier 1 by default, raised by Tech Data unlocks
## (repair_t2/t3/t4). This is the "repair tier-two machines" progression gate.
func max_repair_tier() -> int:
	var best := 1
	for tid: String in unlocked:
		var def: Dictionary = GameData.tech.get(tid, {})
		if String(def.get("effect", "")) == "repair_tier":
			best = maxi(best, int(def.get("value", 1)))
	return best


## True if the colony has unlocked repairing this machine's tier.
func can_repair(def_id: String) -> bool:
	return machine_tier(def_id) <= max_repair_tier()


## The highest tool tier the colony may equip/upgrade to — tier 1 by default, raised by Tech Data
## unlocks (tools_t2/t3/t4). This is the "use higher-tier tools" progression gate.
func max_tool_tier() -> int:
	var best := 1
	for tid: String in unlocked:
		var def: Dictionary = GameData.tech.get(tid, {})
		if String(def.get("effect", "")) == "tool_tier":
			best = maxi(best, int(def.get("value", 1)))
	return best


func can_use_tool_tier(tier: int) -> bool:
	return tier <= max_tool_tier()


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


## Persists the scrapbot's module-bay loadout (called when a run ends).
func save_bay(grid: FactoryGrid) -> void:
	bay_blob = var_to_str(grid.to_data()) if grid != null else ""
	save_game()


## Rebuilds the persisted module bay, or null if there isn't one.
func load_bay() -> FactoryGrid:
	if bay_blob == "":
		return null
	var data: Variant = str_to_var(bay_blob)
	return FactoryGrid.from_data(data) if data is Dictionary else null


func has_process_line() -> bool:
	return process_blob != ""


## Persists the workshop process line (called when a run ends).
func save_process(grid: ProcessGrid) -> void:
	process_blob = var_to_str(grid.to_data()) if grid != null else ""
	save_game()


## Rebuilds the persisted process line, or null if there isn't one.
func load_process() -> ProcessGrid:
	if process_blob == "":
		return null
	var data: Variant = str_to_var(process_blob)
	return ProcessGrid.from_data(data) if data is Dictionary else null


## Persists the machine/transport storage (call after repairs or placements change it).
func save_storage() -> void:
	save_game()


## Wipes the saved factory (used by the big-machine extraction and by starting over).
func clear_factory() -> void:
	factory_blob = ""
	save_game()


func _ready() -> void:
	load_game()
	ensure_roster()  # a brand-new game (no save file) still starts with a named colony


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
	if not _spend_tech(cost):
		return false
	unlocked.append(tech_id)
	save_game()
	changed.emit()
	return true


## Banks a shipped delivery (id -> count) toward Mars re-commissioning. Permanent.
## Returns the names of any machines this delivery newly unlocked (for the summary).
func bank_delivery(items: Dictionary) -> Array:
	for id: String in items:
		mars_delivered[id] = int(mars_delivered.get(id, 0)) + int(items[id])
	var newly := _check_unlocks()
	save_game()
	changed.emit()
	return newly


## The nearest not-yet-earned machine unlock as a short hint like
## "ship 2 Circuit Board → Constructor", or "" if everything is unlocked.
func next_unlock_hint() -> String:
	var best_total := 1 << 30
	var best := ""
	for id: String in GameData.machines:
		var s := _unlock_remaining(GameData.machines[id], id, machines_unlocked)
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
	return newly


## Total resources delivered home across all runs.
func mars_total() -> int:
	var total := 0
	for id: String in mars_delivered:
		total += int(mars_delivered[id])
	return total


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
		"unlocked": unlocked,
		"mars_delivered": mars_delivered,
		"machines_unlocked": machines_unlocked,
		"factory": factory_blob,
		"bay": bay_blob,
		"process": process_blob,
		"cargo_rows_bonus": cargo_rows_bonus,
		"machine_levels": machine_levels,
		"lair_cells": lair_cells,
		"lair_grid": lair_grid,
		"lair_stations": lair_stations,
		"machine_storage": machine_storage,
		"machine_instances": var_to_str(machine_instances),
		"lair_needs": lair_needs,
		"beacon_sent": beacon_sent,
		"colony": colony_size(),   # legacy count (kept in sync with the roster)
		"roster": roster,
		"fallen": fallen,
		"tools_found": tools_found,
		"quests_claimed": quests_claimed,
		"discovered_recipes": discovered_recipes,
		"first_run_done": first_run_done,
		"seen_nudges": seen_nudges,
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
	unlocked.clear()
	for id: Variant in data.get("unlocked", []):
		unlocked.append(String(id))
	mars_delivered.clear()
	var saved: Dictionary = data.get("mars_delivered", {})
	for id: Variant in saved:
		mars_delivered[String(id)] = int(saved[id])
	machines_unlocked.clear()
	for id: Variant in data.get("machines_unlocked", []):
		machines_unlocked.append(String(id))
	factory_blob = String(data.get("factory", ""))
	bay_blob = String(data.get("bay", ""))
	process_blob = String(data.get("process", ""))
	cargo_rows_bonus = clampi(int(data.get("cargo_rows_bonus", 0)), 0, CARGO_BONUS_MAX)
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
	lair_stations.clear()
	for s: Variant in data.get("lair_stations", []):
		if s is Dictionary and GameData.stations.has(String(s.get("type", ""))):
			lair_stations.append({"type": String(s.get("type", "")), "x": int(s.get("x", 0)), "y": int(s.get("y", 0))})
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
	colony = int(data.get("colony", 3))
	roster.clear()
	for rec: Variant in data.get("roster", []):
		if rec is Dictionary:
			var tool_id := String(rec.get("tool", STARTER_TOOL))
			if not TOOLS.has(tool_id):
				tool_id = STARTER_TOOL  # migrate a pre-tool save
			roster.append({"name": String(rec.get("name", "Goblin")), "hauled": int(rec.get("hauled", 0)), "tool": tool_id})
	fallen.clear()
	for rec: Variant in data.get("fallen", []):
		if rec is Dictionary:
			fallen.append({"name": String(rec.get("name", "Goblin")), "hauled": int(rec.get("hauled", 0))})
	tools_found.clear()
	for tid: Variant in data.get("tools_found", []):
		if TOOLS.has(String(tid)):
			tools_found.append(String(tid))
	discovered_recipes.clear()
	for rid: Variant in data.get("discovered_recipes", []):
		discovered_recipes.append(String(rid))
	first_run_done = bool(data.get("first_run_done", false))
	seen_nudges.clear()
	for nid: Variant in data.get("seen_nudges", []):
		seen_nudges.append(String(nid))
	quests_claimed.clear()
	for qid: Variant in data.get("quests_claimed", []):
		quests_claimed.append(String(qid))
	ensure_roster()  # migrate a pre-roster save (or seed a fresh one) from the legacy count
