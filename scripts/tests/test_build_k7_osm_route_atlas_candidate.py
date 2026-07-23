import copy
import importlib.util
import json
import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
MODULE_PATH = SCRIPTS_DIR / "build_k7_osm_route_atlas_candidate.py"
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location(
    "build_k7_osm_route_atlas_candidate",
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


class BuildK7OSMRouteAtlasCandidateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.review = load(
            "data/route-atlas/candidates/"
            "k7-northwest-up-aoba-to-kohoku-osm-directed-review.json"
        )
        self.database = load(
            "data/route-atlas/osm-derived/"
            "k7-northwest-260721-directed-database.json"
        )
        self.expected_candidate = load(
            "data/route-atlas/candidates/"
            "k7-northwest-up-aoba-to-kohoku-osm-directed-candidate.json"
        )
        self.expected_scenario = load(
            "e2e/scenarios/"
            "kr-d22-osm-directed-k7-candidate-remains-blocked.json"
        )
        self.successor_audit = load(
            "data/route-atlas/osm-derived/"
            "k7-northwest-260721-successor-audit.json"
        )
        self.successor_scenario = load(
            "e2e/scenarios/"
            "kr-d23-k7-source-successors-legal-review-blocked.json"
        )

    def test_candidate_rebuild_is_deterministic_and_non_authoritative(
        self,
    ) -> None:
        candidate = builder.build_candidate(self.database, self.review)

        self.assertEqual(candidate, self.expected_candidate)
        self.assertEqual(
            candidate["topology_slice"]["evidence"]["state"],
            "CANDIDATE",
        )
        self.assertEqual(
            candidate["definition"]["evidence"]["state"],
            "CANDIDATE",
        )
        self.assertEqual(len(candidate["route_plan"]["occurrences"]), 13)
        self.assertEqual(len(candidate["topology_slice"]["edges"]), 15)
        self.assertEqual(len(candidate["definition"]["segments"]), 15)
        self.assertEqual(
            builder.build_scenario(candidate, self.database, self.review),
            self.expected_scenario,
        )

    def test_two_reviewed_divergences_preserve_selected_and_alternative_edges(
        self,
    ) -> None:
        candidate = builder.build_candidate(self.database, self.review)
        edges = {
            edge["route_entity_id"]: edge
            for edge in candidate["topology_slice"]["edges"]
        }

        first = edges["shutoko.edge.osm-way.692798735.forward"]
        self.assertEqual(
            first["successor_edge_ids"],
            [
                "shutoko.topology-edge.osm-way.686983570.forward",
                "shutoko.topology-edge.osm-way.686983567.forward",
            ],
        )
        second = edges["shutoko.edge.osm-way.915062290.forward"]
        self.assertEqual(
            second["successor_edge_ids"],
            [
                "shutoko.topology-edge.osm-way.686983572.forward",
                "shutoko.topology-edge.osm-way.367046943.forward",
            ],
        )

    def test_database_direction_drift_fails_closed(self) -> None:
        database = copy.deepcopy(self.database)
        way = next(
            way
            for way in database["ways"]
            if way["id"] == 692755609
        )
        way["nodes"] = list(reversed(way["nodes"]))

        with self.assertRaisesRegex(
            builder.DirectedCandidateBuildError,
            "route discontinuity",
        ):
            builder.build_candidate(database, self.review)

    def test_database_keeps_odbl_boundary(self) -> None:
        self.assertEqual(self.database["licence"], "ODbL-1.0")
        self.assertEqual(
            self.database["attribution"],
            "© OpenStreetMap contributors",
        )
        self.assertFalse(self.database["navigation_authority"])
        self.assertEqual(len(self.database["route"]["way_ids"]), 13)
        self.assertEqual(len(self.database["divergence_alternatives"]), 2)
        boundary = self.database["facility_boundary_evidence"]
        self.assertEqual(boundary["entry_predecessor_way"]["id"], 1462532752)
        self.assertEqual(
            boundary["entry_nonroute_successor_way"]["id"],
            44421530,
        )
        self.assertEqual(
            [
                way["id"]
                for way in boundary["exit_surface_successor_ways"]
            ],
            [734299108, 734299111, 776884422],
        )

    def test_successor_audit_records_complete_source_adjacency_without_release(
        self,
    ) -> None:
        summary = self.successor_audit["summary"]
        self.assertEqual(summary["checkpoint_count"], 14)
        self.assertEqual(summary["observed_successor_count"], 19)
        self.assertTrue(summary["source_adjacency_exact"])
        self.assertFalse(summary["legal_review_complete"])
        self.assertEqual(summary["unresolved_legal_successor_count"], 1)
        self.assertEqual(summary["road_identity_reviewed_count"], 1)
        self.assertEqual(
            summary["current_legal_direction_confirmed_count"],
            0,
        )
        self.assertTrue(summary["field_verification_required"])
        self.assertEqual(
            self.successor_audit["source"]["bounded_extract_sha256"],
            self.database["source"]["bounded_extract_sha256"],
        )
        self.assertEqual(self.successor_audit["licence"], "ODbL-1.0")
        self.assertEqual(
            self.successor_audit["attribution"],
            "© OpenStreetMap contributors",
        )
        exit_checkpoint = next(
            checkpoint
            for checkpoint in self.successor_audit["checkpoints"]
            if checkpoint["checkpoint_id"] == "after-osm-way-734299106"
        )
        self.assertEqual(
            [
                successor["way_id"]
                for successor in exit_checkpoint["observed_successors"]
            ],
            [734299108, 734299111, 776884422],
        )
        self.assertEqual(self.successor_scenario["id"], "KR-D23")
        self.assertEqual(
            self.successor_audit["unresolved_legal_successors"][0][
                "reason_code"
            ],
            "CURRENT_TEMPORARY_PASSAGE_DIRECTION_UNCONFIRMED",
        )
        passage_evidence = self.successor_audit[
            "legal_successor_evidence"
        ][0]
        self.assertEqual(
            passage_evidence["road_identity"]["classification"],
            "LAND_READJUSTMENT_TEMPORARY_PASSAGE",
        )
        self.assertEqual(
            passage_evidence["current_legal_direction"],
            "UNCONFIRMED",
        )
        self.assertFalse(passage_evidence["release_eligible"])
        self.assertFalse(
            self.successor_scenario["given"]["system_state"][
                "legal_review_complete"
            ]
        )


if __name__ == "__main__":
    unittest.main()
