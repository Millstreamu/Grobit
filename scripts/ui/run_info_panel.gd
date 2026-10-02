class_name RunInfoPanel
extends Control
## Debug / run-info panel ([P]). Reveals the run's GUARANTEED production chain and
## whether the weapon can actually be fed — it does NOT fix problems, only surfaces
## them so we can observe good/bad/partial chains. Pauses the world while open.

const PANEL := Rect2(Vector2(40, 46), Vector2(560, 356))

var _opened_frame := -1
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2.ZERO
	size = Vector2(640, 448)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = ThemeDB.fallback_font


func is_open() -> bool:
	return visible


func open() -> void:
	_opened_frame = Engine.get_process_frames()
	visible = true
	get_tree().paused = true
	queue_redraw()


func close() -> void:
	visible = false
	get_tree().paused = false


func _process(_delta: float) -> void:
	if not visible:
		return
	if Engine.get_process_frames() != _opened_frame:
		if Input.is_action_just_pressed("run_info") or Input.is_action_just_pressed("build_cancel"):
			close()
	queue_redraw()


func _draw() -> void:
	draw_rect(PANEL, Color(0.05, 0.06, 0.09, 0.98))
	draw_rect(PANEL, Color(0.3, 0.5, 0.7, 0.6), false, 1.0)
	var x := PANEL.position.x + 16
	var y := PANEL.position.y + 26
	draw_string(_font, Vector2(x, y), "RUN INFO  (debug — problems are shown, not fixed)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.85, 1.0))
	y += 30

	var fam: Dictionary = GameData.families.get(RunState.weapon_family, {})
	_line(x, y, "Weapon family:  %s  →  fires %s" % [String(fam.get("name", "—")), GameData.resource_name(RunState.weapon_ammo)], Color(0.95, 0.9, 0.7)); y += 26

	var rec := String(RunState.run_chain.get("Recycler", ""))
	var rec_mat := _recycler_material(rec)
	_line(x, y, "Recycler:  %s  →  produces %s" % [_mname(rec), GameData.resource_name(rec_mat)]); y += 24

	var am := String(RunState.run_chain.get("Ammo Maker", ""))
	var am_fam := _ammo_family(am)
	_line(x, y, "Ammo Maker:  %s  (%s)  →  %s" % [_mname(am), String(GameData.families.get(am_fam, {}).get("name", "?")), _recipe_text(am)]); y += 24

	var cm := String(RunState.run_chain.get("Component Maker", ""))
	_line(x, y, "Component Maker:  %s  →  %s" % [_mname(cm), _recipe_text(cm)]); y += 30

	_line(x, y, "Producible base materials:  %s" % (GameData.resource_name(rec_mat) if rec_mat != "" else "(none — no Recycler)")); y += 30

	# Viability of the weapon's ammo path, using ONLY the guaranteed chain.
	var reason := ""
	if RunState.weapon_family == "":
		reason = "no weapon family"
	elif am_fam != RunState.weapon_family:
		reason = "Ammo Maker is %s, weapon needs %s" % [am_fam, RunState.weapon_family]
	elif rec_mat != RunState.weapon_family:
		reason = "no Recycler makes %s (you get %s)" % [RunState.weapon_family, rec_mat]
	var viable := reason == ""
	draw_string(_font, Vector2(x, y), "Weapon has a viable ammo path:  %s" % ("YES" if viable else "NO"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 1.0, 0.6) if viable else Color(1.0, 0.5, 0.45)); y += 24
	if not viable:
		_line(x + 12, y, "why: %s" % reason, Color(1.0, 0.7, 0.6)); y += 24

	draw_string(_font, Vector2(x, PANEL.position.y + PANEL.size.y - 14), "[P] / [Esc] close", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.75))


func _line(x: float, y: float, text: String, col := Color(0.88, 0.9, 0.94)) -> void:
	draw_string(_font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, PANEL.size.x - 40, 14, col)


func _mname(def_id: String) -> String:
	if def_id == "":
		return "(none)"
	return String(GameData.machines.get(def_id, {}).get("name", def_id))


func _recycler_material(def_id: String) -> String:
	var rs := GameData.recipes_for(def_id)
	if rs.is_empty():
		return ""
	for k: String in rs[0].get("produces", {}):
		return k
	return ""


func _ammo_family(def_id: String) -> String:
	for fam: String in GameData.families:
		if String(GameData.families[fam].get("ammo_maker", "")) == def_id:
			return fam
	return ""


func _recipe_text(def_id: String) -> String:
	var rs := GameData.recipes_for(def_id)
	if rs.is_empty():
		return "(no recipe)"
	return "%s → %s" % [_ingredients(rs[0].get("needs", {})), _ingredients(rs[0].get("produces", {}))]


func _ingredients(items: Dictionary) -> String:
	var parts: Array = []
	for res: String in items:
		var n := int(items[res])
		parts.append(("%d× %s" % [n, GameData.resource_name(res)]) if n > 1 else GameData.resource_name(res))
	return " + ".join(parts)
