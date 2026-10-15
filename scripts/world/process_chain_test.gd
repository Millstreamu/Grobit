extends Node
## Phase 4 core — the process CHAIN engine. Scrap enters an intake and flows machine-to-machine only
## where ports line up; the ordered verb sequence + input scrap resolves to a product. Misaligned or
## broken chains make nothing. Rearranging is fluid (the sequence — and the product — just changes).
## Multi-line: one grid can hold several independent intakes/chains at once.

const R := Vector2i(1, 0)
const L := Vector2i(-1, 0)
const D := Vector2i(0, 1)
const U := Vector2i(0, -1)

var fail := 0


func _ready() -> void:
	_ck(not GameData.process_recipes.is_empty(), "process.json recipes loaded (%d)" % GameData.process_recipes.size())

	# A straight chain: intake → Heater → Presser, all facing right. steel_scrap → steel_plate.
	var g := ProcessGrid.new(6, 6)
	g.set_intake(Vector2i(0, 2), R, "steel_scrap")   # steel scrap enters (1,2) travelling right
	g.place("heat", Vector2i(1, 2), L, R)
	g.place("press", Vector2i(2, 2), L, R)
	var e := g.first_intake()
	_ck(g.trace_sequence(e) == ["heat", "press"], "a straight aligned chain traces its verb sequence")
	_ck(g.product_for(e) == "steel_plate", "steel_scrap through heat→press makes a steel plate")
	_ck(g.output_cell(e) == Vector2i(3, 2), "the product drops one cell past the last machine")

	# Input scrap matters: re-point the SAME intake to copper and the chain makes a copper sheet.
	g.set_intake(Vector2i(0, 2), R, "copper_scrap")
	_ck(g.product_for(g.first_intake()) == "copper_sheet", "same chain, copper_scrap → copper sheet (input matters)")

	# Fluid: swap the second machine's verb (press → mold) and the product changes with the sequence.
	g.set_intake(Vector2i(0, 2), R, "steel_scrap")
	g.remove(Vector2i(2, 2))
	g.place("mold", Vector2i(2, 2), L, R)
	_ck(g.trace_sequence(g.first_intake()) == ["heat", "mold"], "rearranging changes the traced sequence (fluid)")
	_ck(g.product_for(g.first_intake()) == "steel_ingot", "heat→mold now makes a steel ingot")

	# A MISALIGNED port kills the chain.
	var g2 := ProcessGrid.new(6, 6)
	g2.set_intake(Vector2i(0, 2), R, "steel_scrap")
	g2.place("heat", Vector2i(1, 2), L, R)
	g2.place("press", Vector2i(2, 2), U, R)      # in faces UP — item arrives from the left, not up
	_ck(g2.trace_sequence(g2.first_intake()) == ["heat"], "a misaligned in-port breaks the chain")
	_ck(g2.product_for(g2.first_intake()) == "", "a broken chain makes nothing")

	# A GAP also stops the chain.
	var g3 := ProcessGrid.new(6, 6)
	g3.set_intake(Vector2i(0, 0), R, "steel_scrap")
	g3.place("heat", Vector2i(1, 0), L, R)
	g3.place("press", Vector2i(3, 0), L, R)      # a hole at (2,0)
	_ck(g3.trace_sequence(g3.first_intake()) == ["heat"], "a gap in the line stops the chain")

	# An L-bend works as long as ports line up.
	var g4 := ProcessGrid.new(6, 6)
	g4.set_intake(Vector2i(0, 0), R, "steel_scrap")
	g4.place("heat", Vector2i(1, 0), L, D)       # out goes DOWN
	g4.place("mold", Vector2i(1, 1), U, D)       # in faces UP (back at the Heater)
	_ck(g4.trace_sequence(g4.first_intake()) == ["heat", "mold"], "an L-bend chain traces fine when ports align")

	# No intake → no chain.
	var g5 := ProcessGrid.new(4, 4)
	g5.place("heat", Vector2i(1, 1), L, R)
	_ck(not g5.has_intake() and g5.trace_sequence(g5.first_intake()).is_empty(), "no intake → no sequence")

	# MULTI-LINE: two independent intakes/chains in one grid.
	var gm := ProcessGrid.new(8, 6)
	gm.set_intake(Vector2i(0, 0), R, "steel_scrap")
	gm.place("heat", Vector2i(1, 0), L, R)
	gm.place("press", Vector2i(2, 0), L, R)      # line A: steel → plate
	gm.set_intake(Vector2i(0, 3), R, "copper_scrap")
	gm.place("heat", Vector2i(1, 3), L, R)
	gm.place("fold", Vector2i(2, 3), L, R)       # line B: copper → coil
	_ck(gm.intake_count() == 2, "two intakes = two lines")
	_ck(gm.product_for(gm.intakes[0]) == "steel_plate", "line A makes steel plate")
	_ck(gm.product_for(gm.intakes[1]) == "copper_coil", "line B makes copper coil")
	_ck(gm.chain_cells().size() == 4, "both lines' machine cells are highlighted")

	if fail == 0:
		print("PROCESS_CHAIN_TEST: ALL PASS")
	else:
		printerr("PROCESS_CHAIN_TEST: %d FAILURE(S)" % fail)
	get_tree().quit(fail)


func _ck(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		fail += 1
		printerr("  FAIL - ", label)
