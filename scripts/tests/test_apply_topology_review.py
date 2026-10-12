import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "apply_topology_review.py"
SPEC = importlib.util.spec_from_file_location("apply_topology_review", SCRIPT)
APPLY = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(APPLY)

EXTRACT_AT = "2026-08-04T20:20:51Z"


def position(node_id):
    return (35.0 + node_id * 1e-3, 139.0)


def way(way_id, node_ids, highway="motorway", kind="MAINLINE", **tags):
    return {
        "kind": kind,
        "node_ids": node_ids,
        "route_memberships": [],
        "tags": {"highway": highway, **tags},
        "version": 1,
        "way_id": way_id,
    }


def edges_of(record):
    return [
        {
            "direction": "forward",
            "edge_id": f"osm.{record['way_id']}.{index}.forward",
            "from_node_id": before,
            "kind": record["kind"],
            "length_meters": 100.0,
            "route_memberships": [],
            "segment_index": index,
            "to_node_id": after,
            "way_id": record["way_id"],
        }
        for index, (before, after) in enumerate(zip(record["node_ids"], record["node_ids"][1:]))
    ]


def network():
    # Carriageway 1→2 stops; it resumes 4→5 and runs on to the admitted
    # construction structure 5→6. An exit ramp leaves at 5, crosses the
    # surface road at node 7 and carries straight on as the entrance ramp
    # that rejoins the carriageway at 1.
    ways = [
        way(100, [1, 2]),
        way(101, [4, 5]),
        way(300, [5, 6], **{"kaido:source_highway": "construction"}),
        way(400, [5, 7, 8, 1], highway="motorway_link", kind="LINK"),
    ]
    return {
        "network_snapshot_id": "snap",
        "database_id": "db",
        "sources": {"osm": {"source_snapshot_at": EXTRACT_AT}},
        "routes": [{"route_id": "R", "osm_ref": "R"}],
        "nodes": [
            {"node_id": n, "latitude": position(n)[0], "longitude": position(n)[1], "tags": {}}
            for n in (1, 2, 4, 5, 6, 7, 8)
        ],
        "ways": ways,
        "edges": [edge for record in ways for edge in edges_of(record)],
        "directional_facilities": [
            {
                "facility_id": "f.a",
                "entry_edge_candidates": [{"distance_meters": 1.0, "edge_id": "osm.400.2.forward"}],
                "exit_edge_candidates": [{"distance_meters": 1.0, "edge_id": "osm.400.0.forward"}],
            }
        ],
        "junctions": [{"osm_node_ids": [1]}],
        "parking_areas": [],
    }


def record(way_id, node_ids, timestamp="2026-01-01T00:00:00Z", **tags):
    return {
        "way_id": way_id,
        "version": 1,
        "timestamp": timestamp,
        "tags": tags,
        "node_ids": node_ids,
        "nodes": [
            {
                "node_id": n,
                "latitude": position(n)[0],
                "longitude": position(n)[1],
                "version": 1,
                "timestamp": "2026-01-01T00:00:00Z",
            }
            for n in node_ids
        ],
    }


def crossing(removed=("osm.400.1.forward",)):
    return {
        "interchange": "A",
        "reason": "exit and entrance drawn as one chain",
        "crossing_node_ids": [7],
        "surface_ways": {"7": [{"way_id": 900, "highway": "primary"}]},
        "removed_edge_ids": list(removed),
        "continuations": [["osm.400.0.forward", "osm.400.2.forward"]],
    }


def review(**changes):
    base = {
        "schema_version": "1.0",
        "network_snapshot_id": "snap",
        "source": {"versions_current_at": EXTRACT_AT},
        "restored_chains": [{"route_id": "R", "way_ids": [200], "reason": "outside the relation"}],
        "removed_ways": [{"way_id": 300, "reason": "out of service"}],
        "cut_crossings": [crossing()],
        "unbound_candidates": [],
        "ways": [
            record(200, [2, 3, 4], highway="motorway", oneway="yes", ref="R"),
            record(300, [5, 6], highway="construction"),
        ],
    }
    base.update(changes)
    return base


def edge_ids(applied):
    return {edge["edge_id"] for edge in applied["edges"]}


