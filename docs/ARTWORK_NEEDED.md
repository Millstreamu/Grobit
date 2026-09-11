# ARTWORK NEEDED

The prototype runs with **auto-generated coloured placeholders** for any missing
art, so nothing below blocks gameplay. Each item just needs a sprite added to the
prototype atlas (`content/atlases/prototype/prototype_atlas.png` + `.json`) using
the **exact sprite id** shown, so gameplay code picks it up automatically.

At runtime the game also prints a live `ARTWORK NEEDED` list to the Output/console
listing whatever placeholders were actually used that session.

## Atlas sprites to add

| Sprite id (must match) | Suggested size | Used for |
| --- | --- | --- |
| `power_cell` | 16×16 | Manufactured component + inventory/recipe icon |
| `circuit_board` | 16×16 | Manufactured component + inventory/recipe icon |
| `tech_data` | 16×16 | Permanent-progression pickup + inventory icon |
| `respawn_beacon` | 24×24 | Respawn Beacon buildable (world sprite + build ghost) |
| `extraction_beacon` | 28×28 | Extraction Beacon buildable (world sprite + build ghost) |
| `power_generator` | 48×48 | The area's broken machine (repair objective) |

## Already covered (no action needed)

- Player: `grobit`
- Enemy: `enemy_basic`
- Raw resources: `raw_material` (raw_scrap), `scrap_metal` (metal), `electronics`
- Tiles: `floor_clean`, `wall`, `door_closed`, `door_open`

## Nice-to-have later (not required for the loop)

- Extra enemy variants (add ids under the area's `enemies` list in `data/game/area.json`).
- Distinct icons for each recycler/recipe if you don't want to reuse resource icons.
- A dedicated floor/wall variant set per area (the generator already reads tile
  ids from the area definition, so new tilesets slot in without code changes).

## How the ids connect to data

- Resource/component icons come from `data/game/resources.json` → each entry's `icon`.
- Buildable icons come from `data/game/buildables.json` → each entry's `icon`.
- The generator's tiles come from `data/game/area.json` → `floor_tile` / `wall_tile`
  / `door_closed_tile` / `door_open_tile`.

Change an `icon`/tile id in those files and the code follows it — you never have to
recreate atlas regions inside Godot.
