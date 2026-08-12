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


if __name__ == "__main__":
    unittest.main()
