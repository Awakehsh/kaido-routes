#!/usr/bin/env python3
"""Render a reviewed CONTEXT_ONLY Route Atlas artifact as an SVG instrument."""

from __future__ import annotations

import argparse
import html
import json
import sys
from pathlib import Path
from typing import Any


VIEWBOX_WIDTH = 420.0
VIEWBOX_HEIGHT = 620.0
UNIFORM_SCALE = 560.0


class RenderError(RuntimeError):
    """A fail-closed context artifact or output error."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context", required=True, type=Path)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RenderError(f"cannot read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise RenderError(f"expected a JSON object in {path}")
    return value


def number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise RenderError(f"{label} must be numeric")
    result = float(value)
    if not 0 <= result <= 1:
        raise RenderError(f"{label} must be inside the normalized unit square")
    return result


def display_point(point: dict[str, Any], label: str) -> tuple[float, float]:
    x = number(point.get("x"), f"{label}.x")
    y = number(point.get("y"), f"{label}.y")
    return (
        VIEWBOX_WIDTH / 2 + (x - 0.5) * UNIFORM_SCALE,
        VIEWBOX_HEIGHT / 2 + (y - 0.5) * UNIFORM_SCALE,
    )


def path_class(route_name: str, use_status: str) -> str:
    classes = ["atlas-context-path"]
    if route_name == "首都高速都心環状線":
        classes.append("atlas-context-c1")
    elif route_name == "首都高速中央環状線":
        classes.append("atlas-context-c2")
    elif route_name == "首都高速湾岸線":
        classes.append("atlas-context-bayshore")
    elif "神奈川" in route_name:
        classes.append("atlas-context-kanagawa")
    elif "埼玉" in route_name:
        classes.append("atlas-context-saitama")
    else:
        classes.append("atlas-context-radial")
    if use_status == "PROVISIONAL":
        classes.append("atlas-context-provisional")
    return " ".join(classes)


def render_paths(context: dict[str, Any]) -> list[str]:
    paths = context.get("paths")
    if not isinstance(paths, list) or not paths:
        raise RenderError("context has no paths")
    rendered: list[str] = []
    for path_index, path in enumerate(paths):
        if not isinstance(path, dict):
            raise RenderError(f"path {path_index} is not an object")
        points = path.get("points")
        if not isinstance(points, list) or len(points) < 2:
            raise RenderError(f"path {path_index} has insufficient geometry")
        display_points = []
        for point_index, point in enumerate(points):
            if not isinstance(point, dict):
                raise RenderError(
                    f"path {path_index} point {point_index} is not an object"
                )
            display_points.append(
                display_point(point, f"path {path_index} point {point_index}")
            )
        commands = [
            f"M{display_points[0][0]:.3f} {display_points[0][1]:.3f}"
        ]
        commands.extend(
            f"L{x:.3f} {y:.3f}" for x, y in display_points[1:]
        )
        route_name = path.get("route_name_ja")
        path_id = path.get("path_id")
        source_feature_id = path.get("source_feature_id")
        source_record_id = path.get("source_record_id")
        use_status = path.get("use_status")
        if not all(
            isinstance(value, str) and value
            for value in (
                route_name,
                path_id,
                source_feature_id,
                source_record_id,
                use_status,
            )
        ):
            raise RenderError(f"path {path_index} has incomplete metadata")
        rendered.append(
            "      <path"
            f' class="{html.escape(path_class(route_name, use_status))}"'
            f' data-path-id="{html.escape(path_id)}"'
            f' data-source-feature-id="{html.escape(source_feature_id)}"'
            f' data-source-record-id="{html.escape(source_record_id)}"'
            f' data-route-name-ja="{html.escape(route_name)}"'
            f' d="{" ".join(commands)}"/>'
        )
    return rendered


def render(context: dict[str, Any], source: dict[str, Any]) -> str:
    if context.get("navigation_role") != "CONTEXT_ONLY":
        raise RenderError("only CONTEXT_ONLY artifacts may be rendered")
    if context.get("source_reference_id") != source.get("source_reference_id"):
        raise RenderError("context and source reference IDs do not match")
    attribution = source.get("attribution")
    transformation = source.get("transformation_disclosure")
    if not isinstance(attribution, str) or not attribution:
        raise RenderError("source attribution is missing")
    if not isinstance(transformation, str) or not transformation:
        raise RenderError("source transformation disclosure is missing")
    projection = context.get("projection")
    source_crs = (
        projection.get("source_crs")
        if isinstance(projection, dict)
        else None
    )
    if source_crs not in {"EPSG:4326", "EPSG:6668"}:
        raise RenderError(f"unsupported source CRS {source_crs!r}")
    if source.get("source_crs") != source_crs:
        raise RenderError("context and source CRS values do not match")
    paths = "\n".join(render_paths(context))
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg"
     viewBox="0 0 420 620"
     role="img"
     aria-labelledby="title description">
  <title id="title">Kaido Routes Shuto geographic context</title>
  <desc id="description">North-up CONTEXT_ONLY geometry. Not selectable or navigable. {html.escape(attribution)}. {html.escape(transformation)}</desc>
  <metadata>
    <source-reference-id>{html.escape(str(source["source_reference_id"]))}</source-reference-id>
    <archive-sha256>{html.escape(str(source["archive_sha256"]))}</archive-sha256>
    <dataset-reference-date>{html.escape(str(source["dataset_reference_date"]))}</dataset-reference-date>
    <source-crs>{html.escape(source_crs)}</source-crs>
    <navigation-role>CONTEXT_ONLY</navigation-role>
  </metadata>
  <rect width="420" height="620" rx="28" fill="#162329"/>
  <g id="shutoAtlasContext" fill="none" stroke-linecap="round" stroke-linejoin="round">
{paths}
  </g>
  <style>
    .atlas-context-path {{
      vector-effect: non-scaling-stroke;
      stroke: #52656d;
      stroke-width: 2.8;
      opacity: .76;
    }}
    .atlas-context-c1 {{ stroke: #7f9299; stroke-width: 3.8; opacity: .94; }}
    .atlas-context-c2 {{ stroke: #71858c; stroke-width: 3.4; opacity: .9; }}
    .atlas-context-bayshore {{ stroke: #65818b; stroke-width: 3.5; opacity: .92; }}
    .atlas-context-kanagawa {{ stroke: #5f747c; opacity: .84; }}
    .atlas-context-saitama {{ stroke: #5f747c; opacity: .84; }}
    .atlas-context-provisional {{ stroke-dasharray: 5 5; }}
  </style>
</svg>
"""


def main() -> int:
    args = parse_args()
    try:
        context = load_object(args.context)
        source = load_object(args.source)
        output = render(context, source)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding="utf-8")
    except (OSError, RenderError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"PASS: rendered CONTEXT_ONLY Route Atlas SVG to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
