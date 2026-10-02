extends Node
## Repairable weapons: a placed weapon machine fires with its own stats, eating one unit of
## its family's ammo from its input slot. Wrong ammo is ignored; no ammo → the basic gun
## (try_fire_weapon returns {}).

var fail := 0


class FakeEnemy extends Node:
	var hp := 10
	func take_damage(d: int) -> void:
		hp -= d


func _ready() -> void:
	var g := FactoryGrid.new(6, 6)
	var mi := g.place_machine("steel_weapon", Vector2i(3, 3))
	_ck(mi >= 0, "weapon placed in the grid")
	var inp: Vector2i = g.input_positions(g.machines[mi])[0]

	# No ammo loaded → no weapon shot (player falls back to the basic gun).
	_ck(g.try_fire_weapon().is_empty(), "unloaded weapon doesn't fire (basic gun fallback)")
	_ck(not g.has_loaded_weapon(), "has_loaded_weapon is false when empty")

	# Feed the matching ammo → it's loaded and fires with its stats.
	g.set_cell(inp, {"kind": "resource", "id": "steel_slugs"})
	_ck(g.has_loaded_weapon(), "loaded once its ammo is in the input slot")
	var shot := g.try_fire_weapon()
	_ck(not shot.is_empty() and String(shot.get("family", "")) == "steel", "loaded weapon fires with its family stats")
	_ck(int(shot.get("damage", 0)) == 6, "steel weapon uses its damage (6)")
	_ck(g.get_cell(inp).is_empty(), "firing consumed one ammo from the slot")
	_ck(g.try_fire_weapon().is_empty(), "no ammo left → no further weapon shot")

	# Wrong ammo type is ignored (and left in the slot).
	g.set_cell(inp, {"kind": "resource", "id": "charge_cells"})  # copper ammo in a steel weapon
	_ck(g.try_fire_weapon().is_empty(), "weapon ignores the wrong ammo type")
	_ck(String(g.get_cell(inp).get("id", "")) == "charge_cells", "the wrong ammo stays in the slot")

	# Plastic = spread, ceramic = pierce (behavior fields flow through try_fire_weapon).
	var gp := FactoryGrid.new(6, 6)
	var pm := gp.place_machine("plastic_weapon", Vector2i(3, 3))
	gp.set_cell(gp.input_positions(gp.machines[pm])[0], {"kind": "resource", "id": "resin_capsules"})
	var ps := gp.try_fire_weapon()
	_ck(int(ps.get("pellets", 1)) == 3 and float(ps.get("spread_deg", 0)) > 0.0, "plastic weapon fires a 3-pellet spread")

	var gc := FactoryGrid.new(6, 6)
	var cm := gc.place_machine("ceramic_weapon", Vector2i(3, 3))
	gc.set_cell(gc.input_positions(gc.machines[cm])[0], {"kind": "resource", "id": "ceramic_charges"})
	var cs := gc.try_fire_weapon()
	_ck(int(cs.get("pierce", 0)) == 2, "ceramic weapon shot pierces 2")

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
