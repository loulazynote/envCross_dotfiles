import fnmatch
import json
import pathlib
import tomllib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG_ROOT = ROOT / "ai-assistants" / ".codex"
CONFIG_FILES = ("config.toml", "windows.config.toml", "linux.config.toml")
SCOPE_VIOLATION_CEILING = 0


def flatten(value, path=()):
    if isinstance(value, dict):
        for key, child in value.items():
            yield from flatten(child, path + (key,))
        return
    yield ".".join(path)


def flatten_items(value, path=()):
    if isinstance(value, dict):
        for key, child in value.items():
            yield from flatten_items(child, path + (key,))
        return
    yield ".".join(path), value


class ConfigOwnershipTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads(
            (CONFIG_ROOT / "config-ownership.json").read_text(encoding="utf-8")
        )

    def owner_for(self, filename, path):
        matches = [
            rule["owner"]
            for rule in self.manifest["rules"]
            if filename in rule["files"]
            and any(fnmatch.fnmatchcase(path, pattern) for pattern in rule["patterns"])
        ]
        self.assertEqual(len(matches), 1, f"{filename}:{path} -> {matches}")
        return matches[0]

    def test_owner_names_are_valid_and_unique(self):
        owners = self.manifest["owners"]
        self.assertEqual(len(owners), len(set(owners)))
        self.assertEqual(set(self.manifest["target_files"]), set(owners))
        for rule in self.manifest["rules"]:
            self.assertIn(rule["owner"], owners)

    def test_scope_baseline_is_frozen(self):
        baseline = self.manifest["scope_violation_baseline"]
        self.assertEqual(len(baseline), len(set(baseline)))
        self.assertEqual(len(baseline), SCOPE_VIOLATION_CEILING)
        self.assertEqual(
            self.manifest["scope_violation_ceiling"], SCOPE_VIOLATION_CEILING
        )

    def test_every_leaf_has_exactly_one_owner(self):
        failures = []
        for filename in CONFIG_FILES:
            data = tomllib.loads((CONFIG_ROOT / filename).read_text(encoding="utf-8"))
            for path in flatten(data):
                try:
                    self.owner_for(filename, path)
                except AssertionError as error:
                    failures.append(str(error))
        self.assertEqual(failures, [])

    def test_scope_debt_is_explicit_and_cannot_grow(self):
        violations = []
        for filename in CONFIG_FILES:
            data = tomllib.loads((CONFIG_ROOT / filename).read_text(encoding="utf-8"))
            for path in flatten(data):
                owner = self.owner_for(filename, path)
                if filename not in self.manifest["target_files"][owner]:
                    violations.append(f"{filename}:{path}:{owner}")
        baseline = set(self.manifest["scope_violation_baseline"])
        self.assertLessEqual(len(violations), self.manifest["scope_violation_ceiling"])
        self.assertEqual(set(violations) - baseline, set())

    def test_profiles_do_not_repeat_common_settings(self):
        common = set(
            flatten(tomllib.loads((CONFIG_ROOT / "config.toml").read_text(encoding="utf-8")))
        )
        for filename in ("windows.config.toml", "linux.config.toml"):
            profile = set(
                flatten(
                    tomllib.loads((CONFIG_ROOT / filename).read_text(encoding="utf-8"))
                )
            )
            self.assertEqual(common & profile, set(), filename)

    def test_cross_platform_value_conflicts_require_distinct_owners(self):
        leaves = {}
        for filename in CONFIG_FILES:
            data = tomllib.loads((CONFIG_ROOT / filename).read_text(encoding="utf-8"))
            for path, value in flatten_items(data):
                leaves.setdefault(path, []).append(
                    (filename, value, self.owner_for(filename, path))
                )
        conflicts = []
        for path, records in leaves.items():
            values = {repr(value) for _, value, _ in records}
            if len(values) > 1:
                conflicts.append(
                    {
                        "path": path,
                        "files": sorted(filename for filename, _, _ in records),
                        "owners": sorted(owner for _, _, owner in records),
                    }
                )
        self.assertEqual(
            sorted(conflicts, key=lambda conflict: conflict["path"]),
            self.manifest["allowed_value_conflicts"],
        )


if __name__ == "__main__":
    unittest.main()
