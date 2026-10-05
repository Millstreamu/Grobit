class_name TerminalPanel
extends Control
## System Terminal screen — your link to the goblin base. Here you UPLOAD the Tech Data you
## earned this run (scrapping machines) so it banks permanently, and SPEND banked Tech Data
## on PERMANENT machine upgrades (faster processing, higher recipe gate; applies to every
## machine of that type, now and in future runs). Pauses the world while open.

const PANEL := Rect2(Vector2(96, 44), Vector2(448, 360))
const ROW_H := 20.0

## Machine types you can permanently upgrade.
const UPGRADABLE := [
	"scrapper_arm",  # each level unlocks the next scrap tier: L1 steel, L2 copper, L3 plastic, L4 ceramic
	"copper_recycler", "steel_recycler", "plastic_recycler", "ceramic_recycler",
	"copper_ammo_maker", "steel_ammo_maker", "plastic_ammo_maker", "ceramic_ammo_maker",
	"coupling_maker", "control_maker", "frame_maker", "thermal_maker",
	"copper_weapon", "steel_weapon", "plastic_weapon", "ceramic_weapon",
]

## Leveling the Scrapper Arm unlocks the next scrap tier, and each level demands a BRIDGE
## COMPONENT (crafted from the prior tiers' materials) consumed from the factory, on top of the
## Tech Data cost — the hybrid climb. The arm tops out at tier 4 (ceramic).
const ARM_GATE_COMPONENT := {2: "reinforced_frame", 3: "power_coupling", 4: "thermal_core"}
const ARM_MAX_LEVEL := 4

var _index := 0
var _message := ""
var _opened_frame := -1
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2.ZERO
	size = Vector2(640, 448)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = ThemeDB.fallback_font


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	_index = 0
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
	if Engine.get_process_frames() != _opened_frame:
		_handle_input()
	queue_redraw()


# Row 0 is "upload"; rows 1.. are the upgradable machines.
func _rows() -> Array:
	return ["__upload"] + UPGRADABLE


func _handle_input() -> void:
	if Input.is_action_just_pressed("build_cancel"):
		close()
		return
	var rows := _rows()
	if Input.is_action_just_pressed("move_up"):
		_index = maxi(_index - 1, 0)
	if Input.is_action_just_pressed("move_down"):
		_index = mini(_index + 1, rows.size() - 1)
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("confirm"):
		_activate(String(rows[_index]))


func _activate(id: String) -> void:
	if id == "__upload":
		var n := RunState.currency_count("tech_data")
		if n <= 0:
			_message = "No tech data to upload — scrap some machines first."
			return
		RunState.add("tech_data", -n)  # take it out of the run
		MetaState.add_tech_data(n)     # bank it permanently
		_message = "Uploaded %d Tech Data to the base." % n
		return
	if id == "scrapper_arm":
		_upgrade_arm()
		return
	# A machine upgrade.
	if not MetaState.can_upgrade_machine(id):
		_message = "%s is already at max level." % _name(id)
		return
	var cost := MetaState.machine_upgrade_cost(id)
	if MetaState.tech_data < cost:
		_message = "Need %d banked Tech Data (you have %d). Upload more." % [cost, MetaState.tech_data]
		return
	MetaState.upgrade_machine(id)
	_message = "%s permanently upgraded → Lv %d." % [_name(id), MetaState.machine_level(id)]


## Climbs the Scrapper Arm one tier: spend Tech Data AND consume the tier's bridge component
## from the factory. Caps at tier 4 (ceramic).
func _upgrade_arm() -> void:
	var lvl := MetaState.machine_level("scrapper_arm")
	if lvl >= ARM_MAX_LEVEL:
		_message = "Scrapper Arm is at max tier (ceramic)."
		return
	var next_level := lvl + 1
	var comp := String(ARM_GATE_COMPONENT.get(next_level, ""))
	if comp != "" and int(RunState.get_quantity(comp)) < 1:
		_message = "Need 1 %s in the factory to reach tier %d." % [GameData.resource_name(comp), next_level]
		return
	var cost := MetaState.machine_upgrade_cost("scrapper_arm")
	if MetaState.tech_data < cost:
		_message = "Need %d banked Tech Data (you have %d). Upload more." % [cost, MetaState.tech_data]
		return
	MetaState.upgrade_machine("scrapper_arm")   # spends the Tech Data, +1 level
	if comp != "":
		RunState.add(comp, -1)                  # consume the bridge component from the grid
	_message = "Scrapper Arm → tier %d: %s unlocked." % [next_level, _arm_tier_material(next_level)]


