extends Node
## Automated playtest probe. Samples generated runs (one build each) and simulates the
## core economy loop end-to-end, printing aggregate stats + flags so we can see what
## needs tuning. Not pass/fail — it's a report. Run headless and read the output.

const SEEDS := 15


func _ready() -> void:
	var piles := {"copper scrap": 0, "steel scrap": 0, "plastic scrap": 0, "ceramic scrap": 0}
	var machines := {"Recycler": 0, "Ammo Maker": 0, "Component Maker": 0}
	var fabricators := 0
	var rooms_total := 0
	var loose_scrap := 0
	var guaranteed_match := 0
	var mapwide_match := 0

	for s in SEEDS:
		var seed := 1000 + s * 13
		RunState.begin_run(GameData.first_area_id(), seed)
		var gen := AreaGenerator.new()
		add_child(gen)
		gen.build(GameData.first_area_id(), seed)
		await get_tree().process_frame

		rooms_total += gen.rooms.size()
		for n in get_tree().get_nodes_in_group("scrap_nodes"):
			piles[n.harvest_label] = int(piles.get(n.harvest_label, 0)) + 1
		var fam := RunState.weapon_family
		var want_am := String(GameData.families[fam].get("ammo_maker", ""))
		var found_my_am := false
		for p in get_tree().get_nodes_in_group("pickups"):
			if p is MachinePickup and p.broken:
				machines[p.category] = int(machines.get(p.category, 0)) + 1
				if p.category == "Ammo Maker" and (p.spec_pool as Array).size() == 1:
					var e: Variant = p.spec_pool[0]
					var sid := String(e.get("id", "")) if e is Dictionary else String(e)
					if sid == want_am:
						found_my_am = true
			elif ("amount" in p) and ("resource_id" in p) and p.resource_id == "copper_scrap":
				loose_scrap += int(p.amount)
		fabricators += get_tree().get_nodes_in_group("fabricators").size()

		var chain_matches := String(RunState.run_chain.get("Ammo Maker", "")) == want_am
		if chain_matches:
			guaranteed_match += 1
		if chain_matches or found_my_am:
			mapwide_match += 1

		gen.queue_free()
		await get_tree().process_frame

	print("\n=== A) GENERATION  (avg per run over %d seeds, %.1f rooms/run) ===" % [SEEDS, float(rooms_total) / SEEDS])
	for k in piles:
		print("  piles   %-14s %5.1f" % [k, float(piles[k]) / SEEDS])
	for k in machines:
		print("  broken  %-14s %5.1f" % [k, float(machines[k]) / SEEDS])
	print("  fabricators             %5.1f" % (float(fabricators) / SEEDS))
	print("  loose scrap on ground   %5.1f" % (float(loose_scrap) / SEEDS))

	print("\n=== B) WEAPON VIABILITY ===")
	print("  guaranteed-chain ammo maker matches weapon:  %d%%" % int(round(100.0 * guaranteed_match / SEEDS)))
	print("  weapon feedable somewhere on the map:        %d%%  (a fixed-family Ammo Maker of your family exists)" % int(round(100.0 * mapwide_match / SEEDS)))

	_chain_simulation()
	_repair_note(float(loose_scrap) / SEEDS)
	get_tree().quit()


func _chain_simulation() -> void:
	print("\n=== C) END-TO-END CHAIN  (single 8x8 grid) ===")
	var f := FactoryGrid.new(8, 8)
	var arm := f.place_machine("scrapper_arm", Vector2i(0, 0))
	var rec := f.place_machine("copper_recycler", Vector2i(3, 1))
	var am := f.place_machine("copper_ammo_maker", Vector2i(3, 4))
	print("  placed  arm:%s recycler:%s ammo_maker:%s" % [arm >= 0, rec >= 0, am >= 0])
	var used := 0
	for y in f.rows:
		for x in f.cols:
			if not f.get_cell(Vector2i(x, y)).is_empty():
				used += 1
	print("  3 machines occupy %d/64 cells -> %d free for scrap + conveyors" % [used, 64 - used])
	if rec >= 0:
		for p: Vector2i in f.input_positions(f.machines[rec]):
			f.set_cell(p, {"kind": "resource", "id": "copper_scrap", "count": 4})
		for _t in 6: f.tick(2.5)
		var copper := int(f.resource_counts().get("copper", 0))
		print("  recycler: copper from scrap = %d (%s)" % [copper, "ok" if copper > 0 else "FAIL"])
	if am >= 0:
		for p: Vector2i in f.input_positions(f.machines[am]):
			f.set_cell(p, {"kind": "resource", "id": "copper", "count": 4})
		for _t in 6: f.tick(2.5)
		var ammo := int(f.resource_counts().get("charge_cells", 0))
		print("  ammo maker: charge_cells from copper = %d (%s)" % [ammo, "ok" if ammo > 0 else "FAIL"])


func _repair_note(avg_loose: float) -> void:
	var need := 2 + 3 + 4  # Recycler + Ammo Maker + Component Maker repair costs
	print("\n=== D) REPAIR ECONOMY ===")
	print("  materials to repair one of each category: %d" % need)
	print("  loose scrap/run: %.1f  -> %s" % [avg_loose, "plenty" if avg_loose >= need * 2 else ("ok" if avg_loose >= need else "TIGHT")])
