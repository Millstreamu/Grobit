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

	# Room entry must wait until the player's complete collision body has cleared
	# the door/approach tiles and reached the safe inset of an interior floor tile.
	var generated_room := Room.new()
	generated_room.interior_tiles = [Vector2(100.0, 100.0)]
	generated_room.enemy_min = 0
	generated_room.enemy_max = 0
	root.add_child(generated_room)
	var entering_player := CharacterBody2D.new()
	entering_player.add_to_group("player")
	entering_player.global_position = Vector2(80.0, 100.0)
	root.add_child(entering_player)
	generated_room._on_body_entered(entering_player)
	generated_room._physics_process(0.0)
	assert(not generated_room.is_cleared)
	entering_player.global_position = Vector2(100.0, 100.0)
	generated_room._physics_process(0.0)
	assert(generated_room.is_cleared)
	print("Movement prototype integration tests passed.")
	quit()
