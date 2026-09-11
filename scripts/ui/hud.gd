class_name Hud
extends CanvasLayer
## Rough prototype HUD, built entirely in code so it needs no authored scene.
## Shows health, abilities, resources, recycler + manufacturing progress, build
## and interaction prompts, a short message log, and the end-of-run summary with
## permanent tech unlocks. Intentionally utilitarian — readability over polish.

const RESOURCE_ORDER := ["raw_scrap", "metal", "electronics", "power_cell", "circuit_board", "tech_data"]

var _player: GrobitPlayer
var _combat: PlayerCombat
var _abilities: GrobitAbilities
var _recyclers: RecyclerSystem
var _manufacturing: Manufacturing
var _build: BuildManager

var _status: Label
var _hp_fill: ColorRect
var _hp_label: Label
var _prompt: Label
var _messages: Array = []

var _inventory_panel: Control
var _inventory_list: VBoxContainer
var _manufacture_panel: Control
var _manufacture_label: Label
var _summary_panel: Control
var _summary_label: Label


func setup(player: GrobitPlayer, recyclers: RecyclerSystem, manufacturing: Manufacturing, build: BuildManager) -> void:
	_player = player
	_combat = player.get_node("Combat") as PlayerCombat
	_abilities = player.get_node("Abilities") as GrobitAbilities
	_recyclers = recyclers
	_manufacturing = manufacturing
	_build = build
	RunState.inventory_changed.connect(_on_inventory_changed)
	if _player.health != null:
		_player.health.health_changed.connect(_on_health_changed)
		_on_health_changed(_player.health.health, _player.health.max_health)
	_rebuild_inventory()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _process(_delta: float) -> void:
	if _combat == null:  # setup() not called yet
		return
	_status.text = _status_text()
	_prompt.text = _interaction_prompt()
	if _manufacture_panel.visible:
		_manufacture_label.text = _manufacture_text()
	if _summary_panel.visible:
		_summary_label.text = _summary_text()
	_handle_toggles()


func log_message(text: String) -> void:
	_messages.append({"text": text, "expires": Time.get_ticks_msec() + 4000})
	if _messages.size() > 5:
		_messages.pop_front()


# --------------------------------------------------------------- input ----

func _handle_toggles() -> void:
	if _summary_panel.visible:
		if Input.is_action_just_pressed("confirm"):
			var controller := get_parent() as RunController
			if controller != null:
				controller.restart_run()
			return
		for i in 4:
			if Input.is_action_just_pressed("hotbar_%d" % (i + 1)):
				_try_unlock_tech(i)
		return

	if Input.is_action_just_pressed("toggle_inventory"):
		_inventory_panel.visible = not _inventory_panel.visible
		if _inventory_panel.visible:
			_rebuild_inventory()
	if Input.is_action_just_pressed("toggle_manufacture"):
		_manufacture_panel.visible = not _manufacture_panel.visible
	# Crafting hotkeys only while the manufacturing panel is open and not building.
	if _manufacture_panel.visible and not _build.is_build_active():
		var recipe_ids: Array = GameData.recipes.keys()
		for i in mini(4, recipe_ids.size()):
			if Input.is_action_just_pressed("hotbar_%d" % (i + 1)):
				if not _manufacturing.start(recipe_ids[i]):
					log_message("Not enough materials for %s." % GameData.recipes[recipe_ids[i]].get("name", recipe_ids[i]))


func _try_unlock_tech(index: int) -> void:
	var locked := _locked_tech_ids()
	if index >= locked.size():
		return
	var tech_id: String = locked[index]
	if MetaState.unlock_tech(tech_id):
		log_message("Unlocked %s." % GameData.tech[tech_id].get("name", tech_id))
	else:
		log_message("Not enough tech data.")


func _locked_tech_ids() -> Array:
	var ids: Array = []
	for tech_id: String in GameData.tech:
		if not MetaState.has_tech(tech_id):
			ids.append(tech_id)
	return ids


