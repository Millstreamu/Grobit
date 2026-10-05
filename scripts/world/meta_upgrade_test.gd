extends Node
## Tech-Data meta: permanent machine upgrades (bought at a System Terminal) make a machine
## TYPE faster, persist via MetaState, and apply to every placed machine of that type. Also:
## run-end no longer auto-banks Tech Data (you must upload it at a terminal).

var fail := 0


func _ready() -> void:
	MetaState.machine_levels = {}  # in-memory only — no disk writes in this test

	# Upgrade bookkeeping (pure reads).
	_ck(MetaState.machine_level("copper_recycler") == 1, "machines default to level 1")
	_ck(MetaState.can_upgrade_machine("copper_recycler"), "can upgrade below max")
	_ck(MetaState.machine_upgrade_cost("copper_recycler") == 3, "upgrade cost is 3 × current level")
	MetaState.machine_levels["copper_recycler"] = MetaState.MAX_MACHINE_LEVEL
	_ck(not MetaState.can_upgrade_machine("copper_recycler"), "can't upgrade past max level")

	# A permanent upgrade makes that machine TYPE faster. Smelter base time is 3.0s.
	MetaState.machine_levels = {}
	var g1 := _smelter_grid()  # level 1 → 3.0s
	for _t in 5:
		g1.tick(0.5)  # 2.5s elapsed
	_ck(g1.get_cell(Vector2i(3, 2)).is_empty(), "a level-1 smelter is NOT done at 2.5s")

	MetaState.machine_levels = {"smelter": 3}  # 3.0 × 0.85^2 ≈ 2.17s
	var g3 := _smelter_grid()
	for _t in 5:
		g3.tick(0.5)  # 2.5s elapsed
	_ck(String(g3.get_cell(Vector2i(3, 2)).get("id", "")) == "metal_bar", "a level-3 smelter IS done at 2.5s (upgrade = faster)")

	# Run-end no longer auto-banks Tech Data — it must be uploaded at a terminal.
	MetaState.machine_levels = {}
	RunState.begin_run(GameData.first_area_id(), 1)
	RunState.add("tech_data", 7)  # earned in-run
	var banked_before := MetaState.tech_data
	RunState.end_run(RunState.RESULT_SHIPPED)
	_ck(MetaState.tech_data == banked_before, "end_run no longer auto-banks Tech Data")

	MetaState.machine_levels = {}  # leave MetaState as we found it (in-memory)

	if fail == 0:
		print("META_UPGRADE_TEST: ALL PASS")
	else:
		printerr("META_UPGRADE_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _smelter_grid() -> FactoryGrid:
	var g := FactoryGrid.new(6, 6)
	g.place_machine("smelter", Vector2i(2, 2))  # input (1,2), output (3,2)
	g.set_cell(Vector2i(1, 2), {"kind": "resource", "id": "scrap_metal"})
	return g


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
