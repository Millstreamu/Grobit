extends Node
## The lair/scrapbot entry: you start a run in the lair as the goblin (not driving); the
## scrapbot's prompt is "drive out" until you hop in, then "extract" once you're out.

var fail := 0


func _ready() -> void:
	RunState.begin_run(GameData.first_area_id(), 1)
	_ck(not RunState.driving, "begin_run starts you in the lair (not driving)")

	var s := Scrapbot.new()
	add_child(s)
	await get_tree().process_frame

	var before := s.interaction_prompt()
	_ck("launch" in before.to_lower() or "set up" in before.to_lower(), "scrapbot prompt says set up & launch before you've hopped in")

	RunState.driving = true
	var after := s.interaction_prompt()
	_ck("extract" in after.to_lower() or "head home" in after.to_lower(), "scrapbot prompt says extract once you're driving")

	if fail == 0:
		print("SCRAPBOT_TEST: ALL PASS")
	else:
		printerr("SCRAPBOT_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
