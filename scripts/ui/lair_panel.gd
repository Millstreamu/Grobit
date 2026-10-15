class_name LairPanel
extends Control
## The COLONY STATION PANEL (Phase 1). The old single System Terminal is retired; the lair is now built
## from separate stations (see LairStation), and this one panel renders the three colony SECTIONS, each
## opened LOCKED to one section by its own station:
##   • GOBLINS  (Goblin Quarters) — recruit, equip found tools / upgrade a goblin's tool, the memorial.
##   • TASKS    (Mission Board)    — colony quests (claim rewards) + the lair-restoration goal.
##   • UPGRADES (Upgrade Bench)    — permanent machine/tech/cargo upgrades (spend Tech Data + materials).
## (Production and the process line are their own stations → FactoryPanel / ProcessWorkshopPanel.)
## Pauses the world while open. Tech Data is a grid inventory item, spent from the run inventory.

const PANEL := Vector2(640, 448)
const BODY_TOP := 92.0
const ROW_H := 22.0

## Machine types you can permanently upgrade. Phase 4 economy swap retired the recycler/maker factory,
## so the Upgrade Bench is now Tech + cargo only (no placeable production machines to level up). Weapons
## could be re-added here as a bay-module upgrade later.
const UPGRADABLE := []

const NEED_COLOR := {
	"oxygen": Color(0.45, 0.85, 1.0),
	"power": Color(0.95, 0.8, 0.35),
	"water": Color(0.45, 0.65, 1.0),
	"food": Color(0.55, 0.9, 0.55),
}

## The colony sections this panel can render, each opened by its own station.
const SECTIONS := ["goblins", "tasks", "upgrades"]
const SECTION_TITLES := {"goblins": "GOBLIN QUARTERS", "tasks": "MISSION BOARD", "upgrades": "UPGRADE BENCH"}

var _section := "goblins"
var _gi := 0          # selected row in the Goblins section (0 = recruit, then one per goblin)
var _ti := 0          # selected quest in the Tasks section
var _ui := 0          # selected row in the Upgrades section
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


## Opens the panel LOCKED to one colony section ("goblins" / "tasks" / "upgrades"), as launched by that
## section's station. No tab strip — each station is its own focused view.
func open_section(section: String) -> void:
	if visible:
		return
	_section = section if SECTIONS.has(section) else "goblins"
	_gi = 0
	_ti = 0
	_ui = 0
	_message = ""
	_opened_frame = Engine.get_process_frames()
	visible = true
	get_tree().paused = true
	queue_redraw()


func close() -> void:
	visible = false
	get_tree().paused = false


func _process(_delta: float) -> void:
	if not visible:
		return
	if Engine.get_process_frames() == _opened_frame:
		return  # swallow the keypress that opened us
	if Input.is_action_just_pressed("build_cancel"):
		close()
		return
	_handle_list_input()
	queue_redraw()


# ------------------------------------------------------------------ input ----

func _handle_list_input() -> void:
	match _section:
		"goblins":
			_handle_goblins_input()
		"tasks":
			_handle_tasks_input()
		"upgrades":
			_handle_upgrades_input()


func _handle_goblins_input() -> void:
	var rows := _goblin_rows()
	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("move_left"):
		_gi = maxi(_gi - 1, 0)
	if Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("move_right"):
		_gi = mini(_gi + 1, rows.size() - 1)
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("confirm"):
		var row: String = rows[_gi]
		if row == "__recruit":
			_do_recruit()
		else:
			_improve_goblin(row)


func _handle_tasks_input() -> void:
	var rows := _quest_rows()
	if rows.is_empty():
		return
	if Input.is_action_just_pressed("move_up"):
		_ti = maxi(_ti - 1, 0)
	if Input.is_action_just_pressed("move_down"):
		_ti = mini(_ti + 1, rows.size() - 1)
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("confirm"):
		_activate_task(String(rows[_ti]))


