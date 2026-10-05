extends Node
## Deferred generation: build_lair() makes ONLY the lair (one room, sealed exit) so the player
## can pick a run first; generate_facility() rolls the rest when they hop in the scrapbot.
## Run: godot --headless --path . res://scenes/test/deferred_gen_test.tscn

var fail := 0


func _ready() -> void:
	MetaState.lair_cells = []
	MetaState.lair_grid = []

	var gen := AreaGenerator.new()
	add_child(gen)
	RunState.begin_run(GameData.first_area_id(), 7)

	# --- phase 1: lair only ---
	var start: Vector2 = gen.build_lair(GameData.first_area_id())
	await get_tree().process_frame
	_ck(not gen.facility_ready(), "facility is NOT generated after build_lair")
	_ck(gen.rooms.size() == 1, "only the lair room exists before hopping in (%d)" % gen.rooms.size())
	_ck(gen.rooms[0].room_type == Room.RoomType.START, "the one room is the lair (START)")
	_ck(gen.rooms[0].doors.size() == 1, "the lair has its single exit door")
	_ck(start != Vector2.ZERO, "build_lair returns a spawn point in the lair")
	# The lair must be walkable but sealed: interior floor exists, and the exit is solid.
	_ck(not gen.rooms[0].interior_tiles.is_empty(), "the lair has walkable floor")
	var door := gen.rooms[0].doors[0]
	_ck(not door.can_interact.call() if door.has_method("can_interact") else true, "the exit door is locked (can't be hand-opened)")

	var pickups_before := 0
	for n in get_tree().get_nodes_in_group("pickups"):
		pickups_before += 1
	_ck(pickups_before == 0, "no facility content spawned yet")

	# --- phase 2: hop in → facility rolls ---
	gen.generate_facility(7)
	await get_tree().process_frame
	_ck(gen.facility_ready(), "facility is generated after generate_facility")
	_ck(gen.rooms.size() > 1, "the facility added rooms (%d total)" % gen.rooms.size())
	_ck(gen.rooms[0].room_type == Room.RoomType.START, "the lair is still room 0 after generation")
	_ck(gen.rooms[0].doors.size() == 1, "the lair still has exactly one door")

	# Calling again is a safe no-op (doesn't double-build).
	var n_rooms := gen.rooms.size()
	gen.generate_facility(7)
	_ck(gen.rooms.size() == n_rooms, "generate_facility is idempotent")

	if fail == 0:
		print("DEFERRED_GEN_TEST: ALL PASS")
	else:
		printerr("DEFERRED_GEN_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
