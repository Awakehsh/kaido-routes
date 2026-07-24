from __future__ import annotations

from datetime import date
import importlib.util
import json
import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
MODULE_PATH = SCRIPTS_DIR / "validate_k7_route_atlas_readiness.py"
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location(
    "validate_k7_route_atlas_readiness",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)

REPOSITORY_ROOT = Path(__file__).parents[2]
READINESS_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/candidates/"
    "k7-northwest-up-aoba-to-kohoku-release-readiness.json"
)
FIELD_TEMPLATE_PATH = (
    REPOSITORY_ROOT / "docs/testing/fixtures/"
    "k7-yokohama-kohoku-surface-field-review.template.json"
)
ROAD_REVIEW_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/candidates/"
    "k7-northwest-up-aoba-to-kohoku-road-register-review.json"
)
CANDIDATE_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/candidates/"
    "k7-northwest-up-aoba-to-kohoku-schematic-layout-candidate.json"
)
DISTRIBUTION_REVIEW_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/osm-derived/"
    "k7-northwest-260721-distribution-review.json"
)
TOPOLOGY_REVIEW_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/candidates/"
    "k7-northwest-up-aoba-to-kohoku-topology-release-review.template.json"
)
LAYOUT_REVIEW_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/candidates/"
    "k7-northwest-up-aoba-to-kohoku-layout-release-review.template.json"
)


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def completed_field_review() -> dict:
    review = load(FIELD_TEMPLATE_PATH)
    hashes = [f"{index:064x}" for index in range(1, len(review["observations"]) + 1)]
    review["collection"] = {
        "captured_at": "2026-07-24T10:00:00+09:00",
        "observer_role": "PASSENGER",
        "driver_interaction": False,
        "expressway_stop_required": False,
        "unsafe_positioning_required": False,
        "lawful_travel_only": True,
        "raw_evidence_sha256": hashes,
    }
    for observation, digest in zip(review["observations"], hashes):
        observation["status"] = "CAPTURED"
        observation["sign_findings"] = ["Synthetic test finding; not route evidence."]
        observation["evidence_sha256"] = [digest]
    review["conclusions"] = {
        "current_physical_status": "ACTIVE",
        "current_legal_direction": "FORWARD_ONLY",
        "permitted_exit_movement": "ALLOWED",
        "reviewed_by": "synthetic-reviewer",
        "reviewer_role": "INDEPENDENT_REVIEWER",
        "reviewed_at": "2026-07-24T12:00:00+09:00",
        "valid_through": "2026-08-24",
    }
    return review


