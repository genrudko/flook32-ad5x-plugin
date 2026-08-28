from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

PKG = pathlib.Path(__file__).resolve().parents[1]


class LegacyMigrationTests(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.tmp = pathlib.Path(self.td.name)
        self.mod = self.tmp / "mod_data"
        self.old = self.mod / "plugins" / "flook32"
        self.old.mkdir(parents=True)
        (self.old / "flook32.cfg").write_text("[flook32]\nip: 192.168.1.230\n", encoding="utf-8")
        (self.old / "flook32.py").write_text("legacy\n", encoding="utf-8")
        (self.old / "ensure.sh").write_text("legacy\n", encoding="utf-8")
        (self.mod / "user.cfg").write_text("keep\n[include plugins/flook32/flook32.cfg]\n", encoding="utf-8")
        power = self.mod / "power_on.sh"
        power.write_text(
            "#!/bin/sh\nkeep\n# >>> FLOOK32_BOOT_ENSURE >>>\nold\n# <<< FLOOK32_BOOT_ENSURE <<<\n",
            encoding="utf-8",
        )
        power.chmod(0o755)
        (self.mod / "user.moonraker.conf").write_text("# keep moon\n", encoding="utf-8")
        self.driver = self.tmp / "plugins.sh"
        self.driver.write_text(
            "#!/bin/sh\n"
            "set -eu\n"
            "target=\"$FLOOK32_OLD_DIR\"\n"
            "mkdir -p \"$target/.git\"\n"
            "cp \"$FLOOK32_TEST_PACKAGE/flook32.py\" \"$target/flook32.py\"\n"
            "cp \"$FLOOK32_TEST_PACKAGE/flook32.cfg\" \"$target/flook32.cfg\"\n"
            "printf '%s\\n' '[include plugins/flook32/flook32.cfg]' > \"$FLOOK32_MOD_DATA/plugins.cfg\"\n",
            encoding="utf-8",
        )
        self.driver.chmod(0o755)

    def tearDown(self):
        self.td.cleanup()

    def env(self):
        e = os.environ.copy()
        e.update(
            {
                "FLOOK32_MOD_DATA": str(self.mod),
                "FLOOK32_OLD_DIR": str(self.old),
                "FLOOK32_USER_CFG": str(self.mod / "user.cfg"),
                "FLOOK32_POWER_ON": str(self.mod / "power_on.sh"),
                "FLOOK32_MOON_CFG": str(self.mod / "user.moonraker.conf"),
                "FLOOK32_LEGACY_STASH": str(self.mod / "flook32-legacy.cfg"),
                "FLOOK32_BACKUP_DIR": str(self.mod / "legacy-backup"),
                "FLOOK32_MIGRATION_SNAPSHOT": str(self.mod / "migration-snapshot"),
                "FLOOK32_PLUGIN_DRIVER": str(self.driver),
                "FLOOK32_TEST_PACKAGE": str(PKG),
            }
        )
        return e

    def test_successful_transaction(self):
        result = subprocess.run(
            ["/bin/sh", str(PKG / "migrate_legacy.sh")],
            env=self.env(), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.old / ".git").is_dir())
        self.assertEqual((self.mod / "flook32-legacy.cfg").read_text(), "[flook32]\nip: 192.168.1.230\n")
        self.assertTrue((self.mod / "legacy-backup" / "ensure.sh").exists())
        self.assertNotIn("plugins/flook32/flook32.cfg", (self.mod / "user.cfg").read_text())
        self.assertNotIn("FLOOK32_BOOT_ENSURE", (self.mod / "power_on.sh").read_text())
        moon = (self.mod / "user.moonraker.conf").read_text()
        self.assertIn("[update_manager flook32]", moon)
        self.assertIn("flook32-ad5x-plugin.git", moon)
        self.assertIn("channel: dev", moon)

    def test_zero_driver_without_enabled_include_rolls_back(self):
        self.driver.write_text(
            "#!/bin/sh\n"
            "set -eu\n"
            "target=\"$FLOOK32_OLD_DIR\"\n"
            "mkdir -p \"$target/.git\"\n"
            "cp \"$FLOOK32_TEST_PACKAGE/flook32.py\" \"$target/flook32.py\"\n"
            "cp \"$FLOOK32_TEST_PACKAGE/flook32.cfg\" \"$target/flook32.cfg\"\n"
            "exit 0\n",
            encoding="utf-8",
        )
        self.driver.chmod(0o755)
        before_user = (self.mod / "user.cfg").read_text()
        result = subprocess.run(
            ["/bin/sh", str(PKG / "migrate_legacy.sh")],
            env=self.env(), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("include is not enabled", result.stderr)
        self.assertEqual((self.old / "flook32.py").read_text(), "legacy\n")
        self.assertEqual((self.mod / "user.cfg").read_text(), before_user)

    def test_partial_adoption_is_repaired(self):
        subprocess.run(["git", "init", "-q", str(self.old)], check=True)
        subprocess.run(
            ["git", "-C", str(self.old), "remote", "add", "origin",
             "https://github.com/genrudko/flook32-ad5x-plugin.git"],
            check=True,
        )
        result = subprocess.run(
            ["/bin/sh", str(PKG / "migrate_legacy.sh")],
            env=self.env(), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("repairing lifecycle state", result.stdout)
        self.assertIn(
            "[include plugins/flook32/flook32.cfg]",
            (self.mod / "plugins.cfg").read_text(),
        )
        self.assertFalse((self.mod / "legacy-backup").exists())

    def test_failed_driver_rolls_back(self):
        self.driver.write_text("#!/bin/sh\nexit 7\n", encoding="utf-8")
        self.driver.chmod(0o755)
        before_user = (self.mod / "user.cfg").read_text()
        before_power = (self.mod / "power_on.sh").read_text()
        before_moon = (self.mod / "user.moonraker.conf").read_text()
        result = subprocess.run(
            ["/bin/sh", str(PKG / "migrate_legacy.sh")],
            env=self.env(), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.old / "flook32.py").read_text(), "legacy\n")
        self.assertEqual((self.mod / "user.cfg").read_text(), before_user)
        self.assertEqual((self.mod / "power_on.sh").read_text(), before_power)
        self.assertEqual((self.mod / "user.moonraker.conf").read_text(), before_moon)


if __name__ == "__main__":
    unittest.main()
