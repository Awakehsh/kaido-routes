from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest


SCRIPTS_DIR = Path(__file__).parents[1]
MODULE_PATH = SCRIPTS_DIR / "build_k7_schematic_layout_candidate.py"
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location(
    "build_k7_schematic_layout_candidate",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)

REPOSITORY_ROOT = Path(__file__).parents[2]
BASE_PATH = (
    REPOSITORY_ROOT
    / "data/route-atlas/candidates/"
    "k7-northwest-up-aoba-to-kohoku-osm-directed-candidate.json"
)
LAYOUT_PATH = (
    REPOSITORY_ROOT
    / "data/route-atlas/design/"
    "k7-northwest-up-schematic-layout-candidate.json"
)
CANDIDATE_PATH = (
    REPOSITORY_ROOT
    / "data/route-atlas/candidates/"
    "k7-northwest-up-aoba-to-kohoku-schematic-layout-candidate.json"
)
SCENARIO_PATH = (
    REPOSITORY_ROOT
    / "e2e/scenarios/"
    "kr-d24-k7-schematic-stops-at-surface-boundary.json"
)
SVG_PATH = (
    REPOSITORY_ROOT
    / "data/route-atlas/design/"
    "k7-northwest-up-schematic-layout-candidate.svg"
)


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class BuildK7SchematicLayoutCandidateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.base = load(BASE_PATH)
        self.layout = load(LAYOUT_PATH)
        self.expected_candidate = load(CANDIDATE_PATH)
        self.expected_scenario = load(SCENARIO_PATH)
        self.layout_sha256 = builder.sha256(LAYOUT_PATH)

    def test_rebuild_is_deterministic_and_stops_at_surface_boundary(
        self,
    ) -> None:
        candidate = builder.build_candidate(
            self.base,
            self.layout,
            self.layout_sha256,
        )

        self.assertEqual(candidate, self.expected_candidate)
        self.assertEqual(
            builder.build_scenario(candidate, self.layout),
            self.expected_scenario,
        )
        self.assertEqual(len(candidate["definition"]["segments"]), 15)
        terminal = next(
            segment
            for segment in candidate["definition"]["segments"]
            if segment["topology_edge_id"]
            == builder.EXPECTED_TERMINAL_EDGE_ID
        )
        self.assertEqual(terminal["to_node_id"], builder.EXPECTED_TERMINAL_NODE_ID)
        self.assertEqual(terminal["successor_segment_ids"], [])
        segment_id_text = json.dumps(
            candidate["definition"]["segments"],
            sort_keys=True,
        )
        for way_id in builder.EXPECTED_SURFACE_SUCCESSOR_WAY_IDS:
            self.assertNotIn(f"osm-way.{way_id}.", segment_id_text)

    def test_layout_source_is_separate_and_checksum_bound(self) -> None:
        candidate = builder.build_candidate(
            self.base,
            self.layout,
            self.layout_sha256,
        )

        reference = candidate["source_registry"]["references"][-1]
        self.assertEqual(
            reference["source_reference_id"],
            "kaido.layout.k7-northwest.2026-07-23",
        )
        self.assertEqual(reference["roles"], ["LAYOUT_EVIDENCE"])
        self.assertEqual(reference["content_sha256"], self.layout_sha256)
        self.assertEqual(
            candidate["definition"]["evidence"]["source_reference_ids"],
            ["kaido.layout.k7-northwest.2026-07-23"],
        )

    def test_surface_successor_leak_fails_closed(self) -> None:
        layout = copy.deepcopy(self.layout)
        layout["terminal_boundary"][
            "rendered_successor_topology_edge_ids"
        ] = [
            "shutoko.topology-edge.osm-way.776884422.forward"
        ]

        with self.assertRaisesRegex(
            builder.SchematicLayoutError,
            "surface boundary",
        ):
            builder.build_candidate(self.base, layout, self.layout_sha256)

    def test_node_collapse_fails_closed(self) -> None:
        layout = copy.deepcopy(self.layout)
        layout["nodes"][1]["point"] = layout["nodes"][0]["point"]

        with self.assertRaisesRegex(
            builder.SchematicLayoutError,
            "collapses two topology nodes",
        ):
            builder.build_candidate(self.base, layout, self.layout_sha256)

    def test_missing_topology_segment_fails_closed(self) -> None:
        layout = copy.deepcopy(self.layout)
        layout["segments"].pop()

        with self.assertRaisesRegex(
            builder.SchematicLayoutError,
            "segment coverage",
        ):
            builder.build_candidate(self.base, layout, self.layout_sha256)

    def test_tracked_svg_matches_renderer_and_carries_attribution(self) -> None:
        candidate = builder.build_candidate(
            self.base,
            self.layout,
            self.layout_sha256,
        )
        rendered = builder.render_svg(candidate, self.layout)

        self.assertEqual(rendered, SVG_PATH.read_text(encoding="utf-8"))
        self.assertIn("© OpenStreetMap contributors", rendered)
        self.assertIn("地表后继未审核 · 图在此停止", rendered)
        self.assertIn('data-navigation-authority="false"', rendered)


if __name__ == "__main__":
    unittest.main()
