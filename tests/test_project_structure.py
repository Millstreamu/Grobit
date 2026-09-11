import configparser
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_project_config():
    config = configparser.ConfigParser()
    # Godot's top-level config_version entry precedes its INI-style sections.
    config.read_string("[project]\n" + (ROOT / "project.godot").read_text())
    return config


class ProjectStructureTests(unittest.TestCase):
    def test_expected_directories_exist(self):
        expected = (
            "content/tilesets/prototype",
            "content/atlases/prototype",
            "data/game",
            "scenes/player",
            "scenes/enemies",
            "scenes/world",
            "scenes/ui",
            "scenes/test",
            "scripts/core",
            "scripts/content",
            "scripts/player",
            "scripts/enemies",
            "scripts/world",
            "scripts/ui",
            "docs",
        )
        for relative_path in expected:
            with self.subTest(path=relative_path):
                self.assertTrue((ROOT / relative_path).is_dir())

    def test_main_scene_exists_and_is_configured(self):
        config = load_project_config()
        main_scene = config["application"]["run/main_scene"].strip('"')
        self.assertEqual(main_scene, "res://scenes/test/content_test.tscn")
        self.assertTrue((ROOT / main_scene.removeprefix("res://")).is_file())

    def test_canvas_textures_default_to_nearest_filtering(self):
        config = load_project_config()
        self.assertEqual(
            config["rendering"]["textures/canvas_textures/default_texture_filter"],
            "0",
        )

    def test_external_content_loaders_and_debug_scene_exist(self):
        expected_scripts = (
            "scripts/content/atlas_content.gd",
            "scripts/content/tileset_content.gd",
            "scripts/content/content_test.gd",
        )
        for relative_path in expected_scripts:
            with self.subTest(path=relative_path):
                self.assertTrue((ROOT / relative_path).is_file())

        scene = (ROOT / "scenes/test/content_test.tscn").read_text()
        self.assertIn('path="res://scripts/content/content_test.gd"', scene)
        self.assertIn('name="AtlasGrid"', scene)
        self.assertIn('name="TilesetGrid"', scene)

    def test_loader_fixtures_are_text_only(self):
        fixture_files = (ROOT / "tests/fixtures").iterdir()
        binary_suffixes = {".png", ".jpg", ".jpeg", ".webp"}
        self.assertFalse(
            [path.name for path in fixture_files if path.suffix.lower() in binary_suffixes]
        )


if __name__ == "__main__":
    unittest.main()
