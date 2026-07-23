#!/usr/bin/env python3
"""Build an ODbL-isolated directed K7 Northwest Route Atlas candidate."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from datetime import date, datetime
from pathlib import Path
from typing import Any

from audit_osm_directed_successors import (
    SuccessorAuditError,
    build_audit,
    build_scenario as build_successor_scenario,
)


EXPECTED_SCHEMA_VERSION = "1.0"
EXPECTED_CANDIDATE_STATE = "CANDIDATE"
EXPECTED_LICENCE = "ODbL-1.0"
EXPECTED_ATTRIBUTION = "© OpenStreetMap contributors"
EXPECTED_HIGHWAYS = {"motorway", "motorway_link"}


class DirectedCandidateBuildError(RuntimeError):
    """A fail-closed directed candidate source or identity error."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-extract", required=True, type=Path)
    parser.add_argument("--review", required=True, type=Path)
    parser.add_argument("--database-output", required=True, type=Path)
    parser.add_argument("--candidate-output", required=True, type=Path)
    parser.add_argument("--scenario-output", type=Path)
    parser.add_argument("--successor-audit-output", type=Path)
    parser.add_argument("--successor-scenario-output", type=Path)
    return parser.parse_args()


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise DirectedCandidateBuildError(
            f"cannot read JSON {path}: {error}"
        ) from error
    if not isinstance(value, dict):
        raise DirectedCandidateBuildError(f"expected a JSON object in {path}")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def valid_sha256(value: Any) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def validated_review(review: dict[str, Any]) -> None:
    if (
        review.get("schema_version") != EXPECTED_SCHEMA_VERSION
        or review.get("candidate_state") != EXPECTED_CANDIDATE_STATE
        or review.get("navigation_authority") is not False
    ):
        raise DirectedCandidateBuildError(
            "directed candidate review boundary is invalid"
        )
    try:
        date.fromisoformat(review.get("checked_at"))
        effective_at = review.get("network_effective_at")
        if not isinstance(effective_at, str):
            raise ValueError("missing network effective time")
        datetime.fromisoformat(effective_at.replace("Z", "+00:00"))
    except (TypeError, ValueError) as error:
        raise DirectedCandidateBuildError(
            "directed candidate review date is invalid"
        ) from error

    source = review.get("source_extract")
    route = review.get("route")
    alternatives = review.get("divergence_alternatives")
    if (
        not isinstance(source, dict)
        or not valid_sha256(source.get("expected_extract_sha256"))
        or not valid_sha256(source.get("parent_pbf_sha256"))
        or source.get("licence") != EXPECTED_LICENCE
        or source.get("attribution") != EXPECTED_ATTRIBUTION
        or not isinstance(route, dict)
        or not isinstance(route.get("way_ids"), list)
        or len(route["way_ids"]) < 2
        or len(set(route["way_ids"])) != len(route["way_ids"])
        or not all(
            isinstance(way_id, int) and way_id > 0
            for way_id in route["way_ids"]
        )
        or not isinstance(alternatives, list)
        or len(alternatives) != 2
    ):
        raise DirectedCandidateBuildError(
            "directed candidate source selection is incomplete"
        )
    alternative_ids: set[int] = set()
    for alternative in alternatives:
        if (
            not isinstance(alternative, dict)
            or not isinstance(alternative.get("after_way_id"), int)
            or alternative["after_way_id"] not in route["way_ids"]
            or not isinstance(alternative.get("way_id"), int)
            or alternative["way_id"] in alternative_ids
            or alternative["way_id"] in route["way_ids"]
            or not isinstance(alternative.get("role"), str)
            or not alternative["role"]
        ):
            raise DirectedCandidateBuildError(
                "directed candidate divergence selection is invalid"
            )
        alternative_ids.add(alternative["way_id"])

    source_references = review.get("source_references")
    topology_ids = review.get("topology_evidence_source_ids")
    layout_ids = review.get("layout_evidence_source_ids")
    if (
        not isinstance(source_references, list)
        or len(source_references) < 3
        or not isinstance(topology_ids, list)
        or not isinstance(layout_ids, list)
    ):
        raise DirectedCandidateBuildError(
            "directed candidate evidence registry is incomplete"
        )
    references_by_id: dict[str, dict[str, Any]] = {}
    for reference in source_references:
        if not isinstance(reference, dict):
            raise DirectedCandidateBuildError(
                "directed candidate evidence source is invalid"
            )
        reference_id = reference.get("source_reference_id")
        if (
            not isinstance(reference_id, str)
            or not reference_id
            or reference_id in references_by_id
            or not isinstance(reference.get("roles"), list)
            or not reference["roles"]
            or not set(reference["roles"]).issubset(
                {"TOPOLOGY_EVIDENCE", "LAYOUT_EVIDENCE"}
            )
            or not str(reference.get("source_url", "")).startswith("https://")
            or not valid_sha256(reference.get("content_sha256"))
        ):
            raise DirectedCandidateBuildError(
                "directed candidate evidence source is invalid"
            )
        try:
            date.fromisoformat(reference.get("checked_at"))
        except (TypeError, ValueError) as error:
            raise DirectedCandidateBuildError(
                "directed candidate evidence date is invalid"
            ) from error
        references_by_id[reference_id] = reference
    if (
        set(topology_ids) | set(layout_ids) != set(references_by_id)
        or not set(layout_ids).issubset(set(topology_ids))
        or any(
            "TOPOLOGY_EVIDENCE"
            not in references_by_id[source_id]["roles"]
            for source_id in topology_ids
        )
        or any(
            "LAYOUT_EVIDENCE"
            not in references_by_id[source_id]["roles"]
            for source_id in layout_ids
        )
    ):
        raise DirectedCandidateBuildError(
            "directed candidate evidence roles have drifted"
        )
    blockers = review.get("release_blockers")
    if not isinstance(blockers, list) or len(blockers) < 4:
        raise DirectedCandidateBuildError(
            "directed candidate release blockers are incomplete"
        )


