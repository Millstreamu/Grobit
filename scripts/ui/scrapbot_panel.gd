class_name ScrapbotPanel
extends Control
## The scrapbot window ([I]) — the player's main inventory/loadout view. Three tabs:
##   • Scrapbot — the bot's MODULE BAY (6×4, weapons/processors) above the CARGO HOLD (6×5, hauled
##     loot), with an ABILITIES strip (what the bay lets you do) and a hover INFO panel.
##   • Crew — at base, the pre-run SQUAD PICKER (which goblins ride out); in the field, a read-only
##     readout of the deployed goblins (live health + tool). Recruit/upgrade happen at the terminal.
##   • Tasks — a VIEW-ONLY mirror of the terminal's colony quests (progress only; claim at base).
## The lair WORKSHOP is NOT here — it's the bench you open from the scrapbot at the lair.
## Pauses the world while open. See docs/DESIGN_SPEC.md §0.1.

const PANEL := Vector2(640, 448)
const CELL := 38.0
const STEP := 40.0
const GRID_X := 18.0
const BAY_Y := 62.0
const HOLD_Y := 244.0
const RX := 272.0            # right column (abilities + info)

const TABS := ["Scrapbot", "Crew", "Tasks"]

var _tab := 0
var _cursor := Vector2i.ZERO   # unified over bay (y 0..3) + hold (y 4..8), 6 wide
var _crew_i := 0               # selected row on the Crew tab (squad picker, at base)
var _message := ""
var _opened_frame := -1
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2.ZERO
	size = PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = ThemeDB.fallback_font


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	_tab = 0
	_cursor = Vector2i.ZERO
	_message = ""
	_opened_frame = Engine.get_process_frames()
	visible = true
	get_tree().paused = true
	var h := get_parent()
	if h != null and h.has_method("nudge"):   # guided first run
		h.nudge("scrapbot", "Load your crew (Crew tab) and weapons/modules (bay), then [Enter] to drive out on a run.")
	queue_redraw()


func close() -> void:
	visible = false
	get_tree().paused = false


func _process(_delta: float) -> void:
	if not visible:
		return
	if Engine.get_process_frames() != _opened_frame:
		_handle_input()
	queue_redraw()


# ------------------------------------------------------------- input ----

func _handle_input() -> void:
	if Input.is_action_just_pressed("toggle_inventory") or Input.is_action_just_pressed("build_cancel"):
		close()
		return
	if Input.is_action_just_pressed("cycle_target"):
		_tab = (_tab + 1) % TABS.size()
		_message = ""
		return
	# [Enter] launches the run from anywhere in the window (at base only) — the loadout and squad
	# are set here, so this is where you commit and drive out.
	if not RunState.driving and Input.is_action_just_pressed("confirm"):
		_launch()
		return
	if _tab == 1:
		_handle_crew_input()
		return
	if _tab == 2:
		return  # Tasks is a view-only mirror of the terminal's quests (claim them at base)
	_move_cursor()
	if Input.is_action_just_pressed("attack"):
		_act_on_cursor()
	# [1]–[4] fire a module ability (tactical, non-twitch). Works at base and in the field; each
	# ability gates itself (field-only, charges). The strip shows the number → ability mapping.
	for i in 4:
		if Input.is_action_just_pressed("hotbar_%d" % (i + 1)):
			_use_ability(i)


## Commits the loadout + squad and drives out (the old factory-panel "Accept & launch").
func _launch() -> void:
	for controller: Node in get_tree().get_nodes_in_group("run_controller"):
		if controller.has_method("launch_from_setup"):
			close()
			controller.launch_from_setup()
			return


## Crew tab input. At base (pre-run) this is the SQUAD PICKER — [W/S] to choose a goblin, [Space]
## to toggle whether it deploys. In the field it's a read-only readout, so navigation is inert.
func _handle_crew_input() -> void:
	if RunState.driving:
		return
	var names := MetaState.colony_names()
	if names.is_empty():
		return
	if Input.is_action_just_pressed("move_up"):
		_crew_i = maxi(_crew_i - 1, 0)
	if Input.is_action_just_pressed("move_down"):
		_crew_i = mini(_crew_i + 1, names.size() - 1)
	if Input.is_action_just_pressed("attack"):
		RunState.toggle_deploy(String(names[_crew_i]))


