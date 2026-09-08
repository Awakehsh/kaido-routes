#!/usr/bin/env python3
"""Fold a reviewed parking-area interior into the whole-network snapshot.

`build_shuto_network.py` deliberately drops rest-area service roads: one
reaching the graph is indistinguishable from a facility exit to the topology
gate, and a PA ramp read as an exit invents fare paths that do not exist. The
cost of that rule is that a parking area is a point you can be told about but
never driven to.

This step puts back exactly the geometry a reviewed parking area needs, and
nothing else. The interior arrives as its own `PARKING` edge kind carrying no
route membership, so it stays out of route sequences, out of facility
candidate matching, and out of every fare path — a router reaches it only by
asking for the parking area by name.

The snapshot keeps its `network_snapshot_id`: the interior way is the same
OSM extract's own content, filtered out at build time rather than absent from
it. The `database_id` gains the review's revision so the bundled graph is not
confused with the unrevised build.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any

PARKING_EDGE_KIND = "PARKING"


class ParkingAccessApplyError(RuntimeError):
    pass


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--network", required=True, type=Path)
    parser.add_argument("--review", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
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


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def apply_single_way_review(
    network: dict[str, Any],
    review: dict[str, Any],
) -> dict[str, Any]:
    if review.get("schema_version") != "1.0":
        raise ParkingAccessApplyError("unsupported parking access review schema")
    if review.get("network_snapshot_id") != network["network_snapshot_id"]:
        raise ParkingAccessApplyError(
            "review was taken against a different network snapshot"
        )

    coordinates = {
        node["node_id"]: (node["latitude"], node["longitude"])
        for node in network["nodes"]
    }
    incoming: dict[int, int] = {}
    outgoing: dict[int, int] = {}
    for edge in network["edges"]:
        outgoing[edge["from_node_id"]] = outgoing.get(edge["from_node_id"], 0) + 1
        incoming[edge["to_node_id"]] = incoming.get(edge["to_node_id"], 0) + 1
    existing_way_ids = {way["way_id"] for way in network["ways"]}
    existing_edge_ids = {edge["edge_id"] for edge in network["edges"]}
    parking_areas_by_id = {
        parking_area["parking_area_id"]: parking_area
        for parking_area in network["parking_areas"]
    }

    for reviewed in review["parking_areas"]:
        parking_area = parking_areas_by_id.get(reviewed["parking_area_id"])
        if parking_area is None:
            raise ParkingAccessApplyError(
                f"{reviewed['parking_area_id']} is not in the snapshot"
            )
        access_node_id = reviewed["access_node_id"]
        return_node_id = reviewed["return_node_id"]
        # The review is only meaningful against the dead ends it was taken
        # from: an access ramp nothing leaves, and a return ramp nothing
        # enters. If the snapshot has moved on, the pairing has to be
        # re-reviewed rather than stitched onto whatever is there now.
        if outgoing.get(access_node_id, 0) != 0:
            raise ParkingAccessApplyError(
                f"access node {access_node_id} is no longer a dead end"
            )
        if incoming.get(return_node_id, 0) != 0:
            raise ParkingAccessApplyError(
                f"return node {return_node_id} is no longer a dead start"
            )

        way = reviewed["interior_way"]
        if way["way_id"] in existing_way_ids:
            raise ParkingAccessApplyError(
                f"way {way['way_id']} is already in the snapshot"
            )
        if way["tags"].get("oneway") != "yes":
            raise ParkingAccessApplyError(
                f"way {way['way_id']} is not a one-way parking interior"
            )
        node_ids = way["node_ids"]
        if node_ids[0] != access_node_id or node_ids[-1] != return_node_id:
            raise ParkingAccessApplyError(
                f"way {way['way_id']} does not join the reviewed dead ends"
            )

        positions = {
            node["node_id"]: (node["latitude"], node["longitude"])
            for node in way["nodes"]
        }
        for node in way["nodes"]:
            node_id = node["node_id"]
            position = (node["latitude"], node["longitude"])
            existing = coordinates.get(node_id)
            if existing is None:
                network["nodes"].append(
                    {
                        "node_id": node_id,
                        "latitude": node["latitude"],
                        "longitude": node["longitude"],
                        "tags": {},
                    }
                )
                coordinates[node_id] = position
            elif haversine_meters(existing, position) > 1.0:
                raise ParkingAccessApplyError(
                    f"coordinate drift for OSM node {node_id}"
                )

        network["ways"].append(
            {
                "way_id": way["way_id"],
                "version": way["version"],
                "kind": PARKING_EDGE_KIND,
                "node_ids": node_ids,
                "route_memberships": [],
                "tags": way["tags"],
            }
        )
        existing_way_ids.add(way["way_id"])

        interior_edge_ids: list[str] = []
        for index in range(len(node_ids) - 1):
            edge_id = f"osm.{way['way_id']}.{index}.forward"
            if edge_id in existing_edge_ids:
                raise ParkingAccessApplyError(f"duplicate edge id {edge_id}")
            network["edges"].append(
                {
                    "edge_id": edge_id,
                    "from_node_id": node_ids[index],
                    "to_node_id": node_ids[index + 1],
                    "way_id": way["way_id"],
                    "segment_index": index,
                    "kind": PARKING_EDGE_KIND,
                    "direction": "forward",
                    "length_meters": round(
                        haversine_meters(
                            positions[node_ids[index]],
                            positions[node_ids[index + 1]],
                        ),
                        3,
                    ),
                    "route_memberships": [],
                }
            )
            existing_edge_ids.add(edge_id)
            interior_edge_ids.append(edge_id)

        parking_area["access_node_id"] = access_node_id
        parking_area["return_node_id"] = return_node_id
        parking_area["interior_edge_ids"] = interior_edge_ids
        parking_area["interior_distance_meters"] = round(
            sum(
                haversine_meters(
                    positions[node_ids[index]],
                    positions[node_ids[index + 1]],
                )
                for index in range(len(node_ids) - 1)
            ),
            3,
        )

    network["nodes"].sort(key=lambda node: node["node_id"])
    network["ways"].sort(key=lambda way: way["way_id"])
    network["edges"].sort(key=lambda edge: edge["edge_id"])
    return network


def apply_review(network: dict[str, Any], review: dict[str, Any]) -> dict[str, Any]:
    if review.get("schema_version") == "1.0":
        return apply_single_way_review(network, review)
    if review.get("schema_version") != "1.1":
        raise ParkingAccessApplyError("unsupported parking access review schema")
    if review.get("network_snapshot_id") != network["network_snapshot_id"]:
        raise ParkingAccessApplyError("review was taken against a different network snapshot")
    coordinates = {n["node_id"]: (n["latitude"], n["longitude"]) for n in network["nodes"]}
    ways = {w["way_id"]: w for w in network["ways"]}
    edges = {e["edge_id"]: e for e in network["edges"]}
    source_ways = {w["way_id"]: w for w in review["ways"]}
    parking = {p["parking_area_id"]: p for p in network["parking_areas"]}
    owners = {e: p["parking_area_id"] for p in network["parking_areas"] for e in p.get("interior_edge_ids", [])}

    def add_segment(way_id, index, kind, memberships):
        way = source_ways[way_id]
        tags = way["tags"]
        access = next((tags[k] for k in ("motorcar", "motor_vehicle", "vehicle", "access") if k in tags), None)
        if tags.get("oneway") != "yes" or access not in (None, "yes", "designated", "permissive", "customers"):
            raise ParkingAccessApplyError(f"way {way_id} lacks unrestricted forward motorcar access")
        allowed = ("service", "motorway_link") if kind == PARKING_EDGE_KIND else ("motorway",)
        if tags.get("highway") not in allowed or any(k.endswith(":conditional") for k in tags):
            raise ParkingAccessApplyError(f"way {way_id} is not a reviewed unconditional {kind} road")
        if not 0 <= index < len(way["node_ids"]) - 1:
            raise ParkingAccessApplyError("reviewed segment index is outside the source way")
        for node in way["nodes"]:
            position = (node["latitude"], node["longitude"])
            existing = coordinates.get(node["node_id"])
            if existing is not None and haversine_meters(existing, position) > 1:
                raise ParkingAccessApplyError(f"coordinate drift for OSM node {node['node_id']}")
            if existing is None:
                network["nodes"].append({"node_id": node["node_id"], "latitude": position[0], "longitude": position[1], "tags": {}})
                coordinates[node["node_id"]] = position
        if way_id not in ways:
            ways[way_id] = {"way_id": way_id, "version": way["version"], "kind": kind,
                            "node_ids": way["node_ids"], "route_memberships": memberships, "tags": tags}
        elif ways[way_id]["node_ids"] != way["node_ids"]:
            raise ParkingAccessApplyError(f"node sequence drift for OSM way {way_id}")
        a, b = way["node_ids"][index:index+2]
        edge_id = f"osm.{way_id}.{index}.forward"
        existing = edges.get(edge_id)
        if existing and (existing["from_node_id"], existing["to_node_id"]) != (a, b):
            raise ParkingAccessApplyError(f"edge identity drift for {edge_id}")
        edges[edge_id] = {"edge_id": edge_id, "from_node_id": a, "to_node_id": b, "way_id": way_id,
                          "segment_index": index, "kind": kind, "direction": "forward",
                          "length_meters": round(haversine_meters(coordinates[a], coordinates[b]), 3),
                          "route_memberships": memberships}
        return edges[edge_id]

    for connection in review.get("connecting_ways", []):
        way = source_ways[connection["way_id"]]
        if way["node_ids"][0] not in coordinates or way["node_ids"][-1] not in coordinates:
            raise ParkingAccessApplyError("connecting road must join existing snapshot nodes")
        if connection["kind"] != "MAINLINE" or way["tags"].get("ref") != connection["route_id"]:
            raise ParkingAccessApplyError("connecting road route identity disagrees with OSM")
        for index in range(len(way["node_ids"]) - 1):
            add_segment(way["way_id"], index, "MAINLINE", [{"route_id": connection["route_id"], "directions_ja": []}])

    for item in review["parking_areas"]:
        pid = item["parking_area_id"]
        if pid not in parking or item.get("verification_state") != "SOURCE_REVIEWED":
            raise ParkingAccessApplyError("unknown or unreviewed parking area")
        if item["access_node_id"] not in coordinates or item["return_node_id"] not in coordinates:
            raise ParkingAccessApplyError("parking path must join existing network nodes")
        cursor = item["access_node_id"]
        path = []
        for segment in item["interior_segments"]:
            edge = add_segment(segment["way_id"], segment["segment_index"], PARKING_EDGE_KIND, [])
            if edge["from_node_id"] != cursor:
                raise ParkingAccessApplyError("parking path is not directionally continuous")
            if edge["edge_id"] in owners and owners[edge["edge_id"]] != pid:
                raise ParkingAccessApplyError("a parking edge cannot bind two directional parking areas")
            owners[edge["edge_id"]] = pid
            path.append(edge["edge_id"])
            cursor = edge["to_node_id"]
        if not path or cursor != item["return_node_id"]:
            raise ParkingAccessApplyError("parking path does not reach the reviewed return")
        parking[pid].update(access_node_id=item["access_node_id"], return_node_id=cursor,
                            interior_edge_ids=path, interior_distance_meters=round(sum(edges[e]["length_meters"] for e in path), 3))
        if "coordinate" in item:
            parking[pid]["coordinate"] = item["coordinate"]
    for way in ways.values():
        members = [e for e in edges.values() if e["way_id"] == way["way_id"]]
        if members and all(e["kind"] == PARKING_EDGE_KIND for e in members):
            way["kind"] = PARKING_EDGE_KIND
            way["route_memberships"] = []
    network["nodes"].sort(key=lambda n: n["node_id"])
    network["ways"] = sorted(ways.values(), key=lambda w: w["way_id"])
    network["edges"] = sorted(edges.values(), key=lambda e: e["edge_id"])
    return network


def validate(network: dict[str, Any], review: dict[str, Any]) -> None:
    node_ids = {node["node_id"] for node in network["nodes"]}
    outgoing: dict[int, int] = {}
    incoming: dict[int, int] = {}
    for edge in network["edges"]:
        if edge["from_node_id"] not in node_ids:
            raise ParkingAccessApplyError(
                f"edge {edge['edge_id']} leaves an unknown node"
            )
        if edge["to_node_id"] not in node_ids:
            raise ParkingAccessApplyError(
                f"edge {edge['edge_id']} enters an unknown node"
            )
        outgoing[edge["from_node_id"]] = outgoing.get(edge["from_node_id"], 0) + 1
        incoming[edge["to_node_id"]] = incoming.get(edge["to_node_id"], 0) + 1
    edge_ids = [edge["edge_id"] for edge in network["edges"]]
    if len(edge_ids) != len(set(edge_ids)):
        raise ParkingAccessApplyError("duplicate directed edge IDs")
    parking_areas_by_id = {
        parking_area["parking_area_id"]: parking_area
        for parking_area in network["parking_areas"]
    }
    for reviewed in review["parking_areas"]:
        parking_area = parking_areas_by_id[reviewed["parking_area_id"]]
        # The point of the review: the parking area can now be driven into
        # and driven back out of.
        if outgoing.get(parking_area["access_node_id"], 0) < 1:
            raise ParkingAccessApplyError(
                f"{parking_area['parking_area_id']} still cannot be entered"
            )
        if incoming.get(parking_area["return_node_id"], 0) < 1:
            raise ParkingAccessApplyError(
                f"{parking_area['parking_area_id']} still cannot be left"
            )
    # A parking interior must never carry route membership: that is what
    # keeps it out of route sequences and fare paths.
    for edge in network["edges"]:
        if edge["kind"] == PARKING_EDGE_KIND and edge["route_memberships"]:
            raise ParkingAccessApplyError(
                f"parking edge {edge['edge_id']} carries route membership"
            )


def main() -> int:
    arguments = parse_arguments()
    network = json.loads(arguments.network.read_text())
    review = json.loads(arguments.review.read_text())
    try:
        if review.get("schema_version") == "1.1" and review.get("input_database_sha256") != sha256(arguments.network):
            raise ParkingAccessApplyError("review input database hash does not match")
        applied = apply_review(network, review)
        previous_review = network["sources"].get("parking_access_review")
        applied["sources"]["parking_access_review"] = {
            "review_id": review["review_id"],
            "checked_at": review["checked_at"],
            "sha256": sha256(arguments.review),
            "parking_area_count": sum(bool(p.get("interior_edge_ids")) for p in applied["parking_areas"]),
        }
        if review.get("schema_version") == "1.1":
            applied["sources"]["parking_access_review"]["previous_review"] = previous_review
        applied["database_id"] = (
            applied["database_id"].split("+", 1)[0]
            + "+pa-access-"
            + review["checked_at"].replace("-", "")
        )
        validate(applied, review)
    except ParkingAccessApplyError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    # Byte-identical serialisation to `build_shuto_network.py`, so applying
    # the review shows up as the edges it adds and nothing else.
    arguments.output.write_text(
        json.dumps(
            applied,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    print(
        f"wrote {arguments.output}: database_id={applied['database_id']} "
        f"edges={len(applied['edges'])}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
