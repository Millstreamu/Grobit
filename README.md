# Grobit

Grobit is a Godot 4 project for a real-time, top-down pixel-art game. This
repository includes an initial smooth-movement and basic combat prototype backed
by the external content pipeline.

## Open the project

1. Install Godot 4.x.
2. Import or open `project.godot` from the Godot Project Manager.
3. Run the project to launch `scenes/world/run.tscn` — a rough playable slice of
   the full prototype loop (generated area, combat, salvage, recycling,
   manufacturing, building, extraction and the Power Generator objective).

`scenes/test/combat_test.tscn` and the other test scenes are kept for isolated
checks of individual systems.

See [`docs/MASTER_PROTOTYPE_DIRECTION.md`](docs/MASTER_PROTOTYPE_DIRECTION.md) for
the design direction and [`docs/ARTWORK_NEEDED.md`](docs/ARTWORK_NEEDED.md) for the
list of missing sprites (the game runs with placeholders until they exist). See
[`docs/CONTENT_PIPELINE.md`](docs/CONTENT_PIPELINE.md) before adding exported
artwork.

## Controls

| Input | Action |
| --- | --- |
| — | Shooting is **automatic** — Grobit fires at the nearest/target enemy in range |
| WASD | Move (in build mode: move the placement cursor) |
| Space | Use your equipped ability (chosen at run start); in build mode: place; in menus: confirm |
| Tab | Switch shooting target (cycles enemies in range) |
| I | Open/close the grid inventory (WASD move cursor, Space select/drop; select matching resources to stack them, then drop one at a time) |
| M | Toggle manufacturing panel (number keys build recipes) |
| B | Toggle build mode (1/2 select, WASD move cursor, Space place, B/Esc exit) |
| F | Interact with the nearest object (harvest scrap, pick up drops, use a Fabricator, repair equipment, deposit at / extract) |
| Enter | Start a new run from the summary screen |

Fully keyboard-driven — no mouse required.

## Systems overview

Map shape is authored in **Grobit Config Studio** ([tools/config-studio/index.html](tools/config-studio/index.html)) — a standalone HTML tool that previews generation live and exports `data/game/generation.json`. Rooms are irregular unions of grid cells (complex shapes) packed with **no corridors**; connected rooms share carved doorways. Generated areas mix several room types (weighted, data-driven in
`data/game/area.json`): **start**, **combat** (lock + clear), **objective**
(Power Generator), **salvage** (guaranteed loot, no fight), **hazard** (combat +
a damage zone), and **spawner** (doors lock and a wave spawns; clear it to
unlock, then leaving and returning re-arms a fresh, bigger wave). A HUD
**minimap** shows room types, cleared state, your position, and the objective.

The inventory is a fixed **grid of single-item slots**, so capacity matters and a
full inventory leaves pickups on the ground until you free space. In the inventory
window, matching resources can be grouped into one temporary selection; each press
when dropping places one unit, making it easy to feed several units to a recycler.
The **Scrap Recycler is a module occupying a slot**: recycling only happens when
you move raw scrap onto it, after which it processes over time and drops the
output into a free slot. Manufacturing likewise needs a free slot for its output.

Resource loop: most rooms contain **harvestable breakdown scrap** (`ScrapNode`,
interact with F) — the main resource income. Enemies drop rarer materials, so a
run balances scrapping and fighting. **Workshop** rooms hold **broken equipment**
you can **repair** for a resource cost, granting a reward: unlock a new ability
(then choose/switch it), +max health, or a shoot upgrade. Manufacturing components
requires **building a Fabricator** (build mode → place it, then interact to craft).
Dropped resources are **not auto-collected** — press F to pick them up. Scrap
nodes, repair stations and machines are solid and grid-locked.

Combat: shooting is automatic. At the start of each run you **choose one active
ability** (EMP / Shield / Regen, data-driven in `data/game/abilities.json`) bound
to Space. Shoot upgrades layer on top — e.g. the `aegis_rounds` tech grants a 1s
shield every 3 shots. (Choosing at run start is in; mid-run switching/unlocking
and more shoot upgrades are the planned next steps.)

Enemies are data-driven (`data/game/enemies.json`): a melee grunt, a fast
swarmer, a tanky brute, and a ranged shooter that keeps its distance and fires.
Rooms spawn a weighted mix (`enemy_weights` in the area definition).

Data-driven definitions live in `data/game/` (resources, recyclers, recipes,
buildables, tech, enemies, area). Global state is split into three autoloads:
`ContentLibrary` (art + placeholders), `GameData` (definitions), `RunState`
(per-run data) and `MetaState` (permanent tech progression, saved to `user://`).
The run itself is orchestrated by `scripts/world/run_controller.gd`.

## Validation

The structural tests only use Python's standard library. The development
requirements file is intentionally empty for now, but is provided as the stable
dependency-install entry point for automated environments.

```bash
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -v
```

When a Godot 4 executable is available, validate the GDScript loaders against
the checked-in prototype artwork with:

```bash
godot --headless --path . --import
godot --headless --path . --script tests/content_loader_test.gd
godot --headless --path . --script tests/movement_test.gd
godot --headless --path . --script tests/combat_test.gd
godot --headless --path . scenes/test/inventory_selection_test.tscn
```

The first combat-loop tuning values are exported in the Inspector: enemy
`movement_speed` and `max_health`, plus player Combat `damage`, `attack_range`,
`cooldown`, and `projectile_speed`.
