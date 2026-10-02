extends Node
var fail := 0
func ck(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: fail += 1; printerr("  FAIL: ", l)
func _ready() -> void:
	RunState.begin_run(GameData.first_area_id(), 42)
	var gen := AreaGenerator.new(); add_child(gen)
	gen.build(GameData.first_area_id(), 42)
	await get_tree().process_frame
	# 1. run_chain has one of each category
	ck("Recycler" in RunState.run_chain and "Ammo Maker" in RunState.run_chain and "Component Maker" in RunState.run_chain, "run_chain has all 3 categories: %s" % str(RunState.run_chain))
	# 2. a guaranteed broken machine of each category exists in the world
	var cats := {}
	for p in get_tree().get_nodes_in_group("pickups"):
		if p is MachinePickup and p.broken:
			cats[p.category] = true
	ck(cats.has("Recycler") and cats.has("Ammo Maker") and cats.has("Component Maker"), "at least one broken machine of each category spawned")
	# 3. the chain ids are valid machine defs with recipes
	for k in RunState.run_chain:
		var id = String(RunState.run_chain[k])
		ck(GameData.machines.has(id) and not GameData.recipes_for(id).is_empty(), "%s -> %s is a real machine with a recipe" % [k, id])
	print("SLICE4: weapon=%s chain=%s" % [RunState.weapon_family, str(RunState.run_chain)])
	if fail == 0: print("SLICE4_TEST: ALL PASS")
	else: printerr("SLICE4_TEST: %d FAIL" % fail)
	get_tree().quit(fail)
