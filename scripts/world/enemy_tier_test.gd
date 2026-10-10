extends Node
## Phase 2.4a — enemy tiers keyed to Heat. Tier-1 grunts only threaten goblins; tier-2 bruisers
## (tankier, hit harder) appear once Heat crosses HEAT_BOT_THREAT and go for the SCRAPBOT itself.
## HarvestMode rolls the tier by the current Heat.

var fail := 0


class FakeBot extends Node2D:
	const MAXHP := 10
	var hp := MAXHP
	func take_damage(amount: int) -> void:
		hp -= amount


func _ready() -> void:
	RunState.begin_run(GameData.first_area_id(), 1)

	# Tier stats.
	var grunt := SiegeEnemy.new()
	add_child(grunt)
	grunt.setup_tier(1)
	_ck(grunt.tier == 1 and grunt._damage == SiegeEnemy.DAMAGE and grunt._max_hp == SiegeEnemy.MAX_HP, "tier 1 = grunt stats")
	var bruiser := SiegeEnemy.new()
	add_child(bruiser)
	bruiser.setup_tier(2)
	_ck(bruiser.tier == 2 and bruiser._damage == SiegeEnemy.BRUISER_DAMAGE and bruiser._max_hp == SiegeEnemy.BRUISER_HP, "tier 2 = bruiser stats (tankier, hits harder)")
	_ck(bruiser.is_in_group("bot_threats"), "bruisers join the bot_threats group")

	# A bruiser adjacent to the bot damages it; a grunt does not (goblin-only).
	var bot := FakeBot.new()
	bot.add_to_group("player")
	add_child(bot)
	bruiser.global_position = bot.global_position
	bruiser._physics_process(0.016)
	_ck(bot.hp == FakeBot.MAXHP - SiegeEnemy.BRUISER_DAMAGE, "a bruiser adjacent to the bot damages it")
	var before := bot.hp
	grunt.global_position = bot.global_position
	grunt._physics_process(0.016)
	_ck(bot.hp == before, "a grunt never attacks the bot (goblin-only)")

	# Heat gates the tier HarvestMode rolls.
	var hm := HarvestMode.new()
	add_child(hm)
	RunState.heat = 0.0  # calm
	var all_grunts := true
	for _i in 25:
		if hm._roll_enemy_tier() != 1:
			all_grunts = false
	_ck(all_grunts, "calm Heat only rolls grunts")
	RunState.heat = RunState.HEAT_BOT_THREAT + 1.0
	var saw_bruiser_bt := false
	for _i in 80:
		if hm._roll_enemy_tier() == 2:
			saw_bruiser_bt = true
	_ck(saw_bruiser_bt, "crossing HEAT_BOT_THREAT starts rolling bruisers")
	RunState.heat = RunState.HEAT_FULL_ALERT + 5.0
	var bruisers := 0
	for _i in 100:
		if hm._roll_enemy_tier() == 2:
			bruisers += 1
	_ck(bruisers > 50, "full alert rolls mostly bruisers (%d/100)" % bruisers)

	hm.queue_free()
	if fail == 0:
		print("ENEMY_TIER_TEST: ALL PASS")
	else:
		printerr("ENEMY_TIER_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
