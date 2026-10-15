extends Node
## Phase 5 — module abilities. Installed support bay modules (Coolant / Medbay / Scanner) grant
## tactical, per-run CHARGE-based abilities surfaced on RunState: installed_abilities lists them,
## stacking a module sums its charges, charges deplete as used and refill on begin_run, and the
## Reduce-Heat / Heal / Scan effects behave. (The in-field Scan room-pick is exercised by the panel;
## here we test the data layer + the pure effects.)

var fail := 0


func _ready() -> void:
	RunState.begin_run(GameData.first_area_id(), 1)

	# A bare bay grants nothing.
	_ck(RunState.installed_abilities().is_empty(), "no modules → no abilities")

	# Install one of each support module.
	RunState.bay.place_machine("coolant_module", Vector2i(0, 0))
	RunState.bay.place_machine("medbay_module", Vector2i(2, 0))
	RunState.bay.place_machine("scanner_module", Vector2i(4, 0))
	var abil := RunState.installed_abilities()
	_ck(abil.size() == 3, "three installed modules → three abilities")
	_ck(RunState.ability_max("reduce_heat") == 2, "coolant grants 2 vent-heat charges")
	_ck(RunState.ability_max("scan") == 3, "scanner grants 3 scan charges")

	# Stacking the same module SUMS charges.
	RunState.bay.place_machine("coolant_module", Vector2i(0, 2))
	_ck(RunState.installed_abilities().size() == 3, "a second coolant doesn't add a new ability row")
	_ck(RunState.ability_max("reduce_heat") == 4, "a second coolant stacks to 4 charges")

	# Charges deplete as used, then run dry.
	RunState.ability_used = {}
	_ck(RunState.ability_remaining("reduce_heat") == 4, "charges start full")
	_ck(RunState.use_ability("reduce_heat"), "using an ability spends a charge")
	_ck(RunState.ability_remaining("reduce_heat") == 3, "one charge spent")
	RunState.use_ability("reduce_heat"); RunState.use_ability("reduce_heat"); RunState.use_ability("reduce_heat")
	_ck(RunState.ability_remaining("reduce_heat") == 0, "all four charges spent")
	_ck(not RunState.use_ability("reduce_heat"), "a drained ability can't be used")

	# begin_run refills charges (used resets; modules persist via the saved bay in real play).
	RunState.ability_used["scan"] = 2
	RunState.begin_run(GameData.first_area_id(), 2)
	_ck(RunState.ability_used.is_empty(), "begin_run clears spent charges")

	# Reduce-Heat effect clamps at zero.
	RunState.heat = 6.0
	RunState.add_heat(-10.0)
	_ck(RunState.heat == 0.0, "venting heat clamps at 0")

	# Goblin heal clamps at MAX_HP.
	var gob := HarvesterGoblin.new()
	gob.take_damage(1)  # 3 -> 2
	_ck(gob.needs_heal(), "a hurt goblin needs healing")
	gob.heal(5)
	_ck(gob.health() == HarvesterGoblin.MAX_HP, "healing clamps to full HP")
	_ck(not gob.needs_heal(), "a full-HP goblin no longer needs healing")
	gob.free()

	# Room loot summary (the Scan reveal text).
	var room := Room.new()
	room.salvage_loot = [{"resource": "copper_scrap"}, {"resource": "steel_scrap"}, {"resource": "copper_scrap"}]
	var summary := room.loot_summary()
	_ck("Copper Scrap" in summary and "Steel Scrap" in summary, "loot summary lists distinct resources")
	var bare := Room.new()
	_ck(bare.loot_summary() == "scattered scrap only", "an empty salvage room reads as scrap only")
	room.free()
	bare.free()

	if fail == 0:
		print("MODULE_ABILITY_TEST: ALL PASS")
	else:
		printerr("MODULE_ABILITY_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