func _move_cursor() -> void:
	var step := Vector2i.ZERO
	if Input.is_action_just_pressed("move_up"): step.y -= 1
	if Input.is_action_just_pressed("move_down"): step.y += 1
	if Input.is_action_just_pressed("move_left"): step.x -= 1
	if Input.is_action_just_pressed("move_right"): step.x += 1
	if step == Vector2i.ZERO:
		return
	var c := _cursor + step
	var max_y := RunState.BAY_ROWS + _hold_rows() - 1
	c.x = clampi(c.x, 0, 5)
	c.y = clampi(c.y, 0, max_y)
	_cursor = c


## [Space] on a bay cell: pick up a module back to storage, or equip the first stored module that
## fits. The hold is filled by goblins and unloaded at the lair, so it's view-only here.
func _act_on_cursor() -> void:
	if _in_bay():
		var pos := _cursor
		var mi := RunState.bay.machine_at(pos)
		if mi >= 0:
			var did := String(RunState.bay.machines[mi].get("def_id", ""))
			RunState.bay.pickup_machine(mi)
			RunState.add_machine_instance(did)
			_message = "%s returned to storage." % _name(did)
			return
		_equip_from_storage(pos)
	else:
		_message = "The hold is filled on a run and unloaded at the lair."


## Places the first stored BAY module (weapon / processor) whose rolled layout fits at `core`.
func _equip_from_storage(core: Vector2i) -> void:
	for i in RunState.machine_instances.size():
		var inst: Dictionary = RunState.machine_instances[i]
		var did := String(inst.get("def_id", ""))
		if not _is_bay_module(did):
			continue
		var ino: Array = inst.get("in_offsets", [])
		var outo: Array = inst.get("out_offsets", [])
		var ho: Array = inst.get("hold_offsets", [])
		var bo: Array = inst.get("body_offsets", [])
		if RunState.bay.can_place_layout(did, core, ino, outo, ho, bo):
			RunState.bay.place_machine_layout(did, core, ino, outo, ho, bo)
			RunState.take_instance(i)
			_message = "Equipped %s." % _name(did)
			return
	_message = "No module fits here — find/repair weapons or ammo presses, then equip them."


# --------------------------------------------------------------- draw ----

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, PANEL), Color(0.06, 0.06, 0.09, 1.0))
	for i in TABS.size():
		var tx := 18.0 + i * 92.0
		var active := i == _tab
		draw_string(_font, Vector2(tx, 30), String(TABS[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.95, 1.0) if active else Color(0.55, 0.57, 0.63))
		if active:
			draw_rect(Rect2(tx, 38, 78, 2), Color(0.3, 0.8, 0.7))
	draw_string(_font, Vector2(PANEL.x - 70, 30), "`  help", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.52, 0.58))
	match _tab:
		0: _draw_scrapbot()
		1: _draw_crew()
		2: _draw_tasks()
	# Launch is global (at base): the loadout + squad are set here, so [Enter] commits and drives out.
	if not RunState.driving:
		draw_string(_font, Vector2(PANEL.x - 200, PANEL.y - 12), "[Enter] launch run ▶", HORIZONTAL_ALIGNMENT_RIGHT, 186, 13, Color(0.6, 1.0, 0.7))


