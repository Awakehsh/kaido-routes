#!/usr/bin/env python3
"""Apply a reviewed topology repair to the whole-network snapshot.

Three repairs, each named exactly by the review:

- A restored chain of directed motorway ways carrying the route's `ref`
  joins the graph at both ends and closes a carriageway dead end or dead
  start. It enters the graph as the builder builds a relation member:
  `MAINLINE` edges with the route's membership.
- A removed way is a `highway=construction` structure the builder admitted as
  motorway, once the review shows it out of service. Its edges leave the
  graph, and so do nodes no remaining way uses.
- A cut crossing removes the `motorway_link` segments where an interchange's
  exit ramp meets a surface road and the entrance ramp leaves it. OSM draws
  them as one chain; driving it means leaving the toll road and coming back
  on, so neither a route nor a fare path may use it.

Facility candidates bound to removed edges are unbound, and only when the
review lists exactly those bindings. The step refuses a review taken against
another snapshot, a way version that postdates the pinned extract, a restored
chain that closes no dead end or dead start, and a cut that leaves its exit-to-entrance
continuation drivable. Every other edge keeps its identity, so reviewed
movement bindings stay valid.
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

EARTH_RADIUS_METERS = 6_371_000.0
FORBIDDEN_ACCESS = {"no", "private"}
SIDES = {"entry": "entry_edge_candidates", "exit": "exit_edge_candidates"}


class TopologyApplyError(RuntimeError):
    pass


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--network", required=True, type=Path)
    parser.add_argument("--review", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def haversine_meters(
    first: tuple[float, float],
    second: tuple[float, float],
) -> float:
    """The builder's edge length, so restored edges measure like built ones."""
    latitude1, longitude1 = map(math.radians, first)
    latitude2, longitude2 = map(math.radians, second)
    value = (
        math.sin((latitude2 - latitude1) / 2) ** 2
        + math.cos(latitude1)
        * math.cos(latitude2)
        * math.sin((longitude2 - longitude1) / 2) ** 2
    )
    return 2 * EARTH_RADIUS_METERS * math.asin(min(1.0, math.sqrt(value)))


def link_path_exists(
    edges: list[dict[str, Any]],
    link_way_ids: set[int],
    start_edge_id: str,
    end_edge_id: str,
) -> bool:
    """Does a chain of link edges lead from `start_edge_id` onto `end_edge_id`?"""
    by_id = {edge["edge_id"]: edge for edge in edges}
    if start_edge_id not in by_id or end_edge_id not in by_id:
        return False
    outgoing: dict[int, list[dict[str, Any]]] = {}
    for edge in edges:
        outgoing.setdefault(edge["from_node_id"], []).append(edge)
    seen = {start_edge_id}
    frontier = deque([by_id[start_edge_id]])
    while frontier:
        edge = frontier.popleft()
        for successor in outgoing.get(edge["to_node_id"], ()):
            if successor["edge_id"] == end_edge_id:
                return True
            if successor["way_id"] in link_way_ids and successor["edge_id"] not in seen:
                seen.add(successor["edge_id"])
                frontier.append(successor)
    return False


