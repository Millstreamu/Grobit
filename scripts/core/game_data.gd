extends Node
## Autoload. Loads data-driven gameplay definitions from data/game/*.json.
##
## Gameplay data is deliberately kept separate from artwork JSON. Systems read
## these dictionaries instead of hard-coding balance values, so new resources,
## recipes, buildables, tech and areas can be added by editing data files.

const DATA_DIR := "res://data/game/"

var resources: Dictionary = {}
var recyclers: Dictionary = {}
var recipes: Dictionary = {}
var buildables: Dictionary = {}
var tech: Dictionary = {}
var enemies: Dictionary = {}
var abilities: Dictionary = {}
var areas: Dictionary = {}


func _ready() -> void:
	resources = _load("resources.json").get("resources", {})
	recyclers = _load("recyclers.json").get("recyclers", {})
	recipes = _load("recipes.json").get("recipes", {})
	buildables = _load("buildables.json").get("buildables", {})
	tech = _load("tech.json").get("tech", {})
	enemies = _load("enemies.json").get("enemies", {})
	abilities = _load("abilities.json").get("abilities", {})
	areas = _load("area.json").get("areas", {})


func resource_name(id: String) -> String:
	return String(resources.get(id, {}).get("name", id))


func resource_icon(id: String) -> String:
	return String(resources.get(id, {}).get("icon", id))


func resource_color(id: String) -> String:
	return String(resources.get(id, {}).get("color", ""))


func area(area_id: String) -> Dictionary:
	return areas.get(area_id, {})


func first_area_id() -> String:
	for id: String in areas:
		return id
	return ""


func _load(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		push_error("GameData missing data file: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("GameData could not open: %s" % path)
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("GameData malformed JSON '%s' at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		push_error("GameData '%s' root must be an object." % path)
		return {}
	return json.data
