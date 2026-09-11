extends Node
## Autoload. PERMANENT data that persists between runs.
##
## Holds banked tech_data and unlocked technologies, saved to user:// so future
## runs benefit from previous ones. Kept intentionally separate from RunState
## (per-run data) so restarting a run never touches progression.

const SAVE_PATH := "user://grobit_save.json"

signal changed()

var tech_data := 0
var unlocked: Array[String] = []


func _ready() -> void:
	load_game()


func has_tech(tech_id: String) -> bool:
	return unlocked.has(tech_id)


## Attempts to buy a tech with banked tech_data. Returns true on success.
func unlock_tech(tech_id: String) -> bool:
	if has_tech(tech_id):
		return false
	var def: Dictionary = GameData.tech.get(tech_id, {})
	if def.is_empty():
		return false
	var cost := int(def.get("cost", 0))
	if tech_data < cost:
		return false
	tech_data -= cost
	unlocked.append(tech_id)
	save_game()
	changed.emit()
	return true


func add_tech_data(amount: int) -> void:
	tech_data += amount
	save_game()
	changed.emit()


## Sums the 'value' of every unlocked tech whose effect matches. Numeric effects.
func effect_total(effect: String, default_value: float) -> float:
	var total := default_value
	for tech_id: String in unlocked:
		var def: Dictionary = GameData.tech.get(tech_id, {})
		if String(def.get("effect", "")) == effect:
			total += float(def.get("value", 0.0))
	return total


## Returns the first matching unlocked effect value, or the default.
func effect_value(effect: String, default_value: Variant) -> Variant:
	for tech_id: String in unlocked:
		var def: Dictionary = GameData.tech.get(tech_id, {})
		if String(def.get("effect", "")) == effect:
			return def.get("value", default_value)
	return default_value


func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("MetaState could not write save file.")
		return
	file.store_string(JSON.stringify({
		"tech_data": tech_data,
		"unlocked": unlocked,
	}, "  "))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_warning("MetaState save file was unreadable; ignoring.")
		return
	var data: Dictionary = json.data
	tech_data = int(data.get("tech_data", 0))
	unlocked.clear()
	for id: Variant in data.get("unlocked", []):
		unlocked.append(String(id))
