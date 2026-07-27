from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
MODULE_PATH = SCRIPTS_DIR / "build_k7_pre_drive_evidence_inputs.py"
SPEC = importlib.util.spec_from_file_location(
    "build_k7_pre_drive_evidence_inputs",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


def reviewed_snapshot() -> dict:
    return json.loads(builder.DEFAULT_REVIEW_PATH.read_text(encoding="utf-8"))


class BuildK7PreDriveEvidenceInputsTests(unittest.TestCase):
    def test_builds_all_vehicle_and_payment_profiles(self) -> None:
        draft, authoring = builder.build_inputs(reviewed_snapshot())

        self.assertEqual(authoring["schema_version"], "1.0")
        self.assertEqual(
            authoring["release_id"],
            "shutoko.pre-drive.k7-aoba-to-kohoku.2026-07-27T2224+09",
        )
        profiles = {
            (
                record["evidence"]["vehicle_class"],
                record["evidence"]["payment_method"],
            )
            for record in draft["records"]
        }
        self.assertEqual(
            profiles,
            {
                (vehicle_class, payment_method)
                for vehicle_class in builder.VEHICLE_CLASSES
                for payment_method in builder.PAYMENT_METHODS
            },
        )
        self.assertTrue(
            all(
                record["evidence"]["passage_evidence"]
                == builder.PASSAGE_RESULT
                for record in draft["records"]
            )
        )

    def test_standard_profile_retains_reviewed_official_values(self) -> None:
        draft, _authoring = builder.build_inputs(reviewed_snapshot())
        records = {
            (
                record["evidence"]["vehicle_class"],
                record["evidence"]["payment_method"],
            ): record
            for record in draft["records"]
        }

        self.assertEqual(
            records[("STANDARD", "ETC")]["evidence"]["tariff_quotes"][0][
                "estimated_amount_yen"
            ],
            400,
        )
        self.assertEqual(
            records[("STANDARD", "CASH")]["evidence"]["tariff_quotes"][0][
                "estimated_amount_yen"
            ],
            1950,
        )
        self.assertEqual(
            records[("STANDARD", "ETC")]["evidence"]["tariff_quotes"][0][
                "tariff_distance_km"
            ],
            7.1,
        )

    def test_rejects_normalized_tariff_digest_drift(self) -> None:
        review = reviewed_snapshot()
        review["tariff_query"]["observations"][1]["etc_yen"] = 410

        with self.assertRaisesRegex(
            builder.EvidenceInputError,
            "ETC and ETC2 query results drifted",
        ):
            builder.build_inputs(review)

    def test_rejects_passage_upgrade_or_conflict(self) -> None:
        upgraded = reviewed_snapshot()
        upgraded["passage_review"]["result"] = "REALTIME_CONFIRMED_PASSABLE"
        with self.assertRaisesRegex(
            builder.EvidenceInputError,
            "must remain realtime-unconfirmed",
        ):
            builder.build_inputs(upgraded)

        conflict = reviewed_snapshot()
        conflict["passage_review"]["k7_northwest_restriction_count"] = 1
        with self.assertRaisesRegex(
            builder.EvidenceInputError,
            "reviewed conflict",
        ):
            builder.build_inputs(conflict)

    def test_rejects_chronology_drift(self) -> None:
        review = reviewed_snapshot()
        review["released_at"] = "2026-07-27T22:22:00+09:00"

        with self.assertRaisesRegex(
            builder.EvidenceInputError,
            "validity chronology",
        ):
            builder.build_inputs(review)

    def test_write_refuses_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            draft = Path(directory) / "draft.json"
            config = Path(directory) / "config.json"
            draft.write_text("{}\n", encoding="utf-8")

            with self.assertRaisesRegex(
                builder.EvidenceInputError,
                "already exists",
            ):
                builder.write_inputs(
                    builder.DEFAULT_REVIEW_PATH,
                    draft,
                    config,
                )


if __name__ == "__main__":
    unittest.main()
