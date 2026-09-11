class_name AtlasContent
extends RefCounted

## Parsed, artwork-only representation of an exported sprite atlas.

var source_path := ""
var image_path := ""
var texture: Texture2D
var sprites: Dictionary = {}
var last_error := ""


func load_json(json_path: String) -> bool:
	_clear()
	source_path = json_path
	var document := _read_document(json_path)
	if not last_error.is_empty():
		return false

	if not document.has("image") or not document.image is String or document.image.is_empty():
		return _fail("Atlas JSON '%s' is missing a non-empty 'image' field." % json_path)
	image_path = json_path.get_base_dir().path_join(document.image)
	texture = load(image_path) as Texture2D
	if texture == null:
		return _fail("Atlas PNG '%s' referenced by '%s' could not be loaded." % [image_path, json_path])

	if not document.has("sprites") or not document.sprites is Dictionary:
		return _fail("Atlas JSON '%s' is missing a 'sprites' object." % json_path)
	for sprite_name: Variant in document.sprites:
		var entry: Variant = document.sprites[sprite_name]
		if not entry is Dictionary:
			return _fail("Sprite '%s' in '%s' must be an object." % [sprite_name, json_path])
		for coordinate: String in ["x", "y", "w", "h"]:
			if not entry.has(coordinate) or not entry[coordinate] is float and not entry[coordinate] is int:
				return _fail("Sprite '%s' in '%s' is missing numeric '%s'." % [sprite_name, json_path, coordinate])
		var region := Rect2i(int(entry.x), int(entry.y), int(entry.w), int(entry.h))
		if region.size.x <= 0 or region.size.y <= 0:
			return _fail("Sprite '%s' in '%s' has an invalid size %s." % [sprite_name, json_path, region.size])
		if region.position.x < 0 or region.position.y < 0 or region.end.x > texture.get_width() or region.end.y > texture.get_height():
			return _fail("Sprite '%s' region %s falls outside PNG '%s'." % [sprite_name, region, image_path])
		var atlas_texture := AtlasTexture.new()
		atlas_texture.atlas = texture
		atlas_texture.region = region
		sprites[String(sprite_name)] = {
			"x": region.position.x,
			"y": region.position.y,
			"w": region.size.x,
			"h": region.size.y,
			"kind": entry.get("kind", ""),
			"texture": atlas_texture,
		}
	return true


func get_sprite(sprite_name: String) -> AtlasTexture:
	if not sprites.has(sprite_name):
		push_error("Atlas '%s' does not contain sprite '%s'." % [source_path, sprite_name])
		return null
	return sprites[sprite_name].texture as AtlasTexture


func get_sprite_data(sprite_name: String) -> Dictionary:
	if not sprites.has(sprite_name):
		push_error("Atlas '%s' does not contain sprite '%s'." % [source_path, sprite_name])
		return {}
	return sprites[sprite_name].duplicate()


func get_sprite_names() -> Array[String]:
	var names: Array[String] = []
	for sprite_name: String in sprites:
		names.append(sprite_name)
	return names


func _read_document(json_path: String) -> Dictionary:
	if not FileAccess.file_exists(json_path):
		_fail("Atlas JSON file does not exist: '%s'." % json_path)
		return {}
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		_fail("Atlas JSON '%s' could not be opened (error %s)." % [json_path, FileAccess.get_open_error()])
		return {}
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		_fail("Malformed atlas JSON '%s' at line %d: %s" % [json_path, json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		_fail("Atlas JSON '%s' must contain an object at its root." % json_path)
		return {}
	return json.data


func _clear() -> void:
	source_path = ""
	image_path = ""
	texture = null
	sprites.clear()
	last_error = ""


func _fail(message: String) -> bool:
	last_error = message
	push_error(message)
	return false
