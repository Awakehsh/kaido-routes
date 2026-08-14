import importlib.util
from pathlib import Path
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
            ]
        }
        node_tags = {
            8_256_670_336: {
                "highway": "motorway_junction",
                "name": "葛西JCT",
            }
        }
        node_coordinates = {
            31_330_103: (35.64, 139.86),
            8_256_670_336: (35.64, 139.85),
            31_337_397: (35.70, 139.85),
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
            [31_337_397],
        )


if __name__ == "__main__":
    unittest.main()
