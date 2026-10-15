class_name LairStation
extends InteractableObject
## Phase 1 — a buildable LAIR STATION. The single System Terminal is gone; the lair is now built from
## these separate stations (Workshop, Mission Board, Goblin Quarters, Upgrade Bench, Process Line,
## Fabricator, Component Exchange). You place/move/remove them in build mode ([B]); interacting ([F])
## opens that station's focused panel. Definitions (name/icon/colour/cost/panel) live in
## data/game/stations.json; a missing icon falls back to a coloured square (art never blocks).

var station_type := ""


func _configure() -> void:
	add_to_group("lair_stations")
	var def: Dictionary = GameData.stations.get(station_type, {})
	_sprite_id = String(def.get("icon", "station_" + station_type))
	_sprite_color = String(def.get("color", "5aa9e6"))
	solid_size = Vector2(30, 30)
	interact_radius = 34.0


func can_interact() -> bool:
	return _in_range


func interaction_prompt() -> String:
	var def: Dictionary = GameData.stations.get(station_type, {})
	return "[F] %s — %s" % [String(def.get("name", station_type.capitalize())), String(def.get("desc", ""))]


func interact() -> void:
	for hud: Node in get_tree().get_nodes_in_group("hud"):
		if hud.has_method("open_station"):
			hud.open_station(station_type)
			return
