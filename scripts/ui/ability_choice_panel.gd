class_name AbilityChoicePanel
extends Control
## Run-start screen to choose your one active ability (triggered with Space during
## the run). Keyboard: ←/→ or A/D to select, Space to confirm. Pauses until chosen.
## Structured to also serve future "improve or switch your ability" moments.

const PANEL_SIZE := Vector2(640, 448)
const CARD := Vector2(180, 150)
const GAP := 16.0

var _cursor := 0
var _ids: Array = []
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2.ZERO
	size = PANEL_SIZE
	visible = false
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	if not visible:
		return
	if Input.is_action_just_pressed("move_left"):
		_cursor = maxi(_cursor - 1, 0)
	if Input.is_action_just_pressed("move_right"):
		_cursor = mini(_cursor + 1, _ids.size() - 1)
	if Input.is_action_just_pressed("attack"):
		_confirm()
	queue_redraw()


func is_open() -> bool:
	return visible


func open() -> void:
	_ids = RunState.available_abilities.duplicate()
	if _ids.is_empty():
		return
	_cursor = 0
	visible = true
	get_tree().paused = true
	queue_redraw()


func _confirm() -> void:
	if _cursor < 0 or _cursor >= _ids.size():
		return
	var ability_id := String(_ids[_cursor])
	RunState.equipped_ability = ability_id
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_node("Abilities"):
		(player.get_node("Abilities") as GrobitAbilities).equip(ability_id)
	visible = false
	get_tree().paused = false


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, PANEL_SIZE), Color(0.06, 0.06, 0.09, 1.0))
	draw_string(_font, Vector2(24, 54), "CHOOSE YOUR ABILITY", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.9, 0.95))

	var total := _ids.size() * CARD.x + maxf(0, _ids.size() - 1) * GAP
	var origin := Vector2((PANEL_SIZE.x - total) * 0.5, 120)
	for i in _ids.size():
		var def: Dictionary = GameData.abilities.get(String(_ids[i]), {})
		var pos := origin + Vector2(i * (CARD.x + GAP), 0)
		var rect := Rect2(pos, CARD)
		draw_rect(rect, Color(0.18, 0.18, 0.24) if i == _cursor else Color(0.13, 0.13, 0.17))
		draw_string(_font, pos + Vector2(12, 30), String(def.get("name", _ids[i])), HORIZONTAL_ALIGNMENT_LEFT, CARD.x - 20, 18, Color(1, 0.95, 0.7))
		draw_multiline_string(_font, pos + Vector2(12, 56), String(def.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT, CARD.x - 20, 14, 4, Color(0.85, 0.85, 0.9))
		draw_string(_font, pos + Vector2(12, CARD.y - 14), "cooldown %.0fs" % float(def.get("cooldown", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, CARD.x - 20, 12, Color(0.7, 0.7, 0.75))
		if i == _cursor:
			draw_rect(rect.grow(2), Color.WHITE, false, 2.0)

	draw_string(_font, Vector2(24, PANEL_SIZE.y - 24), "[A/D] select     [Space] confirm", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.7, 0.75))