func _handle_upgrades_input() -> void:
	var rows := _upgrade_rows()
	if rows.is_empty():
		return
	if Input.is_action_just_pressed("move_up"):
		_ui = maxi(_ui - 1, 0)
	if Input.is_action_just_pressed("move_down"):
		_ui = mini(_ui + 1, rows.size() - 1)
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("confirm"):
		_activate_task(String(rows[_ui]))


# ----------------------------------------------------------------- actions ----

func _do_recruit() -> void:
	if not MetaState.can_recruit():
		_message = "The colony is at full strength (%d goblins)." % MetaState.COLONY_MAX
		return
	var rc := MetaState.recruit_cost()
	if not RunState.can_afford(rc):
		_message = "Recruiting needs %s (gather more out in runs)." % _cost_text(rc)
		return
	var rec := MetaState.recruit()
	_message = "%s joins the colony — now %d strong." % [String(rec.get("name", "A goblin")), MetaState.colony_size()]


## Improves a goblin's tool: first equips a higher-tier FOUND tool from the pool (free), otherwise
## spends the current tier's refined material (from the run inventory) to upgrade one tier.
func _improve_goblin(who: String) -> void:
	var current := MetaState.goblin_tool_tier(who)
	var best := MetaState.best_available_tool()
	if best != "" and MetaState.tool_tier(best) > current:
		MetaState.equip_tool(who, best)
		_message = "%s equips the %s (tier %d)." % [who, MetaState.tool_name(best), MetaState.tool_tier(best)]
		return
	var cost := MetaState.upgrade_tool_cost(who)
	if cost.is_empty():
		if current >= 4:
			_message = "%s's tool is already at max tier (ceramic)." % who
		else:
			_message = "Unlock %s toolsmithing (Tech Data) before upgrading past tier %d." % [GameData.resource_name(MetaState.TIER_MATERIAL[current]), current]
		return
	if not RunState.can_afford(cost):
		_message = "Upgrading %s's tool needs %s (refine more scrap first)." % [who, _cost_text(cost)]
		return
	RunState.spend(cost)
	var next_id := MetaState.tool_id_for_tier(current + 1)
	MetaState.set_goblin_tool(who, next_id)
	_message = "%s's tool upgraded → %s (tier %d)." % [who, MetaState.tool_name(next_id), current + 1]


func _activate_task(id: String) -> void:
	var td := MetaState.tech_data_on_hand()
	if id.begins_with("q:"):
		var q := _quest_by_id(id.substr(2))
		if q.is_empty():
			return
		if MetaState.quest_claimed(String(q.get("id", ""))):
			_message = "Already claimed."
		elif not MetaState.quest_done(q):
			var g: Dictionary = q.get("goal", {})
			_message = "Not done yet — %d / %d." % [MetaState.quest_current(g), MetaState.quest_target(g)]
		elif MetaState.claim_quest(q):
			_message = "Quest complete — +%d Tech Data." % int(q.get("reward", {}).get("tech_data", 0))
		return
	if id == "__cargo":
		if not MetaState.can_expand_cargo():
			_message = "The cargo hold is already at maximum size."
			return
		var cc := MetaState.expand_cargo_cost()
		if not RunState.can_afford(cc):
			_message = "Expanding the hold needs %s." % _cost_text(cc)
			return
		MetaState.expand_cargo()
		RunState.cargo = CargoHold.new(RunState.CARGO_COLS, RunState.cargo_rows())  # empty at base — apply now
		_message = "Cargo hold expanded — now %d cells." % RunState.cargo.capacity()
		return
	if id.begins_with("tech:"):
		var tid := id.substr(5)
		if MetaState.has_tech(tid):
			_message = "%s is already unlocked." % _tech_name(tid)
			return
		var cost := int(GameData.tech.get(tid, {}).get("cost", 0))
		if td < cost:
			_message = "%s needs %d Tech Data (you have %d)." % [_tech_name(tid), cost, td]
			return
		MetaState.unlock_tech(tid)
		_message = "Unlocked %s." % _tech_name(tid)
		return
	# A machine type upgrade — paid in refined materials.
	if not MetaState.can_upgrade_machine(id):
		_message = "%s is already at max level." % _name(id)
		return
	var mcost := MetaState.machine_upgrade_cost(id)
	if not RunState.can_afford(mcost):
		_message = "Need %s to upgrade %s." % [_cost_text(mcost), _name(id)]
		return
	MetaState.upgrade_machine(id)
	_message = "%s permanently upgraded → Lv %d." % [_name(id), MetaState.machine_level(id)]


