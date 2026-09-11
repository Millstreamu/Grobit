extends SceneTree


func _initialize() -> void:
	var atlas := AtlasContent.new()
	assert(atlas.load_json("res://tests/fixtures/atlas.json"), atlas.last_error)
	assert(atlas.get_sprite_names() == ["top_left", "bottom_right"])
	assert(atlas.get_sprite("top_left").region == Rect2(0, 0, 3, 2))
	assert(atlas.get_sprite_data("bottom_right").kind == "effect")

	var tileset := TilesetContent.new()
	assert(tileset.load_json("res://tests/fixtures/tileset.json"), tileset.last_error)
	assert(tileset.tile_width == 2 and tileset.tile_height == 2)
	assert(tileset.get_tile("floor_nw").region == Rect2(1, 1, 2, 2))
	assert(tileset.get_tile("floor_se").region == Rect2(4, 4, 2, 2))
	assert(tileset.get_tile_data("floor_nw").collision.size() == 2)
	var corners: Array = tileset.get_tile_data("floor_nw").corners
	assert(corners.size() == 4 and corners[0] == 1 and corners[3] == 1)
	assert(tileset.terrains[0].name == "floor")
	print("Content loader integration tests passed.")
	quit()
