#!/usr/bin/env python3
"""Build a routable, directed whole-Shuto graph from a pinned OSM PBF.

Official operator facts define the product's route, IC, JCT, and PA catalog.
OpenStreetMap supplies candidate geometry and topology only. The generated
database remains an ODbL derivative and is not relicensed as Apache-2.0.
"""

from __future__ import annotations

import argparse
from collections import defaultdict, deque
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import re
import sys
from typing import Any, Iterable


ROUTE_RELATION_IDS = {
    "C1": 4256008,
    "C2": 4256077,
    "Y": 4256119,
    "B": 4256202,
    "1_UENO": 4256217,
    "1_HANEDA": 4256244,
    "2": 4256339,
    "3": 4256376,
    "4": 4256522,
    "5": 4256611,
    "6_MUKOJIMA": 4256960,
    "6_MISATO": 4256985,
    "7": 4257465,
    "9": 4257496,
    "10": 4257498,
    "11": 4257564,
    "S1": 4258155,
    "K1": 4258165,
    "K2": 4258166,
    "K3": 4259160,
    "K5": 4259192,
    "K6": 4259197,
    "S2": 4259487,
    "S5": 4259488,
    "K7_YOKOHAMA_KITA": 10355798,
    "K7_YOKOHAMA_HOKUSEI": 10732984,
}
ALLOWED_HIGHWAYS = {"motorway", "motorway_link"}
FORBIDDEN_ACCESS = {"no", "private"}
ODBL_LICENSE_URI = "https://opendatacommons.org/licenses/odbl/1-0/"
BOUNDS = {
    "minimum_latitude": 35.15,
    "maximum_latitude": 36.15,
    "minimum_longitude": 139.10,
    "maximum_longitude": 140.35,
}
EARTH_RADIUS_METERS = 6_371_000.0
JUNCTION_OSM_NODE_OVERRIDES = {
    # Current 1 Haneda mainline branch nodes at Showajima. The operator
    # directory names the JCT; the pinned OSM nodes carry no junction name.
    "昭和島JCT": [36610838, 36610850],
    # Reviewed C2/B decision nodes. The pinned OSM nodes carry no junction
    # name, while the operator directory and exact directed route identify
    # these forks as part of the named junctions.
    "葛西JCT": [31330103],
    # The outer-loop C1/3 decision is part of Tanimachi JCT in the operator
    # diagram, but the pinned OSM node is unnamed. Keep both carriageway
    # decision nodes bound to the same official junction identity.
    "谷町JCT": [260710778],
    # Reviewed compound decision nodes on the Yokohama circuits. The
    # operator diagrams show these forks inside the named JCTs, while the
    # pinned OSM nodes themselves are unnamed.
    "生麦JCT": [4360978732],
    "大師JCT": [273330999, 3817775796],
    "川崎浮島JCT": [739475888],
}


