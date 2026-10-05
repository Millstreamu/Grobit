extends Node
## C4 — lair needs + distress beacon endgame. Delivering a bridge component on extraction fills
## its matching need (capped), and filling all four readies the beacon (the win).
## (Writes the save — the runner backs it up.)

var fail := 0


func _ready() -> void:
	MetaState.lair_needs = {}
	MetaState.beacon_sent = false

	# Components map to needs; non-components are ignored.
	var added := MetaState.deliver_to_needs({"reinforced_frame": 2, "copper": 9, "power_coupling": 1})
	_ck(MetaState.need_amount("oxygen") == 2, "reinforced_frame fills oxygen")
	_ck(MetaState.need_amount("power") == 1, "power_coupling fills power")
	_ck(MetaState.need_amount("water") == 0, "non-delivered needs stay empty")
	_ck(int(added.get("oxygen", 0)) == 2, "the delivery report lists what was added")

	# A need caps at NEED_MAX (overflow is wasted).
	MetaState.deliver_to_needs({"reinforced_frame": 99})
	_ck(MetaState.need_amount("oxygen") == MetaState.NEED_MAX, "a need caps at NEED_MAX")

	# The lair isn't restored until every need is maxed.
	_ck(not MetaState.lair_restored(), "lair not restored while needs remain")
	MetaState.deliver_to_needs({
		"power_coupling": MetaState.NEED_MAX,
		"control_assembly": MetaState.NEED_MAX,
		"thermal_core": MetaState.NEED_MAX,
	})
	_ck(MetaState.lair_restored(), "lair restored once all four needs are maxed")

	MetaState.send_beacon()
	_ck(MetaState.beacon_sent, "the distress beacon is sent")

	# Disk round-trip.
	MetaState.save_game()
	MetaState.lair_needs = {}
	MetaState.beacon_sent = false
	MetaState.load_game()
	_ck(MetaState.need_amount("oxygen") == MetaState.NEED_MAX and MetaState.beacon_sent, "needs + beacon survive save/load")

	MetaState.lair_needs = {}
	MetaState.beacon_sent = false
	if fail == 0:
		print("LAIR_NEEDS_TEST: ALL PASS")
	else:
		printerr("LAIR_NEEDS_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
