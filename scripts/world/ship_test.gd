extends Node
## Headless test for Step 4's persistence spine: shipping unlock + banking to the
## Mars total + save/load round-trip. Run (back up your save first — this writes it):
##   godot --headless --path . res://scenes/test/ship_test.tscn

func _ready() -> void:
	var failures := 0

	RunState.shipping_unlocked = false
	RunState.unlock_shipping()
	failures += _check(RunState.shipping_unlocked, "unlock_shipping sets the run flag")

	MetaState.mars_delivered.clear()
	MetaState.bank_delivery({"scrap_metal": 2, "wire": 1})
	failures += _check(MetaState.mars_total() == 3, "bank_delivery totals to 3")
	MetaState.bank_delivery({"scrap_metal": 1})
	failures += _check(int(MetaState.mars_delivered.get("scrap_metal", 0)) == 3, "same id accumulates")
	failures += _check(MetaState.mars_total() == 4, "running total is 4")

	# Round-trip: reload from disk should reproduce the banked totals.
	MetaState.load_game()
	failures += _check(MetaState.mars_total() == 4, "mars total persisted through save/load")

	if failures == 0:
		print("SHIP_TEST: ALL PASS")
	else:
		printerr("SHIP_TEST: %d FAILURE(S)" % failures)
	get_tree().quit(failures)


func _check(condition: bool, label: String) -> int:
	if condition:
		print("  ok   - ", label)
		return 0
	printerr("  FAIL - ", label)
	return 1
