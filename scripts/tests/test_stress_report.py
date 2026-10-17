import importlib.util
import unittest
from pathlib import Path


STRESS = Path(__file__).parents[1] / "stress"


def load(name):
    spec = importlib.util.spec_from_file_location(name, STRESS / f"{name}.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


catalog = load("catalog")
report = load("report")


def run(seed, profile="URBAN", **fields):
    row = {
        "group": "planned", "route": "loop:c1-inner:1", "profile": profile, "extra": "", "seed": seed,
        "unadmitted": 10, "falseRecovery": 0, "wrong73": 0, "entered": True, "completed": True,
        "early": False, "finalTrigger": "-", "wall": 1.0,
    }
    row.update(fields)
    return row


def runs(*rows):
    return report.index(rows)


class StressVerdictTests(unittest.TestCase):
    def test_identical_trees_pass(self):
        base = runs(*(run(s) for s in range(1, 11)))
        passed, _, worse = report.verdict(base, dict(base))
        self.assertTrue(passed)
        self.assertEqual(worse, [])

    def test_timing_regresses_at_the_tolerance(self):
        base = runs(run(1))
        self.assertTrue(report.verdict(base, runs(run(1, unadmitted=14)))[0])
        self.assertFalse(report.verdict(base, runs(run(1, unadmitted=15)))[0])

    def test_one_more_contract_line_crossing_fails(self):
        base = runs(run(1, unadmitted=70), run(2))
        passed, _, worse = report.verdict(base, runs(run(1, unadmitted=76), run(2)), counts_only=True)
        self.assertFalse(passed)
        self.assertIn("runs >75 s unadmitted", [m for m, _, _ in worse[0][1]])

    def test_under2x_rows_inform_but_do_not_gate(self):
        base = runs(run(1, profile="UNDER2X"))
        passed, _, worse = report.verdict(base, runs(run(1, profile="UNDER2X", completed=False)))
        self.assertTrue(passed)
        self.assertEqual(len(worse), 1)

    def test_unpaired_runs_fail(self):
        self.assertFalse(report.verdict(runs(run(1), run(2)), runs(run(1)))[0])


class StressCatalogTests(unittest.TestCase):
    def test_default_drops_repeated_laps_but_keeps_the_later_lap_branch(self):
        default = {(c["group"], c["route"], c["extra"]) for c in catalog.select("default")}
        self.assertIn(("planned", "loop:c2:2", ""), default)
        self.assertNotIn(("planned", "loop:c2:3", ""), default)
        self.assertIn(("wrongBranch", "loop:c2:3", "pair=234,lap=2"), default)
        self.assertNotIn(("wrongBranch", "loop:c2:2", "pair=234,lap=2"), default)

    def test_selection_intersects_with_plus_and_removes_with_minus(self):
        cells = catalog.select("planned+laps1,-radial,-bundled")
        self.assertTrue(cells)
        self.assertTrue(all(c["group"] == "planned" and "radial" not in c["tags"] for c in cells))
        with self.assertRaises(ValueError):
            catalog.select("planned+nonsense")


if __name__ == "__main__":
    unittest.main()