# ------------------------------------------------------------------- rows ----

func _goblin_rows() -> Array:
	return ["__recruit"] + MetaState.colony_names()


## Tasks tab: the colony quests (claimable here).
func _quest_rows() -> Array:
	var rows: Array = []
	for q: Dictionary in GameData.quests:
		rows.append("q:" + String(q.get("id", "")))
	return rows


## Upgrades tab: everything you spend Tech Data on — the cargo hold, tech, and machine levels.
func _upgrade_rows() -> Array:
	var rows: Array = ["__cargo"]
	for tid: String in GameData.tech:
		rows.append("tech:" + tid)
	for m: String in UPGRADABLE:
		rows.append(m)
	return rows


func _quest_by_id(id: String) -> Dictionary:
	for q: Dictionary in GameData.quests:
		if String(q.get("id", "")) == id:
			return q
	return {}


# ------------------------------------------------------------------- draw ----

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, PANEL), Color(0.05, 0.055, 0.09, 0.98))
	_draw_header()
	match _section:
		"goblins":
			_draw_goblins()
			_draw_footer("[WASD] pick   [Space] recruit / improve tool   [Esc] close")
		"tasks":
			_draw_tasks()
			_draw_footer("[W/S] pick   [Space] claim reward   [Esc] close")
		"upgrades":
			_draw_upgrades()
			_draw_footer("[W/S] pick   [Space] buy upgrade   [Esc] close")


func _draw_header() -> void:
	draw_string(_font, Vector2(14, 28), String(SECTION_TITLES.get(_section, "COLONY")), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.55, 0.8, 1.0))
	# Shared counters, right-aligned (Food = recruiting, Tech Data = unlocks).
	var td := MetaState.tech_data_on_hand()
	var food := RunState.get_quantity("food")
	var counters := "Food %d    Tech Data %d    Colony %d/%d    Lost %d" % [food, td, MetaState.colony_size(), MetaState.COLONY_MAX, MetaState.fallen.size()]
	draw_string(_font, Vector2(PANEL.x - 430, 26), counters, HORIZONTAL_ALIGNMENT_RIGHT, 416, 13, Color(0.82, 0.88, 0.96))
	draw_line(Vector2(0, 80), Vector2(PANEL.x, 80), Color(0.16, 0.18, 0.24), 1.0)


func _draw_footer(controls: String) -> void:
	if _message != "":
		draw_string(_font, Vector2(14, PANEL.y - 26), _message, HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 28, 13, Color(1, 0.92, 0.7))
	draw_string(_font, Vector2(14, PANEL.y - 8), controls, HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 28, 12, Color(0.62, 0.64, 0.7))


# --- Goblins tab ---

