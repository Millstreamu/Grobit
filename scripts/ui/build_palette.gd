class_name BuildPalette
extends Control
## Non-modal build overlay, shown only while build mode is active. Draws a row of
## buildable "cards" (icon, name, per-resource cost coloured by affordability) with
## the selected one highlighted, plus a validity header explaining whether the
## current cursor tile can be built on.
##
## Input still lives in BuildManager (WASD cursor, Space place, 1-N / Tab select,
## B/Esc exit); this panel only reads state and renders it. Placeholder art: cards
## are flat coloured rects with the buildable's icon until real card art exists.

const CARD := Vector2(120, 64)
const GAP := 10.0
const STRIP_Y := 300.0

var _build: BuildManager
var _font: Font


func _ready() -> void:
	position = Vector2.ZERO
	size = Vector2(640, 448)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = ThemeDB.fallback_font


func setup(build: BuildManager) -> void:
	_build = build


func _process(_delta: float) -> void:
	if _build == null:
		return
	var active := _build.is_build_active()
	if active != visible:
		visible = active
	if active:
		queue_redraw()


func _draw() -> void:
	if _build == null:
		return
	var ids := _build.buildable_ids()
	if ids.is_empty():
		return
	var total_w := ids.size() * CARD.x + (ids.size() - 1) * GAP
	var origin := Vector2((size.x - total_w) * 0.5, STRIP_Y)

	# Validity header above the cards.
	var reason := _build.placement_reason()
	var head := "Ready — [Space] to place" if reason.is_empty() else reason
	var head_col := Color(0.5, 1, 0.6) if reason.is_empty() else Color(1, 0.5, 0.5)
	draw_string(_font, Vector2(origin.x, origin.y - 12), head, HORIZONTAL_ALIGNMENT_LEFT, total_w, 15, head_col)

	for i in ids.size():
		_draw_card(i, String(ids[i]), Rect2(origin + Vector2(i * (CARD.x + GAP), 0), CARD))

	var hint := "[1-%d]/[Tab] select   [WASD] move cursor   [Space] place   [B]/[Esc] exit" % ids.size()
	draw_string(_font, Vector2(origin.x, origin.y + CARD.y + 18), hint, HORIZONTAL_ALIGNMENT_LEFT, total_w, 13, Color(0.7, 0.7, 0.75))


func _draw_card(index: int, id: String, rect: Rect2) -> void:
	var def: Dictionary = GameData.buildables.get(id, {})
	var cost: Dictionary = def.get("cost", {})
	var affordable := RunState.can_afford(cost)
	var selected := index == _build.selected_index()

	draw_rect(rect, Color(0.16, 0.09, 0.09) if not affordable else Color(0.10, 0.11, 0.14))

	# Icon + number badge + name.
	var tex := ContentLibrary.get_icon(String(def.get("icon", id)), Vector2i(24, 24), String(def.get("color", "")))
	draw_texture_rect(tex, Rect2(rect.position + Vector2(8, 8), Vector2(24, 24)), false)
	draw_string(_font, rect.position + Vector2(rect.size.x - 16, 17), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.9, 0.5))
	draw_string(_font, rect.position + Vector2(38, 21), String(def.get("name", id)), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 44, 14, Color(0.92, 0.92, 0.96))

	# Cost tokens, one per resource, coloured green/red by whether you hold enough.
	var x := rect.position.x + 8
	var y := rect.position.y + 46
	if cost.is_empty():
		draw_string(_font, Vector2(x, y), "free", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.8, 1))
	for res: String in cost:
		var need := int(cost[res])
		var col := Color(0.5, 1, 0.6) if RunState.get_quantity(res) >= need else Color(1, 0.5, 0.5)
		var token := "%d %s" % [need, GameData.resource_name(res)]
		draw_string(_font, Vector2(x, y), token, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		x += _font.get_string_size(token, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10

	if selected:
		draw_rect(rect.grow(2), Color(1, 0.85, 0.2), false, 2.0)
	else:
		draw_rect(rect, Color(0, 0, 0, 0.4), false, 1.0)
