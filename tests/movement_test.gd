extends SceneTree


func _initialize() -> void:
	var player_scene := load("res://scenes/player/grobit.tscn") as PackedScene
	assert(player_scene != null)
	var player := player_scene.instantiate() as GrobitPlayer
	assert(player != null)
	root.add_child(player)
	await process_frame
	assert(player.sprite.texture != null)
	assert(player.movement_speed > 0.0)
	assert(player.acceleration > 0.0 and player.deceleration > 0.0)
	assert(player.rotation_speed > 0.0)

	var room_scene := load("res://scenes/test/movement_test.tscn") as PackedScene
	assert(room_scene != null)
	var room := room_scene.instantiate()
	root.add_child(room)
	await process_frame
	assert(room.get_node("Tiles").get_child_count() == 20 * 14)
	assert(room.get_node("Walls").get_child_count() == 4)
	print("Movement prototype integration tests passed.")
	quit()
