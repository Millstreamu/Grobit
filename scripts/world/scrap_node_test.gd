extends Node
## Hold-to-harvest scrap piles. Holding [F] fills a timer; each completion stacks one unit
## of scrap into the Scrapper Arm bar (RunState.arm_scrap, to 99). General junk goes to the
## grid instead. A slot that's full pauses the pile; an emptied pile is removed.

var fail := 0
const H := ScrapNode.HARVEST_SECONDS


func _ready() -> void:
	RunState.begin_run(GameData.first_area_id(), 1)  # bare grid + empty arm bar

	var n := ScrapNode.new()
	n.generate({"tokens_min": 5, "tokens_max": 5, "pool": [{"id": "copper_scrap", "weight": 1}]})
	add_child(n)

	# A partial hold deposits nothing.
	n.hold_interact(H * 0.5)
	_ck(RunState.arm_count("copper_scrap") == 0, "a partial hold deposits nothing")

	# Completing the fill stacks one copper scrap into the arm and spends a charge.
	n.hold_interact(H * 0.5 + 0.01)
	_ck(RunState.arm_count("copper_scrap") == 1 and n.tokens == 4, "a full hold stacks one scrap into the arm")

	# Releasing resets the in-progress fill.
	n.hold_interact(H * 0.6)
	n.hold_release()
	n.hold_interact(H * 0.6)
	_ck(RunState.arm_count("copper_scrap") == 1, "releasing [F] resets progress")

	# A full arm slot (99) pauses harvesting.
	RunState.arm_scrap["copper_scrap"] = RunState.ARM_STACK_MAX
	var before := n.tokens
	n.hold_interact(H + 0.1)
	_ck(n.tokens == before, "a full arm slot pauses harvesting (no charge spent)")

	# Draining the last charge frees the pile.
	RunState.arm_scrap["copper_scrap"] = 0
	var s := ScrapNode.new()
	s.generate({"tokens_min": 1, "tokens_max": 1, "pool": [{"id": "steel_scrap", "weight": 1}]})
	add_child(s)
	s.hold_interact(H + 0.1)
	_ck(RunState.arm_count("steel_scrap") == 1 and s.is_spent(), "last charge empties the pile into the arm")
	_ck(s.is_queued_for_deletion(), "an emptied pile is removed")

	# General junk routes to the grid, not the arm.
	var j := ScrapNode.new()
	j.generate({"tokens_min": 1, "tokens_max": 1, "pool": [{"id": "junk", "weight": 1}]})
	add_child(j)
	j.hold_interact(H + 0.1)
	_ck(int(RunState.currency_count("junk")) >= 1, "general junk goes to the Scrap currency, not a grid cell or arm slot")
	_ck(int(RunState.resource_counts().get("junk", 0)) == 0, "junk never takes a grid cell")

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
