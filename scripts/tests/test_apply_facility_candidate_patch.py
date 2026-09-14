import importlib.util
import unittest
from copy import deepcopy
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "apply_facility_candidate_patch.py"
SPEC = importlib.util.spec_from_file_location("apply_facility_candidate_patch", SCRIPT)
APPLY = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(APPLY)


def edge(edge_id, from_node, to_node, kind="MAINLINE", route_id="X"):
    return {
        "edge_id": edge_id,
        "from_node_id": from_node,
        "to_node_id": to_node,
        "kind": kind,
        "length_meters": 10.0,
        "route_memberships": [{"route_id": route_id, "directions_ja": []}],
    }


def facility(facility_id, name, entry, exit_, route_id="X"):
    return {
        "facility_id": facility_id,
        "name_ja": name,
        "route_id": route_id,
        "coordinate": {"latitude": 35.0, "longitude": 139.0},
        "entrance_directions": ["上り"] if entry else [],
        "exit_directions": ["上り"] if exit_ else [],
        "entry_edge_candidates": [{"distance_meters": 1.0, "edge_id": e} for e in entry],
        "exit_edge_candidates": [{"distance_meters": 1.0, "edge_id": e} for e in exit_],
        "geometry_match_state": "CANDIDATE_MATCHED",
        "operational_status": "AVAILABLE",
    }


def network():
    # A one-way chain 1→2→3→4 with an entrance ramp onto 2 and an exit ramp
    # off 3, plus an opposite-role ramp the wrong binding would land on.
    return {
        "network_snapshot_id": "snap",
        "database_id": "db+pa-access-20260908",
        "sources": {},
        "nodes": [
            {"node_id": n, "latitude": 35.0 + n * 1e-4, "longitude": 139.0}
            for n in range(1, 8)
        ],
        "edges": [
            edge("m.1", 1, 2), edge("m.2", 2, 3), edge("m.3", 3, 4),
            edge("ramp.in", 5, 2, kind="LINK"),
            edge("ramp.out", 3, 6, kind="LINK"),
            edge("wrong.out", 7, 5, kind="LINK"),
            edge("pa.1", 4, 7, kind="PARKING"),
        ],
        "directional_facilities": [
            facility("f.a", "A", ["ramp.in"], []),
            facility("f.b", "B", [], ["wrong.out"]),
        ],
    }


def review(patches):
    return {
        "schema_version": "1.0",
        "review_id": "patch-1",
        "checked_at": "2026-09-14",
        "network_snapshot_id": "snap",
        "patches": patches,
    }


class ApplyFacilityCandidatePatchTests(unittest.TestCase):
    def test_repoints_exit_and_measures_distance_like_the_builder(self):
        applied = APPLY.apply_review(
            network(),
            review([{
                "facility_id": "f.b", "reason": "bound to the wrong ramp",
                "evidence": ["osm way"], "exit_edge_candidates": ["ramp.out"],
                "expect": {"reaching_entrances": 1, "reachable_exits": 0},
            }]),
        )
        exit_facility = next(f for f in applied["directional_facilities"] if f["facility_id"] == "f.b")
        self.assertEqual([c["edge_id"] for c in exit_facility["exit_edge_candidates"]], ["ramp.out"])
        expected = APPLY.distance_to_segment((35.0, 139.0), (35.0003, 139.0), (35.0006, 139.0))
        self.assertAlmostEqual(exit_facility["exit_edge_candidates"][0]["distance_meters"], round(expected, 3))
        counts = APPLY.pairing_counts(applied)
        self.assertEqual(counts["f.b"]["reaching_entrances"], 1)
        self.assertEqual(counts["f.a"]["reachable_exits"], 1)
        self.assertEqual(exit_facility["geometry_match_state"], "CANDIDATE_MATCHED")

    def test_wrong_binding_pairs_with_nothing_and_validation_refuses_it(self):
        counts = APPLY.pairing_counts(network())
        self.assertEqual(counts["f.b"]["reaching_entrances"], 0)
        with self.assertRaises(APPLY.FacilityCandidatePatchError):
            APPLY.validate(network(), review([{
                "facility_id": "f.b", "expect": {"reaching_entrances": 1, "reachable_exits": 0},
            }]))

    def test_unbinding_both_roles_marks_the_facility_unresolved(self):
        applied = APPLY.apply_review(
            network(),
            review([{
                "facility_id": "f.b", "reason": "twin without a ramp",
                "evidence": ["page"], "entry_edge_candidates": [], "exit_edge_candidates": [],
                "expect": {"reaching_entrances": 0, "reachable_exits": 0},
            }]),
        )
        twin = next(f for f in applied["directional_facilities"] if f["facility_id"] == "f.b")
        self.assertEqual(twin["exit_edge_candidates"], [])
        self.assertEqual(twin["geometry_match_state"], "UNRESOLVED")

    def test_refuses_parking_edges_foreign_routes_and_missing_evidence(self):
        for patch in (
            {"facility_id": "f.b", "evidence": ["x"], "exit_edge_candidates": ["pa.1"]},
            {"facility_id": "f.b", "evidence": ["x"], "exit_edge_candidates": ["missing"]},
            {"facility_id": "f.b", "exit_edge_candidates": ["ramp.out"]},
            {"facility_id": "f.a", "evidence": ["x"], "exit_edge_candidates": ["ramp.out"]},
        ):
            with self.assertRaises(APPLY.FacilityCandidatePatchError):
                APPLY.apply_review(network(), review([patch]))
        foreign = network()
        foreign["edges"][4]["route_memberships"] = [{"route_id": "Y", "directions_ja": []}]
        with self.assertRaises(APPLY.FacilityCandidatePatchError):
            APPLY.apply_review(foreign, review([{
                "facility_id": "f.b", "evidence": ["x"], "exit_edge_candidates": ["ramp.out"],
            }]))

    def test_refuses_a_review_from_another_snapshot(self):
        other = review([])
        other["network_snapshot_id"] = "elsewhere"
        with self.assertRaises(APPLY.FacilityCandidatePatchError):
            APPLY.apply_review(network(), other)


if __name__ == "__main__":
    unittest.main()