def validate_source_extract(
    source_extract: dict[str, Any],
    review: dict[str, Any],
    source_extract_sha256: str,
) -> tuple[
    dict[int, dict[str, Any]],
    dict[int, dict[str, Any]],
    dict[int, dict[str, Any]],
]:
    expected = review["source_extract"]
    source = source_extract.get("source")
    if (
        source_extract.get("schema_version") != EXPECTED_SCHEMA_VERSION
        or source_extract_sha256 != expected["expected_extract_sha256"]
        or not isinstance(source, dict)
        or source.get("input_sha256") != expected["parent_pbf_sha256"]
        or source.get("source_snapshot_at")
        != expected["source_snapshot_at"]
        or source.get("source_uri") != expected["source_url"]
        or source.get("licence") != EXPECTED_LICENCE
        or source.get("attribution") != EXPECTED_ATTRIBUTION
        or source.get("extraction_tool") != "pyosmium"
        or source.get("extraction_tool_version")
        != expected["extraction_tool_version"]
        or source_extract.get("bounds") != expected["bounds"]
    ):
        raise DirectedCandidateBuildError(
            "bounded OSM source identity has drifted"
        )
    ways_value = source_extract.get("ways")
    nodes_value = source_extract.get("nodes")
    boundary_ways_value = source_extract.get("boundary_ways")
    if (
        not isinstance(ways_value, list)
        or not isinstance(nodes_value, list)
        or not isinstance(boundary_ways_value, list)
    ):
        raise DirectedCandidateBuildError(
            "bounded OSM source has no ways, nodes, or boundary ways"
        )
    ways: dict[int, dict[str, Any]] = {}
    for way in ways_value:
        if (
            not isinstance(way, dict)
            or not isinstance(way.get("id"), int)
            or way["id"] in ways
            or not isinstance(way.get("nodes"), list)
            or len(way["nodes"]) < 2
            or not isinstance(way.get("tags"), dict)
        ):
            raise DirectedCandidateBuildError(
                "bounded OSM source contains an invalid way"
            )
        ways[way["id"]] = way
    nodes: dict[int, dict[str, Any]] = {}
    for node in nodes_value:
        if (
            not isinstance(node, dict)
            or not isinstance(node.get("id"), int)
            or node["id"] in nodes
            or not isinstance(node.get("lat"), (int, float))
            or not isinstance(node.get("lon"), (int, float))
            or not math.isfinite(node["lat"])
            or not math.isfinite(node["lon"])
        ):
            raise DirectedCandidateBuildError(
                "bounded OSM source contains an invalid node"
            )
        nodes[node["id"]] = node
    boundary_ways: dict[int, dict[str, Any]] = {}
    for way in boundary_ways_value:
        if (
            not isinstance(way, dict)
            or not isinstance(way.get("id"), int)
            or way["id"] in boundary_ways
            or way["id"] in ways
            or not isinstance(way.get("nodes"), list)
            or len(way["nodes"]) < 2
            or not isinstance(way.get("tags"), dict)
            or not isinstance(way["tags"].get("highway"), str)
        ):
            raise DirectedCandidateBuildError(
                "bounded OSM source contains an invalid boundary way"
            )
        boundary_ways[way["id"]] = way
    return ways, nodes, boundary_ways


