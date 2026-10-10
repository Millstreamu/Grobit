extends Node
## Phase 2.1 — the run-wide HEAT meter (presence). It starts calm, rises (never decays in play),
## crosses two staged thresholds (bot-threat, full-alert), clamps to [0, MAX], and resets each run.
## HarvestMode raises it while you're engaged in a breach.

var fail := 0


func _ready() -> void:
	RunState.begin_run(GameData.first_area_id(), 1)
	_ck(RunState.heat == 0.0, "heat starts at 0 each run")
	_ck(RunState.heat_tier() == RunState.HEAT_CALM, "0 heat = calm")

	RunState.add_heat(RunState.HEAT_BOT_THREAT + 5.0)  # 60
	_ck(absf(RunState.heat_ratio() - 0.6) < 0.001, "heat_ratio is heat / HEAT_MAX")
	_ck(RunState.heat_tier() == RunState.HEAT_BOT_THREAT_TIER, "crossing HEAT_BOT_THREAT escalates to bot-threat")

	RunState.add_heat(RunState.HEAT_FULL_ALERT - RunState.HEAT_BOT_THREAT)  # up past full-alert
	_ck(RunState.heat_tier() == RunState.HEAT_FULL_ALERT_TIER, "crossing HEAT_FULL_ALERT = full alert")

	RunState.add_heat(9999)
	_ck(RunState.heat == RunState.HEAT_MAX, "heat clamps at HEAT_MAX")
	RunState.add_heat(-9999)
	_ck(RunState.heat == 0.0, "add_heat clamps at 0 (used by the later Reduce-Heat ability)")

	# Resets with the run.
	RunState.add_heat(50)
	RunState.begin_run(GameData.first_area_id(), 1)
	_ck(RunState.heat == 0.0, "begin_run resets heat to calm")

	# HarvestMode raises Heat while a breach is live with enemies about (and NOT while recalling).
	var hm := HarvestMode.new()
	add_child(hm)
	hm.bot = Node2D.new()
	add_child(hm.bot)
	hm.active = true
	hm._breached = true
	var e := Node2D.new()
	add_child(e)
	hm._enemies.append(e)
	var before := RunState.heat
	hm.advance_siege(1.0)
	_ck(RunState.heat > before, "engaging enemies in a breach raises Heat")
	hm.recalling = true
	var held := RunState.heat
	hm.advance_siege(1.0)
	_ck(RunState.heat == held, "recalling (disengaged) stops Heat climbing")
	hm.queue_free()

	if fail == 0:
		print("HEAT_TEST: ALL PASS")
	else:
		printerr("HEAT_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
