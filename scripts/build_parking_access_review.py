#!/usr/bin/env python3
"""Read the parking-area access, interior and return geometry from OSM.

The whole-network builder keeps only ways that carry a Shuto route relation
plus their motorway links, because a rest-area service road that reaches the
graph looks exactly like a facility exit to the topology gate — Yoyogi PA's
up-side ramp once faked a 1.1 km Shinjuku-to-Yoyogi fare path that way. The
consequence is that every parking area in the snapshot is a labelled point
with no way to drive into it: the access ramp is present but dead-ends, and
the return ramp starts from nothing.

This review supplies the missing interior for the parking areas a route
experience actually stops at. It records the OSM way at the version and
timestamp it was read, so the overlay can be checked against the pinned
extract rather than trusted. Nothing here is synthesised: a parking area
whose interior OSM does not describe is reported and skipped, not invented.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

OSM_API = "https://api.openstreetmap.org/api/0.6"
ATTRIBUTION = "© OpenStreetMap contributors"
LICENCE = "ODbL-1.0"
LICENCE_URI = "https://opendatacommons.org/licenses/odbl/1-0/"

# A parking area whose interior is wanted, and the dead ends the snapshot
# already carries: the node an access ramp stops at, and the node a return
# ramp starts from. Both are read out of the snapshot, not asserted here —
# these ids only say which parking area the review is for.
REVIEWED_PARKING_AREA_IDS = ["shuto.pa.daikoku"]

# How far a candidate interior way may sit from the parking area's recorded
# point before the pairing is rejected as some other service road.
INTERIOR_PROXIMITY_LIMIT_METERS = 400.0


class ParkingAccessReviewError(RuntimeError):
    pass


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--network", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--read-at", required=True)
    parser.add_argument("--review-id", required=True)
    return parser.parse_args()


def haversine_meters(
    first: tuple[float, float],
    second: tuple[float, float],
) -> float:
    radius = 6_371_008.8
    lat1, lon1 = math.radians(first[0]), math.radians(first[1])
    lat2, lon2 = math.radians(second[0]), math.radians(second[1])
    dlat, dlon = lat2 - lat1, lon2 - lon1
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    )
    return 2 * radius * math.asin(min(1.0, math.sqrt(a)))


def fetch(path: str) -> dict[str, Any]:
    url = f"{OSM_API}/{path}"
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "kaido-routes parking-access review"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as error:
        raise ParkingAccessReviewError(f"OSM read failed for {url}: {error}")


def dead_ends(network: dict[str, Any]) -> tuple[set[int], set[int]]:
    """Nodes an edge only enters, and nodes an edge only leaves."""
    sources: set[int] = set()
    sinks: set[int] = set()
    outgoing: dict[int, int] = {}
    incoming: dict[int, int] = {}
    for edge in network["edges"]:
        outgoing[edge["from_node_id"]] = outgoing.get(edge["from_node_id"], 0) + 1
        incoming[edge["to_node_id"]] = incoming.get(edge["to_node_id"], 0) + 1
    for node_id in set(outgoing) | set(incoming):
        if incoming.get(node_id, 0) == 0:
            sources.add(node_id)
        if outgoing.get(node_id, 0) == 0:
            sinks.add(node_id)
    return sources, sinks


def review_parking_area(
    parking_area: dict[str, Any],
    coordinates: dict[int, tuple[float, float]],
    sources: set[int],
    sinks: set[int],
) -> dict[str, Any]:
    """Pair one dead-ended access ramp with one dead-started return ramp.

    The pairing is the OSM way that joins them: a `highway=service` way whose
    first node is where an access ramp stops and whose last node is where a
    return ramp starts. A tertiary or named way joining the same nodes is a
    surface interchange, not a parking area, and is rejected.
    """
    point = (
        parking_area["coordinate"]["latitude"],
        parking_area["coordinate"]["longitude"],
    )
    nearby_sinks = sorted(
        (
            node_id
            for node_id in sinks
            if node_id in coordinates
            and haversine_meters(coordinates[node_id], point)
            <= INTERIOR_PROXIMITY_LIMIT_METERS
        ),
        key=lambda node_id: haversine_meters(coordinates[node_id], point),
    )
    for access_node_id in nearby_sinks:
        parents = fetch(f"node/{access_node_id}/ways.json")
        for way in parents.get("elements", []):
            tags = way.get("tags", {})
            if tags.get("highway") != "service":
                continue
            if way["nodes"][0] != access_node_id:
                continue
            return_node_id = way["nodes"][-1]
            if return_node_id not in sources:
                continue
            full = fetch(f"way/{way['id']}/full.json")
            node_positions = {
                element["id"]: (element["lat"], element["lon"])
                for element in full["elements"]
                if element["type"] == "node"
            }
            detail = next(
                element
                for element in full["elements"]
                if element["type"] == "way"
            )
            closest = min(
                haversine_meters(node_positions[node_id], point)
                for node_id in detail["nodes"]
            )
            if closest > INTERIOR_PROXIMITY_LIMIT_METERS:
                continue
            return {
                "parking_area_id": parking_area["parking_area_id"],
                "access_node_id": access_node_id,
                "return_node_id": return_node_id,
                "closest_approach_meters": round(closest, 3),
                "interior_way": {
                    "way_id": detail["id"],
                    "version": detail["version"],
                    "timestamp": detail["timestamp"],
                    "tags": detail["tags"],
                    "node_ids": detail["nodes"],
                    "nodes": [
                        {
                            "node_id": node_id,
                            "latitude": node_positions[node_id][0],
                            "longitude": node_positions[node_id][1],
                        }
                        for node_id in detail["nodes"]
                    ],
                },
            }
    raise ParkingAccessReviewError(
        "no service way joins a dead-ended access ramp to a return ramp for "
        + parking_area["parking_area_id"]
    )


def build(arguments: argparse.Namespace) -> dict[str, Any]:
    network = json.loads(arguments.network.read_text())
    coordinates = {
        node["node_id"]: (node["latitude"], node["longitude"])
        for node in network["nodes"]
    }
    sources, sinks = dead_ends(network)
    parking_areas_by_id = {
        parking_area["parking_area_id"]: parking_area
        for parking_area in network["parking_areas"]
    }
    reviewed = []
    for parking_area_id in REVIEWED_PARKING_AREA_IDS:
        parking_area = parking_areas_by_id.get(parking_area_id)
        if parking_area is None:
            raise ParkingAccessReviewError(
                f"{parking_area_id} is not in the network snapshot"
            )
        reviewed.append(
            review_parking_area(parking_area, coordinates, sources, sinks)
        )
    return {
        "schema_version": "1.0",
        "review_id": arguments.review_id,
        "checked_at": arguments.read_at[:10],
        "network_snapshot_id": network["network_snapshot_id"],
        "source": {
            "api": OSM_API,
            "read_at": arguments.read_at,
            "attribution": ATTRIBUTION,
            "licence": LICENCE,
            "licence_uri": LICENCE_URI,
        },
        "parking_areas": reviewed,
    }


def main() -> int:
    arguments = parse_arguments()
    try:
        review = build(arguments)
    except ParkingAccessReviewError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    arguments.output.write_text(
        json.dumps(review, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    )
    print(
        f"wrote {arguments.output} with "
        f"{len(review['parking_areas'])} reviewed parking areas"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
