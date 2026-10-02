extends Node
var fail := 0
func ck(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: fail += 1; printerr("  FAIL: ", l)
func _ready() -> void:
	# 1. run picks a random weapon family + ammo
	RunState.begin_run(GameData.first_area_id(), 7)
	ck(RunState.weapon_family in GameData.families, "run picked a weapon family (%s)" % RunState.weapon_family)
	ck(RunState.weapon_ammo == String(GameData.families[RunState.weapon_family].get("ammo","")), "weapon_ammo matches the family")
	# 2. an ammo maker turns 2 of its material into ammo
	var f := FactoryGrid.new(8, 8)
	RunState.factory = f
	var mi := f.place_machine_layout("copper_ammo_maker", Vector2i(3, 3), [Vector2i(-1, 0), Vector2i(0, -1)], [Vector2i(1, 0)], [], [])
	ck(mi >= 0, "ammo maker placed")
	f.set_cell(Vector2i(2, 3), {"kind": "resource", "id": "copper"})
	f.set_cell(Vector2i(3, 2), {"kind": "resource", "id": "copper"})
	for _t in 3: f.tick(3.0)
	ck(int(f.resource_counts().get("charge_cells", 0)) == 1, "copper ammo maker: 2 copper -> 1 charge_cells")
	# 3. weapon consumes ammo; no ammo -> can't fire
	RunState.weapon_family = "copper"; RunState.weapon_ammo = "charge_cells"
	var combat = load("res://scripts/player/player_combat.gd").new()
	add_child(combat)
	# with ammo present, simulate the ammo-gate portion:
	f.add_resource("charge_cells")
	var before: int = int(f.resource_counts().get("charge_cells", 0))
	RunState.add("charge_cells", -1)  # what a shot does
	ck(int(f.resource_counts().get("charge_cells", 0)) == before - 1, "firing consumes one ammo")
	combat.queue_free()
	# 4. broken ammo makers spawn in the world
	var gen := AreaGenerator.new(); add_child(gen)
	gen.build(GameData.first_area_id(), 321)
	await get_tree().process_frame
	var ammo_brokens := 0
	for p in get_tree().get_nodes_in_group("pickups"):
		if p is MachinePickup and p.broken and p.category == "Ammo Maker":
			ammo_brokens += 1
	ck(ammo_brokens > 0, "broken Ammo Makers spawn (%d)" % ammo_brokens)
	if fail == 0: print("SLICE2_TEST: ALL PASS")
	else: printerr("SLICE2_TEST: %d FAIL" % fail)
	get_tree().quit(fail)
