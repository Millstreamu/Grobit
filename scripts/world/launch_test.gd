extends Node
## Launching now lives in the Scrapbot window: at base, [Enter] (confirm) calls the controller's
## launch_from_setup to drive out. This drives that path directly (no scene/physics).

var fail := 0
var _launched := false


func _ready() -> void:
	add_to_group("run_controller")  # stand in for the RunController
	MetaState.seed_colony(3)
	RunState.begin_run(GameData.first_area_id(), 1)
	RunState.driving = false

	var panel := ScrapbotPanel.new()
	add_child(panel)
	panel.open()
	_ck(panel.is_open(), "the scrapbot window opens at base")
	_ck(not _launched, "no launch before confirming")

	# Simulate pressing [Enter] in the window at base.
	panel._launch()
	_ck(_launched, "confirming in the window launches the run (launch_from_setup)")
	_ck(not panel.is_open(), "the window closes on launch")
	panel.free()

	if fail == 0:
		print("LAUNCH_TEST: ALL PASS")
	else:
		printerr("LAUNCH_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func launch_from_setup() -> void:
	_launched = true


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
