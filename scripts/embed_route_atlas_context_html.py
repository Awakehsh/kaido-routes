#!/usr/bin/env python3
"""Embed generated Route Atlas context paths into a self-contained HTML mockup."""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from pathlib import Path
from typing import Any

from render_route_atlas_context_svg import RenderError, render_paths


GROUP_PATTERN = re.compile(
    r'      <g id="shutoAtlasBase"(?:\s+[^>]*)?>.*?\n      </g>\n    </defs>',
    re.DOTALL,
)
HAND_AUTHORED_OVERLAY_PATTERN = re.compile(
    r'\n[ \t]+<(?:path|circle) class="atlas-(?:plan|passed|current|recovery|'
    r'egress|repeat|position|position-halo|node(?: [^"]+)?)"[^>]*/>'
    r'|\n[ \t]+<text class="atlas-label(?: [^"]+)?"[^>]*>.*?</text>'
)


class EmbedError(RuntimeError):
    """A fail-closed HTML embedding error."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context", required=True, type=Path)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--html", required=True, type=Path)
    return parser.parse_args()


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EmbedError(f"cannot read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise EmbedError(f"expected a JSON object in {path}")
    return value


def build_group(
    context: dict[str, Any],
    source: dict[str, Any],
) -> str:
    if context.get("navigation_role") != "CONTEXT_ONLY":
        raise EmbedError("only CONTEXT_ONLY artifacts may be embedded")
    if context.get("source_reference_id") != source.get("source_reference_id"):
        raise EmbedError("context and source reference IDs do not match")
    source_id = html.escape(str(source.get("source_reference_id", "")))
    source_date = html.escape(str(source.get("dataset_reference_date", "")))
    checksum = html.escape(str(source.get("archive_sha256", "")))
    projection = context.get("projection")
    source_crs = (
        projection.get("source_crs")
        if isinstance(projection, dict)
        else None
    )
    if source_crs not in {"EPSG:4326", "EPSG:6668"}:
        raise EmbedError(f"unsupported source CRS {source_crs!r}")
    if source.get("source_crs") != source_crs:
        raise EmbedError("context and source CRS values do not match")
    escaped_source_crs = html.escape(source_crs)
    rendered_paths = "\n".join(render_paths(context))
    return f"""      <g id="shutoAtlasBase"
         class="atlas-context-base"
         data-navigation-role="CONTEXT_ONLY"
         data-source-reference-id="{source_id}"
         data-source-date="{source_date}"
         data-source-crs="{escaped_source_crs}"
         data-source-archive-sha256="{checksum}">
        <title>Shuto full-network geographic context</title>
        <desc>North-up source-derived context from {escaped_source_crs} only. It has no selectable connection, legal-movement, direction, RoutePlan, or realtime authority.</desc>
{rendered_paths}
        <text class="atlas-context-caption" x="20" y="586">CONTEXT ONLY · MLIT N06-2025 · 2025-12-31</text>
      </g>
    </defs>"""


def main() -> int:
    args = parse_args()
    try:
        context = load_object(args.context)
        source = load_object(args.source)
        original = args.html.read_text(encoding="utf-8")
        replacement = build_group(context, source)
        updated, count = GROUP_PATTERN.subn(replacement, original, count=1)
        if count != 1:
            raise EmbedError(
                "expected exactly one shutoAtlasBase group followed by </defs>"
            )
        updated, removed_overlay_count = HAND_AUTHORED_OVERLAY_PATTERN.subn(
            "",
            updated,
        )
        args.html.write_text(updated, encoding="utf-8")
    except (EmbedError, OSError, RenderError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        "PASS: embedded source-derived CONTEXT_ONLY Route Atlas geometry into "
        f"{args.html}; removed {removed_overlay_count} hand-authored map "
        "overlay elements"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