func _draw_goblins() -> void:
	# Recruit button (row 0), full width.
	var rb := Rect2(14, BODY_TOP, PANEL.x - 28, 26)
	if _gi == 0:
		draw_rect(rb, Color(1, 1, 1, 0.1))
	draw_string(_font, Vector2(22, BODY_TOP + 18), "✚ Recruit a goblin (costs Food)", HORIZONTAL_ALIGNMENT_LEFT, 360, 14, Color(0.82, 1.0, 0.86))
	var rtext: String
	var rcol: Color
	if not MetaState.can_recruit():
		rtext = "FULL"
		rcol = Color(0.6, 0.85, 0.6)
	else:
		var rc := MetaState.recruit_cost()
		rtext = _cost_text(rc)
		rcol = Color(0.6, 1.0, 0.7) if RunState.can_afford(rc) else Color(0.9, 0.6, 0.55)
	draw_string(_font, Vector2(PANEL.x - 190, BODY_TOP + 18), rtext, HORIZONTAL_ALIGNMENT_RIGHT, 176, 13, rcol)

	# Goblin cards, 2 columns.
	var names := MetaState.colony_names()
	var card_w := (PANEL.x - 28 - 12) * 0.5
	var card_h := 56.0
	var top := BODY_TOP + 34
	for i in names.size():
		var who := String(names[i])
		var col := i % 2
		var row := i / 2
		var cx := 14 + col * (card_w + 12)
		var cy := top + row * (card_h + 8)
		var r := Rect2(cx, cy, card_w, card_h)
		var selected := _gi == i + 1
		draw_rect(r, Color(0.10, 0.12, 0.17))
		draw_rect(r, Color(0.55, 0.72, 1.0) if selected else Color(0.18, 0.22, 0.30), false, 2.0 if selected else 1.0)
		draw_string(_font, Vector2(cx + 10, cy + 18), who, HORIZONTAL_ALIGNMENT_LEFT, card_w - 20, 14, Color(0.93, 0.96, 1.0))
		var tool := _goblin_tool(who)
		draw_string(_font, Vector2(cx + 10, cy + 36), "%s (t%d)" % [MetaState.tool_name(tool), MetaState.goblin_tool_tier(who)], HORIZONTAL_ALIGNMENT_LEFT, card_w - 20, 12, Color(0.75, 0.85, 0.95))
		draw_string(_font, Vector2(cx + 10, cy + 51), "%d hauled" % _hauled_of(who), HORIZONTAL_ALIGNMENT_LEFT, card_w - 100, 11, Color(0.6, 0.66, 0.74))
		var tag := _tool_row_tag(who)
		draw_string(_font, Vector2(cx + card_w - 130, cy + 51), String(tag[0]), HORIZONTAL_ALIGNMENT_RIGHT, 122, 11, tag[1])

	# Memorial + tool pool.
	var by := PANEL.y - 54
	draw_line(Vector2(14, by - 8), Vector2(PANEL.x - 14, by - 8), Color(0.16, 0.18, 0.24), 1.0)
	draw_string(_font, Vector2(14, by + 6), "☠ Memorial: %s" % _memorial_line(), HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 28, 12, Color(0.7, 0.72, 0.78))
	draw_string(_font, Vector2(14, by + 22), "Tool pool: %s" % _pool_text(), HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 28, 12, Color(0.72, 0.82, 0.92))


# --- Tasks tab ---

