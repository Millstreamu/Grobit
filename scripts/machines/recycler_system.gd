class_name RecyclerSystem
extends Node
## Auto-processes installed recyclers over time. Each installed recycler converts
## a raw material into a processed material whenever enough input is available.
## Progress is exposed for the HUD. Rates are data-driven (data/game/recyclers).

var _progress: Array[float] = []


func _ready() -> void:
	add_to_group("recycler_system")


func _process(delta: float) -> void:
	if not RunState.run_active:
		return
	_sync_slots()
	var speed := 1.0 + MetaState.effect_total("recycler_speed", 0.0)
	for i in RunState.installed_recyclers.size():
		var def := _def(i)
		if def.is_empty():
			continue
		var input_id := String(def.get("input", ""))
		var input_amount := int(def.get("input_amount", 1))
		if RunState.get_quantity(input_id) < input_amount:
			_progress[i] = 0.0
			continue
		_progress[i] += delta * speed
		var seconds := float(def.get("seconds", 3.0))
		if _progress[i] >= seconds:
			_progress[i] -= seconds
			RunState.add(input_id, -input_amount)
			RunState.add(String(def.get("output", "")), int(def.get("output_amount", 1)))


## For the HUD: one dict per installed recycler.
func states() -> Array:
	_sync_slots()
	var result: Array = []
	for i in RunState.installed_recyclers.size():
		var def := _def(i)
		if def.is_empty():
			continue
		var seconds := float(def.get("seconds", 3.0))
		var input_id := String(def.get("input", ""))
		result.append({
			"name": String(def.get("name", RunState.installed_recyclers[i])),
			"input": input_id,
			"output": String(def.get("output", "")),
			"ratio": clampf(_progress[i] / maxf(0.01, seconds), 0.0, 1.0),
			"active": RunState.get_quantity(input_id) >= int(def.get("input_amount", 1)),
		})
	return result


func _sync_slots() -> void:
	if _progress.size() != RunState.installed_recyclers.size():
		_progress.resize(RunState.installed_recyclers.size())
		_progress.fill(0.0)


func _def(index: int) -> Dictionary:
	if index < 0 or index >= RunState.installed_recyclers.size():
		return {}
	return GameData.recyclers.get(RunState.installed_recyclers[index], {})
