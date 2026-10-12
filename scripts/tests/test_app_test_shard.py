from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).parents[2]
MODULE_PATH = REPOSITORY_ROOT / "scripts" / "app_test_shard.py"
SPEC = importlib.util.spec_from_file_location("app_test_shard", MODULE_PATH)
assert SPEC and SPEC.loader
sharder = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = sharder
SPEC.loader.exec_module(sharder)


def enumeration(*identifiers: str, disabled: tuple[str, ...] = ()) -> dict:
    return {
        "errors": [],
        "values": [
            {
                "enabledTests": [{"identifier": name} for name in identifiers],
                "disabledTests": [{"identifier": name} for name in disabled],
            }
        ],
    }


class AppTestShardTests(unittest.TestCase):
    def test_every_enabled_test_of_the_target_lands_in_exactly_one_shard(self) -> None:
        tests = enumeration(
            "UI/B/testTwo()",
            "UI/A/testOne()",
            "UI/A/testTwo()",
            "UI/B/testOne()",
            "UI/C/testOne()",
            "Unit/A/testOne()",
            "UIExtra/A/testOne()",
            disabled=("UI/Audio/testSpeaks()",),
        )
        shards = [sharder.shard(tests, "UI", index, 2) for index in (1, 2)]
        self.assertEqual(
            shards,
            [
                ["UI/A/testOne", "UI/B/testOne", "UI/C/testOne"],
                ["UI/A/testTwo", "UI/B/testTwo"],
            ],
        )

    def test_an_empty_shard_is_an_error_rather_than_the_whole_plan(self) -> None:
        with self.assertRaisesRegex(ValueError, "shard 3/3 of 2 tests is empty"):
            sharder.shard(enumeration("UI/A/testOne()", "UI/A/testTwo()"), "UI", 3, 3)

    def test_an_enumeration_error_fails(self) -> None:
        tests = enumeration("UI/A/testOne()")
        tests["errors"] = ["no destination"]
        with self.assertRaisesRegex(ValueError, "test enumeration failed"):
            sharder.shard(tests, "UI", 1, 1)


if __name__ == "__main__":
    unittest.main()