def apply_review(network: dict[str, Any], review: dict[str, Any]) -> dict[str, Any]:
    if review.get("schema_version") != "1.0":
        raise TopologyApplyError("unsupported topology review schema")
    if review.get("network_snapshot_id") != network["network_snapshot_id"]:
        raise TopologyApplyError("review was taken against a different network snapshot")
    extract_at = network["sources"]["osm"]["source_snapshot_at"]
    if review["source"].get("versions_current_at") != extract_at:
        raise TopologyApplyError("review read OSM at a different extract time")
    records = {way["way_id"]: way for way in review["ways"]}
    named = [
        way_id for chain in review["restored_chains"] for way_id in chain["way_ids"]
    ] + [item["way_id"] for item in review["removed_ways"]]
    if sorted(named) != sorted(records):
        raise TopologyApplyError("review way records do not match the named ways")
    for item in review["restored_chains"] + review["removed_ways"] + review["cut_crossings"]:
        if not item.get("reason"):
            raise TopologyApplyError("every restored chain, removed way and cut crossing carries a reason")
    for way in records.values():
        if way["timestamp"] > extract_at or any(
            node["timestamp"] > extract_at for node in way["nodes"]
        ):
            raise TopologyApplyError(f"way {way['way_id']} postdates the pinned extract")

    applied = json.loads(json.dumps(network))
    coordinates = {
        node["node_id"]: (node["latitude"], node["longitude"])
        for node in applied["nodes"]
    }
    ways = {way["way_id"]: way for way in applied["ways"]}
    routes = {route["route_id"]: route for route in applied["routes"]}
    edges_by_id = {edge["edge_id"]: edge for edge in applied["edges"]}
    link_way_ids = {
        way_id for way_id, way in ways.items() if way["tags"].get("highway") == "motorway_link"
    }

    removed_edge_ids: set[str] = set()
    for item in review["removed_ways"]:
        way_id = item["way_id"]
        way = ways.get(way_id)
        record = records[way_id]
        if way is None:
            raise TopologyApplyError(f"way {way_id} is not in the snapshot")
        if (
            record["tags"].get("highway") != "construction"
            or way["tags"].get("kaido:source_highway") != "construction"
        ):
            raise TopologyApplyError(
                f"way {way_id} is not a construction structure the builder admitted"
            )
        if way["version"] != record["version"] or way["node_ids"] != record["node_ids"]:
            raise TopologyApplyError(f"way {way_id} differs from the reviewed version")
        removed_edge_ids.update(
            edge_id for edge_id, edge in edges_by_id.items() if edge["way_id"] == way_id
        )
        del ways[way_id]

    for crossing in review["cut_crossings"]:
        crossing_nodes = set(crossing["crossing_node_ids"])
        if set(map(int, crossing["surface_ways"])) != crossing_nodes or not all(
            crossing["surface_ways"].values()
        ):
            raise TopologyApplyError(
                f"{crossing['interchange']}: every crossing node needs its surface road"
            )
        cut = []
        for edge_id in crossing["removed_edge_ids"]:
            edge = edges_by_id.get(edge_id)
            if edge is None or edge["way_id"] not in link_way_ids:
                raise TopologyApplyError(f"{edge_id} is not a motorway_link edge in the snapshot")
            cut.append(edge)
        # A removed segment touches a crossing node, or lies on the removed
        # run between two of them: the stretch drawn along the surface road.
        after_crossing = {
            edge["edge_id"] for edge in cut if edge["from_node_id"] in crossing_nodes
        }
        before_crossing = {
            edge["edge_id"] for edge in cut if edge["to_node_id"] in crossing_nodes
        }
        changed = True
        while changed:
            changed = False
            for edge in cut:
                if edge["edge_id"] not in after_crossing and any(
                    other["to_node_id"] == edge["from_node_id"]
                    for other in cut
                    if other["edge_id"] in after_crossing
                ):
                    after_crossing.add(edge["edge_id"])
                    changed = True
                if edge["edge_id"] not in before_crossing and any(
                    other["from_node_id"] == edge["to_node_id"]
                    for other in cut
                    if other["edge_id"] in before_crossing
                ):
                    before_crossing.add(edge["edge_id"])
                    changed = True
        for edge in cut:
            touches = {edge["from_node_id"], edge["to_node_id"]} & crossing_nodes
            between = edge["edge_id"] in after_crossing and edge["edge_id"] in before_crossing
            if not touches and not between:
                raise TopologyApplyError(
                    f"{edge['edge_id']} lies outside the reviewed surface crossing"
                )
        for start_edge_id, end_edge_id in crossing["continuations"]:
            if not link_path_exists(applied["edges"], link_way_ids, start_edge_id, end_edge_id):
                raise TopologyApplyError(
                    f"{crossing['interchange']}: {start_edge_id} does not reach {end_edge_id}"
                )
        removed_edge_ids.update(crossing["removed_edge_ids"])

    bound = {
        (facility["facility_id"], side, candidate["edge_id"])
        for facility in applied["directional_facilities"]
        for side, key in SIDES.items()
        for candidate in facility[key]
        if candidate["edge_id"] in removed_edge_ids
    }
    listed = {
        (item["facility_id"], item["side"], item["edge_id"])
        for item in review["unbound_candidates"]
    }
    if bound != listed:
        raise TopologyApplyError(
            "unbound candidates differ from the bindings on removed edges: "
            + ", ".join(sorted(map(str, bound ^ listed)))
        )
    for facility in applied["directional_facilities"]:
        for key in SIDES.values():
            facility[key] = [
                candidate
                for candidate in facility[key]
                if candidate["edge_id"] not in removed_edge_ids
            ]
    parking_edge_ids = {
        edge_id
        for parking_area in applied["parking_areas"]
        for edge_id in parking_area.get("interior_edge_ids") or []
    }
    if removed_edge_ids & parking_edge_ids:
        raise TopologyApplyError("a removal touches a parking-area interior")
    edges = [edge for edge in applied["edges"] if edge["edge_id"] not in removed_edge_ids]

    for crossing in review["cut_crossings"]:
        for start_edge_id, end_edge_id in crossing["continuations"]:
            if link_path_exists(edges, link_way_ids, start_edge_id, end_edge_id):
                raise TopologyApplyError(
                    f"{crossing['interchange']}: {start_edge_id} still reaches {end_edge_id}"
                )

    outgoing: dict[int, int] = {}
    incoming: dict[int, int] = {}
    for edge in edges:
        outgoing[edge["from_node_id"]] = outgoing.get(edge["from_node_id"], 0) + 1
        incoming[edge["to_node_id"]] = incoming.get(edge["to_node_id"], 0) + 1
    closures = []
    for restored in review["restored_chains"]:
        chain = [records[way_id] for way_id in restored["way_ids"]]
        route = routes.get(restored["route_id"])
        if route is None:
            raise TopologyApplyError(f"unknown route {restored['route_id']}")
        for before, after in zip(chain, chain[1:]):
            if before["node_ids"][-1] != after["node_ids"][0]:
                raise TopologyApplyError(
                    f"way {after['way_id']} does not continue way {before['way_id']}"
                )
        start_node = chain[0]["node_ids"][0]
        end_node = chain[-1]["node_ids"][-1]
        # The point of a restoration: the chain joins the graph at both ends
        # and closes a carriageway dead end or dead start the graph has.
        if incoming.get(start_node, 0) == 0 or outgoing.get(end_node, 0) == 0:
            raise TopologyApplyError(
                f"chain {restored['way_ids']} does not join the graph at both ends"
            )
        if outgoing.get(start_node, 0) != 0 and incoming.get(end_node, 0) != 0:
            raise TopologyApplyError(
                f"chain {restored['way_ids']} closes no carriageway dead end or dead start"
            )
        closures.append((start_node, end_node))
        for record in chain:
            restore_way(applied, ways, edges, coordinates, record, route)
    for start_node, end_node in closures:
        if not reaches(edges, start_node, end_node):
            raise TopologyApplyError(f"node {end_node} is still unreachable from {start_node}")

    used_node_ids = {node_id for way in ways.values() for node_id in way["node_ids"]}
    referenced = {
        node_id for junction in applied["junctions"] for node_id in junction["osm_node_ids"]
    } | {
        parking_area[key]
        for parking_area in applied["parking_areas"]
        for key in ("access_node_id", "return_node_id")
        if parking_area.get(key) is not None
    }
    if referenced - used_node_ids:
        raise TopologyApplyError("a removal orphans a junction or parking-area node")
    applied["nodes"] = sorted(
        (node for node in applied["nodes"] if node["node_id"] in used_node_ids),
        key=lambda node: node["node_id"],
    )
    applied["ways"] = sorted(ways.values(), key=lambda way: way["way_id"])
    applied["edges"] = sorted(edges, key=lambda edge: edge["edge_id"])
    return applied


