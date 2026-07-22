#!/usr/bin/env python3
"""Convert a bounded OpenStreetMap extract into a Kaido surface graph.

The generated graph is derived from OpenStreetMap and remains under ODbL. This
script is Apache-2.0 project code; its output is not relicensed by the repository.
"""

from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, TextIO


ALLOWED_HIGHWAYS = {
    "living_street",
    "motorway",
    "motorway_link",
    "primary",
    "primary_link",
    "residential",
    "road",
    "secondary",
    "secondary_link",
    "service",
    "tertiary",
    "tertiary_link",
    "trunk",
    "trunk_link",
    "unclassified",
}
ALLOWED_ACCESS = {"yes", "designated", "permissive", "destination", "customers"}
FORBIDDEN_ACCESS = {"no", "private"}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input", default="-", help="Overpass JSON or OSM XML path, or - for stdin"
    )
    parser.add_argument("--output", default="-", help="Graph JSON path or - for stdout")
    parser.add_argument(
        "--input-format",
        choices=("auto", "overpass-json", "osm-xml"),
        default="auto",
        help="Input encoding; auto inspects the first non-whitespace character",
    )
    parser.add_argument(
        "--source-snapshot-at",
        help=(
            "Explicit retrieval timestamp required for OSM XML, whose root does not "
            "carry an Overpass base timestamp"
        ),
    )
    parser.add_argument("--network-snapshot-id", required=True)
    parser.add_argument(
        "--source-uri",
        default="https://www.openstreetmap.org",
        help="Human-readable source or query URI retained in provenance",
    )
    parser.add_argument(
        "--expressway-toll-domain-id",
        help="Reviewed toll-domain ID applied to motorway and motorway_link edges",
    )
    return parser.parse_args()


def load_text(path: str) -> str:
    stream: TextIO
    if path == "-":
        stream = sys.stdin
        return stream.read()
    with Path(path).open(encoding="utf-8") as stream:
        return stream.read()


def parse_osm_xml(text: str, source_snapshot_at: str | None) -> dict[str, Any]:
    if not source_snapshot_at:
        raise ValueError("--source-snapshot-at is required for OSM XML input")

    root = ET.fromstring(text)
    if root.tag != "osm":
        raise ValueError("OSM XML root element must be osm")

    elements: list[dict[str, Any]] = []
    for child in root:
        if child.tag == "node":
            node_id = child.get("id")
            latitude = child.get("lat")
            longitude = child.get("lon")
            if node_id is None or latitude is None or longitude is None:
                continue
            elements.append(
                {
                    "type": "node",
                    "id": int(node_id),
                    "lat": float(latitude),
                    "lon": float(longitude),
                }
            )
        elif child.tag == "way":
            way_id = child.get("id")
            if way_id is None:
                continue
            elements.append(
                {
                    "type": "way",
                    "id": int(way_id),
                    "nodes": [
                        int(node.attrib["ref"])
                        for node in child.findall("nd")
                        if "ref" in node.attrib
                    ],
                    "tags": {
                        tag.attrib["k"]: tag.attrib["v"]
                        for tag in child.findall("tag")
                        if "k" in tag.attrib and "v" in tag.attrib
                    },
                }
            )

    return {
        "osm3s": {"timestamp_osm_base": source_snapshot_at},
        "elements": elements,
    }


def load_document(
    path: str, input_format: str, source_snapshot_at: str | None
) -> dict[str, Any]:
    text = load_text(path)
    resolved_format = input_format
    if resolved_format == "auto":
        first_character = text.lstrip()[:1]
        if first_character in {"{", "["}:
            resolved_format = "overpass-json"
        elif first_character == "<":
            resolved_format = "osm-xml"
        else:
            raise ValueError("could not detect input format")

    if resolved_format == "overpass-json":
        document = json.loads(text)
        if not isinstance(document, dict):
            raise ValueError("Overpass JSON root must be an object")
        return document
    return parse_osm_xml(text, source_snapshot_at)


