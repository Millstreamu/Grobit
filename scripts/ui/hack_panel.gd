class_name HackPanel
extends Control
## The door-hack minigame window (Phase 2.3). Drives a HackSession and draws its two stages:
##   SWITCHES — flip the row to match the lit target, then confirm.
##   TIMING   — stop the sweeping marker inside the green arc of a circular dial.
##   CHOICE   — cracked! the room alarm (Heat on open) is shown — OPEN or SKIP.
## Outcome is applied to the door: open (+alarm Heat) / skip (nothing) / FAIL (Heat spike + lock) /
## cancel (free). Pauses the world while open. Controller-first (d-pad + one confirm button).

const SCREEN := Vector2(640, 448)
const PANEL := Vector2(440, 320)

var _font: Font
var _session: HackSession
var _door: Node
var _choice := 0            # CHOICE stage: 0 = Open, 1 = Skip
var _opened_frame := -1
var _resolved := false
var _outcome := ""
var _outcome_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2.ZERO
	size = SCREEN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = ThemeDB.fallback_font


func is_open() -> bool:
	return visible


func open(door: Node) -> void:
	if visible:
		return
	_door = door
	var diff := int(door.get("difficulty")) if door.get("difficulty") != null else 1
	var alarm := float(door.get("alarm")) if door.get("alarm") != null else 15.0
	_session = HackSession.new(diff, alarm)
	_choice = 0
	_resolved = false
	_outcome = ""
	_outcome_t = 0.0
	_opened_frame = Engine.get_process_frames()
	visible = true
	get_tree().paused = true
	queue_redraw()


func close() -> void:
	visible = false
	get_tree().paused = false


func _process(delta: float) -> void:
	if not visible:
		return
	if _resolved:
		_outcome_t -= delta
		if _outcome_t <= 0.0:
			close()
		queue_redraw()
		return
	if Engine.get_process_frames() != _opened_frame:
		_handle_input()
	if _session.stage == HackSession.STAGE_TIMING:
		_session.tick(delta)
	if _session.is_done():
		_resolve()
	queue_redraw()


func _handle_input() -> void:
	if Input.is_action_just_pressed("build_cancel"):
		_session.cancel()
		return
	match _session.stage:
		HackSession.STAGE_SWITCHES:
			if Input.is_action_just_pressed("move_left"):
				_session.move_cursor(-1)
			if Input.is_action_just_pressed("move_right"):
				_session.move_cursor(1)
			if Input.is_action_just_pressed("attack"):
				_session.toggle()
			if Input.is_action_just_pressed("confirm"):
				_session.confirm_switches()
		HackSession.STAGE_TIMING:
			if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("confirm"):
				_session.lock_timing()
		HackSession.STAGE_CHOICE:
			if Input.is_action_just_pressed("move_left"):
				_choice = 0
			if Input.is_action_just_pressed("move_right"):
				_choice = 1
			if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("attack"):
				if _choice == 0:
					_session.choose_open()
				else:
					_session.choose_skip()


## Apply the finished hack to the door and flash the outcome before closing.
func _resolve() -> void:
	_resolved = true
	_outcome_t = 0.9
	if _session.opened:
		_outcome = "OPEN — +%d Heat" % int(round(_session.alarm))
		if _door != null and _door.has_method("hack_open"):
			_door.hack_open(_session.alarm)
	elif _session.failed:
		_outcome = "HACK FAILED — Heat spike, door jammed"
		if _door != null and _door.has_method("hack_fail"):
			_door.hack_fail()
	elif _session.cracked:
		_outcome = "Left it sealed."
	else:
		_outcome = "Backed off."


# ------------------------------------------------------------------- draw ----