def restore_way(
    applied: dict[str, Any],
    ways: dict[int, dict[str, Any]],
    edges: list[dict[str, Any]],
    coordinates: dict[int, tuple[float, float]],
    record: dict[str, Any],
    route: dict[str, Any],
) -> None:
    """Add one reviewed OSM way as the builder adds a relation member."""
    tags = record["tags"]
    way_id = record["way_id"]
    if way_id in ways:
        raise TopologyApplyError(f"way {way_id} is already in the snapshot")
    if tags.get("highway") != "motorway" or tags.get("oneway") != "yes":
        raise TopologyApplyError(f"way {way_id} is not a one-way motorway")
    if tags.get("ref") != route["osm_ref"]:
        raise TopologyApplyError(f"way {way_id} does not carry route ref {route['osm_ref']}")
    if any(
        tags.get(key) in FORBIDDEN_ACCESS for key in ("motorcar", "motor_vehicle", "access")
    ) or any(key.endswith(":conditional") for key in tags):
        raise TopologyApplyError(f"way {way_id} restricts motorcar access")
    positions = {
        node["node_id"]: (node["latitude"], node["longitude"])
        for node in record["nodes"]
    }
    if list(positions) != record["node_ids"]:
        raise TopologyApplyError(f"way {way_id} node records are out of order")
    for node_id, position in positions.items():
        existing = coordinates.get(node_id)
        if existing is None:
            applied["nodes"].append(
                {
                    "latitude": position[0],
                    "longitude": position[1],
                    "node_id": node_id,
                    "tags": {},
                }
            )
            coordinates[node_id] = position
        elif existing != position:
            raise TopologyApplyError(f"coordinate drift for OSM node {node_id}")
    memberships = [{"directions_ja": [], "route_id": route["route_id"]}]
    ways[way_id] = {
        "kind": "MAINLINE",
        "node_ids": record["node_ids"],
        "route_memberships": memberships,
        "tags": tags,
        "version": record["version"],
        "way_id": way_id,
    }
    for index, (before, after) in enumerate(zip(record["node_ids"], record["node_ids"][1:])):
        edges.append(
            {
                "direction": "forward",
                "edge_id": f"osm.{way_id}.{index}.forward",
                "from_node_id": before,
                "kind": "MAINLINE",
                "length_meters": round(haversine_meters(positions[before], positions[after]), 3),
                "route_memberships": memberships,
                "segment_index": index,
                "to_node_id": after,
                "way_id": way_id,
            }
        )


