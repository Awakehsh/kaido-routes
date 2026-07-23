#!/usr/bin/env python3
"""Render the non-navigable Route Atlas recognition design as SVG."""

from __future__ import annotations

import argparse
import html
import json
import math
import sys
from datetime import date
from pathlib import Path
from typing import Any

from render_route_atlas_context_svg import (
    RenderError,
    display_point,
    render_paths,
)


MAXIMUM_ANCHOR_DISTANCE = 0.08


class DesignRenderError(RuntimeError):
    """A fail-closed recognition catalog, layout, or output error."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context", required=True, type=Path)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--route-catalog", required=True, type=Path)
    parser.add_argument("--route-mark-layout", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise DesignRenderError(f"cannot read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise DesignRenderError(f"expected a JSON object in {path}")
    return value


def normalized_point(value: Any, label: str) -> tuple[float, float]:
    if not isinstance(value, dict):
        raise DesignRenderError(f"{label} must be an object")
    coordinates: list[float] = []
    for axis in ("x", "y"):
        coordinate = value.get(axis)
        if (
            isinstance(coordinate, bool)
            or not isinstance(coordinate, (int, float))
            or not math.isfinite(coordinate)
            or not 0 <= coordinate <= 1
        ):
            raise DesignRenderError(
                f"{label}.{axis} must be finite and inside the unit square"
            )
        coordinates.append(float(coordinate))
    return coordinates[0], coordinates[1]


def label_offset(value: Any, label: str) -> tuple[float, float]:
    if value is None:
        return 0.0, 0.0
    if not isinstance(value, dict):
        raise DesignRenderError(f"{label} must be an object")
    coordinates: list[float] = []
    for axis in ("x", "y"):
        coordinate = value.get(axis)
        if (
            isinstance(coordinate, bool)
            or not isinstance(coordinate, (int, float))
            or not math.isfinite(coordinate)
            or abs(coordinate) > 48
        ):
            raise DesignRenderError(
                f"{label}.{axis} must be finite and within 48 SVG units"
            )
        coordinates.append(float(coordinate))
    return coordinates[0], coordinates[1]


def context_points_by_route(
    context: dict[str, Any],
) -> dict[str, list[dict[str, Any]]]:
    if context.get("navigation_role") != "CONTEXT_ONLY":
        raise DesignRenderError("recognition design requires CONTEXT_ONLY geometry")
    paths = context.get("paths")
    if not isinstance(paths, list) or not paths:
        raise DesignRenderError("context has no paths")
    result: dict[str, list[dict[str, Any]]] = {}
    for path_index, path in enumerate(paths):
        if not isinstance(path, dict):
            raise DesignRenderError(f"context path {path_index} is not an object")
        route_name = path.get("route_name_ja")
        points = path.get("points")
        if not isinstance(route_name, str) or not route_name:
            raise DesignRenderError(f"context path {path_index} has no route name")
        if not isinstance(points, list) or len(points) < 2:
            raise DesignRenderError(
                f"context path {path_index} has insufficient geometry"
            )
        result.setdefault(route_name, []).extend(points)
    return result


def validated_catalog(
    context: dict[str, Any],
    catalog: dict[str, Any],
) -> dict[str, dict[str, Any]]:
    if catalog.get("reference_role") != "DISPLAY_REFERENCE_ONLY":
        raise DesignRenderError("route catalog is not display-reference-only")
    if catalog.get("navigation_authority") is not False:
        raise DesignRenderError("route catalog must deny navigation authority")
    context_reference = catalog.get("context_reference")
    if not isinstance(context_reference, dict):
        raise DesignRenderError("route catalog has no context reference")
    if context_reference.get("context_id") != context.get("context_id"):
        raise DesignRenderError("route catalog and context IDs do not match")
    source_reference_id = context_reference.get("source_reference_id")
    if source_reference_id != context.get("source_reference_id"):
        raise DesignRenderError("route catalog and context sources do not match")

    routes = catalog.get("routes")
    operator_source = catalog.get("operator_source")
    if not isinstance(routes, list) or not isinstance(operator_source, dict):
        raise DesignRenderError("route catalog structure is incomplete")
    expected_count = operator_source.get("operator_route_count")
    operator_checksum = operator_source.get("content_sha256")
    if expected_count != 26 or len(routes) != expected_count:
        raise DesignRenderError(
            "route catalog must preserve all 26 reviewed operator route names"
        )
    if (
        not isinstance(operator_checksum, str)
        or len(operator_checksum) != 64
        or any(character not in "0123456789abcdef" for character in operator_checksum)
    ):
        raise DesignRenderError("route catalog has no valid operator checksum")

    route_by_id: dict[str, dict[str, Any]] = {}
    matched_context_names: set[str] = set()
    unmatched_ids: set[str] = set()
    for route_index, route in enumerate(routes):
        if not isinstance(route, dict):
            raise DesignRenderError(f"catalog route {route_index} is not an object")
        route_id = route.get("route_id")
        route_code = route.get("route_code")
        route_name = route.get("route_name_ja")
        match_state = route.get("context_match")
        if not all(
            isinstance(value, str) and value
            for value in (route_id, route_code, route_name, match_state)
        ):
            raise DesignRenderError(f"catalog route {route_index} is incomplete")
        if route_id in route_by_id:
            raise DesignRenderError(f"duplicate route ID {route_id}")
        route_by_id[route_id] = route
        display_status = route.get("operator_display_status")
        if display_status is not None:
            if display_status != "LONG_TERM_CLOSED":
                raise DesignRenderError(
                    f"unsupported operator display status {display_status!r}"
                )
            status_source = route.get("status_source")
            if not isinstance(status_source, dict):
                raise DesignRenderError(
                    f"route {route_id} has no status source"
                )
            status_url = status_source.get("source_url")
            status_checksum = status_source.get("content_sha256")
            checked_at = status_source.get("checked_at")
            if (
                not isinstance(status_url, str)
                or not status_url.startswith("https://")
                or not isinstance(status_checksum, str)
                or len(status_checksum) != 64
                or any(
                    character not in "0123456789abcdef"
                    for character in status_checksum
                )
                or not isinstance(checked_at, str)
            ):
                raise DesignRenderError(
                    f"route {route_id} has invalid status provenance"
                )
            try:
                date.fromisoformat(checked_at)
            except ValueError as error:
                raise DesignRenderError(
                    f"route {route_id} has invalid status checked date"
                ) from error
        context_name = route.get("context_route_name_ja")
        if match_state == "MATCHED":
            if not isinstance(context_name, str) or not context_name:
                raise DesignRenderError(
                    f"matched route {route_id} has no context route name"
                )
            if context_name in matched_context_names:
                raise DesignRenderError(
                    f"context route {context_name} is matched more than once"
                )
            matched_context_names.add(context_name)
        elif match_state == "UNMATCHED":
            if context_name is not None:
                raise DesignRenderError(
                    f"unmatched route {route_id} must not name context geometry"
                )
            unmatched_ids.add(route_id)
        else:
            raise DesignRenderError(
                f"unsupported context match state {match_state!r}"
            )

    points_by_route = context_points_by_route(context)
    if set(points_by_route) != matched_context_names:
        missing = sorted(set(points_by_route) - matched_context_names)
        extra = sorted(matched_context_names - set(points_by_route))
        raise DesignRenderError(
            "catalog-to-context coverage mismatch: "
            f"missing catalog matches {missing}; missing context geometry {extra}"
        )
    if len(matched_context_names) != 26 or unmatched_ids:
        raise DesignRenderError(
            "expected all 26 operator routes to match context geometry"
        )
    if context_reference.get("matched_route_count") != len(matched_context_names):
        raise DesignRenderError("catalog matched-route summary has drifted")
    declared_unmatched = context_reference.get("unmatched_operator_route_ids")
    if not isinstance(declared_unmatched, list) or set(declared_unmatched) != unmatched_ids:
        raise DesignRenderError("catalog unmatched-route summary has drifted")

    reconciliations = catalog.get("naming_reconciliations")
    if not isinstance(reconciliations, list) or len(reconciliations) != 1:
        raise DesignRenderError(
            "catalog must preserve the one reviewed naming reconciliation"
        )
    reconciliation = reconciliations[0]
    if not isinstance(reconciliation, dict):
        raise DesignRenderError("catalog naming reconciliation is not an object")
    route_id = reconciliation.get("operator_route_id")
    context_name = reconciliation.get("context_route_name_ja")
    feature_id = reconciliation.get("context_source_feature_id")
    record_id = reconciliation.get("context_source_record_id")
    source_url = reconciliation.get("operator_source_url")
    checksum = reconciliation.get("operator_content_sha256")
    checked_at = reconciliation.get("checked_at")
    joint_names = (
        reconciliation.get("context_start_joint_ja"),
        reconciliation.get("context_end_joint_ja"),
    )
    reconciled_route = route_by_id.get(route_id)
    matching_paths = [
        path
        for path in context.get("paths", [])
        if isinstance(path, dict)
        and path.get("route_name_ja") == context_name
        and path.get("source_feature_id") == feature_id
        and path.get("source_record_id") == record_id
    ]
    if (
        route_id != "shutoko.k7.yokohama-northwest"
        or reconciled_route is None
        or reconciled_route.get("context_match") != "MATCHED"
        or reconciled_route.get("context_route_name_ja") != context_name
        or context_name != "高速横浜環状北西線"
        or len(matching_paths) != 1
        or not isinstance(source_url, str)
        or not source_url.startswith("https://www.shutoko.jp/")
        or not isinstance(checksum, str)
        or len(checksum) != 64
        or any(character not in "0123456789abcdef" for character in checksum)
        or not all(isinstance(value, str) and value for value in joint_names)
    ):
        raise DesignRenderError("K7 Northwest naming reconciliation has drifted")
    try:
        date.fromisoformat(checked_at)
    except (TypeError, ValueError) as error:
        raise DesignRenderError(
            "K7 Northwest reconciliation has an invalid checked date"
        ) from error
    return route_by_id


def nearest_route_point(
    points: list[dict[str, Any]],
    hint: tuple[float, float],
    label: str,
) -> tuple[dict[str, float], float]:
    nearest: dict[str, float] | None = None
    nearest_distance = math.inf
    for point_index, point in enumerate(points):
        x, y = normalized_point(point, f"{label}.route_point[{point_index}]")
        distance = math.hypot(x - hint[0], y - hint[1])
        if distance < nearest_distance:
            nearest = {"x": x, "y": y}
            nearest_distance = distance
    if nearest is None or nearest_distance > MAXIMUM_ANCHOR_DISTANCE:
        raise DesignRenderError(
            f"{label} cannot snap to its matched route: "
            f"distance {nearest_distance:.6f}"
        )
    return nearest, nearest_distance


def build_mark_group(
    context: dict[str, Any],
    catalog: dict[str, Any],
    layout: dict[str, Any],
) -> str:
    route_by_id = validated_catalog(context, catalog)
    if layout.get("status") != "REVIEW_ONLY":
        raise DesignRenderError("route-mark layout must remain REVIEW_ONLY")
    if layout.get("navigation_authority") is not False:
        raise DesignRenderError("route-mark layout must deny navigation authority")
    if layout.get("context_id") != context.get("context_id"):
        raise DesignRenderError("route-mark layout and context IDs do not match")
    if layout.get("catalog_id") != catalog.get("catalog_id"):
        raise DesignRenderError("route-mark layout and catalog IDs do not match")

    unmatched_route_ids = {
        route_id
        for route_id, route in route_by_id.items()
        if route.get("context_match") == "UNMATCHED"
    }
    unrepresented = layout.get("unrepresented_catalog_route_ids")
    if not isinstance(unrepresented, list) or set(unrepresented) != unmatched_route_ids:
        raise DesignRenderError(
            "layout must declare exactly the unmatched operator routes"
        )

    marks = layout.get("marks")
    if not isinstance(marks, list) or not marks:
        raise DesignRenderError("route-mark layout has no marks")
    points_by_route = context_points_by_route(context)
    seen_mark_ids: set[str] = set()
    represented_route_ids: set[str] = set()
    rendered: list[str] = []
    for mark_index, mark in enumerate(marks):
        if not isinstance(mark, dict):
            raise DesignRenderError(f"layout mark {mark_index} is not an object")
        mark_id = mark.get("mark_id")
        route_id = mark.get("route_id")
        density = mark.get("density")
        if not all(
            isinstance(value, str) and value
            for value in (mark_id, route_id, density)
        ):
            raise DesignRenderError(f"layout mark {mark_index} is incomplete")
        if mark_id in seen_mark_ids:
            raise DesignRenderError(f"duplicate mark ID {mark_id}")
        seen_mark_ids.add(mark_id)
        if density not in {"PRIMARY", "SECONDARY"}:
            raise DesignRenderError(
                f"layout mark {mark_id} has unsupported density {density!r}"
            )
        route = route_by_id.get(route_id)
        if route is None or route.get("context_match") != "MATCHED":
            raise DesignRenderError(
                f"layout mark {mark_id} references an unmatched route"
            )
        context_name = route["context_route_name_ja"]
        hint = normalized_point(mark.get("anchor_hint"), f"layout mark {mark_id}")
        anchor, anchor_distance = nearest_route_point(
            points_by_route[context_name],
            hint,
            f"layout mark {mark_id}",
        )
        display_x, display_y = display_point(anchor, f"layout mark {mark_id}")
        offset_x, offset_y = label_offset(
            mark.get("label_offset"),
            f"layout mark {mark_id}.label_offset",
        )
        route_code = route["route_code"]
        width = max(22, 12 + len(route_code) * 8)
        status_class = (
            " atlas-route-mark-closed"
            if route.get("operator_display_status") == "LONG_TERM_CLOSED"
            else ""
        )
        rendered.append(
            "        <g"
            f' class="atlas-route-mark atlas-route-mark-{density.lower()}'
            f'{status_class}"'
            f' data-mark-id="{html.escape(mark_id)}"'
            f' data-route-id="{html.escape(route_id)}"'
            f' data-route-name-ja="{html.escape(route["route_name_ja"])}"'
            f' data-context-route-name-ja="{html.escape(context_name)}"'
            f' data-anchor-distance="{anchor_distance:.6f}"'
            f' transform="translate({display_x:.3f} {display_y:.3f})">'
            + (
                f'<line x1="0" y1="0" x2="{offset_x:.1f}" '
                f'y2="{offset_y:.1f}"/>'
                if offset_x or offset_y
                else ""
            )
            + (
                f'<g transform="translate({offset_x:.1f} {offset_y:.1f})">'
                f'<rect x="{-width / 2:.1f}" y="-9" width="{width}" '
                f'height="18" rx="5"/>'
                f'<text x="0" y="0">{html.escape(route_code)}</text>'
                "</g>"
            )
            + "</g>"
        )
        represented_route_ids.add(route_id)

    expected_represented = set(route_by_id) - unmatched_route_ids
    if represented_route_ids != expected_represented:
        missing = sorted(expected_represented - represented_route_ids)
        extra = sorted(represented_route_ids - expected_represented)
        raise DesignRenderError(
            "route-mark coverage mismatch: "
            f"missing {missing}; unexpected {extra}"
        )

    mark_content = "\n".join(rendered)
    return f"""      <g id="shutoAtlasRouteMarks"
         class="atlas-route-marks"
         data-reference-role="DISPLAY_REFERENCE_ONLY"
         data-navigation-authority="false"
         data-catalog-id="{html.escape(str(catalog["catalog_id"]))}"
         data-layout-id="{html.escape(str(layout["layout_id"]))}">
        <title>Current Shuto route-code recognition reference</title>
        <desc>Kaido-owned route-code capsules snapped to matched MLIT context vertices. All twenty-six current operator route names are represented. Yokohama Northwest Route K7 is reconciled to the MLIT source record named 高速横浜環状北西線. This layer is not selectable or navigable.</desc>
{mark_content}
      </g>"""


def render(
    context: dict[str, Any],
    source: dict[str, Any],
    catalog: dict[str, Any],
    layout: dict[str, Any],
) -> str:
    if context.get("source_reference_id") != source.get("source_reference_id"):
        raise DesignRenderError("context and source reference IDs do not match")
    attribution = source.get("attribution")
    transformation = source.get("transformation_disclosure")
    if not isinstance(attribution, str) or not attribution:
        raise DesignRenderError("source attribution is missing")
    if not isinstance(transformation, str) or not transformation:
        raise DesignRenderError("source transformation disclosure is missing")
    paths = "\n".join(render_paths(context))
    marks = build_mark_group(context, catalog, layout)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg"
     viewBox="0 0 420 620"
     role="img"
     aria-labelledby="title description">
  <title id="title">Kaido Routes Shuto Route Atlas recognition design</title>
  <desc id="description">North-up non-navigable design reference. {html.escape(attribution)}. {html.escape(transformation)}</desc>
  <rect width="420" height="620" rx="28" fill="#162329"/>
  <g fill="none" stroke-linecap="round" stroke-linejoin="round">
{paths}
  </g>
{marks}
  <text class="atlas-context-caption" x="20" y="586">RECOGNITION REFERENCE · 26 / 26 ROUTES PLACED · NAVIGATION BLOCKED</text>
  <style>
    .atlas-context-path {{
      fill: none;
      stroke: #53666e;
      stroke-width: 2.8;
      stroke-linecap: round;
      stroke-linejoin: round;
      opacity: .74;
    }}
    .atlas-context-c1 {{ stroke: #93a4aa; stroke-width: 3.8; opacity: .98; }}
    .atlas-context-c2 {{ stroke: #7d9299; stroke-width: 3.5; opacity: .94; }}
    .atlas-context-bayshore {{ stroke: #6f8b94; stroke-width: 3.5; opacity: .94; }}
    .atlas-context-provisional {{ stroke-dasharray: 5 5; }}
    .atlas-route-mark rect {{
      fill: #10191d;
      stroke: #c8d5d8;
      stroke-width: 1;
      vector-effect: non-scaling-stroke;
    }}
    .atlas-route-mark line {{
      stroke: #83969d;
      stroke-width: .8;
      vector-effect: non-scaling-stroke;
    }}
    .atlas-route-mark text {{
      fill: #f4f6f4;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 9px;
      font-weight: 900;
      text-anchor: middle;
      dominant-baseline: central;
    }}
    .atlas-route-mark-secondary {{ opacity: .78; }}
    .atlas-route-mark-closed rect {{ stroke: #eb8d7f; stroke-dasharray: 2 2; }}
    .atlas-route-mark-closed text {{ fill: #f2aaa0; }}
    .atlas-context-caption {{
      fill: rgba(172, 193, 200, .68);
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 7px;
      font-weight: 800;
      letter-spacing: .04em;
    }}
  </style>
</svg>
"""


def main() -> int:
    args = parse_args()
    try:
        context = load_object(args.context)
        source = load_object(args.source)
        catalog = load_object(args.route_catalog)
        layout = load_object(args.route_mark_layout)
        output = render(context, source, catalog, layout)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding="utf-8")
    except (DesignRenderError, OSError, RenderError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        "PASS: rendered Route Atlas recognition design with 26 matched "
        f"operator routes to {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