func _draw_scrapbot() -> void:
	var bay := RunState.bay
	var hold := RunState.cargo
	# Module bay
	draw_string(_font, Vector2(GRID_X, 54), "Module bay", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.8, 0.45))
	for r in RunState.BAY_ROWS:
		for c in 6:
			_draw_slot(GRID_X + c * STEP, BAY_Y + r * STEP, Color(0.16, 0.14, 0.10))
	for mi in bay.machines.size():
		var m: Dictionary = bay.machines[mi]
		if bool(m.get("removed", false)):
			continue
		var core := Vector2i(m.core)
		for c in 6:
			for r in RunState.BAY_ROWS:
				var p := Vector2i(c, r)
				var k := String(bay.get_cell(p).get("kind", ""))
				if k == "machine" or k == "machine_body":
					var rr := Rect2(GRID_X + c * STEP + 2, BAY_Y + r * STEP + 2, CELL - 4, CELL - 4)
					draw_rect(rr, Color(0.55, 0.42, 0.18, 0.8))
		draw_string(_font, Vector2(GRID_X + core.x * STEP + 4, BAY_Y + core.y * STEP + 22), _short(String(m.def_id)), HORIZONTAL_ALIGNMENT_LEFT, STEP * 2, 11, Color(1, 0.95, 0.85))
	# Cargo hold
	draw_string(_font, Vector2(GRID_X, 234), "Cargo hold", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.85, 0.72))
	for r in _hold_rows():
		for c in 6:
			_draw_slot(GRID_X + c * STEP, HOLD_Y + r * STEP, Color(0.10, 0.15, 0.14))
	for idx in hold.cells.size():
		var cell: Dictionary = hold.cells[idx]
		if cell.is_empty():
			continue
		var cx := idx % hold.cols
		var cy := idx / hold.cols
		var rr := Rect2(GRID_X + cx * STEP + 2, HOLD_Y + cy * STEP + 2, CELL - 4, CELL - 4)
		if String(cell.get("kind", "")) == "scrap":
			draw_rect(rr, Color(0.3, 0.55, 0.45, 0.8))
			draw_string(_font, rr.position + Vector2(3, 24), str(int(cell.get("count", 0))), HORIZONTAL_ALIGNMENT_LEFT, CELL, 12, Color(0.9, 1, 0.95))
		else:
			draw_rect(rr, Color(0.5, 0.45, 0.3, 0.85))
	# Cursor highlight
	var cr := _cursor_rect()
	draw_rect(cr, Color(1, 1, 1, 0.14))
	draw_rect(cr, Color(0.9, 0.95, 1.0, 0.7), false, 1.5)
	_draw_abilities()
	_draw_info()


func _draw_abilities() -> void:
	var w := PANEL.x - RX - 14
	draw_string(_font, Vector2(RX + 6, 54), "Abilities  [1–3]", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.9, 0.95))
	var abilities := _abilities()
	if abilities.is_empty():
		draw_string(_font, Vector2(RX + 6, 72), "Install support modules", HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.6, 0.62, 0.68))
		draw_string(_font, Vector2(RX + 6, 88), "(Coolant / Medbay / Scanner)", HORIZONTAL_ALIGNMENT_LEFT, w, 11, Color(0.5, 0.52, 0.58))
		return
	var y := 62.0
	for i in abilities.size():
		var a: Dictionary = abilities[i]
		var id := String(a.get("id", ""))
		var remaining := RunState.ability_remaining(id)
		var field_lock := bool(a.get("field_only", false)) and not RunState.driving
		var usable := remaining > 0 and not field_lock
		var col := Color(0.55, 0.9, 1.0) if usable else Color(0.5, 0.52, 0.58)
		var row := Rect2(RX + 4, y - 1, w, 18)
		if usable:
			draw_rect(row, Color(0.12, 0.35, 0.6, 0.25))
		draw_string(_font, Vector2(RX + 6, y + 13), "%d %s %s" % [i + 1, String(a.get("glyph", "•")), String(a.get("name", id))], HORIZONTAL_ALIGNMENT_LEFT, w - 48, 13, col)
		var tag := ("field" if field_lock else "%d/%d" % [remaining, RunState.ability_max(id)])
		draw_string(_font, Vector2(RX + 6, y + 13), tag, HORIZONTAL_ALIGNMENT_RIGHT, w - 6, 12, col)
		y += 20.0
	draw_string(_font, Vector2(RX + 6, y + 6), "charges refill at the lair", HORIZONTAL_ALIGNMENT_LEFT, w, 11, Color(0.55, 0.57, 0.63))


func _draw_info() -> void:
	var box := Rect2(RX, 130, PANEL.x - RX - 14, 300)
	draw_rect(box, Color(0.09, 0.10, 0.13))
	draw_rect(box, Color(0.22, 0.23, 0.29), false, 1.0)
	var info := _cursor_info()
	draw_string(_font, box.position + Vector2(14, 26), String(info.title), HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 28, 15, Color(0.92, 0.94, 0.98))
	if String(info.get("sub", "")) != "":
		draw_string(_font, box.position + Vector2(14, 46), String(info.sub), HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 28, 13, Color(0.7, 0.75, 0.82))
	var yy := 76.0
	for line: String in info.get("lines", []):
		draw_string(_font, box.position + Vector2(14, yy), line, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 28, 13, Color(0.72, 0.8, 0.88))
		yy += 22
	if _message != "":
		draw_string(_font, Vector2(14, PANEL.y - 12), _message, HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 28, 13, Color(1, 0.95, 0.7))


## Crew tab. At base: the SQUAD PICKER — pick which goblins ride out this run. In the field: a
## read-only readout of the deployed goblins (live health + tool), only the ones actually on the run.
func _draw_crew() -> void:
	if RunState.driving:
		_draw_crew_field()
	else:
		_draw_crew_squad()


