class_name ScrapMinigame
extends Control
## Real-time scrapping minigame overlay (Step 3 — see docs/SLICE_1_SCOPE.md). Shows
## a node's 4 slots, its token count, and rust/loose state. The world keeps running
## while this is open (the player is locked in place but still auto-shoots, so
## harvesting is an exposed commitment). Each action spends one token; harvested
## items drop into the scrapper arm's holding cells in the inventory-factory.
##
## A centred panel (not full-screen) so danger stays visible around the edges.

const PANEL := Rect2(Vector2(100, 116), Vector2(440, 216))
const SLOT := Vector2(92, 92)
const GAP := 12.0

var _node: ScrapNode
var _player: GrobitPlayer
var _cursor := 0
var _message := ""
var _opened_frame := -1
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT  # runs while the world runs (not paused)
	position = Vector2.ZERO
	size = Vector2(640, 448)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = ThemeDB.fallback_font


func setup(player: GrobitPlayer) -> void:
	_player = player


func is_open() -> bool:
	return visible


func open(node: ScrapNode) -> void:
	if visible:
		return
	_node = node
	_cursor = 0
	_message = ""
	_opened_frame = Engine.get_process_frames()
	visible = true
	if _player != null:
		_player.set_input_locked(true)
	queue_redraw()


func close() -> void:
	visible = false
	_node = null
	if _player != null and (_player.health == null or not _player.health.is_dead()):
		_player.set_input_locked(false)


func _process(_delta: float) -> void:
	if not visible:
		return
	# Safety: the node was depleted/removed, or the player died — bail out.
	if not is_instance_valid(_node) or _node.is_spent():
		close()
		return
	if _player != null and _player.health != null and _player.health.is_dead():
		close()
		return
	# Ignore input on the frame we opened: the F (interact) press that opened us is
	# still "just pressed" this frame, and reading it here would close immediately.
	if Engine.get_process_frames() != _opened_frame:
		_handle_input()
	queue_redraw()


func _handle_input() -> void:
	# Leave on Esc only. F is reserved for opening (SelectionManager re-fires interact
	# each frame F is held/pressed, so closing on F would instantly reopen us).
	if Input.is_action_just_pressed("build_cancel"):
		close()
		return
	if Input.is_action_just_pressed("move_left"):
		_cursor = maxi(_cursor - 1, 0)
	if Input.is_action_just_pressed("move_right"):
		_cursor = mini(_cursor + 1, ScrapNode.SLOT_COUNT - 1)
	if Input.is_action_just_pressed("attack"):
		_act()


func _act() -> void:
	var result := _node.hit_slot(_cursor)
	match result:
		"rust": _message = "Cracked rust."
		"empty": _message = "Nothing there."
		"arm_full": _message = "Arm full — clear a holding slot."
		"spent": _message = "Node is spent."
		_: _message = "+ %s" % GameData.resource_name(result)
	if _node.is_spent():
		var spent := _node
		close()
		if is_instance_valid(spent):
			spent.queue_free()


func _draw() -> void:
	if not is_instance_valid(_node):
		return
	# Dim only behind the panel, so the surrounding world/danger stays visible.
	draw_rect(PANEL.grow(8), Color(0, 0, 0, 0.55))
	draw_rect(PANEL, Color(0.07, 0.07, 0.10, 0.96))

	var header := "SCRAPPING: %s     tokens %d" % [_node.harvest_label, _node.tokens]
	draw_string(_font, PANEL.position + Vector2(14, 26), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.9, 0.95))
	if _node.loose:
		draw_string(_font, PANEL.position + Vector2(PANEL.size.x - 150, 26), "LOOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.8, 0.4))

	var row_w := ScrapNode.SLOT_COUNT * SLOT.x + (ScrapNode.SLOT_COUNT - 1) * GAP
	var origin := PANEL.position + Vector2((PANEL.size.x - row_w) * 0.5, 44)
	for i in ScrapNode.SLOT_COUNT:
		_draw_slot(i, Rect2(origin + Vector2(i * (SLOT.x + GAP), 0), SLOT))

	var space := RunState.factory.harvest_space() if RunState.factory != null else 0
	draw_string(_font, PANEL.position + Vector2(14, PANEL.size.y - 44), "Arm holding space: %d" % space, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.85, 0.9))
	if _message != "":
		draw_string(_font, PANEL.position + Vector2(180, PANEL.size.y - 44), _message, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.7))
	draw_string(_font, PANEL.position + Vector2(14, PANEL.size.y - 16), "[A/D] select   [Space] hit   [Esc] leave (node keeps its tokens)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.7, 0.75))


func _draw_slot(index: int, rect: Rect2) -> void:
	var state := _node.slot_state(index)
	var rusted := int(state.get("rust", 0)) > 0
	var id := String(state.get("id", ""))

	draw_rect(rect, Color(0.20, 0.14, 0.10) if rusted else Color(0.13, 0.14, 0.17))

	if rusted:
		draw_string(_font, rect.position + Vector2(10, 40), "RUSTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.6, 0.4))
		draw_string(_font, rect.position + Vector2(10, 64), "%d hit(s)" % int(state.rust), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.6, 0.45))
	elif id != "":
		var tex := ContentLibrary.get_icon(GameData.resource_icon(id), Vector2i(20, 20), GameData.resource_color(id))
		draw_texture_rect(tex, Rect2(rect.position + Vector2((SLOT.x - 32) * 0.5, 12), Vector2(32, 32)), false)
		draw_string(_font, rect.position + Vector2(6, SLOT.y - 12), GameData.resource_name(id), HORIZONTAL_ALIGNMENT_CENTER, SLOT.x - 12, 12, Color(0.9, 0.9, 0.95))
	else:
		draw_string(_font, rect.position + Vector2(0, 50), "— empty —", HORIZONTAL_ALIGNMENT_CENTER, SLOT.x, 13, Color(0.5, 0.5, 0.55))

	draw_string(_font, rect.position + Vector2(6, 16), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.6, 0.65))
	if index == _cursor:
		draw_rect(rect.grow(2), Color.WHITE, false, 2.0)
