extends SceneTree


func _initialize() -> void:
	var room_scene := load("res://scenes/test/combat_test.tscn") as PackedScene
	assert(room_scene != null)
	var room := room_scene.instantiate()
	root.add_child(room)
	await process_frame
	await physics_frame

	var player := room.get_node("Grobit") as GrobitPlayer
	var combat := player.get_node("Combat") as PlayerCombat
	var enemy := room.get_node("BasicEnemy") as BasicEnemy
	var counter := room.get_node("HUD/ResourceCounter") as ResourceCounter
	assert(player != null and combat != null and enemy != null and counter != null)
	assert(enemy.sprite.texture != null)
	assert(enemy.health == enemy.max_health)
	assert(combat.damage > 0 and combat.attack_range > 0.0)
	assert(combat.cooldown > 0.0 and combat.projectile_speed > 0.0)

	# Exercise targeting/projectile creation, then damage and drop deterministically.
	enemy.global_position = player.global_position + Vector2(80.0, 0.0)
	assert(combat.attack_nearest())
	await process_frame
	assert(get_nodes_in_group("enemies").size() == 2)
	assert(room.get_node_or_null("Projectile") != null)
	enemy.take_damage(enemy.max_health)
	await process_frame
	var pickup := room.get_node_or_null("ScrapPickup") as ResourcePickup
	assert(pickup != null)
	assert(pickup.sprite.texture != null)
	pickup._on_body_entered(player)
	assert(counter.scrap_metal == 1)
	assert(counter.label.text == "Scrap metal: 1")
	print("Basic combat loop integration tests passed.")
	quit()
