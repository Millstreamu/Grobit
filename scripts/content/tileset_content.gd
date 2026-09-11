class_name TilesetContent
extends RefCounted

## Parsed, artwork-only representation of an exported tile sheet.

var source_path := ""
var image_path := ""
var texture: Texture2D
var tile_width := 0
var tile_height := 0
var count := 0
var columns := 0
var spacing := 0
var padding := 0
var terrains: Variant = []
var tiles: Dictionary = {}
var last_error := ""


func load_json(json_path: String) -> bool:
	_clear()
	source_path = json_path
	var document := _read_document(json_path)
	if not last_error.is_empty():
		return false
	if not document.has("image") or not document.image is String or document.image.is_empty():
		return _fail("Tileset JSON '%s' is missing a non-empty 'image' field." % json_path)
	for field: String in ["tileWidth", "tileHeight", "count", "columns", "spacing", "padding"]:
		if not document.has(field) or not document[field] is float and not document[field] is int:
			return _fail("Tileset JSON '%s' is missing numeric '%s'." % [json_path, field])

	image_path = json_path.get_base_dir().path_join(document.image)
	texture = load(image_path) as Texture2D
	if texture == null:
		return _fail("Tileset PNG '%s' referenced by '%s' could not be loaded." % [image_path, json_path])
	tile_width = int(document.tileWidth)
	tile_height = int(document.tileHeight)
	count = int(document.count)
	columns = int(document.columns)
	spacing = int(document.spacing)
	padding = int(document.padding)
	if tile_width <= 0 or tile_height <= 0 or count < 0 or columns <= 0 or spacing < 0 or padding < 0:
		return _fail("Tileset JSON '%s' contains invalid dimensions, count, columns, spacing, or padding." % json_path)
	terrains = document.get("terrains", []).duplicate(true)
	if not document.has("tiles") or not document.tiles is Dictionary and not document.tiles is Array:
		return _fail("Tileset JSON '%s' is missing a 'tiles' object or array." % json_path)

	if document.tiles is Dictionary:
		for tile_name: Variant in document.tiles:
			if not _add_tile(String(tile_name), document.tiles[tile_name]):
				return false
	else:
		for entry: Variant in document.tiles:
			if not entry is Dictionary:
				return _fail("A tile in '%s' is not an object." % json_path)
			var tile_name := String(entry.get("name", entry.get("index", "")))
			if tile_name.is_empty() or not _add_tile(tile_name, entry):
				return false
	return true


func get_tile(tile_name: String) -> AtlasTexture:
	if not tiles.has(tile_name):
		push_error("Tileset '%s' does not contain tile '%s'." % [source_path, tile_name])
		return null
	return tiles[tile_name].texture as AtlasTexture


func get_tile_data(tile_name: String) -> Dictionary:
	if not tiles.has(tile_name):
		push_error("Tileset '%s' does not contain tile '%s'." % [source_path, tile_name])
		return {}
	return tiles[tile_name].duplicate(true)


func get_tile_names() -> Array[String]:
	var names: Array[String] = []
	for tile_name: String in tiles:
		names.append(tile_name)
	return names


func _add_tile(tile_name: String, value: Variant) -> bool:
	if not value is Dictionary:
		return _fail("Tile '%s' in '%s' must be an object." % [tile_name, source_path])
	if not value.has("index") or not value.index is float and not value.index is int:
		return _fail("Tile '%s' in '%s' is missing numeric 'index'." % [tile_name, source_path])
	var index := int(value.index)
	if index < 0 or index >= count:
		return _fail("Tile '%s' in '%s' has invalid index %d (count is %d)." % [tile_name, source_path, index, count])
	var column := index % columns
	var row := floori(float(index) / columns)
	var region := Rect2i(
		padding + column * (tile_width + spacing),
		padding + row * (tile_height + spacing),
		tile_width,
		tile_height
	)
	if region.end.x > texture.get_width() or region.end.y > texture.get_height():
		return _fail("Tile '%s' region %s falls outside PNG '%s'." % [tile_name, region, image_path])
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = texture
	atlas_texture.region = region
	var metadata: Dictionary = value.duplicate(true)
	metadata["index"] = index
	metadata["kind"] = value.get("kind", "")
	metadata["collision"] = value.get("collision", value.get("collisions", null))
	metadata["texture"] = atlas_texture
	tiles[tile_name] = metadata
	return true


func _read_document(json_path: String) -> Dictionary:
	if not FileAccess.file_exists(json_path):
		_fail("Tileset JSON file does not exist: '%s'." % json_path)
		return {}
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		_fail("Tileset JSON '%s' could not be opened (error %s)." % [json_path, FileAccess.get_open_error()])
		return {}
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		_fail("Malformed tileset JSON '%s' at line %d: %s" % [json_path, json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		_fail("Tileset JSON '%s' must contain an object at its root." % json_path)
		return {}
	return json.data


func _clear() -> void:
	source_path = ""
	image_path = ""
	texture = null
	tile_width = 0
	tile_height = 0
	count = 0
	columns = 0
	spacing = 0
	padding = 0
	terrains = []
	tiles.clear()
	last_error = ""


func _fail(message: String) -> bool:
	last_error = message
	push_error(message)
	return false