## Pre-run squad picker: one row per colony goblin with a deploy checkbox + its tool.
func _draw_crew_squad() -> void:
	draw_string(_font, Vector2(GRID_X, 64), "Deploy squad", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.95, 0.85))
	var squad := RunState.squad_names()
	draw_string(_font, Vector2(PANEL.x - 170, 64), "%d of %d going out" % [squad.size(), MetaState.colony_size()], HORIZONTAL_ALIGNMENT_LEFT, 160, 12, Color(0.7, 0.75, 0.82))
	var names := MetaState.colony_names()
	var y := 90.0
	for i in names.size():
		var who := String(names[i])
		var going := RunState.is_deploying(who)
		var row := Rect2(GRID_X - 2, y - 2, PANEL.x - GRID_X - 12, 26)
		if i == _crew_i:
			draw_rect(row, Color(1, 1, 1, 0.1))
		var box := Rect2(GRID_X + 2, y + 2, 16, 16)
		draw_rect(box, Color(0.12, 0.2, 0.16) if going else Color(0.12, 0.12, 0.15))
		draw_rect(box, Color(0.45, 0.85, 0.55) if going else Color(0.35, 0.37, 0.42), false, 1.5)
		if going:
			draw_string(_font, box.position + Vector2(2, 13), "✓", HORIZONTAL_ALIGNMENT_LEFT, 16, 13, Color(0.6, 1.0, 0.7))
		var tier := MetaState.goblin_tool_tier(who)
		var col := Color(0.92, 0.95, 1.0) if going else Color(0.6, 0.62, 0.68)
		draw_string(_font, Vector2(GRID_X + 26, y + 15), "%s — %s (t%d)" % [who, MetaState.tool_name(_goblin_tool(who)), tier], HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - GRID_X - 60, 14, col)
		y += 28
	draw_string(_font, Vector2(GRID_X, PANEL.y - 12), "[W/S] pick   [Space] toggle who deploys", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.62, 0.68))


