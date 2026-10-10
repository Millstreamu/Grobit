class_name HackSession
extends RefCounted
## The two-stage door hack (pure logic — no rendering; HackPanel drives + draws it).
##   Stage 1 (SWITCHES): flip a row of switches to match the shown target pattern, then confirm.
##   Stage 2 (TIMING):   stop a marker sweeping a circular dial inside the green window.
##   Stage 3 (CHOICE):   cracked! the room's alarm (Heat cost) is revealed — OPEN or SKIP.
## Missing the timing window FAILS the hack (caller applies a Heat spike + a temporary door lock).
## Harder doors = a longer switch pattern + a tighter, faster dial window. Controller-first:
## d-pad to pick a switch, one button to toggle / lock / choose.

enum { STAGE_SWITCHES, STAGE_TIMING, STAGE_CHOICE, DONE }

var stage := STAGE_SWITCHES
var cracked := false     # reached CHOICE (beat the minigame)
var failed := false      # missed the timing window (caller applies Heat spike + door lock)
var opened := false      # chose to open the door (only meaningful once DONE + cracked)
var alarm := 0.0         # Heat added when the door is opened (the room's "alarm"), revealed on crack

# Stage 1 — switches
var pattern: Array = []  # target bools
var switches: Array = [] # current bools
var cursor := 0

# Stage 2 — circular timing dial (positions are fractions of the circle, 0..1)
var dial := 0.0
var sweep_speed := 0.8   # fractions of the circle per second
var green_start := 0.0
var green_size := 0.2

var _rng := RandomNumberGenerator.new()


func _init(difficulty := 1, room_alarm := 15.0, seed_val := 0) -> void:
	if seed_val != 0:
		_rng.seed = seed_val
	else:
		_rng.randomize()
	alarm = room_alarm
	var n := clampi(2 + difficulty, 3, 6)  # pattern length grows with difficulty
	for _i in n:
		pattern.append(_rng.randf() < 0.5)
		switches.append(false)
	# Guarantee at least one switch must be flipped (never an all-off "already solved" pattern).
	if not pattern.has(true):
		pattern[_rng.randi() % n] = true
	sweep_speed = 0.7 + 0.18 * float(difficulty)
	green_size = clampf(0.24 - 0.04 * float(difficulty), 0.08, 0.24)
	green_start = _rng.randf()


# --- Stage 1: switches ---
func move_cursor(dir: int) -> void:
	if stage == STAGE_SWITCHES and not switches.is_empty():
		cursor = clampi(cursor + dir, 0, switches.size() - 1)


func toggle() -> void:
	if stage == STAGE_SWITCHES:
		switches[cursor] = not bool(switches[cursor])


func switches_match() -> bool:
	return switches == pattern


## Confirm the switches. Advances to the timing stage only when the pattern matches (no fail here —
## you simply can't proceed until it's right). Returns true if it advanced.
func confirm_switches() -> bool:
	if stage == STAGE_SWITCHES and switches_match():
		stage = STAGE_TIMING
		return true
	return false


# --- Stage 2: timing dial ---
func tick(delta: float) -> void:
	if stage == STAGE_TIMING:
		dial = fmod(dial + sweep_speed * delta, 1.0)


func in_green() -> bool:
	var d := fmod((dial - green_start) + 1.0, 1.0)
	return d <= green_size


## Lock the marker: in the green → cracked (reveal the alarm + choose); otherwise the hack FAILS.
func lock_timing() -> void:
	if stage != STAGE_TIMING:
		return
	if in_green():
		cracked = true
		stage = STAGE_CHOICE
	else:
		failed = true
		stage = DONE


# --- Stage 3: choice (only reached on a crack) ---
func choose_open() -> void:
	if stage == STAGE_CHOICE:
		opened = true
		stage = DONE


func choose_skip() -> void:
	if stage == STAGE_CHOICE:
		opened = false
		stage = DONE


func is_done() -> bool:
	return stage == DONE


## Abort (walked away) — no crack, no open; the caller treats this as a free cancel (no penalty).
func cancel() -> void:
	cracked = false
	opened = false
	stage = DONE
