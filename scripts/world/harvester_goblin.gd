class_name HarvesterGoblin
extends CharacterBody2D
## A deployed colony goblin — the ONLY thing that can harvest or repair (the scrapbot can't). It is
## COMMANDED now (Phase 3): it does nothing until the player assigns it a target (a scrap pile its
## TOOL allows, or a broken machine it can afford/repair). It works that target, auto-hauls the
## scrap / repaired machine back to the bot when full, then resumes it; when the target is done it
## flows to the next commanded task (priority = assignment order) or idles by the bot. A better tool
## is the main progression lever. Killed while carrying a repaired machine → that machine is lost.

const SPEED := 86.0
const HARVEST_TIME := 0.45    # base seconds per piece (scaled up by the pile's tier)
const CARRY_CAP := 3          # scrap pieces carried before hauling back to the bot
const REACH := 15.0           # how close counts as "arrived"

const MAX_HP := 3

var gob_name := ""             # which roster goblin this is (for permadeath + haul credit)
var tool_tier := 1            # the tier its equipped tool reaches — gates scrap + repairs
var _mode: Node                # the HarvestMode manager (bot position + recall flag)
var _state := "seek"           # seek | harvest | return | repair | carry_machine
var assigned_target: Node = null   # the COMMANDED target (a ScrapNode pile or a MachinePickup); null = idle
var _target: ScrapNode = null
var _machine_target: Node = null   # a MachinePickup being repaired
var _carry := 0
var _carry_id := ""
var _carry_machine_id := ""    # a repaired machine in hand, banked only on reaching the bot
var _progress := 0.0
var _hp := MAX_HP
var _flash := 0.0
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("harvester_goblins")
	collision_layer = 0
	collision_mask = 0
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 6.0
	col.shape = shape
	add_child(col)
	_sprite = Sprite2D.new()
	_sprite.texture = ContentLibrary.get_icon("goblin", Vector2i(16, 16), "6ab04c")
	_sprite.scale = Vector2(0.7, 0.7)
	add_child(_sprite)


func setup(mode: Node) -> void:
	_mode = mode


func carrying() -> int:
	return _carry


func carrying_machine() -> String:
	return _carry_machine_id


## Current hit points (for the in-run Crew readout in the Scrapbot window).
func health() -> int:
	return _hp


## A besieger hit this goblin. Permadeath: at 0 HP it's lost for good (any repaired machine it was
## hauling dies with it — it never reached the bot).
func take_damage(amount: int) -> void:
	_hp -= amount
	_flash = 0.18
	if _hp <= 0:
		if _mode != null and _mode.has_method("on_goblin_lost"):
			_mode.on_goblin_lost(self)  # removes from the colony (permanent)
		queue_free()


func _physics_process(delta: float) -> void:
	if _mode == null:
		return
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
		_sprite.modulate = Color(1, 0.4, 0.4)
	else:
		_sprite.modulate = Color.WHITE
	var bot: Vector2 = _mode.bot_position()
	# Recall overrides everything: drop what you're doing and get back to the bot.
	if bool(_mode.recalling):
		_move_to(bot)
		if global_position.distance_to(bot) <= REACH:
			_deposit_carry()
			_mode.board(self)  # re-boards (frees this goblin)
		return
	match _state:
		"seek": _seek(bot)
		"harvest": _harvest(delta)
		"return": _return(bot)
		"repair": _repair(delta)
		"carry_machine": _carry_machine(bot)


# --------------------------------------------------------------- seek ----

## Commanded behaviour: head to the ASSIGNED target and start working it. With no valid assignment,
## ask the mode for the next commanded task (priority order); if there's still none, idle by the bot.
func _seek(bot: Vector2) -> void:
	if not has_valid_assignment():
		assigned_target = null
		if _mode != null and _mode.has_method("reassign_idle"):
			_mode.reassign_idle(self)
	if not has_valid_assignment():
		_move_to(bot)  # nothing commanded — wait by the bot
		return
	var t := assigned_target as Node2D
	_move_to(t.global_position)
	if global_position.distance_to(t.global_position) <= REACH:
		_progress = 0.0
		if assigned_target is ScrapNode:
			_target = assigned_target
			_state = "harvest"
		else:
			_machine_target = assigned_target
			_state = "repair"


## True when this goblin has a target it can actually work (tool/affordability gates respected).
func has_valid_assignment() -> bool:
	if assigned_target == null or not is_instance_valid(assigned_target):
		return false
	return can_work(assigned_target)


## Can this goblin work `target` (a pile within its tool tier, or a machine it can afford + repair)?
func can_work(target: Node) -> bool:
	if target is ScrapNode:
		return _valid(target)
	return _machine_valid(target)


## Available to be given a new task (not currently committed to a valid one).
func is_idle() -> bool:
	return not has_valid_assignment()


# ------------------------------------------------------------ harvest ----

func _harvest(delta: float) -> void:
	if not _valid(_target):
		_target = null
		assigned_target = null  # this pile is done — flow to the next task (or idle) after hauling
		_state = "return" if _carry > 0 else "seek"
		return
	velocity = Vector2.ZERO
	_progress += delta
	if _progress >= _harvest_time(_target):
		_progress = 0.0
		var id := _target.take_one()
		if id != "":
			_carry += 1
			_carry_id = id
		if not _valid(_target):
			_target = null
			assigned_target = null  # stripped it clean
			_state = "return" if _carry > 0 else "seek"
		elif _carry >= CARRY_CAP:
			_state = "return"  # haul the full load, then resume this same pile (assignment kept)


