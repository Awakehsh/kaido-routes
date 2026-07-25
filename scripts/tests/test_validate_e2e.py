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
PRE_DRIVE_SCENARIO_PATH = (
    REPOSITORY_ROOT
    / "e2e"
    / "scenarios"
    / "kr-u04-pre-drive-review.json"
)
SAVED_ROUTE_LIFECYCLE_SCENARIO_PATH = (
    REPOSITORY_ROOT
    / "e2e"
    / "scenarios"
    / "kr-u19-saved-route-lifecycle.json"
)
NAVIGATION_RELEASE_SCENARIO_PATH = (
    REPOSITORY_ROOT
    / "e2e"
    / "scenarios"
    / "kr-d25-versioned-navigation-release-artifact.json"
)
ROUTE_ATLAS_AUTHORING_SCENARIO_PATH = (
    REPOSITORY_ROOT
    / "e2e"
    / "scenarios"
    / "kr-d28-route-atlas-release-authoring.json"
)
PRE_DRIVE_EVIDENCE_BUNDLE_SCENARIO_PATH = (
    REPOSITORY_ROOT
    / "e2e"
    / "scenarios"
    / "kr-d29-pre-drive-evidence-bundle.json"
)
SURFACE_EGRESS_MATCHER_SCENARIO_PATH = (
    REPOSITORY_ROOT
    / "e2e"
    / "scenarios"
    / "kr-s20-surface-egress-matcher-handoff.json"
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


class ValidatePreDriveEvidenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scenario = json.loads(
            PRE_DRIVE_SCENARIO_PATH.read_text(encoding="utf-8")
        )

    def validate_evidence(self, scenario: dict) -> list[str]:
        validation = validator.Validation(PRE_DRIVE_SCENARIO_PATH)
        validator.validate_tariff_quotes(
            validation,
            scenario["given"]["tariff_quotes"],
        )
        validator.validate_pre_drive_evidence(
            validation,
            scenario["given"],
        )
        return validation.errors

    def test_exact_pre_drive_evidence_is_valid(self) -> None:
        self.assertEqual(self.validate_evidence(self.scenario), [])

    def test_tariff_route_drift_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["given"]["tariff_quotes"][0][
            "exit_facility_id"
        ] = "test.exit.drift"

        errors = self.validate_evidence(scenario)

        self.assertTrue(
            any(
                "exit_facility_id must match given.route_plan" in error
                for error in errors
            )
        )

    def test_future_tariff_evidence_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["given"]["tariff_quotes"][0][
            "checked_at"
        ] = "2026-07-23T13:00:00+09:00"

        errors = self.validate_evidence(scenario)

        self.assertTrue(
            any("must not postdate pre-drive evaluation" in error for error in errors)
        )

    def test_tariff_vehicle_class_drift_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["given"]["tariff_quotes"][0]["vehicle_class"] = "LIGHT_MOTORCYCLE"

        errors = self.validate_evidence(scenario)

        self.assertTrue(
            any(
                "vehicle_class must match pre-drive evidence" in error
                for error in errors
            )
        )

    def test_provider_vehicle_class_drift_fails_session_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["given"]["inputs"]["pre_drive_evidence"]["vehicle_class"] = (
            "LIGHT_MOTORCYCLE"
        )
        for quote in scenario["given"]["tariff_quotes"]:
            quote["vehicle_class"] = "LIGHT_MOTORCYCLE"

        errors = self.validate_evidence(scenario)

        self.assertTrue(
            any(
                "vehicle_class must match pre-drive session" in error
                for error in errors
            )
        )

    def test_payment_method_is_not_accepted_as_vehicle_class(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["given"]["tariff_quotes"][0]["vehicle_class"] = "STANDARD_CAR_ETC"

        errors = self.validate_evidence(scenario)

        self.assertTrue(any("vehicle_class is unknown" in error for error in errors))

    def test_tariff_payment_method_drift_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["given"]["tariff_quotes"][0]["payment_method"] = "CASH"

        errors = self.validate_evidence(scenario)

        self.assertTrue(
            any(
                "payment_method must match pre-drive evidence" in error
                for error in errors
            )
        )

    def test_provider_payment_method_drift_fails_session_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["given"]["inputs"]["pre_drive_evidence"]["payment_method"] = "CASH"
        for quote in scenario["given"]["tariff_quotes"]:
            quote["payment_method"] = "CASH"

        errors = self.validate_evidence(scenario)

        self.assertTrue(
            any(
                "payment_method must match pre-drive session" in error
                for error in errors
            )
        )

    def test_missing_pre_drive_session_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        del scenario["given"]["inputs"]["pre_drive_session"]

        errors = self.validate_evidence(scenario)

        self.assertTrue(
            any("requires given.inputs.pre_drive_session" in error for error in errors)
        )


class ValidatePreDriveEvidenceBundleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scenario = json.loads(
            PRE_DRIVE_EVIDENCE_BUNDLE_SCENARIO_PATH.read_text(encoding="utf-8")
        )

    def validate_bundle(self, scenario: dict) -> list[str]:
        validation = validator.Validation(PRE_DRIVE_EVIDENCE_BUNDLE_SCENARIO_PATH)
        validator.validate_pre_drive_evidence_bundle(
            validation,
            scenario["given"],
            scenario["when"],
        )
        return validation.errors

    def test_exact_pre_drive_evidence_bundle_is_valid(self) -> None:
        self.assertEqual(self.validate_bundle(self.scenario), [])
        self.assertIn(
            "PRE_DRIVE_EVIDENCE_BUNDLE_RESOLVED",
            validator.EVENT_TYPES,
        )

    def test_missing_passage_source_role_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        manifest = scenario["given"]["inputs"]["pre_drive_evidence_bundle"]
        manifest["source_registry"][1]["roles"] = ["TARIFF_QUERY"]

        errors = self.validate_bundle(scenario)

        self.assertTrue(any("requires PASSAGE_REVIEW" in error for error in errors))

    def test_duplicate_tariff_profile_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        manifest = scenario["given"]["inputs"]["pre_drive_evidence_bundle"]
        duplicate = copy.deepcopy(manifest["records"][0])
        duplicate["record_id"] = "test.record.pre-drive-duplicate"
        manifest["records"].append(duplicate)

        errors = self.validate_bundle(scenario)

        self.assertTrue(any("duplicates a tariff profile" in error for error in errors))

    def test_event_identity_drift_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["when"][0]["payload"][
            "product_release_id"
        ] = "test.product.drift"

        errors = self.validate_bundle(scenario)

        self.assertTrue(
            any("product_release_id must match bundle" in error for error in errors)
        )

    def test_source_check_cannot_postdate_evidence_evaluation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        manifest = scenario["given"]["inputs"]["pre_drive_evidence_bundle"]
        manifest["source_registry"][0][
            "checked_at"
        ] = "2026-07-25T12:00:00+09:00"

        errors = self.validate_bundle(scenario)

        self.assertTrue(
            any(
                "must not postdate evidence evaluation" in error
                for error in errors
            )
        )


class ValidateSavedRouteLifecycleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scenario = json.loads(
            SAVED_ROUTE_LIFECYCLE_SCENARIO_PATH.read_text(encoding="utf-8")
        )

    def validate_lifecycle(self, scenario: dict) -> list[str]:
        validation = validator.Validation(SAVED_ROUTE_LIFECYCLE_SCENARIO_PATH)
        validator.validate_saved_route_library(validation, scenario["given"])
        validator.validate_saved_route_lifecycle_events(
            validation,
            scenario["given"],
            scenario["when"],
        )
        return validation.errors

    def test_exact_saved_route_lifecycle_is_valid(self) -> None:
        self.assertEqual(self.validate_lifecycle(self.scenario), [])

    def test_lifecycle_input_requires_one_event(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["when"] = [
            event
            for event in scenario["when"]
            if event["type"] != "SAVED_ROUTE_LIBRARY_LIFECYCLE_REQUESTED"
        ]

        errors = self.validate_lifecycle(scenario)

        self.assertTrue(any("requires exactly one" in error for error in errors))

    def test_lifecycle_event_requires_input(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        del scenario["given"]["inputs"]["saved_route_library"]["lifecycle"]

        errors = self.validate_lifecycle(scenario)

        self.assertTrue(
            any(
                "requires given.inputs.saved_route_library.lifecycle" in error
                for error in errors
            )
        )

    def test_lifecycle_event_requires_earlier_compile(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["when"].reverse()

        errors = self.validate_lifecycle(scenario)

        self.assertTrue(
            any(
                "requires an earlier ROUTE_COMPILE_REQUESTED" in error
                for error in errors
            )
        )

    def test_lifecycle_event_rejects_payload_authority(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["when"][1]["payload"] = {"record_id": "test.override"}

        errors = self.validate_lifecycle(scenario)

        self.assertTrue(any("payload must be empty" in error for error in errors))


class ValidateNavigationReleaseAuthoringTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scenario = json.loads(
            NAVIGATION_RELEASE_SCENARIO_PATH.read_text(encoding="utf-8")
        )

    def validate_authoring(self, scenario: dict) -> list[str]:
        validation = validator.Validation(NAVIGATION_RELEASE_SCENARIO_PATH)
        validator.validate_navigation_release_authoring_events(
            validation,
            scenario["given"],
            scenario["when"],
        )
        return validation.errors

    def test_navigation_release_authoring_event_is_valid(self) -> None:
        self.assertEqual(self.validate_authoring(self.scenario), [])

    def test_navigation_release_authoring_rejects_unknown_payload(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["when"][0]["payload"] = {"promote_synthetic": True}

        errors = self.validate_authoring(scenario)

        self.assertTrue(
            any("payload has unsupported keys" in error for error in errors)
        )

    def test_navigation_release_authoring_requires_artifact_inputs(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        del scenario["given"]["inputs"]["navigation_release_asset_evidence"]

        errors = self.validate_authoring(scenario)

        self.assertTrue(
            any(
                "requires navigation release artifact inputs" in error
                for error in errors
            )
        )

    def test_navigation_release_authoring_rejects_empty_schema(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["when"][0]["payload"] = {"draft_schema_version": ""}

        errors = self.validate_authoring(scenario)

        self.assertTrue(
            any("draft_schema_version must be non-empty" in error
                for error in errors)
        )


class ValidateRouteAtlasReleaseAuthoringTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scenario = json.loads(
            ROUTE_ATLAS_AUTHORING_SCENARIO_PATH.read_text(encoding="utf-8")
        )

    def validate_authoring(self, scenario: dict) -> list[str]:
        validation = validator.Validation(ROUTE_ATLAS_AUTHORING_SCENARIO_PATH)
        validator.validate_route_atlas_release_authoring_events(
            validation,
            scenario["given"],
            scenario["when"],
        )
        return validation.errors

    def test_route_atlas_release_authoring_event_is_valid(self) -> None:
        self.assertEqual(self.validate_authoring(self.scenario), [])

    def test_route_atlas_authoring_rejects_unknown_payload(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["when"][0]["payload"] = {"promote_candidate": True}

        errors = self.validate_authoring(scenario)

        self.assertTrue(
            any("payload has unsupported keys" in error for error in errors)
        )

    def test_route_atlas_authoring_requires_release_inputs(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        del scenario["given"]["inputs"]["route_atlas_sources"]

        errors = self.validate_authoring(scenario)

        self.assertTrue(
            any(
                "requires Route Atlas release inputs" in error
                for error in errors
            )
        )

    def test_route_atlas_authoring_rejects_empty_schema(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["when"][0]["payload"] = {
            "configuration_schema_version": ""
        }

        errors = self.validate_authoring(scenario)

        self.assertTrue(
            any(
                "configuration_schema_version must be non-empty" in error
                for error in errors
            )
        )


class ValidateSurfaceEgressMatcherAdmissionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scenario = json.loads(
            SURFACE_EGRESS_MATCHER_SCENARIO_PATH.read_text(encoding="utf-8")
        )

    def validate_admission(self, scenario: dict) -> list[str]:
        validation = validator.Validation(SURFACE_EGRESS_MATCHER_SCENARIO_PATH)
        validator.validate_surface_egress_matcher_admission(
            validation,
            scenario["given"],
            scenario["when"],
        )
        return validation.errors

    def test_exact_surface_egress_matcher_admission_is_valid(self) -> None:
        self.assertEqual(self.validate_admission(self.scenario), [])
        self.assertIn(
            "SURFACE_EGRESS_MATCHER_OBSERVATION_RECEIVED",
            validator.EVENT_TYPES,
        )

    def test_repeated_edge_geometry_drift_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        admission = scenario["given"]["inputs"][
            "surface_egress_matcher_admission"
        ]
        admission["occurrences"][2]["coordinates"][1]["longitude"] = 139.763

        errors = self.validate_admission(scenario)

        self.assertTrue(
            any("repeated edge geometry must be identical" in error for error in errors)
        )

    def test_unreleased_exit_option_drift_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        option = scenario["given"]["inputs"]["precomputed_egress_options"][0]
        option["released"] = False

        errors = self.validate_admission(scenario)

        self.assertTrue(
            any("must match one released precomputed egress option" in error
                for error in errors)
        )

    def test_invalid_observation_course_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["when"][2]["payload"]["course_degrees"] = 360

        errors = self.validate_admission(scenario)

        self.assertTrue(
            any("course_degrees is invalid" in error for error in errors)
        )


if __name__ == "__main__":
    unittest.main()
