extends Node
## Tool finding + equip. Tools are found in the field (ToolPickup → the colony pool), weighted
## toward the frontier + 1, then equipped onto a goblin at the System Terminal. Drives the real
## pickup, generator roll, and MetaState equip logic.

var fail := 0


func _ready() -> void:
	MetaState.seed_colony(2)   # two starter (tier-1) goblins, empty tool pool
	MetaState.tools_found.clear()
	MetaState.unlocked.append("tools_t4")  # higher tool tiers are Tech-Data unlocks now; unlock them so found tools are usable

	# Taking a tool pickup drops it into the colony's tool pool.
	var pickup := ToolPickup.new()
	pickup.tool_id = "copper_cutter"
	add_child(pickup)
	pickup.interact()
	_ck(MetaState.tools_found.has("copper_cutter"), "taking a tool pickup adds it to the pool")
	_ck(pickup.is_queued_for_deletion(), "the field pickup is consumed")

	# best_available_tool surfaces the highest-tier pooled tool.
	MetaState.found_tool("ceramic_saw")
	_ck(MetaState.best_available_tool() == "ceramic_saw", "best_available_tool picks the highest tier in the pool")

	# Equipping the best tool raises that goblin's reach and pulls it from the pool.
	var who := String(MetaState.colony_names()[0])
	MetaState.equip_tool(who, "ceramic_saw")
	_ck(MetaState.goblin_tool_tier(who) == 4, "%s equips the tier-4 tool" % who)
	_ck(not MetaState.tools_found.has("ceramic_saw"), "the equipped tool left the pool")
	_ck(MetaState.best_tool_tier() == 4, "the colony frontier rises to the equipped tool")

	# The generator rolls tool tiers weighted toward the frontier + 1 (the upgrade you want).
	MetaState.seed_colony(1)   # frontier back to tier 1 → want = tier 2 (copper)
	MetaState.tools_found.clear()
	var gen := AreaGenerator.new()
	add_child(gen)
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	var want := 0
	for _i in 400:
		if MetaState.tool_tier(gen._roll_tool_id(rng)) == 2:
			want += 1
	_ck(want > 200, "most field tools roll at the wanted tier (frontier+1): %d/400" % want)

	MetaState.seed_colony(3)
	MetaState.tools_found.clear()
	if fail == 0:
		print("TOOL_FIND_TEST: ALL PASS")
	else:
		printerr("TOOL_FIND_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
