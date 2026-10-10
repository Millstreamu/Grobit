class_name Hud
extends CanvasLayer
## Rough prototype HUD, built entirely in code so it needs no authored scene.
## Shows health, abilities, factory resources, manufacturing progress, build and
## interaction prompts, a short message log, and the end-of-run summary with
## permanent tech unlocks. Intentionally utilitarian — readability over polish.

const RESOURCE_ORDER := ["copper_scrap", "steel_scrap", "plastic_scrap", "ceramic_scrap", "copper", "steel", "plastic", "ceramic", "charge_cells", "steel_slugs", "resin_capsules", "ceramic_charges", "power_coupling", "control_assembly", "reinforced_frame", "thermal_core", "tech_data"]

var _player: GrobitPlayer
var _combat: PlayerCombat
var _abilities: GrobitAbilities
var _build: BuildManager

var _status: Label
var _hp_fill: ColorRect
var _hp_label: Label
var _prompt: Label
var _siege: Label
var _heat: Label
var _cargo: Label
var _messages: Array = []

var _minimap: Minimap
var _factory: FactoryPanel
var _scrapbot: ScrapbotPanel
var _exchange: ExchangePanel
var _terminal: LairPanel
var _hack: HackPanel
var _fabricator: FabricatorPanel
var _found: FoundMachinePanel
var _run_info: RunInfoPanel
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
	_minimap = Minimap.new()
	_minimap.position = Vector2(490, 6)
	add_child(_minimap)
	_minimap.configure(generator)
	if _player.health != null:
		_player.health.health_changed.connect(_on_health_changed)
		_on_health_changed(_player.health.health, _player.health.max_health)
	# No ability chooser at game start any more — you begin in the lair as the goblin. Picking a
	# run powerup will happen when you commit to a run (hop in the scrapbot); that's a placeholder
	# for now (see RunController._drive_out). A debug env var can still force one for headless tests.
	if RunState.equipped_ability.is_empty() and OS.has_environment("GROBIT_DEBUG_ABILITY"):
		var aid := OS.get_environment("GROBIT_DEBUG_ABILITY")
		if not GameData.abilities.has(aid) and not RunState.available_abilities.is_empty():
			aid = RunState.available_abilities[0]
		RunState.equipped_ability = aid
		if not aid.is_empty():
			_abilities.equip(aid)


var _last_overflow_msec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")
	_build_ui()
	RunState.overflow.connect(_on_overflow)


