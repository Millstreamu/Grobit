# ARTWORK NEEDED

The prototype runs with **auto-generated coloured placeholders** for any missing
art, so nothing below blocks gameplay. Each item just needs a sprite added to the
prototype atlas (`content/atlases/prototype/prototype_atlas.png` + `.json`) using
the **exact sprite id** shown, so gameplay code picks it up automatically.

At runtime the game also prints a live `ARTWORK NEEDED` list to the Output/console
listing whatever placeholders were actually used that session.

## Still needed (gameplay)

Salvage economy (see docs/MACHINES_SCRAPABLES_RESOURCES.md). Everything renders as a
coloured placeholder until a matching sprite id is added.

**Grid machines (28×28):** `scrapper_arm`, `scrap_recycler`, `grinder`, `separator`,
`smelter`, `press`, `refiner`, `circuit_printer`, `constructor`, `assembler`,
`storage_cache` (stacks 16 of one item; ships the whole stack in one cartridge slot).

**NEW 4-material economy (16×16):** `junk` (generic salvage), `copper`, `steel`, `plastic`, `ceramic`.

**NEW typed scrap (16×16):** `scrap_copper`, `scrap_steel`, `scrap_plastic`, `scrap_ceramic` — the harvested scrap each recycler eats (from the matching scrap pile). Tint toward the parent material. Also used in the Scrapper Arm bar (top of the inventory) and on Scrap Insert points.

**NEW Scrap Insert point (optional frame, ~36×36):** `scrap_insert` — a 2-tall source machine built with [B]; the top tile is the emitter (currently drawn as the scrap icon + a ▼). A dedicated frame/housing sprite would read better than the bare scrap icon.

**NEW typed scrap piles (world nodes, ~26×26):** `scrap_copper`, `scrap_steel`, `scrap_plastic`, `scrap_ceramic` are reused as pile sprites too — a scrap heap coloured for its material. (The old generic `scrap_node` sprite is still used for debug loot.)

**NEW recycler icons (28×28):** `recycler_copper`, `recycler_steel`, `recycler_plastic`, `recycler_ceramic` (a broken Recycler repairs into one of these).

**NEW ammo (16×16):** `charge_cells`, `steel_slugs`, `resin_capsules`, `ceramic_charges` (one per family).

**NEW ammo-maker icons (28×28):** `ammo_maker_copper`, `ammo_maker_steel`, `ammo_maker_plastic`, `ammo_maker_ceramic`.

**NEW weapon icons (28×28):** `weapon_copper`, `weapon_steel`, `weapon_plastic`, `weapon_ceramic` — repairable weapons found broken in rooms; each is placed in the inventory with an ammo input slot and eats its family's ammo (copper→charge_cells, steel→steel_slugs, plastic→resin_capsules, ceramic→ceramic_charges).

**NEW components (16×16):** `power_coupling`, `control_assembly`, `reinforced_frame`, `thermal_core`.

**NEW component-maker icons (28×28):** `comp_maker_coupling`, `comp_maker_control`, `comp_maker_frame`, `comp_maker_thermal`.

**Junk items (16×16, harvested):** `bent_panel`, `cable_bundle`, `burnt_board`,
`broken_motor`.

**Materials/processed/components (16×16):** `mixed_components`, `scrap_metal`,
`copper_wire`, `electronic_scrap`, `polymer`, `mechanical_parts`, `metal_bar`,
`metal_plate`, `refined_copper`, `polymer_sheet`, `circuit_board`, `motor`,
`structural_frame`, `control_unit`, `tech_data`.

**Modules (24×24):** `module_overclock`, `module_precision`, `module_yield`,
`module_turbo`.

