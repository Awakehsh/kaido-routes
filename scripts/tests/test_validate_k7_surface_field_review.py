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
    REPOSITORY_ROOT
    / "docs/testing/fixtures/"
    "k7-yokohama-kohoku-surface-field-review.template.json"
)


def template() -> dict:
    return json.loads(TEMPLATE_PATH.read_text(encoding="utf-8"))


def completed_review() -> dict:
    review = template()
    hashes = [
        f"{index:064x}"
        for index in range(1, len(review["observations"]) + 1)
    ]
    review["collection"] = {
        "captured_at": "2026-07-24T10:00:00+09:00",
        "observer_role": "PASSENGER",
        "driver_interaction": False,
        "expressway_stop_required": False,
        "raw_evidence_sha256": hashes,
    }
    for observation, digest in zip(review["observations"], hashes):
        observation["status"] = "CAPTURED"
        observation["sign_findings"] = [
            "Synthetic test finding; not route evidence."
        ]
        observation["evidence_sha256"] = [digest]
    review["conclusions"] = {
        "current_physical_status": "ACTIVE",
        "current_legal_direction": "FORWARD_ONLY",
        "permitted_exit_movement": "ALLOWED",
        "reviewed_by": "synthetic-reviewer",
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
            "forbidden private-location field",
        ):
            validator.evaluate(review, date(2026, 7, 24))

    def test_allowed_exit_requires_active_forward_access(self) -> None:
        review = completed_review()
        review["conclusions"]["current_legal_direction"] = "REVERSE_ONLY"

        report = validator.evaluate(review, date(2026, 7, 24))

        self.assertFalse(report["field_review_complete"])
        self.assertIn("FIELD_CONCLUSIONS_CONFLICT", report["blockers"])


if __name__ == "__main__":
    unittest.main()
