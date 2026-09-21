extends Node
## Headless test for Step 3 minigame logic (ScrapNode.hit_slot + arm intake). Run:
##   godot --headless --path . res://scenes/test/scrap_node_test.tscn
## Exits 0 on success. Sets node fields directly for determinism (no RNG).

func _ready() -> void:
	var failures := 0

	# --- Harvest deposits to the arm, spends a token; arm-full blocks with no cost.
	RunState.factory = _fresh_arm_grid()  # 3 free holding cells
	var n := _node(5, ["scrap_metal", "scrap_metal", "scrap_metal", "scrap_metal"], [0, 0, 0, 0])
	failures += _check(n.hit_slot(0) == "scrap_metal", "harvest returns the item id")
	failures += _check(n.tokens == 4, "harvest spends a token")
	failures += _check(String(n.slots[0]) == "", "harvested slot becomes empty")
	failures += _check(RunState.factory.harvest_space() == 2, "item deposited into an arm holding cell")
	# Fill the arm (2 more), then a further harvest must be blocked.
	n.hit_slot(1)
	n.hit_slot(2)
	failures += _check(RunState.factory.harvest_space() == 0, "arm now full")
	failures += _check(n.tokens == 2, "three harvests spent three tokens")
	failures += _check(n.hit_slot(3) == "arm_full", "harvest blocked when arm is full")
	failures += _check(n.tokens == 2, "arm-full harvest costs no token")
	failures += _check(String(n.slots[3]) == "scrap_metal", "arm-full harvest leaves the item")

	# --- Rust: each hit spends a token and chips rust; then the item is takeable.
	RunState.factory = _fresh_arm_grid()
	var r := _node(5, ["scrap_metal", "", "", ""], [2, 0, 0, 0])
	failures += _check(r.hit_slot(0) == "rust", "rust hit returns 'rust'")
	failures += _check(r.tokens == 4 and int(r.rust[0]) == 1, "rust hit spends token, chips one")
	r.hit_slot(0)
	failures += _check(int(r.rust[0]) == 0, "rust fully cleared after 2 hits")
	failures += _check(r.hit_slot(0) == "scrap_metal", "exposed slot then harvests")

	# --- Empty exposed slot: no token cost.
	RunState.factory = _fresh_arm_grid()
	var e := _node(3, ["", "", "", ""], [0, 0, 0, 0])
	failures += _check(e.hit_slot(0) == "empty", "empty slot returns 'empty'")
	failures += _check(e.tokens == 3, "empty slot costs no token")

	# --- Depletion: last token spent → node is spent.
	RunState.factory = _fresh_arm_grid()
	var s := _node(1, ["scrap_metal", "scrap_metal", "", ""], [0, 0, 0, 0])
	failures += _check(s.hit_slot(0) == "scrap_metal", "final harvest succeeds")
	failures += _check(s.is_spent(), "node spent when tokens hit 0")
	failures += _check(s.hit_slot(1) == "spent", "spent node rejects further hits")

	if failures == 0:
		print("SCRAP_NODE_TEST: ALL PASS")
	else:
		printerr("SCRAP_NODE_TEST: %d FAILURE(S)" % failures)
	get_tree().quit(failures)


func _fresh_arm_grid() -> FactoryGrid:
	var g := FactoryGrid.new(6, 3)
	g.place_machine("scrapper_arm", Vector2i(0, 0))  # 3 holding cells
	return g


func _node(tokens: int, slots: Array, rust: Array) -> ScrapNode:
	var n := ScrapNode.new()
	n.tokens = tokens
	n.slots = slots.duplicate()
	n.rust = rust.duplicate()
	n.loose = false
	n._pool = [{"id": "scrap_metal", "weight": 1}]
	return n


func _check(condition: bool, label: String) -> int:
	if condition:
		print("  ok   - ", label)
		return 0
	printerr("  FAIL - ", label)
	return 1