def write_json(value: dict[str, Any], path: str) -> None:
    if path == "-":
        json.dump(value, sys.stdout, ensure_ascii=False, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return
    with Path(path).open("w", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, sort_keys=True)
        stream.write("\n")


def is_motor_accessible(tags: dict[str, str]) -> bool:
    explicit = tags.get("motorcar") or tags.get("motor_vehicle")
    if explicit in ALLOWED_ACCESS:
        return True
    if explicit in FORBIDDEN_ACCESS:
        return False
    return tags.get("access") not in FORBIDDEN_ACCESS


def directions(tags: dict[str, str]) -> tuple[bool, bool]:
    oneway = tags.get("oneway", "").lower()
    if oneway == "-1":
        return False, True
    if oneway in {"yes", "true", "1"} or tags.get("junction") == "roundabout":
        return True, False
    return True, True


def edge_kind(highway: str) -> str:
    if highway == "motorway_link":
        return "ENTRY_TRANSITION"
    if highway == "motorway":
        return "EXPRESSWAY"
    return "ORDINARY_ROAD"


def coordinate(node: dict[str, Any]) -> dict[str, float]:
    return {"latitude": node["lat"], "longitude": node["lon"]}


def make_edge(
    way_id: int,
    segment_index: int,
    direction: str,
    from_node: dict[str, Any],
    to_node: dict[str, Any],
    kind: str,
    toll_domain_id: str | None,
) -> dict[str, Any]:
    edge = {
        "edge_id": f"osm.way.{way_id}.segment.{segment_index}.{direction}",
        "from_node_id": f"osm.node.{from_node['id']}",
        "to_node_id": f"osm.node.{to_node['id']}",
        "kind": kind,
        "coordinates": [coordinate(from_node), coordinate(to_node)],
    }
    if toll_domain_id and kind != "ORDINARY_ROAD":
        edge["toll_domain_id"] = toll_domain_id
    return edge


def convert(
    document: dict[str, Any],
    network_snapshot_id: str,
    source_uri: str,
    expressway_toll_domain_id: str | None,
) -> dict[str, Any]:
    timestamp = document.get("osm3s", {}).get("timestamp_osm_base")
    if not timestamp:
        raise ValueError("Overpass osm3s.timestamp_osm_base is required")

    elements = document.get("elements")
    if not isinstance(elements, list):
        raise ValueError("Overpass elements array is required")
    nodes = {
        element["id"]: element
        for element in elements
        if element.get("type") == "node" and "lat" in element and "lon" in element
    }

    edges: list[dict[str, Any]] = []
    for way in elements:
        if way.get("type") != "way":
            continue
        tags = way.get("tags", {})
        highway = tags.get("highway")
        if highway not in ALLOWED_HIGHWAYS or not is_motor_accessible(tags):
            continue
        node_ids = way.get("nodes", [])
        if len(node_ids) < 2:
            continue
        missing = [node_id for node_id in node_ids if node_id not in nodes]
        if missing:
            raise ValueError(f"way {way['id']} is missing nodes: {missing}")

        forward, reverse = directions(tags)
        kind = edge_kind(highway)
        for segment_index, (first_id, second_id) in enumerate(zip(node_ids, node_ids[1:])):
            first = nodes[first_id]
            second = nodes[second_id]
            if forward:
                edges.append(
                    make_edge(
                        way["id"],
                        segment_index,
                        "forward",
                        first,
                        second,
                        kind,
                        expressway_toll_domain_id,
                    )
                )
            if reverse:
                edges.append(
                    make_edge(
                        way["id"],
                        segment_index,
                        "reverse",
                        second,
                        first,
                        kind,
                        expressway_toll_domain_id,
                    )
                )

    if not edges:
        raise ValueError("extract produced no motor-accessible road edges")

    return {
        "network_snapshot_id": network_snapshot_id,
        "provenance": {
            "source": "OpenStreetMap",
            "source_snapshot_at": timestamp,
            "source_uri": source_uri,
            "licence": "ODbL-1.0",
            "attribution": "© OpenStreetMap contributors",
        },
        "edges": edges,
    }


def main() -> None:
    arguments = parse_arguments()
    result = convert(
        load_document(
            arguments.input,
            arguments.input_format,
            arguments.source_snapshot_at,
        ),
        arguments.network_snapshot_id,
        arguments.source_uri,
        arguments.expressway_toll_domain_id,
    )
    write_json(result, arguments.output)


if __name__ == "__main__":
    main()
