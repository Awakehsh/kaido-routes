import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT_PATH = (
    Path(__file__).resolve().parents[1] / "build_shuto_network.py"
)
SPEC = importlib.util.spec_from_file_location(
    "build_shuto_network",
    SCRIPT_PATH,
)
assert SPEC is not None and SPEC.loader is not None
BUILD_SHUTO_NETWORK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD_SHUTO_NETWORK)


class BuildShutoNetworkTests(unittest.TestCase):
    def test_candidate_review_accepts_full_facility_search_radius(
        self,
    ) -> None:
        review = {
            "schema_version": "1.2",
            "excluded_candidates": [],
            "entry_candidate_replacements": [],
            "entry_boundary_rebindings": [
                {
                    "facility_id": "test.entry",
                    "anchor_edge_id": "test.anchor",
                    "boundary_edge_id": "test.boundary",
                    "distance_meters": 750.0,
                    "reason": "reviewed boundary",
                    "evidence": "reviewed topology",
                }
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "review.json"
            path.write_text(json.dumps(review), encoding="utf-8")

            loaded, digest = BUILD_SHUTO_NETWORK.load_candidate_review(path)

            self.assertEqual(loaded, review)
            self.assertEqual(len(digest), 64)

            review["entry_boundary_rebindings"][0][
                "distance_meters"
            ] = 750.001
            path.write_text(json.dumps(review), encoding="utf-8")
            with self.assertRaisesRegex(
                BUILD_SHUTO_NETWORK.NetworkBuildError,
                "within 750 meters",
            ):
                BUILD_SHUTO_NETWORK.load_candidate_review(path)

    def test_entry_boundary_rebinding_preserves_forward_ramp_order(
        self,
    ) -> None:
        facilities = [
            {
                "facility_id": "test.entry",
                "route_id": "2",
                "entrance_directions": ["上り"],
                "entry_edge_candidates": [
                    {"edge_id": "test.anchor", "distance_meters": 4.0}
                ],
                "exit_edge_candidates": [],
            }
        ]
        edges = [
            {
                "edge_id": "test.anchor",
                "kind": "LINK",
                "from_node_id": 1,
                "to_node_id": 2,
                "route_memberships": [
                    {"route_id": "2", "directions_ja": []}
                ],
            },
            {
                "edge_id": "test.boundary",
                "kind": "LINK",
                "from_node_id": 2,
                "to_node_id": 3,
                "route_memberships": [
                    {"route_id": "2", "directions_ja": []}
                ],
            },
        ]
        review = {
            "excluded_candidates": [],
            "entry_boundary_rebindings": [
                {
                    "facility_id": "test.entry",
                    "anchor_edge_id": "test.anchor",
                    "boundary_edge_id": "test.boundary",
                    "distance_meters": 4.0,
                }
            ],
        }

        BUILD_SHUTO_NETWORK.apply_candidate_review(
            facilities, review, edges
        )

        self.assertEqual(
            facilities[0]["entry_edge_candidates"],
            [{"edge_id": "test.boundary", "distance_meters": 4.0}],
        )

    def test_entry_boundary_rebinding_rejects_non_successor(
        self,
    ) -> None:
        facilities = [
            {
                "facility_id": "test.entry",
                "route_id": "2",
                "entrance_directions": ["上り"],
                "entry_edge_candidates": [
                    {"edge_id": "test.anchor", "distance_meters": 4.0}
                ],
                "exit_edge_candidates": [],
            }
        ]
        edges = [
            {
                "edge_id": "test.anchor",
                "kind": "LINK",
                "from_node_id": 1,
                "to_node_id": 2,
                "route_memberships": [
                    {"route_id": "2", "directions_ja": []}
                ],
            },
            {
                "edge_id": "test.boundary",
                "kind": "LINK",
                "from_node_id": 9,
                "to_node_id": 10,
                "route_memberships": [
                    {"route_id": "2", "directions_ja": []}
                ],
            },
        ]
        review = {
            "excluded_candidates": [],
            "entry_boundary_rebindings": [
                {
                    "facility_id": "test.entry",
                    "anchor_edge_id": "test.anchor",
                    "boundary_edge_id": "test.boundary",
                    "distance_meters": 4.0,
                }
            ],
        }

        with self.assertRaisesRegex(
            BUILD_SHUTO_NETWORK.NetworkBuildError,
            "not one forward ramp step",
        ):
            BUILD_SHUTO_NETWORK.apply_candidate_review(
                facilities, review, edges
            )

    def test_entry_candidate_replacement_pins_reviewed_ramp_boundary(
        self,
    ) -> None:
        facilities = [
            {
                "facility_id": "test.entry",
                "route_id": "9",
                "entrance_directions": ["上り"],
                "entry_edge_candidates": [
                    {"edge_id": "test.wrong.1", "distance_meters": 4.0},
                    {"edge_id": "test.wrong.2", "distance_meters": 5.0},
                ],
                "exit_edge_candidates": [],
            }
        ]
        edges = [
            {
                "edge_id": "test.predecessor",
                "kind": "LINK",
                "from_node_id": 1,
                "to_node_id": 2,
                "route_memberships": [{"route_id": "9", "directions_ja": []}],
            },
            {
                "edge_id": "test.boundary",
                "kind": "LINK",
                "from_node_id": 2,
                "to_node_id": 3,
                "route_memberships": [{"route_id": "9", "directions_ja": []}],
            },
        ]
        review = {
            "excluded_candidates": [],
            "entry_boundary_rebindings": [],
            "entry_candidate_replacements": [
                {
                    "facility_id": "test.entry",
                    "expected_entry_edge_ids": ["test.wrong.1", "test.wrong.2"],
                    "predecessor_edge_id": "test.predecessor",
                    "boundary_edge_id": "test.boundary",
                    "distance_meters": 62.107,
                }
            ],
        }

        BUILD_SHUTO_NETWORK.apply_candidate_review(facilities, review, edges)

        self.assertEqual(
            facilities[0]["entry_edge_candidates"],
            [{"edge_id": "test.boundary", "distance_meters": 62.107}],
        )

    def test_entry_candidate_replacement_rejects_stale_candidates(
        self,
    ) -> None:
        facilities = [
            {
                "facility_id": "test.entry",
                "route_id": "9",
                "entrance_directions": ["上り"],
                "entry_edge_candidates": [
                    {"edge_id": "test.changed", "distance_meters": 4.0}
                ],
                "exit_edge_candidates": [],
            }
        ]
        edges = []
        review = {
            "excluded_candidates": [],
            "entry_boundary_rebindings": [],
            "entry_candidate_replacements": [
                {
                    "facility_id": "test.entry",
                    "expected_entry_edge_ids": ["test.old"],
                    "predecessor_edge_id": "test.predecessor",
                    "boundary_edge_id": "test.boundary",
                    "distance_meters": 4.0,
                }
            ],
        }

        with self.assertRaisesRegex(
            BUILD_SHUTO_NETWORK.NetworkBuildError,
            "does not match current candidates",
        ):
            BUILD_SHUTO_NETWORK.apply_candidate_review(
                facilities, review, edges
            )

    def test_official_route_directions_come_from_directional_facilities(
        self,
    ) -> None:
        catalog_path = (
            SCRIPT_PATH.parents[1]
            / "data/network/shuto-official-catalog-20260729.json"
        )
        catalog, _ = BUILD_SHUTO_NETWORK.load_catalog(catalog_path)

        directions = BUILD_SHUTO_NETWORK.official_directions_by_route(
            catalog
        )

        self.assertEqual(directions["C1"], ["内回り", "外回り"])
        self.assertEqual(directions["C2"], ["内回り", "外回り"])
        self.assertEqual(directions["B"], ["東行き", "西行き"])
        self.assertEqual(directions["Y"], ["北行き", "南行き"])
        self.assertEqual(directions["3"], ["上り", "下り"])
        self.assertEqual(set(directions), set(BUILD_SHUTO_NETWORK.ROUTE_RELATION_IDS))

    def test_distributed_notice_matches_generated_osm_metadata(self) -> None:
        notice = (
            SCRIPT_PATH.parents[1] / "DATA-LICENSES.md"
        ).read_text(encoding="utf-8")

        self.assertIn("© OpenStreetMap contributors", notice)
        self.assertIn("ODbL-1.0", notice)
        self.assertIn(BUILD_SHUTO_NETWORK.ODBL_LICENSE_URI, notice)
        self.assertIn(
            "https://download.geofabrik.de/asia/japan/"
            "kanto-260804.osm.pbf",
            notice,
        )

    def test_validate_rejects_noncanonical_odbl_license_uri(self) -> None:
        result = {
            "sources": {
                "osm": {
                    "attribution": "© OpenStreetMap contributors",
                    "licence": "ODbL-1.0",
                    "licence_uri": "https://example.com/not-the-odbl",
                }
            }
        }

        with self.assertRaisesRegex(
            BUILD_SHUTO_NETWORK.NetworkBuildError,
            "OSM distribution metadata mismatch",
        ):
            BUILD_SHUTO_NETWORK.validate(result)

    def test_reviewed_junction_nodes_extend_tagged_geometry(self) -> None:
        catalog = {
            "junctions": [
                {
                    "junction_id": "shuto.jct.jct_kasai",
                    "name_ja": "葛西JCT",
                },
                {
                    "junction_id": "shuto.jct.jct_komatsugawa",
                    "name_ja": "小松川JCT",
                },
                {
                    "junction_id": "shuto.jct.jct_daishi",
                    "name_ja": "大師JCT",
                },
                {
                    "junction_id": "shuto.jct.jct_tanimachi",
                    "name_ja": "谷町JCT",
                },
            ]
        }
        node_tags = {
            8_256_670_336: {
                "highway": "motorway_junction",
                "name": "葛西JCT",
            },
            370_270_524: {
                "highway": "motorway_junction",
                "name": "小松川JCT",
            },
            600_726_158: {
                "highway": "motorway_junction",
                "name": "小松川JCT",
            },
        }
        node_coordinates = {
            31_330_103: (35.64, 139.86),
            8_256_670_336: (35.64, 139.85),
            370_270_524: (35.70, 139.85),
            600_726_158: (35.70, 139.86),
            273_330_999: (35.53, 139.72),
            3_817_775_796: (35.54, 139.73),
            260_710_778: (35.665, 139.739),
        }

        junctions = BUILD_SHUTO_NETWORK.match_junctions(
            catalog,
            node_tags,
            node_coordinates,
        )

        self.assertEqual(
            junctions[0]["osm_node_ids"],
            [31_330_103, 8_256_670_336],
        )
        self.assertEqual(
            junctions[1]["osm_node_ids"],
            [370_270_524, 600_726_158],
        )
        self.assertEqual(
            junctions[2]["osm_node_ids"],
            [273_330_999, 3_817_775_796],
        )
        self.assertEqual(
            junctions[3]["osm_node_ids"],
            [260_710_778],
        )


if __name__ == "__main__":
    unittest.main()
