#!/usr/bin/env python3
"""Extract a deterministic bounded motorway slice from a pinned OSM PBF.

This evidence-only helper requires pyosmium. Its generated database remains
under ODbL 1.0 and is not relicensed by the repository's Apache-2.0 licence.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import sys
from pathlib import Path
from typing import Any


ALLOWED_HIGHWAYS = {"motorway", "motorway_link"}


class ExtractionError(RuntimeError):
    """A fail-closed source, dependency, or geometry error."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--expected-input-sha256", required=True)
    parser.add_argument("--source-uri", required=True)
    parser.add_argument("--minimum-latitude", required=True, type=float)
    parser.add_argument("--maximum-latitude", required=True, type=float)
    parser.add_argument("--minimum-longitude", required=True, type=float)
    parser.add_argument("--maximum-longitude", required=True, type=float)
    parser.add_argument("--expected-pyosmium-version", default="4.3.1")
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_osmium(expected_version: str) -> Any:
    try:
        actual_version = importlib.metadata.version("osmium")
        import osmium
    except (ImportError, importlib.metadata.PackageNotFoundError) as error:
        raise ExtractionError(
            "pyosmium is required; install the pinned evidence-tool version"
        ) from error
    if actual_version != expected_version:
        raise ExtractionError(
            "pyosmium version mismatch: "
            f"expected {expected_version}, got {actual_version}"
        )
    return osmium


def extract(arguments: argparse.Namespace) -> dict[str, Any]:
    actual_sha256 = sha256(arguments.input)
    if actual_sha256 != arguments.expected_input_sha256:
        raise ExtractionError(
            "input PBF SHA-256 mismatch: "
            f"expected {arguments.expected_input_sha256}, got {actual_sha256}"
        )
    if not (
        arguments.minimum_latitude < arguments.maximum_latitude
        and arguments.minimum_longitude < arguments.maximum_longitude
    ):
        raise ExtractionError("invalid extraction bounds")

    osmium = load_osmium(arguments.expected_pyosmium_version)
    processor = osmium.FileProcessor(str(arguments.input)).with_locations()
    source_snapshot_at = processor.header.get("osmosis_replication_timestamp")
    if not source_snapshot_at:
        raise ExtractionError("PBF has no replication timestamp")

    def in_bounds(latitude: float, longitude: float) -> bool:
        return (
            arguments.minimum_latitude
            <= latitude
            <= arguments.maximum_latitude
            and arguments.minimum_longitude
            <= longitude
            <= arguments.maximum_longitude
        )

    ways: list[dict[str, Any]] = []
    nodes: dict[int, dict[str, Any]] = {}
    for obj in processor:
        if not obj.is_way():
            continue
        tags = dict(obj.tags)
        if tags.get("highway") not in ALLOWED_HIGHWAYS:
            continue
        coordinates = [
            (node.ref, node.location.lat, node.location.lon)
            for node in obj.nodes
            if node.location.valid()
        ]
        if len(coordinates) != len(obj.nodes):
            raise ExtractionError(f"way {obj.id} has an unresolved node")
        if not any(
            in_bounds(latitude, longitude)
            for _, latitude, longitude in coordinates
        ):
            continue
        for node_id, latitude, longitude in coordinates:
            nodes[node_id] = {
                "type": "node",
                "id": node_id,
                "lat": latitude,
                "lon": longitude,
            }
        ways.append(
            {
                "type": "way",
                "id": obj.id,
                "nodes": [node_id for node_id, _, _ in coordinates],
                "tags": tags,
            }
        )

    selected_way_ids = {int(way["id"]) for way in ways}
    selected_node_ids = set(nodes)
    selected_endpoint_ids = {
        int(way["nodes"][0])
        for way in ways
    } | {
        int(way["nodes"][-1])
        for way in ways
    }
    boundary_ways: list[dict[str, Any]] = []
    relations: list[dict[str, Any]] = []
    for obj in osmium.FileProcessor(str(arguments.input)):
        if obj.is_way():
            if obj.id in selected_way_ids or obj.tags.get("highway") is None:
                continue
            node_ids = [node.ref for node in obj.nodes]
            if selected_endpoint_ids.intersection(node_ids):
                boundary_ways.append(
                    {
                        "type": "way",
                        "id": obj.id,
                        "nodes": node_ids,
                        "tags": dict(obj.tags),
                    }
                )
            continue
        if not obj.is_relation() or obj.tags.get("type") != "restriction":
            continue
        members = [
            {
                "type": {
                    "n": "node",
                    "w": "way",
                    "r": "relation",
                }.get(member.type, member.type),
                "ref": member.ref,
                "role": member.role,
            }
            for member in obj.members
        ]
        if any(
            (
                member["type"] == "way"
                and member["ref"] in selected_way_ids
            )
            or (
                member["type"] == "node"
                and member["ref"] in selected_node_ids
            )
            for member in members
        ):
            relations.append(
                {
                    "type": "relation",
                    "id": obj.id,
                    "members": members,
                    "tags": dict(obj.tags),
                }
            )

    if not ways:
        raise ExtractionError("bounded PBF scan produced no motorway ways")
    return {
        "schema_version": "1.0",
        "source": {
            "input_file": arguments.input.name,
            "input_sha256": actual_sha256,
            "source_snapshot_at": source_snapshot_at,
            "source_uri": arguments.source_uri,
            "licence": "ODbL-1.0",
            "attribution": "© OpenStreetMap contributors",
            "extraction_tool": "pyosmium",
            "extraction_tool_version": arguments.expected_pyosmium_version,
        },
        "bounds": {
            "minimum_latitude": arguments.minimum_latitude,
            "maximum_latitude": arguments.maximum_latitude,
            "minimum_longitude": arguments.minimum_longitude,
            "maximum_longitude": arguments.maximum_longitude,
        },
        "nodes": sorted(nodes.values(), key=lambda node: int(node["id"])),
        "ways": sorted(ways, key=lambda way: int(way["id"])),
        "boundary_ways": sorted(
            boundary_ways,
            key=lambda way: int(way["id"]),
        ),
        "relations": sorted(
            relations,
            key=lambda relation: int(relation["id"]),
        ),
    }


def main() -> int:
    arguments = parse_arguments()
    try:
        result = extract(arguments)
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(
            json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True)
            + "\n",
            encoding="utf-8",
        )
    except (ExtractionError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        "PASS: extracted "
        f"{len(result['ways'])} motorway ways and "
        f"{len(result['nodes'])} nodes with "
        f"{len(result['boundary_ways'])} endpoint boundary ways "
        "from the pinned PBF"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
