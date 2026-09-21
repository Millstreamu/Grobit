extends Node
## Regression test for the scrap-minigame open/close bug: pressing F (interact) to
## open it must NOT also close it (SelectionManager re-fires 'interact' the same
## frame). F must be inert as a close key; only Esc closes. Run:
##   godot --headless --path . res://scenes/test/minigame_input_test.tscn

func _ready() -> void:
	var failures := 0

	var mg := ScrapMinigame.new()
	add_child(mg)
	mg.setup(null)

	var node := ScrapNode.new()
	node.tokens = 5
	node.slots = ["scrap_metal", "", "", ""]
	node.rust = [0, 0, 0, 0]

	mg.open(node)
	failures += _check(mg.is_open(), "minigame opens")
	failures += _check(mg._opened_frame == Engine.get_process_frames(), "open records the frame (input skipped that frame)")

	# The bug: F/interact used to close it → same-frame reopen flicker. Now inert.
	Input.action_press("interact")
	mg._handle_input()
	Input.action_release("interact")
	failures += _check(mg.is_open(), "F (interact) does NOT close the minigame")

	# Esc still leaves.
	Input.action_press("build_cancel")
	mg._handle_input()
	Input.action_release("build_cancel")
	failures += _check(not mg.is_open(), "Esc closes the minigame")

	if failures == 0:
		print("MINIGAME_INPUT_TEST: ALL PASS")
	else:
		printerr("MINIGAME_INPUT_TEST: %d FAILURE(S)" % failures)
	get_tree().quit(failures)


func _check(condition: bool, label: String) -> int:
	if condition:
		print("  ok   - ", label)
		return 0
	printerr("  FAIL - ", label)
	return 1