## In-field readout: only the goblins currently deployed, with their live health + tool.
func _draw_crew_field() -> void:
	draw_string(_font, Vector2(GRID_X, 64), "Crew on the ground", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.95, 0.85))
	var live := get_tree().get_nodes_in_group("harvester_goblins")
	if live.is_empty():
		draw_string(_font, Vector2(GRID_X, 94), "No goblins deployed — press [E] near scrap to send the squad out.", HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 40, 14, Color(0.7, 0.72, 0.78))
		return
	var y := 92.0
	for g: Node in live:
		var who := String(g.gob_name)
		var hp := int(g.health())
		var maxhp := int(HarvesterGoblin.MAX_HP)
		draw_string(_font, Vector2(GRID_X, y), "%s" % who, HORIZONTAL_ALIGNMENT_LEFT, 120, 14, Color(0.92, 0.95, 1.0))
		# HP pips.
		for h in maxhp:
			var pip := Rect2(GRID_X + 110 + h * 14, y - 11, 10, 10)
			draw_rect(pip, Color(0.85, 0.35, 0.35) if h < hp else Color(0.2, 0.2, 0.24))
		draw_string(_font, Vector2(GRID_X + 110 + maxhp * 14 + 12, y), "%s (t%d)" % [MetaState.tool_name(_goblin_tool(who)), MetaState.goblin_tool_tier(who)], HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 300, 13, Color(0.75, 0.82, 0.92))
		y += 28
	draw_string(_font, Vector2(GRID_X, PANEL.y - 12), "Lose a goblin and it's gone for good — recall [E] before the room overruns you.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.62, 0.68))


## Tasks tab — a VIEW-ONLY mirror of the terminal's colony quests: progress only, no claiming out
## in the field (cash them in at the System Terminal).
func _draw_tasks() -> void:
	draw_string(_font, Vector2(GRID_X, 64), "Tasks", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.9, 0.95))
	var y := 92.0
	for q: Dictionary in GameData.quests:
		var g: Dictionary = q.get("goal", {})
		var cur := MetaState.quest_current(g)
		var tgt := MetaState.quest_target(g)
		var claimed := MetaState.quest_claimed(String(q.get("id", "")))
		var done := cur >= tgt
		draw_string(_font, Vector2(GRID_X, y), "✦ " + String(q.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 150, 13, Color(0.86, 0.9, 0.78))
		var tag := "claimed" if claimed else ("ready — claim at base" if done else "%d/%d" % [cur, tgt])
		var tcol := Color(0.55, 0.6, 0.66) if claimed else (Color(0.6, 1.0, 0.7) if done else Color(0.72, 0.8, 0.9))
		draw_string(_font, Vector2(PANEL.x - 190, y), tag, HORIZONTAL_ALIGNMENT_RIGHT, 180, 12, tcol)
		y += 26
	draw_string(_font, Vector2(GRID_X, PANEL.y - 12), "View-only — claim rewards at the System Terminal.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.62, 0.68))


func _goblin_tool(gob_name: String) -> String:
	for g: Dictionary in MetaState.roster:
		if String(g.get("name", "")) == gob_name:
			return String(g.get("tool", MetaState.STARTER_TOOL))
	return MetaState.STARTER_TOOL


# ------------------------------------------------------------ helpers ----

func _hold_rows() -> int:
	return RunState.cargo.rows if RunState.cargo != null else RunState.CARGO_ROWS


func _in_bay() -> bool:
	return _cursor.y < RunState.BAY_ROWS


func _bay_pos() -> Vector2i:
	return _cursor


func _hold_pos() -> Vector2i:
	return Vector2i(_cursor.x, _cursor.y - RunState.BAY_ROWS)


func _cursor_rect() -> Rect2:
	if _in_bay():
		return Rect2(GRID_X + _cursor.x * STEP, BAY_Y + _cursor.y * STEP, CELL, CELL)
	var hp := _hold_pos()
	return Rect2(GRID_X + hp.x * STEP, HOLD_Y + hp.y * STEP, CELL, CELL)


func _draw_slot(x: float, y: float, fill: Color) -> void:
	var rr := Rect2(x, y, CELL, CELL)
	draw_rect(rr, fill)
	draw_rect(rr, Color(0.28, 0.3, 0.36), false, 1.0)


func _cursor_info() -> Dictionary:
	if _in_bay():
		var mi := RunState.bay.machine_at(_bay_pos())
		if mi >= 0:
			var did := String(RunState.bay.machines[mi].get("def_id", ""))
			return {"title": _name(did), "sub": "bay module", "lines": _module_lines(did)}
		if String(RunState.bay.get_cell(_bay_pos()).get("kind", "")) == "machine_body":
			return {"title": "module", "sub": "bay module", "lines": []}
		return {"title": "Empty bay slot", "sub": "", "lines": ["[Space] equip a stored weapon or processor"]}
	var cell := _hold_cell()
	var k := String(cell.get("kind", ""))
	if k == "scrap":
		return {"title": GameData.resource_name(String(cell.id)), "sub": "hauled scrap ×%d" % int(cell.get("count", 0)), "lines": ["refined into materials at the lair workshop"]}
	if k == "crate":
		return {"title": _name(String(cell.def_id)), "sub": "recovered machine (bulky)", "lines": ["banked to storage on extraction"]}
	return {"title": "Empty", "sub": "cargo hold", "lines": []}


func _hold_cell() -> Dictionary:
	var hp := _hold_pos()
	var idx := hp.y * RunState.cargo.cols + hp.x
	if idx >= 0 and idx < RunState.cargo.cells.size():
		return RunState.cargo.cells[idx]
	return {}


func _module_lines(did: String) -> Array:
	var def: Dictionary = GameData.machines.get(did, {})
	if bool(def.get("weapon", false)):
		var ammo := String(def.get("ammo", ""))
		var cap := RunState.ammo_capacity()
		if RunState.driving:
			return [
				"fires in combat — damage %d" % int(def.get("damage", 0)),
				"ammo loaded: %d / %d (hold cap)" % [RunState.ammo_count(ammo), cap],
				"make more in the workshop between runs",
			]
		var stock := RunState.get_quantity(ammo)
		return [
			"fires in combat — damage %d" % int(def.get("damage", 0)),
			"ammo: %s — %d in workshop stock" % [GameData.resource_name(ammo), stock],
			"the bot carries up to %d (capped by hold size)" % cap,
		]
	if float(def.get("fire_rate", 0.0)) > 0.0:
		return ["speeds up every weapon's fire rate", "+%d%% per Ammo Loader installed" % int(round(float(def.get("fire_rate", 0.0)) * 100.0))]
	var ab: Dictionary = def.get("ability", {})
	if not ab.is_empty():
		var id := String(ab.get("id", ""))
		var lines: Array = ["grants ability: %s" % String(ab.get("name", id))]
		match id:
			"reduce_heat":
				lines.append("vents %d Heat per use" % int(ab.get("amount", 10)))
			"heal_goblins":
				lines.append("heals deployed goblins +%d HP" % int(ab.get("amount", 2)))
			"scan":
				lines.append("reveals a nearby room's salvage")
		lines.append("%d charge(s)/run (use from [1–3]); stack to add more" % int(ab.get("charges", 1)))
		return lines
	return ["a bay module"]


## The usable abilities, one per distinct installed support module (charges summed across stacks).
func _abilities() -> Array:
	return RunState.installed_abilities()


## Fires ability #i (0-based) from the strip: checks charges + field-only gating, applies the effect,
## then spends a charge only if the effect actually did something.
func _use_ability(i: int) -> void:
	var list := _abilities()
	if i < 0 or i >= list.size():
		return
	var a: Dictionary = list[i]
	var id := String(a.get("id", ""))
	var nm := String(a.get("name", id))
	if RunState.ability_remaining(id) <= 0:
		_message = "%s — no charges left this run (refills at the lair)." % nm
		return
	if bool(a.get("field_only", false)) and not RunState.driving:
		_message = "%s only works out on a run." % nm
		return
	var summary := _apply_ability(id, a)
	if summary == "":
		return  # the effect was a no-op (reason already in _message); no charge spent
	RunState.use_ability(id)
	_message = "%s — %s. %d charge(s) left." % [nm, summary, RunState.ability_remaining(id)]


## Applies an ability's effect. Returns a short success summary, or "" (with _message set) when it
## was a no-op so the caller spends no charge.
func _apply_ability(id: String, a: Dictionary) -> String:
	match id:
		"reduce_heat":
			if RunState.heat <= 0.0:
				_message = "Heat is already calm — no need to vent."
				return ""
			var amt := float(a.get("amount", 10))
			RunState.add_heat(-amt)
			return "vented heat to %d" % int(round(RunState.heat))
		"heal_goblins":
			var amt := int(a.get("amount", 2))
			var healed := 0
			for g: Node in get_tree().get_nodes_in_group("harvester_goblins"):
				if g.has_method("needs_heal") and g.needs_heal():
					g.heal(amt)
					healed += 1
			if healed == 0:
				_message = "No wounded goblins deployed."
				return ""
			return "healed %d goblin(s)" % healed
		"scan":
			return _do_scan()
	return ""


## Scan the nearest un-scanned, un-cleared room and reveal its salvage to the HUD log.
func _do_scan() -> String:
	var controller := _find_controller()
	var gen: Variant = controller.generator if controller != null and "generator" in controller else null
	if gen == null or not ("rooms" in gen):
		_message = "Nothing to scan yet — drive out first."
		return ""
	var origin := _bot_position()
	var best: Room = null
	var best_d := INF
	for room: Room in gen.rooms:
		if room == null or room.scanned or room.is_cleared:
			continue
		if room.salvage_loot.is_empty():
			continue  # scanning is for rooms with guaranteed salvage worth revealing
		var d := origin.distance_to(room.center())
		if d < best_d:
			best_d = d
			best = room
	if best == null:
		_message = "No un-scanned salvage rooms in range."
		return ""
	best.scanned = true
	var summary := best.loot_summary()
	var parent := get_parent()
	if parent != null and parent.has_method("log_message"):
		parent.log_message("Scan: a room ahead holds %s." % summary)
	return "found %s" % summary


func _find_controller() -> Node:
	for c: Node in get_tree().get_nodes_in_group("run_controller"):
		return c
	return null


## The planted bot's position (the Scan origin), or zero if it can't be found.
func _bot_position() -> Vector2:
	for p: Node in get_tree().get_nodes_in_group("player"):
		if p is Node2D:
			return (p as Node2D).global_position
	return Vector2.ZERO


func _is_bay_module(did: String) -> bool:
	return bool(GameData.machines.get(did, {}).get("bay", false))


func _name(did: String) -> String:
	return String(GameData.machines.get(did, {}).get("name", did))


func _short(did: String) -> String:
	return _name(did).split(" ")[0]


func _ing(d: Dictionary) -> String:
	var parts: Array = []
	for id: String in d:
		parts.append("%d %s" % [int(d[id]), GameData.resource_name(id)])
	return ", ".join(parts)
