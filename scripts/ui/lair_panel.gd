class_name LairPanel
extends Control
## The LAIR WINDOW — opened by interacting with the System Terminal at base. The single hub for
## running the colony between runs. Three tabs:
##   • PRODUCTION — the workshop floor (an embedded FactoryPanel): lay out and run the refiners
##     and component makers. Refining only happens here at the lair.
##   • GOBLINS   — the colony roster: recruit, equip found tools / upgrade a goblin's tool, and
##     the memorial for the fallen.
##   • TASKS     — colony quests (claim rewards), permanent Upgrades & tech (spend Tech Data), and
##     the lair-restoration goal (oxygen/power/water/food → the beacon = the win).
## Pauses the world while open. Tech Data is a grid inventory item, spent from the run inventory.

const PANEL := Vector2(640, 448)
const BODY_TOP := 92.0
const ROW_H := 22.0

## Machine types you can permanently upgrade (mirrors the old terminal list).
const UPGRADABLE := [
	"copper_recycler", "steel_recycler", "plastic_recycler", "ceramic_recycler",
	"copper_ammo_maker", "steel_ammo_maker", "plastic_ammo_maker", "ceramic_ammo_maker",
	"coupling_maker", "control_maker", "frame_maker", "thermal_maker",
	"copper_weapon", "steel_weapon", "plastic_weapon", "ceramic_weapon",
]

const NEED_COLOR := {
	"oxygen": Color(0.45, 0.85, 1.0),
	"power": Color(0.95, 0.8, 0.35),
	"water": Color(0.45, 0.65, 1.0),
	"food": Color(0.55, 0.9, 0.55),
}

enum { TAB_PROD, TAB_GOB, TAB_TASK, TAB_UPG }
const TAB_NAMES := ["Production", "Goblins", "Tasks", "Upgrades"]

var _tab := TAB_PROD
var _gi := 0          # selected row on the Goblins tab (0 = recruit, then one per goblin)
var _ti := 0          # selected quest on the Tasks tab
var _ui := 0          # selected row on the Upgrades tab
var _message := ""
var _opened_frame := -1
var _font: Font
var _workshop: FactoryPanel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2.ZERO
	size = PANEL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = ThemeDB.fallback_font
	# The embedded workshop renders the Production tab. It lives as our child so it draws on top
	# of our header (its grid sits below the tab strip), sharing RunState.factory with the game.
	_workshop = FactoryPanel.new()
	_workshop.embedded = true
	add_child(_workshop)
	_workshop.visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	_tab = TAB_PROD
	_gi = 0
	_ti = 0
	_message = ""
	_opened_frame = Engine.get_process_frames()
	visible = true
	get_tree().paused = true
	_workshop.open()               # resets its state; embedded → doesn't pause
	_enter_tab(TAB_PROD)
	queue_redraw()


func close() -> void:
	_workshop.visible = false
	visible = false
	get_tree().paused = false


func _enter_tab(tab: int) -> void:
	_tab = tab
	_message = ""
	if tab == TAB_PROD:
		_workshop.visible = true
		_workshop.embedded_refresh()
	else:
		_workshop.visible = false


func _cycle_tab() -> void:
	_enter_tab((_tab + 1) % TAB_NAMES.size())


func _process(delta: float) -> void:
	if not visible:
		return
	if Engine.get_process_frames() == _opened_frame:
		return  # swallow the keypress that opened us
	var on_prod := _tab == TAB_PROD
	var top_level := (not on_prod) or _workshop.at_top_level()
	# [Tab] cycles tabs and [Esc] closes — but only when the workshop isn't mid-placement, so a
	# sub-mode's own [Esc]/[Tab] handling still works on the Production tab.
	if top_level and Input.is_action_just_pressed("cycle_target"):
		_cycle_tab()
		queue_redraw()
		return
	if top_level and Input.is_action_just_pressed("build_cancel"):
		close()
		return
	if on_prod:
		_workshop.embedded_tick(delta)   # the workshop drives its own grid input + redraw
	else:
		_handle_list_input()
		queue_redraw()


# ------------------------------------------------------------------ input ----

func _handle_list_input() -> void:
	if _tab == TAB_GOB:
		_handle_goblins_input()
	elif _tab == TAB_TASK:
		_handle_tasks_input()
	else:
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
			_message = "Unlock %s toolsmithing (Tech Data) before upgrading past tier %d." % [MetaState.TIER_MATERIAL[current], current]
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
	match _tab:
		TAB_PROD:
			pass  # the embedded workshop (our child) paints the Production tab itself
		TAB_GOB:
			_draw_goblins()
			_draw_footer("[WASD] pick   [Space] recruit / improve tool   [Tab] switch tab   [Esc] close")
		TAB_TASK:
			_draw_tasks()
			_draw_footer("[W/S] pick   [Space] claim reward   [Tab] switch tab   [Esc] close")
		TAB_UPG:
			_draw_upgrades()
			_draw_footer("[W/S] pick   [Space] buy upgrade   [Tab] switch tab   [Esc] close")


func _draw_header() -> void:
	draw_string(_font, Vector2(14, 28), "SYSTEM TERMINAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.55, 0.8, 1.0))
	# Shared counters, right-aligned (Food = recruiting, Tech Data = unlocks).
	var td := MetaState.tech_data_on_hand()
	var food := RunState.get_quantity("food")
	var counters := "Food %d    Tech Data %d    Colony %d/%d    Lost %d" % [food, td, MetaState.colony_size(), MetaState.COLONY_MAX, MetaState.fallen.size()]
	draw_string(_font, Vector2(PANEL.x - 430, 26), counters, HORIZONTAL_ALIGNMENT_RIGHT, 416, 13, Color(0.82, 0.88, 0.96))
	# Tab strip (laid out left-to-right by label width so 4 tabs fit cleanly).
	var tx := 20.0
	for i in TAB_NAMES.size():
		var active := i == _tab
		var col := Color(0.6, 0.82, 1.0) if active else Color(0.55, 0.58, 0.66)
		draw_string(_font, Vector2(tx, 70), TAB_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
		var w := _font.get_string_size(TAB_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		if active:
			draw_line(Vector2(tx, 76), Vector2(tx + w, 76), Color(0.35, 0.6, 0.9), 2.0)
		tx += w + 34.0
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


# --- Upgrades tab ---

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
