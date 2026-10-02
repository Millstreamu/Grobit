extends Node
## Filter conveyor: the set item turns out the 90° side, everything else goes straight,
## and a matching item waits when its exit is blocked.
var fail := 0
func ck(c: bool, l: String) -> void:
	if c:
		print("  ok: ", l)
	else:
		fail += 1
		printerr("  FAIL: ", l)
func _ready() -> void:
	var g := FactoryGrid.new(6, 6)
	# filter at (2,2), straight = right (dir), 90° side = down (dir2 = (-dir.y,dir.x) of (1,0) = (0,1))
	g.place_filter(Vector2i(2,2), Vector2i(1,0), "copper_wire")
	# a matching item on the filter -> goes out the 90 side (down)
	var c = g.get_cell(Vector2i(2,2)); c["item"] = "copper_wire"
	g.tick(FactoryGrid.CONVEYOR_INTERVAL)
	ck(String(g.get_cell(Vector2i(2,3)).get("id","")) == "copper_wire", "matching item turned out the 90° side (down)")
	ck(g.get_cell(Vector2i(3,2)).is_empty(), "straight side stayed empty for a match")
	# a non-matching item -> goes straight (right)
	c["item"] = "scrap_metal"
	g.tick(FactoryGrid.CONVEYOR_INTERVAL)
	ck(String(g.get_cell(Vector2i(3,2)).get("id","")) == "scrap_metal", "non-matching item went straight (right)")
	# blocked filter side: matching item waits (strict routing)
	g.set_cell(Vector2i(2,4), {"kind":"resource","id":"scrap_metal"})  # not the exit; ensure exit (2,3) occupied
	g.set_cell(Vector2i(2,3), {"kind":"resource","id":"copper_wire"})   # occupy the 90 exit
	c["item"] = "copper_wire"
	g.tick(FactoryGrid.CONVEYOR_INTERVAL)
	ck(String(g.get_cell(Vector2i(2,2)).get("item","")) == "copper_wire", "matching item waits when the 90° exit is blocked")
	if fail == 0:
		print("FILTER CHECKS PASS")
	else:
		printerr(fail, " FAIL")
	get_tree().quit(fail)
