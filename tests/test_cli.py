"""Black-box tests for the omarchy-rgb CLI.

Every test runs the real CLI as a subprocess against a throwaway $HOME —
all of the CLI's paths derive from ~, so this isolates state, theme files
and the override toml without any mocking inside the CLI itself.

Two hardware strategies:

- Most tests set devices_none in the seeded state, the CLI's built-in
  "manage nothing" mode, so apply_state succeeds without OpenRGB.
- StubHardwareTest installs a fake `openrgb` package into the venv
  site-packages path the CLI adds to sys.path, recording every set_mode /
  set_color / save_mode call to a log file. That exercises real device
  logic (mode fallbacks, software brightness scaling) with no hardware.
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

CLI = Path(__file__).resolve().parent.parent / "bin" / "omarchy-rgb"

STUB_INIT = '''
import json, os


class _Mode:
    def __init__(self, name):
        self.name = name


class _Device:
    def __init__(self, spec, log):
        from openrgb.utils import DeviceType
        self.name = spec["name"]
        self.type = DeviceType.MOTHERBOARD
        self.modes = [_Mode(m) for m in spec["modes"]]
        self._log = log

    def _record(self, event):
        with open(self._log, "a") as f:
            f.write(json.dumps(event) + "\\n")

    def set_mode(self, mode):
        self._record({"dev": self.name, "set_mode": mode.name})

    def set_color(self, color):
        self._record({"dev": self.name,
                      "set_color": [color.red, color.green, color.blue]})

    def save_mode(self):
        self._record({"dev": self.name, "save_mode": True})


class OpenRGBClient:
    def __init__(self):
        devices = json.loads(os.environ["OPENRGB_STUB_DEVICES"])
        log = os.environ["OPENRGB_STUB_LOG"]
        self.devices = [_Device(d, log) for d in devices]

    def disconnect(self):
        pass
'''

STUB_UTILS = '''
import enum


class DeviceType(enum.Enum):
    MOTHERBOARD = 0


class RGBColor:
    def __init__(self, red, green, blue):
        self.red, self.green, self.blue = red, green, blue
'''


class CliTestCase(unittest.TestCase):
    """Shared fixture: temp $HOME with seeded state and theme files."""

    def setUp(self):
        self.home = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.env = dict(os.environ, HOME=str(self.home))
        self.state_dir = self.home / ".local/state/omarchy-rgb"
        self.state_dir.mkdir(parents=True)
        self.seed_state({"devices_none": True})
        self.theme_dir = self.home / ".local/state/omarchy/current/theme"
        self.theme_dir.mkdir(parents=True)
        self.colors_file = self.theme_dir / "colors.toml"
        self.colors_file.write_text('accent = "#112233"\n')
        self.name_file = self.home / ".local/state/omarchy/current/theme.name"
        self.name_file.write_text("testtheme\n")

    def seed_state(self, extra):
        (self.state_dir / "state.json").write_text(json.dumps(extra))

    def run_cli(self, *args, expect=0):
        result = subprocess.run([str(CLI), *args], env=self.env,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, expect,
                         f"{args}: {result.stderr or result.stdout}")
        return result

    def state(self):
        return json.loads((self.state_dir / "state.json").read_text())


class StateCommandsTest(CliTestCase):
    def test_status_seeds_defaults_and_reports(self):
        out = json.loads(self.run_cli("status").stdout)
        self.assertTrue(out["on"])
        self.assertEqual(out["brightness"], 100)
        self.assertIn("server", out)
        self.assertTrue(self.state()["devices_none"])

    def test_on_off_toggle_is_on(self):
        self.run_cli("off")
        self.assertFalse(self.state()["on"])
        self.run_cli("is-on", expect=1)
        self.run_cli("toggle")
        self.assertTrue(self.state()["on"])
        self.run_cli("is-on")

    def test_brightness_absolute_relative_clamped(self):
        self.run_cli("brightness", "40")
        self.assertEqual(self.state()["brightness"], 40)
        self.run_cli("brightness", "+30")
        self.assertEqual(self.state()["brightness"], 70)
        self.run_cli("brightness", "+90")
        self.assertEqual(self.state()["brightness"], 100)
        self.run_cli("brightness", "-200")
        self.assertEqual(self.state()["brightness"], 0)

    def test_set_color_forces_on_and_drops_follow(self):
        self.run_cli("off")
        self.run_cli("set-color", "#00FF00")
        state = self.state()
        self.assertTrue(state["on"])
        self.assertEqual(state["color"], "#00FF00")
        self.assertEqual(state["hue"], 120)
        self.assertFalse(state["follow_theme"])

    def test_set_hue(self):
        self.run_cli("set-hue", "240")
        state = self.state()
        self.assertEqual(state["hue"], 240)
        self.assertEqual(state["color"], "#0000FF")

    def test_cycle_preset_wraps(self):
        presets = json.loads(self.run_cli("status").stdout)["presets"]
        self.seed_state({"devices_none": True,
                         "preset_index": len(presets) - 1,
                         "presets": presets})
        self.run_cli("cycle-preset")
        state = self.state()
        self.assertEqual(state["preset_index"], 0)
        self.assertEqual(state["color"], presets[0])

class ThemeResolutionTest(CliTestCase):
    def test_set_theme_follows_accent_by_default(self):
        self.run_cli("set-theme")
        state = self.state()
        self.assertEqual(state["color"], "#112233")
        self.assertTrue(state["follow_theme"])

    def test_manual_color_wins_until_follow_reenabled(self):
        self.run_cli("set-color", "#ABCDEF")
        self.run_cli("set-theme")
        self.assertEqual(self.state()["color"], "#ABCDEF")
        self.run_cli("follow-theme", "on")
        self.assertEqual(self.state()["color"], "#112233")

    def test_curated_beats_accent(self):
        self.name_file.write_text("rose-pine\n")
        self.run_cli("set-theme")
        self.assertEqual(self.state()["color"], "#D7827E")

    def test_theme_rgb_table_beats_curated(self):
        self.name_file.write_text("rose-pine\n")
        self.colors_file.write_text(
            'accent = "#112233"\n\n[rgb]\nprimary = "#445566"\n')
        self.run_cli("set-theme")
        self.assertEqual(self.state()["color"], "#445566")

    def test_override_beats_theme_rgb_table(self):
        self.name_file.write_text("rose-pine\n")
        self.colors_file.write_text(
            'accent = "#112233"\n\n[rgb]\nprimary = "#445566"\n')
        self.run_cli("theme-color", "rose-pine", "#778899")
        self.run_cli("set-theme")
        self.assertEqual(self.state()["color"], "#778899")

    def test_hex_argument_is_last_ditch_fallback(self):
        self.name_file.unlink()
        self.colors_file.unlink()
        self.run_cli("set-theme", "#445566")
        self.assertEqual(self.state()["color"], "#445566")

    def test_set_theme_without_any_theme_info_is_a_noop(self):
        self.name_file.unlink()
        self.colors_file.unlink()
        before = json.loads(self.run_cli("status").stdout)["color"]
        self.run_cli("set-theme")
        self.assertEqual(self.state()["color"], before)


class ThemeColorCommandTest(CliTestCase):
    def overrides(self):
        return (self.home / ".config/omarchy-rgb/themes.toml").read_text()

    def test_set_list_unset_roundtrip(self):
        self.run_cli("theme-color", "#FF00BF")  # bare hex → current theme
        self.assertIn("[testtheme]", self.overrides())
        self.assertIn('primary = "#FF00BF"', self.overrides())
        out = self.run_cli("theme-color").stdout
        self.assertIn("testtheme: #FF00BF", out)
        self.assertIn("resolves to #FF00BF", out)
        self.run_cli("theme-color", "testtheme", "--unset")
        self.assertNotIn("[testtheme]", self.overrides())
        self.assertIn("resolves to #112233", self.run_cli("theme-color").stdout)

    def test_setting_current_theme_relights_immediately(self):
        self.run_cli("theme-color", "#AABBCC")
        self.assertEqual(self.state()["color"], "#AABBCC")

    def test_setting_other_theme_leaves_lights_alone(self):
        before = json.loads(self.run_cli("status").stdout)["color"]
        self.run_cli("theme-color", "othertheme", "#AABBCC")
        self.assertEqual(self.state()["color"], before)


class StubHardwareTest(CliTestCase):
    """Device-level behaviour through a fake openrgb package.

    The CLI prepends <data dir>/venv/lib/python*/site-packages to sys.path;
    planting the stub there means the unmodified CLI imports it exactly as
    it would the real openrgb-python.
    """

    def setUp(self):
        super().setUp()
        site = (self.home / ".local/share/omarchy-openrgb"
                / "venv/lib/python3/site-packages/openrgb")
        site.mkdir(parents=True)
        (site / "__init__.py").write_text(STUB_INIT)
        (site / "utils.py").write_text(STUB_UTILS)
        self.log = self.home / "stub-calls.jsonl"
        self.env["OPENRGB_STUB_LOG"] = str(self.log)
        self.set_devices([{"name": "Stub Board", "modes": ["Static", "Off"]}])
        self.seed_state({})  # manage real (stub) devices, not devices_none

    def set_devices(self, devices):
        self.env["OPENRGB_STUB_DEVICES"] = json.dumps(devices)

    def calls(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_static_mode_and_software_brightness_scaling(self):
        self.run_cli("brightness", "50")
        self.log.unlink()
        self.run_cli("set-color", "#FF0080")
        calls = self.calls()
        self.assertIn({"dev": "Stub Board", "set_mode": "Static"}, calls)
        self.assertIn({"dev": "Stub Board", "set_color": [128, 0, 64]}, calls)
        self.assertIn({"dev": "Stub Board", "save_mode": True}, calls)

    def test_no_save_skips_device_flash(self):
        self.run_cli("set-color", "#FF0080", "--no-save")
        self.assertNotIn({"dev": "Stub Board", "save_mode": True}, self.calls())

    def test_off_uses_native_off_mode(self):
        self.run_cli("off")
        calls = self.calls()
        self.assertIn({"dev": "Stub Board", "set_mode": "Off"}, calls)
        self.assertFalse(any("set_color" in c for c in calls))

    def test_off_falls_back_to_black_without_off_mode(self):
        self.set_devices([{"name": "Stub Board", "modes": ["Static"]}])
        self.run_cli("off")
        calls = self.calls()
        self.assertIn({"dev": "Stub Board", "set_mode": "Static"}, calls)
        self.assertIn({"dev": "Stub Board", "set_color": [0, 0, 0]}, calls)

    def test_set_device_names_and_none(self):
        self.run_cli("set-device", "Stub Board")
        state = self.state()
        self.assertEqual(state["devices"], ["Stub Board"])
        self.assertFalse(state["devices_none"])
        self.run_cli("set-device", "--none")
        state = self.state()
        self.assertEqual(state["devices"], [])
        self.assertTrue(state["devices_none"])

    def test_direct_fallback_when_no_static_mode(self):
        self.set_devices([{"name": "Stub Mouse", "modes": ["Direct"]}])
        self.run_cli("set-color", "#102030")
        self.assertIn({"dev": "Stub Mouse", "set_mode": "Direct"}, self.calls())


if __name__ == "__main__":
    unittest.main()