## Per-piece time: higher scrap tiers take longer to strip (exposing the goblin more).
func _harvest_time(pile: ScrapNode) -> float:
	var tier: int = maxi(1, pile.scrap_tier())
	return HARVEST_TIME * (1.0 + 0.5 * float(tier - 1))


func _return(bot: Vector2) -> void:
	_move_to(bot)
	if global_position.distance_to(bot) <= REACH:
		_deposit_carry()
		# If the hold was full and a load remains in hand, idle at the bot (keep retrying) — the
		# colony stops producing, which is the signal to extract.
		_state = "seek" if _carry == 0 else "return"


# ------------------------------------------------------------- repair ----

func _repair(delta: float) -> void:
	if not _machine_valid(_machine_target):
		_machine_target = null
		assigned_target = null
		_state = "seek"
		return
	velocity = Vector2.ZERO
	_progress += delta
	if _progress >= float(_machine_target.repair_seconds()):
		_progress = 0.0
		var id := String(_machine_target.repair_and_take())  # spends cost, frees the pickup
		_machine_target = null
		assigned_target = null  # repaired — this task is done
		if id == "":
			_state = "seek"  # couldn't pay after all — leave it broken
			return
		_carry_machine_id = id
		_state = "carry_machine"


func _carry_machine(bot: Vector2) -> void:
	_move_to(bot)
	if global_position.distance_to(bot) <= REACH:
		_bank_machine()
		# If the hold couldn't take the bulky machine, keep holding it and idle at the bot.
		_state = "seek" if _carry_machine_id == "" else "carry_machine"


## Loads a hauled repaired machine into the bot's CARGO HOLD as a bulky crate (only reached if the
## goblin survived the carry). Fails silently if the hold has no room — the goblin keeps carrying.
func _bank_machine() -> void:
	if _carry_machine_id == "":
		return
	if RunState.cargo != null and RunState.cargo.deposit_machine(_carry_machine_id):
		_log("%s hauled a repaired %s into the hold." % [gob_name, _machine_name(_carry_machine_id)])
		_carry_machine_id = ""


## Deposits the carried scrap into the bot's CARGO HOLD (packs into 1×1 stacks). Only what fits is
## accepted; any remainder stays in hand (the hold is full).
func _deposit_carry() -> void:
	if _carry > 0 and _carry_id != "" and RunState.cargo != null:
		var took := RunState.cargo.deposit_scrap(_carry_id, _carry)
		if took > 0 and gob_name != "":
			MetaState.record_haul(gob_name, took)
		_carry -= took
		if _carry <= 0:
			_carry_id = ""
	_bank_machine()  # also stow any repaired machine in hand (e.g. on recall/board)


func _move_to(target: Vector2) -> void:
	var to := target - global_position
	velocity = to.normalized() * SPEED if to.length() > 2.0 else Vector2.ZERO
	move_and_slide()
	if absf(velocity.x) > 5.0:
		_sprite.flip_h = velocity.x < 0.0


# ----------------------------------------------------------- targeting ----

## Nearest harvestable (non-empty, tool allows) pile in the DEPLOY ROOM, or null.
func _nearest_pile() -> ScrapNode:
	var best: ScrapNode = null
	var best_dist := INF
	for n: Node in _mode.room_piles():
		var pile := n as ScrapNode
		if not _valid(pile):
			continue
		var d := global_position.distance_to(pile.global_position)
		if d < best_dist:
			best_dist = d
			best = pile
	return best


## Nearest broken machine in the room this goblin can afford to repair, or null.
func _nearest_machine() -> Node:
	var best: Node = null
	var best_dist := INF
	for n: Node in _mode.room_machines():
		if not _machine_valid(n):
			continue
		var d := global_position.distance_to((n as Node2D).global_position)
		if d < best_dist:
			best_dist = d
			best = n
	return best


# `pile` is deliberately UNTYPED: a pile stripped empty frees itself, and a typed ScrapNode
# parameter would reject the freed object before the body runs. Tier above the tool is off limits.
func _valid(pile: Variant) -> bool:
	if not is_instance_valid(pile):
		return false
	var node := pile as ScrapNode
	if node == null or node.is_spent():
		return false
	var tier := node.scrap_tier()
	return tier == 0 or tier <= tool_tier


func _machine_valid(m: Variant) -> bool:
	# Affordable (materials), AND its material tier must be unlocked for repair (a Tech Data gate —
	# tier-1 always, higher tiers need repair_t2/t3/t4). A machine above the unlocked tier is skipped.
	return is_instance_valid(m) and bool(m.get("broken")) and bool(m.affordable()) \
		and MetaState.can_repair(String(m.get("machine_id")))


func _machine_name(id: String) -> String:
	match id:
		"__conveyor": return "Conveyor"
		"__splitter": return "Splitter"
		"__filter": return "Filter"
		"__inserter": return "Scrap Inserter"
	return String(GameData.machines.get(id, {}).get("name", id))


func _log(text: String) -> void:
	for hud: Node in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("log_message"):
			hud.log_message(text)
			return