func _draw_tasks() -> void:
	var td := MetaState.tech_data_on_hand()
	var list_x := 14.0
	var list_w := 320.0
	var rows := _quest_rows()
	_ti = clampi(_ti, 0, maxi(rows.size() - 1, 0))
	var y := BODY_TOP + 6
	for i in rows.size():
		var ry := y + i * ROW_H
		if i == _ti:
			draw_rect(Rect2(list_x - 2, ry - 1, list_w + 4, ROW_H), Color(1, 1, 1, 0.1))
		_draw_task_row(String(rows[i]), list_x, ry, list_w, td)

	# Right: the lair-restoration goal (the win condition).
	var gx := 350.0
	var gw := PANEL.x - gx - 14
	draw_line(Vector2(gx - 10, BODY_TOP), Vector2(gx - 10, PANEL.y - 36), Color(0.18, 0.2, 0.26), 1.0)
	draw_string(_font, Vector2(gx, BODY_TOP + 12), "RESTORE THE LAIR", HORIZONTAL_ALIGNMENT_LEFT, gw, 14, Color(0.7, 0.9, 1.0))
	var ny := BODY_TOP + 30
	for need: String in MetaState.LAIR_NEEDS:
		var amount := MetaState.need_amount(need)
		var frac := clampf(float(amount) / float(MetaState.NEED_MAX), 0.0, 1.0)
		draw_string(_font, Vector2(gx, ny), "%s  %d/%d" % [need.capitalize(), amount, MetaState.NEED_MAX], HORIZONTAL_ALIGNMENT_LEFT, gw, 12, Color(0.85, 0.88, 0.94))
		var bar := Rect2(gx, ny + 5, gw, 7)
		draw_rect(bar, Color(0.12, 0.13, 0.18))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), NEED_COLOR.get(need, Color(0.5, 0.7, 1.0)))
		ny += 30
	if MetaState.lair_restored():
		draw_string(_font, Vector2(gx, ny + 6), "BEACON READY — go home to win", HORIZONTAL_ALIGNMENT_LEFT, gw, 12, Color(0.6, 1.0, 0.7))
	else:
		draw_string(_font, Vector2(gx, ny + 6), "Ship components home to fill these.", HORIZONTAL_ALIGNMENT_LEFT, gw, 11, Color(0.6, 0.64, 0.72))


# --- Upgrades section ---

func _draw_upgrades() -> void:
	var td := MetaState.tech_data_on_hand()
	draw_string(_font, Vector2(14, BODY_TOP + 2), "Spend Tech Data on permanent upgrades (apply to this and every future run).", HORIZONTAL_ALIGNMENT_LEFT, PANEL.x - 28, 11, Color(0.62, 0.68, 0.78))
	var list_x := 14.0
	var list_w := PANEL.x - 28
	var rows := _upgrade_rows()
	_ui = clampi(_ui, 0, maxi(rows.size() - 1, 0))
	var visible_rows := 13
	var top_i := clampi(_ui - visible_rows / 2, 0, maxi(rows.size() - visible_rows, 0))
	var y := BODY_TOP + 18
	for i in range(top_i, mini(top_i + visible_rows, rows.size())):
		var ry := y + (i - top_i) * ROW_H
		if i == _ui:
			draw_rect(Rect2(list_x - 2, ry - 1, list_w + 4, ROW_H), Color(1, 1, 1, 0.1))
		_draw_task_row(String(rows[i]), list_x, ry, list_w, td)


