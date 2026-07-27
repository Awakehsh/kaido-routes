import copy
import importlib.util
import json
import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
MODULE_PATH = SCRIPTS_DIR / "build_k7_route_atlas_candidate.py"
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location(
    "build_k7_route_atlas_candidate",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)

REPOSITORY_ROOT = Path(__file__).parents[2]


def load(relative_path: str) -> dict:
    return json.loads(
        (REPOSITORY_ROOT / relative_path).read_text(encoding="utf-8")
    )


class BuildK7RouteAtlasCandidateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.context = load(
            "data/route-atlas/context/"
            "mlit-n06-2025-current-shuto-context.json"
        )
        self.catalog = load(
            "data/route-atlas/context/"
            "operator-route-mark-catalog-2026-07-23.json"
        )
        self.review = load(
            "data/route-atlas/candidates/"
            "k7-northwest-up-aoba-to-kohoku-source-review.json"
        )

    def test_candidate_is_deterministic_and_stays_official_checked(self) -> None:
        first = builder.build(self.context, self.catalog, self.review)
        second = builder.build(self.context, self.catalog, self.review)

        self.assertEqual(first, second)
        self.assertEqual(
            first["topology_slice"]["evidence"]["state"],
            "OFFICIAL_CHECKED",
        )
        self.assertEqual(
            first["definition"]["evidence"]["state"],
            "OFFICIAL_CHECKED",
        )
        self.assertEqual(
            len(first["definition"]["segments"][0]["points"]),
            38,
        )
        self.assertEqual(
            first["definition"]["segments"][0]["points"][0],
            self.context["paths"][-1]["points"][-1],
        )
        self.assertEqual(
            {
                reference["source_reference_id"]
                for reference in first["source_registry"]["references"]
            },
            set(builder.EXPECTED_SOURCE_CONTRACTS),
        )
        self.assertEqual(
            self.catalog["naming_reconciliations"][0][
                "operator_source_reference_id"
            ],
            builder.EXPECTED_RECONCILIATION_SOURCE_ID,
        )

    def test_context_source_identity_drift_fails_closed(self) -> None:
        context = copy.deepcopy(self.context)
        path = next(
            path
            for path in context["paths"]
            if path["source_feature_id"] == builder.EXPECTED_FEATURE_ID
        )
        path["source_record_id"] = "EA02_DRIFT"

        with self.assertRaisesRegex(
            builder.CandidateBuildError,
            "exactly one K7 Northwest",
        ):
            builder.build(context, self.catalog, self.review)

    def test_release_blockers_cannot_be_removed(self) -> None:
        review = copy.deepcopy(self.review)
        review["release_blockers"] = []

        with self.assertRaisesRegex(
            builder.CandidateBuildError,
            "review boundary is incomplete",
        ):
            builder.build(self.context, self.catalog, review)

    def test_missing_required_stable_source_fails_closed(self) -> None:
        review = copy.deepcopy(self.review)
        review["source_references"] = [
            reference
            for reference in review["source_references"]
            if reference["source_reference_id"]
            != "shutoko.aoba-up-toll-map.2021-07-27"
        ]
        review["topology_evidence_source_ids"].remove(
            "shutoko.aoba-up-toll-map.2021-07-27"
        )

        with self.assertRaisesRegex(
            builder.CandidateBuildError,
            "source IDs have drifted",
        ):
            builder.build(self.context, self.catalog, review)

    def test_stable_source_hash_drift_fails_closed(self) -> None:
        review = copy.deepcopy(self.review)
        opening = next(
            reference
            for reference in review["source_references"]
            if reference["source_reference_id"]
            == builder.EXPECTED_RECONCILIATION_SOURCE_ID
        )
        opening["content_sha256"] = "0" * 64

        with self.assertRaisesRegex(
            builder.CandidateBuildError,
            "source contract has drifted",
        ):
            builder.build(self.context, self.catalog, review)

    def test_duplicate_reconciliation_url_and_hash_fails_closed(self) -> None:
        review = copy.deepcopy(self.review)
        opening = next(
            reference
            for reference in review["source_references"]
            if reference["source_reference_id"]
            == builder.EXPECTED_RECONCILIATION_SOURCE_ID
        )
        toll_map = next(
            reference
            for reference in review["source_references"]
            if reference["source_reference_id"]
            == "shutoko.aoba-up-toll-map.2021-07-27"
        )
        toll_map["source_url"] = opening["source_url"]
        toll_map["content_sha256"] = opening["content_sha256"]

        with self.assertRaisesRegex(
            builder.CandidateBuildError,
            "operator source identity has drifted",
        ):
            builder.validate_catalog(self.catalog, review)

    def test_claim_cannot_expand_an_operator_source_role(self) -> None:
        review = copy.deepcopy(self.review)
        entry_claim = next(
            claim
            for claim in review["reviewed_claims"]
            if claim["claim_id"] == "aoba-up-entrance-to-k7-northwest"
        )
        entry_claim["source_reference_ids"].append(
            "shutoko.aoba-up-toll-map.2021-07-27"
        )

        with self.assertRaisesRegex(
            builder.CandidateBuildError,
            "reviewed claim sources have drifted",
        ):
            builder.build(self.context, self.catalog, review)


if __name__ == "__main__":
    unittest.main()
