import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class SharedAgentRulesTests(unittest.TestCase):
    def test_grok_global_rules_are_linked_by_both_installers(self):
        windows_installer = (ROOT / "install.nu").read_text(encoding="utf-8")
        linux_installer = (ROOT / "install.sh").read_text(encoding="utf-8")

        self.assertIn(
            '{src: $shared_agents, dest: ($grok_home | path join "AGENTS.md")',
            windows_installer,
        )
        self.assertIn(
            'create_file_link "$shared_agents" "$HOME/.grok/AGENTS.md" "grok-rules"',
            linux_installer,
        )
        self.assertIn(
            "claude-code|codex|grok|opencode|hermes-agent",
            linux_installer,
        )

    def test_twelve_rule_backup_is_complete_and_not_an_install_target(self):
        backup = (ROOT / "ai-assistants" / "AGENTS.12-rules.backup.md").read_text(
            encoding="utf-8"
        )
        core = (ROOT / "ai-assistants" / "AGENTS.md").read_text(encoding="utf-8")
        windows_installer = (ROOT / "install.nu").read_text(encoding="utf-8")
        linux_installer = (ROOT / "install.sh").read_text(encoding="utf-8")
        headings = [
            line for line in backup.splitlines() if line.startswith("### Rule ")
        ]

        self.assertEqual(len(headings), 12)
        self.assertEqual(
            [int(line.split()[2]) for line in headings],
            list(range(1, 13)),
        )
        self.assertEqual(
            hashlib.sha256(backup.encode()).hexdigest(),
            "4eee5b655cb97ff17d75651808b0f2110998589b557a45397846c8caa8a38735",
        )
        self.assertNotIn("12-Rule Task Contract", core)
        self.assertNotIn("AGENTS.12-rules.backup.md", windows_installer)
        self.assertNotIn("AGENTS.12-rules.backup.md", linux_installer)


