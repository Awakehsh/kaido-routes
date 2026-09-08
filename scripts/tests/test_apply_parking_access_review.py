import importlib.util
import unittest
from copy import deepcopy
from pathlib import Path


SCRIPT_PATH = (
    Path(__file__).resolve().parents[1] / "apply_parking_access_review.py"
)
SPEC = importlib.util.spec_from_file_location(
    "apply_parking_access_review",
    SCRIPT_PATH,
)
assert SPEC is not None and SPEC.loader is not None
APPLY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(APPLY)


def network() -> dict:
    """A mainline with an access ramp that dead-ends and a return ramp that
    starts from nothing — the shape every parking area has in the build."""
    return {
        "network_snapshot_id": "test-snapshot",
        "database_id": "test.database.2026-01-01",
        "nodes": [
            {"node_id": 1, "latitude": 35.0, "longitude": 139.0, "tags": {}},
            {"node_id": 2, "latitude": 35.001, "longitude": 139.0, "tags": {}},
            {"node_id": 3, "latitude": 35.002, "longitude": 139.0, "tags": {}},
            {"node_id": 4, "latitude": 35.003, "longitude": 139.0, "tags": {}},
        ],
        "ways": [{"way_id": 10, "version": 1, "kind": "LINK", "node_ids": [1, 2], "route_memberships": [], "tags": {}}],
        "edges": [
            {
                "edge_id": "osm.10.0.forward",
                "from_node_id": 1,
                "to_node_id": 2,
                "way_id": 10,
                "segment_index": 0,
                "kind": "LINK",
                "direction": "forward",
                "length_meters": 111.0,
                "route_memberships": [],
            },
            {
                "edge_id": "osm.11.0.forward",
                "from_node_id": 3,
                "to_node_id": 4,
                "way_id": 11,
                "segment_index": 0,
                "kind": "LINK",
                "direction": "forward",
                "length_meters": 111.0,
                "route_memberships": [],
            },
        ],
        "parking_areas": [
            {
                "parking_area_id": "test.pa",
                "name_ja": "テストPA",
                "coordinate": {"latitude": 35.0015, "longitude": 139.0},
            }
        ],
    }


def review() -> dict:
    return {
        "schema_version": "1.0",
        "review_id": "test-review",
        "checked_at": "2026-01-02",
        "network_snapshot_id": "test-snapshot",
        "parking_areas": [
            {
                "parking_area_id": "test.pa",
                "access_node_id": 2,
                "return_node_id": 3,
                "interior_way": {
                    "way_id": 12,
                    "version": 6,
                    "timestamp": "2017-04-16T07:08:39Z",
                    "tags": {"highway": "service", "oneway": "yes"},
                    "node_ids": [2, 5, 3],
                    "nodes": [
                        {"node_id": 2, "latitude": 35.001, "longitude": 139.0},
                        {"node_id": 5, "latitude": 35.0015, "longitude": 139.0},
                        {"node_id": 3, "latitude": 35.002, "longitude": 139.0},
                    ],
                },
            }
        ],
    }


class ApplyParkingAccessReviewTests(unittest.TestCase):
    def test_interior_makes_the_parking_area_drivable(self) -> None:
        applied = APPLY.apply_review(network(), review())
        APPLY.validate(applied, review())

        parking_area = applied["parking_areas"][0]
        self.assertEqual(parking_area["access_node_id"], 2)
        self.assertEqual(parking_area["return_node_id"], 3)
        self.assertEqual(len(parking_area["interior_edge_ids"]), 2)
        # The access ramp now leads somewhere and the return ramp is fed.
        outgoing = {edge["from_node_id"] for edge in applied["edges"]}
        incoming = {edge["to_node_id"] for edge in applied["edges"]}
        self.assertIn(2, outgoing)
        self.assertIn(3, incoming)

    def test_interior_never_carries_route_membership(self) -> None:
        """This is what keeps a parking area out of route sequences and
        every fare path: the interior belongs to no numbered route."""
        applied = APPLY.apply_review(network(), review())
        parking = [
            edge
            for edge in applied["edges"]
            if edge["kind"] == APPLY.PARKING_EDGE_KIND
        ]
        self.assertEqual(len(parking), 2)
        self.assertTrue(all(not edge["route_memberships"] for edge in parking))

    def test_review_taken_against_another_snapshot_is_refused(self) -> None:
        drifted = review()
        drifted["network_snapshot_id"] = "other-snapshot"
        with self.assertRaises(APPLY.ParkingAccessApplyError):
            APPLY.apply_review(network(), drifted)

    def test_dead_end_that_moved_on_is_refused(self) -> None:
        """The pairing only means anything against the dead ends it was
        reviewed from; a stitched-on interior would be a guess."""
        moved = network()
        moved["edges"].append(
            {
                "edge_id": "osm.13.0.forward",
                "from_node_id": 2,
                "to_node_id": 4,
                "way_id": 13,
                "segment_index": 0,
                "kind": "LINK",
                "direction": "forward",
                "length_meters": 10.0,
                "route_memberships": [],
            }
        )
        with self.assertRaises(APPLY.ParkingAccessApplyError):
            APPLY.apply_review(moved, review())

    def test_interior_must_join_the_reviewed_dead_ends(self) -> None:
        wrong = review()
        wrong["parking_areas"][0]["interior_way"]["node_ids"] = [2, 5, 4]
        wrong["parking_areas"][0]["interior_way"]["nodes"][2] = {
            "node_id": 4,
            "latitude": 35.003,
            "longitude": 139.0,
        }
        with self.assertRaises(APPLY.ParkingAccessApplyError):
            APPLY.apply_review(network(), wrong)

    def test_two_way_interior_is_refused(self) -> None:
        bidirectional = review()
        bidirectional["parking_areas"][0]["interior_way"]["tags"] = {
            "highway": "service"
        }
        with self.assertRaises(APPLY.ParkingAccessApplyError):
            APPLY.apply_review(network(), bidirectional)

    def test_existing_node_coordinates_must_agree(self) -> None:
        drifted = review()
        drifted["parking_areas"][0]["interior_way"]["nodes"][0] = {
            "node_id": 2,
            "latitude": 35.9,
            "longitude": 139.0,
        }
        with self.assertRaises(APPLY.ParkingAccessApplyError):
            APPLY.apply_review(network(), drifted)

    def test_untouched_network_is_preserved(self) -> None:
        original = network()
        applied = APPLY.apply_review(deepcopy(original), review())
        applied_by_id = {edge["edge_id"]: edge for edge in applied["edges"]}
        for edge in original["edges"]:
            self.assertEqual(applied_by_id[edge["edge_id"]], edge)


