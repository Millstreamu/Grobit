extends Node
## New inventory model: combine two placed machines with [C] (result drops into your hand),
## and scrap a machine in hand with [R] for tech data (the "no room → break it down" path).

var fail := 0


func _ready() -> void:
	var panel := FactoryPanel.new()
	add_child(panel)

	# --- combine is category-aware: two recyclers → a DIFFERENT recycler ---
	var f := FactoryGrid.new(8, 8)
	f.place_machine("copper_recycler", Vector2i(3, 1))
	f.place_machine("steel_recycler", Vector2i(3, 4))
	f.place_machine("steel_ammo_maker", Vector2i(6, 1))
	RunState.factory = f
	RunState.machine_stock = {}
	RunState.machine_instances = []

	# The scrapper arm can't be combined.
	panel._cursor = Vector2i(0, 0)
	panel._combine_at_cursor()
	_ck(panel._combine_a_core == Vector2i(-1, -1), "the scrapper arm can't be marked for combine")

	# Mismatched types are refused (recycler + ammo maker), keeping the first mark.
	panel._cursor = Vector2i(3, 1)
	panel._combine_at_cursor()
	_ck(panel._combine_a_core == Vector2i(3, 1), "first recycler marked")
	panel._cursor = Vector2i(6, 1)
	panel._combine_at_cursor()
	_ck(f.machine_at(Vector2i(3, 1)) >= 0 and f.machine_at(Vector2i(6, 1)) >= 0, "mismatched types aren't combined")
	_ck(panel._combine_a_core == Vector2i(3, 1), "the first mark is kept after a mismatch")

	# Two recyclers (copper + steel) → a recycler that is neither (plastic or ceramic).
	panel._cursor = Vector2i(3, 4)
	panel._combine_at_cursor()
	_ck(f.machine_at(Vector2i(3, 1)) < 0 and f.machine_at(Vector2i(3, 4)) < 0, "both recyclers removed from the grid")
	_ck(panel._place_mode, "the result drops into your hand to place")
	_ck(panel._place_id in ["plastic_recycler", "ceramic_recycler"], "result is a DIFFERENT recycler (not either input)")
	_ck(RunState.instance_count() == 1, "the result is held as an instance until placed")

	# Two of the SAME type (two copper recyclers) → one of the other three recyclers.
	var w := FactoryGrid.new(8, 8)
	w.place_machine("copper_recycler", Vector2i(1, 1))
	w.place_machine("copper_recycler", Vector2i(4, 1))
	RunState.factory = w
	RunState.machine_stock = {}
	panel._reset_modes()
	panel._cursor = Vector2i(1, 1); panel._combine_at_cursor()
	panel._cursor = Vector2i(4, 1); panel._combine_at_cursor()
	_ck(panel._place_id in ["steel_recycler", "plastic_recycler", "ceramic_recycler"], "two copper recyclers → a non-copper recycler")

	# Weapons combine into weapons.
	var wv := FactoryGrid.new(8, 8)
	wv.place_machine("copper_weapon", Vector2i(1, 1))
	wv.place_machine("steel_weapon", Vector2i(4, 1))
	RunState.factory = wv
	RunState.machine_stock = {}
	panel._reset_modes()
	panel._cursor = Vector2i(1, 1); panel._combine_at_cursor()
	panel._cursor = Vector2i(4, 1); panel._combine_at_cursor()
	_ck(panel._place_id in ["plastic_weapon", "ceramic_weapon"], "two weapons → a different weapon")

	# --- marking the same machine twice unmarks it ---
	var g := FactoryGrid.new(8, 8)
	g.place_machine("copper_recycler", Vector2i(2, 2))
	RunState.factory = g
	panel._reset_modes()
	panel._cursor = Vector2i(2, 2)
	panel._combine_at_cursor()
	panel._combine_at_cursor()
	_ck(panel._combine_a_core == Vector2i(-1, -1), "marking the same machine twice clears it")

	# --- scrap a machine instance held in hand → tech data ---
	RunState.factory = FactoryGrid.new(8, 8)
	RunState.machine_instances = []
	panel._reset_modes()
	RunState.add_machine_instance("copper_recycler")
	panel._begin_place_instance(0)  # into hand, with its layout
	var before := RunState.get_quantity("tech_data")
	panel._scrap_held_machine()
	_ck(RunState.get_quantity("tech_data") > before, "scrapping a held machine yields tech data")
	_ck(RunState.instance_count() == 0, "the scrapped instance leaves storage")
	_ck(not panel._place_mode or panel._place_id != "copper_recycler", "no longer holding the scrapped machine")

	# --- scrap a placed machine lifted for a move → tech data ---
	var h := FactoryGrid.new(8, 8)
	var mi := h.place_machine("steel_recycler", Vector2i(4, 4))
	RunState.factory = h
	panel._reset_modes()
	panel._move_mi = mi
	panel._move_mode = true
	var td := RunState.get_quantity("tech_data")
	panel._scrap_moving_machine()
	_ck(h.machine_at(Vector2i(4, 4)) < 0, "the lifted machine is removed when scrapped")
	_ck(RunState.get_quantity("tech_data") > td, "scrapping a lifted machine yields tech data")
	_ck(not panel._move_mode, "move mode ends after scrapping")

	if fail == 0:
		print("COMBINE_TEST: ALL PASS")
	else:
		printerr("COMBINE_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
