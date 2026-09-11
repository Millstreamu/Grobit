extends SceneTree


func _initialize() -> void:
	var prototype_atlas := AtlasContent.new()
	assert(prototype_atlas.load_json("res://content/atlases/prototype/prototype_atlas.json"), prototype_atlas.last_error)
	assert(prototype_atlas.image_path.ends_with("prototype_atlas.png"))
	assert(prototype_atlas.get_sprite_names().size() == 5)
	assert(prototype_atlas.get_sprite("grobit").region == Rect2(0, 0, 32, 32))

	var prototype_tileset := TilesetContent.new()
	assert(prototype_tileset.load_json("res://content/tilesets/prototype/prototype_environment.json"), prototype_tileset.last_error)
	assert(prototype_tileset.image_path.ends_with("prototype_environment.png"))
	assert(prototype_tileset.get_tile_names().size() == 6)
	assert(prototype_tileset.tile_width == 32 and prototype_tileset.tile_height == 32)
	assert(prototype_tileset.count == 6 and prototype_tileset.columns == 4)
	assert(prototype_tileset.spacing == 0 and prototype_tileset.padding == 0)
	assert(prototype_tileset.get_tile("door_open").region == Rect2(32, 32, 32, 32))
	assert(prototype_tileset.get_tile_data("wall").collision == true)
	assert(prototype_tileset.get_tile_data("wall").corners == ["wall", "wall", "wall", "wall"])
	assert(prototype_tileset.terrains == ["floor", "wall"])
	print("Content loader integration tests passed.")
	quit()
