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
    / "kr-u13-directional-entrance-explanation.json"
)


class ValidateEntranceRecommendationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scenario = json.loads(SCENARIO_PATH.read_text(encoding="utf-8"))

    def validate_inputs(self, scenario: dict) -> list[str]:
        validation = validator.Validation(SCENARIO_PATH)
        validator.validate_entrance_recommendation(
            validation,
            scenario["given"],
        )
        return validation.errors

    def test_directional_explanation_fixture_is_valid(self) -> None:
        self.assertEqual(self.validate_inputs(self.scenario), [])

    def test_duplicate_candidate_identity_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        candidates = scenario["given"]["inputs"]["entrance_candidates"]
        candidates[1]["facility_id"] = candidates[0]["facility_id"]

        errors = self.validate_inputs(scenario)

        self.assertTrue(
            any(
                "duplicate entrance candidate facility_id" in error
                for error in errors
            )
        )

    def test_invalid_candidate_metric_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        candidate = scenario["given"]["inputs"]["entrance_candidates"][0]
        candidate["surface_eta_minutes"] = -1

        errors = self.validate_inputs(scenario)

        self.assertTrue(
            any(
                "surface_eta_minutes must be finite and non-negative" in error
                for error in errors
            )
        )


if __name__ == "__main__":
    unittest.main()