class NetworkBuildError(RuntimeError):
    """Fail-closed source, catalog, topology, or geometry error."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--official-catalog", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--expected-input-sha256", required=True)
    parser.add_argument("--facility-candidate-review", required=True, type=Path)
    parser.add_argument("--source-uri", required=True)
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
        raise NetworkBuildError(
            "pyosmium is required; install the pinned builder version"
        ) from error
    if actual_version != expected_version:
        raise NetworkBuildError(
            f"pyosmium version mismatch: {actual_version} != {expected_version}"
        )
    return osmium


def entity_filter(osmium: Any, entity_type: Any) -> Any:
    return osmium.filter.EntityFilter(entity_type)


def load_catalog(path: Path) -> tuple[dict[str, Any], str]:
    raw = path.read_bytes()
    catalog = json.loads(raw)
    if catalog.get("schema_version") != "1.0":
        raise NetworkBuildError("unsupported official catalog schema")
    route_ids = {
        route["route_id"] for route in catalog.get("routes", [])
    }
    missing = set(ROUTE_RELATION_IDS) - route_ids
    if missing:
        raise NetworkBuildError(
            "official catalog is missing routes: " + ", ".join(sorted(missing))
        )
    return catalog, hashlib.sha256(raw).hexdigest()


def official_directions_by_route(
    catalog: dict[str, Any],
) -> dict[str, list[str]]:
    directions: dict[str, set[str]] = defaultdict(set)
    for facility in catalog["directional_facilities"]:
        directions[facility["route_id"]].update(
            facility["entrance_directions"]
        )
        directions[facility["route_id"]].update(
            facility["exit_directions"]
        )
    return {
        route["route_id"]: sorted(directions[route["route_id"]])
        for route in catalog["routes"]
    }


def relation_snapshot(
    osmium: Any,
    input_path: Path,
) -> tuple[
    dict[str, dict[str, Any]],
    dict[int, list[dict[str, str]]],
    str,
]:
    relation_to_route = {
        relation_id: route_id
        for route_id, relation_id in ROUTE_RELATION_IDS.items()
    }
    routes: dict[str, dict[str, Any]] = {}
    membership_by_way: dict[int, list[dict[str, str]]] = defaultdict(list)
    processor = osmium.FileProcessor(str(input_path)).with_filter(
        entity_filter(osmium, osmium.osm.RELATION)
    )
    source_snapshot_at = processor.header.get("osmosis_replication_timestamp")
    if not source_snapshot_at:
        raise NetworkBuildError("PBF has no replication timestamp")
    for relation in processor:
        route_id = relation_to_route.get(relation.id)
        if route_id is None:
            continue
        tags = dict(relation.tags)
        if tags.get("type") != "route" or tags.get("route") != "road":
            raise NetworkBuildError(
                f"OSM relation {relation.id} is no longer a road route"
            )
        routes[route_id] = {
            "route_id": route_id,
            "relation_id": relation.id,
            "relation_version": relation.version,
            "osm_name": tags.get("name"),
            "osm_ref": tags.get("ref"),
        }
        for member in relation.members:
            if member.type != "w":
                continue
            membership_by_way[member.ref].append(
                {
                    "route_id": route_id,
                    "member_role": member.role or "",
                }
            )
    missing = set(ROUTE_RELATION_IDS) - set(routes)
    if missing:
        raise NetworkBuildError(
            "PBF is missing Shuto route relations: "
            + ", ".join(sorted(missing))
        )
    return routes, membership_by_way, source_snapshot_at


def is_in_bounds(latitude: float, longitude: float) -> bool:
    return (
        BOUNDS["minimum_latitude"]
        <= latitude
        <= BOUNDS["maximum_latitude"]
        and BOUNDS["minimum_longitude"]
        <= longitude
        <= BOUNDS["maximum_longitude"]
    )


def scan_motorway_ways(
    osmium: Any,
    input_path: Path,
    mainline_way_ids: set[int],
    membership_by_way: dict[int, list[dict[str, str]]],
) -> tuple[
    dict[int, dict[str, Any]],
    dict[int, tuple[float, float]],
    dict[int, dict[str, Any]],
    dict[int, tuple[float, float]],
]:
    ways: dict[int, dict[str, Any]] = {}
    node_coordinates: dict[int, tuple[float, float]] = {}
    # Plain motorway ways carrying no pinned relation membership. They are
    # never flood-filled; only the bounded gap-connector pass may absorb
    # them, so another expressway's mainline stays out of the graph.
    orphan_ways: dict[int, dict[str, Any]] = {}
    orphan_node_coordinates: dict[int, tuple[float, float]] = {}
    expected_inactive_way_ids: set[int] = set()
    processor = (
        osmium.FileProcessor(str(input_path))
        .with_filter(entity_filter(osmium, osmium.osm.WAY))
        .with_locations()
    )
    for way in processor:
        tags = dict(way.tags)
        highway = tags.get("highway")
        if (
            highway == "construction"
            and tags.get("construction") == "motorway"
            and tags.get("motorcar") not in FORBIDDEN_ACCESS
        ):
            highway = "motorway"
            tags["kaido:source_highway"] = "construction"
            tags["highway"] = "motorway"
        is_orphan_motorway = (
            way.id not in mainline_way_ids and highway == "motorway"
        )
        if (
            way.id not in mainline_way_ids
            and highway != "motorway_link"
            and not is_orphan_motorway
        ):
            continue
        if highway not in ALLOWED_HIGHWAYS:
            if tags.get("abandoned:highway") == "motorway":
                expected_inactive_way_ids.add(way.id)
            continue
        motorcar_access = tags.get("motorcar")
        if motorcar_access in FORBIDDEN_ACCESS:
            expected_inactive_way_ids.add(way.id)
            continue
        if motorcar_access is None and (
            tags.get("motor_vehicle") in FORBIDDEN_ACCESS
            or tags.get("access") in FORBIDDEN_ACCESS
        ):
            expected_inactive_way_ids.add(way.id)
            continue
        coordinates: list[tuple[int, float, float]] = []
        for node in way.nodes:
            if not node.location.valid():
                raise NetworkBuildError(
                    f"OSM way {way.id} has an unresolved node"
                )
            coordinates.append(
                (node.ref, node.location.lat, node.location.lon)
            )
        if len(coordinates) < 2:
            continue
        if way.id not in mainline_way_ids and not any(
            is_in_bounds(latitude, longitude)
            for _, latitude, longitude in coordinates
        ):
            continue
        record = {
            "way_id": way.id,
            "version": way.version,
            "node_ids": [node_id for node_id, _, _ in coordinates],
            "tags": tags,
        }
        if is_orphan_motorway:
            orphan_ways[way.id] = record
            for node_id, latitude, longitude in coordinates:
                orphan_node_coordinates[node_id] = (latitude, longitude)
            continue
        ways[way.id] = record
        for node_id, latitude, longitude in coordinates:
            existing = node_coordinates.get(node_id)
            coordinate = (latitude, longitude)
            if existing is not None and existing != coordinate:
                raise NetworkBuildError(
                    f"coordinate drift for OSM node {node_id}"
                )
            node_coordinates[node_id] = coordinate

    missing = mainline_way_ids - set(ways)
    unavailable_only_missing = {
        way_id
        for way_id in missing
        if {
            membership["route_id"]
            for membership in membership_by_way[way_id]
        }
        <= {"Y"}
    }
    unexpected_missing = (
        missing - unavailable_only_missing - expected_inactive_way_ids
    )
    if unexpected_missing:
        raise NetworkBuildError(
            f"{len(unexpected_missing)} available Shuto relation ways "
            "were not usable motorways: "
            + ", ".join(str(value) for value in sorted(unexpected_missing))
        )
    return ways, node_coordinates, orphan_ways, orphan_node_coordinates


def select_connected_links(
    ways: dict[int, dict[str, Any]],
    mainline_way_ids: set[int],
) -> set[int]:
    link_ids = set(ways) - mainline_way_ids
    links_by_node: dict[int, set[int]] = defaultdict(set)
    for way_id in link_ids:
        for node_id in ways[way_id]["node_ids"]:
            links_by_node[node_id].add(way_id)

    selected = set(mainline_way_ids)
    queue = deque(
        node_id
        for way_id in mainline_way_ids
        for node_id in ways[way_id]["node_ids"]
    )
    visited_nodes: set[int] = set()
    while queue:
        node_id = queue.popleft()
        if node_id in visited_nodes:
            continue
        visited_nodes.add(node_id)
        for way_id in links_by_node.get(node_id, ()):
            if way_id in selected:
                continue
            selected.add(way_id)
            queue.extend(ways[way_id]["node_ids"])
    return selected


def normalize_member_role(role: str) -> list[str]:
    value = role.lower()
    directions: list[str] = []
    mappings = [
        ("inner", "内回り"),
        ("outer", "外回り"),
        ("east", "東行き"),
        ("west", "西行き"),
        ("north", "北行き"),
        ("south", "南行き"),
        ("inbound", "上り"),
        ("outbound", "下り"),
        ("up", "上り"),
        ("down", "下り"),
    ]
    for token, direction in mappings:
        if re.search(rf"\b{token}\b", value):
            directions.append(direction)
    return directions


def propagate_membership(
    ways: dict[int, dict[str, Any]],
    selected_way_ids: set[int],
    mainline_way_ids: set[int],
    membership_by_way: dict[int, list[dict[str, str]]],
) -> dict[int, list[dict[str, Any]]]:
    memberships: dict[int, dict[str, set[str]]] = {}
    ways_by_node: dict[int, set[int]] = defaultdict(set)
    for way_id in selected_way_ids:
        for node_id in ways[way_id]["node_ids"]:
            ways_by_node[node_id].add(way_id)
        memberships[way_id] = defaultdict(set)
        for membership in membership_by_way.get(way_id, []):
            route_id = membership["route_id"]
            role = membership["member_role"]
            memberships[way_id][route_id].update(
                normalize_member_role(role)
            )

    queue = deque(
        way_id
        for way_id in selected_way_ids
        if memberships[way_id]
    )
    while queue:
        way_id = queue.popleft()
        current = memberships[way_id]
        for node_id in ways[way_id]["node_ids"]:
            for neighbor_id in ways_by_node[node_id]:
                if neighbor_id == way_id:
                    continue
                if neighbor_id in mainline_way_ids:
                    continue
                neighbor = memberships[neighbor_id]
                changed = False
                for route_id, directions in current.items():
                    if route_id not in neighbor:
                        neighbor[route_id] = set(directions)
                        changed = True
                if changed:
                    queue.append(neighbor_id)

    return {
        way_id: [
            {
                "route_id": route_id,
                "directions_ja": sorted(directions),
            }
            for route_id, directions in sorted(route_memberships.items())
        ]
        for way_id, route_memberships in memberships.items()
    }


GAP_CONNECTOR_MAX_METERS = 1_000.0
GAP_CONNECTOR_MAX_WAYS = 4


def gap_connector_matches(
    tags: dict[str, str],
    terminating_route_ids: set[str],
) -> bool:
    """A gap connector must belong to the interrupted route itself.

    OSM editors regularly split a carriageway way and forget to re-add the
    new piece to the route relation; those pieces keep the route's `ref`
    (or at least a Shuto name). Another expressway's mainline sharing the
    junction node (Aqua-Line, Yoko-Yoko, Kan-Etsu, ...) carries a different
    ref and is rejected, which preserves the no-flood-fill promise.
    """
    route_refs = {
        route_id.split("_")[0] for route_id in terminating_route_ids
    }
    refs = [
        value.strip()
        for value in tags.get("ref", "").split(";")
        if value.strip()
    ]
    if refs:
        return any(ref in route_refs for ref in refs)
    return "首都高" in tags.get("name", "")


def absorb_gap_connectors(
    ways: dict[int, dict[str, Any]],
    orphan_ways: dict[int, dict[str, Any]],
    orphan_node_coordinates: dict[int, tuple[float, float]],
    selected_way_ids: set[int],
    mainline_way_ids: set[int],
    memberships: dict[int, list[dict[str, Any]]],
    node_coordinates: dict[int, tuple[float, float]],
) -> list[int]:
    """Bounded repair of directed dead ends inside the selected graph.

    A membership-carrying carriageway that ends with no outgoing
    continuation is a gap, not a route terminus, when a short chain of
    same-route orphan motorway ways (relation membership lost to an OSM
    split) leads directly back onto the selected graph. Each absorbed way
    inherits the interrupted route's membership and is marked with a
    `kaido:gap_connector` tag for provenance.
    """
    outgoing_nodes: set[int] = set()
    terminal_memberships: dict[int, dict[str, set[str]]] = {}
    for way_id in selected_way_ids:
        way = ways[way_id]
        forward, reverse = directions(way["tags"])
        node_ids = way["node_ids"]
        for before, after in zip(node_ids, node_ids[1:]):
            if forward:
                outgoing_nodes.add(before)
            if reverse:
                outgoing_nodes.add(after)
        way_routes = {
            membership["route_id"]: set(membership["directions_ja"])
            for membership in memberships.get(way_id, [])
        }
        if not way_routes:
            continue
        terminals = []
        if forward:
            terminals.append(node_ids[-1])
        if reverse:
            terminals.append(node_ids[0])
        for terminal in terminals:
            merged = terminal_memberships.setdefault(terminal, {})
            for route_id, route_directions in way_routes.items():
                merged.setdefault(route_id, set()).update(
                    route_directions
                )

    dead_ends = sorted(
        node_id
        for node_id in terminal_memberships
        if node_id not in outgoing_nodes
    )

    orphan_entries: dict[int, list[tuple[int, bool]]] = defaultdict(list)
    for way_id, way in orphan_ways.items():
        forward, reverse = directions(way["tags"])
        if forward:
            orphan_entries[way["node_ids"][0]].append((way_id, False))
        if reverse:
            orphan_entries[way["node_ids"][-1]].append((way_id, True))

    def orphan_length(way: dict[str, Any]) -> float:
        node_ids = way["node_ids"]
        return sum(
            haversine_meters(
                orphan_node_coordinates[before],
                orphan_node_coordinates[after],
            )
            for before, after in zip(node_ids, node_ids[1:])
        )

    absorbed: dict[int, dict[str, set[str]]] = {}
    for node_id in dead_ends:
        routes = terminal_memberships[node_id]
        queue: deque[tuple[int, float, tuple[tuple[int, bool], ...]]] = (
            deque([(node_id, 0.0, ())])
        )
        seen = {node_id}
        found: tuple[tuple[int, bool], ...] | None = None
        while queue and found is None:
            current, travelled, path = queue.popleft()
            if len(path) >= GAP_CONNECTOR_MAX_WAYS:
                continue
            for way_id, reversed_traversal in orphan_entries.get(
                current, ()
            ):
                if any(step[0] == way_id for step in path):
                    continue
                way = orphan_ways[way_id]
                if not gap_connector_matches(way["tags"], set(routes)):
                    continue
                length = orphan_length(way)
                if travelled + length > GAP_CONNECTOR_MAX_METERS:
                    continue
                exit_node = (
                    way["node_ids"][0]
                    if reversed_traversal
                    else way["node_ids"][-1]
                )
                next_path = path + ((way_id, reversed_traversal),)
                if exit_node in outgoing_nodes:
                    found = next_path
                    break
                if exit_node not in seen:
                    seen.add(exit_node)
                    queue.append(
                        (exit_node, travelled + length, next_path)
                    )
        if found is None:
            continue
        for way_id, _ in found:
            merged = absorbed.setdefault(way_id, {})
            refs = [
                value.strip()
                for value in orphan_ways[way_id]["tags"]
                .get("ref", "")
                .split(";")
                if value.strip()
            ]
            for route_id, route_directions in routes.items():
                if refs and route_id.split("_")[0] not in refs:
                    continue
                merged.setdefault(route_id, set()).update(
                    route_directions
                )

    for way_id in sorted(absorbed):
        way = dict(orphan_ways[way_id])
        way["tags"] = dict(way["tags"])
        way["tags"]["kaido:gap_connector"] = "yes"
        ways[way_id] = way
        selected_way_ids.add(way_id)
        mainline_way_ids.add(way_id)
        memberships[way_id] = [
            {
                "route_id": route_id,
                "directions_ja": sorted(route_directions),
            }
            for route_id, route_directions in sorted(
                absorbed[way_id].items()
            )
        ]
        for node_id in way["node_ids"]:
            coordinate = orphan_node_coordinates[node_id]
            existing = node_coordinates.get(node_id)
            if existing is not None and existing != coordinate:
                raise NetworkBuildError(
                    f"coordinate drift for OSM node {node_id}"
                )
            node_coordinates[node_id] = coordinate
    return sorted(absorbed)


def directions(tags: dict[str, str]) -> tuple[bool, bool]:
    oneway = tags.get("oneway", "").lower()
    if oneway == "-1":
        return False, True
    if oneway in {"yes", "true", "1"}:
        return True, False
    if tags.get("highway") == "motorway":
        return True, False
    return True, True


def haversine_meters(
    first: tuple[float, float],
    second: tuple[float, float],
) -> float:
    latitude1, longitude1 = map(math.radians, first)
    latitude2, longitude2 = map(math.radians, second)
    latitude_delta = latitude2 - latitude1
    longitude_delta = longitude2 - longitude1
    value = (
        math.sin(latitude_delta / 2) ** 2
        + math.cos(latitude1)
        * math.cos(latitude2)
        * math.sin(longitude_delta / 2) ** 2
    )
    return (
        2
        * EARTH_RADIUS_METERS
        * math.asin(min(1.0, math.sqrt(value)))
    )


def build_edges(
    ways: dict[int, dict[str, Any]],
    selected_way_ids: set[int],
    node_coordinates: dict[int, tuple[float, float]],
    memberships: dict[int, list[dict[str, Any]]],
) -> list[dict[str, Any]]:
    edges: list[dict[str, Any]] = []
    for way_id in sorted(selected_way_ids):
        way = ways[way_id]
        forward, reverse = directions(way["tags"])
        node_ids = way["node_ids"]
        for index, (before, after) in enumerate(
            zip(node_ids, node_ids[1:])
        ):
            length = haversine_meters(
                node_coordinates[before],
                node_coordinates[after],
            )
            common = {
                "way_id": way_id,
                "segment_index": index,
                "kind": (
                    "MAINLINE"
                    if way_id in ROUTE_WAY_IDS
                    else "LINK"
                ),
                "length_meters": round(length, 3),
                "route_memberships": memberships[way_id],
            }
            if forward:
                edges.append(
                    {
                        "edge_id": f"osm.{way_id}.{index}.forward",
                        "from_node_id": before,
                        "to_node_id": after,
                        "direction": "forward",
                        **common,
                    }
                )
            if reverse:
                edges.append(
                    {
                        "edge_id": f"osm.{way_id}.{index}.reverse",
                        "from_node_id": after,
                        "to_node_id": before,
                        "direction": "reverse",
                        **common,
                    }
                )
    return edges


def distance_to_segment(
    point: tuple[float, float],
    first: tuple[float, float],
    second: tuple[float, float],
) -> float:
    latitude_scale = 111_132.0
    longitude_scale = (
        111_320.0 * math.cos(math.radians(point[0]))
    )
    px = (point[1] - first[1]) * longitude_scale
    py = (point[0] - first[0]) * latitude_scale
    sx = (second[1] - first[1]) * longitude_scale
    sy = (second[0] - first[0]) * latitude_scale
    denominator = sx * sx + sy * sy
    if denominator == 0:
        return math.hypot(px, py)
    fraction = max(0.0, min(1.0, (px * sx + py * sy) / denominator))
    return math.hypot(px - fraction * sx, py - fraction * sy)


def membership_matches(
    edge: dict[str, Any],
    route_id: str,
    official_directions: list[str],
) -> bool:
    for membership in edge["route_memberships"]:
        if membership["route_id"] != route_id:
            continue
        candidate_directions = membership["directions_ja"]
        return (
            not official_directions
            or not candidate_directions
            or bool(set(official_directions) & set(candidate_directions))
        )
    return False


RAMP_TOPOLOGY_PROBE_METERS = 1_500.0


def reaches_mainline(
    start_node: int,
    adjacency: dict[int, list[dict[str, Any]]],
    follow_forward: bool,
) -> bool:
    """Bounded probe: does the ramp chain rejoin a mainline carriageway?

    A genuine exit ramp leaves the network (its downstream dead-ends inside
    the graph because surface streets are not part of it), while a
    junction-to-junction connector merges back into a mainline within a few
    hundred meters. Entry ramps are symmetric: a genuine one begins at a
    graph dead-start, a connector is fed by a mainline.
    """
    frontier = [(start_node, 0.0)]
    seen = {start_node}
    index = 0
    while index < len(frontier):
        node, travelled = frontier[index]
        index += 1
        if travelled > RAMP_TOPOLOGY_PROBE_METERS:
            continue
        for edge in adjacency.get(node, ()):
            if edge["kind"] == "MAINLINE":
                return True
            next_node = (
                edge["to_node_id"]
                if follow_forward
                else edge["from_node_id"]
            )
            if next_node not in seen:
                seen.add(next_node)
                frontier.append(
                    (next_node, travelled + edge["length_meters"])
                )
    return False


def candidate_edges_for_facility(
    facility: dict[str, Any],
    edges: list[dict[str, Any]],
    node_coordinates: dict[int, tuple[float, float]],
    direction_key: str,
    outgoing_edges: dict[int, list[dict[str, Any]]],
    incoming_edges: dict[int, list[dict[str, Any]]],
) -> list[dict[str, Any]]:
    point = (
        facility["coordinate"]["latitude"],
        facility["coordinate"]["longitude"],
    )
    route_id = facility["route_id"]
    official_directions = facility[direction_key]
    ranked: list[tuple[float, dict[str, Any]]] = []
    for edge in edges:
        if not membership_matches(
            edge, route_id, official_directions
        ):
            continue
        distance = distance_to_segment(
            point,
            node_coordinates[edge["from_node_id"]],
            node_coordinates[edge["to_node_id"]],
        )
        if distance <= 750:
            ranked.append((distance, edge))
    ranked.sort(key=lambda item: (item[0], item[1]["edge_id"]))
    if not ranked:
        return []
    link_candidates = [item for item in ranked if item[1]["kind"] == "LINK"]
    if link_candidates:
        # Ramp-topology gate: at a stacked junction the geometric ranking
        # also catches junction-to-junction connectors running beside the
        # true ramp (Namamugi's exit caught the K5-to-K1 connector, faking
        # a short fare path the operator's own search prices via 15 km).
        # If the gate would drop every candidate — e.g., a combined plaza
        # whose exit loop rejoins an entry ramp — keep the geometric list
        # rather than unmatching the facility.
        if direction_key == "exit_directions":
            gated = [
                item
                for item in link_candidates
                if not reaches_mainline(
                    item[1]["to_node_id"],
                    outgoing_edges,
                    follow_forward=True,
                )
            ]
        else:
            gated = [
                item
                for item in link_candidates
                if not reaches_mainline(
                    item[1]["from_node_id"],
                    incoming_edges,
                    follow_forward=False,
                )
            ]
        if gated:
            link_candidates = gated
        # Anchor each surviving candidate at its ramp mouth: the chain start
        # for an entrance (the toll gate the drive actually begins at) and
        # the chain end for an exit. Planning from an arbitrary mid-ramp
        # segment starts routes inside hairpin geometry that entry
        # continuity verification cannot walk.
        walk_forward = direction_key == "exit_directions"
        adjacency = outgoing_edges if walk_forward else incoming_edges
        anchored: dict[str, tuple[float, dict[str, Any]]] = {}
        for distance, edge in link_candidates:
            current = edge
            walked = 0.0
            for _ in range(60):
                node = (
                    current["to_node_id"]
                    if walk_forward
                    else current["from_node_id"]
                )
                links = [
                    neighbor
                    for neighbor in adjacency.get(node, ())
                    if neighbor["kind"] == "LINK"
                ]
                # The toll gate sits within a few hundred meters of the
                # facility point; walking further would anchor onto
                # pre-gate collectors shared with other structures.
                if (
                    len(links) != 1
                    or walked + links[0]["length_meters"] > 350
                ):
                    break
                current = links[0]
                walked += current["length_meters"]
            existing = anchored.get(current["edge_id"])
            if existing is None or distance < existing[0]:
                anchored[current["edge_id"]] = (distance, current)
        link_candidates = sorted(
            anchored.values(),
            key=lambda item: (item[0], item[1]["edge_id"]),
        )
        # Parking-access rejection: a rest-area ramp also "leaves the
        # network" (its service roads are not part of the graph), so the
        # topology gate cannot tell it from a genuine exit — Yoyogi PA's
        # up-side ramp faked a 1.1 km Shinjuku-to-Yoyogi fare path this
        # way. A mouth that sits beside a parking area, closer to the PA
        # than to the claiming facility, belongs to the PA. If the filter
        # would drop everything, keep the unfiltered list.
    selected = link_candidates[:12] if link_candidates else ranked[:12]
    return [
        {
            "edge_id": edge["edge_id"],
            "distance_meters": round(distance, 3),
        }
        for distance, edge in selected
    ]


def load_candidate_review(path: Path) -> tuple[dict[str, Any], str]:
    raw = path.read_bytes()
    review = json.loads(raw)
    if review.get("schema_version") != "1.2":
        raise NetworkBuildError("unsupported facility candidate review schema")
    for exclusion in review.get("excluded_candidates", []):
        for field in ("facility_id", "side", "edge_id", "reason", "evidence"):
            if not exclusion.get(field):
                raise NetworkBuildError(
                    "facility candidate exclusion is missing " + field
                )
        if exclusion["side"] not in ("entry", "exit"):
            raise NetworkBuildError(
                "facility candidate exclusion side must be entry or exit"
            )
    for rebinding in review.get("entry_boundary_rebindings", []):
        for field in (
            "facility_id",
            "anchor_edge_id",
            "boundary_edge_id",
            "distance_meters",
            "reason",
            "evidence",
        ):
            if rebinding.get(field) in (None, ""):
                raise NetworkBuildError(
                    "entry boundary rebinding is missing " + field
                )
        distance = rebinding["distance_meters"]
        if (
            not isinstance(distance, (int, float))
            or not math.isfinite(distance)
            or distance < 0
            or distance > 750
        ):
            raise NetworkBuildError(
                "entry boundary rebinding distance must be within 750 meters"
            )
    for replacement in review.get("entry_candidate_replacements", []):
        for field in (
            "facility_id",
            "expected_entry_edge_ids",
            "predecessor_edge_id",
            "boundary_edge_id",
            "distance_meters",
            "reason",
            "evidence",
        ):
            if replacement.get(field) in (None, "", []):
                raise NetworkBuildError(
                    "entry candidate replacement is missing " + field
                )
        expected = replacement["expected_entry_edge_ids"]
        if (
            not isinstance(expected, list)
            or not all(
                isinstance(edge_id, str) and edge_id for edge_id in expected
            )
            or len(set(expected)) != len(expected)
        ):
            raise NetworkBuildError(
                "entry candidate replacement expected edges must be unique IDs"
            )
        distance = replacement["distance_meters"]
        if (
            not isinstance(distance, (int, float))
            or not math.isfinite(distance)
            or distance < 0
            or distance > 750
        ):
            raise NetworkBuildError(
                "entry candidate replacement distance must be within 750 meters"
            )
    return review, hashlib.sha256(raw).hexdigest()


def apply_candidate_review(
    facilities: list[dict[str, Any]],
    review: dict[str, Any],
    edges: list[dict[str, Any]],
) -> None:
    """Apply exact reviewed exclusions and forward entry boundaries.

    Every correction must match the current graph. A stale review fails the
    build instead of silently rotting or weakening directed continuity.
    """
    by_id = {facility["facility_id"]: facility for facility in facilities}
    for exclusion in review.get("excluded_candidates", []):
        facility = by_id.get(exclusion["facility_id"])
        if facility is None:
            raise NetworkBuildError(
                "candidate review names unknown facility "
                + exclusion["facility_id"]
            )
        key = (
            "entry_edge_candidates"
            if exclusion["side"] == "entry"
            else "exit_edge_candidates"
        )
        remaining = [
            candidate
            for candidate in facility[key]
            if candidate["edge_id"] != exclusion["edge_id"]
        ]
        if len(remaining) == len(facility[key]):
            raise NetworkBuildError(
                "candidate review exclusion did not match: "
                + exclusion["facility_id"]
                + " "
                + exclusion["edge_id"]
            )
        if not remaining:
            raise NetworkBuildError(
                "candidate review would unmatch facility "
                + exclusion["facility_id"]
            )
        facility[key] = remaining

    edges_by_id = {edge["edge_id"]: edge for edge in edges}
    for rebinding in review.get("entry_boundary_rebindings", []):
        facility = by_id.get(rebinding["facility_id"])
        if facility is None:
            raise NetworkBuildError(
                "entry boundary rebinding names unknown facility "
                + rebinding["facility_id"]
            )
        candidates = facility["entry_edge_candidates"]
        matching = [
            candidate
            for candidate in candidates
            if candidate["edge_id"] == rebinding["anchor_edge_id"]
        ]
        if len(matching) != 1:
            raise NetworkBuildError(
                "entry boundary rebinding did not match exactly one anchor: "
                + rebinding["facility_id"]
                + " "
                + rebinding["anchor_edge_id"]
            )
        anchor = edges_by_id.get(rebinding["anchor_edge_id"])
        boundary = edges_by_id.get(rebinding["boundary_edge_id"])
        if anchor is None or boundary is None:
            raise NetworkBuildError(
                "entry boundary rebinding names an unknown graph edge"
            )
        if (
            anchor["kind"] != "LINK"
            or boundary["kind"] != "LINK"
            or anchor["to_node_id"] != boundary["from_node_id"]
            or not membership_matches(
                boundary,
                facility["route_id"],
                facility["entrance_directions"],
            )
        ):
            raise NetworkBuildError(
                "entry boundary rebinding is not one forward ramp step"
            )
        if any(
            candidate["edge_id"] == boundary["edge_id"]
            for candidate in candidates
        ):
            raise NetworkBuildError(
                "entry boundary rebinding duplicates an existing candidate"
            )
        facility["entry_edge_candidates"] = sorted(
            [
                candidate
                for candidate in candidates
                if candidate["edge_id"] != anchor["edge_id"]
            ]
            + [
                {
                    "edge_id": boundary["edge_id"],
                    "distance_meters": round(
                        float(rebinding["distance_meters"]), 3
                    ),
                }
            ],
            key=lambda candidate: (
                candidate["distance_meters"],
                candidate["edge_id"],
            ),
        )

    for replacement in review.get("entry_candidate_replacements", []):
        facility = by_id.get(replacement["facility_id"])
        if facility is None:
            raise NetworkBuildError(
                "entry candidate replacement names unknown facility "
                + replacement["facility_id"]
            )
        actual_ids = {
            candidate["edge_id"]
            for candidate in facility["entry_edge_candidates"]
        }
        expected_ids = set(replacement["expected_entry_edge_ids"])
        if actual_ids != expected_ids:
            raise NetworkBuildError(
                "entry candidate replacement does not match current candidates: "
                + replacement["facility_id"]
            )
        predecessor = edges_by_id.get(replacement["predecessor_edge_id"])
        boundary = edges_by_id.get(replacement["boundary_edge_id"])
        if predecessor is None or boundary is None:
            raise NetworkBuildError(
                "entry candidate replacement names an unknown graph edge"
            )
        if (
            predecessor["kind"] != "LINK"
            or boundary["kind"] != "LINK"
            or predecessor["to_node_id"] != boundary["from_node_id"]
            or not membership_matches(
                boundary,
                facility["route_id"],
                facility["entrance_directions"],
            )
        ):
            raise NetworkBuildError(
                "entry candidate replacement is not a forward ramp boundary"
            )
        facility["entry_edge_candidates"] = [
            {
                "edge_id": boundary["edge_id"],
                "distance_meters": round(
                    float(replacement["distance_meters"]), 3
                ),
            }
        ]


def match_facilities(
    catalog: dict[str, Any],
    edges: list[dict[str, Any]],
    node_coordinates: dict[int, tuple[float, float]],
) -> list[dict[str, Any]]:
    outgoing_edges: dict[int, list[dict[str, Any]]] = defaultdict(list)
    incoming_edges: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for edge in edges:
        outgoing_edges[edge["from_node_id"]].append(edge)
        incoming_edges[edge["to_node_id"]].append(edge)
    facilities: list[dict[str, Any]] = []
    for official in catalog["directional_facilities"]:
        entry_candidates = (
            candidate_edges_for_facility(
                official,
                edges,
                node_coordinates,
                "entrance_directions",
                outgoing_edges,
                incoming_edges,
            )
            if official["entrance_directions"]
            and official["operational_status"] == "AVAILABLE"
            else []
        )
        exit_candidates = (
            candidate_edges_for_facility(
                official,
                edges,
                node_coordinates,
                "exit_directions",
                outgoing_edges,
                incoming_edges,
            )
            if official["exit_directions"]
            and official["operational_status"] == "AVAILABLE"
            else []
        )
        facilities.append(
            {
                **official,
                "entry_edge_candidates": entry_candidates,
                "exit_edge_candidates": exit_candidates,
                "geometry_match_state": (
                    "CANDIDATE_MATCHED"
                    if (
                        (not official["entrance_directions"] or entry_candidates)
                        and (
                            not official["exit_directions"]
                            or exit_candidates
                        )
                    )
                    else "UNRESOLVED"
                ),
            }
        )
    return facilities


def normalized_name(value: str) -> str:
    return re.sub(
        r"(ジャンクション|JCT|・|（.*?）|\s)",
        "",
        value,
        flags=re.IGNORECASE,
    )


def selected_node_tags(
    osmium: Any,
    input_path: Path,
    selected_node_ids: set[int],
) -> dict[int, dict[str, str]]:
    result: dict[int, dict[str, str]] = {}
    processor = osmium.FileProcessor(str(input_path)).with_filter(
        entity_filter(osmium, osmium.osm.NODE)
    )
    for node in processor:
        if node.id not in selected_node_ids or not node.tags:
            continue
        result[node.id] = dict(node.tags)
    return result


def match_junctions(
    catalog: dict[str, Any],
    node_tags: dict[int, dict[str, str]],
    node_coordinates: dict[int, tuple[float, float]],
) -> list[dict[str, Any]]:
    tagged_names: list[tuple[int, str]] = []
    for node_id, tags in node_tags.items():
        name = tags.get("name") or tags.get("name:ja") or ""
        if name and (
            tags.get("highway") == "motorway_junction"
            or "JCT" in name
            or "ジャンクション" in name
        ):
            tagged_names.append((node_id, name))

    junctions: list[dict[str, Any]] = []
    for official in catalog["junctions"]:
        tokens = [
            normalized_name(token)
            for token in re.split(r"[・･]", official["name_ja"])
            if normalized_name(token)
        ]
        matched_node_ids = sorted(
            {
                node_id
                for node_id, osm_name in tagged_names
                if any(
                    token in normalized_name(osm_name)
                    or normalized_name(osm_name) in token
                    for token in tokens
                )
            }
            | {
                node_id
                for node_id in JUNCTION_OSM_NODE_OVERRIDES.get(
                    official["name_ja"], []
                )
                if node_id in node_coordinates
            }
        )
        coordinates = [
            node_coordinates[node_id]
            for node_id in matched_node_ids
            if node_id in node_coordinates
        ]
        junctions.append(
            {
                **official,
                "osm_node_ids": matched_node_ids,
                "coordinate": (
                    {
                        "latitude": sum(value[0] for value in coordinates)
                        / len(coordinates),
                        "longitude": sum(value[1] for value in coordinates)
                        / len(coordinates),
                    }
                    if coordinates
                    else None
                ),
                "geometry_match_state": (
                    "CANDIDATE_MATCHED"
                    if coordinates
                    else "UNRESOLVED"
                ),
            }
        )
    return junctions


def compact_way(
    way: dict[str, Any],
    memberships: list[dict[str, Any]],
    mainline_way_ids: set[int],
) -> dict[str, Any]:
    tags = way["tags"]
    retained_tags = {
        key: tags[key]
        for key in (
            "highway",
            "name",
            "name:ja",
            "ref",
            "oneway",
            "destination",
            "destination:ref",
            "destination:lanes",
            "lanes",
            "tunnel",
            "layer",
            "construction",
            "kaido:source_highway",
            "kaido:gap_connector",
            "note",
        )
        if key in tags
    }
    return {
        "way_id": way["way_id"],
        "version": way["version"],
        "kind": (
            "MAINLINE"
            if way["way_id"] in mainline_way_ids
            else "LINK"
        ),
        "node_ids": way["node_ids"],
        "route_memberships": memberships,
        "tags": retained_tags,
    }


ROUTE_WAY_IDS: set[int] = set()


def build(arguments: argparse.Namespace) -> dict[str, Any]:
    actual_sha = sha256(arguments.input)
    if actual_sha != arguments.expected_input_sha256:
        raise NetworkBuildError(
            f"input SHA-256 mismatch: {actual_sha} "
            f"!= {arguments.expected_input_sha256}"
        )
    catalog, catalog_sha = load_catalog(arguments.official_catalog)
    candidate_review, candidate_review_sha = load_candidate_review(
        arguments.facility_candidate_review
    )
    osmium = load_osmium(arguments.expected_pyosmium_version)
    routes, membership_by_way, source_snapshot_at = relation_snapshot(
        osmium, arguments.input
    )
    relation_way_ids = set(membership_by_way)
    ways, node_coordinates, orphan_ways, orphan_node_coordinates = (
        scan_motorway_ways(
            osmium,
            arguments.input,
            relation_way_ids,
            membership_by_way,
        )
    )
    mainline_way_ids = relation_way_ids & set(ways)
    global ROUTE_WAY_IDS
    ROUTE_WAY_IDS = mainline_way_ids
    selected_way_ids = select_connected_links(ways, mainline_way_ids)
    memberships = propagate_membership(
        ways,
        selected_way_ids,
        mainline_way_ids,
        membership_by_way,
    )
    gap_connector_way_ids = absorb_gap_connectors(
        ways,
        orphan_ways,
        orphan_node_coordinates,
        selected_way_ids,
        mainline_way_ids,
        memberships,
        node_coordinates,
    )
    selected_node_ids = {
        node_id
        for way_id in selected_way_ids
        for node_id in ways[way_id]["node_ids"]
    }
    edges = build_edges(
        ways,
        selected_way_ids,
        node_coordinates,
        memberships,
    )
    node_tags = selected_node_tags(
        osmium,
        arguments.input,
        selected_node_ids,
    )
    official_route_by_id = {
        route["route_id"]: route for route in catalog["routes"]
    }
    official_directions_by_route_id = official_directions_by_route(catalog)
    reviewed_facilities = match_facilities(
        catalog,
        edges,
        node_coordinates,
    )
    apply_candidate_review(reviewed_facilities, candidate_review, edges)
    return {
        "schema_version": "1.0",
        "database_id": (
            "kaido.shuto.whole-network."
            + source_snapshot_at[:10]
        ),
        "network_snapshot_id": (
            "shuto-official-"
            + catalog["checked_at"]
            + "-osm-"
            + source_snapshot_at[:10]
        ),
        "verification_state": (
            "OFFICIAL_FACILITIES_OSM_GEOMETRY_CANDIDATE"
        ),
        "checked_at": catalog["checked_at"],
        "sources": {
            "official_catalog": {
                "catalog_id": catalog["catalog_id"],
                "sha256": catalog_sha,
            },
            "facility_candidate_review": {
                "review_id": candidate_review["review_id"],
                "checked_at": candidate_review["checked_at"],
                "sha256": candidate_review_sha,
                "excluded_candidate_count": len(
                    candidate_review.get("excluded_candidates", [])
                ),
                "entry_boundary_rebinding_count": len(
                    candidate_review.get("entry_boundary_rebindings", [])
                ),
                "entry_candidate_replacement_count": len(
                    candidate_review.get("entry_candidate_replacements", [])
                ),
            },
            "osm": {
                "input_file": arguments.input.name,
                "input_sha256": actual_sha,
                "source_snapshot_at": source_snapshot_at,
                "source_uri": arguments.source_uri,
                "licence": "ODbL-1.0",
                "licence_uri": ODBL_LICENSE_URI,
                "attribution": "© OpenStreetMap contributors",
                "builder": "pyosmium",
                "builder_version": arguments.expected_pyosmium_version,
                "gap_connector_way_ids": gap_connector_way_ids,
            },
        },
        "limitations": [
            (
                "OSM geometry and topology are routing candidates, not "
                "operator-authored lane or vertical-road authority."
            ),
            (
                "Current traffic, passage, toll, and PA closure state remain "
                "REALTIME_UNCONFIRMED without a current provider response."
            ),
            (
                "Junction inset lane arrows require a separate reviewed "
                "definition; generic graph geometry must not invent lanes."
            ),
        ],
        "bounds": BOUNDS,
        "routes": [
            {
                **routes[route_id],
                "official_name_ja": official_route_by_id[route_id][
                    "official_name_ja"
                ],
                "operational_status": official_route_by_id[route_id][
                    "operational_status"
                ],
                "official_directions_ja":
                    official_directions_by_route_id[route_id],
            }
            for route_id in ROUTE_RELATION_IDS
        ],
        "nodes": [
            {
                "node_id": node_id,
                "latitude": node_coordinates[node_id][0],
                "longitude": node_coordinates[node_id][1],
                "tags": node_tags.get(node_id, {}),
            }
            for node_id in sorted(selected_node_ids)
        ],
        "ways": [
            compact_way(
                ways[way_id],
                memberships[way_id],
                mainline_way_ids,
            )
            for way_id in sorted(selected_way_ids)
        ],
        "edges": edges,
        "directional_facilities": reviewed_facilities,
        "junctions": match_junctions(
            catalog,
            node_tags,
            node_coordinates,
        ),
        "parking_areas": catalog["parking_areas"],
    }


def validate(result: dict[str, Any]) -> None:
    osm_source = result.get("sources", {}).get("osm", {})
    if (
        osm_source.get("attribution") != "© OpenStreetMap contributors"
        or osm_source.get("licence") != "ODbL-1.0"
        or osm_source.get("licence_uri") != ODBL_LICENSE_URI
    ):
        raise NetworkBuildError("OSM distribution metadata mismatch")
    if len(result["routes"]) != len(ROUTE_RELATION_IDS):
        raise NetworkBuildError("whole-network route count mismatch")
    if len(result["nodes"]) < 2_000 or len(result["edges"]) < 2_000:
        raise NetworkBuildError("whole-network graph is unexpectedly small")
    edge_ids = [edge["edge_id"] for edge in result["edges"]]
    if len(edge_ids) != len(set(edge_ids)):
        raise NetworkBuildError("duplicate directed edge IDs")
    route_ids = {
        membership["route_id"]
        for edge in result["edges"]
        for membership in edge["route_memberships"]
    }
    missing_routes = set(ROUTE_RELATION_IDS) - route_ids - {"Y"}
    if missing_routes:
        raise NetworkBuildError(
            "graph has no edges for: " + ", ".join(sorted(missing_routes))
        )
    unresolved_usable = [
        facility["facility_id"]
        for facility in result["directional_facilities"]
        if facility["operational_status"] == "AVAILABLE"
        and facility["geometry_match_state"] == "UNRESOLVED"
    ]
    if unresolved_usable:
        raise NetworkBuildError(
            "usable IC geometry matches unresolved: "
            + ", ".join(unresolved_usable)
        )
    unresolved_junctions = [
        junction["junction_id"]
        for junction in result["junctions"]
        if junction["geometry_match_state"] == "UNRESOLVED"
    ]
    if unresolved_junctions:
        raise NetworkBuildError(
            "JCT geometry matches unresolved: "
            + ", ".join(unresolved_junctions)
        )


def main() -> int:
    arguments = parse_arguments()
    try:
        result = build(arguments)
        validate(result)
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(
            json.dumps(
                result,
                ensure_ascii=False,
                separators=(",", ":"),
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
    except (NetworkBuildError, OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    matched_facilities = sum(
        facility["geometry_match_state"] == "CANDIDATE_MATCHED"
        for facility in result["directional_facilities"]
    )
    matched_junctions = sum(
        junction["geometry_match_state"] == "CANDIDATE_MATCHED"
        for junction in result["junctions"]
    )
    print(
        "PASS: built whole-Shuto graph with "
        f"{len(result['routes'])} routes, "
        f"{len(result['ways'])} ways, "
        f"{len(result['edges'])} directed edges, "
        f"{matched_facilities}/"
        f"{len(result['directional_facilities'])} IC matches, and "
        f"{matched_junctions}/{len(result['junctions'])} JCT matches"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