# ---------------------------------------------------------------- text ----

func _status_text() -> String:
	var lines: Array = []
	lines.append("Abilities:  " + _ability_text())
	for state: Dictionary in _recyclers.states():
		var suffix := "%d%%" % int(state.ratio * 100.0) if state.active else "idle (need %s)" % GameData.resource_name(state.input)
		lines.append("Recycler: %s -> %s  %s" % [GameData.resource_name(state.input), GameData.resource_name(state.output), suffix])
	if not _manufacturing.current_recipe().is_empty():
		lines.append("Manufacturing: %s  %d%%  (queue %d)" % [
			GameData.recipes[_manufacturing.current_recipe()].get("name", ""),
			int(_manufacturing.current_ratio() * 100.0),
			_manufacturing.queue_size()])
	if _build.is_build_active():
		lines.append(_build.status_line())
	lines.append("Resources: " + _resource_line())
	lines.append("[I] inventory   [M] manufacture   [B] build   [E] EMP  [Q] shield  [R] regen  [F] interact")
	for msg: Dictionary in _messages:
		lines.append("> " + String(msg.text))
	return "\n".join(lines)


func _ability_text() -> String:
	var parts: Array = []
	parts.append("Shoot" if _combat.cooldown_ratio() <= 0.0 else "Shoot(%d%%)" % int((1.0 - _combat.cooldown_ratio()) * 100.0))
	for ability: String in ["emp", "shield", "regen"]:
		if _abilities.is_ready(ability):
			parts.append(ability.capitalize())
		else:
			parts.append("%s(%d%%)" % [ability.capitalize(), int((1.0 - _abilities.cooldown_ratio(ability)) * 100.0)])
	return "   ".join(parts)


func _resource_line() -> String:
	var parts: Array = []
	for id: String in RESOURCE_ORDER:
		var qty := RunState.get_quantity(id)
		if qty > 0:
			parts.append("%s %d" % [GameData.resource_name(id), qty])
	return "none" if parts.is_empty() else "   ".join(parts)


func _interaction_prompt() -> String:
	for node: Node in get_tree().get_nodes_in_group("interactables"):
		if node.has_method("can_interact") and node.can_interact():
			return node.interaction_prompt()
	return ""


func _manufacture_text() -> String:
	var lines: Array = ["MANUFACTURING  (press number to build)"]
	var recipe_ids: Array = GameData.recipes.keys()
	for i in recipe_ids.size():
		var id: String = recipe_ids[i]
		var def: Dictionary = GameData.recipes[id]
		var cost_parts: Array = []
		for res: String in def.get("inputs", {}):
			cost_parts.append("%d %s" % [int(def.inputs[res]), GameData.resource_name(res)])
		var affordable := "" if _manufacturing.can_craft(id) else "  (need materials)"
		lines.append("[%d] %s = %s%s" % [i + 1, String(def.get("name", id)), ", ".join(cost_parts), affordable])
	return "\n".join(lines)


func _summary_text() -> String:
	var lines: Array = []
	match RunState.result:
		RunState.RESULT_REPAIRED:
			lines.append("AREA COMPLETE — Power Generator repaired!")
		RunState.RESULT_EXTRACTED:
			lines.append("EXTRACTED — you left the area safely.")
		_:
			lines.append("RUN LOST — no respawn beacon remained.")
	lines.append("")
	lines.append("Resources this run:")
	for id: String in RESOURCE_ORDER:
		var qty := RunState.get_quantity(id)
		if qty > 0:
			lines.append("  %s: %d" % [GameData.resource_name(id), qty])
	lines.append("")
	lines.append("Banked Tech Data: %d" % MetaState.tech_data)
	var locked := _locked_tech_ids()
	if locked.is_empty():
		lines.append("All technologies unlocked.")
	else:
		lines.append("Unlock technology (press number):")
		for i in mini(4, locked.size()):
			var tid: String = locked[i]
			var def: Dictionary = GameData.tech[tid]
			lines.append("  [%d] %s (%d) — %s" % [i + 1, String(def.get("name", tid)), int(def.get("cost", 0)), String(def.get("desc", ""))])
	lines.append("")
	lines.append("[Enter] start a new run")
	return "\n".join(lines)


