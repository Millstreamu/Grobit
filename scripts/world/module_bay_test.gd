extends Node
## Slice 3 — the scrapbot MODULE BAY. Weapons live in the bot's bay (a separate persisted grid),
## not the lair workshop (factory). The bot fires from the BAY; a weapon sitting in the workshop
## does nothing in the field. The bay loadout persists across runs.

func _ready() -> void:
	var fail := 0
	RunState.begin_run(GameData.first_area_id(), 1)

	# The bay is its own grid, sized to BAY_COLS×BAY_ROWS and distinct from the workshop.
	fail += _ck(RunState.bay != null and RunState.bay != RunState.factory, "the bay is a separate grid from the workshop")
	fail += _ck(RunState.bay.cols == RunState.BAY_COLS and RunState.bay.rows == RunState.BAY_ROWS, "the bay is sized to the loadout grid")

	# A weapon placed in the WORKSHOP does NOT arm the bot (firing reads the bay).
	RunState.factory.place_machine("steel_weapon", Vector2i(3, 3))
	fail += _ck(not RunState.bay.has_weapon(), "a weapon in the workshop does NOT arm the bot")

	# A weapon in the BAY arms the bot once the bot carries its ammo (loaded from the workshop).
	RunState.bay.place_machine("steel_weapon", Vector2i(1, 1))
	fail += _ck(RunState.bay.has_weapon(), "a weapon placed in the bay is equipped")
	fail += _ck(not RunState.weapon_armed(), "equipped but with no loaded ammo, it isn't armed yet")
	RunState.add("steel_slugs", 3)  # made in the workshop
	RunState.load_ammo()            # launch loads it onto the bot
	fail += _ck(RunState.weapon_armed(), "with ammo loaded, the bay weapon arms the bot")
	fail += _ck(RunState.consume_ammo("steel_slugs"), "firing the bay weapon spends loaded ammo")

	# The bay loadout persists across a save/load round-trip.
	MetaState.save_bay(RunState.bay)
	var reloaded := MetaState.load_bay()
	fail += _ck(reloaded != null and reloaded.machine_at(Vector2i(1, 1)) >= 0, "the bay loadout persists (the weapon reloads)")

	MetaState.bay_blob = ""
	if fail == 0:
		print("MODULE_BAY_TEST: ALL PASS")
	else:
		printerr("MODULE_BAY_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> int:
	if condition:
		print("  ok   - ", label)
		return 0
	printerr("  FAIL - ", label)
	return 1
