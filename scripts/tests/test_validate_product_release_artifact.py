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
    / "kr-d26-product-release-requires-editor-atlas-coverage.json"
)
RUNTIME_USE_SCENARIO_PATH = (
    REPOSITORY_ROOT
    / "e2e"
    / "scenarios"
    / "kr-d27-product-runtime-live-input-authority.json"
)


class ValidateProductReleaseArtifactTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scenario = json.loads(SCENARIO_PATH.read_text(encoding="utf-8"))

    def validate_inputs(self, scenario: dict) -> list[str]:
        validation = validator.Validation(SCENARIO_PATH)
        validator.validate_product_release_artifact(
            validation,
            scenario["given"],
        )
        return validation.errors

    def test_declared_missing_editor_entity_is_derived_exactly(self) -> None:
        self.assertEqual(self.validate_inputs(self.scenario), [])
        self.assertIn(
            "PRODUCT_RELEASE_ARTIFACT_VALIDATED",
            validator.EVENT_TYPES,
        )
        self.assertIn(
            "PRODUCT_NAVIGATION_RUNTIME_CREATED",
            validator.EVENT_TYPES,
        )
        self.assertEqual(
            self.scenario["given"]["inputs"]["product_runtime_evidence_scope"],
            "SYNTHETIC_TEST_ONLY",
        )
        self.assertEqual(
            self.scenario["given"]["inputs"]["product_live_input_policy"],
            "DISABLED",
        )

    def test_product_runtime_use_declaration_is_required(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        del scenario["given"]["inputs"]["product_live_input_policy"]

        errors = self.validate_inputs(scenario)

        self.assertTrue(
            any("product_live_input_policy" in error for error in errors)
        )

    def test_synthetic_product_cannot_enable_live_input(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["given"]["inputs"][
            "product_live_input_policy"
        ] = "FOREGROUND_WHEN_IN_USE"

        errors = self.validate_inputs(scenario)

        self.assertTrue(
            any(
                "synthetic product release live input must be DISABLED" in error
                for error in errors
            )
        )

    def test_released_road_scope_rejects_synthetic_sources(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["given"]["inputs"][
            "product_runtime_evidence_scope"
        ] = "RELEASED_ROAD"

        errors = self.validate_inputs(scenario)

        self.assertTrue(
            any(
                "released-road product runtime cannot contain synthetic sources"
                in error
                for error in errors
            )
        )

    def test_wrong_missing_editor_declaration_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["given"]["inputs"][
            "product_release_expected_missing_editor_entity_ids"
        ] = []

        errors = self.validate_inputs(scenario)

        self.assertTrue(
            any(
                "must exactly match derived missing editor entities" in error
                for error in errors
            )
        )

    def test_adding_missing_entity_requires_an_empty_declaration(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        topology = scenario["given"]["inputs"]["route_atlas_topology"]
        topology["nodes"].append({"node_id": "test.node.product.editor-approach"})
        topology["edges"].append(
            {
                "edge_id": "test.topology-edge.product.editor-approach",
                "route_entity_id": "test.approach.product-release.exit",
                "from_node_id": "test.node.product.editor-approach",
                "to_node_id": "test.node.product.decision",
                "successor_edge_ids": ["test.topology-edge.product.movement"],
            }
        )

        errors = self.validate_inputs(scenario)

        self.assertTrue(
            any(
                'derived missing editor entities: []' in error
                for error in errors
            )
        )

    def test_route_plan_entity_missing_from_atlas_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        edges = scenario["given"]["inputs"]["route_atlas_topology"]["edges"]
        edges[:] = [
            edge
            for edge in edges
            if edge["route_entity_id"] != "test.edge.product-release.exit"
        ]

        errors = self.validate_inputs(scenario)

        self.assertTrue(
            any(
                "Route Atlas is missing RoutePlan entities" in error
                for error in errors
            )
        )

    def test_future_navigation_or_atlas_evidence_fails_validation(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        inputs = scenario["given"]["inputs"]
        inputs["navigation_release_released_at"] = "2026-07-25T12:00:00+09:00"
        inputs["route_atlas"]["evidence"]["checked_at"] = "2026-07-25"

        errors = self.validate_inputs(scenario)

        self.assertTrue(
            any(
                "navigation_release_released_at cannot follow" in error
                for error in errors
            )
        )
        self.assertTrue(
            any(
                "route_atlas.evidence.checked_at cannot follow" in error
                for error in errors
            )
        )


class ValidateProductRuntimeUseCasesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scenario = json.loads(
            RUNTIME_USE_SCENARIO_PATH.read_text(encoding="utf-8")
        )

    def validate_inputs(self, scenario: dict) -> list[str]:
        validation = validator.Validation(RUNTIME_USE_SCENARIO_PATH)
        validator.validate_product_runtime_use_cases(
            validation,
            scenario["given"],
            scenario["when"],
        )
        return validation.errors

    def test_runtime_use_cases_and_event_are_portable(self) -> None:
        self.assertEqual(self.validate_inputs(self.scenario), [])
        self.assertIn(
            "PRODUCT_RUNTIME_USE_EVALUATED",
            validator.EVENT_TYPES,
        )

    def test_runtime_use_event_must_reference_a_declared_case(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["when"][0]["payload"]["case_id"] = "missing-case"

        errors = self.validate_inputs(scenario)

        self.assertTrue(
            any("unknown case_id" in error for error in errors)
        )

    def test_each_runtime_source_domain_must_be_nonempty(self) -> None:
        scenario = copy.deepcopy(self.scenario)
        scenario["given"]["inputs"]["product_runtime_use_cases"][0][
            "route_atlas_sources"
        ] = []

        errors = self.validate_inputs(scenario)

        self.assertTrue(
            any(
                "route_atlas_sources must be a non-empty array" in error
                for error in errors
            )
        )


if __name__ == "__main__":
    unittest.main()
