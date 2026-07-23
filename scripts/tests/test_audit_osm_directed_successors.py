from __future__ import annotations

import copy
import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
MODULE_PATH = SCRIPTS_DIR / "audit_osm_directed_successors.py"
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location(
    "audit_osm_directed_successors",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
auditor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(auditor)


def way(
    way_id: int,
    start_node_id: int,
    end_node_id: int,
    *,
    highway: str = "motorway_link",
    oneway: str | None = "yes",
) -> dict:
    tags = {"highway": highway}
    if oneway is not None:
        tags["oneway"] = oneway
    return {
        "type": "way",
        "id": way_id,
        "nodes": [start_node_id, end_node_id],
        "tags": tags,
    }


def fixture() -> tuple[dict, dict, str]:
    extract_sha256 = "a" * 64
    parent_sha256 = "b" * 64
    source_extract = {
        "schema_version": "1.0",
        "source": {
            "input_sha256": parent_sha256,
            "source_snapshot_at": "2026-07-21T20:21:50Z",
        },
        "ways": [
            way(9, 1, 2),
            way(10, 2, 3),
            way(11, 3, 4),
            way(12, 2, 20),
        ],
        "boundary_ways": [
            way(13, 4, 30, highway="tertiary"),
            way(14, 4, 40, highway="tertiary", oneway=None),
        ],
        "relations": [],
    }
    review = {
        "review_id": "review.synthetic",
        "network_snapshot_id": "snapshot.synthetic",
        "route_plan_id": "plan.synthetic",
        "source_extract": {
            "expected_extract_sha256": extract_sha256,
            "parent_pbf_sha256": parent_sha256,
            "source_snapshot_at": "2026-07-21T20:21:50Z",
        },
        "route": {
            "entry_node_id": 2,
            "exit_node_id": 4,
            "way_ids": [10, 11],
        },
        "divergence_alternatives": [],
        "facility_boundary_checks": {
            "entry_predecessor_way_id": 9,
            "entry_nonroute_successor_way_id": 12,
            "exit_surface_successor_way_ids": [13, 14],
        },
        "successor_audit": {
            "audit_id": "audit.synthetic",
            "state": (
                "SOURCE_ADJACENCY_COMPLETE_LEGAL_REVIEW_INCOMPLETE"
            ),
            "navigation_authority": False,
            "unresolved_legal_successors": [
                {
                    "incoming_way_id": 11,
                    "via_node_id": 4,
                    "way_id": 14,
                    "direction": "FORWARD",
                    "reason_code": "SYNTHETIC_UNRESOLVED",
                }
            ],
            "release_blockers": ["Synthetic legal review is incomplete."],
        },
    }
    return source_extract, review, extract_sha256


class AuditOSMDirectedSuccessorsTests(unittest.TestCase):
    def test_exact_source_adjacency_preserves_bidirectional_surface_way(
        self,
    ) -> None:
        source_extract, review, extract_sha256 = fixture()

        result = auditor.build_audit(
            source_extract,
            review,
            extract_sha256,
        )

        self.assertEqual(result["summary"]["checkpoint_count"], 3)
        self.assertEqual(result["summary"]["observed_successor_count"], 5)
        self.assertTrue(result["summary"]["source_adjacency_exact"])
        self.assertFalse(result["summary"]["legal_review_complete"])
        exit_checkpoint = result["checkpoints"][-1]
        self.assertEqual(
            [
                (
                    successor["way_id"],
                    successor["direction"],
                    successor["oneway"],
                )
                for successor in exit_checkpoint["observed_successors"]
            ],
            [
                (13, "FORWARD", "yes"),
                (14, "FORWARD", "UNSPECIFIED"),
            ],
        )

    def test_unexpected_source_successor_fails_closed(self) -> None:
        source_extract, review, extract_sha256 = fixture()
        source_extract["boundary_ways"].append(
            way(15, 4, 50, highway="tertiary")
        )

        with self.assertRaisesRegex(
            auditor.SuccessorAuditError,
            "unexpected=.*15",
        ):
            auditor.build_audit(
                source_extract,
                review,
                extract_sha256,
            )

    def test_turn_restriction_drift_fails_closed(self) -> None:
        source_extract, review, extract_sha256 = fixture()
        source_extract = copy.deepcopy(source_extract)
        source_extract["relations"].append(
            {
                "type": "relation",
                "id": 100,
                "members": [
                    {"type": "way", "ref": 11, "role": "from"},
                    {"type": "node", "ref": 4, "role": "via"},
                    {"type": "way", "ref": 14, "role": "to"},
                ],
                "tags": {
                    "type": "restriction",
                    "restriction": "no_right_turn",
                },
            }
        )

        with self.assertRaisesRegex(
            auditor.SuccessorAuditError,
            "missing=.*14",
        ):
            auditor.build_audit(
                source_extract,
                review,
                extract_sha256,
            )


if __name__ == "__main__":
    unittest.main()
