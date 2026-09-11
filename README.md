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
| WASD | Move |
| Space / Left mouse | Shoot (auto-targets nearest enemy) |
| E / Q / R | EMP / Shield / Regen abilities |
| I | Toggle inventory |
| M | Toggle manufacturing panel (number keys build recipes) |
| B | Toggle build mode (1/2 select, left click place, B/Esc exit) |
| F | Interact (repair generator, extract) |
| Enter | Start a new run from the summary screen |

## Systems overview

Data-driven definitions live in `data/game/` (resources, recyclers, recipes,
buildables, tech, area). Global state is split into three autoloads:
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
```

The first combat-loop tuning values are exported in the Inspector: enemy
`movement_speed` and `max_health`, plus player Combat `damage`, `attack_range`,
`cooldown`, and `projectile_speed`.
