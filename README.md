# Grobit

Grobit is a Godot 4 project for a real-time, top-down pixel-art game. This
repository currently contains only the project skeleton and content-pipeline
conventions; gameplay has not yet been implemented.

## Open the project

1. Install Godot 4.x.
2. Import or open `project.godot` from the Godot Project Manager.
3. Run the project to launch the temporary `content_test.tscn` main scene.

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

When a Godot 4 executable is available, validate the GDScript loaders and their
test artwork with:

```bash
godot --headless --path . --import
godot --headless --path . --script tests/content_loader_test.gd
```
