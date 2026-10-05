class_name MachinePickup
extends Area2D
## A machine lying in a room. Two flavours:
##  - a plain crate you take (machine_id set, broken = false) — the old behaviour.
##  - a BROKEN machine you repair (broken = true): pay repair_cost, then it is RANDOMLY
##    specialised into one of `spec_pool` (e.g. a broken Recycler becomes a Copper /
##    Steel / Plastic / Ceramic Recycler). The result goes to stock and the found card
##    reveals what you got. Non-solid, so Grobit can walk over it.

@export var machine_id := "scrap_recycler"

## Broken-machine fields (data-driven; see AreaGenerator machine_finds.categories).
var broken := false
var category := "Machine"
var spec_pool: Array = []          # [{id, weight}] or [id] to roll on repair
var repair_cost: Dictionary = {}   # resources spent (from the factory inventory) to repair

var _in_range := false
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("pickups")
	# All machine finds look the same on the floor (a generic crate); you only learn
	# what it is when you repair/take it.
	_sprite = Sprite2D.new()
	_sprite.texture = ContentLibrary.get_icon("machine_crate", Vector2i(24, 24), "9aa4b0")
	add_child(_sprite)
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 14.0
	col.shape = shape
	add_child(col)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_in_range = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_in_range = false


func can_interact() -> bool:
	return _in_range


func selection_size() -> int:
	return 24


func interaction_prompt() -> String:
	if broken:
		var cost := "" if repair_cost.is_empty() else "  (%s)" % _cost_text(repair_cost)
		# Fixed specialisation: the pile already knows what it'll become, so name it (you
		# decide whether it's worth repairing BEFORE you spend the materials).
		var fixed := _fixed_spec()
		if fixed != "":
			return "[F] Repair broken %s%s" % [_name(fixed), cost]
		return "[F] Repair broken %s%s" % [category, cost]
	return "[F] Take %s" % _name(machine_id)


## The single pre-decided specialisation id, or "" if this pile still rolls randomly.
func _fixed_spec() -> String:
	if spec_pool.size() == 1:
		var e: Variant = spec_pool[0]
		return String(e.get("id", "")) if e is Dictionary else String(e)
	return ""


func interact() -> void:
	if broken:
		_repair()
	else:
		_grant(machine_id)


func _repair() -> void:
	if not RunState.can_afford(repair_cost):
		_notify("Need %s to repair." % _cost_text(repair_cost))
		return
	RunState.spend(repair_cost)
	var id := _roll_spec()
	if id.is_empty():
		return
	_grant(id)


## Adds a repaired machine to storage (as a per-instance record with its own rolled layout, so
## duplicates are worth collecting) and shows the reveal card. Transport parts stay fungible.
func _grant(id: String) -> void:
	if id.begins_with("__"):
		RunState.add_to_stock(id)            # conveyors/splitters/filters are fungible counts
	else:
		RunState.add_machine_instance(id)    # machines keep a unique rolled layout
	queue_free()
	for hud: Node in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("open_found_machine"):
			hud.open_found_machine(id)
			return


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


func _name(id: String) -> String:
	match id:
		"__conveyor": return "Conveyor"
		"__splitter": return "Splitter"
		"__filter": return "Filter"
	return String(GameData.machines.get(id, {}).get("name", id))


func _cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for res: String in cost:
		parts.append("%d %s" % [int(cost[res]), GameData.resource_name(res)])
	return ", ".join(parts)


func _notify(text: String) -> void:
	for hud: Node in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("log_message"):
			hud.log_message(text)
			return