## The scrap material a given arm tier unlocks (tier 2 = copper … 4 = ceramic).
func _arm_tier_material(tier: int) -> String:
	var scraps: Array = FactoryGrid.ARM_SLOT_TYPES
	if tier >= 1 and tier <= scraps.size():
		return GameData.resource_name(String(scraps[tier - 1]).trim_suffix("_scrap"))
	return "a new material"


func _name(id: String) -> String:
	return String(GameData.machines.get(id, {}).get("name", id))


## A short label for the bridge component on the arm's upgrade row.
func _short(id: String) -> String:
	match id:
		"reinforced_frame": return "Frame"
		"power_coupling": return "Coupling"
		"thermal_core": return "Core"
	return GameData.resource_name(id)


func _draw() -> void:
	draw_rect(PANEL, Color(0.06, 0.07, 0.12, 0.97))
	var p := PANEL.position
	draw_string(_font, p + Vector2(14, 26), "SYSTEM TERMINAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.55, 0.8, 1.0))
	draw_string(_font, p + Vector2(14, 46), "Tech Data this run: %d      Banked at base: %d" % [RunState.currency_count("tech_data"), MetaState.tech_data], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.9, 0.95))

	var rows := _rows()
	var visible_rows := 13
	var top := clampi(_index - visible_rows / 2, 0, maxi(rows.size() - visible_rows, 0))
	var list_y := p.y + 66
	for i in range(top, mini(top + visible_rows, rows.size())):
		var id: String = rows[i]
		var ry := list_y + (i - top) * ROW_H
		if i == _index:
			draw_rect(Rect2(p.x + 10, ry - 1, PANEL.size.x - 20, ROW_H), Color(1, 1, 1, 0.1))
		if id == "__upload":
			draw_string(_font, Vector2(p.x + 16, ry + 14), "▲ Upload this run's Tech Data to the base", HORIZONTAL_ALIGNMENT_LEFT, PANEL.size.x - 32, 13, Color(0.7, 1.0, 0.8))
		else:
			var lvl := MetaState.machine_level(id)
			var tex := ContentLibrary.get_icon(String(GameData.machines.get(id, {}).get("icon", id)), Vector2i(14, 14), String(GameData.machines.get(id, {}).get("color", "")))
			draw_texture_rect(tex, Rect2(p.x + 16, ry + 1, 14, 14), false)
			draw_string(_font, Vector2(p.x + 36, ry + 14), "%s   Lv %d" % [_name(id), lvl], HORIZONTAL_ALIGNMENT_LEFT, PANEL.size.x - 150, 13, Color(0.92, 0.92, 0.96))
			var right: String
			var col: Color
			if id == "scrapper_arm":
				if lvl >= ARM_MAX_LEVEL:
					right = "MAX"
					col = Color(0.6, 0.85, 0.6)
				else:
					var comp := String(ARM_GATE_COMPONENT.get(lvl + 1, ""))
					var td := MetaState.machine_upgrade_cost("scrapper_arm")
					var have := comp == "" or int(RunState.get_quantity(comp)) >= 1
					right = "%dTD +%s" % [td, _short(comp)]
					col = Color(0.6, 1.0, 0.7) if (MetaState.tech_data >= td and have) else Color(0.9, 0.6, 0.55)
			elif not MetaState.can_upgrade_machine(id):
				right = "MAX"
				col = Color(0.6, 0.85, 0.6)
			else:
				var cost := MetaState.machine_upgrade_cost(id)
				right = "%d TD" % cost
				col = Color(0.6, 1.0, 0.7) if MetaState.tech_data >= cost else Color(0.9, 0.6, 0.55)
			draw_string(_font, Vector2(p.x + PANEL.size.x - 118, ry + 14), right, HORIZONTAL_ALIGNMENT_LEFT, 112, 12, col)

	draw_string(_font, p + Vector2(14, PANEL.size.y - 12), "[W/S] pick   [Space] upload / upgrade   [Esc] close", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.75))
	if _message != "":
		draw_string(_font, p + Vector2(14, PANEL.size.y - 30), _message, HORIZONTAL_ALIGNMENT_LEFT, PANEL.size.x - 28, 12, Color(1, 0.9, 0.7))