func _draw_task_row(id: String, x: float, ry: float, w: float, td: int) -> void:
	var label := ""
	var right := ""
	var rcol := Color(0.6, 1.0, 0.7)
	if id.begins_with("q:"):
		var q := _quest_by_id(id.substr(2))
		var g: Dictionary = q.get("goal", {})
		var cur := MetaState.quest_current(g)
		var tgt := MetaState.quest_target(g)
		label = "✦ " + String(q.get("name", id))
		if MetaState.quest_claimed(String(q.get("id", ""))):
			right = "claimed"
			rcol = Color(0.55, 0.6, 0.66)
		elif cur >= tgt:
			right = "CLAIM +%d" % int(q.get("reward", {}).get("tech_data", 0))
			rcol = Color(0.6, 1.0, 0.7)
		else:
			right = "%d/%d" % [cur, tgt]
			rcol = Color(0.72, 0.8, 0.9)
		draw_string(_font, Vector2(x + 4, ry + 15), label, HORIZONTAL_ALIGNMENT_LEFT, w - 90, 12, Color(0.86, 0.9, 0.78))
		draw_string(_font, Vector2(x + w - 86, ry + 15), right, HORIZONTAL_ALIGNMENT_RIGHT, 82, 12, rcol)
		return
	if id == "__cargo":
		label = "▢ Expand the cargo hold (+1 row)"
		if not MetaState.can_expand_cargo():
			right = "MAX"; rcol = Color(0.6, 0.85, 0.6)
		else:
			var ec := MetaState.expand_cargo_cost()
			right = _cost_text(ec)
			rcol = Color(0.6, 1.0, 0.7) if RunState.can_afford(ec) else Color(0.9, 0.6, 0.55)
	elif id.begins_with("tech:"):
		var tid := id.substr(5)
		label = "⚛ " + _tech_name(tid)
		if MetaState.has_tech(tid):
			right = "owned"; rcol = Color(0.6, 0.85, 0.6)
		else:
			var tc := int(GameData.tech.get(tid, {}).get("cost", 0))
			right = "%d TD" % tc
			rcol = Color(0.6, 1.0, 0.7) if td >= tc else Color(0.9, 0.6, 0.55)
	else:
		label = "⚙ %s  Lv %d" % [_name(id), MetaState.machine_level(id)]
		if not MetaState.can_upgrade_machine(id):
			right = "MAX"; rcol = Color(0.6, 0.85, 0.6)
		else:
			var mc := MetaState.machine_upgrade_cost(id)
			right = _cost_text(mc)
			rcol = Color(0.6, 1.0, 0.7) if RunState.can_afford(mc) else Color(0.9, 0.6, 0.55)
	draw_string(_font, Vector2(x + 4, ry + 15), label, HORIZONTAL_ALIGNMENT_LEFT, w - 160, 12, Color(0.9, 0.9, 0.95))
	draw_string(_font, Vector2(x + w - 156, ry + 15), right, HORIZONTAL_ALIGNMENT_RIGHT, 152, 12, rcol)


# ---------------------------------------------------------------- helpers ----

func _tool_row_tag(who: String) -> Array:
	var current := MetaState.goblin_tool_tier(who)
	var best := MetaState.best_available_tool()
	if best != "" and MetaState.tool_tier(best) > current:
		return ["equip %s" % MetaState.tool_name(best), Color(0.6, 1.0, 0.7)]
	var cost := MetaState.upgrade_tool_cost(who)
	if cost.is_empty():
		if current >= 4:
			return ["MAX", Color(0.6, 0.85, 0.6)]
		return ["locked (tech)", Color(0.75, 0.7, 0.55)]  # next tier needs a toolsmithing unlock
	var mat := String(cost.keys()[0])
	var tag := "%d %s" % [int(cost[mat]), GameData.resource_name(mat)]
	return [tag, Color(0.6, 1.0, 0.7) if RunState.can_afford(cost) else Color(0.9, 0.6, 0.55)]


func _cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for res: String in cost:
		parts.append("%d %s" % [int(cost[res]), GameData.resource_name(res)])
	return ", ".join(parts)


func _goblin_tool(gob_name: String) -> String:
	for g: Dictionary in MetaState.roster:
		if String(g.get("name", "")) == gob_name:
			return String(g.get("tool", MetaState.STARTER_TOOL))
	return MetaState.STARTER_TOOL


func _hauled_of(gob_name: String) -> int:
	for g: Dictionary in MetaState.roster:
		if String(g.get("name", "")) == gob_name:
			return int(g.get("hauled", 0))
	return 0


func _pool_text() -> String:
	if MetaState.tools_found.is_empty():
		return "(empty — find tools out in runs)"
	var names: Array = []
	for id: String in MetaState.tools_found:
		names.append(MetaState.tool_name(id))
	return ", ".join(names)


func _memorial_line() -> String:
	if MetaState.fallen.is_empty():
		return "(none lost)"
	var parts: Array = []
	for g: Dictionary in MetaState.fallen:
		parts.append(String(g.get("name", "?")))
	return ", ".join(parts)


func _tech_name(tid: String) -> String:
	return String(GameData.tech.get(tid, {}).get("name", tid))


func _name(id: String) -> String:
	return String(GameData.machines.get(id, {}).get("name", id))
