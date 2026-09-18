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

var _minimap: Minimap
var _inventory: InventoryPanel
var _manufacture: ManufacturePanel
var _ability_choice: AbilityChoicePanel
var _summary_panel: Control
var _summary_label: Label


func setup(player: GrobitPlayer, recyclers: RecyclerSystem, manufacturing: Manufacturing, build: BuildManager, generator: AreaGenerator) -> void:
	_player = player
	_combat = player.get_node("Combat") as PlayerCombat
	_abilities = player.get_node("Abilities") as GrobitAbilities
	_recyclers = recyclers
	_manufacturing = manufacturing
	_build = build
	_minimap = Minimap.new()
	_minimap.position = Vector2(490, 6)
	add_child(_minimap)
	_minimap.configure(generator)
	if _player.health != null:
		_player.health.health_changed.connect(_on_health_changed)
		_on_health_changed(_player.health.health, _player.health.max_health)
	# Choose the run's active ability up front if one isn't equipped yet.
	if RunState.equipped_ability.is_empty():
		if OS.has_environment("GROBIT_DEBUG_ABILITY"):  # skip the modal in headless tests
			var aid := OS.get_environment("GROBIT_DEBUG_ABILITY")
			if not GameData.abilities.has(aid) and not RunState.available_abilities.is_empty():
				aid = RunState.available_abilities[0]
			RunState.equipped_ability = aid
			if not aid.is_empty():
				_abilities.equip(aid)
		else:
			_ability_choice.open()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")
	_build_ui()


func _process(_delta: float) -> void:
	if _combat == null:  # setup() not called yet
		return
	_status.text = _status_text()
	_prompt.text = _interaction_prompt()
	if _summary_panel.visible:
		_summary_label.text = _summary_text()
	if _minimap != null:
		_minimap.visible = not (_inventory.is_open() or _manufacture.is_open() or _ability_choice.is_open())
	_handle_toggles()


## Opens the ability chooser mid-run (e.g. after unlocking one by repairing).
func open_ability_choice() -> void:
	if _ability_choice != null:
		_ability_choice.open()


## Manufacturing requires a built Fabricator (interact with one, or press M near/with one).
func open_manufacture() -> void:
	if get_tree().get_nodes_in_group("fabricators").is_empty():
		log_message("Build a Fabricator to manufacture components.")
		return
	_manufacture.open()


func log_message(text: String) -> void:
	_messages.append({"text": text, "expires": Time.get_ticks_msec() + 4000})
	if _messages.size() > 5:
		_messages.pop_front()


# --------------------------------------------------------------- input ----

func _handle_toggles() -> void:
	if _ability_choice.is_open():
		return  # run-start ability choice owns input until confirmed
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

	# Inventory and manufacturing are full-screen modals; only one open at a time,
	# each owns input (and closes with its own key) while open.
	if _inventory.is_open():
		if Input.is_action_just_pressed("toggle_inventory"):
			_inventory.close()
		return
	if _manufacture.is_open():
		if Input.is_action_just_pressed("toggle_manufacture"):
			_manufacture.close()
		return
	if Input.is_action_just_pressed("toggle_inventory"):
		_inventory.open()
		return
	if Input.is_action_just_pressed("toggle_manufacture"):
		open_manufacture()
		return


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
	lines.append("Ability:  " + _ability_text())
	for state: Dictionary in _recyclers.states():
		var suffix := "buffer %d/%d" % [state.buffer, state.input_amount]
		if state.working:
			suffix += "  %d%%" % int(state.ratio * 100.0)
		lines.append("Recycler: %s -> %s  (%s)" % [GameData.resource_name(state.input), GameData.resource_name(state.output), suffix])
	if not _manufacturing.current_recipe().is_empty():
		lines.append("Manufacturing: %s  %d%%  (queue %d)" % [
			GameData.recipes[_manufacturing.current_recipe()].get("name", ""),
			int(_manufacturing.current_ratio() * 100.0),
			_manufacturing.queue_size()])
	if _build.is_build_active():
		lines.append(_build.status_line())
	lines.append("Resources: " + _resource_line())
	lines.append("Shooting is automatic.   [Space] use ability   [Tab] switch target   [F] interact")
	lines.append("[I] inventory   [M] manufacture   [B] build (WASD move, Space place)")
	for msg: Dictionary in _messages:
		lines.append("> " + String(msg.text))
	return "\n".join(lines)


func _ability_text() -> String:
	var equipped := _abilities.equipped_id()
	if equipped.is_empty():
		return "Ability: —"
	if _abilities.is_ready():
		return "%s: ready" % _abilities.equipped_name()
	return "%s: %d%%" % [_abilities.equipped_name(), int((1.0 - _abilities.cooldown_ratio()) * 100.0)]


func _resource_line() -> String:
	var parts: Array = []
	for id: String in RESOURCE_ORDER:
		var qty := RunState.get_quantity(id)
		if qty > 0:
			parts.append("%s %d" % [GameData.resource_name(id), qty])
	return "none" if parts.is_empty() else "   ".join(parts)


func _interaction_prompt() -> String:
	var best: Node2D
	var best_distance := INF
	for node: Node in get_tree().get_nodes_in_group("interactables"):
		if not node is Node2D or not node.has_method("can_interact") or not node.can_interact():
			continue
		var distance := _player.global_position.distance_to((node as Node2D).global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best.interaction_prompt() if best != null else ""


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

	# Full-window grid inventory (modal), hidden until toggled.
	_inventory = InventoryPanel.new()
	add_child(_inventory)

	# Full-window manufacturing grid (modal), hidden until toggled.
	_manufacture = ManufacturePanel.new()
	add_child(_manufacture)

	# Run-start ability chooser (modal), opened from setup().
	_ability_choice = AbilityChoicePanel.new()
	add_child(_ability_choice)

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
