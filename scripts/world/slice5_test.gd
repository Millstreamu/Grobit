extends Node
var fail := 0
func ck(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: fail += 1; printerr("  FAIL: ", l)
func _ready() -> void:
	# 1. rooms no longer seal on entry
	var room := Room.new()
	room.room_type = Room.RoomType.COMBAT
	ck(room._locks_on_entry() == false, "combat rooms no longer lock/seal on entry")
	room.free()
	# 2. enemy counts are sparse and no spawner rooms
	var w: Dictionary = GameData.generation.get("room_type_weights", {})
	ck(int(GameData.generation.get("max_enemies", 99)) <= 2, "enemy count is sparse (max <= 2)")
	ck(int(w.get("spawner", 1)) == 0, "no spawner (wave) rooms")
	# 3. enemy drifts when far, engages when near (no rushing across the map)
	var player := Node2D.new(); player.add_to_group("player"); add_child(player)
	var enemy = load("res://scenes/enemies/basic_enemy.tscn").instantiate()
	add_child(enemy); enemy.global_position = Vector2.ZERO
	await get_tree().process_frame
	player.global_position = Vector2(600, 0)  # far (> aggro)
	enemy._physics_process(0.1)
	var far_speed: float = enemy.velocity.length()
	player.global_position = Vector2(60, 0)   # near (< aggro)
	enemy._physics_process(0.1)
	var near_v: Vector2 = enemy.velocity
	ck(far_speed < enemy.movement_speed * 0.5, "drifts slowly when Grobit is far (%.0f < %.0f)" % [far_speed, enemy.movement_speed])
	ck(near_v.x > 0 and near_v.length() > far_speed, "pursues toward Grobit only when near")
	if fail == 0: print("SLICE5_TEST: ALL PASS")
	else: printerr("SLICE5_TEST: %d FAIL" % fail)
	get_tree().quit(fail)
