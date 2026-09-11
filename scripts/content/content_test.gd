extends Control

const ATLAS_DIRECTORY := "res://content/atlases/prototype"
const TILESET_DIRECTORY := "res://content/tilesets/prototype"

@onready var atlas_grid: GridContainer = %AtlasGrid
@onready var tileset_grid: GridContainer = %TilesetGrid
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	var atlas_path := _find_first_json(ATLAS_DIRECTORY)
	var tileset_path := _find_first_json(TILESET_DIRECTORY)
	var messages: Array[String] = []
	if atlas_path.is_empty():
		messages.append("No atlas JSON found in %s" % ATLAS_DIRECTORY)
		push_error(messages[-1])
	else:
		var atlas := AtlasContent.new()
		if atlas.load_json(atlas_path):
			for sprite_name: String in atlas.get_sprite_names():
				atlas_grid.add_child(_make_preview(sprite_name, atlas.get_sprite(sprite_name)))
			messages.append("Atlas: %d sprites from %s" % [atlas.sprites.size(), atlas_path.get_file()])
		else:
			messages.append(atlas.last_error)

	if tileset_path.is_empty():
		messages.append("No tileset JSON found in %s" % TILESET_DIRECTORY)
		push_error(messages[-1])
	else:
		var tileset := TilesetContent.new()
		if tileset.load_json(tileset_path):
			for tile_name: String in tileset.get_tile_names():
				tileset_grid.add_child(_make_preview(tile_name, tileset.get_tile(tile_name)))
			messages.append("Tileset: %d tiles from %s" % [tileset.tiles.size(), tileset_path.get_file()])
		else:
			messages.append(tileset.last_error)
	status_label.text = "\n".join(messages)


func _find_first_json(directory_path: String) -> String:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		push_error("Content directory could not be opened: '%s'." % directory_path)
		return ""
	var candidates: Array[String] = []
	for file_name: String in directory.get_files():
		if file_name.get_extension().to_lower() == "json":
			candidates.append(file_name)
	candidates.sort()
	if candidates.is_empty():
		return ""
	if candidates.size() > 1:
		print("Multiple JSON files found in '%s'; loading '%s'." % [directory_path, candidates[0]])
	return directory_path.path_join(candidates[0])


func _make_preview(item_name: String, item_texture: Texture2D) -> VBoxContainer:
	var preview := VBoxContainer.new()
	preview.custom_minimum_size = Vector2(96, 80)
	var texture_rect := TextureRect.new()
	texture_rect.custom_minimum_size = Vector2(64, 56)
	texture_rect.texture = item_texture
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.add_child(texture_rect)
	var label := Label.new()
	label.text = item_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_child(label)
	return preview
