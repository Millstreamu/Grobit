import configparser
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

_SECTION_RE = re.compile(r"^\[.+\]\s*$")
_KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_/.]*=")


def load_project_config():
    # Godot serialises input actions as multi-line inline dicts (containing bare
    # "]"/"}" lines and repeated "deadzone" keys) that a plain INI parser rejects.
    # Keep only section headers and top-level `key=` lines; that preserves every
    # section plus each action's `name={` line, which is all these tests inspect.
    kept = ["[project]"]  # top-level entries precede the first real section
    for line in (ROOT / "project.godot").read_text().splitlines():
        if _SECTION_RE.match(line) or _KEY_RE.match(line):
            kept.append(line)
    config = configparser.ConfigParser(strict=False)
    config.optionxform = str  # preserve case (e.g. autoload "ContentLibrary")
    config.read_string("\n".join(kept))
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
        self.assertEqual(main_scene, "res://scenes/world/run.tscn")
        self.assertTrue((ROOT / main_scene.removeprefix("res://")).is_file())

    def test_core_autoloads_are_registered(self):
        config = load_project_config()
        self.assertIn("autoload", config)
        for singleton in ("ContentLibrary", "GameData", "MetaState", "RunState"):
            with self.subTest(autoload=singleton):
                self.assertIn(singleton, config["autoload"])

    def test_prototype_gameplay_data_files_exist(self):
        import json

        for name in (
            "resources.json",
            "recyclers.json",
            "recipes.json",
            "buildables.json",
            "tech.json",
            "enemies.json",
            "abilities.json",
            "generation.json",
            "area.json",
        ):
            path = ROOT / "data" / "game" / name
            with self.subTest(data_file=name):
                self.assertTrue(path.is_file())
                # Every gameplay data file must be valid JSON.
                json.loads(path.read_text())

    def test_prototype_system_scripts_exist(self):
        expected = (
            "scripts/core/content_library.gd",
            "scripts/core/game_data.gd",
            "scripts/core/run_state.gd",
            "scripts/core/meta_state.gd",
            "scripts/core/health_component.gd",
            "scripts/player/grobit_abilities.gd",
            "scripts/world/door.gd",
            "scripts/world/room.gd",
            "scripts/world/area_generator.gd",
            "scripts/world/run_controller.gd",
            "scripts/world/hazard_zone.gd",
            "scripts/world/spawner.gd",
            "scripts/world/interactable_object.gd",
            "scripts/world/scrap_node.gd",
            "scripts/world/repair_station.gd",
            "scripts/build/build_manager.gd",
            "scripts/build/respawn_beacon.gd",
            "scripts/build/extraction_beacon.gd",
            "scripts/build/fabricator.gd",
            "scripts/machines/recycler_system.gd",
            "scripts/machines/manufacturing.gd",
            "scripts/machines/power_generator.gd",
            "scripts/ui/hud.gd",
            "scripts/ui/selector.gd",
            "scripts/ui/selection_manager.gd",
            "scripts/ui/minimap.gd",
            "scripts/ui/inventory_panel.gd",
            "scripts/ui/manufacture_panel.gd",
            "scripts/ui/ability_choice_panel.gd",
        )
        for relative_path in expected:
            with self.subTest(path=relative_path):
                self.assertTrue((ROOT / relative_path).is_file())

    def test_new_input_actions_exist(self):
        config = load_project_config()
        for action in (
            "ability_emp",
            "ability_shield",
            "ability_regen",
            "toggle_inventory",
            "toggle_build",
            "toggle_manufacture",
            "interact",
            "hotbar_1",
        ):
            with self.subTest(action=action):
                self.assertIn(action, config["input"])

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

    def test_movement_prototype_files_and_controls_exist(self):
        expected_files = (
            "scenes/player/grobit.tscn",
            "scenes/test/movement_test.tscn",
            "scripts/player/grobit.gd",
            "scripts/world/movement_test.gd",
        )
        for relative_path in expected_files:
            with self.subTest(path=relative_path):
                self.assertTrue((ROOT / relative_path).is_file())

        config = load_project_config()
        for action in ("move_up", "move_down", "move_left", "move_right"):
            with self.subTest(action=action):
                self.assertIn(action, config["input"])

    def test_basic_combat_loop_files_and_control_exist(self):
        expected_files = (
            "scenes/test/combat_test.tscn",
            "scenes/enemies/basic_enemy.tscn",
            "scenes/combat/projectile.tscn",
            "scenes/resources/scrap_pickup.tscn",
            "scripts/player/player_combat.gd",
            "scripts/enemies/basic_enemy.gd",
            "scripts/combat/projectile.gd",
            "scripts/combat/enemy_projectile.gd",
            "scripts/resources/scrap_pickup.gd",
            "scripts/core/resource_counter.gd",
        )
        for relative_path in expected_files:
            with self.subTest(path=relative_path):
                self.assertTrue((ROOT / relative_path).is_file())
        self.assertIn("attack", load_project_config()["input"])

    def test_generated_passages_use_one_shared_door(self):
        generator = (ROOT / "scripts/world/area_generator.gd").read_text()
        self.assertIn("_doorways.append([a, b, p[0], p[1]])", generator)
        self.assertEqual(generator.count("var door := Door.new()"), 1)
        self.assertIn("rooms[doorway[0]].doors.append(door)", generator)
        self.assertIn("rooms[doorway[1]].doors.append(door)", generator)

        studio = (ROOT / "tools/config-studio/index.html").read_text()
        self.assertIn("const doorFloors=new Set(),doors=[];", studio)
        self.assertIn("doors.push(sel);", studio)
        self.assertNotIn("doors.add(sel[0]", studio)

if __name__ == "__main__":
    unittest.main()
