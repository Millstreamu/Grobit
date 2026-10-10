extends Node
## Phase 3 — the in-room COMMAND layer. Goblins are IDLE until commanded. `command_target` registers
## a task (priority = assignment order) and puts ONE more idle, capable goblin on it per call, so the
## squad SPLITS across tasks. `cancel_target` pulls them off. When a task finishes, idle goblins flow
## to the next commanded task in priority order, then idle by the bot.

const TICK := 1.0 / 60.0

var fail := 0


func _ready() -> void:
	MetaState.seed_colony(3)
	RunState.begin_run(GameData.first_area_id(), 1)
	RunState.driving = true
	var bot := Node2D.new()
	add_child(bot)
	var hm := HarvestMode.new()
	hm.bot = bot
	add_child(hm)
	var a := _pile(10)
	a.global_position = Vector2(100, 0)
	add_child(a)
	var b := _pile(10)
	b.global_position = Vector2(-100, 0)
	add_child(b)

	hm.deploy()
	var gobs := get_tree().get_nodes_in_group("harvester_goblins")
	_ck(gobs.size() == 3, "deploy pours out the 3-goblin squad")
	_ck(_all_idle(gobs), "goblins start IDLE — nothing is commanded yet")

	# Allocate 2 → pile A, 1 → pile B (each call adds one goblin; the squad splits).
	hm.command_target(a)
	hm.command_target(a)
	hm.command_target(b)
	_ck(hm.goblins_on(a) == 2 and hm.goblins_on(b) == 1, "2 goblins on A, 1 on B (the squad splits)")
	_ck(hm.task_count() == 2, "two tasks registered")

	# Cancel A → its goblins come off; on the next tick they flow to the remaining task (B).
	hm.cancel_target(a)
	_ck(hm.goblins_on(a) == 0, "cancel pulls every goblin off that task")
	for g: Node in gobs:
		g._physics_process(TICK)
	_ck(hm.goblins_on(b) == 3, "freed goblins flow to the next commanded task (all 3 now on B)")

	# Finish B (strip it clean + free it): the task is pruned and the goblins idle.
	while not b.is_spent():
		b.take_one()
	b.free()
	for _i in 4:
		for g: Node in gobs:
			if is_instance_valid(g):
				g._physics_process(TICK)
	_ck(hm.task_count() == 0, "a finished task is pruned")
	_ck(_all_idle(gobs), "with no tasks left, goblins idle again")

	# A goblin can't be commanded to a pile above its tool tier.
	var ceramic := _pile_of("ceramic_scrap", 5)  # tier 4, starter tool is tier 1
	add_child(ceramic)
	_ck(not hm.command_target(ceramic), "can't dispatch a tier-1 goblin to a tier-4 pile")

	hm.queue_free()
	if fail == 0:
		print("COMMAND_TEST: ALL PASS")
	else:
		printerr("COMMAND_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _pile(n: int) -> ScrapNode:
	return _pile_of("steel_scrap", n)


func _pile_of(id: String, n: int) -> ScrapNode:
	var p := ScrapNode.new()
	p.generate({"label": "s", "tokens_min": n, "tokens_max": n, "pool": [{"id": id, "weight": 1}]})
	return p


func _all_idle(gobs: Array) -> bool:
	for g: Node in gobs:
		if is_instance_valid(g) and not g.is_idle():
			return false
	return true


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
