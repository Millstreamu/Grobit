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
	# 1. Only a RECYCLER is guaranteed now (machines are scarce; ammo/component makers are
	#    lucky finds). The guaranteed chain records exactly that.
	ck("Recycler" in RunState.run_chain, "run_chain guarantees a Recycler: %s" % str(RunState.run_chain))
	ck(not ("Ammo Maker" in RunState.run_chain) and not ("Component Maker" in RunState.run_chain), "ammo/component makers are NOT guaranteed")
	# 2. a guaranteed broken Recycler exists in the world
	var cats := {}
	for p in get_tree().get_nodes_in_group("pickups"):
		if p is MachinePickup and p.broken:
			cats[p.category] = true
	ck(cats.has("Recycler"), "at least one broken Recycler spawned (guaranteed)")
	# 3. the chain ids are valid machine defs with recipes
	for k in RunState.run_chain:
		var id = String(RunState.run_chain[k])
		ck(GameData.machines.has(id) and not GameData.recipes_for(id).is_empty(), "%s -> %s is a real machine with a recipe" % [k, id])
	print("SLICE4: weapon=%s chain=%s" % [RunState.weapon_family, str(RunState.run_chain)])
	if fail == 0: print("SLICE4_TEST: ALL PASS")
	else: printerr("SLICE4_TEST: %d FAIL" % fail)
	get_tree().quit(fail)
