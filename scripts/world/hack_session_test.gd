extends Node
## Phase 2.3 — the door hack logic (HackSession): match the switches → nail the circular timing
## window → crack it (reveal alarm, choose open/skip). Missing the window fails. Harder doors scale.

var fail := 0


func _ready() -> void:
	var h := HackSession.new(1, 20.0, 12345)  # seeded for determinism
	_ck(h.stage == HackSession.STAGE_SWITCHES, "starts on the switches stage")
	_ck(h.alarm == 20.0, "carries the room's alarm (Heat on open)")
	_ck(h.pattern.size() == h.switches.size() and h.pattern.size() >= 3, "pattern + switches sized by difficulty")
	_ck(h.pattern.has(true), "the target is never all-off (always something to flip)")

	_ck(not h.confirm_switches(), "can't advance until the switches match the target")
	_ck(h.stage == HackSession.STAGE_SWITCHES, "still on switches after a bad confirm")
	for i in h.switches.size():
		if bool(h.pattern[i]) != bool(h.switches[i]):
			h.cursor = i
			h.toggle()
	_ck(h.switches_match(), "flipping each wrong switch matches the target")
	_ck(h.confirm_switches() and h.stage == HackSession.STAGE_TIMING, "confirm advances to timing once matched")

	h.dial = fmod(h.green_start + h.green_size * 0.5, 1.0)  # inside the green window
	_ck(h.in_green(), "a marker inside the window reads as green")
	h.lock_timing()
	_ck(h.cracked and h.stage == HackSession.STAGE_CHOICE, "locking in the green cracks the hack → choice")
	h.choose_open()
	_ck(h.is_done() and h.opened, "choosing OPEN finishes, opened")

	# A miss fails the hack.
	var miss := HackSession.new(1, 20.0, 999)
	miss.stage = HackSession.STAGE_TIMING
	miss.green_start = 0.1
	miss.green_size = 0.1
	miss.dial = 0.5
	_ck(not miss.in_green(), "a marker outside the window is not green")
	miss.lock_timing()
	_ck(miss.is_done() and not miss.cracked, "missing the window FAILS the hack (no crack)")

	# Difficulty scales the challenge.
	var easy := HackSession.new(1, 10.0, 1)
	var hard := HackSession.new(3, 10.0, 1)
	_ck(hard.pattern.size() >= easy.pattern.size(), "harder doors have a longer switch pattern")
	_ck(hard.green_size < easy.green_size, "harder doors have a tighter timing window")
	_ck(hard.sweep_speed > easy.sweep_speed, "harder doors sweep faster")

	# Cancel = free walk-away (no crack, no open, no penalty for the caller to apply).
	var cancelled := HackSession.new(1, 10.0, 5)
	cancelled.cancel()
	_ck(cancelled.is_done() and not cancelled.cracked and not cancelled.opened, "cancel ends clean (free walk-away)")

	if fail == 0:
		print("HACK_SESSION_TEST: ALL PASS")
	else:
		printerr("HACK_SESSION_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
