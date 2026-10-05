extends Node
## C2 — the cost-chain ladder: bridge components craft from prior-tier materials, repair costs
## escalate in the prior tier's material, and leveling the Scrapper Arm costs Tech Data + the
## tier's bridge component (consumed from the factory). (Writes the save — runner backs it up.)

var fail := 0


func _ready() -> void:
	# --- bridge recipe: frame_maker turns 2 steel into a reinforced_frame (the T1→T2 bridge) ---
	var g := FactoryGrid.new(8, 8)
	g.place_machine_layout("frame_maker", Vector2i(3, 3), [Vector2i(-1, 0)], [Vector2i(1, 0)], [], [])
	g.set_cell(Vector2i(2, 3), {"kind": "resource", "id": "steel", "count": 2})
	for _t in 5: g.tick(3.5)
	_ck(int(g.resource_counts().get("reinforced_frame", 0)) > 0, "frame_maker: 2 steel → reinforced_frame")

	# --- tier-escalating repair costs ---
	var gen := AreaGenerator.new()
	_ck(gen._repair_cost_for("Recycler", "steel_recycler") == {"steel": 2}, "steel-tier repair is cheap steel")
	_ck(gen._repair_cost_for("Recycler", "copper_recycler") == {"steel": 4}, "copper machines cost steel")
	_ck(gen._repair_cost_for("Ammo Maker", "plastic_ammo_maker") == {"copper": 4}, "plastic machines cost copper")
	_ck(gen._repair_cost_for("Weapon", "ceramic_weapon") == {"plastic": 4}, "ceramic machines cost plastic")
	_ck(gen._repair_cost_for("Transport", "__conveyor") == {"steel": 1}, "transport is cheapest (steel)")
	_ck(gen._repair_cost_for("Component Maker", "frame_maker") == {"steel": 3}, "cross-tier makers default to steel")
	gen.free()

	# --- arm unlock gate: Tech Data + the bridge component, consumed from the factory ---
	MetaState.machine_levels = {}           # arm level 1
	MetaState.tech_data = 100               # plenty banked
	RunState.begin_run(GameData.first_area_id(), 1)
	RunState.factory = FactoryGrid.new(8, 8)
	var panel := TerminalPanel.new()
	add_child(panel)

	panel._upgrade_arm()                    # no frame in the factory yet
	_ck(MetaState.machine_level("scrapper_arm") == 1, "arm won't level without the bridge component")

	RunState.add("reinforced_frame", 1)     # produce the T1→T2 bridge into the grid
	var td_before := MetaState.tech_data
	panel._upgrade_arm()
	_ck(MetaState.machine_level("scrapper_arm") == 2, "arm levels to 2 with frame + Tech Data (copper unlocked)")
	_ck(int(RunState.get_quantity("reinforced_frame")) == 0, "the bridge component was consumed")
	_ck(MetaState.tech_data < td_before, "Tech Data was spent too")

	MetaState.machine_levels = {}
	if fail == 0:
		print("LADDER_TEST: ALL PASS")
	else:
		printerr("LADDER_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
