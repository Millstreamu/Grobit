class_name RecyclerSystem
extends Node
## Processes recycler modules sitting in the inventory grid. A recycler only works
## on scrap the player has fed into it (by moving a resource onto its slot); it
## then converts buffered input into output over time and drops the output into a
## free inventory slot. Rates are data-driven (data/game/recyclers).

func _ready() -> void:
	add_to_group("recycler_system")


func _process(delta: float) -> void:
	if not RunState.run_active:
		return
	var speed := 1.0 + MetaState.effect_total("recycler_speed", 0.0)
	for i in RunState.slot_count():
		var slot := RunState.get_slot(i)
		if slot.get("kind", "") != "module":
			continue
		var def: Dictionary = GameData.recyclers.get(String(slot.get("id", "")), {})
		if def.is_empty():
			continue
		var input_amount := int(def.get("input_amount", 1))
		if int(slot.get("buffer", 0)) < input_amount:
			slot["progress"] = 0.0
			continue
		slot["progress"] = float(slot.get("progress", 0.0)) + delta * speed
		if slot["progress"] < float(def.get("seconds", 3.0)):
			continue
		# Only complete a conversion when there is room for the output.
		if not RunState.has_space():
			slot["progress"] = float(def.get("seconds", 3.0))
			continue
		slot["progress"] = float(slot["progress"]) - float(def.get("seconds", 3.0))
		slot["buffer"] = int(slot["buffer"]) - input_amount
		RunState.add(String(def.get("output", "")), int(def.get("output_amount", 1)))


## For the HUD status line: one dict per recycler module in the grid.
func states() -> Array:
	var result: Array = []
	for i in RunState.slot_count():
		var slot := RunState.get_slot(i)
		if slot.get("kind", "") != "module":
			continue
		var def: Dictionary = GameData.recyclers.get(String(slot.get("id", "")), {})
		if def.is_empty():
			continue
		var input_amount := int(def.get("input_amount", 1))
		var buffer := int(slot.get("buffer", 0))
		result.append({
			"name": String(def.get("name", slot.get("id", ""))),
			"input": String(def.get("input", "")),
			"output": String(def.get("output", "")),
			"buffer": buffer,
			"input_amount": input_amount,
			"ratio": clampf(float(slot.get("progress", 0.0)) / maxf(0.01, float(def.get("seconds", 3.0))), 0.0, 1.0),
			"working": buffer >= input_amount,
		})
	return result
