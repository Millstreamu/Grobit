extends Node
## Component Exchange: selling components builds per-run credit, and each full
## ExchangePanel.MACHINE_COST grants a random machine into stock. Credit carries while
## the run lasts; partial credit waits for the next sale.

var fail := 0


func _ready() -> void:
	RunState.factory = FactoryGrid.new(8, 8)
	RunState.factory.place_machine("scrapper_arm", Vector2i(0, 0))
	RunState.exchange_credit = 0
	RunState.exchange_machines_granted = 0
	RunState.machine_stock = {}
	RunState.machine_instances = []

	var panel := ExchangePanel.new()
	add_child(panel)

	# Selling with nothing in hand does nothing.
	panel._sell_all()
	_ck(RunState.exchange_credit == 0 and _stock_total() == 0, "selling empty-handed grants nothing")

	# Partial sale banks credit without granting yet.
	RunState.add("power_coupling", 2)  # 2 credit < MACHINE_COST
	panel._sell_all()
	_ck(RunState.exchange_credit == 2 and _stock_total() == 0, "a partial sale banks credit, no machine yet")

	# Topping past the cost grants one machine; the exchange then goes dormant (cap 1).
	RunState.add("power_coupling", 2)  # +2 → 4 credit → one machine, 1 left over
	panel._sell_all()
	_ck(_stock_total() == 1, "crossing the cost grants one machine")
	_ck(RunState.exchange_credit == 1, "leftover credit above the cost stays banked")
	_ck(_granted_is_from_pool(), "the granted machine is a production machine")
	_ck(RunState.exchange_dormant(), "the exchange goes dormant after its one machine")

	# Dormant: further sales grant nothing and don't even consume your components.
	RunState.add("thermal_core", 4)
	var before := RunState.get_quantity("thermal_core")
	panel._sell_all()
	_ck(_stock_total() == 1 and RunState.get_quantity("thermal_core") == before, "a dormant exchange grants nothing and keeps your components")

	# Credit and dormancy are per-run: a fresh run clears them.
	RunState.begin_run(GameData.first_area_id(), 1)
	_ck(RunState.exchange_credit == 0 and not RunState.exchange_dormant(), "a new run clears exchange credit and dormancy")

	if fail == 0:
		print("EXCHANGE_TEST: ALL PASS")
	else:
		printerr("EXCHANGE_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _stock_total() -> int:
	return RunState.instance_count()


func _granted_is_from_pool() -> bool:
	for inst: Dictionary in RunState.machine_instances:
		if not ExchangePanel.MACHINE_POOL.has(String(inst.get("def_id", ""))):
			return false
	return true


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