def build_database(
    source_extract: dict[str, Any],
    review: dict[str, Any],
    source_extract_sha256: str,
) -> dict[str, Any]:
    validated_review(review)
    ways, nodes, boundary_ways = validate_source_extract(
        source_extract,
        review,
        source_extract_sha256,
    )
    route = review["route"]
    route_way_ids = route["way_ids"]
    alternative_way_ids = [
        alternative["way_id"]
        for alternative in review["divergence_alternatives"]
    ]
    selected_way_ids = route_way_ids + alternative_way_ids
    try:
        selected_ways = [ways[way_id] for way_id in selected_way_ids]
    except KeyError as error:
        raise DirectedCandidateBuildError(
            f"expected OSM way {error.args[0]} is absent"
        ) from error

    for way in selected_ways:
        tags = way["tags"]
        if (
            tags.get("highway") not in EXPECTED_HIGHWAYS
            or tags.get("oneway") != "yes"
            or any(node_id not in nodes for node_id in way["nodes"])
        ):
            raise DirectedCandidateBuildError(
                f"OSM way {way['id']} lost its directed-road identity"
            )
    for first_id, second_id in zip(route_way_ids, route_way_ids[1:]):
        if ways[first_id]["nodes"][-1] != ways[second_id]["nodes"][0]:
            raise DirectedCandidateBuildError(
                f"route discontinuity between OSM ways {first_id} and {second_id}"
            )
    if (
        ways[route_way_ids[0]]["nodes"][0]
        != route["entry_node_id"]
        or ways[route_way_ids[-1]]["nodes"][-1]
        != route["exit_node_id"]
    ):
        raise DirectedCandidateBuildError(
            "directed route facility boundary has drifted"
        )
    for alternative in review["divergence_alternatives"]:
        predecessor = ways[alternative["after_way_id"]]
        alternate = ways[alternative["way_id"]]
        if predecessor["nodes"][-1] != alternate["nodes"][0]:
            raise DirectedCandidateBuildError(
                f"alternative OSM way {alternate['id']} is disconnected"
            )

    boundary_checks = review.get("facility_boundary_checks")
    if not isinstance(boundary_checks, dict):
        raise DirectedCandidateBuildError(
            "facility boundary checks are missing"
        )
    entry_predecessor_id = boundary_checks.get(
        "entry_predecessor_way_id"
    )
    entry_nonroute_successor_id = boundary_checks.get(
        "entry_nonroute_successor_way_id"
    )
    exit_surface_successor_ids = boundary_checks.get(
        "exit_surface_successor_way_ids"
    )
    if (
        not isinstance(entry_predecessor_id, int)
        or entry_predecessor_id not in ways
        or ways[entry_predecessor_id]["nodes"][-1]
        != route["entry_node_id"]
        or not isinstance(entry_nonroute_successor_id, int)
        or entry_nonroute_successor_id not in ways
        or ways[entry_nonroute_successor_id]["nodes"][0]
        != route["entry_node_id"]
        or not isinstance(exit_surface_successor_ids, list)
        or len(exit_surface_successor_ids) < 1
        or any(
            way_id not in boundary_ways
            or boundary_ways[way_id]["nodes"][0]
            != route["exit_node_id"]
            for way_id in exit_surface_successor_ids
        )
    ):
        raise DirectedCandidateBuildError(
            "facility boundary connection has drifted"
        )
    expected_surface_tags_by_way = boundary_checks.get(
        "required_exit_surface_tags_by_way",
    )
    if (
        not isinstance(expected_surface_tags_by_way, dict)
        or set(expected_surface_tags_by_way)
        != {str(way_id) for way_id in exit_surface_successor_ids}
    ):
        raise DirectedCandidateBuildError(
            "exit surface tag requirements have drifted"
        )
    for way_id in exit_surface_successor_ids:
        tags = boundary_ways[way_id]["tags"]
        expected_surface_tags = expected_surface_tags_by_way[str(way_id)]
        if not isinstance(expected_surface_tags, dict):
            raise DirectedCandidateBuildError(
                f"exit surface tag requirements are invalid for OSM way {way_id}"
            )
        if any(
            tags.get(key) != value
            for key, value in expected_surface_tags.items()
        ):
            raise DirectedCandidateBuildError(
                f"exit surface tags drifted for OSM way {way_id}"
            )

    required_tags = review.get("required_way_tags", {})
    for way_id_text, expected_tags in required_tags.items():
        way_id = int(way_id_text)
        actual_tags = ways.get(way_id, {}).get("tags", {})
        if any(
            actual_tags.get(key) != value
            for key, value in expected_tags.items()
        ):
            raise DirectedCandidateBuildError(
                f"required tags drifted for OSM way {way_id}"
            )

    retained_node_ids = sorted(
        {
            node_id
            for way in selected_ways
            for node_id in way["nodes"]
        }
    )
    source = source_extract["source"]
    return {
        "schema_version": EXPECTED_SCHEMA_VERSION,
        "database_id": review["database_id"],
        "licence": EXPECTED_LICENCE,
        "attribution": EXPECTED_ATTRIBUTION,
        "navigation_authority": False,
        "source": {
            "parent_pbf_url": source["source_uri"],
            "parent_pbf_sha256": source["input_sha256"],
            "source_snapshot_at": source["source_snapshot_at"],
            "bounded_extract_sha256": source_extract_sha256,
            "extraction_tool": source["extraction_tool"],
            "extraction_tool_version": source[
                "extraction_tool_version"
            ],
            "bounds": source_extract["bounds"],
        },
        "route": {
            "entry_facility_id": route["entry_facility_id"],
            "exit_facility_id": route["exit_facility_id"],
            "entry_node_id": route["entry_node_id"],
            "exit_node_id": route["exit_node_id"],
            "way_ids": route_way_ids,
        },
        "divergence_alternatives": review[
            "divergence_alternatives"
        ],
        "facility_boundary_evidence": {
            "entry_predecessor_way": ways[entry_predecessor_id],
            "entry_nonroute_successor_way": ways[
                entry_nonroute_successor_id
            ],
            "exit_surface_successor_ways": [
                boundary_ways[way_id]
                for way_id in exit_surface_successor_ids
            ],
        },
        "nodes": [nodes[node_id] for node_id in retained_node_ids],
        "ways": selected_ways,
    }


