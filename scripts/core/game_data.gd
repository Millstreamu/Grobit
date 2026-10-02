extends Node
## Autoload. Loads data-driven gameplay definitions from data/game/*.json.
##
## Gameplay data is deliberately kept separate from artwork JSON. Systems read
## these dictionaries instead of hard-coding balance values, so new resources,
## recipes, buildables, tech and areas can be added by editing data files.

const DATA_DIR := "res://data/game/"

var resources: Dictionary = {}
var recipes: Array = []  # list of grid-machine recipes (see recipes.json)
var buildables: Dictionary = {}
var tech: Dictionary = {}
var enemies: Dictionary = {}
var abilities: Dictionary = {}
var machines: Dictionary = {}
var modules: Dictionary = {}
var generation: Dictionary = {}
var areas: Dictionary = {}
var families: Dictionary = {}  # material family -> {name, letter, ammo, ammo_maker}


func _ready() -> void:
	resources = _load("resources.json").get("resources", {})
	recipes = _load("recipes.json").get("recipes", [])
	buildables = _load("buildables.json").get("buildables", {})
	tech = _load("tech.json").get("tech", {})
	enemies = _load("enemies.json").get("enemies", {})
	abilities = _load("abilities.json").get("abilities", {})
	# Factory machines that live in the inventory grid (inventory-factory redesign).
	machines = _load("machines.json").get("machines", {})
	modules = _load("modules.json").get("modules", {})
	# Map-shape parameters authored in the Config Studio tool (optional file).
	generation = _load("generation.json").get("generation", {})
	areas = _load("area.json").get("areas", {})
	families = _load("families.json").get("families", {})


func resource_name(id: String) -> String:
	return String(resources.get(id, {}).get("name", id))


func resource_icon(id: String) -> String:
	return String(resources.get(id, {}).get("icon", id))


func resource_color(id: String) -> String:
	return String(resources.get(id, {}).get("color", ""))


## How many of this resource fit in one inventory cell (1 = no stacking). Ammo stacks to
## 16, tier-1 components to 8, tier-2 components to 4 (set per resource in resources.json).
func stack_max(id: String) -> int:
	return maxi(1, int(resources.get(id, {}).get("stack", 1)))


## Recipes that run on a given machine id (in list order — first satisfied wins).
func recipes_for(machine_id: String) -> Array:
	var out: Array = []
	for recipe: Dictionary in recipes:
		if String(recipe.get("machine", "")) == machine_id:
			out.append(recipe)
	return out


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
