extends Node
## Slice 1 — the scrapbot CARGO HOLD (Dredge-style). Goblins deposit hauled scrap (1×1 stacks)
## and recovered machines (bulky crates) into a finite hold; when it fills nothing more fits; on
## extraction the hold drains into the base inventory.

const TICK := 1.0 / 60.0

var fail := 0


func _ready() -> void:
	MetaState.machine_levels = {}
	MetaState.seed_colony(1)
	RunState.begin_run(GameData.first_area_id(), 1)
	RunState.driving = true

	# --- CargoHold unit: scrap packs into 1×1 stacks, then fills, then rejects ---
	var h := CargoHold.new(2, 2)  # 4 cells
	_ck(h.capacity() == 4 and h.used() == 0, "a fresh hold is empty (cap 4)")
	_ck(h.deposit_scrap("steel_scrap", CargoHold.SCRAP_STACK) == CargoHold.SCRAP_STACK and h.used() == 1, "one full scrap stack takes one cell")
	_ck(h.deposit_scrap("steel_scrap", CargoHold.SCRAP_STACK * 3) == CargoHold.SCRAP_STACK * 3 and h.used() == 4, "overflow scrap spills into more cells")
	_ck(h.is_full() and h.deposit_scrap("steel_scrap", 1) == 0, "a full hold accepts no more scrap")
	_ck(int(h.scrap_counts().get("steel_scrap", 0)) == CargoHold.SCRAP_STACK * 4, "scrap_counts totals the hold")

	# --- bulky machines take a shaped footprint ---
	var h2 := CargoHold.new(4, 4)  # 16 cells
	var fp := h2.footprint_for("steel_recycler")
	_ck(fp.x * fp.y >= 2, "a recovered machine has a multi-cell footprint (%dx%d)" % [fp.x, fp.y])
	_ck(h2.deposit_machine("steel_recycler") and h2.used() == fp.x * fp.y, "a machine occupies its whole footprint")
	_ck(h2.machine_list() == ["steel_recycler"], "machine_list reports the stowed machine once")
	_ck(h2.footprint_for("__conveyor") == Vector2i(1, 1), "transport parts are a single cell")

	# --- a goblin deposits its haul into RunState.cargo ---
	var bot := Node2D.new()
	add_child(bot)
	var harvest := HarvestMode.new()
	harvest.bot = bot
	add_child(harvest)
	harvest.set_process(false)
	var pile := ScrapNode.new()
	pile.generate({"tokens_min": 6, "tokens_max": 6, "pool": [{"id": "steel_scrap", "weight": 1}]})
	add_child(pile)
	pile.global_position = Vector2(40, 0)
	harvest.deploy()
	var gob: HarvesterGoblin = get_tree().get_nodes_in_group("harvester_goblins")[0]
	harvest.command_target(pile)  # goblins are commanded now
	gob.global_position = pile.global_position
	for _i in 300:
		gob._physics_process(TICK)
		if gob.carrying() >= HarvesterGoblin.CARRY_CAP:
			break
	gob.global_position = bot.global_position
	gob._physics_process(TICK)
	_ck(int(RunState.cargo.scrap_counts().get("steel_scrap", 0)) == HarvesterGoblin.CARRY_CAP, "the goblin's haul lands in the bot's cargo hold (%d)" % int(RunState.cargo.scrap_counts().get("steel_scrap", 0)))

	# --- extraction drain: hold contents move into the base inventory, hold empties ---
	RunState.machine_instances = []
	RunState.cargo.deposit_machine("steel_recycler")
	var scrap_before := int(RunState.factory.resource_counts().get("steel_scrap", 0))
	var hauled := RunState.cargo.scrap_counts()
	for sid: String in hauled:
		RunState.deposit(sid, int(hauled[sid]))
	for def_id: String in RunState.cargo.machine_list():
		RunState.add_machine_instance(def_id)
	RunState.cargo.clear()
	_ck(int(RunState.factory.resource_counts().get("steel_scrap", 0)) == scrap_before + HarvesterGoblin.CARRY_CAP, "draining moves hauled scrap into the base inventory")
	_ck(RunState.machine_instances.size() == 1, "draining banks the recovered machine to storage")
	_ck(RunState.cargo.used() == 0, "the hold is empty after extraction")

	MetaState.seed_colony(3)
	if fail == 0:
		print("CARGO_HOLD_TEST: ALL PASS")
	else:
		printerr("CARGO_HOLD_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