def normalized_points(
    nodes: dict[int, dict[str, Any]],
) -> dict[int, dict[str, float]]:
    longitudes = [node["lon"] for node in nodes.values()]
    latitudes = [node["lat"] for node in nodes.values()]
    minimum_longitude = min(longitudes)
    maximum_longitude = max(longitudes)
    minimum_latitude = min(latitudes)
    maximum_latitude = max(latitudes)
    center_longitude = (minimum_longitude + maximum_longitude) / 2
    center_latitude = (minimum_latitude + maximum_latitude) / 2
    longitude_scale = math.cos(math.radians(center_latitude))
    width = (maximum_longitude - minimum_longitude) * longitude_scale
    height = maximum_latitude - minimum_latitude
    extent = max(width, height)
    if extent <= 0:
        raise DirectedCandidateBuildError(
            "directed candidate geometry is degenerate"
        )
    scale = 0.84 / extent
    return {
        node_id: {
            "x": round(
                0.5
                + (node["lon"] - center_longitude)
                * longitude_scale
                * scale,
                9,
            ),
            "y": round(
                0.5 - (node["lat"] - center_latitude) * scale,
                9,
            ),
        }
        for node_id, node in nodes.items()
    }


def build_candidate(
    database: dict[str, Any],
    review: dict[str, Any],
) -> dict[str, Any]:
    validated_review(review)
    if (
        database.get("schema_version") != EXPECTED_SCHEMA_VERSION
        or database.get("database_id") != review["database_id"]
        or database.get("licence") != EXPECTED_LICENCE
        or database.get("attribution") != EXPECTED_ATTRIBUTION
        or database.get("navigation_authority") is not False
        or database.get("route") != review["route"]
        or database.get("divergence_alternatives")
        != review["divergence_alternatives"]
        or not isinstance(
            database.get("facility_boundary_evidence"),
            dict,
        )
    ):
        raise DirectedCandidateBuildError(
            "derived K7 database identity has drifted"
        )
    ways = {way["id"]: way for way in database.get("ways", [])}
    nodes = {node["id"]: node for node in database.get("nodes", [])}
    route_way_ids = review["route"]["way_ids"]
    alternative_way_ids = [
        alternative["way_id"]
        for alternative in review["divergence_alternatives"]
    ]
    all_way_ids = route_way_ids + alternative_way_ids
    if set(ways) != set(all_way_ids):
        raise DirectedCandidateBuildError(
            "derived K7 database way coverage has drifted"
        )
    facility_boundary = database["facility_boundary_evidence"]
    boundary_checks = review["facility_boundary_checks"]
    entry_predecessor = facility_boundary.get("entry_predecessor_way")
    entry_nonroute_successor = facility_boundary.get(
        "entry_nonroute_successor_way"
    )
    exit_surface_successors = facility_boundary.get(
        "exit_surface_successor_ways"
    )
    required_exit_tags_by_way = boundary_checks.get(
        "required_exit_surface_tags_by_way"
    )
    if (
        not isinstance(entry_predecessor, dict)
        or entry_predecessor.get("id")
        != boundary_checks["entry_predecessor_way_id"]
        or entry_predecessor.get("nodes", [])[-1:]
        != [review["route"]["entry_node_id"]]
        or not isinstance(entry_nonroute_successor, dict)
        or entry_nonroute_successor.get("id")
        != boundary_checks["entry_nonroute_successor_way_id"]
        or entry_nonroute_successor.get("nodes", [])[:1]
        != [review["route"]["entry_node_id"]]
        or not isinstance(exit_surface_successors, list)
        or not isinstance(required_exit_tags_by_way, dict)
        or set(required_exit_tags_by_way)
        != {
            str(way_id)
            for way_id in boundary_checks["exit_surface_successor_way_ids"]
        }
        or [
            way.get("id")
            for way in exit_surface_successors
            if isinstance(way, dict)
        ]
        != boundary_checks["exit_surface_successor_way_ids"]
        or any(
            way.get("nodes", [])[:1]
            != [review["route"]["exit_node_id"]]
            or any(
                way.get("tags", {}).get(key) != value
                for key, value in required_exit_tags_by_way.get(
                    str(way.get("id")),
                    {},
                ).items()
            )
            for way in exit_surface_successors
        )
    ):
        raise DirectedCandidateBuildError(
            "derived facility boundary evidence has drifted"
        )
    source = database.get("source")
    expected_source = review["source_extract"]
    if (
        not isinstance(source, dict)
        or source.get("parent_pbf_url") != expected_source["source_url"]
        or source.get("parent_pbf_sha256")
        != expected_source["parent_pbf_sha256"]
        or source.get("source_snapshot_at")
        != expected_source["source_snapshot_at"]
        or source.get("bounded_extract_sha256")
        != expected_source["expected_extract_sha256"]
        or source.get("extraction_tool") != "pyosmium"
        or source.get("extraction_tool_version")
        != expected_source["extraction_tool_version"]
        or source.get("bounds") != expected_source["bounds"]
    ):
        raise DirectedCandidateBuildError(
            "derived K7 database source lineage has drifted"
        )
    for way_id in all_way_ids:
        way = ways[way_id]
        if (
            not isinstance(way.get("nodes"), list)
            or len(way["nodes"]) < 2
            or not isinstance(way.get("tags"), dict)
            or way["tags"].get("highway") not in EXPECTED_HIGHWAYS
            or way["tags"].get("oneway") != "yes"
            or any(node_id not in nodes for node_id in way["nodes"])
        ):
            raise DirectedCandidateBuildError(
                f"derived OSM way {way_id} has drifted"
            )
    for first_id, second_id in zip(route_way_ids, route_way_ids[1:]):
        if ways[first_id]["nodes"][-1] != ways[second_id]["nodes"][0]:
            raise DirectedCandidateBuildError(
                f"derived route discontinuity between {first_id} and {second_id}"
            )
    if (
        ways[route_way_ids[0]]["nodes"][0]
        != review["route"]["entry_node_id"]
        or ways[route_way_ids[-1]]["nodes"][-1]
        != review["route"]["exit_node_id"]
    ):
        raise DirectedCandidateBuildError(
            "derived route facility boundary has drifted"
        )
    for alternative in review["divergence_alternatives"]:
        if (
            ways[alternative["after_way_id"]]["nodes"][-1]
            != ways[alternative["way_id"]]["nodes"][0]
        ):
            raise DirectedCandidateBuildError(
                f"derived alternative {alternative['way_id']} is disconnected"
            )
    for way_id_text, expected_tags in review.get(
        "required_way_tags",
        {},
    ).items():
        actual_tags = ways[int(way_id_text)]["tags"]
        if any(
            actual_tags.get(key) != value
            for key, value in expected_tags.items()
        ):
            raise DirectedCandidateBuildError(
                f"derived required tags drifted for OSM way {way_id_text}"
            )
    points_by_node = normalized_points(nodes)
    snapshot_id = review["network_snapshot_id"]
    plan_id = review["route_plan_id"]
    topology_slice_id = (
        "shutoko.topology.k7-northwest.osm-directed-candidate.2026-07-23"
    )

    def topology_edge_id(way_id: int) -> str:
        return f"shutoko.topology-edge.osm-way.{way_id}.forward"

    def route_entity_id(way_id: int) -> str:
        return f"shutoko.edge.osm-way.{way_id}.forward"

    def segment_id(way_id: int) -> str:
        return f"shutoko.segment.osm-way.{way_id}.forward"

    alternative_by_predecessor = {
        alternative["after_way_id"]: alternative["way_id"]
        for alternative in review["divergence_alternatives"]
    }
    successors: dict[int, list[int]] = {}
    for index, way_id in enumerate(route_way_ids):
        next_ids = (
            [route_way_ids[index + 1]]
            if index + 1 < len(route_way_ids)
            else []
        )
        if way_id in alternative_by_predecessor:
            next_ids.append(alternative_by_predecessor[way_id])
        successors[way_id] = next_ids
    for way_id in alternative_way_ids:
        successors[way_id] = []

    endpoint_node_ids = sorted(
        {
            way["nodes"][0]
            for way in ways.values()
        }
        | {
            way["nodes"][-1]
            for way in ways.values()
        }
    )
    occurrences = [
        {
            "occurrence_id": (
                f"shutoko.occurrence.k7-northwest.up.osm-way.{way_id}."
                f"{index}"
            ),
            "index": index,
            "kind": "EDGE",
            "entity_id": route_entity_id(way_id),
        }
        for index, way_id in enumerate(route_way_ids)
    ]
    topology_edges = [
        {
            "edge_id": topology_edge_id(way_id),
            "route_entity_id": route_entity_id(way_id),
            "from_node_id": f"osm.node.{ways[way_id]['nodes'][0]}",
            "to_node_id": f"osm.node.{ways[way_id]['nodes'][-1]}",
            "successor_edge_ids": [
                topology_edge_id(successor_id)
                for successor_id in successors[way_id]
            ],
        }
        for way_id in all_way_ids
    ]
    segments = [
        {
            "segment_id": segment_id(way_id),
            "topology_edge_id": topology_edge_id(way_id),
            "from_node_id": f"osm.node.{ways[way_id]['nodes'][0]}",
            "to_node_id": f"osm.node.{ways[way_id]['nodes'][-1]}",
            "successor_segment_ids": [
                segment_id(successor_id)
                for successor_id in successors[way_id]
            ],
            "points": [
                points_by_node[node_id]
                for node_id in ways[way_id]["nodes"]
            ],
        }
        for way_id in all_way_ids
    ]
    evidence = {
        "state": EXPECTED_CANDIDATE_STATE,
        "checked_at": review["checked_at"],
    }
    return {
        "schema_version": EXPECTED_SCHEMA_VERSION,
        "network_snapshot": {
            "id": snapshot_id,
            "status": "ACTIVE",
            "effective_at": review["network_effective_at"],
        },
        "route_plan": {
            "plan_id": plan_id,
            "network_snapshot_id": snapshot_id,
            "entry_facility_id": review["route"]["entry_facility_id"],
            "exit_facility_id": review["route"]["exit_facility_id"],
            "recovery_policy": "STRICT",
            "occurrences": occurrences,
        },
        "source_registry": {
            "references": review["source_references"],
        },
        "topology_slice": {
            "topology_slice_id": topology_slice_id,
            "network_snapshot_id": snapshot_id,
            "nodes": [
                {"node_id": f"osm.node.{node_id}"}
                for node_id in endpoint_node_ids
            ],
            "edges": topology_edges,
            "evidence": {
                **evidence,
                "source_reference_ids": review[
                    "topology_evidence_source_ids"
                ],
            },
        },
        "definition": {
            "atlas_id": (
                "shutoko.atlas.k7-northwest."
                "osm-directed-candidate.2026-07-23"
            ),
            "network_snapshot_id": snapshot_id,
            "route_plan_id": plan_id,
            "topology_slice_id": topology_slice_id,
            "nodes": [
                {
                    "topology_node_id": f"osm.node.{node_id}",
                    "point": points_by_node[node_id],
                }
                for node_id in endpoint_node_ids
            ],
            "segments": segments,
            "occurrence_bindings": [
                {
                    "occurrence_id": occurrence["occurrence_id"],
                    "occurrence_index": occurrence["index"],
                    "segment_id": segment_id(way_id),
                }
                for occurrence, way_id in zip(
                    occurrences,
                    route_way_ids,
                )
            ],
            "evidence": {
                **evidence,
                "source_reference_ids": review[
                    "layout_evidence_source_ids"
                ],
            },
        },
    }


