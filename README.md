# Grobit

Grobit is a Godot 4 project for a real-time, top-down pixel-art game. This
repository includes an initial smooth-movement and basic combat prototype backed
by the external content pipeline.

## Open the project

1. Install Godot 4.x.
2. Import or open `project.godot` from the Godot Project Manager.
3. Run the project to launch `combat_test.tscn`. Move Grobit with WASD and use
   Space or the left mouse button to fire at the nearest enemy in range.

See [`docs/CONTENT_PIPELINE.md`](docs/CONTENT_PIPELINE.md) before adding exported
artwork.

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
