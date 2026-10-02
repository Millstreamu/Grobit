class_name ExchangePanel
extends Control
## Component Exchange screen. Sell the finished components in your inventory for credit;
## each full MACHINE_COST of credit grants a random production machine into your stock
## (placeable from the inventory for free). Credit is per-run (RunState.exchange_credit).
## Pauses the world while open.

const PANEL := Rect2(Vector2(120, 70), Vector2(400, 300))
const ROW_H := 30.0

## Credit needed to earn one random machine.
const MACHINE_COST := 3

## Components the exchange buys, and the credit each is worth.
const COMPONENT_VALUES := {
	"power_coupling": 1,
	"control_assembly": 1,
	"reinforced_frame": 1,
	"thermal_core": 1,
}

## Machines a sale can roll (the new-economy production machines).
const MACHINE_POOL := [
	"copper_recycler", "steel_recycler", "plastic_recycler", "ceramic_recycler",
	"copper_ammo_maker", "steel_ammo_maker", "plastic_ammo_maker", "ceramic_ammo_maker",
	"coupling_maker", "control_maker", "frame_maker", "thermal_maker",
]

var _message := ""
var _opened_frame := -1
var _font: Font
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2.ZERO
	size = Vector2(640, 448)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = ThemeDB.fallback_font
	_rng.randomize()


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
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


func _handle_input() -> void:
	if Input.is_action_just_pressed("build_cancel"):
		close()
		return
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("confirm"):
		_sell_all()


## Consumes every held component for credit, then grants a random machine for each full
## MACHINE_COST the credit reaches.
func _sell_all() -> void:
	var sold := 0
	var gained := 0
	for id: String in COMPONENT_VALUES:
		var have := RunState.get_quantity(id)
		if have <= 0:
			continue
		RunState.add(id, -have)
		sold += have
		gained += have * int(COMPONENT_VALUES[id])
	if sold == 0:
		_message = "No components to sell."
		return
	RunState.exchange_credit += gained
	var granted: Array = []
	while RunState.exchange_credit >= MACHINE_COST and not MACHINE_POOL.is_empty():
		RunState.exchange_credit -= MACHINE_COST
		var mid := String(MACHINE_POOL[_rng.randi_range(0, MACHINE_POOL.size() - 1)])
		RunState.add_to_stock(mid)
		granted.append(GameData.machines.get(mid, {}).get("name", mid))
	_message = "Sold %d component%s (+%d credit)." % [sold, "" if sold == 1 else "s", gained]
	if not granted.is_empty():
		_message += "  Received: %s!" % ", ".join(granted)
		_notify("Component Exchange: received %s (place it from your inventory)." % ", ".join(granted))


func _notify(text: String) -> void:
	for hud: Node in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("log_message"):
			hud.log_message(text)
			return


func _draw() -> void:
	draw_rect(PANEL, Color(0.06, 0.06, 0.11, 0.97))
	var p := PANEL.position
	draw_string(_font, p + Vector2(14, 28), "COMPONENT EXCHANGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.85, 0.5))

	# Credit bar: progress toward the next random machine.
	var frac := clampf(float(RunState.exchange_credit) / float(MACHINE_COST), 0.0, 1.0)
	var bar := Rect2(p + Vector2(14, 44), Vector2(PANEL.size.x - 28, 16))
	draw_rect(bar, Color(0.12, 0.13, 0.18))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color(0.9, 0.7, 0.3))
	draw_rect(bar, Color(0.5, 0.45, 0.3, 0.7), false, 1.0)
	draw_string(_font, p + Vector2(18, 57), "Credit %d / %d  →  random machine" % [RunState.exchange_credit, MACHINE_COST], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.9, 0.95))

	# Components you currently hold.
	draw_string(_font, p + Vector2(14, 84), "Your components:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.82, 0.86))
	var total := 0
	var i := 0
	for id: String in COMPONENT_VALUES:
		var have := RunState.get_quantity(id)
		total += have
		var row := p + Vector2(22, 104 + i * ROW_H)
		var def: Dictionary = GameData.resources.get(id, {})
		var tex := ContentLibrary.get_icon(String(def.get("icon", id)), Vector2i(20, 20), String(def.get("color", "")))
		draw_texture_rect(tex, Rect2(row, Vector2(22, 22)), false)
		var col := Color(0.92, 0.92, 0.96) if have > 0 else Color(0.5, 0.5, 0.55)
		draw_string(_font, row + Vector2(30, 17), "%s  ×%d   (%d credit each)" % [GameData.resource_name(id), have, int(COMPONENT_VALUES[id])], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		i += 1
	if total == 0:
		draw_string(_font, p + Vector2(22, 104 + i * ROW_H + 6), "Build components at a Component Maker, then sell them here.", HORIZONTAL_ALIGNMENT_LEFT, PANEL.size.x - 40, 11, Color(0.7, 0.6, 0.6))

	draw_string(_font, p + Vector2(14, PANEL.size.y - 14), "[Space] sell all   [Esc] close", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.75))
	if _message != "":
		draw_string(_font, p + Vector2(14, PANEL.size.y - 32), _message, HORIZONTAL_ALIGNMENT_LEFT, PANEL.size.x - 28, 12, Color(1, 0.9, 0.7))
