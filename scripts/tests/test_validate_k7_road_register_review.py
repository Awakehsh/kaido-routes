from __future__ import annotations

import copy
from datetime import date
import importlib.util
import json
import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
MODULE_PATH = SCRIPTS_DIR / "validate_k7_road_register_review.py"
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location(
    "validate_k7_road_register_review",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)

REPOSITORY_ROOT = Path(__file__).parents[2]
TEMPLATE_PATH = (
    REPOSITORY_ROOT / "docs/testing/fixtures/"
    "k7-yokohama-kohoku-road-register-review.template.json"
)


def template() -> dict:
    return json.loads(TEMPLATE_PATH.read_text(encoding="utf-8"))


def completed_review() -> dict:
    review = template()
    digest = "a" * 64
    review["record_collection"] = {
        "status": "OBTAINED",
        "obtained_at": "2026-07-24T10:00:00+09:00",
        "obtained_via": "ROAD_SURVEY_DIVISION_COUNTER",
        "official_authority": "City of Yokohama Road Survey Division",
        "register_map_id": 66,
        "register_map_name_ja": "認定路線図",
        "record_current_through": "2026-07-24",
        "official_record_reference": (
            "Synthetic exact map-66 counter locator; not road evidence."
        ),
        "raw_record_sha256": [digest],
    }
    review["exact_mapping_review"] = {
        "status": "CONFIRMED",
        "recognized_route_identifier": "SYNTHETIC_CITY_ROAD_342",
        "recognized_route_name_ja": "合成市道第342号線",
        "compared_osm_way_ids": [734299108, 734299111, 776884422],
        "selected_osm_way_id": 776884422,
        "mapping_basis": (
            "Synthetic record comparison isolates the third successor; "
            "not road evidence."
        ),
        "record_evidence_sha256": [digest],
    }
    review["conclusions"] = {
        "reviewed_by": "synthetic-road-reviewer",
        "reviewer_role": "INDEPENDENT_ROAD_IDENTITY_REVIEWER",
        "reviewed_at": "2026-07-24T12:00:00+09:00",
        "valid_through": "2026-08-24",
    }
    return review


class ValidateK7RoadRegisterReviewTests(unittest.TestCase):
    def test_pending_template_fails_closed(self) -> None:
        report = validator.evaluate(template(), date(2026, 7, 24))

        self.assertFalse(report["road_identity_review_complete"])
        self.assertFalse(report["route_release_authority"])
        self.assertIn("OFFICIAL_RECORD_NOT_OBTAINED", report["blockers"])
        self.assertIn(
            "EXACT_OSM_WAY_MAPPING_UNCONFIRMED",
            report["blockers"],
        )

    def test_complete_coordinate_free_record_review_passes_only_identity_gate(
        self,
    ) -> None:
        report = validator.evaluate(
            completed_review(),
            date(2026, 7, 24),
        )

        self.assertTrue(report["road_identity_review_complete"])
        self.assertFalse(report["route_release_authority"])
        self.assertEqual(report["raw_record_file_count"], 1)
        self.assertEqual(report["selected_osm_way_id"], 776884422)
        self.assertEqual(report["blockers"], [])
        self.assertNotIn("reviewed_by", report)
        self.assertNotIn("raw_record_sha256", report)
        self.assertNotIn("mapping_basis", report)

    def test_online_map_cannot_replace_counter_record(self) -> None:
        review = completed_review()
        review["record_collection"]["obtained_via"] = "ONLINE_MAP_66"

        report = validator.evaluate(review, date(2026, 7, 24))

        self.assertFalse(report["road_identity_review_complete"])
        self.assertIn(
            "OFFICIAL_RECORD_METHOD_UNCONFIRMED",
            report["blockers"],
        )

    def test_map_67_cannot_replace_recognized_route_map(self) -> None:
        review = completed_review()
        review["record_collection"]["register_map_id"] = 67

        with self.assertRaisesRegex(
            validator.RoadRegisterReviewError,
            "official register",
        ):
            validator.evaluate(review, date(2026, 7, 24))

    def test_other_successor_cannot_be_selected(self) -> None:
        review = completed_review()
        review["exact_mapping_review"]["selected_osm_way_id"] = 734299108

        report = validator.evaluate(review, date(2026, 7, 24))

        self.assertFalse(report["road_identity_review_complete"])
        self.assertIn(
            "EXACT_OSM_WAY_SELECTION_UNCONFIRMED",
            report["blockers"],
        )

    def test_unbound_or_unreferenced_record_hash_fails_closed(self) -> None:
        review = completed_review()
        review["exact_mapping_review"]["record_evidence_sha256"] = ["b" * 64]

        report = validator.evaluate(review, date(2026, 7, 24))

        self.assertFalse(report["road_identity_review_complete"])
        self.assertIn("EXACT_MAPPING_EVIDENCE_UNBOUND", report["blockers"])
        self.assertIn(
            "RAW_OFFICIAL_RECORD_HASHES_UNREFERENCED",
            report["blockers"],
        )

    def test_stale_record_and_review_fail_closed(self) -> None:
        review = completed_review()
        review["record_collection"]["record_current_through"] = "2026-06-01"
        review["conclusions"]["valid_through"] = "2026-07-25"

        report = validator.evaluate(review, date(2026, 7, 26))

        self.assertFalse(report["road_identity_review_complete"])
        self.assertIn("OFFICIAL_RECORD_TOO_OLD", report["blockers"])
        self.assertIn("ROAD_IDENTITY_REVIEW_STALE", report["blockers"])

    def test_record_currentness_cannot_postdate_acquisition(self) -> None:
        review = completed_review()
        review["record_collection"]["record_current_through"] = "2026-07-25"
        review["conclusions"]["reviewed_at"] = "2026-07-25T12:00:00+09:00"
        review["conclusions"]["valid_through"] = "2026-08-24"

        report = validator.evaluate(review, date(2026, 7, 25))

        self.assertFalse(report["road_identity_review_complete"])
        self.assertIn(
            "OFFICIAL_RECORD_CURRENTNESS_POSTDATES_ACQUISITION",
            report["blockers"],
        )

    def test_validity_window_is_bounded_by_review_and_record(self) -> None:
        review = completed_review()
        review["conclusions"]["valid_through"] = "2026-08-25"

        report = validator.evaluate(review, date(2026, 7, 24))

        self.assertFalse(report["road_identity_review_complete"])
        self.assertIn(
            "ROAD_IDENTITY_REVIEW_VALIDITY_WINDOW_TOO_LONG",
            report["blockers"],
        )
        self.assertIn(
            "ROAD_IDENTITY_RECORD_VALIDITY_WINDOW_TOO_LONG",
            report["blockers"],
        )

    def test_extra_private_fields_are_rejected(self) -> None:
        review = copy.deepcopy(completed_review())
        review["record_collection"]["file_path"] = "/private/record.pdf"

        with self.assertRaisesRegex(
            validator.RoadRegisterReviewError,
            "record_collection keys have drifted",
        ):
            validator.evaluate(review, date(2026, 7, 24))

    def test_completed_manifest_inside_repository_must_stay_ignored(
        self,
    ) -> None:
        validator.validate_review_input_path(TEMPLATE_PATH)

        with self.assertRaisesRegex(
            validator.RoadRegisterReviewError,
            "must stay under ignored research",
        ):
            validator.validate_review_input_path(
                REPOSITORY_ROOT / "data/road-register-review.json"
            )


if __name__ == "__main__":
    unittest.main()
