extends Node
## Tier-weighted generation: the world biases toward the player's CURRENT + NEXT tier. Scrap
## piles of higher tiers thin out / disappear, and machine finds mostly roll usable (current-
## tier) specs. Driven by the colony's best tool tier (MetaState.best_tool_tier()).

var fail := 0


func _ready() -> void:
	var gen := AreaGenerator.new()
	add_child(gen)

	# --- frontier tier 1 (every goblin has the starter steel tool) ---
	MetaState.seed_colony(1)
	_ck(abs(gen._tier_weight("steel_recycler") - 1.0) < 0.001, "steel find full weight at L1")
	_ck(abs(gen._tier_weight("copper_recycler") - 0.4) < 0.001, "copper (next tier) is a teaser weight")
	_ck(abs(gen._tier_weight("plastic_recycler") - 0.1) < 0.001, "plastic (beyond) is rare")
	_ck(abs(gen._tier_weight("frame_maker") - 1.0) < 0.001, "non-tiered machines stay neutral")

	# Scrap piles scaled: steel full, copper thinned, plastic/ceramic hidden.
	var cfg := {"nodes": [
		{"per_room_min": 0, "per_room_max": 2, "pool": [{"id": "steel_scrap", "weight": 1}]},
		{"per_room_min": 0, "per_room_max": 2, "pool": [{"id": "copper_scrap", "weight": 1}]},
		{"per_room_min": 0, "per_room_max": 2, "pool": [{"id": "plastic_scrap", "weight": 1}]},
		{"per_room_min": 0, "per_room_max": 2, "pool": [{"id": "ceramic_scrap", "weight": 1}]},
	]}
	var scaled: Array = gen._tier_scaled_harvest(cfg).nodes
	_ck(int(scaled[0].per_room_max) == 2, "steel piles spawn at full count")
	_ck(int(scaled[1].per_room_max) == 1, "copper piles (next tier) are thinned to a teaser")
	_ck(int(scaled[2].per_room_max) == 0, "plastic piles (beyond) don't litter the map")
	_ck(int(scaled[3].per_room_max) == 0, "ceramic piles (beyond) don't litter the map")

	# Finds mostly roll the current tier: at L1, a recycler pool returns steel the large majority.
	var pool := [{"id": "steel_recycler"}, {"id": "copper_recycler"}, {"id": "plastic_recycler"}, {"id": "ceramic_recycler"}]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var counts := {}
	for _i in 400:
		var id := gen._pick_spec(pool, rng)
		counts[id] = int(counts.get(id, 0)) + 1
	_ck(int(counts.get("steel_recycler", 0)) > 200, "L1 recycler finds are mostly steel (%d/400)" % int(counts.get("steel_recycler", 0)))
	_ck(int(counts.get("ceramic_recycler", 0)) < int(counts.get("copper_recycler", 0)), "ceramic (beyond) is rarer than copper (next)")

	# --- a goblin with a tier-3 (plastic) tool moves the frontier up ---
	MetaState.seed_colony(1)
	MetaState.roster[0]["tool"] = "poly_ripper"  # tier 3
	_ck(abs(gen._tier_weight("plastic_recycler") - 1.0) < 0.001, "plastic is full weight once reachable (tier 3)")
	_ck(abs(gen._tier_weight("ceramic_recycler") - 0.4) < 0.001, "ceramic becomes the next-tier teaser at tier 3")

	MetaState.seed_colony(3)
	if fail == 0:
		print("TIER_WEIGHT_TEST: ALL PASS")
	else:
		printerr("TIER_WEIGHT_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
