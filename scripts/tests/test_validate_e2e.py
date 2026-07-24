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
    / "kr-u02-duplicate-reviewed-editor-lap.json"
)


class ValidateExpertRouteEditorLapTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scenario = json.loads(SCENARIO_PATH.read_text(encoding="utf-8"))

    def validate_catalog(self, scenario: dict) -> list[str]:
        validation = validator.Validation(SCENARIO_PATH)
        validator.validate_expert_route_editor(validation, scenario["given"])
        return validation.errors

    def test_reviewed_closed_lap_catalog_is_valid(self) -> None:
        self.assertEqual(self.validate_catalog(self.scenario), [])
        self.assertIn(
            "ROUTE_EDITOR_LAP_DUPLICATION_REQUESTED",
            validator.EVENT_TYPES,
        )

    def test_unclosed_lap_template_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        template = scenario["given"]["inputs"]["expert_route_editor_catalog"][
            "lap_templates"
        ][0]
        template["choice_ids"] = ["test.choice.exit"]

        errors = self.validate_catalog(scenario)

        self.assertTrue(
            any(
                "must form a reviewed closed choice sequence" in error
                for error in errors
            )
        )

    def test_duplicate_lap_template_identity_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        catalog = scenario["given"]["inputs"]["expert_route_editor_catalog"]
        catalog["lap_templates"].append(copy.deepcopy(catalog["lap_templates"][0]))

        errors = self.validate_catalog(scenario)

        self.assertTrue(
            any("duplicate editor lap template_id" in error for error in errors)
        )


if __name__ == "__main__":
    unittest.main()
