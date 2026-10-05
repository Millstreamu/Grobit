extends Node
## Hold-to-harvest scrap piles. Holding [F] fills a timer; each completion stacks one unit of
## scrap into the Scrapper Arm MACHINE's matching typed slot (FactoryGrid.deposit_harvest). A
## non-scrap item goes to the grid instead. A full slot pauses the pile; an emptied pile is
## removed. (Uses STEEL — tier 1, unlocked at the default arm level 1.)

var fail := 0
const H := ScrapNode.HARVEST_SECONDS


func _ready() -> void:
	MetaState.machine_levels = {}  # arm level 1 (steel unlocked)
	RunState.begin_run(GameData.first_area_id(), 1)  # bare grid + empty arm bar
	var arm := RunState.factory.place_scrapper_arm(Vector2i(0, 0))
	_ck(arm >= 0, "scrapper arm placed for harvesting")
	var steel_slot := Vector2i(1, 0)

	var n := ScrapNode.new()
	n.generate({"tokens_min": 5, "tokens_max": 5, "pool": [{"id": "steel_scrap", "weight": 1}]})
	add_child(n)

	# A partial hold deposits nothing.
	n.hold_interact(H * 0.5)
	_ck(RunState.factory.arm_slot_count("steel_scrap") == 0, "a partial hold deposits nothing")

	# Completing the fill stacks one steel scrap into the arm slot and spends a charge.
	n.hold_interact(H * 0.5 + 0.01)
	_ck(RunState.factory.arm_slot_count("steel_scrap") == 1 and n.tokens == 4, "a full hold stacks one scrap into the arm")

	# Releasing resets the in-progress fill.
	n.hold_interact(H * 0.6)
	n.hold_release()
	n.hold_interact(H * 0.6)
	_ck(RunState.factory.arm_slot_count("steel_scrap") == 1, "releasing [F] resets progress")

	# A full slot pauses harvesting.
	RunState.factory.get_cell(steel_slot)["count"] = FactoryGrid.ARM_SLOT_MAX
	var before := n.tokens
	n.hold_interact(H + 0.1)
	_ck(n.tokens == before, "a full arm slot pauses harvesting (no charge spent)")

	# Draining the slot frees the pile.
	RunState.factory.get_cell(steel_slot)["count"] = 0
	var s := ScrapNode.new()
	s.generate({"tokens_min": 1, "tokens_max": 1, "pool": [{"id": "steel_scrap", "weight": 1}]})
	add_child(s)
	s.hold_interact(H + 0.1)
	_ck(RunState.factory.arm_slot_count("steel_scrap") == 1 and s.is_spent(), "last charge empties the pile into the arm")
	_ck(s.is_queued_for_deletion(), "an emptied pile is removed")

	# A pile of a LOCKED tier (copper at arm level 1) can't be harvested at all.
	var locked := ScrapNode.new()
	locked.generate({"tokens_min": 2, "tokens_max": 2, "pool": [{"id": "copper_scrap", "weight": 1}]})
	add_child(locked)
	locked.hold_interact(H + 0.1)
	_ck(locked.tokens == 2 and RunState.factory.arm_slot_count("copper_scrap") == 0, "a locked-tier pile yields nothing (inert)")

	# A non-scrap item (e.g. a refined material) routes to the factory grid, not the arm.
	var j := ScrapNode.new()
	j.generate({"tokens_min": 1, "tokens_max": 1, "pool": [{"id": "copper", "weight": 1}]})
	add_child(j)
	j.hold_interact(H + 0.1)
	_ck(int(RunState.resource_counts().get("copper", 0)) >= 1, "a non-scrap item goes to a grid cell")
	_ck(RunState.factory.arm_slot_count("copper") == 0, "a non-scrap item never takes an arm slot")

	if fail == 0:
		print("SCRAP_NODE_TEST: ALL PASS")
	else:
		printerr("SCRAP_NODE_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