**World stations / nodes (30×30 / ~20×20):** `scrap_node`, `e_waste_node`,
`repair_station`, `objective_terminal`, `retrieval_pad`, `decode_station`,
`respawn_beacon`, `power_relay` (buildable that lights up its room), `fabricator` (in-room workbench that crafts transport/caches), `component_exchange` (now spawns out in the map, gives 1 machine then goes dormant), `scrapbot` (the goblin's machine parked at the lair's exit — [F] to hop in & drive out, and again to extract; non-solid; ~30×30, wants a proper "parked mech" look), `system_terminal` (found in the map: upload Tech Data to the base & buy permanent machine upgrades).

**Enemies / hazards:** `enemy_swarmer` (12×12), `enemy_brute` (26×26),
`enemy_shooter` (18×18), `enemy_shot` (8×8), `wall_spawner` (32×32),
`hazard_zone` (~80×80).

## UI art (nice-to-have — panels currently use plain coloured squares)

Wanted for the grid inventory + manufacturing screens. Until these exist the
panels draw flat rectangles, so they're optional, not blocking.

| Sprite id (must match) | Suggested size | Used for |
| --- | --- | --- |
| `rust` | ~40×40 | Scrapping minigame: rust marker shown over a rusted 2×2 slot (a corner badge overlays the charges-to-expose number). Currently an orange placeholder |
| `filter` | 28×28 | Filter conveyor buildable icon (routes one item type out the 90° side). Currently a coloured placeholder; the cell also draws its arrows + filtered-item icon in code |
| `machine_crate` | 24×24 | The generic "unknown machine" crate shown for EVERY machine/transport pickup found in a room (conveyors/splitters/filters are now found broken too) — you only learn which it is from the F prompt. Currently a grey placeholder |
| `ui_slot` | 54×54 | Empty inventory / recipe cell background |
| `ui_slot_module` | 54×54 | Recycler / module slot background (distinct from a normal cell) |
| `ui_panel_bg` | ~560×400 | Full-window panel background (inventory & manufacturing) |
| `recycler` | 16×16 | Dedicated recycler module icon (currently reuses `scrap_metal`) |
| `ability_emp` | 24×24 | Ability card / HUD icon (EMP) — cards are text-only for now |
| `ability_shield` | 24×24 | Ability card / HUD icon (Shield) |
| `ability_regen` | 24×24 | Ability card / HUD icon (Regen) |

All render as coloured placeholders until added to `grobit_atlas.json` with the
matching id. (If you add `ui_slot` / `ui_panel_bg` I'll wire the panels to use
them instead of the flat squares.)

## Already covered (no action needed)

- Player: `grobit` (from `grobit_atlas`, drawn facing up) — the driven scrapbot out in the run
- Lair goblin: `goblin` (16×16, from `content/atlases/Goblin.png`, loaded as a loose sprite) — the on-foot character in the lair; drawn upright and flipped L/R, with a code-driven hop (no walk frames needed)
- Gun overlay: `grobit_gun_01` (mounted on Grobit, aims at the shot target)
- Enemy: `enemy_basic` (16×16, non-directional — never rotated)
- Resources: `raw_material` (raw_scrap), `scrap_metal` (metal), `electronics`, `power_cell`, `tech_data`
- Buildables/objective: `respawn_beacon`, `extraction_beacon`, `power_generator`
- Tiles: `floor_clean`, `wall`, `door_closed`, `door_open`

## Selection brackets (`selection_16/32/64`) — now wired

Driven by the reusable `Selector` component (`scripts/ui/selector.gd`), which picks
the smallest bracket that fits a target's size. Live users:

- `SelectionManager` (`scripts/ui/selection_manager.gd`) highlights the current aim
  target and the nearest in-range interactable (sized via each object's
  `selection_size()`).
- `BuildManager` brackets the placement tile (green = valid, red = invalid).

To add more selection visuals later (target picker, inventory slot, build menu),
reuse `Selector` or the `selection_*` sprites directly.

Atlases are merged by `ContentLibrary` in priority order (see `ATLAS_PATHS`):
`grobit_atlas` first, then `prototype_atlas`, so shared ids (`grobit`, `enemy_basic`,
`scrap_metal`, `electronics`) use the newer sheet.

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
