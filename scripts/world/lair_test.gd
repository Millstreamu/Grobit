extends Node
## The goblin lair (room 0) is pinned to the bottom-middle of the map, its size/shape persist
## across runs via MetaState, and it exits the facility through a single door at its top-middle.
## Run: godot --headless --path . res://scenes/test/lair_test.tscn
## (The runner backs up/restores user://grobit_save.json — the freeze below writes to disk.)

var fail := 0


func _ready() -> void:
	# Start from no saved footprint so the default is generated and frozen this build.
	MetaState.lair_cells = []
	MetaState.lair_grid = []

	var gen := AreaGenerator.new()
	add_child(gen)
	RunState.begin_run(GameData.first_area_id(), 101)
	gen.build(GameData.first_area_id(), 101)
	await get_tree().process_frame

	var w: int = gen._W
	var h: int = gen._H
	var cols: int = gen._C
	var tile: int = gen.tile

	# --- footprint: bottom row, horizontally centred ---
	_ck(not gen._lair_cells.is_empty(), "lair has a footprint")
	var min_cx := 1 << 30
	var max_cx := -1
	var max_cy := -1
	for c: int in gen._lair_cells:
		min_cx = mini(min_cx, c % w)
		max_cx = maxi(max_cx, c % w)
		max_cy = maxi(max_cy, c / w)
	_ck(max_cy == h - 1, "lair is anchored to the bottom row (max cell-y %d == %d)" % [max_cy, h - 1])
	_ck(min_cx + max_cx == w - 1, "lair is horizontally centred (cols %d..%d on a width-%d grid)" % [min_cx, max_cx, w])

	# --- it IS room 0, the START room ---
	_ck(not gen.rooms.is_empty() and gen.rooms[0].room_type == Room.RoomType.START, "room 0 is the START/lair room")

	# --- a single exit door, on the lair's top edge, near horizontal centre ---
	_ck(not gen._lair_door_tiles.is_empty(), "lair planned an exit door")
	var top_ty := 0
	var min_cy := 1 << 30
	for c: int in gen._lair_cells:
		min_cy = mini(min_cy, c / w)
	top_ty = min_cy * cols
	var door_on_top := true
	for t: Vector2i in gen._lair_door_tiles:
		if t.y != top_ty:
			door_on_top = false
	_ck(door_on_top, "every door tile sits on the lair's top edge (row %d)" % top_ty)
	_ck(not gen.rooms.is_empty() and gen.rooms[0].doors.size() == 1, "the lair has exactly ONE door (its single entry)")
	_ck(gen._lair_neighbor >= 1, "the door opens into a real facility room (%d)" % gen._lair_neighbor)

	# door x within the lair's tile span and near the map's horizontal centre
	var span_lo := min_cx * cols
	var span_hi := (max_cx + 1) * cols - 1
	var map_mid := gen._TW / 2.0
	var near_mid := true
	for t: Vector2i in gen._lair_door_tiles:
		if t.x < span_lo or t.x > span_hi or absf(t.x + 0.5 - map_mid) > cols:
			near_mid = false
	_ck(near_mid, "door sits near the top-middle of the map")

	# door world position matches the planned tile (what RunController parks the scrapbot by)
	var door := gen.rooms[0].doors[0]
	var expected_y := top_ty * tile + tile * 0.5
	_ck(absf(door.global_position.y - expected_y) < 0.5, "door world Y is the lair's top edge")

	# --- persistence: the footprint is frozen and reused for a different seed ---
	_ck(MetaState.has_lair(), "the footprint was frozen into MetaState")
	var frozen: Array = MetaState.lair_cells.duplicate()
	var gen2 := AreaGenerator.new()
	add_child(gen2)
	gen2.build(GameData.first_area_id(), 999)  # different seed
	await get_tree().process_frame
	var same := gen2._lair_cells.size() == frozen.size()
	if same:
		for c: int in frozen:
			if not gen2._lair_cells.has(c):
				same = false
				break
	_ck(same, "a different seed rebuilds the SAME lair (shape persists)")

	if fail == 0:
		print("LAIR_TEST: ALL PASS")
	else:
		printerr("LAIR_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
