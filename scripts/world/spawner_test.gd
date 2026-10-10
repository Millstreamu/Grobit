extends Node
## Phase 2.4b — destructible spawners. Shoot them down (below full alert) to CUT the enemy flow; once
## Heat hits FULL_ALERT they're hardened (can't be dropped) and even wrecked ones source again, so you
## can no longer clear your way out.

var fail := 0


func _ready() -> void:
	RunState.begin_run(GameData.first_area_id(), 1)

	var s := Spawner.new()
	add_child(s)
	_ck(s.can_source(), "an intact spawner can source enemies")

	RunState.heat = 0.0  # below full alert
	s.take_damage(Spawner.MAX_HP)
	_ck(s.destroyed, "enough damage wrecks a spawner below full alert")
	_ck(not s.can_source(), "a wrecked spawner stops sourcing — pressure relief")

	RunState.heat = RunState.HEAT_FULL_ALERT + 5.0
	_ck(s.can_source(), "on full alert even a wrecked spawner sources again (hardened)")
	var s2 := Spawner.new()
	add_child(s2)
	s2.take_damage(999)
	_ck(not s2.destroyed, "on full alert, damage can't wreck a spawner")

	# HarvestMode: wreck every spawner (below full alert) and the flow stops.
	RunState.heat = 0.0
	var hm := HarvestMode.new()
	add_child(hm)
	hm.bot = Node2D.new()
	add_child(hm.bot)
	hm.active = true
	hm._breach()
	_ck(hm._spawners.size() >= 1, "a breach plants spawner(s)")
	_ck(hm._pick_source_spawner() != null, "a source is available while spawners stand")
	for sp: Variant in hm._spawners:
		sp.take_damage(Spawner.MAX_HP)
	_ck(hm._pick_source_spawner() == null, "wrecking every spawner cuts the flow (no source)")
	RunState.heat = RunState.HEAT_FULL_ALERT + 5.0
	_ck(hm._pick_source_spawner() != null, "full alert brings wrecked spawners back as sources")
	hm.queue_free()

	if fail == 0:
		print("SPAWNER_TEST: ALL PASS")
	else:
		printerr("SPAWNER_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
