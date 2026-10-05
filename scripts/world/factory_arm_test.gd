extends Node
## Scrapper Arm = a 5-cell MACHINE whose LEVEL gates its scrap tiers: L1 steel, L2 +copper,
## L3 +plastic, L4 +ceramic. Slots sit in tier order. Harvested scrap stacks into its unlocked
## slot; a recycler whose input touches a slot pulls it out. Locked tiers refuse harvest.

func _ready() -> void:
	var fails := 0
	MetaState.machine_levels = {}  # arm defaults to level 1 (steel only)
	var g := FactoryGrid.new(8, 5)
	var mi := g.place_scrapper_arm(Vector2i(0, 0))
	fails += _ck(mi >= 0, "scrapper arm placed (core + 4 slots)")

	# Slots are laid out in tier order: steel first.
	fails += _ck(String(g.get_cell(Vector2i(1, 0)).get("scrap", "")) == "steel_scrap", "first slot is steel (tier 1)")
	fails += _ck(String(g.get_cell(Vector2i(2, 0)).get("scrap", "")) == "copper_scrap", "second slot is copper (tier 2)")

	# At level 1 only steel is accepted; copper/plastic/ceramic are locked (inert).
	fails += _ck(g.arm_accepts("steel_scrap"), "arm accepts steel at level 1")
	fails += _ck(not g.arm_accepts("copper_scrap"), "arm REFUSES copper at level 1 (locked tier)")
	fails += _ck(g.deposit_harvest("steel_scrap"), "harvesting steel goes into the arm")
	fails += _ck(not g.deposit_harvest("copper_scrap"), "harvesting copper is refused while its tier is locked")
	fails += _ck(g.arm_slot_count("copper_scrap") == 0, "nothing landed in the locked copper slot")

	# Levelling the arm to 2 unlocks copper.
	MetaState.machine_levels["scrapper_arm"] = 2
	fails += _ck(g.arm_accepts("copper_scrap"), "copper unlocks at arm level 2")
	fails += _ck(g.deposit_harvest("copper_scrap"), "copper can now be harvested")

	# A recycler whose input touches the steel slot pulls the scrap out and makes steel.
	g.get_cell(Vector2i(1, 0))["count"] = 3
	var rec := g.place_machine("steel_recycler", Vector2i(2, 1))  # input (1,1), below steel slot (1,0)
	fails += _ck(rec >= 0, "steel recycler placed next to the arm")
	for _t in 4:
		g.tick(2.5)
	fails += _ck(int(g.resource_counts().get("steel", 0)) > 0, "recycler pulled steel scrap from the arm and made steel")
	fails += _ck(g.arm_slot_count("steel_scrap") < 3, "the arm's steel slot was drained by the pull")

	# Full slot refuses more.
	for _i in FactoryGrid.ARM_SLOT_MAX:
		g.deposit_harvest("copper_scrap")
	fails += _ck(g.arm_slot_count("copper_scrap") == FactoryGrid.ARM_SLOT_MAX, "copper slot fills to the cap")
	fails += _ck(not g.deposit_harvest("copper_scrap"), "a full slot refuses more scrap")

	MetaState.machine_levels = {}
	if fails == 0:
		print("FACTORY_ARM_TEST: ALL PASS")
	else:
		printerr("FACTORY_ARM_TEST: %d FAIL" % fails)
	get_tree().quit(fails)


func _ck(c: bool, l: String) -> int:
	if c:
		print("  ok: ", l)
		return 0
	printerr("  FAIL: ", l)
	return 1
