extends Control
## Phase 6 — the TITLE / main menu (the game's main scene). Keyboard-driven to match the in-game
## panels: [W/S] move, [Space]/[Enter] pick, [Esc] cancels a pending confirm. Play continues the
## persistent save (RunState/MetaState are autoloads that survive the scene change); New Game wipes it
## (two-step confirm); Debug Lair boots a pre-stocked test lair.

const TITLE := "GROBIT"
const PREMISE := "Salvage the ruins, keep your goblins alive, rebuild the lair."
const OPTIONS := ["Play", "New Game", "Debug Lair", "Quit"]

var _sel := 0
var _confirm_new := false
var _opened_frame := -1
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_opened_frame = Engine.get_process_frames()
	queue_redraw()


func _process(_delta: float) -> void:
	if Engine.get_process_frames() == _opened_frame:
		return  # swallow the keypress that got us here
	if Input.is_action_just_pressed("move_up"):
		_sel = (_sel - 1 + OPTIONS.size()) % OPTIONS.size()
		_confirm_new = false
		queue_redraw()
	if Input.is_action_just_pressed("move_down"):
		_sel = (_sel + 1) % OPTIONS.size()
		_confirm_new = false
		queue_redraw()
	if Input.is_action_just_pressed("build_cancel"):
		_confirm_new = false
		queue_redraw()
	if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("attack"):
		_activate()


func _activate() -> void:
	match OPTIONS[_sel]:
		"Play":
			_start()
		"New Game":
			if _confirm_new:
				MetaState.reset_new_game()
				_start()
			else:
				_confirm_new = true
				queue_redraw()
		"Debug Lair":
			MetaState.start_debug_lair()
			_start()
		"Quit":
			get_tree().quit()


func _start() -> void:
	get_tree().change_scene_to_file("res://scenes/world/run.tscn")


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.04, 0.05, 0.08))
	var cx := vp.x
	draw_string(_font, Vector2(0, vp.y * 0.28), TITLE, HORIZONTAL_ALIGNMENT_CENTER, cx, 54, Color(0.6, 0.85, 1.0))
	draw_string(_font, Vector2(0, vp.y * 0.28 + 34), PREMISE, HORIZONTAL_ALIGNMENT_CENTER, cx, 15, Color(0.72, 0.78, 0.88))

	var oy := vp.y * 0.56
	for i in OPTIONS.size():
		var y := oy + i * 32.0
		var selected := i == _sel
		var label := String(OPTIONS[i])
		var col := Color(0.95, 0.98, 1.0) if selected else Color(0.6, 0.63, 0.7)
		if selected:
			var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			draw_string(_font, Vector2(0, y), "›", HORIZONTAL_ALIGNMENT_CENTER, cx - w - 24, 20, Color(0.5, 0.8, 1.0))
		draw_string(_font, Vector2(0, y), label, HORIZONTAL_ALIGNMENT_CENTER, cx, 20, col)

	if _confirm_new:
		draw_string(_font, Vector2(0, oy + OPTIONS.size() * 32.0 + 16), "New Game wipes your save — press again to confirm.", HORIZONTAL_ALIGNMENT_CENTER, cx, 13, Color(1.0, 0.65, 0.55))
	draw_string(_font, Vector2(0, vp.y - 24), "[W/S] move   [Space] select   [Esc] cancel", HORIZONTAL_ALIGNMENT_CENTER, cx, 12, Color(0.5, 0.53, 0.6))
