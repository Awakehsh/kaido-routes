import copy
import importlib.util
import json
import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
MODULE_PATH = SCRIPTS_DIR / "render_route_atlas_design_svg.py"
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location(
    "render_route_atlas_design_svg",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
renderer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(renderer)

REPOSITORY_ROOT = Path(__file__).parents[2]
CONTEXT_PATH = (
    REPOSITORY_ROOT
    / "data/route-atlas/context/mlit-n06-2025-current-shuto-context.json"
)
SOURCE_PATH = (
    REPOSITORY_ROOT
    / "data/route-atlas/context/mlit-n06-2025-current-source.json"
)
CATALOG_PATH = (
    REPOSITORY_ROOT
    / "data/route-atlas/context/operator-route-mark-catalog-2026-07-23.json"
)
LAYOUT_PATH = (
    REPOSITORY_ROOT
    / "data/route-atlas/design/route-mark-layout-prototype.json"
)


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class RouteAtlasDesignRendererTests(unittest.TestCase):
    def setUp(self) -> None:
        self.context = load(CONTEXT_PATH)
        self.source = load(SOURCE_PATH)
        self.catalog = load(CATALOG_PATH)
        self.layout = load(LAYOUT_PATH)

    def test_real_reference_is_deterministic_and_complete(self) -> None:
        first = renderer.render(
            self.context,
            self.source,
            self.catalog,
            self.layout,
        )
        second = renderer.render(
            self.context,
            self.source,
            self.catalog,
            self.layout,
        )

        self.assertEqual(first, second)
        self.assertEqual(first.count('class="atlas-route-mark '), 28)
        route_ids = {
            line.split('data-route-id="', 1)[1].split('"', 1)[0]
            for line in first.splitlines()
            if 'data-route-id="' in line
        }
        self.assertEqual(len(route_ids), 26)
        self.assertIn("26 / 26 ROUTES PLACED", first)
        self.assertIn("shutoko.k7.yokohama-northwest", route_ids)
        self.assertIn('data-navigation-authority="false"', first)

    def test_catalog_name_drift_fails_closed(self) -> None:
        catalog = copy.deepcopy(self.catalog)
        catalog["routes"][0]["context_route_name_ja"] = "首都高速架空線"

        with self.assertRaisesRegex(
            renderer.DesignRenderError,
            "catalog-to-context coverage mismatch",
        ):
            renderer.build_mark_group(self.context, catalog, self.layout)

    def test_mark_too_far_from_matched_route_fails_closed(self) -> None:
        layout = copy.deepcopy(self.layout)
        layout["marks"][0]["anchor_hint"] = {"x": 0.0, "y": 0.0}

        with self.assertRaisesRegex(
            renderer.DesignRenderError,
            "cannot snap to its matched route",
        ):
            renderer.build_mark_group(self.context, self.catalog, layout)

    def test_k7_northwest_source_identity_drift_fails_closed(self) -> None:
        catalog = copy.deepcopy(self.catalog)
        catalog["naming_reconciliations"][0][
            "context_source_feature_id"
        ] = "mlit.n06-2025.feature.9999"

        with self.assertRaisesRegex(
            renderer.DesignRenderError,
            "K7 Northwest naming reconciliation has drifted",
        ):
            renderer.build_mark_group(self.context, catalog, self.layout)

    def test_k7_northwest_reconciliation_cannot_be_removed(self) -> None:
        catalog = copy.deepcopy(self.catalog)
        catalog["naming_reconciliations"] = []

        with self.assertRaisesRegex(
            renderer.DesignRenderError,
            "one reviewed naming reconciliation",
        ):
            renderer.build_mark_group(self.context, catalog, self.layout)

    def test_navigation_authority_is_rejected(self) -> None:
        layout = copy.deepcopy(self.layout)
        layout["navigation_authority"] = True

        with self.assertRaisesRegex(
            renderer.DesignRenderError,
            "must deny navigation authority",
        ):
            renderer.build_mark_group(self.context, self.catalog, layout)

    def test_operator_status_without_provenance_is_rejected(self) -> None:
        catalog = copy.deepcopy(self.catalog)
        yaesu = next(
            route
            for route in catalog["routes"]
            if route["route_id"] == "shutoko.y.yaesu"
        )
        del yaesu["status_source"]

        with self.assertRaisesRegex(
            renderer.DesignRenderError,
            "has no status source",
        ):
            renderer.build_mark_group(self.context, catalog, self.layout)

    def test_operator_catalog_without_checksum_is_rejected(self) -> None:
        catalog = copy.deepcopy(self.catalog)
        catalog["operator_source"]["content_sha256"] = "not-a-checksum"

        with self.assertRaisesRegex(
            renderer.DesignRenderError,
            "no valid operator checksum",
        ):
            renderer.build_mark_group(self.context, catalog, self.layout)


if __name__ == "__main__":
    unittest.main()
