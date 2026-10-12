#!/usr/bin/env python3
"""Re-point reviewed facility ramp candidates in the whole-network snapshot.

`build_shuto_network.py` binds each official facility to the `LINK` edges
within 750 m that its ramp-topology gate accepts. Where the operator's real
ramp is itself a route-relation member (typed `MAINLINE`), where the only
links nearby belong to the opposite role, where a rest-area ramp sits closer
than the toll plaza, or where a split interchange keeps its ramps farther
than the radius, that binding lands on the wrong ramp and the facility pairs
with nothing but itself.

This step replaces exactly the candidate lists a source review names, with
distances measured the way the builder measures them, and refuses the result
unless every patched facility then pairs with the network the review says it
should. Graph geometry is untouched: only which ramp edge a toll point is
bound to changes, so `network_snapshot_id` stays and `database_id` gains the
review's revision.

Schema 1.1 reviews every facility at once. A candidate the facility already
had keeps the distance the builder measured, so re-reviewing a binding that
was right changes nothing; a re-pointed candidate is measured to its edge.
A candidate whose OSM ramp carries another route's relation membership (one
interchange the operator lists under two routes, or a ramp OSM files under
the neighbouring route) binds only when the patch names it under
`cross_route` with a reason. A review may also add a facility the catalog
missed, and re-point a junction's OSM nodes, recomputing the junction
coordinate as the builder does: the mean of its nodes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from collections import deque
from pathlib import Path
from typing import Any

PARKING_EDGE_KIND = "PARKING"


class FacilityCandidatePatchError(RuntimeError):
    pass


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--network", required=True, type=Path)
    parser.add_argument("--review", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def distance_to_segment(
    point: tuple[float, float],
    first: tuple[float, float],
    second: tuple[float, float],
) -> float:
    """The builder's planar point-to-segment distance, so patched candidates
    carry distances comparable to built ones."""
    latitude_scale = 111_132.0
    longitude_scale = 111_320.0 * math.cos(math.radians(point[0]))
    px = (point[1] - first[1]) * longitude_scale
    py = (point[0] - first[0]) * latitude_scale
    sx = (second[1] - first[1]) * longitude_scale
    sy = (second[0] - first[0]) * latitude_scale
    denominator = sx * sx + sy * sy
    if denominator == 0:
        return math.hypot(px, py)
    fraction = max(0.0, min(1.0, (px * sx + py * sy) / denominator))
    return math.hypot(px - fraction * sx, py - fraction * sy)


FACILITY_FIELDS = {
    "coordinate",
    "entrance_directions",
    "etc_only",
    "exit_directions",
    "facility_id",
    "name_ja",
    "official_page_route_slug",
    "official_page_url",
    "operational_status",
    "reading_ja",
    "route_id",
    "source_sha256",
}


def add_facilities(applied: dict[str, Any], additions: list[dict[str, Any]]) -> None:
    """Insert reviewed facilities after the last facility of their route, with
    no ramp bound until a patch binds one."""
    routes = {route["route_id"] for route in applied["routes"]}
    facilities = applied["directional_facilities"]
    for addition in additions:
        record = {key: addition[key] for key in FACILITY_FIELDS if key in addition}
        if set(record) != FACILITY_FIELDS or not addition.get("evidence"):
            raise FacilityCandidatePatchError(
                f"added facility {addition.get('facility_id')} is incomplete or carries no evidence"
            )
        if any(facility["facility_id"] == record["facility_id"] for facility in facilities):
            raise FacilityCandidatePatchError(f"facility {record['facility_id']} already exists")
        if record["route_id"] not in routes:
            raise FacilityCandidatePatchError(f"unknown route {record['route_id']}")
        record.update(
            entry_edge_candidates=[],
            exit_edge_candidates=[],
            geometry_match_state="UNRESOLVED",
        )
        position = max(
            (index for index, facility in enumerate(facilities)
             if facility["route_id"] == record["route_id"]),
            default=len(facilities) - 1,
        )
        facilities.insert(position + 1, record)


def patch_junctions(applied: dict[str, Any], patches: list[dict[str, Any]]) -> None:
    coordinates = {
        node["node_id"]: (node["latitude"], node["longitude"])
        for node in applied["nodes"]
    }
    junctions = {junction["junction_id"]: junction for junction in applied["junctions"]}
    for patch in patches:
        junction = junctions.get(patch["junction_id"])
        if junction is None:
            raise FacilityCandidatePatchError(f"unknown junction {patch['junction_id']}")
        if not patch.get("evidence") or not patch.get("reason"):
            raise FacilityCandidatePatchError(
                f"junction patch for {patch['junction_id']} carries no reason or evidence"
            )
        node_ids = sorted(set(patch["osm_node_ids"]))
        if not node_ids or any(node_id not in coordinates for node_id in node_ids):
            raise FacilityCandidatePatchError(
                f"junction {patch['junction_id']} names a node outside the snapshot"
            )
        junction["osm_node_ids"] = node_ids
        junction["coordinate"] = {
            "latitude": sum(coordinates[node_id][0] for node_id in node_ids) / len(node_ids),
            "longitude": sum(coordinates[node_id][1] for node_id in node_ids) / len(node_ids),
        }


def apply_review(network: dict[str, Any], review: dict[str, Any]) -> dict[str, Any]:
    schema = review.get("schema_version")
    if schema not in ("1.0", "1.1"):
        raise FacilityCandidatePatchError("unsupported facility candidate patch schema")
    if review.get("network_snapshot_id") != network["network_snapshot_id"]:
        raise FacilityCandidatePatchError(
            "review was taken against a different network snapshot"
        )
    coordinates = {
        node["node_id"]: (node["latitude"], node["longitude"])
        for node in network["nodes"]
    }
    edges = {edge["edge_id"]: edge for edge in network["edges"]}
    facilities = {
        facility["facility_id"]: facility
        for facility in network["directional_facilities"]
    }
    applied = json.loads(json.dumps(network))
    if schema == "1.1":
        add_facilities(applied, review.get("added_facilities", []))
        patch_junctions(applied, review.get("junction_patches", []))
    patched = {
        facility["facility_id"]: facility
        for facility in applied["directional_facilities"]
    }
    seen: set[str] = set()
    for patch in review["patches"]:
        facility_id = patch["facility_id"]
        if facility_id in seen:
            raise FacilityCandidatePatchError(f"facility {facility_id} patched twice")
        seen.add(facility_id)
        facility = patched.get(facility_id)
        if facility is None:
            raise FacilityCandidatePatchError(f"unknown facility {facility_id}")
        if not patch.get("evidence"):
            raise FacilityCandidatePatchError(f"patch for {facility_id} carries no evidence")
        for role, key in (("entry", "entry_edge_candidates"), ("exit", "exit_edge_candidates")):
            edge_ids = patch.get(key)
            if edge_ids is None:
                continue
            measured_before = {
                candidate["edge_id"]: candidate["distance_meters"]
                for candidate in facility[key]
            }
            cross_route = patch.get("cross_route", {}) if schema == "1.1" else {}
            if len(set(edge_ids)) != len(edge_ids):
                raise FacilityCandidatePatchError(f"{facility_id} repeats an {role} edge")
            directions = facility["entrance_directions" if role == "entry" else "exit_directions"]
            if edge_ids and not directions:
                raise FacilityCandidatePatchError(
                    f"{facility_id} has no official {role} direction to bind"
                )
            candidates = []
            for edge_id in edge_ids:
                edge = edges.get(edge_id)
                if edge is None:
                    raise FacilityCandidatePatchError(f"unknown edge {edge_id}")
                if edge["kind"] == PARKING_EDGE_KIND:
                    raise FacilityCandidatePatchError(
                        f"{edge_id} is a parking edge and cannot bind a toll point"
                    )
                if not cross_route.get(edge_id) and not any(
                    membership["route_id"] == facility["route_id"]
                    for membership in edge["route_memberships"]
                ):
                    raise FacilityCandidatePatchError(
                        f"{edge_id} does not belong to route {facility['route_id']}"
                    )
                if schema == "1.1" and edge_id in measured_before:
                    distance = measured_before[edge_id]
                else:
                    distance = distance_to_segment(
                        (facility["coordinate"]["latitude"], facility["coordinate"]["longitude"]),
                        coordinates[edge["from_node_id"]],
                        coordinates[edge["to_node_id"]],
                    )
                candidates.append(
                    {"distance_meters": round(distance, 3), "edge_id": edge_id}
                )
            candidates.sort(key=lambda item: (item["distance_meters"], item["edge_id"]))
            facility[key] = candidates
        # A facility left without any ramp is unresolved, like the built
        # facilities the builder could not bind; the app then offers it
        # neither as an entrance nor as an exit.
        if not facility["entry_edge_candidates"] and not facility["exit_edge_candidates"]:
            facility["geometry_match_state"] = "UNRESOLVED"
        elif schema == "1.1":
            facility["geometry_match_state"] = "CANDIDATE_MATCHED"
    return applied


def pairing_counts(network: dict[str, Any]) -> dict[str, dict[str, int]]:
    """Per facility: differently named entrances some directed non-parking
    path leads from to it, and differently named exits it reaches — the
    planner's exact reachability rule."""
    edges = {edge["edge_id"]: edge for edge in network["edges"]}
    outgoing: dict[int, list[int]] = {}
    for edge in network["edges"]:
        if edge["kind"] == PARKING_EDGE_KIND:
            continue
        outgoing.setdefault(edge["from_node_id"], []).append(edge["to_node_id"])
    facilities = network["directional_facilities"]
    exit_nodes = {
        facility["facility_id"]: {
            edges[candidate["edge_id"]]["from_node_id"]
            for candidate in facility["exit_edge_candidates"]
            if candidate["edge_id"] in edges
        }
        for facility in facilities
        if facility["exit_directions"]
    }
    counts = {
        facility["facility_id"]: {"reaching_entrances": 0, "reachable_exits": 0}
        for facility in facilities
    }
    for entrance in facilities:
        if not entrance["entrance_directions"]:
            continue
        reached: set[int] = set()
        frontier = deque(
            edges[candidate["edge_id"]]["to_node_id"]
            for candidate in entrance["entry_edge_candidates"]
            if candidate["edge_id"] in edges
        )
        reached.update(frontier)
        while frontier:
            node = frontier.popleft()
            for successor in outgoing.get(node, ()):
                if successor not in reached:
                    reached.add(successor)
                    frontier.append(successor)
        names = {entrance["name_ja"]}
        for exit_id, nodes in exit_nodes.items():
            exit_facility = next(f for f in facilities if f["facility_id"] == exit_id)
            if exit_facility["name_ja"] in names:
                continue
            if reached & nodes:
                counts[entrance["facility_id"]]["reachable_exits"] += 1
                counts[exit_id]["reaching_entrances"] += 1
    return counts


