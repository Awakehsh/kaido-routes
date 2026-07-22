import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "build_osm_surface_graph.py"
SPEC = importlib.util.spec_from_file_location("build_osm_surface_graph", MODULE_PATH)
assert SPEC and SPEC.loader
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class OSMSurfaceGraphBuilderTests(unittest.TestCase):
    def test_osm_xml_preserves_lineage_and_direction(self) -> None:
        document = builder.parse_osm_xml(
            """<?xml version="1.0" encoding="UTF-8"?>
            <osm version="0.6">
              <node id="1" lat="35.0" lon="139.0" />
              <node id="2" lat="35.1" lon="139.1" />
              <way id="42">
                <nd ref="1" />
                <nd ref="2" />
                <tag k="highway" v="motorway_link" />
                <tag k="oneway" v="yes" />
              </way>
            </osm>""",
            "2026-07-22T14:00:00Z",
        )

        graph = builder.convert(
            document,
            "test.snapshot",
            "https://api.openstreetmap.org/api/0.6/map?bbox=test",
            "test.toll-domain",
            "test.provider-dataset.1",
        )

        self.assertEqual(graph["network_snapshot_id"], "test.snapshot")
        self.assertEqual(
            graph["provenance"]["source_snapshot_at"], "2026-07-22T14:00:00Z"
        )
        self.assertEqual(
            graph["provenance"]["source_dataset_id"], "test.provider-dataset.1"
        )
        self.assertEqual(len(graph["edges"]), 1)
        self.assertEqual(graph["edges"][0]["edge_id"], "osm.way.42.segment.0.forward")
        self.assertEqual(graph["edges"][0]["kind"], "ENTRY_TRANSITION")
        self.assertEqual(graph["edges"][0]["toll_domain_id"], "test.toll-domain")

    def test_osm_xml_requires_explicit_snapshot_time(self) -> None:
        with self.assertRaisesRegex(ValueError, "source-snapshot-at"):
            builder.parse_osm_xml('<osm version="0.6" />', None)

    def test_overpass_document_conversion_is_unchanged(self) -> None:
        graph = builder.convert(
            {
                "osm3s": {"timestamp_osm_base": "2026-07-22T14:00:00Z"},
                "elements": [
                    {"type": "node", "id": 1, "lat": 35.0, "lon": 139.0},
                    {"type": "node", "id": 2, "lat": 35.1, "lon": 139.1},
                    {
                        "type": "way",
                        "id": 7,
                        "nodes": [1, 2],
                        "tags": {"highway": "residential"},
                    },
                ],
            },
            "test.snapshot",
            "https://overpass-api.de/api/interpreter",
            None,
        )

        self.assertEqual(
            [edge["edge_id"] for edge in graph["edges"]],
            [
                "osm.way.7.segment.0.forward",
                "osm.way.7.segment.0.reverse",
            ],
        )


if __name__ == "__main__":
    unittest.main()
