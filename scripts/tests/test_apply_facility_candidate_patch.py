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


def network_1_1():
    reviewed = network()
    reviewed["routes"] = [{"route_id": "X"}, {"route_id": "Y"}]
    reviewed["junctions"] = [{
        "junction_id": "j.1",
        "osm_node_ids": [1, 7],
        "coordinate": {"latitude": 35.0004, "longitude": 139.0},
    }]
    return reviewed


def review_1_1(patches, **extra):
    return {**review(patches), "schema_version": "1.1", **extra}


def added(facility_id="f.c", route_id="X"):
    return {
        "facility_id": facility_id,
        "name_ja": "C",
        "reading_ja": "しー",
        "route_id": route_id,
        "entrance_directions": [],
        "exit_directions": ["上り"],
        "etc_only": False,
        "coordinate": {"latitude": 35.0006, "longitude": 139.0},
        "official_page_url": "https://example.invalid/c",
        "official_page_route_slug": "route-x",
        "operational_status": "AVAILABLE",
        "source_sha256": "0" * 64,
        "evidence": ["operator page"],
    }


class ApplyFacilityCandidatePatchSchema11Tests(unittest.TestCase):
    def test_kept_candidate_keeps_its_measured_distance(self):
        applied = APPLY.apply_review(network_1_1(), review_1_1([{
            "facility_id": "f.a", "reason": "re-reviewed", "evidence": ["osm way"],
            "entry_edge_candidates": ["ramp.in"],
            "expect": {"reaching_entrances": 0, "reachable_exits": 0},
        }]))
        entry = next(f for f in applied["directional_facilities"] if f["facility_id"] == "f.a")
        self.assertEqual(entry["entry_edge_candidates"], [{"distance_meters": 1.0, "edge_id": "ramp.in"}])

    def test_added_facility_follows_its_route_and_binds_through_a_patch(self):
        applied = APPLY.apply_review(network_1_1(), review_1_1(
            [{
                "facility_id": "f.c", "reason": "operator lists it", "evidence": ["osm way"],
                "exit_edge_candidates": ["ramp.out"],
                "expect": {"reaching_entrances": 1, "reachable_exits": 0},
            }],
            added_facilities=[added()],
        ))
        ids = [f["facility_id"] for f in applied["directional_facilities"]]
        self.assertEqual(ids, ["f.a", "f.b", "f.c"])
        new = applied["directional_facilities"][2]
        self.assertEqual([c["edge_id"] for c in new["exit_edge_candidates"]], ["ramp.out"])
        self.assertEqual(new["geometry_match_state"], "CANDIDATE_MATCHED")
        self.assertNotIn("evidence", new)

    def test_refuses_an_incomplete_or_duplicate_addition(self):
        incomplete = added()
        del incomplete["source_sha256"]
        for addition in (incomplete, {**added(), "evidence": []}, added("f.a"), added(route_id="Z")):
            with self.assertRaises(APPLY.FacilityCandidatePatchError):
                APPLY.apply_review(network_1_1(), review_1_1([], added_facilities=[addition]))

    def test_junction_patch_recomputes_the_coordinate_from_its_nodes(self):
        applied = APPLY.apply_review(network_1_1(), review_1_1([], junction_patches=[{
            "junction_id": "j.1", "osm_node_ids": [3, 1], "reason": "stray node",
            "evidence": ["osm node"],
        }]))
        junction = applied["junctions"][0]
        self.assertEqual(junction["osm_node_ids"], [1, 3])
        self.assertAlmostEqual(junction["coordinate"]["latitude"], 35.0002)
        for bad in (
            {"junction_id": "j.1", "osm_node_ids": [99], "reason": "r", "evidence": ["e"]},
            {"junction_id": "j.1", "osm_node_ids": [1], "reason": "r", "evidence": []},
            {"junction_id": "j.9", "osm_node_ids": [1], "reason": "r", "evidence": ["e"]},
        ):
            with self.assertRaises(APPLY.FacilityCandidatePatchError):
                APPLY.apply_review(network_1_1(), review_1_1([], junction_patches=[bad]))

    def test_another_routes_ramp_binds_only_when_named_cross_route(self):
        foreign = network_1_1()
        foreign["edges"][4]["route_memberships"] = [{"route_id": "Y", "directions_ja": []}]
        patch = {
            "facility_id": "f.b", "reason": "shared interchange", "evidence": ["osm way"],
            "exit_edge_candidates": ["ramp.out"],
            "expect": {"reaching_entrances": 1, "reachable_exits": 0},
        }
        with self.assertRaises(APPLY.FacilityCandidatePatchError):
            APPLY.apply_review(foreign, review_1_1([patch]))
        applied = APPLY.apply_review(foreign, review_1_1([
            {**patch, "cross_route": {"ramp.out": "OSM files the ramp under route Y"}},
        ]))
        exit_facility = next(f for f in applied["directional_facilities"] if f["facility_id"] == "f.b")
        self.assertEqual([c["edge_id"] for c in exit_facility["exit_edge_candidates"]], ["ramp.out"])


if __name__ == "__main__":
    unittest.main()