# Grid-full feedback: incoming items were lost because the factory has no room.
func _on_overflow(resource_id: String, lost: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_overflow_msec < 2500:
		return  # throttle so a burst of drops doesn't spam
	_last_overflow_msec = now
	log_message("Factory full — %d %s lost! Clear space in the grid." % [lost, GameData.resource_name(resource_id)])


func _process(_delta: float) -> void:
	if _combat == null:  # setup() not called yet
		return
	if Input.is_action_just_pressed("toggle_debug"):
		_status.visible = not _status.visible  # [`] shows/hides the debug readout
	if Input.is_action_just_pressed("debug_reset"):  # [F9] wipe factory + storage to a bare arm
		for rc: Node in get_tree().get_nodes_in_group("run_controller"):
			if rc.has_method("debug_reset_to_arm"):
				rc.debug_reset_to_arm()
				return
	if _status.visible:
		_status.text = _status_text()
	_prompt.text = _interaction_prompt()
	_update_siege()
	_update_heat()
	_update_cargo()
	if _summary_panel.visible:
		_summary_label.text = _summary_text()
	if _minimap != null:
		_minimap.visible = not (_factory.is_open() or _scrapbot.is_open() or _exchange.is_open() or _terminal.is_open() or _fabricator.is_open() or _found.is_open() or _run_info.is_open() or _ability_choice.is_open() or _hack.is_open())
	_handle_toggles()


## Opens the ability chooser mid-run (e.g. after unlocking one by repairing).
func open_ability_choice() -> void:
	if _ability_choice != null:
		_ability_choice.open()



## Opens the factory loadout for run setup (called by the scrapbot in the lair).
func open_factory() -> void:
	if _factory != null and not _factory.is_open():
		_factory.open()


## Opens the scrapbot window (bay / hold / crew / tasks). Called by [I] and by boarding the bot.
func open_scrapbot() -> void:
	if _scrapbot != null and not _scrapbot.is_open():
		_scrapbot.open()


## Opens the door-hack minigame for `door` (called by a field Door's interact()).
func open_hack(door: Node) -> void:
	if _hack != null and not _hack.is_open():
		_hack.open(door)


## Opens the component exchange (called by ComponentExchange.interact()).
func open_exchange() -> void:
	if _exchange != null:
		_exchange.open()


## Opens the system terminal (called by SystemTerminal.interact()).
func open_terminal() -> void:
	if _terminal != null:
		_terminal.open()


func open_fabricator() -> void:
	if _fabricator != null:
		_fabricator.open()


## Shown when a machine is picked up in a room: the reveal card.
func open_found_machine(machine_id: String) -> void:
	if _found != null:
		_found.open(machine_id)


## Jumps into the inventory in place-mode for a machine (from the found card).
func open_place_machine(machine_id: String) -> void:
	if _factory != null:
		_factory.open_place(machine_id)


func log_message(text: String) -> void:
	_messages.append({"text": text, "expires": Time.get_ticks_msec() + 4000})
	if _messages.size() > 5:
		_messages.pop_front()


# --------------------------------------------------------------- input ----

func _handle_toggles() -> void:
	if _hack.is_open():
		return  # the door-hack minigame owns input while open
	if _ability_choice.is_open():
		return  # run-start ability choice owns input until confirmed
	if _exchange.is_open():
		return  # the component exchange owns input while open
	if _terminal.is_open():
		return  # the system terminal owns input while open
	if _fabricator.is_open():
		return  # the Fabricator crafting menu owns input while open
	if _found.is_open():
		return  # the machine-found card owns input while open
	if _run_info.is_open():
		return  # the debug run-info panel owns input while open
	if _scrapbot.is_open():
		return  # the scrapbot window owns input while open (it closes itself on [I]/[Esc])
	if Input.is_action_just_pressed("run_info"):
		_run_info.open()
		return
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

	# The factory panel (lair WORKSHOP) is a full-screen modal opened from the scrapbot bench.
	if _factory.is_open():
		if Input.is_action_just_pressed("toggle_inventory"):
			_factory.try_close()  # refused while machines are still in storage
		return
	# [I] opens the SCRAPBOT window (bay / hold / abilities / crew / tasks).
	if Input.is_action_just_pressed("toggle_inventory"):
		_scrapbot.open()
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
	lines.append("Weapon:  " + _weapon_text())
	lines.append("Goal:  " + _goal_text())
	var _f := RunState.factory
	var _counts := _f.resource_counts() if _f != null else {}
	var _rc := func(id: String) -> int: return int(_counts.get(id, 0)) + (_f.inserter_count(id) if _f != null else 0)
	lines.append("Scrap — Cu %d  St %d  Pl %d  Ce %d    Tech Data: %d" % [_rc.call("copper_scrap"), _rc.call("steel_scrap"), _rc.call("plastic_scrap"), _rc.call("ceramic_scrap"), _rc.call("tech_data")])
	lines.append("Resources: " + _resource_line())
	lines.append("Lair: " + _lair_needs_line())
	lines.append("[Space] shoot (auto-aim)   [Tab] switch target   [F] interact")
	lines.append("[I] factory (place/combine/scrap machines)   [F] interact/scrap   [P] run info")
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


## Weapon family + ammo count (red when out — the run may lack a matching Ammo Maker).
func _weapon_text() -> String:
	# Combat uses a placed, loaded Weapon machine if you have one (stronger); otherwise
	# Grobit's weak built-in gun. Report whichever is actually driving your shots.
	var f := RunState.factory
	var loaded := ""
	var needs_ammo := ""
	if f != null:
		for m: Dictionary in f.machines:
			if bool(m.get("removed", false)):
				continue
			var def: Dictionary = GameData.machines.get(String(m.def_id), {})
			if not bool(def.get("weapon", false)):
				continue
			var ammo := String(def.get("ammo", ""))
			var is_loaded := false
			for p: Vector2i in f.input_positions(m):
				var c := f.get_cell(p)
				if String(c.get("kind", "")) == "resource" and String(c.get("id", "")) == ammo:
					is_loaded = true
					break
			if is_loaded:
				loaded = String(def.get("name", "Weapon"))
				break
			elif needs_ammo == "":
				needs_ammo = "%s needs %s" % [String(def.get("name", "Weapon")), GameData.resource_name(ammo)]
	if loaded != "":
		return "%s — loaded" % loaded
	if needs_ammo != "":
		return "UNARMED — %s" % needs_ammo
	return "UNARMED — find & repair a weapon, then feed it ammo"


func _goal_text() -> String:
	# First run (nothing delivered yet): show a step-by-step onboarding tip instead.
	if MetaState.mars_total() == 0:
		return _tip_text()
	# Otherwise: actionable "next unlock" first, then Mars total + ship note.
	var parts: Array = []
	var hint := MetaState.next_unlock_hint()
	if hint != "":
		parts.append("next: " + hint)
	parts.append("Mars %d" % MetaState.mars_total())
	parts.append("head back to the start to extract")
	return "   •   ".join(parts)


# Rough onboarding for a brand-new player (first run, nothing banked yet).
func _tip_text() -> String:
	var has_scrap := false
	var f := RunState.factory
	if f != null:
		var counts := f.resource_counts()
		for t: String in RunState.SCRAP_TYPES:
			if int(counts.get(t, 0)) + f.inserter_count(t) > 0:
				has_scrap = true
				break
	if not has_scrap:
		return "park the bot in a room and press [E] to deploy goblins — they strip scrap their tool can handle"
	return "open the factory [I]: place a scrap inserter to route a scrap type to a recycler, build recyclers/ammo makers + a weapon, then return to the start [F] to extract"


func _resource_line() -> String:
	# Show what's actually in the factory grid (where harvested/refined items live).
	var counts := RunState.factory.resource_counts() if RunState.factory != null else {}
	var parts: Array = []
	for id: String in counts:
		parts.append("%s %d" % [GameData.resource_name(String(id)), int(counts[id])])
	return "none" if parts.is_empty() else "   ".join(parts)


func _interaction_prompt() -> String:
	var best := SelectionManager.nearest_interactable(
		_player, get_tree().get_nodes_in_group("interactables")
	)
	return best.interaction_prompt() if best != null else ""


## Siege pressure readout — alarm meter while the colony harvests, breach warning once the doors
## give, plus deployed/incoming counts so the player can judge when to recall. Hidden otherwise.
func _update_siege() -> void:
	var mode: Node = get_tree().get_first_node_in_group("harvest_mode")
	if mode == null or not bool(mode.active):
		_siege.visible = false
		return
	_siege.visible = true
	var out: int = mode.deployed_count()
	# Does the bot have a weapon AND loaded ammo to man the auto-turrets? The fight-or-flee tell.
	var armed: bool = RunState.weapon_armed()
	var defense := "turrets ACTIVE" if armed else ("OUT OF AMMO — flee" if RunState.bay != null and RunState.bay.has_weapon() else "NO WEAPON — flee")
	if bool(mode.recalling):
		_siege.modulate = Color(0.6, 1, 0.7)
		_siege.text = "RECALLING — get to the bot and drive  ·  goblins out: %d" % out
		return
	if mode.is_breached():
		_siege.modulate = Color(1, 0.45, 0.4)
		_siege.text = "⚠ BREACHED — enemies: %d  ·  goblins out: %d  ·  %s  ·  [E] RECALL" % [mode.enemy_count(), out, defense]
		return
	var filled: int = int(round(mode.alarm_ratio() * 10.0))
	var meter := "▮".repeat(filled) + "▯".repeat(10 - filled)
	_siege.modulate = Color(1, 0.9, 0.55)
	_siege.text = "ALARM %s  ·  goblins out: %d  ·  %s  ·  [E] recall" % [meter, out, defense]


## Heat readout (shown while driving): the run-wide presence meter + what tier of threat it's brought.
func _update_heat() -> void:
	if _heat == null:
		return
	if not RunState.driving:
		_heat.visible = false
		return
	_heat.visible = true
	var filled: int = int(round(RunState.heat_ratio() * 12.0))
	var meter := "▮".repeat(filled) + "▯".repeat(12 - filled)
	var pct := int(round(RunState.heat_ratio() * 100.0))
	match RunState.heat_tier():
		RunState.HEAT_FULL_ALERT_TIER:
			_heat.modulate = Color(1, 0.4, 0.35)
			_heat.text = "HEAT %s %d%%  ·  FULL ALERT — get out!" % [meter, pct]
		RunState.HEAT_BOT_THREAT_TIER:
			_heat.modulate = Color(1, 0.7, 0.3)
			_heat.text = "HEAT %s %d%%  ·  bot-killers inbound" % [meter, pct]
		_:
			_heat.modulate = Color(0.7, 0.85, 0.75)
			_heat.text = "HEAT %s %d%%" % [meter, pct]


## Cargo-hold readout (shown out on a run): how full the bot's hold is, with a FULL warning.
func _update_cargo() -> void:
	var hold: CargoHold = RunState.cargo
	if hold == null or not RunState.driving:
		_cargo.visible = false
		return
	_cargo.visible = true
	var used := hold.used()
	var cap := hold.capacity()
	if hold.is_full():
		_cargo.modulate = Color(1, 0.45, 0.4)
		_cargo.text = "HOLD FULL %d/%d — extract to unload" % [used, cap]
	else:
		_cargo.modulate = Color(0.75, 0.85, 0.95) if hold.fullness() < 0.8 else Color(1, 0.85, 0.5)
		_cargo.text = "Hold %d/%d" % [used, cap]


## One-line lair-needs readout: "O2 2/5  Pwr 5/5  Wtr 0/5  Food 1/5" (or RESTORED).
func _lair_needs_line() -> String:
	if MetaState.beacon_sent:
		return "RESTORED — distress beacon sent."
	var parts: Array = []
	for need: String in MetaState.LAIR_NEEDS:
		parts.append("%s %d/%d" % [need.substr(0, 3).capitalize(), MetaState.need_amount(need), MetaState.NEED_MAX])
	return "  ".join(parts)


func _summary_text() -> String:
	var lines: Array = []
	match RunState.result:
		RunState.RESULT_RESCUED:
			lines.append("RESCUED! The lair is whole — the distress beacon is away.")
			lines.append("Other goblins are coming for you. You made it home.")
		RunState.RESULT_REPAIRED:
			lines.append("AREA COMPLETE — Power Generator repaired!")
		RunState.RESULT_EXTRACTED:
			lines.append("EXTRACTED — you left the area safely.")
		RunState.RESULT_SHIPPED:
			lines.append("EXTRACTED — you hauled your inventory back to the lair.")
		_:
			lines.append("RUN LOST — no respawn beacon remained.")
	lines.append("")
	# Lair needs — the meta goal. Components delivered THIS run are flagged.
	lines.append("Lair needs (deliver components to fix the lair):")
	for need: String in MetaState.LAIR_NEEDS:
		var got: int = int(RunState.needs_delivered.get(need, 0))
		var flag := "   (+%d this run)" % got if got > 0 else ""
		lines.append("  %s: %d / %d%s" % [need.capitalize(), MetaState.need_amount(need), MetaState.NEED_MAX, flag])
	if not MetaState.beacon_sent:
		lines.append("  Fill all four, then extract, to send the distress beacon.")
	lines.append("")
	lines.append("Resources this run:")
	for id: String in RESOURCE_ORDER:
		var qty := RunState.get_quantity(id)
		if qty > 0:
			lines.append("  %s: %d" % [GameData.resource_name(id), qty])
	lines.append("")
	lines.append("Tech Data: %d" % RunState.get_quantity("tech_data"))
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

	# Main status/debug text (top-left, below health). Small, and toggled with [`].
	_status = _make_label(Vector2(12, 34), 620)
	_status.add_theme_font_size_override("font_size", 11)
	_add_control(_status)

	# Interaction prompt (bottom-center).
	_prompt = _make_label(Vector2(80, 400), 520)
	_prompt.modulate = Color(1, 0.95, 0.6)
	_add_control(_prompt)

	# Siege readout — centred near the top, only shown while the colony is deployed.
	_siege = _make_label(Vector2(0, 60), 1152)
	_siege.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_siege.visible = false
	_add_control(_siege)

	# Heat (run-wide presence) readout — top-centre, shown while out on a run.
	_heat = _make_label(Vector2(0, 40), 1152)
	_heat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heat.visible = false
	_add_control(_heat)

	# Cargo-hold readout — top-right, shown while out on a run.
	_cargo = _make_label(Vector2(0, 80), 1138)
	_cargo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cargo.visible = false
	_add_control(_cargo)

	# Inventory-factory grid — opened with [I].
	_factory = FactoryPanel.new()
	add_child(_factory)

	# The scrapbot window ([I]) — bay / hold / abilities / crew / tasks.
	_scrapbot = ScrapbotPanel.new()
	add_child(_scrapbot)


	# Component exchange (opened from the start-room Component Exchange station).
	_exchange = ExchangePanel.new()
	add_child(_exchange)

	# System terminal (opened from a System Terminal — upload tech data, buy upgrades).
	_terminal = LairPanel.new()
	add_child(_terminal)

	# Door-hack minigame (opened by a field Door's interact()).
	_hack = HackPanel.new()
	add_child(_hack)

	# Fabricator crafting menu (opened from a Fabricator station).
	_fabricator = FabricatorPanel.new()
	add_child(_fabricator)

	# "Machine found" card (shown when you pick a machine up in a room).
	_found = FoundMachinePanel.new()
	add_child(_found)

	# Debug run-info panel ([P]).
	_run_info = RunInfoPanel.new()
	add_child(_run_info)

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