def validate(network: dict[str, Any], review: dict[str, Any]) -> dict[str, dict[str, int]]:
    counts = pairing_counts(network)
    for patch in review["patches"]:
        expect = patch["expect"]
        actual = counts[patch["facility_id"]]
        for key in ("reaching_entrances", "reachable_exits"):
            if actual[key] < expect[key]:
                raise FacilityCandidatePatchError(
                    f"{patch['facility_id']} {key}={actual[key]} below the reviewed "
                    f"minimum {expect[key]}"
                )
    return counts


def main() -> int:
    arguments = parse_arguments()
    network = json.loads(arguments.network.read_text())
    review = json.loads(arguments.review.read_text())
    try:
        if review.get("input_database_sha256") != sha256(arguments.network):
            raise FacilityCandidatePatchError("review input database hash does not match")
        applied = apply_review(network, review)
        previous_patch = network["sources"].get("facility_candidate_patch")
        applied["sources"]["facility_candidate_patch"] = {
            "review_id": review["review_id"],
            "checked_at": review["checked_at"],
            "sha256": sha256(arguments.review),
            "patched_facility_count": len(review["patches"]),
        }
        if review["schema_version"] == "1.1":
            applied["sources"]["facility_candidate_patch"].update(
                added_facility_count=len(review.get("added_facilities", [])),
                patched_junction_count=len(review.get("junction_patches", [])),
                previous_patch=previous_patch,
            )
        applied["database_id"] = (
            applied["database_id"]
            + "+facility-candidates-"
            + review["checked_at"].replace("-", "")
        )
        counts = validate(applied, review)
    except FacilityCandidatePatchError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    # Byte-identical serialisation to `build_shuto_network.py`, so applying
    # the review shows up as the candidates it re-points and nothing else.
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
    print(f"wrote {arguments.output}: database_id={applied['database_id']}")
    for patch in review["patches"]:
        actual = counts[patch["facility_id"]]
        print(
            f"  {patch['facility_id']}: reaching_entrances={actual['reaching_entrances']} "
            f"reachable_exits={actual['reachable_exits']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
