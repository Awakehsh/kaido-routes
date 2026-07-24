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
    / "kr-d25-versioned-navigation-release-artifact.json"
)


class ValidateNavigationReleaseArtifactTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scenario = json.loads(SCENARIO_PATH.read_text(encoding="utf-8"))

    def validate_inputs(self, scenario: dict) -> list[str]:
        validation = validator.Validation(SCENARIO_PATH)
        validator.validate_navigation_release_artifact(
            validation,
            scenario["given"],
        )
        return validation.errors

    def test_exact_provenance_fixture_is_valid(self) -> None:
        self.assertEqual(self.validate_inputs(self.scenario), [])
        self.assertIn(
            "NAVIGATION_RELEASE_ARTIFACT_VALIDATED",
            validator.EVENT_TYPES,
        )

    def test_missing_asset_evidence_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        evidence = scenario["given"]["inputs"][
            "navigation_release_asset_evidence"
        ]
        evidence[:] = [record for record in evidence if record["role"] != "GUIDANCE"]

        errors = self.validate_inputs(scenario)

        self.assertTrue(
            any(
                "missing navigation release asset evidence: GUIDANCE:"
                in error
                for error in errors
            )
        )

    def test_source_role_mismatch_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        source = scenario["given"]["inputs"]["navigation_release_sources"][0]
        source["roles"].remove("DECISION_ZONE")

        errors = self.validate_inputs(scenario)

        self.assertTrue(
            any(
                "does not support role DECISION_ZONE" in error
                for error in errors
            )
        )

    def test_unreleased_asset_evidence_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        evidence = scenario["given"]["inputs"][
            "navigation_release_asset_evidence"
        ][0]
        evidence["state"] = "OFFICIAL_CHECKED"

        errors = self.validate_inputs(scenario)

        self.assertTrue(
            any(".state must be RELEASED" in error for error in errors)
        )

    def test_malformed_source_roles_fail_without_crashing(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        source = scenario["given"]["inputs"]["navigation_release_sources"][0]
        source["roles"] = [{"unexpected": "object"}]

        errors = self.validate_inputs(scenario)

        self.assertTrue(
            any("roles must be unique known asset roles" in error for error in errors)
        )


if __name__ == "__main__":
    unittest.main()
