extends Node
## Component Exchange: selling components builds per-run credit, and each full
## ExchangePanel.MACHINE_COST grants a random machine into stock. Credit carries while
## the run lasts; partial credit waits for the next sale.

var fail := 0


func _ready() -> void:
	RunState.factory = FactoryGrid.new(8, 8)
	RunState.factory.place_machine("scrapper_arm", Vector2i(0, 0))
	RunState.exchange_credit = 0
	RunState.machine_stock = {}

	var panel := ExchangePanel.new()
	add_child(panel)

	# Selling with nothing in hand does nothing.
	panel._sell_all()
	_ck(RunState.exchange_credit == 0 and _stock_total() == 0, "selling empty-handed grants nothing")

	# Exactly one machine's worth of components → one machine, credit back to zero.
	RunState.add("power_coupling", 2)
	RunState.add("thermal_core", 1)  # 3 components, 3 credit, = MACHINE_COST
	panel._sell_all()
	_ck(RunState.get_quantity("power_coupling") == 0 and RunState.get_quantity("thermal_core") == 0, "sold components are consumed")
	_ck(_stock_total() == 1, "a full credit bar grants one machine")
	_ck(RunState.exchange_credit == 0, "credit resets after granting a machine")
	_ck(_granted_is_from_pool(), "the granted machine is a production machine")

	# Partial sale banks credit without granting yet; a later sale tops it up.
	RunState.add("reinforced_frame", 2)  # 2 credit < MACHINE_COST
	panel._sell_all()
	_ck(RunState.exchange_credit == 2 and _stock_total() == 1, "a partial sale banks credit, no machine yet")
	RunState.add("control_assembly", 2)  # +2 credit -> 4 total -> one machine, 1 left over
	panel._sell_all()
	_ck(_stock_total() == 2, "credit carries over and the next sale grants a machine")
	_ck(RunState.exchange_credit == 1, "leftover credit above the cost stays banked")

	# Credit is per-run: a fresh run clears it.
	RunState.begin_run(GameData.first_area_id(), 1)
	_ck(RunState.exchange_credit == 0, "a new run clears exchange credit")

	if fail == 0:
		print("EXCHANGE_TEST: ALL PASS")
	else:
		printerr("EXCHANGE_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _stock_total() -> int:
	var n := 0
	for id: String in RunState.machine_stock:
		n += int(RunState.machine_stock[id])
	return n


func _granted_is_from_pool() -> bool:
	for id: String in RunState.machine_stock:
		if not ExchangePanel.MACHINE_POOL.has(id):
			return false
	return true


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
