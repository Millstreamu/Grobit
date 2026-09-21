extends Node
## Headless test for modules: decode draft, install/remove, and speed + yield
## effects in the tick. Run:
##   godot --headless --path . res://scenes/test/factory_module_test.tscn
## Sets modules_owned directly (no disk write).

func _ready() -> void:
	var failures := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 999

	# Unlock the whole catalogue in-memory (no save) so the draft pool is full here.
	MetaState.module_library.clear()
	for mid: String in GameData.modules:
		if not MetaState.is_module_unlocked(mid):
			MetaState.module_library.append(mid)

	# Decode draft: distinct ids from the (now full) library.
	var opts := MetaState.decode_options(3, rng)
	failures += _check(opts.size() == mini(3, GameData.modules.size()), "decode offers up to 3 options")
	failures += _check(opts.size() == _distinct(opts).size(), "decode options are distinct")

	# Build a leveled refiner with two MOD slots.
	var g := FactoryGrid.new(6, 4)
	var mi := g.place_machine("smelter", Vector2i(2, 1))  # input (1,1), output (3,1)
	var shape := g.roll_upgrade(mi, FactoryGrid.SLOTS_PER_LEVEL, rng)
	g.apply_upgrade(mi, shape)  # level 2, two machine_slot cells

	# Install overclock + yield into the two slots.
	failures += _check(g.install_module(shape[0], "overclock"), "install overclock into a slot")
	failures += _check(g.install_module(shape[1], "yield_amp"), "install yield_amp into a slot")
	failures += _check(g.installed_count("overclock") == 1, "installed_count tracks overclock")
	failures += _check(not g.install_module(shape[0], "overclock"), "cannot install into an occupied slot")
	failures += _check(g.module_at(shape[0]) == "overclock", "module_at reports the installed module")

	# Ownership accounting (panel uses this to cap installs).
	MetaState.modules_owned = {"overclock": 1}
	failures += _check(MetaState.module_count("overclock") - g.installed_count("overclock") == 0, "no spare overclock left to install")

	# Effect: level 2 (0.8) * overclock (0.8) = 1.92s, so it finishes by 2.0s; and
	# yield_amp adds a bonus item, so one craft yields two metal_bar.
	g.set_cell(Vector2i(1, 1), {"kind": "resource", "id": "scrap_metal"})
	for _i in 4:
		g.tick(0.5)
	failures += _check(String(g.get_cell(Vector2i(3, 1)).get("id", "")) == "metal_bar", "sped-up craft finished by 2.0s")
	failures += _check(int(g.resource_counts().get("metal_bar", 0)) == 2, "yield module produced a bonus item (2 total)")

	# Remove a module.
	failures += _check(g.remove_module(shape[0]) == "overclock", "remove returns the module id")
	failures += _check(g.installed_count("overclock") == 0, "installed_count drops after removal")

	if failures == 0:
		print("FACTORY_MODULE_TEST: ALL PASS")
	else:
		printerr("FACTORY_MODULE_TEST: %d FAILURE(S)" % failures)
	get_tree().quit(failures)


func _distinct(arr: Array) -> Array:
	var seen := {}
	for x: Variant in arr:
		seen[x] = true
	return seen.keys()


func _check(condition: bool, label: String) -> int:
	if condition:
		print("  ok   - ", label)
		return 0
	printerr("  FAIL - ", label)
	return 1
