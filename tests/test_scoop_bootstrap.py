import re
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INSTALLER_URL = (
    "https://raw.githubusercontent.com/ScoopInstaller/Install/"
    "3bcaeb2ea53ad611fd8552eb9f735c5e2cd52f40/install.ps1"
)
INSTALLER_SHA256 = "84242117FBD6CF80C1F1767E590A681257DB47E8E0E6864DC445CE6C7FD6980E"


class ScoopBootstrapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / "install.nu").read_text(encoding="utf-8")
        match = re.search(
            r"    def --env ensure_scoop \[.*?\n    }\n\n    def install_tool",
            cls.source,
            re.DOTALL,
        )
        cls.body = match.group(0) if match else ""

    def test_bootstrap_uses_pinned_official_installer(self):
        self.assertIn(f'let install_url = "{INSTALLER_URL}"', self.body)
        self.assertIn(f'let expected_hash = "{INSTALLER_SHA256}"', self.body)
        self.assertIn("http get --raw $install_url | save --raw --force $temp_script", self.body)

    def test_hash_gate_precedes_execution(self):
        self.assertIn("let actual_hash = (open --raw $temp_script | hash sha256 | str uppercase)", self.body)
        gate = "if $actual_hash != $expected_hash"
        execution = "^powershell.exe -NoProfile -ExecutionPolicy Bypass -File $temp_script"
        self.assertIn(gate, self.body)
        self.assertIn(execution, self.body)
        self.assertLess(self.body.index(gate), self.body.index(execution))
        self.assertRegex(
            self.body,
            r"if \$actual_hash != \$expected_hash \{\s+log_error .*?\s+return false",
        )

    def test_execution_is_local_and_admin_flag_is_guarded(self):
        self.assertNotIn("Invoke-Expression", self.body)
        self.assertNotIn("Invoke-RestMethod", self.body)
        self.assertNotIn("Set-ExecutionPolicy", self.body)
        self.assertNotIn("https://get.scoop.sh", self.body)
        self.assertRegex(
            self.body,
            r"if \$elevated \{\s+\(\^powershell\.exe .*? -File \$temp_script -RunAsAdmin \| complete\)\s+} else \{\s+\(\^powershell\.exe .*? -File \$temp_script \| complete\)",
        )

    def test_fresh_install_refreshes_parent_environment(self):
        execution = self.body.index("if $result.exit_code != 0")
        command_check = self.body.index('if (check_cmd "scoop")', execution)
        refresh = self.body.index("$env.PATH = ($env.PATH | prepend $scoop_shims)", execution)
        self.assertLess(refresh, command_check)
        self.assertIn("$env.SCOOP = $scoop_root", self.body)
        self.assertIn('default ($env.USERPROFILE | path join "scoop")', self.body)

    @unittest.skipUnless(shutil.which("nu"), "Nushell is required")
    def test_refresh_logic_makes_fresh_shim_discoverable(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as temp:
            home = Path(temp)
            shims = home / "scoop" / "shims"
            shims.mkdir(parents=True)
            (shims / "scoop.cmd").write_text("@exit /b 0\n", encoding="utf-8")
            env = os.environ.copy()
            env.pop("SCOOP", None)
            env["USERPROFILE"] = str(home)
            command = (
                'def --env refresh [] { let scoop_root = ($env.SCOOP? | default '
                '($env.USERPROFILE | path join "scoop")); let scoop_shims = '
                '($scoop_root | path join "shims"); let scoop_command = '
                '($scoop_shims | path join "scoop.cmd"); if ($scoop_command | path exists) '
                '{ $env.SCOOP = $scoop_root; $env.PATH = ($env.PATH | prepend $scoop_shims) } }; '
                'refresh; if (which scoop | is-empty) { error make "scoop shim not found" }'
            )
            result = subprocess.run(
                [shutil.which("nu"), "--no-config-file", "-c", command],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_temp_script_is_cleaned_in_finally(self):
        self.assertRegex(
            self.body,
            r"finally \{\s+rm --force \$temp_script\s+}",
        )

    def test_bootstrap_failure_terminates_the_installer(self):
        self.assertRegex(
            self.source,
            r"if not \(ensure_scoop \$dry_run \$is_admin\) \{\s+log_error \"Scoop required\"\s+error make \"Scoop required\"\s+}",
        )


if __name__ == "__main__":
    unittest.main()
