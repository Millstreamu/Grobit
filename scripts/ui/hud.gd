class_name Hud
extends CanvasLayer
## Rough prototype HUD, built entirely in code so it needs no authored scene.
## Shows health, abilities, factory resources, manufacturing progress, build and
## interaction prompts, a short message log, and the end-of-run summary with
## permanent tech unlocks. Intentionally utilitarian — readability over polish.

const RESOURCE_ORDER := ["bent_panel", "cable_bundle", "burnt_board", "broken_motor", "mixed_components", "scrap_metal", "copper_wire", "electronic_scrap", "polymer", "mechanical_parts", "metal_bar", "metal_plate", "refined_copper", "polymer_sheet", "circuit_board", "motor", "structural_frame", "control_unit", "tech_data"]

var _player: GrobitPlayer
var _combat: PlayerCombat
var _abilities: GrobitAbilities
var _build: BuildManager

var _status: Label
var _hp_fill: ColorRect
var _hp_label: Label
var _prompt: Label
var _messages: Array = []

var _minimap: Minimap
var _factory: FactoryPanel
var _scrap_minigame: ScrapMinigame
var _cartridge: CartridgePanel
var _decode: DecodePanel
var _ability_choice: AbilityChoicePanel
var _build_palette: BuildPalette
var _summary_panel: Control
var _summary_label: Label


func setup(player: GrobitPlayer, build: BuildManager, generator: AreaGenerator) -> void:
	_player = player
	_combat = player.get_node("Combat") as PlayerCombat
	_abilities = player.get_node("Abilities") as GrobitAbilities
	_build = build
	_build_palette.setup(build)
	_scrap_minigame.setup(player)
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
		_minimap.visible = not (_factory.is_open() or _scrap_minigame.is_open() or _cartridge.is_open() or _decode.is_open() or _ability_choice.is_open())
	_handle_toggles()


## Opens the ability chooser mid-run (e.g. after unlocking one by repairing).
func open_ability_choice() -> void:
	if _ability_choice != null:
		_ability_choice.open()


## Opens the scrapping minigame for a node (called by ScrapNode.interact()).
func open_scrap_minigame(node: ScrapNode) -> void:
	if _scrap_minigame != null:
		_scrap_minigame.open(node)


## Opens the retrieval-cartridge loader (called by RetrievalPad.interact()).
func open_cartridge() -> void:
	if _cartridge != null:
		_cartridge.open()


## Opens the module decode draft (called by DecodeStation.interact()).
func open_decode(cost: Dictionary) -> void:
	if _decode != null:
		_decode.open(cost)


func log_message(text: String) -> void:
	_messages.append({"text": text, "expires": Time.get_ticks_msec() + 4000})
	if _messages.size() > 5:
		_messages.pop_front()


# --------------------------------------------------------------- input ----

func _handle_toggles() -> void:
	if _ability_choice.is_open():
		return  # run-start ability choice owns input until confirmed
	if _scrap_minigame.is_open():
		return  # the minigame owns input (A/D/Space/F/Esc) while open
	if _cartridge.is_open():
		return  # the cartridge loader owns input while open
	if _decode.is_open():
		return  # the decode draft owns input while open
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

	# The factory panel is a full-screen modal that owns input while open.
	if _factory.is_open():
		if Input.is_action_just_pressed("toggle_inventory"):
			_factory.close()
		return
	if Input.is_action_just_pressed("toggle_inventory"):
		_factory.open()
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
	lines.append("Resources: " + _resource_line())
	lines.append("Shooting is automatic.   [Space] use ability   [Tab] switch target   [F] interact")
	lines.append("[I] factory   [B] build   [F] interact/scrap")
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
	# Show what's actually in the factory grid (where harvested/refined items live).
	var counts := RunState.factory.resource_counts() if RunState.factory != null else {}
	var parts: Array = []
	for id: String in counts:
		parts.append("%s %d" % [GameData.resource_name(String(id)), int(counts[id])])
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
		RunState.RESULT_SHIPPED:
			lines.append("SHIPPED — retrieval cartridge sent home to Mars.")
		_:
			lines.append("RUN LOST — no respawn beacon remained.")
	lines.append("")
	lines.append("Resources this run:")
	for id: String in RESOURCE_ORDER:
		var qty := RunState.get_quantity(id)
		if qty > 0:
			lines.append("  %s: %d" % [GameData.resource_name(id), qty])
	lines.append("")
	if RunState.result == RunState.RESULT_SHIPPED and not RunState.last_run_unlocks.is_empty():
		lines.append("NEW: unlocked %s" % ", ".join(RunState.last_run_unlocks))
	lines.append("Delivered to Mars (all runs): %d" % MetaState.mars_total())
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

	# Inventory-factory grid — opened with [I].
	_factory = FactoryPanel.new()
	add_child(_factory)

	# Real-time scrapping minigame overlay (opened by interacting with a scrap node).
	_scrap_minigame = ScrapMinigame.new()
	add_child(_scrap_minigame)

	# Retrieval-cartridge loader (opened from the retrieval pad once shipping is on).
	_cartridge = CartridgePanel.new()
	add_child(_cartridge)

	# Module decode draft (opened from a decode station).
	_decode = DecodePanel.new()
	add_child(_decode)

	# Run-start ability chooser (modal), opened from setup().
	_ability_choice = AbilityChoicePanel.new()
	add_child(_ability_choice)

	# Non-modal build palette overlay, visible only while build mode is active.
	_build_palette = BuildPalette.new()
	add_child(_build_palette)

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
