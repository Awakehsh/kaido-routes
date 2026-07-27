from __future__ import annotations

import copy
import importlib.util
import json
import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
MODULE_PATH = SCRIPTS_DIR / "build_k7_navigation_release_candidates.py"
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location(
    "build_k7_navigation_release_candidates",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class BuildK7NavigationReleaseCandidatesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.database = load(builder.DATABASE_PATH)
        self.atlas_v1 = load(builder.ATLAS_V1_PATH)

    def test_build_is_deterministic_and_occurrence_complete(self) -> None:
        first = builder.build(self.database, self.atlas_v1)
        second = builder.build(self.database, self.atlas_v1)

        self.assertEqual(first, second)
        atlas, navigation, packet = first
        self.assertEqual(atlas["route_plan"], navigation["route_plan"])
        self.assertEqual(
            [value["kind"] for value in navigation["route_plan"]["occurrences"]],
            [
                "EDGE",
                "JUNCTION_MOVEMENT",
                "EDGE",
                "JUNCTION_MOVEMENT",
                "EDGE",
            ],
        )
        self.assertEqual(
            navigation["route_plan"]["actual_distance_km"],
            7.031167671,
        )
        self.assertEqual(len(atlas["definition"]["occurrence_bindings"]), 5)
        self.assertEqual(len(navigation["matcher_corridor"]["occurrences"]), 5)
        self.assertEqual(len(navigation["decision_zones"]), 2)
        self.assertEqual(len(navigation["released_guidance"]), 2)
        self.assertEqual(packet["review_decisions"]["topology"], "PENDING")
        self.assertEqual(
            builder.encoded_json(atlas),
            builder.DEFAULT_ATLAS_DRAFT_PATH.read_bytes(),
        )
        self.assertEqual(
            builder.encoded_json(navigation),
            builder.DEFAULT_NAVIGATION_DRAFT_PATH.read_bytes(),
        )
        self.assertEqual(
            builder.encoded_json(packet),
            builder.DEFAULT_REVIEW_PACKET_PATH.read_bytes(),
        )

    def test_entry_transition_is_separate_from_strict_route(self) -> None:
        _atlas, navigation, _packet = builder.build(
            self.database,
            self.atlas_v1,
        )
        transition_ids = navigation["runtime_policy"]["entry_transition"][
            "directed_edge_ids"
        ]

        self.assertEqual(
            transition_ids,
            [
                "shutoko.edge.osm-way.574920138.forward",
                "shutoko.edge.osm-way.692426107.forward",
            ],
        )
        self.assertNotIn(
            transition_ids[0],
            [
                occurrence["entity_id"]
                for occurrence in navigation["route_plan"]["occurrences"]
            ],
        )

    def test_both_kohoku_movements_are_left_branches(self) -> None:
        _atlas, navigation, _packet = builder.build(
            self.database,
            self.atlas_v1,
        )
        guidance = navigation["released_guidance"]

        self.assertEqual(
            [value["frame_template"]["maneuver"] for value in guidance],
            ["TAKE_EXIT_LEFT", "TAKE_EXIT_LEFT"],
        )
        self.assertEqual(
            [
                value["frame_template"]["lane_preparation"]
                for value in guidance
            ],
            ["USE_LEFT_LANES", "USE_LEFT_LANES"],
        )
        self.assertEqual(
            guidance[0]["frame_template"]["presentation_source"][
                "japanese_sign_text"
            ],
            "第三京浜・出口へ",
        )

    def test_route_way_order_drift_fails_closed(self) -> None:
        database = copy.deepcopy(self.database)
        database["route"]["way_ids"][2:4] = reversed(
            database["route"]["way_ids"][2:4]
        )

        with self.assertRaisesRegex(
            builder.CandidateBuildError,
            "route way sequence drifted",
        ):
            builder.build(database, self.atlas_v1)

    def test_unreleased_atlas_input_fails_closed(self) -> None:
        atlas = copy.deepcopy(self.atlas_v1)
        atlas["definition"]["evidence"]["state"] = "CANDIDATE"

        with self.assertRaisesRegex(
            builder.CandidateBuildError,
            "layout is not released",
        ):
            builder.build(self.database, atlas)

    def test_terminal_atlas_excludes_surface_successors(self) -> None:
        atlas, _navigation, _packet = builder.build(
            self.database,
            self.atlas_v1,
        )
        edge_ids = {
            edge["edge_id"] for edge in atlas["topology_slice"]["edges"]
        }

        self.assertTrue(
            {
                "shutoko.topology-edge.osm-way.686983567.forward",
                "shutoko.topology-edge.osm-way.367046943.forward",
            }.issubset(edge_ids)
        )
        self.assertTrue(
            {
                "shutoko.topology-edge.osm-way.734299108.forward",
                "shutoko.topology-edge.osm-way.734299111.forward",
                "shutoko.topology-edge.osm-way.776884422.forward",
            }.isdisjoint(edge_ids)
        )


if __name__ == "__main__":
    unittest.main()