class ValidateK7RouteAtlasReadinessTests(unittest.TestCase):
    def test_tracked_candidate_has_exact_release_blockers(self) -> None:
        report = validator.evaluate(
            load(READINESS_PATH),
            date(2026, 7, 24),
            REPOSITORY_ROOT,
        )

        self.assertEqual(report["status"], "BLOCKED")
        self.assertFalse(report["candidate_ready_for_release_validation"])
        self.assertFalse(report["navigation_authority"])
        self.assertEqual(
            report["satisfied_gate_ids"],
            [
                "ARTIFACT_BINDINGS",
                "DIRECTED_CANDIDATE_STRUCTURE",
                "ODBL_DISTRIBUTION",
                "SOURCE_ADJACENCY",
            ],
        )
        self.assertEqual(
            report["blocker_codes"],
            [
                "CURRENT_ROAD_IDENTITY_UNCONFIRMED",
                "CURRENT_SURFACE_FIELD_REVIEW_INCOMPLETE",
                "UNRELEASED_ATLAS_EVIDENCE",
                "UNRELEASED_ATLAS_TOPOLOGY_EVIDENCE",
            ],
        )
        self.assertEqual(
            report["distribution_review_status"],
            "TECHNICAL_REVIEW_COMPLETE",
        )
        self.assertEqual(
            report["realtime_status"],
            "REALTIME_UNCONFIRMED",
        )
        self.assertFalse(report["realtime_release_blocking"])
        self.assertEqual(
            report["topology_release_review_status"],
            "PENDING",
        )
        self.assertFalse(report["topology_release_review_current"])
        self.assertEqual(
            report["layout_release_review_status"],
            "PENDING",
        )
        self.assertFalse(report["layout_release_review_current"])

    def test_artifact_digest_drift_is_rejected(self) -> None:
        readiness = load(READINESS_PATH)
        readiness["artifact_bindings"][0]["content_sha256"] = "0" * 64

        with self.assertRaisesRegex(
            validator.ReadinessError,
            "artifact binding digest drifted",
        ):
            validator.evaluate(
                readiness,
                date(2026, 7, 24),
                REPOSITORY_ROOT,
            )

    def test_malformed_binding_role_fails_without_crashing(self) -> None:
        readiness = load(READINESS_PATH)
        readiness["artifact_bindings"][0]["role"] = ["unexpected"]

        with self.assertRaisesRegex(
            validator.ReadinessError,
            "role must be a string",
        ):
            validator.evaluate(
                readiness,
                date(2026, 7, 24),
                REPOSITORY_ROOT,
            )

    def test_malformed_osm_roles_fail_without_crashing(self) -> None:
        candidate = load(CANDIDATE_PATH)
        osm_source = next(
            source
            for source in candidate["source_registry"]["references"]
            if source["source_reference_id"] == "osm.geofabrik.kanto-260721.k7-directed"
        )
        osm_source["roles"] = [{"unexpected": "object"}]

        with self.assertRaisesRegex(
            validator.ReadinessError,
            "ODbL source contract",
        ):
            validator.validate_candidate(candidate)

    def test_complete_field_review_clears_only_its_gate(self) -> None:
        readiness = load(READINESS_PATH)

        report = validator.evaluate(
            readiness,
            date(2026, 7, 24),
            REPOSITORY_ROOT,
            completed_field_review(),
        )

        self.assertNotIn(
            "CURRENT_SURFACE_FIELD_REVIEW_INCOMPLETE",
            report["blocker_codes"],
        )
        self.assertEqual(
            report["gate_states"]["CURRENT_SURFACE_FIELD_REVIEW"],
            "SATISFIED",
        )
        self.assertIn(
            "CURRENT_ROAD_IDENTITY_UNCONFIRMED",
            report["blocker_codes"],
        )
        self.assertEqual(
            report["field_review_input"],
            "PRIVATE_OVERRIDE",
        )
        self.assertRegex(
            report["field_review_manifest_sha256"],
            r"^[0-9a-f]{64}$",
        )
        self.assertFalse(report["navigation_authority"])

    def test_pending_topology_review_blocks_a_released_state(self) -> None:
        field_review = completed_field_review()
        complete, reviewer_id, status = validator.evaluate_topology_release_review(
            load(TOPOLOGY_REVIEW_PATH),
            date(2026, 7, 24),
            REPOSITORY_ROOT,
            "RELEASED",
            True,
            True,
            validator.canonical_sha256(field_review),
        )

        self.assertFalse(complete)
        self.assertIsNone(reviewer_id)
        self.assertEqual(status, "PENDING")

    def test_pending_layout_review_blocks_a_released_state(self) -> None:
        complete, reviewer_id, status = validator.evaluate_layout_release_review(
            load(LAYOUT_REVIEW_PATH),
            date(2026, 7, 24),
            REPOSITORY_ROOT,
            "RELEASED",
            True,
            "APPROVED",
            "topology-reviewer",
        )

        self.assertFalse(complete)
        self.assertIsNone(reviewer_id)
        self.assertEqual(status, "PENDING")

    def test_release_review_binding_digest_drift_is_rejected(self) -> None:
        review = load(TOPOLOGY_REVIEW_PATH)
        review["artifact_bindings"][0]["content_sha256"] = "0" * 64

        with self.assertRaisesRegex(
            validator.ReadinessError,
            "binding digest drifted",
        ):
            validator.evaluate_topology_release_review(
                review,
                date(2026, 7, 24),
                REPOSITORY_ROOT,
                "CANDIDATE",
                False,
                False,
                validator.canonical_sha256(completed_field_review()),
            )

    def test_release_review_validity_cannot_exceed_31_days(self) -> None:
        decision = {
            "status": "APPROVED",
            "reviewer_id": "independent-topology-reviewer",
            "reviewer_role": "INDEPENDENT_TOPOLOGY_REVIEWER",
            "reviewed_at": "2026-07-24T12:00:00+09:00",
            "valid_through": "2026-08-25",
            "blocker_codes": [],
        }

        with self.assertRaisesRegex(
            validator.ReadinessError,
            "validity window is too long",
        ):
            validator.evaluate_release_review_decision(
                decision,
                date(2026, 7, 24),
                "INDEPENDENT_TOPOLOGY_REVIEWER",
                "topology_release_review",
            )

    def test_approved_reviews_require_distinct_current_reviewers(self) -> None:
        field_review = completed_field_review()
        field_digest = validator.canonical_sha256(field_review)
        topology_review = load(TOPOLOGY_REVIEW_PATH)
        topology_review["required_checks"] = {
            "candidate_structure": "SATISFIED",
            "source_adjacency": "SATISFIED",
            "current_road_identity": "SATISFIED",
            "current_surface_field_review": "SATISFIED",
            "exact_legal_successor_review": "SATISFIED",
        }
        topology_review["private_field_review_manifest_sha256"] = field_digest
        topology_review["decision"] = {
            "status": "APPROVED",
            "reviewer_id": "independent-topology-reviewer",
            "reviewer_role": "INDEPENDENT_TOPOLOGY_REVIEWER",
            "reviewed_at": "2026-07-24T12:00:00+09:00",
            "valid_through": "2026-08-24",
            "blocker_codes": [],
        }
        topology_complete, topology_reviewer_id, _ = (
            validator.evaluate_topology_release_review(
                topology_review,
                date(2026, 7, 24),
                REPOSITORY_ROOT,
                "RELEASED",
                True,
                True,
                field_digest,
            )
        )
        self.assertTrue(topology_complete)

        layout_review = load(LAYOUT_REVIEW_PATH)
        layout_review["required_checks"] = {
            "topology_release_review": "SATISFIED",
            "layout_identity_and_coverage": "SATISFIED",
            "endpoint_and_successor_geometry": "SATISFIED",
            "surface_boundary_exclusion": "SATISFIED",
            "attribution_presentation": "SATISFIED",
            "independent_layout_review": "SATISFIED",
        }
        layout_review["decision"] = {
            "status": "APPROVED",
            "reviewer_id": topology_reviewer_id,
            "reviewer_role": "INDEPENDENT_LAYOUT_REVIEWER",
            "reviewed_at": "2026-07-24T14:00:00+09:00",
            "valid_through": "2026-08-24",
            "blocker_codes": [],
        }

        with self.assertRaisesRegex(
            validator.ReadinessError,
            "require different reviewers",
        ):
            validator.evaluate_layout_release_review(
                layout_review,
                date(2026, 7, 24),
                REPOSITORY_ROOT,
                "RELEASED",
                topology_complete,
                "APPROVED",
                topology_reviewer_id,
            )

        layout_review["decision"]["reviewer_id"] = "independent-layout-reviewer"
        layout_complete, layout_reviewer_id, status = (
            validator.evaluate_layout_release_review(
                layout_review,
                date(2026, 7, 24),
                REPOSITORY_ROOT,
                "RELEASED",
                topology_complete,
                "APPROVED",
                topology_reviewer_id,
            )
        )
        self.assertTrue(layout_complete)
        self.assertEqual(layout_reviewer_id, "independent-layout-reviewer")
        self.assertEqual(status, "APPROVED")

    def test_pending_road_register_review_stays_identity_blocked(
        self,
    ) -> None:
        review = load(ROAD_REVIEW_PATH)
        complete, blockers = validator.evaluate_road_register_review(
            review,
            date(2026, 7, 24),
        )

        self.assertFalse(complete)
        self.assertEqual(
            blockers,
            ["CURRENT_ROAD_IDENTITY_UNCONFIRMED"],
        )
        self.assertEqual(
            review["supporting_findings"]["official_corridor_identity"][
                "recognized_route_name_ja"
            ],
            "市道東方町第342号線",
        )
        self.assertEqual(
            review["supporting_findings"]["exact_osm_way_mapping"]["status"],
            "UNCONFIRMED",
        )

    def test_corridor_identity_cannot_promote_exact_osm_way_mapping(
        self,
    ) -> None:
        review = load(ROAD_REVIEW_PATH)
        review["supporting_findings"]["exact_osm_way_mapping"]["status"] = "CONFIRMED"

        with self.assertRaisesRegex(
            validator.ReadinessError,
            "road-register review contract",
        ):
            validator.evaluate_road_register_review(
                review,
                date(2026, 7, 24),
            )

    def test_road_register_source_reference_drift_is_rejected(
        self,
    ) -> None:
        review = load(ROAD_REVIEW_PATH)
        review["source_references"][0]["content_sha256"] = "0" * 64

        with self.assertRaisesRegex(
            validator.ReadinessError,
            "source reference contract",
        ):
            validator.evaluate_road_register_review(
                review,
                date(2026, 7, 24),
            )

    def test_malformed_road_register_layers_fail_without_crashing(
        self,
    ) -> None:
        review = load(ROAD_REVIEW_PATH)
        review["review_method"]["available_register_layers"] = [
            {"unexpected": "object"}
        ]

        with self.assertRaisesRegex(
            validator.ReadinessError,
            "road-register review contract",
        ):
            validator.evaluate_road_register_review(
                review,
                date(2026, 7, 24),
            )

    def test_confirmed_road_identity_requires_exact_record_fields(
        self,
    ) -> None:
        review = load(ROAD_REVIEW_PATH)
        review["review_method"]["exact_record_review_status"] = "CONFIRMED"
        review["current_road_identity"]["status"] = "CONFIRMED"
        review["decision"] = {
            "status": "READY_FOR_TOPOLOGY_REVIEW",
            "blocker_codes": [],
        }

        with self.assertRaisesRegex(
            validator.ReadinessError,
            "exact_record_reference",
        ):
            validator.evaluate_road_register_review(
                review,
                date(2026, 7, 24),
            )

    def test_distribution_status_cannot_replace_bound_review(
        self,
    ) -> None:
        readiness = load(READINESS_PATH)
        readiness["distribution_readiness"]["implementation_status"] = "PENDING"

        with self.assertRaisesRegex(
            validator.ReadinessError,
            "distribution contract has drifted",
        ):
            validator.evaluate(
                readiness,
                date(2026, 7, 24),
                REPOSITORY_ROOT,
            )

    def test_distribution_review_licence_url_drift_is_rejected(
        self,
    ) -> None:
        review = load(DISTRIBUTION_REVIEW_PATH)
        review["licence"]["url"] = "https://example.invalid/odbl"

        with self.assertRaisesRegex(
            validator.ReadinessError,
            "review licence has drifted",
        ):
            validator.validate_distribution_review(
                review,
                date(2026, 7, 24),
                REPOSITORY_ROOT,
            )

    def test_distribution_review_artifact_digest_drift_is_rejected(
        self,
    ) -> None:
        review = load(DISTRIBUTION_REVIEW_PATH)
        review["artifact_bindings"][0]["content_sha256"] = "0" * 64

        with self.assertRaisesRegex(
            validator.ReadinessError,
            "binding digest drifted",
        ):
            validator.validate_distribution_review(
                review,
                date(2026, 7, 24),
                REPOSITORY_ROOT,
            )

    def test_distribution_review_malformed_binding_role_fails_without_crashing(
        self,
    ) -> None:
        review = load(DISTRIBUTION_REVIEW_PATH)
        review["artifact_bindings"][0]["role"] = ["unexpected"]

        with self.assertRaisesRegex(
            validator.ReadinessError,
            "binding role must be a string",
        ):
            validator.validate_distribution_review(
                review,
                date(2026, 7, 24),
                REPOSITORY_ROOT,
            )

    def test_realtime_unconfirmed_cannot_be_promoted_by_readiness(
        self,
    ) -> None:
        readiness = load(READINESS_PATH)
        readiness["realtime_context"]["status"] = "OPEN"

        with self.assertRaisesRegex(
            validator.ReadinessError,
            "realtime context must remain unconfirmed",
        ):
            validator.evaluate(
                readiness,
                date(2026, 7, 24),
                REPOSITORY_ROOT,
            )

    def test_declared_decision_must_match_derived_result(self) -> None:
        readiness = load(READINESS_PATH)
        readiness["expected_decision"]["blocker_codes"] = []

        with self.assertRaisesRegex(
            validator.ReadinessError,
            "expected_decision does not match",
        ):
            validator.evaluate(
                readiness,
                date(2026, 7, 24),
                REPOSITORY_ROOT,
            )

    def test_assessment_cannot_postdate_as_of(self) -> None:
        with self.assertRaisesRegex(
            validator.ReadinessError,
            "assessment is in the future",
        ):
            validator.evaluate(
                load(READINESS_PATH),
                date(2026, 7, 23),
                REPOSITORY_ROOT,
            )


if __name__ == "__main__":
    unittest.main()
