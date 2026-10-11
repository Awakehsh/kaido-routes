import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "apply_facility_closure_review.py"
SPEC = importlib.util.spec_from_file_location("apply_facility_closure_review", SCRIPT)
APPLY = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(APPLY)


def facility(facility_id, entrances, exits, entry, exit_):
    return {
        "facility_id": facility_id,
        "entrance_directions": entrances,
        "exit_directions": exits,
        "entry_edge_candidates": [{"distance_meters": 1.0, "edge_id": e} for e in entry],
        "exit_edge_candidates": [{"distance_meters": 1.0, "edge_id": e} for e in exit_],
        "geometry_match_state": "CANDIDATE_MATCHED",
        "operational_status": "AVAILABLE",
    }


def network():
    # A: entrances both ways, exits both ways. B: exit-only, whose ramp A
    # also binds by radius. C: exit-only, bound to B's ramp and its own.
    return {
        "network_snapshot_id": "snap",
        "database_id": "db",
        "sources": {},
        "directional_facilities": [
            facility("f.a", ["内回り", "外回り"], ["内回り", "外回り"],
                     ["a.in.inner", "a.in.outer"], ["a.out", "b.out"]),
            facility("f.b", [], ["内回り", "外回り"], [], ["b.out", "a.out"]),
            facility("f.c", [], ["内回り"], [], ["c.out", "b.out"]),
        ],
    }


def review(closures):
    return {
        "schema_version": "1.0",
        "review_id": "closure-1",
        "checked_at": "2026-10-12",
        "network_snapshot_id": "snap",
        "closures": closures,
    }


def closure(facility_id, entrances=(), exits=(), edges=()):
    return {
        "facility_id": facility_id,
        "closed_entrance_directions": list(entrances),
        "closed_exit_directions": list(exits),
        "closed_ramp_edge_ids": list(edges),
        "reason": "operator notice",
        "evidence": ["https://example.invalid/notice"],
    }


def by_id(applied, facility_id):
    return next(f for f in applied["directional_facilities"] if f["facility_id"] == facility_id)


def edge_ids(candidates):
    return [candidate["edge_id"] for candidate in candidates]


class ApplyFacilityClosureReviewTests(unittest.TestCase):
    def test_one_closed_entrance_direction_keeps_the_rest_of_the_facility(self):
        applied = APPLY.apply_review(
            network(), review([closure("f.a", entrances=["内回り"], edges=["a.in.inner"])])
        )
        a = by_id(applied, "f.a")
        self.assertEqual(a["entrance_directions"], ["外回り"])
        self.assertEqual(a["exit_directions"], ["内回り", "外回り"])
        self.assertEqual(edge_ids(a["entry_edge_candidates"]), ["a.in.outer"])
        self.assertEqual(edge_ids(a["exit_edge_candidates"]), ["a.out", "b.out"])
        self.assertEqual(a["operational_status"], "AVAILABLE")

    def test_abolished_facility_is_unavailable_and_its_ramp_leaves_every_neighbour(self):
        applied = APPLY.apply_review(
            network(), review([closure("f.b", exits=["内回り", "外回り"], edges=["b.out"])])
        )
        b = by_id(applied, "f.b")
        self.assertEqual(b["operational_status"], "UNAVAILABLE")
        self.assertEqual(b["geometry_match_state"], "UNRESOLVED")
        self.assertEqual(b["exit_directions"], ["内回り", "外回り"])
        self.assertEqual(b["exit_edge_candidates"], [])
        self.assertEqual(edge_ids(by_id(applied, "f.a")["exit_edge_candidates"]), ["a.out"])
        self.assertEqual(edge_ids(by_id(applied, "f.c")["exit_edge_candidates"]), ["c.out"])

    def test_closing_every_direction_of_one_role_unbinds_that_role(self):
        applied = APPLY.apply_review(
            network(),
            review([closure("f.a", entrances=["内回り", "外回り"], edges=["a.in.inner"])]),
        )
        a = by_id(applied, "f.a")
        self.assertEqual(a["entrance_directions"], [])
        self.assertEqual(a["entry_edge_candidates"], [])
        self.assertEqual(a["operational_status"], "AVAILABLE")

    def test_refuses_a_closure_that_strands_a_neighbour(self):
        stranded = network()
        by_id(stranded, "f.c")["exit_edge_candidates"] = [{"distance_meters": 1.0, "edge_id": "b.out"}]
        with self.assertRaises(APPLY.FacilityClosureError):
            APPLY.apply_review(
                stranded, review([closure("f.b", exits=["内回り", "外回り"], edges=["b.out"])])
            )

    def test_refuses_closures_the_snapshot_does_not_support(self):
        for bad in (
            closure("f.missing", exits=["内回り"]),
            closure("f.c", exits=["外回り"]),
            closure("f.c", exits=["内回り"], edges=["a.in.inner"]),
            closure("f.c"),
            {**closure("f.c", exits=["内回り"]), "evidence": []},
        ):
            with self.assertRaises(APPLY.FacilityClosureError):
                APPLY.apply_review(network(), review([bad]))
        with self.assertRaises(APPLY.FacilityClosureError):
            APPLY.apply_review(
                network(), review([closure("f.c", exits=["内回り"]), closure("f.c", exits=["内回り"])])
            )
        other = review([])
        other["network_snapshot_id"] = "elsewhere"
        with self.assertRaises(APPLY.FacilityClosureError):
            APPLY.apply_review(network(), other)


if __name__ == "__main__":
    unittest.main()