def segment_review() -> dict:
    old = review()
    item = old["parking_areas"][0]
    return {
        "schema_version": "1.1", "network_snapshot_id": old["network_snapshot_id"],
        "ways": [item["interior_way"]], "parking_areas": [{
            "parking_area_id": "test.pa", "verification_state": "SOURCE_REVIEWED",
            "access_node_id": 2, "return_node_id": 3,
            "interior_segments": [{"way_id": 12, "segment_index": i} for i in (0, 1)]
        }]
    }


class ApplyParkingSegmentReviewTests(unittest.TestCase):
    def test_through_node_access_requires_the_explicit_interior(self):
        source = network()
        source["edges"].append(dict(source["edges"][0], edge_id="bypass", from_node_id=2, to_node_id=3))
        applied = APPLY.apply_review(source, segment_review())
        APPLY.validate(applied, segment_review())
        self.assertEqual(applied["parking_areas"][0]["interior_edge_ids"], ["osm.12.0.forward", "osm.12.1.forward"])
        self.assertTrue(any(e["edge_id"] == "bypass" for e in applied["edges"]))

    def test_disconnected_segments_are_rejected(self):
        invalid = segment_review()
        invalid["parking_areas"][0]["interior_segments"].reverse()
        with self.assertRaisesRegex(APPLY.ParkingAccessApplyError, "continuous"):
            APPLY.apply_review(network(), invalid)

    def test_opposite_parking_areas_cannot_share_an_interior(self):
        source = network()
        source["parking_areas"].append(dict(source["parking_areas"][0], parking_area_id="test.other"))
        invalid = segment_review()
        invalid["parking_areas"].append(dict(invalid["parking_areas"][0], parking_area_id="test.other"))
        with self.assertRaisesRegex(APPLY.ParkingAccessApplyError, "two directional"):
            APPLY.apply_review(source, invalid)

    def test_private_service_road_is_rejected(self):
        invalid = segment_review()
        invalid["ways"][0]["tags"]["access"] = "private"
        with self.assertRaisesRegex(APPLY.ParkingAccessApplyError, "motorcar access"):
            APPLY.apply_review(network(), invalid)

    def test_unreviewed_candidate_is_rejected(self):
        invalid = segment_review()
        invalid["parking_areas"][0]["verification_state"] = "CANDIDATE"
        with self.assertRaisesRegex(APPLY.ParkingAccessApplyError, "unreviewed"):
            APPLY.apply_review(network(), invalid)

    def test_existing_interior_is_reclassified_without_changing_its_identity(self):
        source = APPLY.apply_single_way_review(network(), review())
        for edge in source["edges"]:
            if edge["way_id"] == 12:
                edge["kind"] = "LINK"
                edge["route_memberships"] = [{"route_id": "4"}]
        applied = APPLY.apply_review(source, segment_review())
        self.assertTrue(all(e["route_memberships"] == [] for e in applied["edges"] if e["way_id"] == 12))
        self.assertEqual(len(applied["edges"]), 4)


if __name__ == "__main__":
    unittest.main()
