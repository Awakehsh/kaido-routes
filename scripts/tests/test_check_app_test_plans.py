from __future__ import annotations

import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).parents[2]
MODULE_PATH = REPOSITORY_ROOT / "scripts" / "check_app_test_plans.py"
SPEC = importlib.util.spec_from_file_location("check_app_test_plans", MODULE_PATH)
assert SPEC and SPEC.loader
checker = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = checker
SPEC.loader.exec_module(checker)


UNIT_SOURCE = """
import XCTest

final class RouteTests: XCTestCase {
  func testPlansRoute() {}
  func testRefusesSharedTollPoint() async throws {}
  private static func testLanguages() -> Int { 0 }
}

final class SpeakerTests: XCTestCase {
  func testSpeaks() {}
}
"""


def plan(*entries: dict) -> dict:
    return {
        "configurations": [{"id": "A", "name": "Default", "options": {}}],
        "defaultOptions": {},
        "testTargets": list(entries),
        "version": 1,
    }


def target(**selection: list[str]) -> dict:
    return {
        **selection,
        "target": {
            "containerPath": "container:App.xcodeproj",
            "identifier": "ID",
            "name": "AppTests",
        },
    }


class CheckAppTestPlansTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.directory)
        self.sources = self.directory / "Tests"
        self.sources.mkdir()
        (self.sources / "Tests.swift").write_text(UNIT_SOURCE, encoding="utf-8")

    def check(self, *plans: dict) -> list[str]:
        paths = []
        for index, content in enumerate(plans):
            path = self.directory / f"Plan{index}.xctestplan"
            path.write_text(json.dumps(content), encoding="utf-8")
            paths.append(path)
        return checker.check(paths, {"AppTests": self.sources})

    def test_discovers_instance_test_methods_per_class(self) -> None:
        self.assertEqual(
            checker.discover_tests(self.sources),
            {
                "RouteTests": {"testPlansRoute", "testRefusesSharedTollPoint"},
                "SpeakerTests": {"testSpeaks"},
            },
        )

    def test_a_target_included_whole_covers_every_test(self) -> None:
        self.assertEqual(self.check(plan(target())), [])

    def test_a_test_skipped_in_one_plan_may_run_in_another(self) -> None:
        self.assertEqual(
            self.check(
                plan(target(skippedTests=["SpeakerTests"])),
                plan(target(selectedTests=["SpeakerTests/testSpeaks()"])),
            ),
            [],
        )

    def test_a_test_no_plan_runs_fails(self) -> None:
        self.assertEqual(
            self.check(plan(target(skippedTests=["SpeakerTests"]))),
            ["AppTests/SpeakerTests/testSpeaks() runs in no test plan"],
        )

    def test_an_entry_naming_no_test_fails(self) -> None:
        errors = self.check(
            plan(target(skippedTests=["RouteTests/testRenamed()", "GoneTests"]))
        )
        self.assertEqual(
            errors,
            [
                "Plan0.xctestplan: AppTests names missing test RouteTests/testRenamed()",
                "Plan0.xctestplan: AppTests names missing test class GoneTests",
            ],
        )

    def test_a_disabled_target_covers_nothing(self) -> None:
        self.assertEqual(
            len(self.check(plan({**target(), "enabled": False}))),
            3,
        )


if __name__ == "__main__":
    unittest.main()
