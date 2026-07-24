import copy
import importlib.util
import json
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).parents[2]
MODULE_PATH = REPOSITORY_ROOT / "scripts" / "validate_e2e.py"
SPEC = importlib.util.spec_from_file_location("validate_e2e", MODULE_PATH)
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)

SCENARIO_PATH = (
    REPOSITORY_ROOT
    / "e2e"
    / "scenarios"
    / "kr-s19-release-bound-entry-evidence.json"
)


class ValidateEntryTransitionAdmissionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scenario = json.loads(SCENARIO_PATH.read_text(encoding="utf-8"))

    def validate(self, scenario: dict) -> list[str]:
        validation = validator.Validation(SCENARIO_PATH)
        validator.validate_entry_transition_admission(
            validation,
            scenario["given"],
            scenario["when"],
        )
        return validation.errors

    def test_release_bound_entry_fixture_is_valid(self) -> None:
        self.assertEqual(self.validate(self.scenario), [])
        self.assertIn(
            "ENTRY_TRANSITION_EVIDENCE_OBSERVED",
            validator.EVENT_TYPES,
        )

    def test_entry_evidence_requires_an_explicit_source(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        del scenario["when"][1]["payload"]["source"]

        errors = self.validate(scenario)

        self.assertTrue(any("missing: source" in error for error in errors))

    def test_entry_admission_rejects_a_broken_successor_chain(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["given"]["inputs"]["matcher_corridor"]["edges"][0][
            "successor_edge_ids"
        ] = []

        errors = self.validate(scenario)

        self.assertTrue(any("does not lead to" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
