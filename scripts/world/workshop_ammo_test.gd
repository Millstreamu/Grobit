extends Node
## Ammo is made in the LAIR WORKSHOP now (not on the bot). A steel ammo maker in the factory
## converts steel → steel_slugs at base; in the field the workshop is frozen. The bay holds weapons
## and Ammo Loaders — shape-only modules that don't process, so the bay produces nothing.

var fail := 0


func _ready() -> void:
	RunState.begin_run(GameData.first_area_id(), 1)
	var f := RunState.factory
	var mi := f.place_machine("steel_ammo_maker", Vector2i(2, 1))
	for p: Vector2i in f.input_positions(f.machines[mi]):
		f.set_cell(p, {"kind": "resource", "id": "steel", "count": 4})

	var proc := FactoryProcessor.new()
	add_child(proc)

	# AT BASE: the workshop ammo maker refines steel into ammo.
	RunState.driving = false
	for _i in 12:
		proc._process(1.0)
	var made := int(f.resource_counts().get("steel_slugs", 0))
	_ck(made > 0, "the workshop ammo maker produces ammo at base (%d)" % made)

	# IN THE FIELD: the workshop is frozen — no more ammo is made out on a run.
	RunState.driving = true
	for _i in 12:
		proc._process(1.0)
	_ck(int(f.resource_counts().get("steel_slugs", 0)) == made, "the workshop is frozen in the field (no ammo made on a run)")

	# The bay holds shape-only modules: a weapon + an Ammo Loader produce nothing when ticked.
	var bay := RunState.bay
	bay.place_machine("steel_weapon", Vector2i(1, 1))
	bay.place_machine("ammo_loader", Vector2i(3, 1))
	for _i in 12:
		proc._process(1.0)
	_ck(bay.resource_counts().is_empty(), "the bay makes nothing — its modules are shapes, not processors")
	_ck(bay.fire_rate_multiplier() > 1.3, "the Ammo Loader boosts the bay's fire rate instead")

	RunState.driving = false
	if fail == 0:
		print("WORKSHOP_AMMO_TEST: ALL PASS")
	else:
		printerr("WORKSHOP_AMMO_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
