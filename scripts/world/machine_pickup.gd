class_name MachinePickup
extends Area2D
## A broken machine lying in a room. The scrapbot can't touch it — a deployed GOBLIN walks over,
## REPAIRS it in place (taking longer the rarer/more expensive it is, exposing the goblin to the
## siege), pays its repair_cost from the factory on completion, then HAULS it back to the bot. If
## the carrier is killed before reaching the bot, the repaired machine is lost. Non-solid.

@export var machine_id := "scrap_recycler"

## Broken-machine fields (data-driven; see AreaGenerator machine_finds.categories).
var broken := true
var category := "Machine"
var spec_pool: Array = []          # [{id, weight}] or [id] to roll on repair
var repair_cost: Dictionary = {}   # resources spent (from the factory) on repair completion

## Repair time tuning — the longer a goblin is exposed. Rarer/pricier machines (bigger repair_cost)
## take longer, so a weak tool that forces you to linger on cheap finds is a real cost.
const REPAIR_BASE := 2.0
const REPAIR_PER_COST := 1.2

var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("pickups")
	add_to_group("repairables")   # goblins scan this group for repair targets
	_sprite = Sprite2D.new()
	_sprite.texture = ContentLibrary.get_icon("machine_crate", Vector2i(24, 24), "9aa4b0")
	add_child(_sprite)
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 14.0
	col.shape = shape
	add_child(col)


## The scrapbot can't repair — only goblins can. Never offer this to the player's [F].
func can_interact() -> bool:
	return false


func selection_size() -> int:
	return 24


## Seconds a goblin must stay on this machine to repair it — scales with its repair cost (rarer /
## higher-tier finds cost more and take longer, per AreaGenerator._repair_cost_for).
func repair_seconds() -> float:
	var total := 0
	for res: String in repair_cost:
		total += int(repair_cost[res])
	return REPAIR_BASE + REPAIR_PER_COST * float(total)


## True if the factory can currently pay this machine's repair cost (goblins only target ones
## you can afford to finish).
func affordable() -> bool:
	return RunState.can_afford(repair_cost)


## The single pre-decided specialisation id, or "" if this pile still rolls randomly.
func _fixed_spec() -> String:
	if spec_pool.size() == 1:
		var e: Variant = spec_pool[0]
		return String(e.get("id", "")) if e is Dictionary else String(e)
	return ""


## Completes the repair: spends the cost from the factory, frees the pickup, and returns the
## repaired machine's id for the goblin to HAUL back (it is NOT banked yet — the goblin banks it
## on reaching the bot, so it's lost if the carrier dies). Returns "" if the cost can't be paid.
func repair_and_take() -> String:
	if not RunState.spend(repair_cost):
		return ""
	var id := _roll_spec()
	queue_free()
	return id


func _roll_spec() -> String:
	if spec_pool.is_empty():
		return machine_id
	var total := 0.0
	for entry: Variant in spec_pool:
		total += float(entry.get("weight", 1)) if entry is Dictionary else 1.0
	var pick := randf() * total
	for entry: Variant in spec_pool:
		pick -= float(entry.get("weight", 1)) if entry is Dictionary else 1.0
		if pick <= 0.0:
			return String(entry.get("id", "")) if entry is Dictionary else String(entry)
	var last: Variant = spec_pool[spec_pool.size() - 1]
	return String(last.get("id", "")) if last is Dictionary else String(last)
