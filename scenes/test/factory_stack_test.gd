extends Node
## Panel-level regression: carried resource stacking (pick up multiples, drop one at a
## time) and returning a held stack to the grid on close.
var fail := 0
func ck(c: bool, l: String) -> void:
	if c:
		print("  ok: ", l)
	else:
		fail += 1
		printerr("  FAIL: ", l)
func _ready() -> void:
	RunState.factory = FactoryGrid.new(8, 8)
	var f = RunState.factory
	f.set_cell(Vector2i(1,1), {"kind":"resource","id":"scrap_metal"})
	f.set_cell(Vector2i(2,1), {"kind":"resource","id":"scrap_metal"})
	f.set_cell(Vector2i(3,1), {"kind":"resource","id":"copper_wire"})
	var p = FactoryPanel.new()
	add_child(p)
	# pick up two scrap_metal into a stack
	p._cursor = Vector2i(1,1); p._pick_or_drop()
	p._cursor = Vector2i(2,1); p._pick_or_drop()
	ck(int(p._carried.get("count",0)) == 2, "stacked 2 of the same item")
	ck(f.get_cell(Vector2i(1,1)).is_empty() and f.get_cell(Vector2i(2,1)).is_empty(), "both source cells cleared")
	# different item under cursor while holding -> refused, stack intact
	p._cursor = Vector2i(3,1); p._pick_or_drop()
	ck(int(p._carried.get("count",0)) == 2 and String(f.get_cell(Vector2i(3,1)).get("id","")) == "copper_wire", "different item not grabbed")
	# drop one onto an empty cell
	p._cursor = Vector2i(5,5); p._pick_or_drop()
	ck(int(p._carried.get("count",0)) == 1, "dropping placed one, stack now 1")
	ck(String(f.get_cell(Vector2i(5,5)).get("id","")) == "scrap_metal", "dropped item landed")
	# drop the last one -> hand empty
	p._cursor = Vector2i(6,6); p._pick_or_drop()
	ck(p._carried.is_empty(), "hand empty after dropping the last")
	# carried returns to grid on close
	f.set_cell(Vector2i(0,0), {"kind":"resource","id":"metal_bar"})
	p._cursor = Vector2i(0,0); p._pick_or_drop()
	var before = int(f.resource_counts().get("metal_bar",0))
	p.close()
	ck(int(f.resource_counts().get("metal_bar",0)) == before + 1, "carried item returned to grid on close")
	if fail == 0:
		print("STACK CHECKS PASS")
	else:
		printerr(fail, " FAIL")
	get_tree().quit(fail)