def build_scenario(
    candidate: dict[str, Any],
    database: dict[str, Any],
    review: dict[str, Any],
) -> dict[str, Any]:
    definition = json.loads(json.dumps(candidate["definition"]))
    for binding in definition["occurrence_bindings"]:
        binding["index"] = binding.pop("occurrence_index")
    source_references = {
        reference["source_reference_id"]: reference
        for reference in review["source_references"]
    }
    return {
        "schema_version": "1.0",
        "id": "KR-D22",
        "title": (
            "OSM-directed K7 candidate preserves two divergences "
            "without gaining release authority"
        ),
        "layer": "DOMAIN",
        "tags": [
            "route-atlas",
            "real-evidence",
            "k7",
            "odbl",
            "release-gate",
        ],
        "purpose": (
            "Prove that one exact ODbL-isolated K7 one-way chain and "
            "its two reviewed alternatives pass atlas structural "
            "integrity while remaining non-navigable."
        ),
        "evidence": {
            "classification": "COMMUNITY_CANDIDATE",
            "sources": [
                {
                    "id": "osm-geofabrik-kanto-260721",
                    "uri": review["source_extract"]["source_url"],
                    "checked_at": review["checked_at"],
                    "supports": (
                        "The pinned ODbL Kanto PBF supplies exact OSM "
                        "node, way, tag, and digitized-direction lineage "
                        "for the bounded candidate."
                    ),
                },
                {
                    "id": "shutoko-k7-aoba-guide",
                    "uri": source_references[
                        "shutoko.guide.k7-aoba.2026-07-23"
                    ]["source_url"],
                    "checked_at": review["checked_at"],
                    "supports": (
                        "The operator guide documents the Yokohama "
                        "Aoba entrance movement onto K7 Northwest."
                    ),
                },
                {
                    "id": "shutoko-k7-kohoku-guide",
                    "uri": source_references[
                        "shutoko.guide.k7-kohoku.2026-07-23"
                    ]["source_url"],
                    "checked_at": review["checked_at"],
                    "supports": (
                        "The operator guide documents the K7 Northwest "
                        "up-direction branch toward Daisan-Keihin and "
                        "Yokohama Kohoku exit, followed by the exit split."
                    ),
                },
            ],
            "limitations": [
                (
                    "The OSM-derived graph is a community-data "
                    "candidate, not independent field approval."
                ),
                (
                    "The operator diagrams support factual movement "
                    "review but are not redistributed layout assets."
                ),
            ],
            "release_blockers": review["release_blockers"],
        },
        "given": {
            "network_snapshot": candidate["network_snapshot"],
            "route_plan": candidate["route_plan"],
            "inputs": {
                "route_atlas_sources": candidate["source_registry"][
                    "references"
                ],
                "route_atlas_topology": candidate["topology_slice"],
                "route_atlas": definition,
            },
            "system_state": {
                "directed_route_way_count": len(
                    database["route"]["way_ids"]
                ),
                "reviewed_alternative_count": len(
                    database["divergence_alternatives"]
                ),
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
                "id": "directed-candidate-remains-blocked",
                "after": "attempt-release",
                "category": "SAFETY",
                "subject": "route_atlas.status",
                "matcher": "EQUALS",
                "expected": "BLOCKED",
                "rationale": (
                    "A structurally coherent directed graph does not "
                    "silently become released navigation data."
                ),
            },
            {
                "id": "topology-review-remains-required",
                "after": "attempt-release",
                "category": "EVIDENCE",
                "subject": "route_atlas.error_codes",
                "matcher": "CONTAINS",
                "expected": "UNRELEASED_ATLAS_TOPOLOGY_EVIDENCE",
                "rationale": (
                    "The OSM-derived candidate still requires release "
                    "review and independent corroboration."
                ),
            },
            {
                "id": "layout-review-remains-required",
                "after": "attempt-release",
                "category": "EVIDENCE",
                "subject": "route_atlas.error_codes",
                "matcher": "CONTAINS",
                "expected": "UNRELEASED_ATLAS_EVIDENCE",
                "rationale": (
                    "Raw OSM-derived geometry is not a released Kaido "
                    "production atlas layout."
                ),
            },
        ],
    }


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
        source_extract = load_object(arguments.source_extract)
        review = load_object(arguments.review)
        source_extract_sha256 = sha256(arguments.source_extract)
        successor_audit = build_audit(
            source_extract,
            review,
            source_extract_sha256,
        )
        database = build_database(
            source_extract,
            review,
            source_extract_sha256,
        )
        candidate = build_candidate(database, review)
        write_json(database, arguments.database_output)
        write_json(candidate, arguments.candidate_output)
        if arguments.scenario_output is not None:
            write_json(
                build_scenario(candidate, database, review),
                arguments.scenario_output,
            )
        if arguments.successor_audit_output is not None:
            write_json(
                successor_audit,
                arguments.successor_audit_output,
            )
        if arguments.successor_scenario_output is not None:
            write_json(
                build_successor_scenario(
                    candidate,
                    successor_audit,
                    review,
                ),
                arguments.successor_scenario_output,
            )
    except (
        DirectedCandidateBuildError,
        OSError,
        SuccessorAuditError,
    ) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        "PASS: built ODbL-isolated K7 directed candidate with "
        f"{len(database['route']['way_ids'])} route ways, "
        f"{len(database['divergence_alternatives'])} alternatives, and "
        f"{len(database['nodes'])} retained nodes; audited "
        f"{successor_audit['summary']['checkpoint_count']} successor "
        "checkpoints; navigation remains blocked"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