def reaches(edges: list[dict[str, Any]], start_node: int, end_node: int) -> bool:
    successors: dict[int, list[int]] = {}
    for edge in edges:
        successors.setdefault(edge["from_node_id"], []).append(edge["to_node_id"])
    reached = {start_node}
    frontier = deque([start_node])
    while frontier:
        node = frontier.popleft()
        for successor in successors.get(node, ()):
            if successor not in reached:
                reached.add(successor)
                frontier.append(successor)
    return end_node in reached


def main() -> int:
    arguments = parse_arguments()
    network = json.loads(arguments.network.read_text())
    review = json.loads(arguments.review.read_text())
    try:
        if review.get("input_database_sha256") != sha256(arguments.network):
            raise TopologyApplyError("review input database hash does not match")
        applied = apply_review(network, review)
        applied["sources"]["topology_review"] = {
            "checked_at": review["checked_at"],
            "cut_crossing_count": len(review["cut_crossings"]),
            "removed_way_count": len(review["removed_ways"]),
            "restored_way_count": sum(
                len(chain["way_ids"]) for chain in review["restored_chains"]
            ),
            "review_id": review["review_id"],
            "sha256": sha256(arguments.review),
        }
        applied["database_id"] = (
            applied["database_id"] + "+topology-" + review["checked_at"].replace("-", "")
        )
    except TopologyApplyError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    # Byte-identical serialisation to `build_shuto_network.py`, so applying
    # the review shows up as the ways and segments it changes and nothing else.
    arguments.output.write_text(
        json.dumps(applied, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
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
