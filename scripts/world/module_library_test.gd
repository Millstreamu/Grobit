extends Node
## Headless test for module library growth (decode pool widens via deliveries).
## Writes the save — back it up. Run:
##   godot --headless --path . res://scenes/test/module_library_test.tscn

func _ready() -> void:
	var failures := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	MetaState.module_library.clear()
	MetaState.mars_delivered.clear()

	# Base modules only at first.
	failures += _check(MetaState.is_module_unlocked("overclock"), "base module unlocked by default")
	failures += _check(not MetaState.is_module_unlocked("yield_amp"), "yield_amp locked at first")
	failures += _check(not MetaState.is_module_unlocked("turbo_core"), "turbo_core locked at first")
	failures += _check(MetaState.decode_options(3, rng).size() == 2, "decode pool starts at the 2 base modules")

	# Deliver machine parts → the library grows.
	var newly := MetaState.bank_delivery({"control_unit": 2})
	failures += _check(MetaState.is_module_unlocked("yield_amp"), "yield_amp joins the library at 1 control unit")
	failures += _check(newly.has("Yield Amplifier"), "delivery reports the new module")
	failures += _check(MetaState.decode_options(3, rng).size() == 3, "decode pool grew to 3")
	failures += _check(not MetaState.is_module_unlocked("turbo_core"), "turbo_core still locked below its threshold")

	MetaState.bank_delivery({"control_unit": 4})  # cumulative 6
	failures += _check(MetaState.is_module_unlocked("turbo_core"), "turbo_core unlocks at 6 machine parts")

	# Persists.
	MetaState.load_game()
	failures += _check(MetaState.is_module_unlocked("yield_amp") and MetaState.is_module_unlocked("turbo_core"), "library persists through save/load")

	if failures == 0:
		print("MODULE_LIBRARY_TEST: ALL PASS")
	else:
		printerr("MODULE_LIBRARY_TEST: %d FAILURE(S)" % failures)
	get_tree().quit(failures)


func _check(condition: bool, label: String) -> int:
	if condition:
		print("  ok   - ", label)
		return 0
	printerr("  FAIL - ", label)
	return 1
