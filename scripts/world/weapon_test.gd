extends Node
## Weapons are BAY MODULES now — shapes with NO ammo input slot. A placed weapon exposes its firing
## stats via weapon_stats() (no consuming), the bot draws ammo from RunState's loaded reserve (ammo
## is MADE in the workshop and loaded at launch), and Ammo Loader modules speed up the fire rate.
## Spread/pierce behaviour fields still flow through weapon_stats.

var fail := 0


class FakeEnemy extends Node:
	var hp := 10
	func take_damage(d: int) -> void:
		hp -= d


func _ready() -> void:
	var g := FactoryGrid.new(6, 6)
	_ck(not g.has_weapon(), "no weapon → has_weapon is false")
	_ck(g.weapon_stats().is_empty(), "no weapon → no stats")
	var mi := g.place_machine("steel_weapon", Vector2i(3, 3))
	_ck(mi >= 0, "a weapon places as a bay module")
	_ck(g.input_positions(g.machines[mi]).is_empty(), "a weapon module has no input ports (it's just a shape)")
	_ck(g.has_weapon(), "has_weapon is true once placed")
	var shot := g.weapon_stats()
	_ck(String(shot.get("family", "")) == "steel" and int(shot.get("damage", 0)) == 6, "weapon_stats returns its family + damage")
	_ck(String(shot.get("ammo", "")) == "steel_slugs", "weapon_stats names its ammo type")

	# Fire rate: Ammo Loaders multiply it.
	_ck(absf(g.fire_rate_multiplier() - 1.0) < 0.001, "no loaders → 1.0× fire rate")
	g.place_machine("ammo_loader", Vector2i(0, 0))
	_ck(g.fire_rate_multiplier() > 1.3, "an Ammo Loader speeds up the fire rate (+35%)")

	# The ammo reserve lives on the BOT (RunState), loaded from the workshop — not in a grid cell.
	RunState.begin_run(GameData.first_area_id(), 1)
	RunState.bay = FactoryGrid.new(RunState.BAY_COLS, RunState.BAY_ROWS)
	RunState.bay.place_machine("steel_weapon", Vector2i(2, 2))
	RunState.add("steel_slugs", 2)  # produced in the workshop
	_ck(not RunState.weapon_armed(), "a weapon with no loaded ammo is NOT armed")
	RunState.load_ammo()
	_ck(RunState.ammo_count("steel_slugs") == 2 and RunState.get_quantity("steel_slugs") == 0, "launch loads the workshop ammo onto the bot")
	_ck(RunState.weapon_armed(), "a weapon + loaded ammo is armed")
	_ck(RunState.consume_ammo("steel_slugs"), "firing spends one ammo from the reserve")
	_ck(RunState.ammo_count("steel_slugs") == 1, "the reserve drops by one")
	RunState.consume_ammo("steel_slugs")
	_ck(not RunState.consume_ammo("steel_slugs"), "no shot once the reserve is empty")
	_ck(not RunState.weapon_armed(), "out of ammo → not armed")

	# Unspent ammo returns to the workshop on a clean extract.
	RunState.ammo = {"steel_slugs": 3}
	RunState.return_ammo()
	_ck(RunState.get_quantity("steel_slugs") == 3 and RunState.ammo.is_empty(), "unspent ammo comes home on extract")

	# The carry is CAPPED by hold size — extra ammo stays in the workshop (workshop now holds 3).
	var cap := RunState.ammo_capacity()
	_ck(cap > 0, "ammo capacity is derived from the hold (%d)" % cap)
	RunState.add("steel_slugs", cap + 50)  # workshop now holds 3 + cap + 50 — far over the cap
	RunState.load_ammo()
	_ck(RunState.ammo_count("steel_slugs") == cap, "the bot loads only up to the hold cap")
	_ck(RunState.get_quantity("steel_slugs") == 53, "ammo beyond the cap stays in the workshop (3 + 50)")

	# Spread / pierce behaviour fields flow through weapon_stats.
	var gp := FactoryGrid.new(6, 6)
	gp.place_machine("plastic_weapon", Vector2i(3, 3))
	var ps := gp.weapon_stats()
	_ck(int(ps.get("pellets", 1)) == 3 and float(ps.get("spread_deg", 0)) > 0.0, "plastic weapon = 3-pellet spread")
	var gc := FactoryGrid.new(6, 6)
	gc.place_machine("ceramic_weapon", Vector2i(3, 3))
	_ck(int(gc.weapon_stats().get("pierce", 0)) == 2, "ceramic weapon pierces 2")

	# A piercing projectile passes through its allowance of enemies, once each.
	var proj := BasicProjectile.new()
	proj.pierce = 1
	add_child(proj)
	var e1 := FakeEnemy.new()
	var e2 := FakeEnemy.new()
	proj._on_body_entered(e1)
	_ck(e1.hp == 9 and not proj.is_queued_for_deletion(), "pierce shot hits the first enemy and keeps going")
	proj._on_body_entered(e1)
	_ck(e1.hp == 9, "pierce shot never double-hits the same enemy")
	proj._on_body_entered(e2)
	_ck(e2.hp == 9 and proj.is_queued_for_deletion(), "pierce shot stops after its allowance")

	if fail == 0:
		print("WEAPON_TEST: ALL PASS")
	else:
		printerr("WEAPON_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
