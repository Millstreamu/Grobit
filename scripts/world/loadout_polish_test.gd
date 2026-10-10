extends Node
## Slice 5 polish: (1) category gating — weapons + consumable processors belong in the bot's
## MODULE BAY, refiners/crafters in the LAIR WORKSHOP; (2) the cargo hold can be EXPANDED at the
## terminal (persistent, Dredge "bigger hold").

func _ready() -> void:
	var fail := 0

	# --- category gating classifier ---
	var panel := FactoryPanel.new()
	fail += _ck(panel._is_bay_module("steel_weapon"), "weapons are bay modules")
	fail += _ck(panel._is_bay_module("ammo_loader"), "ammo loaders are bay modules")
	fail += _ck(not panel._is_bay_module("steel_ammo_maker"), "ammo makers are WORKSHOP machines now (ammo is made at base)")
	fail += _ck(not panel._is_bay_module("steel_recycler"), "recyclers are NOT bay modules (workshop only)")
	fail += _ck(not panel._is_bay_module("frame_maker"), "component makers stay in the workshop")
	panel.free()

	# --- cargo hold expansion (paid in refined materials now) ---
	MetaState.cargo_rows_bonus = 0
	RunState.begin_run(GameData.first_area_id(), 1)
	RunState.add("steel", 200)
	RunState.add("copper", 200)
	fail += _ck(RunState.cargo.rows == RunState.CARGO_ROWS, "hold starts at base size")
	var cost := MetaState.expand_cargo_cost()
	var steel_before := RunState.get_quantity("steel")
	fail += _ck(MetaState.expand_cargo(), "expand the hold with enough materials")
	fail += _ck(MetaState.cargo_rows_bonus == 1 and RunState.get_quantity("steel") == steel_before - int(cost.get("steel", 0)), "bonus +1 and materials spent from inventory")
	RunState.begin_run(GameData.first_area_id(), 1)  # next run's hold reflects the bonus
	RunState.add("steel", 120)   # enough for the remaining expansions (and it fits the grid's stacks)
	RunState.add("copper", 90)
	fail += _ck(RunState.cargo.rows == RunState.CARGO_ROWS + 1, "a new run's hold is one row bigger")

	# cap
	while MetaState.can_expand_cargo():
		if not MetaState.expand_cargo():
			break  # ran out of materials (shouldn't here) — don't spin forever
	fail += _ck(MetaState.cargo_rows_bonus == MetaState.CARGO_BONUS_MAX, "expansion caps at CARGO_BONUS_MAX")
	fail += _ck(not MetaState.expand_cargo(), "no expansion past the cap")

	MetaState.cargo_rows_bonus = 0
	if fail == 0:
		print("LOADOUT_POLISH_TEST: ALL PASS")
	else:
		printerr("LOADOUT_POLISH_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> int:
	if condition:
		print("  ok   - ", label)
		return 0
	printerr("  FAIL - ", label)
	return 1