class ApplyTopologyReviewTests(unittest.TestCase):
    def test_restores_removes_and_cuts_and_keeps_every_other_edge(self):
        before = network()
        applied = APPLY.apply_review(before, review())
        restored = [edge for edge in applied["edges"] if edge["way_id"] == 200]
        self.assertEqual([edge["edge_id"] for edge in restored], ["osm.200.0.forward", "osm.200.1.forward"])
        self.assertTrue(all(edge["kind"] == "MAINLINE" for edge in restored))
        self.assertEqual(restored[0]["route_memberships"], [{"directions_ja": [], "route_id": "R"}])
        self.assertAlmostEqual(
            restored[0]["length_meters"],
            round(APPLY.haversine_meters(position(2), position(3)), 3),
        )
        self.assertEqual(
            edge_ids(before) - edge_ids(applied),
            {"osm.300.0.forward", "osm.400.1.forward"},
        )
        self.assertNotIn(6, {node["node_id"] for node in applied["nodes"]})
        self.assertIn(3, {node["node_id"] for node in applied["nodes"]})
        self.assertTrue(APPLY.reaches(applied["edges"], 2, 4))

    def test_refuses_a_chain_that_closes_nothing(self):
        joined = network()
        joined["edges"].append({**joined["edges"][0], "edge_id": "bridge", "from_node_id": 2, "to_node_id": 4})
        with self.assertRaises(APPLY.TopologyApplyError):
            APPLY.apply_review(joined, review())

    def test_refuses_a_restored_way_that_is_not_the_routes_motorway(self):
        for tags in ({"highway": "motorway", "oneway": "yes", "ref": "Q"},
                     {"highway": "motorway_link", "oneway": "yes", "ref": "R"},
                     {"highway": "motorway", "oneway": "yes", "ref": "R", "access": "no"}):
            bad = review()
            bad["ways"][0] = record(200, [2, 3, 4], **tags)
            with self.assertRaises(APPLY.TopologyApplyError):
                APPLY.apply_review(network(), bad)

    def test_refuses_a_way_newer_than_the_extract(self):
        bad = review()
        bad["ways"][0] = record(
            200, [2, 3, 4], timestamp="2026-09-01T00:00:00Z",
            highway="motorway", oneway="yes", ref="R",
        )
        with self.assertRaises(APPLY.TopologyApplyError):
            APPLY.apply_review(network(), bad)

    def test_refuses_removing_a_way_that_is_not_an_admitted_construction(self):
        bad = review(
            removed_ways=[{"way_id": 101, "reason": "r"}],
            ways=[review()["ways"][0], record(101, [4, 5], highway="motorway")],
        )
        with self.assertRaises(APPLY.TopologyApplyError):
            APPLY.apply_review(network(), bad)

    def test_refuses_a_cut_away_from_the_surface_crossing(self):
        with self.assertRaises(APPLY.TopologyApplyError):
            APPLY.apply_review(network(), review(cut_crossings=[crossing(removed=["osm.400.2.forward"])]))

    def test_refuses_a_cut_that_leaves_the_chain_drivable(self):
        parallel = network()
        bypass = way(401, [7, 8], highway="motorway_link", kind="LINK")
        parallel["ways"].append(bypass)
        parallel["edges"].extend(edges_of(bypass))
        with self.assertRaises(APPLY.TopologyApplyError):
            APPLY.apply_review(parallel, review())

    def test_unbinds_only_the_bindings_the_review_lists(self):
        bound = network()
        bound["directional_facilities"][0]["exit_edge_candidates"].append(
            {"distance_meters": 1.0, "edge_id": "osm.400.1.forward"}
        )
        with self.assertRaises(APPLY.TopologyApplyError):
            APPLY.apply_review(bound, review())
        applied = APPLY.apply_review(bound, review(unbound_candidates=[
            {"facility_id": "f.a", "side": "exit", "edge_id": "osm.400.1.forward"},
        ]))
        self.assertEqual(
            applied["directional_facilities"][0]["exit_edge_candidates"],
            [{"distance_meters": 1.0, "edge_id": "osm.400.0.forward"}],
        )

    def test_refuses_a_review_from_another_snapshot(self):
        with self.assertRaises(APPLY.TopologyApplyError):
            APPLY.apply_review(network(), review(network_snapshot_id="elsewhere"))


if __name__ == "__main__":
    unittest.main()
