extends Node
## The reworked economy: Tech Data is PROGRESSION-UNLOCK currency (higher-tier machine repair +
## higher-tier tools are gated until unlocked), while everyday spending uses FOOD (recruiting) and
## REFINED MATERIALS (machine upgrades, cargo expansion). Drives the MetaState rules directly.

var fail := 0


func _ready() -> void:
	RunState.begin_run(GameData.first_area_id(), 1)
	MetaState.unlocked.clear()
	MetaState.tools_found.clear()  # start from a clean slate (ignore whatever the real save had)
	MetaState.seed_colony(1)

	# A machine's tier comes from its material (family or id prefix).
	_ck(MetaState.machine_tier("steel_recycler") == 1, "steel machines are tier 1")
	_ck(MetaState.machine_tier("copper_recycler") == 2, "copper machines are tier 2")
	_ck(MetaState.machine_tier("ceramic_weapon") == 4, "ceramic machines are tier 4")
	_ck(MetaState.machine_tier("frame_maker") == 1, "family-less machines are tier 1 (always repairable)")

	# REPAIR gate: tier 1 only until unlocked with Tech Data.
	_ck(MetaState.max_repair_tier() == 1, "repair capped at tier 1 by default")
	_ck(MetaState.can_repair("steel_recycler"), "goblins can repair tier-1 machines")
	_ck(not MetaState.can_repair("copper_recycler"), "can't repair tier-2 machines yet")
	MetaState.unlocked.append("repair_t2")
	_ck(MetaState.can_repair("copper_recycler"), "repair_t2 unlocks tier-2 repair")
	_ck(not MetaState.can_repair("plastic_recycler"), "but not tier-3 until repair_t3")

	# TOOL gate: tier 1 only until unlocked.
	_ck(MetaState.max_tool_tier() == 1, "tools capped at tier 1 by default")
	MetaState.found_tool("copper_cutter")  # a tier-2 tool found in a run
	_ck(MetaState.best_available_tool() == "", "a higher-tier found tool is unusable until unlocked")
	var who := String(MetaState.colony_names()[0])
	_ck(MetaState.upgrade_tool_cost(who).is_empty(), "tool upgrade past tier 1 is blocked until unlocked")
	MetaState.unlocked.append("tools_t2")
	_ck(MetaState.max_tool_tier() == 2, "tools_t2 raises the tool cap")
	_ck(MetaState.best_available_tool() == "copper_cutter", "the tier-2 tool becomes usable")
	_ck(not MetaState.upgrade_tool_cost(who).is_empty(), "tool upgrade to tier 2 is now allowed")

	# Everyday economy uses Food + materials, never Tech Data.
	_ck(MetaState.recruit_cost().has("food"), "recruiting costs Food")
	_ck(MetaState.machine_upgrade_cost("copper_recycler").has("copper"), "machine upgrades cost the machine's material")
	_ck(MetaState.expand_cargo_cost().has("steel"), "cargo expansion costs refined materials")

	# Spending actually draws from the inventory: recruit spends Food, upgrade spends materials.
	MetaState.seed_colony(2)
	var rc := int(MetaState.recruit_cost().get("food", 0))
	RunState.add("food", rc)
	_ck(not MetaState.recruit().is_empty() and RunState.get_quantity("food") == 0, "recruiting draws Food from the inventory")
	RunState.add("copper", 10)
	MetaState.machine_levels = {}
	var up := int(MetaState.machine_upgrade_cost("copper_recycler").get("copper", 0))
	_ck(MetaState.upgrade_machine("copper_recycler") and RunState.get_quantity("copper") == 10 - up, "upgrading draws materials from the inventory")

	MetaState.unlocked.clear()
	MetaState.machine_levels = {}
	if fail == 0:
		print("ECONOMY_GATES_TEST: ALL PASS")
	else:
		printerr("ECONOMY_GATES_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
