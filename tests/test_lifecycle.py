from __future__ import annotations

import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

PKG = pathlib.Path(__file__).resolve().parents[1]


def run_script(script: str, env: dict[str, str]):
    e = os.environ.copy()
    e.update(env)
    return subprocess.run(
        ["/bin/sh", str(PKG / script)],
        cwd=PKG,
        env=e,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def fake_python(path: pathlib.Path):
    path.write_text(
        "#!/bin/sh\n"
        "if [ \"$1\" = '-' ]; then shift; exec \"%s\" - \"$@\"; fi\n"
        "exec \"%s\" \"$@\"\n" % (sys.executable, sys.executable),
        encoding="utf-8",
    )
    path.chmod(0o755)


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.tmp = pathlib.Path(self.td.name)
        self.mod = self.tmp / "mod_data"
        self.mod.mkdir()
        (self.mod / "plugins.cfg").write_text(
            "[include plugins/flook32/flook32.cfg]\n", encoding="utf-8"
        )
        (self.mod / "user.cfg").write_text(
            "[include plugins/flook32/flook32.cfg]\n", encoding="utf-8"
        )
        power = self.mod / "power_on.sh"
        power.write_text(
            "#!/bin/sh\n"
            "echo keep-before\n"
            "# >>> FLOOK32_BOOT_ENSURE >>>\n"
            "legacy\n"
            "# <<< FLOOK32_BOOT_ENSURE <<<\n"
            "echo keep-after\n",
            encoding="utf-8",
        )
        power.chmod(0o755)
        self.root = self.tmp / "klipper"
        (self.root / "klippy" / "extras").mkdir(parents=True)
        (self.root / "klippy" / "klippy.py").write_text("# fake\n", encoding="utf-8")
        (self.root / ".git" / "info").mkdir(parents=True)
        self.py = self.tmp / "python3"
        fake_python(self.py)
        self.env = {
            "FLOOK32_MOD_DATA": str(self.mod),
            "FLOOK32_POWER_ON": str(power),
            "FLOOK32_USER_CFG": str(self.mod / "user.cfg"),
            "FLOOK32_PLUGINS_CFG": str(self.mod / "plugins.cfg"),
            "FLOOK32_KLIPPER_ROOT": str(self.root),
            "FLOOK32_PYTHON": str(self.py),
            "FLOOK32_SKIP_PIP": "1",
            "FLOOK32_LEGACY_STASH": str(self.mod / "flook32-legacy.cfg"),
        }
        self.local = PKG / "flook32.local.cfg"
        if self.local.exists():
            self.local.unlink()

    def tearDown(self):
        if self.local.exists():
            self.local.unlink()
        self.td.cleanup()

    def test_install_links_and_removes_legacy(self):
        result = run_script("install.sh", self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        link = self.root / "klippy" / "extras" / "flook32.py"
        self.assertTrue(link.is_symlink())
        self.assertEqual(link.resolve(), (PKG / "flook32.py").resolve())
        power = self.mod / "power_on.sh"
        self.assertNotIn("FLOOK32_BOOT_ENSURE", power.read_text())
        self.assertIn("keep-before", power.read_text())
        self.assertIn("keep-after", power.read_text())
        self.assertTrue(power.stat().st_mode & 0o100)
        self.assertEqual((self.mod / "user.cfg").read_text().strip(), "")
        exclude = self.root / ".git" / "info" / "exclude"
        self.assertIn("/klippy/extras/flook32.py", exclude.read_text())

    def test_install_accepts_existing_symlink_to_same_inode_alias(self):
        dest = self.root / "klippy" / "extras" / "flook32.py"
        with tempfile.TemporaryDirectory(dir=PKG) as same_fs_dir:
            alias = pathlib.Path(same_fs_dir) / "flook32-alias.py"
            os.link(PKG / "flook32.py", alias)
            dest.symlink_to(alias)
            result = run_script("install.sh", self.env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(dest.is_symlink())

    def test_install_refuses_foreign_module_and_rolls_back_include(self):
        dest = self.root / "klippy" / "extras" / "flook32.py"
        dest.write_text("foreign\n", encoding="utf-8")
        result = run_script("install.sh", self.env)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(dest.read_text(), "foreign\n")
        self.assertEqual((self.mod / "plugins.cfg").read_text().strip(), "")

    def test_uninstall_only_removes_owned_symlink(self):
        self.assertEqual(run_script("install.sh", self.env).returncode, 0)
        result = run_script("uninstall.sh", self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "klippy" / "extras" / "flook32.py").exists())
        exclude = self.root / ".git" / "info" / "exclude"
        self.assertNotIn("/klippy/extras/flook32.py", exclude.read_text())

    def test_uninstall_does_not_touch_foreign_module_or_its_exclude(self):
        dest = self.root / "klippy" / "extras" / "flook32.py"
        dest.write_text("foreign\n", encoding="utf-8")
        exclude = self.root / ".git" / "info" / "exclude"
        exclude.write_text("/klippy/extras/flook32.py\n", encoding="utf-8")
        result = run_script("uninstall.sh", self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(dest.read_text(), "foreign\n")
        self.assertIn("/klippy/extras/flook32.py", exclude.read_text())

    def test_update_imports_stashed_legacy_config(self):
        legacy = pathlib.Path(self.env["FLOOK32_LEGACY_STASH"])
        legacy.write_text("[flook32]\nip: 192.168.1.230\n", encoding="utf-8")
        result = run_script("update.sh", self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.local.read_text(), legacy.read_text())

    def test_legacy_visible_sensor_is_hidden_on_import(self):
        legacy = pathlib.Path(self.env["FLOOK32_LEGACY_STASH"])
        legacy.write_text(
            "[flook32]\n\n[temperature_sensor chamber]\nsensor_type: flook32\n",
            encoding="utf-8",
        )
        result = run_script("update.sh", self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = self.local.read_text()
        self.assertIn("[temperature_sensor _flook32_chamber]", text)
        self.assertNotIn("[temperature_sensor chamber]", text)

    def test_tracked_config_has_optional_local_wildcard(self):
        text = (PKG / "flook32.cfg").read_text(encoding="utf-8")
        self.assertIn("[include flook32.local*.cfg]", text)


if __name__ == "__main__":
    unittest.main()