class InstallerRollbackTests(unittest.TestCase):
    def test_windows_commit_is_durable_before_cleanup(self):
        if os.name != "nt":
            self.skipTest("Windows-only installer")
        nu = shutil.which("nu")
        powershell = shutil.which("powershell.exe")
        cmd = shutil.which("cmd.exe")
        if not nu or not powershell or not cmd:
            self.skipTest("Nushell, PowerShell, or cmd is unavailable")

        with tempfile.TemporaryDirectory(prefix="dotfiles-durable-") as temp:
            root = Path(temp)
            fixture = root / "repo"
            source = fixture / "nvim"
            home = root / "home"
            destination = home / "AppData" / "Local" / "nvim"
            marker = root / "durable-commit"
            source.mkdir(parents=True)
            destination.mkdir(parents=True)
            (source / "managed.txt").write_text("managed\n", encoding="utf-8")
            (destination / "original.txt").write_text("original\n", encoding="utf-8")
            installer = (ROOT / "install.nu").read_text(encoding="utf-8")
            append_signature = "def append_transaction_journal [path: string, entry: record, durable: bool = false]: nothing -> bool {"
            append_injected = append_signature + '\n        if (($entry.event? | default "") == "run_committed") { if not $durable { return false }; "ready" | save --force $env.DURABILITY_MARKER }'
            cleanup_signature = "def remove_rollback_path [path: string, identity: record]: nothing -> bool {"
            cleanup_injected = cleanup_signature + '\n        if not ($env.DURABILITY_MARKER | path exists) { error make {msg: "Cleanup preceded durable commit"} }'
            self.assertIn(append_signature, installer)
            self.assertIn(cleanup_signature, installer)
            fixture.mkdir(parents=True, exist_ok=True)
            (fixture / "install.nu").write_text(
                installer.replace(append_signature, append_injected, 1).replace(
                    cleanup_signature,
                    cleanup_injected,
                    1,
                ),
                encoding="utf-8",
            )
            env = os.environ.copy()
            env.update(
                {
                    "USERPROFILE": str(home),
                    "APPDATA": str(home / "AppData" / "Roaming"),
                    "LOCALAPPDATA": str(home / "AppData" / "Local"),
                    "HOME": str(home),
                    "DURABILITY_MARKER": str(marker),
                    "PATH": os.pathsep.join(
                        (str(Path(powershell).parent), str(Path(cmd).parent))
                    ),
                }
            )
            result = subprocess.run(
                [
                    nu,
                    "--no-config-file",
                    str(fixture / "install.nu"),
                    "--only",
                    "neovim",
                    "--no-install",
                    "--no-backup",
                ],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                timeout=60,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(marker.exists())
            self.assertTrue((destination / "managed.txt").exists())
            journals = list(
                (home / "AppData" / "Local" / "envCross_dotfiles" / "transactions").glob("*.jsonl")
            )
            self.assertEqual(len(journals), 1)
            events = [json.loads(line)["event"] for line in journals[0].read_text(encoding="utf-8").splitlines()]
            self.assertLess(events.index("run_committed"), events.index("rollback_removed"))

    def test_windows_foreign_rollback_sibling_is_preserved(self):
        if os.name != "nt":
            self.skipTest("Windows-only installer")
        nu = shutil.which("nu")
        powershell = shutil.which("powershell.exe")
        cmd = shutil.which("cmd.exe")
        if not nu or not powershell or not cmd:
            self.skipTest("Nushell, PowerShell, or cmd is unavailable")

        with tempfile.TemporaryDirectory(prefix="dotfiles-foreign-rollback-") as temp:
            root = Path(temp)
            fixture = root / "repo"
            source = fixture / "nvim"
            home = root / "home"
            destination = home / "AppData" / "Local" / "nvim"
            source.mkdir(parents=True)
            destination.mkdir(parents=True)
            (source / "managed.txt").write_text("managed\n", encoding="utf-8")
            (destination / "original.txt").write_text("original\n", encoding="utf-8")
            installer = (ROOT / "install.nu").read_text(encoding="utf-8")
            signature = "def append_transaction_journal [path: string, entry: record, durable: bool = false]: nothing -> bool {"
            injected = signature + '\n        if (($entry.event? | default "") == "target_swapped") { rm --recursive --force $entry.rollback; mkdir $entry.rollback; "foreign\\n" | save --raw ($entry.rollback | path join "foreign.txt"); return false }'
            self.assertIn(signature, installer)
            fixture.mkdir(parents=True, exist_ok=True)
            (fixture / "install.nu").write_text(
                installer.replace(signature, injected, 1),
                encoding="utf-8",
            )
            env = os.environ.copy()
            env.update(
                {
                    "USERPROFILE": str(home),
                    "APPDATA": str(home / "AppData" / "Roaming"),
                    "LOCALAPPDATA": str(home / "AppData" / "Local"),
                    "HOME": str(home),
                    "PATH": os.pathsep.join(
                        (str(Path(powershell).parent), str(Path(cmd).parent))
                    ),
                }
            )
            result = subprocess.run(
                [
                    nu,
                    "--no-config-file",
                    str(fixture / "install.nu"),
                    "--only",
                    "neovim",
                    "--no-install",
                    "--no-backup",
                ],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                timeout=60,
            )

            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertTrue((destination / "managed.txt").exists())
            self.assertFalse((destination / "foreign.txt").exists())
            rollback_siblings = list(destination.parent.glob(".nvim.envCross-*.rollback"))
            self.assertEqual(len(rollback_siblings), 1)
            self.assertEqual(
                (rollback_siblings[0] / "foreign.txt").read_text(encoding="utf-8"),
                "foreign\n",
            )
            journals = list(
                (home / "AppData" / "Local" / "envCross_dotfiles" / "transactions").glob("*.jsonl")
            )
            self.assertEqual(len(journals), 1)
            events = [json.loads(line)["event"] for line in journals[0].read_text(encoding="utf-8").splitlines()]
            self.assertIn("rollback_failed", events)

    def test_windows_foreign_rollback_sibling_is_not_deleted_after_commit(self):
        if os.name != "nt":
            self.skipTest("Windows-only installer")
        nu = shutil.which("nu")
        powershell = shutil.which("powershell.exe")
        cmd = shutil.which("cmd.exe")
        if not nu or not powershell or not cmd:
            self.skipTest("Nushell, PowerShell, or cmd is unavailable")

        with tempfile.TemporaryDirectory(prefix="dotfiles-foreign-cleanup-") as temp:
            root = Path(temp)
            fixture = root / "repo"
            source = fixture / "nvim"
            home = root / "home"
            destination = home / "AppData" / "Local" / "nvim"
            source.mkdir(parents=True)
            destination.mkdir(parents=True)
            (source / "managed.txt").write_text("managed\n", encoding="utf-8")
            (destination / "original.txt").write_text("original\n", encoding="utf-8")
            installer = (ROOT / "install.nu").read_text(encoding="utf-8")
            signature = "def append_transaction_journal [path: string, entry: record, durable: bool = false]: nothing -> bool {"
            injected = signature + '\n        if (($entry.event? | default "") == "run_committed") { if not $durable { return false }; let planned = (open $path | lines | each { from json } | where event == "target_swapped" | last); rm --recursive --force $planned.rollback; mkdir $planned.rollback; "foreign\\n" | save --raw ($planned.rollback | path join "foreign.txt") }'
            self.assertIn(signature, installer)
            fixture.mkdir(parents=True, exist_ok=True)
            (fixture / "install.nu").write_text(
                installer.replace(signature, injected, 1),
                encoding="utf-8",
            )
            env = os.environ.copy()
            env.update(
                {
                    "USERPROFILE": str(home),
                    "APPDATA": str(home / "AppData" / "Roaming"),
                    "LOCALAPPDATA": str(home / "AppData" / "Local"),
                    "HOME": str(home),
                    "PATH": os.pathsep.join(
                        (str(Path(powershell).parent), str(Path(cmd).parent))
                    ),
                }
            )
            result = subprocess.run(
                [
                    nu,
                    "--no-config-file",
                    str(fixture / "install.nu"),
                    "--only",
                    "neovim",
                    "--no-install",
                    "--no-backup",
                ],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                timeout=60,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            rollback_siblings = list(destination.parent.glob(".nvim.envCross-*.rollback"))
            self.assertEqual(len(rollback_siblings), 1)
            self.assertEqual(
                (rollback_siblings[0] / "foreign.txt").read_text(encoding="utf-8"),
                "foreign\n",
            )
            journals = list(
                (home / "AppData" / "Local" / "envCross_dotfiles" / "transactions").glob("*.jsonl")
            )
            events = [json.loads(line)["event"] for line in journals[0].read_text(encoding="utf-8").splitlines()]
            self.assertIn("rollback_cleanup_failed", events)
            self.assertNotIn("rollback_removed", events)

    def test_windows_journal_failure_rolls_back_swapped_target(self):
        if os.name != "nt":
            self.skipTest("Windows-only installer")
        nu = shutil.which("nu")
        powershell = shutil.which("powershell.exe")
        if not nu or not powershell:
            self.skipTest("Nushell or PowerShell is unavailable")

        with tempfile.TemporaryDirectory(prefix="dotfiles-journal-") as temp:
            root = Path(temp)
            fixture = root / "repo"
            source = fixture / "nvim"
            home = root / "home"
            destination = home / "AppData" / "Local" / "nvim"
            source.mkdir(parents=True)
            destination.mkdir(parents=True)
            (source / "managed.txt").write_text("managed\n", encoding="utf-8")
            original = destination / "original.txt"
            original.write_text("original\n", encoding="utf-8")
            installer = (ROOT / "install.nu").read_text(encoding="utf-8")
            signature = "def append_transaction_journal [path: string, entry: record, durable: bool = false]: nothing -> bool {"
            injected = signature + '\n        if (($entry.event? | default "") == "target_swapped") { return false }'
            self.assertIn(signature, installer)
            (fixture / "install.nu").write_text(
                installer.replace(signature, injected, 1),
                encoding="utf-8",
            )
            env = os.environ.copy()
            env.update(
                {
                    "USERPROFILE": str(home),
                    "APPDATA": str(home / "AppData" / "Roaming"),
                    "LOCALAPPDATA": str(home / "AppData" / "Local"),
                    "HOME": str(home),
                    "PATH": os.pathsep.join(
                        (str(Path(powershell).parent), str(Path(shutil.which("cmd.exe")).parent))
                    ),
                }
            )
            result = subprocess.run(
                [
                    nu,
                    "--no-config-file",
                    str(fixture / "install.nu"),
                    "--only",
                    "neovim",
                    "--no-install",
                    "--no-backup",
                ],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                timeout=60,
            )

            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertTrue(destination.is_dir())
            self.assertFalse(destination.is_symlink())
            self.assertEqual(original.read_text(encoding="utf-8"), "original\n")
            self.assertFalse((destination / "managed.txt").exists())

    def test_windows_link_failure_preserves_existing_config(self):
        if os.name != "nt":
            self.skipTest("Windows-only installer")
        nu = shutil.which("nu")
        if not nu:
            self.skipTest("nu is unavailable")

        with tempfile.TemporaryDirectory(prefix="dotfiles-rollback-") as temp:
            home = Path(temp) / "home"
            config = home / ".codex" / "config.toml"
            windows_profile = home / ".codex" / "windows.config.toml"
            fake_bin = Path(temp) / "bin"
            fixture = Path(temp) / "repo"
            fixture_config = fixture / "ai-assistants" / ".codex"
            config.parent.mkdir(parents=True)
            fake_bin.mkdir()
            fixture_config.mkdir(parents=True)
            transaction_id = "00000000-0000-0000-0000-000000000000"
            installer = (ROOT / "install.nu").read_text(encoding="utf-8")
            installer = installer.replace(
                "let transaction_id = (random uuid | into string)",
                f'let transaction_id = "{transaction_id}"',
            )
            (fixture / "install.nu").write_text(installer, encoding="utf-8")
            shutil.copy2(
                ROOT / "ai-assistants" / ".codex" / "config.toml",
                fixture_config / "config.toml",
            )
            shutil.copy2(
                ROOT / "ai-assistants" / ".codex" / "windows.config.toml",
                fixture_config / "windows.config.toml",
            )
            original = b"original-windows-config\n"
            original_profile = b"original-windows-profile\n"
            config.write_bytes(original)
            windows_profile.write_bytes(original_profile)
            marker = config.parent / f".config.toml.envCross-{transaction_id}.stage"
            marker.write_text("occupied stage\n", encoding="utf-8")
            (fake_bin / "codex.cmd").write_text(
                "exit /b 0\n",
                encoding="ascii",
            )

            env = os.environ.copy()
            env.update(
                {
                    "USERPROFILE": str(home),
                    "APPDATA": str(home / "AppData" / "Roaming"),
                    "LOCALAPPDATA": str(home / "AppData" / "Local"),
                    "HOME": str(home),
                    "CODEX_HOME": str(home / ".codex"),
                    "XDG_CACHE_HOME": str(home / ".cache"),
                    "XDG_CONFIG_HOME": str(home / ".config"),
                    "XDG_STATE_HOME": str(home / ".local" / "state"),
                    "PATH": os.pathsep.join(
                        (
                            str(fake_bin),
                            str(Path(shutil.which("powershell.exe")).parent),
                            str(Path(shutil.which("cmd.exe")).parent),
                        )
                    ),
                }
            )
            result = subprocess.run(
                [
                    nu,
                    "--no-config-file",
                    str(fixture / "install.nu"),
                    "--only",
                    "codex",
                    "--no-install",
                    "--no-backup",
                ],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                timeout=60,
            )

            self.assertTrue(marker.exists(), "Windows occupied-stage failure was not injected")
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertNotIn("Copied: Codex Windows config", result.stdout)
            self.assertTrue(config.exists(), "installer removed the existing Windows config")
            self.assertEqual(config.read_bytes(), original)
            self.assertEqual(windows_profile.read_bytes(), original_profile)
            journal = home / "AppData" / "Local" / "envCross_dotfiles" / "transactions" / f"{transaction_id}.jsonl"
            events = [json.loads(line)["event"] for line in journal.read_text(encoding="utf-8").splitlines()]
            self.assertIn("run_started", events)
            self.assertIn("target_failed", events)
            self.assertIn("run_failed", events)

    def test_linux_link_failure_preserves_existing_config(self):
        bash = shutil.which("bash")
        if os.name == "nt":
            scoop_bash = Path(r"D:\ProgramData\Scoop\apps\git\current\bin\bash.exe")
            bash = str(scoop_bash) if scoop_bash.exists() else bash
        if not bash:
            self.skipTest("bash is unavailable")

        with tempfile.TemporaryDirectory(prefix="dotfiles-rollback-") as temp:
            temp_path = Path(temp)
            fake_bin = temp_path / "bin"
            fake_bin.mkdir()
            for name in ("pacman", "stow"):
                path = fake_bin / name
                path.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
                path.chmod(0o755)
            ln = fake_bin / "ln"
            ln.write_text(
                "#!/usr/bin/env bash\n"
                "for arg in \"$@\"; do\n"
                "    if [[ \"$arg\" == */.codex/windows.config.toml ]]; then\n"
                "        printf reached > \"$FAILURE_MARKER\"\n"
                "        exit 1\n"
                "    fi\n"
                "done\n"
                "exec /usr/bin/ln \"$@\"\n",
                encoding="utf-8",
            )
            ln.chmod(0o755)

            env = os.environ.copy()
            home = temp_path / "home"
            config = home / ".codex" / "config.toml"
            rules = home / ".codex" / "AGENTS.md"
            marker = temp_path / "linux-link-failure-reached"
            config.parent.mkdir(parents=True)
            config.write_bytes(b"original-linux-config\n")
            rules.write_bytes(b"original-linux-rules\n")
            if os.name == "nt":
                def bash_path(path):
                    resolved = Path(path).resolve()
                    drive = resolved.drive.rstrip(":").lower()
                    tail = resolved.as_posix()[2:]
                    return f"/{drive}{tail}"
            else:
                def bash_path(path):
                    return str(path)
            home_posix = bash_path(home)
            fake_bin_posix = bash_path(fake_bin)
            script_posix = bash_path(ROOT / "install.sh")
            env.update(
                {
                    "HOME": home_posix,
                    "CODEX_HOME": f"{home_posix}/.codex",
                    "XDG_CACHE_HOME": f"{home_posix}/.cache",
                    "XDG_CONFIG_HOME": f"{home_posix}/.config",
                    "XDG_DATA_HOME": f"{home_posix}/.local/share",
                    "XDG_STATE_HOME": f"{home_posix}/.local/state",
                    "FAILURE_MARKER": bash_path(marker),
                    "TEST_BIN_POSIX": fake_bin_posix,
                }
            )
            command = (
                'export PATH="$TEST_BIN_POSIX:$PATH"; '
                f'bash "{script_posix}" --only-codex --no-install --no-backup'
            )
            result = subprocess.run(
                [bash, "--noprofile", "--norc", "-c", command],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                timeout=60,
            )

            self.assertTrue(marker.exists(), "Linux config link failure was not injected")
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertTrue(config.exists(), "installer removed the existing Linux config")
            self.assertEqual(config.read_bytes(), b"original-linux-config\n")
            self.assertEqual(rules.read_bytes(), b"original-linux-rules\n")
            journals = list((home / ".local" / "state" / "envcross" / "transactions").glob("*/journal"))
            self.assertEqual(len(journals), 1)
            self.assertIn("state\trolled-back", journals[0].read_text(encoding="utf-8"))
            if os.name != "nt":
                self.assertEqual(journals[0].stat().st_mode & 0o777, 0o600)
                self.assertEqual(journals[0].parent.stat().st_mode & 0o777, 0o700)


if __name__ == "__main__":
    unittest.main()