func _draw() -> void:
	var o := (SCREEN - PANEL) * 0.5
	draw_rect(Rect2(o, PANEL), Color(0.06, 0.07, 0.11, 0.98))
	draw_rect(Rect2(o, PANEL), Color(0.3, 0.55, 0.8, 0.8), false, 1.5)
	draw_string(_font, o + Vector2(16, 28), "DOOR HACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.6, 0.82, 1.0))

	if _resolved:
		var col := Color(0.6, 1.0, 0.7)
		if _session.failed:
			col = Color(1.0, 0.45, 0.4)
		elif not _session.opened:
			col = Color(0.8, 0.85, 0.9)
		draw_string(_font, o + Vector2(0, 160), _outcome, HORIZONTAL_ALIGNMENT_CENTER, PANEL.x, 18, col)
		return

	match _session.stage:
		HackSession.STAGE_SWITCHES:
			_draw_switches(o)
		HackSession.STAGE_TIMING:
			_draw_timing(o)
		HackSession.STAGE_CHOICE:
			_draw_choice(o)


func _draw_switches(o: Vector2) -> void:
	draw_string(_font, o + Vector2(16, 58), "1/2  Match the switches to the lit pattern", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.9, 0.96))
	var n := _session.switches.size()
	var cell := 44.0
	var total := n * cell + (n - 1) * 10.0
	var sx := o.x + (PANEL.x - total) * 0.5
	var ty := o.y + 100.0  # target lights row
	var sy := o.y + 160.0  # switches row
	for i in n:
		var x := sx + i * (cell + 10.0)
		# Target light (what you're matching).
		var tlit := bool(_session.pattern[i])
		var tr := Rect2(x, ty, cell, 22)
		draw_rect(tr, Color(0.95, 0.85, 0.35) if tlit else Color(0.14, 0.15, 0.2))
		draw_rect(tr, Color(0.4, 0.42, 0.5), false, 1.0)
		# Switch (your current state).
		var son := bool(_session.switches[i])
		var sr := Rect2(x, sy, cell, cell)
		draw_rect(sr, Color(0.2, 0.5, 0.35) if son else Color(0.15, 0.16, 0.22))
		var ok := son == tlit
		draw_rect(sr, (Color(0.5, 0.95, 0.6) if ok else Color(0.5, 0.52, 0.6)), false, 1.5)
		draw_string(_font, Vector2(x + cell * 0.5 - 10, sy + cell * 0.5 + 7), "ON" if son else "off", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 1.0, 0.92) if son else Color(0.6, 0.62, 0.68))
		if i == _session.cursor:
			draw_rect(sr.grow(3), Color.WHITE, false, 2.0)
	var matched := _session.switches_match()
	draw_string(_font, o + Vector2(0, PANEL.y - 44), "match! [Enter] confirm" if matched else "[A/D] pick   [Space] flip", HORIZONTAL_ALIGNMENT_CENTER, PANEL.x, 13, Color(0.6, 1.0, 0.7) if matched else Color(0.8, 0.82, 0.88))
	draw_string(_font, o + Vector2(0, PANEL.y - 24), "[Esc] back off (no cost)", HORIZONTAL_ALIGNMENT_CENTER, PANEL.x, 12, Color(0.6, 0.62, 0.68))


func _draw_timing(o: Vector2) -> void:
	draw_string(_font, o + Vector2(16, 58), "2/2  Stop the marker in the green", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.9, 0.96))
	var c := o + Vector2(PANEL.x * 0.5, PANEL.y * 0.5 + 6)
	var r := 86.0
	draw_arc(c, r, 0.0, TAU, 64, Color(0.3, 0.33, 0.4), 6.0)
	# Green window.
	var gs := _session.green_start * TAU - PI / 2.0
	var ge := (_session.green_start + _session.green_size) * TAU - PI / 2.0
	draw_arc(c, r, gs, ge, 24, Color(0.4, 0.95, 0.5), 8.0)
	# Sweeping marker.
	var a := _session.dial * TAU - PI / 2.0
	var mp := c + Vector2(cos(a), sin(a)) * r
	draw_circle(mp, 7.0, Color(1.0, 0.95, 0.6))
	draw_string(_font, o + Vector2(0, PANEL.y - 30), "[Space] lock    [Esc] back off", HORIZONTAL_ALIGNMENT_CENTER, PANEL.x, 13, Color(0.8, 0.82, 0.88))


func _draw_choice(o: Vector2) -> void:
	draw_string(_font, o + Vector2(0, 90), "CRACKED", HORIZONTAL_ALIGNMENT_CENTER, PANEL.x, 20, Color(0.6, 1.0, 0.7))
	draw_string(_font, o + Vector2(0, 130), "Room alarm — opening adds %d Heat" % int(round(_session.alarm)), HORIZONTAL_ALIGNMENT_CENTER, PANEL.x, 14, Color(0.95, 0.85, 0.5))
	var labels := ["Open (+%d Heat)" % int(round(_session.alarm)), "Skip (leave sealed)"]
	var bw := 190.0
	var gap := 20.0
	var bx := o.x + (PANEL.x - (bw * 2 + gap)) * 0.5
	var by := o.y + 180.0
	for i in 2:
		var br := Rect2(bx + i * (bw + gap), by, bw, 44)
		var sel := i == _choice
		draw_rect(br, Color(0.16, 0.22, 0.3) if sel else Color(0.12, 0.13, 0.18))
		draw_rect(br, Color(0.55, 0.8, 1.0) if sel else Color(0.3, 0.32, 0.4), false, 2.0 if sel else 1.0)
		draw_string(_font, br.position + Vector2(0, 28), labels[i], HORIZONTAL_ALIGNMENT_CENTER, bw, 14, Color(0.95, 0.97, 1.0) if sel else Color(0.75, 0.78, 0.85))
	draw_string(_font, o + Vector2(0, PANEL.y - 28), "[A/D] pick    [Enter] select", HORIZONTAL_ALIGNMENT_CENTER, PANEL.x, 12, Color(0.7, 0.72, 0.78))
