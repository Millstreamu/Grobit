# Content pipeline

Grobit's artwork originates in an external pixel-art application. Keep every
exported PNG beside its matching JSON metadata file so that future content code
can discover and interpret the pair without requiring atlas regions or tiles to
be recreated manually in Godot.

## Tilesets

Place tileset PNG/JSON pairs in `res://content/tilesets/`. Prototype exports go
in `res://content/tilesets/prototype/`, for example:

```text
prototype_environment.png
prototype_environment.json
```

Both files in a pair should have the same base filename. Preserve the JSON
format emitted by the art application; it is source data for the future tileset
loader.

## Atlases

Place atlas PNG/JSON pairs in `res://content/atlases/`. Prototype exports go in
`res://content/atlases/prototype/`, for example:

```text
prototype_atlas.png
prototype_atlas.json
```

Both files in a pair should have the same base filename. Treat exported atlas
JSON as source data rather than manually duplicating its sprite regions inside
Godot.

## Runtime loading

`AtlasContent` and `TilesetContent` in `res://scripts/content/` load the export
metadata directly. Image paths are resolved relative to the JSON file, so an
exported pair remains portable as long as both files stay together. The test
scene automatically loads the alphabetically first JSON file in each prototype
directory and displays every named entry.

Atlas `sprites` are expected to be an object keyed by sprite name. Tilesets may
represent `tiles` either as an object keyed by tile name or as an array whose
entries contain `name`; an unnamed array entry falls back to its index as its
debug name. Tile indices are zero-based and advance left-to-right, then
top-to-bottom. `padding` is the outer image inset on every side and `spacing` is
the gap between adjacent tiles. All tile fields are retained, including terrain,
corner, and collision fields, without interpreting them as gameplay data.

## Artwork metadata and game data

Keep gameplay data separate from artwork metadata wherever practical. An atlas
can identify a sprite as `scrap_metal`, while a separate file under
`res://data/game/` will eventually describe its gameplay behavior. Exported art
JSON should continue to describe the source artwork, not game rules.
