class_name Manufacturing
extends Node
## Player-triggered manufacturing. Uses processed materials to build specific
## components over time. Kept conceptually separate from recyclers. Recipes are
## data-driven (data/game/recipes) so more can be added without code changes.

signal queue_changed()

var _current := ""
var _timer := 0.0
var _queue: Array[String] = []


func _ready() -> void:
	add_to_group("manufacturing")


func _process(delta: float) -> void:
	if _current.is_empty():
		if _queue.is_empty():
			return
		_current = _queue.pop_front()
		_timer = float(_def(_current).get("seconds", 4.0))
		queue_changed.emit()
		return
	_timer -= delta
	if _timer <= 0.0:
		# Hold the finished item until an inventory slot frees up.
		if not RunState.has_space():
			_timer = 0.0
			return
		var def := _def(_current)
		RunState.add(String(def.get("output", _current)), int(def.get("output_amount", 1)))
		_current = ""
		queue_changed.emit()


## Reserves inputs immediately and queues the craft. Returns false if unaffordable.
func start(recipe_id: String) -> bool:
	var def := _def(recipe_id)
	if def.is_empty():
		return false
	var inputs: Dictionary = def.get("inputs", {})
	if not RunState.spend(inputs):
		return false
	_queue.append(recipe_id)
	queue_changed.emit()
	return true


func can_craft(recipe_id: String) -> bool:
	return RunState.can_afford(_def(recipe_id).get("inputs", {}))


func current_recipe() -> String:
	return _current


func current_ratio() -> float:
	if _current.is_empty():
		return 0.0
	var seconds := float(_def(_current).get("seconds", 4.0))
	return clampf(1.0 - _timer / maxf(0.01, seconds), 0.0, 1.0)


func queue_size() -> int:
	return _queue.size()


func _def(recipe_id: String) -> Dictionary:
	return GameData.recipes.get(recipe_id, {})
