from __future__ import annotations

import copy
from datetime import date
import importlib.util
import json
import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
MODULE_PATH = SCRIPTS_DIR / "validate_k7_surface_field_review.py"
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location(
    "validate_k7_surface_field_review",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)

REPOSITORY_ROOT = Path(__file__).parents[2]
TEMPLATE_PATH = (
    REPOSITORY_ROOT / "docs/testing/fixtures/"
    "k7-yokohama-kohoku-surface-field-review.template.json"
)


def template() -> dict:
    return json.loads(TEMPLATE_PATH.read_text(encoding="utf-8"))


def completed_review() -> dict:
    review = template()
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


class ValidateK7SurfaceFieldReviewTests(unittest.TestCase):
    def test_pending_template_fails_closed(self) -> None:
        report = validator.evaluate(template(), date(2026, 7, 23))

        self.assertFalse(report["field_review_complete"])
        self.assertFalse(report["route_release_authority"])
        self.assertIn(
            "CURRENT_LEGAL_DIRECTION_UNCONFIRMED",
            report["blockers"],
        )
        self.assertIn(
            "CHECKPOINT_PENDING:EXIT_RAMP_SIGNAL_APPROACH",
            report["blockers"],
        )

    def test_complete_coordinate_free_review_passes_field_gate_only(
        self,
    ) -> None:
        report = validator.evaluate(
            completed_review(),
            date(2026, 7, 24),
        )

        self.assertTrue(report["field_review_complete"])
        self.assertFalse(report["route_release_authority"])
        self.assertEqual(report["raw_evidence_file_count"], 4)
        self.assertEqual(report["blockers"], [])
        self.assertEqual(
            report["manifest_classification"],
            "PRIVATE_COORDINATE_FREE_REVIEW",
        )
        self.assertEqual(
            set(report),
            {
                "schema_version",
                "plan_id",
                "target",
                "as_of",
                "field_review_complete",
                "route_release_authority",
                "manifest_classification",
                "raw_evidence_file_count",
                "current_physical_status",
                "current_legal_direction",
                "permitted_exit_movement",
                "blockers",
            },
        )

    def test_driver_interaction_fails_closed(self) -> None:
        review = completed_review()
        review["collection"]["driver_interaction"] = True

        report = validator.evaluate(review, date(2026, 7, 24))

        self.assertFalse(report["field_review_complete"])
        self.assertIn(
            "DRIVER_INTERACTION_NOT_FORBIDDEN",
            report["blockers"],
        )

    def test_stale_field_review_fails_closed(self) -> None:
        review = completed_review()
        review["conclusions"]["valid_through"] = "2026-07-25"

        report = validator.evaluate(review, date(2026, 7, 26))

        self.assertFalse(report["field_review_complete"])
        self.assertIn("FIELD_REVIEW_STALE", report["blockers"])

    def test_unbound_checkpoint_hash_fails_closed(self) -> None:
        review = completed_review()
        review = copy.deepcopy(review)
        review["observations"][0]["evidence_sha256"] = ["f" * 64]

        report = validator.evaluate(review, date(2026, 7, 24))

        self.assertFalse(report["field_review_complete"])
        self.assertIn(
            "CHECKPOINT_EVIDENCE_UNBOUND:EXIT_RAMP_SIGNAL_APPROACH",
            report["blockers"],
        )

    def test_private_location_fields_are_rejected(self) -> None:
        review = completed_review()
        review["collection"]["latitude"] = 35.0

        with self.assertRaisesRegex(
            validator.FieldReviewError,
            "forbidden private-location field|collection keys have drifted",
        ):
            validator.evaluate(review, date(2026, 7, 24))

    def test_raw_media_field_is_rejected_even_without_location_key(self) -> None:
        review = completed_review()
        review["observations"][0]["photo_data"] = "embedded-private-media"

        with self.assertRaisesRegex(
            validator.FieldReviewError,
            "checkpoint EXIT_RAMP_SIGNAL_APPROACH keys have drifted",
        ):
            validator.evaluate(review, date(2026, 7, 24))

    def test_required_view_cannot_be_weakened(self) -> None:
        review = completed_review()
        review["observations"][0]["required_view"] = "One convenient photo."

        with self.assertRaisesRegex(
            validator.FieldReviewError,
            "required view has drifted",
        ):
            validator.evaluate(review, date(2026, 7, 24))

    def test_unreferenced_raw_evidence_hash_fails_closed(self) -> None:
        review = completed_review()
        review["collection"]["raw_evidence_sha256"].append("f" * 64)

        report = validator.evaluate(review, date(2026, 7, 24))

        self.assertFalse(report["field_review_complete"])
        self.assertIn(
            "RAW_EVIDENCE_HASHES_UNREFERENCED",
            report["blockers"],
        )

    def test_validity_window_is_bounded(self) -> None:
        review = completed_review()
        review["conclusions"]["valid_through"] = "2026-08-25"

        report = validator.evaluate(review, date(2026, 7, 24))

        self.assertFalse(report["field_review_complete"])
        self.assertIn(
            "REVIEW_VALIDITY_WINDOW_TOO_LONG",
            report["blockers"],
        )

    def test_completed_manifest_inside_repository_must_stay_ignored(
        self,
    ) -> None:
        validator.validate_review_input_path(TEMPLATE_PATH)

        with self.assertRaisesRegex(
            validator.FieldReviewError,
            "must stay under ignored research",
        ):
            validator.validate_review_input_path(
                REPOSITORY_ROOT / "data/field-review.json"
            )

    def test_allowed_exit_requires_active_forward_access(self) -> None:
        review = completed_review()
        review["conclusions"]["current_legal_direction"] = "REVERSE_ONLY"

        report = validator.evaluate(review, date(2026, 7, 24))

        self.assertFalse(report["field_review_complete"])
        self.assertIn("FIELD_CONCLUSIONS_CONFLICT", report["blockers"])


if __name__ == "__main__":
    unittest.main()
