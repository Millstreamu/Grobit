extends Node
## Autoload. Central access to prototype artwork with graceful placeholders.
##
## Gameplay code asks for an icon or tile by its stable content id. If the
## artwork exists in the loaded atlas/tileset it is returned; otherwise a simple
## generated placeholder is produced and the missing id is recorded so it can be
## reported (see docs/ ARTWORK NEEDED output on startup).

const ATLAS_PATH := "res://content/atlases/prototype/prototype_atlas.json"
const TILESET_PATH := "res://content/tilesets/prototype/prototype_environment.json"

var atlas := AtlasContent.new()
var tileset := TilesetContent.new()
var _placeholder_cache: Dictionary = {}
var _missing: Dictionary = {}


func _ready() -> void:
	if not atlas.load_json(ATLAS_PATH):
		push_error("ContentLibrary could not load atlas: %s" % atlas.last_error)
	if not tileset.load_json(TILESET_PATH):
		push_error("ContentLibrary could not load tileset: %s" % tileset.last_error)


## Returns an icon texture for the given atlas sprite id, or a placeholder.
func get_icon(icon_id: String, size := Vector2i(16, 16), color_hex := "") -> Texture2D:
	if not icon_id.is_empty() and atlas.sprites.has(icon_id):
		return atlas.get_sprite(icon_id)
	_record_missing(icon_id, size)
	return _placeholder(icon_id, size, color_hex)


## Returns a tile texture for the given tileset tile id, or a placeholder.
func get_tile(tile_id: String, size := Vector2i(32, 32), color_hex := "") -> Texture2D:
	if not tile_id.is_empty() and tileset.tiles.has(tile_id):
		return tileset.get_tile(tile_id)
	_record_missing(tile_id, size)
	return _placeholder(tile_id, size, color_hex)


func has_icon(icon_id: String) -> bool:
	return atlas.sprites.has(icon_id)


func missing_ids() -> Array:
	return _missing.keys()


func missing_report() -> Array:
	var lines: Array = []
	for id: String in _missing:
		var s: Vector2i = _missing[id]
		lines.append("%s  (%dx%d)" % [id, s.x, s.y])
	lines.sort()
	return lines


func print_missing_report() -> void:
	var report := missing_report()
	if report.is_empty():
		return
	print("\n==== ARTWORK NEEDED (placeholders in use) ====")
	for line: String in report:
		print("  - " + line)
	print("=============================================\n")


func _record_missing(id: String, size: Vector2i) -> void:
	if id.is_empty():
		return
	if not _missing.has(id):
		_missing[id] = size


func _placeholder(id: String, size: Vector2i, color_hex: String) -> Texture2D:
	var key := "%s:%dx%d:%s" % [id, size.x, size.y, color_hex]
	if _placeholder_cache.has(key):
		return _placeholder_cache[key]
	var fill := Color.MAGENTA
	if not color_hex.is_empty():
		fill = Color.html(color_hex)
	elif not id.is_empty():
		fill = Color.from_hsv(float(hash(id) % 360) / 360.0, 0.55, 0.85)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(fill)
	# A darker 1px border makes overlapping placeholders readable.
	var border := fill.darkened(0.45)
	for x in size.x:
		image.set_pixel(x, 0, border)
		image.set_pixel(x, size.y - 1, border)
	for y in size.y:
		image.set_pixel(0, y, border)
		image.set_pixel(size.x - 1, y, border)
	var texture := ImageTexture.create_from_image(image)
	_placeholder_cache[key] = texture
	return texture
