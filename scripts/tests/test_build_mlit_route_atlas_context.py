import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
MODULE_PATH = SCRIPTS_DIR / "build_mlit_route_atlas_context.py"
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location(
    "build_mlit_route_atlas_context",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


def feature(
    route_name: str,
    *,
    end_year: int = 9999,
    road_class: str = "5",
) -> dict:
    return {
        "type": "Feature",
        "properties": {
            "N06_003": end_year,
            "N06_007": route_name,
            "N06_008": road_class,
        },
        "geometry": {
            "type": "LineString",
            "coordinates": [[139.5, 35.5], [139.6, 35.6]],
        },
    }


class BuildMLITRouteAtlasContextTests(unittest.TestCase):
    def test_current_shuto_selection_includes_northwest_source_name(self) -> None:
        geojson = {
            "crs": {
                "properties": {
                    "name": builder.EXPECTED_SOURCE_CRS,
                }
            },
            "features": [
                feature("首都高速神奈川7号横浜北線"),
                feature("高速横浜環状北西線"),
                feature("第一東海自動車道"),
            ],
        }

        selected = builder.selected_features(geojson)

        self.assertEqual([index for index, _ in selected], [0, 1])

    def test_northwest_name_does_not_bypass_current_state_or_class(self) -> None:
        geojson = {
            "crs": {
                "properties": {
                    "name": builder.EXPECTED_SOURCE_CRS,
                }
            },
            "features": [
                feature("高速横浜環状北西線", end_year=2024),
                feature("高速横浜環状北西線", road_class="1"),
            ],
        }

        self.assertEqual(builder.selected_features(geojson), [])


if __name__ == "__main__":
    unittest.main()
