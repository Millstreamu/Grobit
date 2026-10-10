extends Node
## Slice 3 — auto-turret defense. The scrapbot's loaded weapon auto-fires at besiegers to protect
## the deployed goblins. Two things have to be true: (1) besiegers sit on a collision layer the
## bot's projectiles actually detect, and (2) the existing auto-fire (PlayerCombat) picks them as
## targets and connects. No loaded weapon → no defense (the fight-or-flee fork). Physics-free:
## we check layers/targeting/damage logic directly so it's deterministic headless.

const PROJECTILE_SCENE := preload("res://scenes/combat/projectile.tscn")

var fail := 0


func _ready() -> void:
	MetaState.machine_levels = {}
	RunState.begin_run(GameData.first_area_id(), 1)
	RunState.driving = true

	# (1) A besieger is detectable by the bot's projectiles: its collision layer intersects the
	#     projectile's mask. (This is the whole bug — on layer 0 the gun shoots straight through.)
	var siege := SiegeEnemy.new()
	add_child(siege)
	siege.global_position = Vector2(60, 0)
	var proj_probe := PROJECTILE_SCENE.instantiate() as BasicProjectile
	_ck(siege.collision_layer != 0, "besieger is on a non-zero collision layer")
	_ck((proj_probe.collision_mask & siege.collision_layer) != 0, "the bot's projectiles scan the besieger's layer")
	_ck(siege.collision_mask == 0, "besieger still passes through walls/goblins (room-local approach)")
	proj_probe.free()
	_ck(siege.is_in_group("enemies"), "besieger is in the \"enemies\" group the turret targets")

	# (2) The bot's auto-fire targets the besieger, and a shot damages/kills it.
	var bot := Node2D.new()
	add_child(bot)
	var combat := PlayerCombat.new()
	bot.add_child(combat)
	_ck(combat.get_aim_target() == siege, "the auto-turret locks onto the besieger in range")

	# A projectile that reaches it deals damage; a lethal hit removes it.
	var proj := BasicProjectile.new()
	proj.damage = SiegeEnemy.MAX_HP
	add_child(proj)
	proj._on_body_entered(siege)
	_ck(siege.is_queued_for_deletion(), "a lethal turret shot takes the besieger down")

	# Put a weapon in the MODULE BAY and load ammo (made in the workshop) onto the bot — confirm it
	# fires at a besieger (spawns a shot, spends ammo). Weapons are bay modules; ammo is a reserve.
	RunState.bay.place_machine("steel_weapon", Vector2i(3, 3))
	RunState.add("steel_slugs", 2)
	RunState.load_ammo()
	_ck(RunState.weapon_armed(), "bot has a weapon + loaded ammo (turrets active)")
	var live := SiegeEnemy.new()
	add_child(live)
	live.global_position = Vector2(40, 0)
	live.set_physics_process(false)
	var before := _count_projectiles()
	var fired: bool = combat.attack_nearest()
	_ck(fired, "the bot fires at the besieger when armed")
	_ck(_count_projectiles() == before + 1, "a defending projectile was launched")
	_ck(RunState.ammo_count("steel_slugs") == 1, "the shot spent one unit of loaded ammo")

	# Out of ammo → no defense: the player must recall and flee instead.
	RunState.ammo = {}
	_ck(not RunState.weapon_armed(), "with no ammo the turrets fall silent")
	_ck(not combat.attack_nearest(), "out of ammo, the bot can't fire — recall and run")

	if fail == 0:
		print("SLICE3_TEST: ALL PASS")
	else:
		printerr("SLICE3_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _count_projectiles() -> int:
	var n := 0
	for c: Node in get_children():
		if c is BasicProjectile:
			n += 1
	return n


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
