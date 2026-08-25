import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import tomllib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
MCP_ENV = ROOT / "scripts" / "secrets" / "mcp-env.sh"
GIT = shutil.which("git")
BASH = shutil.which("bash")
if BASH is None and GIT:
    candidate = pathlib.Path(GIT).resolve().parents[1] / "bin" / "bash.exe"
    if candidate.is_file():
        BASH = str(candidate)


def bash_path(path):
    path = pathlib.Path(path).resolve()
    if os.name != "nt":
        return str(path)
    result = subprocess.run(
        [BASH, "-lc", 'cygpath -u "$1"', "_", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip().splitlines()[-1]


@unittest.skipUnless(BASH, "Bash is required")
class SecretCacheTests(unittest.TestCase):
    def run_bash(self, body, *paths):
        return subprocess.run(
            [BASH, "--noprofile", "--norc", "-c", f'export PATH="/usr/bin:/bin:$PATH"; {body}', "_", *map(bash_path, paths)],
            capture_output=True,
            text=True,
        )

    def test_round_trip_does_not_execute_secret_text(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as temp:
            cache = pathlib.Path(temp) / "mcp.env"
            marker = pathlib.Path(temp) / "executed"
            result = self.run_bash(
                'set -euo pipefail; source "$1"; MCP_ENV_CACHE="$2"; '
                'expected="\\$(touch \\"$3\\")=alpha;beta"; '
                'FIRECRAWL_API_KEY="$expected"; mcp_env_write_cache_from_env; '
                'unset FIRECRAWL_API_KEY BWS_SECRETS_INJECTED; mcp_env_load_cache; '
                '[[ "$FIRECRAWL_API_KEY" == "$expected" && ! -e "$3" ]]',
                MCP_ENV,
                cache,
                marker,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_unsafe_files_and_records(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as temp:
            root = pathlib.Path(temp)
            result = self.run_bash(
                'set -euo pipefail; source "$1"; MCP_ENV_CACHE="$2"; '
                'printf "FIRECRAWL_API_KEY=x\\n" >"$2"; chmod 0644 "$2"; '
                '! mcp_env_load_cache; chmod 0600 "$2"; '
                'ln "$2" "$3"; MCP_ENV_CACHE="$3"; ! mcp_env_load_cache; '
                'rm "$3"; ln -s "$2" "$3"; ! mcp_env_load_cache; '
                'rm "$3"; MCP_ENV_CACHE="$2"; '
                'printf "UNKNOWN=x\\n" >"$2"; chmod 0600 "$2"; ! mcp_env_load_cache; '
                'printf "FIRECRAWL_API_KEY=x\\nFIRECRAWL_API_KEY=y\\n" >"$2"; '
                '! mcp_env_load_cache',
                MCP_ENV,
                root / "cache",
                root / "alias",
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_unapproved_mcp_package(self):
        result = self.run_bash(
            'source "$1"; mcp_env_exec_npm unapproved-package@1.0.0; [[ $? == 2 ]]',
            MCP_ENV,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_directory_failure_stops_cache_write_without_errexit(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as temp:
            root = pathlib.Path(temp)
            result = self.run_bash(
                'source "$1"; mkdir "$2/real"; ln -s "$2/real" "$2/link"; '
                'if [[ ! -L "$2/link" ]]; then rm -rf "$2/link"; : >"$2/link"; fi; '
                'MCP_ENV_CACHE="$2/link/cache"; FIRECRAWL_API_KEY=x; '
                'mcp_env_write_cache_from_env; code=$?; '
                '[[ $code != 0 && ! -e "$2/real/cache" ]]',
                MCP_ENV,
                root,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_mcp_helpers_execute_only_exact_npx_specs(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as temp:
            root = pathlib.Path(temp)
            fake = root / "npx"
            fake.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$@" >"$NPM_ARGS"\n', encoding="utf-8")
            fake.chmod(0o755)
            for body, expected in (
                ('mcp_env_exec_remote endpoint', ["-y", "mcp-remote@0.1.38", "endpoint"]),
                ('mcp_env_exec_npm firecrawl-mcp@3.24.0', ["-y", "firecrawl-mcp@3.24.0"]),
                ('mcp_env_exec_npm tavily-mcp@0.2.22', ["-y", "tavily-mcp@0.2.22"]),
            ):
                output = root / "args"
                result = self.run_bash(
                    'source "$1"; export PATH="$2:/usr/bin:/bin" NPM_ARGS="$3"; ' + body,
                    MCP_ENV,
                    root,
                    output,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(output.read_text(encoding="utf-8").splitlines(), expected)


class PackagePinTests(unittest.TestCase):
    def test_mcp_and_playwright_packages_are_exactly_pinned(self):
        mcp = MCP_ENV.read_text(encoding="utf-8")
        firecrawl = (ROOT / "scripts" / "mcp" / "run-firecrawl.sh").read_text(encoding="utf-8")
        tavily = (ROOT / "scripts" / "mcp" / "run-tavily.sh").read_text(encoding="utf-8")
        playwright = (ROOT / "ai-assistants" / "SKILLS" / "playwright" / "scripts" / "playwright_cli.sh").read_text(encoding="utf-8")
        self.assertIn("mcp-remote@0.1.38", mcp)
        self.assertIn("firecrawl-mcp@3.24.0", firecrawl)
        self.assertIn("tavily-mcp@0.2.22", tavily)
        self.assertIn("@playwright/cli@0.1.18", playwright)
        self.assertNotIn("@latest", "\n".join((mcp, firecrawl, tavily, playwright)))
        self.assertNotIn("MCP_NODE_PREFIX", mcp)

    def test_playwright_wrapper_executes_exact_npx_spec(self):
        if not BASH:
            self.skipTest("Bash is required")
        with tempfile.TemporaryDirectory(dir=ROOT) as temp:
            root = pathlib.Path(temp)
            fake = root / "npx"
            output = root / "args"
            fake.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$@" >"$NPM_ARGS"\n', encoding="utf-8")
            fake.chmod(0o755)
            wrapper = ROOT / "ai-assistants" / "SKILLS" / "playwright" / "scripts" / "playwright_cli.sh"
            result = subprocess.run(
                [BASH, bash_path(wrapper), "snapshot"],
                env={**os.environ, "PATH": f"{root}{os.pathsep}{os.environ.get('PATH', '')}", "NPM_ARGS": str(output)},
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                output.read_text(encoding="utf-8").splitlines(),
                ["--yes", "--package", "@playwright/cli@0.1.18", "playwright-cli", "snapshot"],
            )

    def test_playwright_docs_invoke_wrapper_through_bash(self):
        docs = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (ROOT / "ai-assistants" / "SKILLS" / "playwright").rglob("*.md")
        )
        self.assertNotIn('\n"$PWCLI"', docs)
        self.assertNotIn('alias pwcli="$PWCLI"', docs)

    def test_code_review_graph_tracks_current_release_in_common_config(self):
        expected = ["code-review-graph", "serve"]
        config_root = ROOT / "ai-assistants" / ".codex"
        common = tomllib.loads((config_root / "config.toml").read_text(encoding="utf-8"))
        self.assertEqual(common["mcp_servers"]["code-review-graph"]["args"], expected)
        self.assertNotIn("==", " ".join(expected))
        for filename in ("windows.config.toml", "linux.config.toml"):
            profile = tomllib.loads((config_root / filename).read_text(encoding="utf-8"))
            self.assertNotIn("code-review-graph", profile.get("mcp_servers", {}))

    def test_grok_config_is_cross_platform_and_minimal(self):
        path = ROOT / "ai-assistants" / ".grok" / "config.toml"
        text = path.read_text(encoding="utf-8")
        config = tomllib.loads(text)

        self.assertEqual(
            set(config["mcp_servers"]),
            {"code-review-graph", "mem0"},
        )
        self.assertEqual(
            config["mcp_servers"]["code-review-graph"]["args"],
            ["code-review-graph", "serve"],
        )
        for vendor in ("cursor", "claude"):
            self.assertEqual(
                config["compat"][vendor],
                {
                    "skills": False,
                    "rules": False,
                    "agents": False,
                    "mcps": False,
                    "hooks": False,
                    "sessions": False,
                },
            )
        self.assertEqual(config["compat"]["codex"], {"sessions": False})
        claude = json.loads(
            (ROOT / "ai-assistants" / ".claude" / "settings.json").read_text(
                encoding="utf-8"
            )
        )
        enabled_claude_plugins = {
            name.split("@", 1)[0]
            for name, enabled in claude.get("enabledPlugins", {}).items()
            if enabled
        }
        self.assertTrue(
            enabled_claude_plugins.issubset(set(config["plugins"]["disabled"]))
        )
        self.assertEqual(
            config["mcp_servers"]["mem0"],
            {"url": "https://mcp.mem0.ai/mcp"},
        )
        self.assertNotIn("model", config)
        self.assertNotIn("/home/", text)
        self.assertNotRegex(text, r"[A-Za-z]:\\")

        codex = tomllib.loads(
            (ROOT / "ai-assistants" / ".codex" / "config.toml").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(
            codex["mcp_servers"]["mem0"],
            {"url": "https://mcp.mem0.ai/mcp"},
        )


if __name__ == "__main__":
    unittest.main()
