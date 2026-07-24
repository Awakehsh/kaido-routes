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

    def validate_runtime_policy(self, scenario: dict) -> list[str]:
        validation = validator.Validation(SCENARIO_PATH)
        validator.validate_navigation_runtime_policy(
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

    def test_runtime_policy_is_required_by_the_artifact(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        del scenario["given"]["inputs"]["navigation_runtime_policy"]

        errors = self.validate_inputs(scenario)

        self.assertTrue(
            any(
                "navigation release artifact inputs are missing: "
                "navigation_runtime_policy" in error
                for error in errors
            )
        )

    def test_runtime_entry_must_match_the_route_plan(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        policy = scenario["given"]["inputs"]["navigation_runtime_policy"]
        policy["entry_transition"]["facility_id"] = "test.entrance.other"

        errors = self.validate_runtime_policy(scenario)

        self.assertTrue(
            any(
                "entry_transition.facility_id must match" in error
                for error in errors
            )
        )

    def test_safe_rejoin_requires_a_released_candidate(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        policy = scenario["given"]["inputs"]["navigation_runtime_policy"]
        policy["recovery_candidates"] = []

        errors = self.validate_runtime_policy(scenario)

        self.assertTrue(
            any(
                "recovery_candidates requires a released safe rejoin" in error
                for error in errors
            )
        )

    def test_safe_rejoin_target_must_be_a_later_occurrence(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        inputs = scenario["given"]["inputs"]
        policy = inputs["navigation_runtime_policy"]
        policy["recovery_candidates"][0]["target_occurrence_id"] = (
            scenario["given"]["route_plan"]["occurrences"][0]["occurrence_id"]
        )

        errors = self.validate_runtime_policy(scenario)

        self.assertTrue(
            any(
                "target_occurrence_id must be later than the first RoutePlan "
                "occurrence" in error
                for error in errors
            )
        )

    def test_non_rejoin_policy_cannot_carry_rejoin_candidates(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["given"]["route_plan"]["recovery_policy"] = "STRICT"

        errors = self.validate_runtime_policy(scenario)

        self.assertTrue(
            any(
                "recovery_candidates are allowed only for SAFE_REJOIN" in error
                for error in errors
            )
        )

    def test_egress_cannot_replace_the_compiled_exit(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        policy = scenario["given"]["inputs"]["navigation_runtime_policy"]
        policy["egress_options"][0]["exit_facility_id"] = "test.exit.other"

        errors = self.validate_runtime_policy(scenario)

        self.assertTrue(
            any(
                "exit_facility_id must match given.route_plan.exit_facility_id"
                in error
                for error in errors
            )
        )


if __name__ == "__main__":
    unittest.main()