func show_summary(_result: String, _summary: Dictionary) -> void:
	_summary_panel.visible = true


# ------------------------------------------------------------ building ----

func _on_health_changed(current: int, maximum: int) -> void:
	if _hp_fill == null:
		return
	_hp_fill.size.x = 160.0 * (float(current) / maxf(1.0, float(maximum)))
	_hp_label.text = "HP %d / %d" % [current, maximum]


func _on_inventory_changed(_id: String, _qty: int) -> void:
	if _inventory_panel != null and _inventory_panel.visible:
		_rebuild_inventory()


func _rebuild_inventory() -> void:
	if _inventory_list == null:
		return
	for child in _inventory_list.get_children():
		child.queue_free()
	var header := Label.new()
	header.text = "INVENTORY"
	_inventory_list.add_child(header)
	for id: String in RESOURCE_ORDER:
		var qty := RunState.get_quantity(id)
		var row := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = ContentLibrary.get_icon(GameData.resource_icon(id), Vector2i(16, 16), GameData.resource_color(id))
		icon.custom_minimum_size = Vector2(18, 18)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var label := Label.new()
		label.text = "%s: %d" % [GameData.resource_name(id), qty]
		if qty <= 0:
			label.modulate = Color(1, 1, 1, 0.4)
		row.add_child(label)
		_inventory_list.add_child(row)


func _build_ui() -> void:
	# Health bar (top-left).
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.6)
	hp_bg.position = Vector2(12, 10)
	hp_bg.size = Vector2(160, 18)
	_add_control(hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.8, 0.25, 0.25)
	_hp_fill.position = Vector2(12, 10)
	_hp_fill.size = Vector2(160, 18)
	_add_control(_hp_fill)
	_hp_label = _make_label(Vector2(16, 10), 400)
	_add_control(_hp_label)

	# Main status text (top-left, below health).
	_status = _make_label(Vector2(12, 34), 620)
	_add_control(_status)

	# Interaction prompt (bottom-center).
	_prompt = _make_label(Vector2(80, 400), 520)
	_prompt.modulate = Color(1, 0.95, 0.6)
	_add_control(_prompt)

	# Inventory panel (top-right), hidden until toggled.
	_inventory_panel = _make_panel(Vector2(470, 40), Vector2(170, 200))
	_inventory_list = VBoxContainer.new()
	_inventory_list.position = Vector2(8, 8)
	_inventory_panel.add_child(_inventory_list)
	_inventory_panel.visible = false

	# Manufacturing panel (right, mid), hidden until toggled.
	_manufacture_panel = _make_panel(Vector2(360, 250), Vector2(280, 120))
	_manufacture_label = _make_label(Vector2(8, 8), 264)
	_manufacture_panel.add_child(_manufacture_label)
	_manufacture_panel.visible = false

	# End-of-run summary (center), hidden until the run ends.
	_summary_panel = _make_panel(Vector2(120, 60), Vector2(420, 340))
	_summary_label = _make_label(Vector2(14, 12), 400)
	_summary_panel.add_child(_summary_label)
	_summary_panel.visible = false


func _make_label(pos: Vector2, width: float) -> Label:
	var label := Label.new()
	label.position = pos
	label.custom_minimum_size = Vector2(width, 0)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func _make_panel(pos: Vector2, panel_size: Vector2) -> Control:
	var control := Control.new()
	control.position = pos
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 0.85)
	bg.size = panel_size
	control.add_child(bg)
	_add_control(control)
	return control


func _add_control(node: Control) -> void:
	add_child(node)
