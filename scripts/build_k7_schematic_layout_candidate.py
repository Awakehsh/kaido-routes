#!/usr/bin/env python3
"""Build and render the Kaido-owned K7 schematic layout candidate."""

from __future__ import annotations

import argparse
import copy
from datetime import date
import hashlib
import html
import json
import math
from pathlib import Path
import sys
from typing import Any


SCHEMA_VERSION = "1.0"
CANDIDATE_STATE = "CANDIDATE"
LAYOUT_METHOD = "KAIDO_OWNED_SCHEMATIC"
COORDINATE_SPACE = "NORMALIZED_NORTH_UP"
EXPECTED_TERMINAL_NODE_ID = "osm.node.7473451738"
EXPECTED_TERMINAL_EDGE_ID = (
    "shutoko.topology-edge.osm-way.734299106.forward"
)
EXPECTED_SURFACE_SUCCESSOR_WAY_IDS = [734299108, 734299111, 776884422]
EXPECTED_BOUNDARY_REASON = "SURFACE_EGRESS_OUTSIDE_REVIEWED_LAYOUT"
OUTPUT_ATLAS_ID = (
    "shutoko.atlas.k7-northwest.schematic-layout-candidate.2026-07-23"
)


class SchematicLayoutError(RuntimeError):
    """A fail-closed K7 schematic source or topology error."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-candidate", required=True, type=Path)
    parser.add_argument("--layout", required=True, type=Path)
    parser.add_argument("--candidate-output", required=True, type=Path)
    parser.add_argument("--scenario-output", required=True, type=Path)
    parser.add_argument("--svg-output", required=True, type=Path)
    return parser.parse_args()


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SchematicLayoutError(f"cannot read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise SchematicLayoutError(f"expected a JSON object in {path}")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def valid_point(value: Any) -> bool:
    return (
        isinstance(value, dict)
        and set(value) == {"x", "y"}
        and all(
            isinstance(value[axis], (int, float))
            and not isinstance(value[axis], bool)
            and math.isfinite(value[axis])
            and 0.0 <= value[axis] <= 1.0
            for axis in ("x", "y")
        )
    )


def validate_base_candidate(candidate: dict[str, Any]) -> None:
    topology = candidate.get("topology_slice")
    definition = candidate.get("definition")
    route_plan = candidate.get("route_plan")
    registry = candidate.get("source_registry")
    if (
        candidate.get("schema_version") != SCHEMA_VERSION
        or not isinstance(topology, dict)
        or not isinstance(definition, dict)
        or not isinstance(route_plan, dict)
        or not isinstance(registry, dict)
        or topology.get("evidence", {}).get("state") != CANDIDATE_STATE
        or definition.get("evidence", {}).get("state") != CANDIDATE_STATE
        or not isinstance(topology.get("nodes"), list)
        or not isinstance(topology.get("edges"), list)
        or not isinstance(definition.get("segments"), list)
        or not isinstance(route_plan.get("occurrences"), list)
        or not isinstance(registry.get("references"), list)
    ):
        raise SchematicLayoutError("base candidate boundary is invalid")

    topology_edges = topology["edges"]
    edge_ids = [edge.get("edge_id") for edge in topology_edges]
    if (
        len(topology_edges) != 15
        or len(set(edge_ids)) != len(edge_ids)
        or EXPECTED_TERMINAL_EDGE_ID not in edge_ids
    ):
        raise SchematicLayoutError("base candidate topology coverage has drifted")
    terminal_edge = next(
        edge
        for edge in topology_edges
        if edge["edge_id"] == EXPECTED_TERMINAL_EDGE_ID
    )
    if (
        terminal_edge.get("to_node_id") != EXPECTED_TERMINAL_NODE_ID
        or terminal_edge.get("successor_edge_ids") != []
    ):
        raise SchematicLayoutError(
            "base candidate no longer stops at the reviewed exit boundary"
        )

    route_entity_id = terminal_edge.get("route_entity_id")
    if route_plan["occurrences"][-1].get("entity_id") != route_entity_id:
        raise SchematicLayoutError(
            "base RoutePlan does not end at the reviewed exit edge"
        )


def validate_layout(
    layout: dict[str, Any],
    candidate: dict[str, Any],
) -> tuple[
    dict[str, dict[str, float]],
    dict[str, list[dict[str, float]]],
]:
    topology = candidate["topology_slice"]
    definition = candidate["definition"]
    source_reference = layout.get("source_reference")
    try:
        date.fromisoformat(layout.get("checked_at"))
    except (TypeError, ValueError) as error:
        raise SchematicLayoutError("layout review date is invalid") from error
    if (
        layout.get("schema_version") != SCHEMA_VERSION
        or layout.get("expected_base_atlas_id") != definition.get("atlas_id")
        or layout.get("network_snapshot_id")
        != candidate["network_snapshot"].get("id")
        or layout.get("route_plan_id") != candidate["route_plan"].get("plan_id")
        or layout.get("topology_slice_id")
        != topology.get("topology_slice_id")
        or layout.get("status") != CANDIDATE_STATE
        or layout.get("navigation_authority") is not False
        or layout.get("coordinate_space") != COORDINATE_SPACE
        or layout.get("authoring_method") != LAYOUT_METHOD
        or not isinstance(source_reference, dict)
        or source_reference.get("roles") != ["LAYOUT_EVIDENCE"]
        or source_reference.get("licence_identifier") != "Apache-2.0"
        or not str(source_reference.get("source_url", "")).startswith("https://")
    ):
        raise SchematicLayoutError("schematic layout identity is invalid")

    topology_node_ids = {
        node.get("node_id") for node in topology["nodes"]
    }
    nodes = layout.get("nodes")
    if not isinstance(nodes, list):
        raise SchematicLayoutError("schematic layout has no nodes")
    points_by_node: dict[str, dict[str, float]] = {}
    point_pairs: set[tuple[float, float]] = set()
    for node in nodes:
        if (
            not isinstance(node, dict)
            or not isinstance(node.get("topology_node_id"), str)
            or node["topology_node_id"] in points_by_node
            or not valid_point(node.get("point"))
        ):
            raise SchematicLayoutError("schematic layout contains an invalid node")
        point = node["point"]
        point_pair = (float(point["x"]), float(point["y"]))
        if point_pair in point_pairs:
            raise SchematicLayoutError(
                "schematic layout collapses two topology nodes"
            )
        point_pairs.add(point_pair)
        points_by_node[node["topology_node_id"]] = {
            "x": point_pair[0],
            "y": point_pair[1],
        }
    if set(points_by_node) != topology_node_ids:
        raise SchematicLayoutError(
            "schematic layout node coverage does not match topology"
        )

    topology_edge_ids = {
        edge.get("edge_id") for edge in topology["edges"]
    }
    segments = layout.get("segments")
    if not isinstance(segments, list):
        raise SchematicLayoutError("schematic layout has no segments")
    controls_by_edge: dict[str, list[dict[str, float]]] = {}
    for segment in segments:
        if (
            not isinstance(segment, dict)
            or not isinstance(segment.get("topology_edge_id"), str)
            or segment["topology_edge_id"] in controls_by_edge
            or not isinstance(segment.get("control_points"), list)
            or not all(valid_point(point) for point in segment["control_points"])
        ):
            raise SchematicLayoutError(
                "schematic layout contains an invalid segment"
            )
        controls_by_edge[segment["topology_edge_id"]] = [
            {
                "x": float(point["x"]),
                "y": float(point["y"]),
            }
            for point in segment["control_points"]
        ]
    if set(controls_by_edge) != topology_edge_ids:
        raise SchematicLayoutError(
            "schematic layout segment coverage does not match topology"
        )

    boundary = layout.get("terminal_boundary")
    if (
        not isinstance(boundary, dict)
        or boundary.get("topology_node_id") != EXPECTED_TERMINAL_NODE_ID
        or boundary.get("incoming_topology_edge_id")
        != EXPECTED_TERMINAL_EDGE_ID
        or boundary.get("rendered_successor_topology_edge_ids") != []
        or boundary.get("unrendered_surface_successor_osm_way_ids")
        != EXPECTED_SURFACE_SUCCESSOR_WAY_IDS
        or boundary.get("reason_code") != EXPECTED_BOUNDARY_REASON
    ):
        raise SchematicLayoutError(
            "schematic layout surface boundary has drifted"
        )
    for way_id in EXPECTED_SURFACE_SUCCESSOR_WAY_IDS:
        if any(
            f"osm-way.{way_id}." in edge_id
            for edge_id in controls_by_edge
        ):
            raise SchematicLayoutError(
                f"surface successor way {way_id} leaked into the layout"
            )

    return points_by_node, controls_by_edge


def schematic_segment_id(topology_edge_id: str) -> str:
    prefix = "shutoko.topology-edge."
    if not topology_edge_id.startswith(prefix):
        raise SchematicLayoutError(
            f"unsupported topology edge identity {topology_edge_id}"
        )
    return "shutoko.schematic-segment." + topology_edge_id.removeprefix(prefix)


def build_candidate(
    base_candidate: dict[str, Any],
    layout: dict[str, Any],
    layout_sha256: str,
) -> dict[str, Any]:
    validate_base_candidate(base_candidate)
    points_by_node, controls_by_edge = validate_layout(
        layout,
        base_candidate,
    )
    candidate = copy.deepcopy(base_candidate)
    topology_edges = candidate["topology_slice"]["edges"]
    segment_ids = {
        edge["edge_id"]: schematic_segment_id(edge["edge_id"])
        for edge in topology_edges
    }
    segments = []
    for edge in topology_edges:
        edge_id = edge["edge_id"]
        segments.append(
            {
                "segment_id": segment_ids[edge_id],
                "topology_edge_id": edge_id,
                "from_node_id": edge["from_node_id"],
                "to_node_id": edge["to_node_id"],
                "successor_segment_ids": [
                    segment_ids[successor_id]
                    for successor_id in edge["successor_edge_ids"]
                ],
                "points": [
                    points_by_node[edge["from_node_id"]],
                    *controls_by_edge[edge_id],
                    points_by_node[edge["to_node_id"]],
                ],
            }
        )

    previous_segments = {
        segment["segment_id"]: segment["topology_edge_id"]
        for segment in candidate["definition"]["segments"]
    }
    occurrence_bindings = []
    for binding in candidate["definition"]["occurrence_bindings"]:
        topology_edge_id = previous_segments.get(binding["segment_id"])
        if topology_edge_id is None:
            raise SchematicLayoutError(
                "base occurrence binding references an unknown segment"
            )
        occurrence_bindings.append(
            {
                **binding,
                "segment_id": segment_ids[topology_edge_id],
            }
        )

    source_reference = copy.deepcopy(layout["source_reference"])
    source_reference["content_sha256"] = layout_sha256
    source_reference["checked_at"] = layout["checked_at"]
    existing_reference_ids = {
        reference["source_reference_id"]
        for reference in candidate["source_registry"]["references"]
    }
    if source_reference["source_reference_id"] in existing_reference_ids:
        raise SchematicLayoutError("layout source reference is duplicated")
    candidate["source_registry"]["references"].append(source_reference)
    candidate["definition"] = {
        "atlas_id": OUTPUT_ATLAS_ID,
        "network_snapshot_id": layout["network_snapshot_id"],
        "route_plan_id": layout["route_plan_id"],
        "topology_slice_id": layout["topology_slice_id"],
        "nodes": [
            {
                "topology_node_id": node["topology_node_id"],
                "point": points_by_node[node["topology_node_id"]],
            }
            for node in layout["nodes"]
        ],
        "segments": segments,
        "occurrence_bindings": occurrence_bindings,
        "evidence": {
            "state": CANDIDATE_STATE,
            "checked_at": layout["checked_at"],
            "source_reference_ids": [
                source_reference["source_reference_id"]
            ],
        },
    }
    return candidate


def scenario_definition(candidate: dict[str, Any]) -> dict[str, Any]:
    definition = copy.deepcopy(candidate["definition"])
    for binding in definition["occurrence_bindings"]:
        binding["index"] = binding.pop("occurrence_index")
    return definition


def build_scenario(
    candidate: dict[str, Any],
    layout: dict[str, Any],
) -> dict[str, Any]:
    surface_successor_ids = layout["terminal_boundary"][
        "unrendered_surface_successor_osm_way_ids"
    ]
    return {
        "schema_version": SCHEMA_VERSION,
        "id": "KR-D24",
        "title": (
            "K7 schematic candidate stops at the unresolved surface boundary"
        ),
        "layer": "DOMAIN",
        "tags": [
            "route-atlas",
            "k7",
            "schematic-layout",
            "release-gate",
            "fail-closed",
        ],
        "purpose": (
            "Prove that a Kaido-owned normalized schematic covers every "
            "reviewed expressway topology edge and both divergences without "
            "rendering any unreviewed surface successor."
        ),
        "evidence": {
            "classification": "COMMUNITY_CANDIDATE",
            "sources": [
                {
                    "id": "osm-geofabrik-kanto-260721",
                    "uri": candidate["source_registry"]["references"][0][
                        "source_url"
                    ],
                    "checked_at": layout["checked_at"],
                    "supports": (
                        "The isolated ODbL database supplies the bounded "
                        "directed topology and exact endpoint identities."
                    ),
                },
                {
                    "id": "kaido-k7-schematic-layout",
                    "uri": layout["source_reference"]["source_url"],
                    "checked_at": layout["checked_at"],
                    "supports": (
                        "The project-authored normalized layout separates "
                        "visual geometry from graph authority."
                    ),
                },
            ],
            "limitations": [
                (
                    "The schematic is a production-layout candidate, not "
                    "released navigation evidence."
                ),
                (
                    "All three source-adjacent surface ways are intentionally "
                    "unrendered beyond the exit terminal."
                ),
            ],
            "release_blockers": [
                (
                    "Topology and layout evidence remain CANDIDATE pending "
                    "independent release review."
                ),
                (
                    "Current surface-road identity, direction, and permitted "
                    "exit movement remain unresolved."
                ),
            ],
        },
        "given": {
            "network_snapshot": candidate["network_snapshot"],
            "route_plan": candidate["route_plan"],
            "inputs": {
                "route_atlas_sources": candidate["source_registry"][
                    "references"
                ],
                "route_atlas_topology": candidate["topology_slice"],
                "route_atlas": scenario_definition(candidate),
            },
            "system_state": {
                "layout_method": layout["authoring_method"],
                "layout_segment_count": len(
                    candidate["definition"]["segments"]
                ),
                "terminal_boundary_node_id": EXPECTED_TERMINAL_NODE_ID,
                "rendered_surface_successor_count": 0,
                "unrendered_surface_successor_way_ids": surface_successor_ids,
            },
        },
        "when": [
            {
                "id": "attempt-release",
                "at_ms": 0,
                "type": "ROUTE_ATLAS_RELEASE_VALIDATED",
                "payload": {},
            }
        ],
        "then": [
            {
                "id": "schematic-candidate-remains-blocked",
                "after": "attempt-release",
                "category": "SAFETY",
                "subject": "route_atlas.status",
                "matcher": "EQUALS",
                "expected": "BLOCKED",
                "rationale": (
                    "A structurally complete schematic does not become "
                    "released navigation data."
                ),
            },
            {
                "id": "topology-release-remains-required",
                "after": "attempt-release",
                "category": "EVIDENCE",
                "subject": "route_atlas.error_codes",
                "matcher": "CONTAINS",
                "expected": "UNRELEASED_ATLAS_TOPOLOGY_EVIDENCE",
                "rationale": (
                    "The reviewed expressway topology remains a candidate."
                ),
            },
            {
                "id": "layout-release-remains-required",
                "after": "attempt-release",
                "category": "EVIDENCE",
                "subject": "route_atlas.error_codes",
                "matcher": "CONTAINS",
                "expected": "UNRELEASED_ATLAS_EVIDENCE",
                "rationale": (
                    "The Kaido-authored schematic still requires production "
                    "layout release review."
                ),
            },
        ],
    }


def svg_point(point: dict[str, float]) -> tuple[float, float]:
    return 70.0 + point["x"] * 860.0, 55.0 + point["y"] * 540.0


def render_svg(
    candidate: dict[str, Any],
    layout: dict[str, Any],
) -> str:
    definition = candidate["definition"]
    route_segment_ids = {
        binding["segment_id"] for binding in definition["occurrence_bindings"]
    }
    alternative_edge_ids = {
        "shutoko.topology-edge.osm-way.686983567.forward",
        "shutoko.topology-edge.osm-way.367046943.forward",
    }
    segment_paths = []
    for segment in definition["segments"]:
        points = [svg_point(point) for point in segment["points"]]
        coordinates = " ".join(
            f"{x:.1f},{y:.1f}" for x, y in points
        )
        classes = ["schematic-edge"]
        if segment["segment_id"] in route_segment_ids:
            classes.append("selected")
        if segment["topology_edge_id"] in alternative_edge_ids:
            classes.append("alternative")
        segment_paths.append(
            "    "
            f'<polyline class="{" ".join(classes)}" '
            f'data-topology-edge-id="{html.escape(segment["topology_edge_id"])}" '
            f'points="{coordinates}"/>'
        )

    nodes_by_id = {
        node["topology_node_id"]: svg_point(node["point"])
        for node in definition["nodes"]
    }
    start = nodes_by_id["osm.node.5517714075"]
    terminal = nodes_by_id[EXPECTED_TERMINAL_NODE_ID]
    alt_k7 = nodes_by_id["osm.node.4741046930"]
    alt_e83 = nodes_by_id["osm.node.7299285384"]
    layout_id = html.escape(layout["layout_id"])
    attribution = "© OpenStreetMap contributors"
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 680" role="img" aria-labelledby="title description" data-layout-id="{layout_id}" data-navigation-authority="false">
  <title id="title">K7 Northwest up schematic layout candidate</title>
  <desc id="description">Kaido-owned fixed north-up schematic from Yokohama Aoba entrance to Yokohama Kohoku exit. It expands two reviewed expressway divergences and stops before all three unreviewed surface successors. Candidate only; not for navigation.</desc>
  <metadata>{attribution}; underlying topology ODbL-1.0. Kaido schematic layout Apache-2.0. Candidate checked 2026-07-23.</metadata>
  <style>
    .background {{ fill: #10191e; }}
    .grid {{ stroke: #26363d; stroke-width: 1; }}
    .schematic-edge {{ fill: none; stroke: #51636a; stroke-width: 13; stroke-linecap: round; stroke-linejoin: round; }}
    .schematic-edge.selected {{ stroke: #e9edef; }}
    .schematic-edge.alternative {{ stroke: #74858b; stroke-width: 11; stroke-dasharray: 13 10; }}
    .route-core {{ fill: none; stroke: #efb640; stroke-width: 4; stroke-linecap: round; stroke-linejoin: round; }}
    .node {{ fill: #10191e; stroke: #b8c5c9; stroke-width: 3; }}
    .decision {{ fill: #efb640; stroke: #fff0bc; }}
    .terminal {{ fill: #f28070; stroke: #ffe3de; }}
    .terminal-bar {{ stroke: #f28070; stroke-width: 7; stroke-linecap: round; }}
    .label {{ fill: #e9edef; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; font-size: 21px; font-weight: 700; }}
    .secondary {{ fill: #9babb0; font-size: 16px; font-weight: 600; }}
    .status {{ fill: #f7c0b8; font-size: 15px; font-weight: 800; letter-spacing: 1.2px; }}
    .shield {{ fill: #10191e; stroke: #efb640; stroke-width: 2; }}
    .shield-text {{ fill: #efb640; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; font-size: 22px; font-weight: 900; text-anchor: middle; dominant-baseline: central; }}
    .attribution {{ fill: #788a91; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; font-size: 13px; }}
  </style>
  <rect class="background" width="1000" height="680" rx="28"/>
  <g opacity=".7">
    <path class="grid" d="M70 120H930M70 240H930M70 360H930M70 480H930M180 55V625M360 55V625M540 55V625M720 55V625M900 55V625"/>
  </g>
  <g id="schematic-segments">
{chr(10).join(segment_paths)}
  </g>
  <g id="route-core">
{chr(10).join(path.replace('class="schematic-edge selected"', 'class="route-core"').replace('class="schematic-edge selected alternative"', 'class="route-core"') for path in segment_paths if ' selected' in path)}
  </g>
  <circle class="node" cx="{start[0]:.1f}" cy="{start[1]:.1f}" r="9"/>
  <circle class="decision" cx="{nodes_by_id['osm.node.6988179578'][0]:.1f}" cy="{nodes_by_id['osm.node.6988179578'][1]:.1f}" r="10"/>
  <circle class="decision" cx="{nodes_by_id['osm.node.4435202077'][0]:.1f}" cy="{nodes_by_id['osm.node.4435202077'][1]:.1f}" r="10"/>
  <circle class="terminal" cx="{terminal[0]:.1f}" cy="{terminal[1]:.1f}" r="11"/>
  <path class="terminal-bar" d="M{terminal[0] - 14:.1f} {terminal[1] - 14:.1f}L{terminal[0] + 14:.1f} {terminal[1] + 14:.1f}"/>
  <rect class="shield" x="304" y="254" width="54" height="38" rx="10"/>
  <text class="shield-text" x="331" y="273">K7</text>
  <text class="label" x="{start[0] + 18:.1f}" y="{start[1] - 18:.1f}">横浜青葉入口</text>
  <text class="label" x="{terminal[0] + 22:.1f}" y="{terminal[1] + 8:.1f}">横浜港北出口</text>
  <text class="secondary" x="{alt_k7[0] - 45:.1f}" y="{alt_k7[1] - 18:.1f}">K7 横浜北線</text>
  <text class="secondary" x="{alt_e83[0] - 34:.1f}" y="{alt_e83[1] - 18:.1f}">E83 第三京浜</text>
  <text class="status" x="{terminal[0] - 125:.1f}" y="{terminal[1] + 52:.1f}">地表后继未审核 · 图在此停止</text>
  <text class="label" x="70" y="52">K7 横浜北西線 · 上り示意布局候选</text>
  <text class="status" x="70" y="646">CANDIDATE · NAVIGATION BLOCKED</text>
  <text class="attribution" x="930" y="646" text-anchor="end">{attribution}</text>
</svg>
"""


def write_json(value: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True)
        + "\n",
        encoding="utf-8",
    )


def main() -> int:
    arguments = parse_arguments()
    try:
        base_candidate = load_object(arguments.base_candidate)
        layout = load_object(arguments.layout)
        candidate = build_candidate(
            base_candidate,
            layout,
            sha256(arguments.layout),
        )
        scenario = build_scenario(candidate, layout)
        svg = render_svg(candidate, layout)
        write_json(candidate, arguments.candidate_output)
        write_json(scenario, arguments.scenario_output)
        arguments.svg_output.parent.mkdir(parents=True, exist_ok=True)
        arguments.svg_output.write_text(svg, encoding="utf-8")
    except (OSError, SchematicLayoutError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        "PASS: built K7 schematic layout candidate with "
        f"{len(candidate['definition']['segments'])} topology-bound segments; "
        "3 surface successors remain unrendered and navigation stays blocked"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
