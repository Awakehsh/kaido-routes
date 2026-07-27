from __future__ import annotations

from datetime import date
import importlib.util
import json
import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
MODULE_PATH = SCRIPTS_DIR / "build_k7_navigation_release_inputs.py"
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location(
    "build_k7_navigation_release_inputs",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def approved_reviews(packet: dict) -> dict:
    roles = {
        "TOPOLOGY": "INDEPENDENT_TOPOLOGY_REVIEWER",
        "LAYOUT": "INDEPENDENT_LAYOUT_REVIEWER",
        "NAVIGATION_GUIDANCE": "INDEPENDENT_NAVIGATION_GUIDANCE_REVIEWER",
    }
    return {
        "schema_version": "1.0",
        "candidate_id": packet["candidate_id"],
        "candidate_bindings": packet["candidate_bindings"],
        "reviews": [
            {
                "scope": scope,
                "reviewer_id": f"test-{scope.lower()}-reviewer",
                "reviewer_role": role,
                "reviewed_at": f"2026-07-27T{hour}:00:00+09:00",
                "valid_through": "2026-08-26",
                "status": "APPROVED",
                "blocker_codes": [],
                "review_record_sha256": str(index + 1) * 64,
            }
            for index, (scope, role, hour) in enumerate(
                [
                    ("TOPOLOGY", roles["TOPOLOGY"], "10"),
                    ("LAYOUT", roles["LAYOUT"], "11"),
                    (
                        "NAVIGATION_GUIDANCE",
                        roles["NAVIGATION_GUIDANCE"],
                        "12",
                    ),
                ]
            )
        ],
    }


class BuildK7NavigationReleaseInputsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.atlas_draft = load(builder.ATLAS_DRAFT_PATH)
        self.navigation_draft = load(builder.NAVIGATION_DRAFT_PATH)
        self.packet = load(builder.REVIEW_PACKET_PATH)
        self.atlas_v1 = load(builder.ATLAS_V1_PATH)
        self.atlas_v1_authoring = load(builder.ATLAS_V1_AUTHORING_PATH)

    def build(self, reviews: dict | None = None):
        return builder.build_inputs(
            self.atlas_draft,
            self.navigation_draft,
            self.packet,
            reviews or approved_reviews(self.packet),
            self.atlas_v1,
            self.atlas_v1_authoring,
            date(2026, 7, 27),
        )

    def test_builds_exact_released_evidence_coverage(self) -> None:
        atlas, navigation, product = self.build()

        self.assertEqual(atlas["topology_evidence"]["state"], "RELEASED")
        self.assertEqual(atlas["layout_evidence"]["state"], "RELEASED")
        self.assertEqual(navigation["released_at"], "2026-07-27T12:00:00+09:00")
        self.assertEqual(
            [(value["role"], value["asset_id"]) for value in navigation["asset_evidence"]],
            [
                (
                    "EDITOR_CATALOG",
                    self.navigation_draft["editor_catalog_id"],
                ),
                (
                    "EDITOR_PRESENTATION",
                    self.navigation_draft["editor_presentation_catalog"][
                        "presentation_catalog_id"
                    ],
                ),
                (
                    "RUNTIME_POLICY",
                    self.navigation_draft["runtime_policy"]["runtime_policy_id"],
                ),
                (
                    "MATCHER_CORRIDOR",
                    self.navigation_draft["matcher_corridor"]["corridor_id"],
                ),
                *[
                    ("DECISION_ZONE", value["decision_zone_id"])
                    for value in self.navigation_draft["decision_zones"]
                ],
                *[
                    ("GUIDANCE", value["anchor"]["prompt_id"])
                    for value in self.navigation_draft["released_guidance"]
                ],
            ],
        )
        self.assertEqual(product["released_at"], "2026-07-27T12:00:01+09:00")

    def test_rejects_same_reviewer_across_scopes(self) -> None:
        reviews = approved_reviews(self.packet)
        reviews["reviews"][1]["reviewer_id"] = reviews["reviews"][0]["reviewer_id"]

        with self.assertRaisesRegex(
            builder.ReleaseInputError,
            "different reviewers",
        ):
            self.build(reviews)

    def test_rejects_unapproved_navigation_guidance(self) -> None:
        reviews = approved_reviews(self.packet)
        reviews["reviews"][2]["status"] = "BLOCKED"
        reviews["reviews"][2]["blocker_codes"] = ["GUIDANCE_TIMING_UNREVIEWED"]

        with self.assertRaisesRegex(
            builder.ReleaseInputError,
            "NAVIGATION_GUIDANCE review is not approved",
        ):
            self.build(reviews)

    def test_rejects_expired_review(self) -> None:
        with self.assertRaisesRegex(
            builder.ReleaseInputError,
            "review is not current",
        ):
            builder.build_inputs(
                self.atlas_draft,
                self.navigation_draft,
                self.packet,
                approved_reviews(self.packet),
                self.atlas_v1,
                self.atlas_v1_authoring,
                date(2026, 8, 27),
            )

    def test_rejects_navigation_draft_hash_drift(self) -> None:
        drifted = json.loads(json.dumps(self.navigation_draft))
        drifted["released_guidance"][1]["trigger_distance_meters"] = 251

        with self.assertRaisesRegex(
            builder.ReleaseInputError,
            "navigation draft hash drifted",
        ):
            builder.build_inputs(
                self.atlas_draft,
                drifted,
                self.packet,
                approved_reviews(self.packet),
                self.atlas_v1,
                self.atlas_v1_authoring,
                date(2026, 7, 27),
            )


if __name__ == "__main__":
    unittest.main()
