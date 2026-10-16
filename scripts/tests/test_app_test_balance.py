from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).parents[2]
MODULE_PATH = REPOSITORY_ROOT / "scripts" / "app_test_balance.py"
SPEC = importlib.util.spec_from_file_location("app_test_balance", MODULE_PATH)
assert SPEC and SPEC.loader
balance = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = balance
SPEC.loader.exec_module(balance)

DURATIONS = {
    "Unit/A/testSlow": 40.0,
    "Unit/A/testFast": 1.0,
    "Unit/B/testMedium": 25.0,
    "Unit/B/testShort": 14.0,
    "UI/A/testOne": 99.0,
}


class RecordTests(unittest.TestCase):
    def test_keeps_the_median_of_each_passed_test(self) -> None:
        logs = [
            "Test Case '-[Unit.A testSlow]' passed (30.000 seconds).\n"
            "Test Case '-[Unit.A testBroken]' failed (2.000 seconds).\n",
            "Test Case '-[Unit.A testSlow]' passed (50.000 seconds).\n",
            "Test Case '-[Unit.A testSlow]' passed (41.500 seconds).\n"
            "Test Case '-[Unit.B testOther]' passed (0.004 seconds).\n",
        ]
        self.assertEqual(
            balance.record(logs), {"Unit/A/testSlow": 41.5, "Unit/B/testOther": 0.004}
        )


class SelectTests(unittest.TestCase):
    def test_deals_the_longest_test_first_onto_the_lighter_shard(self) -> None:
        self.assertEqual(
            balance.shards(DURATIONS, "Unit", 2),
            [["Unit/A/testSlow"], ["Unit/A/testFast", "Unit/B/testMedium", "Unit/B/testShort"]],
        )

    def test_the_last_shard_runs_the_target_without_the_other_shards_tests(self) -> None:
        self.assertEqual(
            balance.select(DURATIONS, "Unit", 1, 2),
            ["-only-testing:Unit/A/testSlow"],
        )
        # A test absent from the durations, such as a new one, runs here.
        self.assertEqual(
            balance.select(DURATIONS, "Unit", 2, 2),
            [
                "-only-testing:Unit",
                "-skip-testing:Unit/A/testSlow",
            ],
        )

    def test_an_empty_named_shard_is_an_error_rather_than_the_whole_plan(self) -> None:
        with self.assertRaisesRegex(ValueError, "shard 2/3 has no recorded tests"):
            balance.select({"Unit/A/testOnly": 1.0}, "Unit", 2, 3)


if __name__ == "__main__":
    unittest.main()
