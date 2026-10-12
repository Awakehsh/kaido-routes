#!/usr/bin/env python3
"""Read the OSM facts a whole-network topology review relies on.

Two kinds of graph defect come out of the builder's rules rather than out of
OSM itself. A carriageway section that editors drew on ways outside the route
relation is either longer than the 1 km gap connector reaches, or feeds a
carriageway the connector never searches from: Route 1 Haneda southbound
stopped after its 2025-10-29 switch, and K3 began from nothing at Honmoku
JCT. And an interchange whose exit ramp and entrance ramp meet the same
surface road is drawn as one continuous `motorway_link` chain, so the graph
lets a drive or a fare path leave the expressway and come straight back on.

This step records the facts the reviewer names, and selects nothing itself:
each restored or removed way at the version current at the pinned extract's
timestamp, with its nodes, and for each surface crossing the surface roads
OSM attaches to the crossing nodes as read now. `apply_topology_review.py`
checks the graph-side claims.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

OSM_API = "https://api.openstreetmap.org/api/0.6"
ATTRIBUTION = "© OpenStreetMap contributors"
LICENCE = "ODbL-1.0"
LICENCE_URI = "https://opendatacommons.org/licenses/odbl/1-0/"
EXPRESSWAY_HIGHWAYS = {"motorway", "motorway_link", "construction"}


class TopologyReviewError(RuntimeError):
    pass


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--network", required=True, type=Path)
    parser.add_argument(
        "--selection",
        required=True,
        type=Path,
        help="Review naming the ways and crossings; its OSM facts are refreshed.",
    )
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--read-at", required=True)
    parser.add_argument("--review-id", required=True)
    return parser.parse_args()


def fetch(path: str) -> dict[str, Any]:
    url = f"{OSM_API}/{path}"
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "kaido-routes topology review"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as error:
        raise TopologyReviewError(f"OSM read failed for {url}: {error}")


def version_at(kind: str, element_id: int, timestamp: str) -> dict[str, Any]:
    """The element's last version at or before `timestamp`; ISO-8601 UTC
    strings compare in time order."""
    history = fetch(f"{kind}/{element_id}/history.json")["elements"]
    current = [element for element in history if element["timestamp"] <= timestamp]
    if not current:
        raise TopologyReviewError(f"{kind} {element_id} did not exist at {timestamp}")
    element = current[-1]
    if element.get("visible") is False:
        raise TopologyReviewError(f"{kind} {element_id} was deleted at {timestamp}")
    return element


def read_way(way_id: int, timestamp: str) -> dict[str, Any]:
    way = version_at("way", way_id, timestamp)
    nodes = []
    for node_id in way["nodes"]:
        node = version_at("node", node_id, timestamp)
        nodes.append(
            {
                "node_id": node_id,
                "latitude": node["lat"],
                "longitude": node["lon"],
                "version": node["version"],
                "timestamp": node["timestamp"],
            }
        )
    return {
        "way_id": way_id,
        "version": way["version"],
        "timestamp": way["timestamp"],
        "tags": way.get("tags", {}),
        "node_ids": way["nodes"],
        "nodes": nodes,
    }


def surface_ways(node_id: int) -> list[dict[str, Any]]:
    """The non-expressway roads OSM attaches to a node, as read now."""
    found = []
    for way in fetch(f"node/{node_id}/ways.json")["elements"]:
        tags = way.get("tags", {})
        highway = tags.get("highway")
        if highway is None or highway in EXPRESSWAY_HIGHWAYS:
            continue
        found.append(
            {
                "way_id": way["id"],
                "version": way["version"],
                "timestamp": way["timestamp"],
                "highway": highway,
                "name": tags.get("name"),
            }
        )
    if not found:
        raise TopologyReviewError(f"node {node_id} joins no surface road")
    return sorted(found, key=lambda way: way["way_id"])


def build(arguments: argparse.Namespace) -> dict[str, Any]:
    network_bytes = arguments.network.read_bytes()
    network = json.loads(network_bytes)
    review = json.loads(arguments.selection.read_text())
    if review.get("schema_version") != "1.0":
        raise TopologyReviewError("unsupported topology review schema")
    extract_at = network["sources"]["osm"]["source_snapshot_at"]
    way_ids = [
        way_id for chain in review["restored_chains"] for way_id in chain["way_ids"]
    ] + [item["way_id"] for item in review["removed_ways"]]
    if len(set(way_ids)) != len(way_ids):
        raise TopologyReviewError("a way is named twice")
    for crossing in review["cut_crossings"]:
        crossing["surface_ways"] = {
            str(node_id): surface_ways(node_id)
            for node_id in crossing["crossing_node_ids"]
        }
    review.update(
        review_id=arguments.review_id,
        checked_at=arguments.read_at[:10],
        network_snapshot_id=network["network_snapshot_id"],
        input_database_id=network["database_id"],
        input_database_sha256=hashlib.sha256(network_bytes).hexdigest(),
        ways=[read_way(way_id, extract_at) for way_id in sorted(way_ids)],
    )
    review["source"] = {
        **review.get("source", {}),
        "api": OSM_API,
        "read_at": arguments.read_at,
        "versions_current_at": extract_at,
        "attribution": ATTRIBUTION,
        "licence": LICENCE,
        "licence_uri": LICENCE_URI,
    }
    return review


def main() -> int:
    arguments = parse_arguments()
    try:
        review = build(arguments)
    except TopologyReviewError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    arguments.output.write_text(
        json.dumps(review, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        f"wrote {arguments.output} with {len(review['ways'])} ways and "
        f"{len(review['cut_crossings'])} surface crossings"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
