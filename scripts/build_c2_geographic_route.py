#!/usr/bin/env python3
"""Build the bounded C2 + B geographic route used by the iPhone map.

The output is an ODbL derivative database. Official Shutoko sources establish
the directional facilities and legal route choices; OSM supplies geometry
only. Exact node checkpoints keep the generated line on the reviewed
C2-outer -> B-west -> C2-outer sequence.
"""

from __future__ import annotations

import argparse
import hashlib
import heapq
import json
import math
from pathlib import Path
from typing import Any


C2_RELATION_ID = 4256077
C2_RELATION_VERSION = 44
B_RELATION_ID = 4256202
B_RELATION_VERSION = 55

TOMIGAYA = (35.66378171, 139.6877503)
HATSUDAI_MINAMI = (35.67511257, 139.6878147)

C2_NORTH_EAST_CHECKPOINTS = [
    919617341,  # Tomigaya outer mainline beside the official facility point
    263988109,  # Itabashi JCT outer carriageway
    309609006,  # Kosuge JCT outer carriageway
    370270206,  # Horikiri JCT outer carriageway
    370270524,  # Komatsugawa JCT outer carriageway
    31330124,  # C2 outer approach to the Kasai right branch
]
KASAI_TRANSITION_CHECKPOINTS = [
    31330124,
    31330101,  # B west carriageway after the legal C2 outer movement
]
B_WEST_CHECKPOINTS = [
    31330101,
    31300491,  # Tatsumi JCT westbound
    31288811,  # Ariake JCT westbound
    6534476215,  # Oi JCT westbound / C2 outer movement boundary
]
C2_YAMATE_CHECKPOINTS = [
    6534476215,
    3387909708,  # Ohashi JCT C2 outer carriageway
    13359168654,  # C2 outer beside Hatsudai-minami exit
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--c2-source", type=Path, required=True)
    parser.add_argument("--b-source", type=Path, required=True)
    parser.add_argument("--kasai-source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def load_json(path: Path) -> tuple[dict[str, Any], str]:
    raw = path.read_bytes()
    return json.loads(raw), hashlib.sha256(raw).hexdigest()


def element_index(document: dict[str, Any]) -> dict[tuple[str, int], dict[str, Any]]:
    return {
        (element["type"], element["id"]): element
        for element in document["elements"]
    }


def relation_way_ids(
    elements: dict[tuple[str, int], dict[str, Any]],
    relation_id: int,
    expected_version: int,
) -> set[int]:
    relation = elements.get(("relation", relation_id))
    if relation is None:
        raise ValueError(f"missing relation {relation_id}")
    if relation.get("version") != expected_version:
        raise ValueError(
            f"relation {relation_id} version drift: "
            f"{relation.get('version')} != {expected_version}"
        )
    return {
        member["ref"]
        for member in relation["members"]
        if member["type"] == "way"
    }


def haversine_meters(
    first: tuple[float, float],
    second: tuple[float, float],
) -> float:
    radius = 6_371_000.0
    lat1, lon1 = map(math.radians, first)
    lat2, lon2 = map(math.radians, second)
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    value = (
        math.sin(dlat / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    )
    return 2 * radius * math.asin(math.sqrt(value))


def merge_nodes(
    target: dict[int, tuple[float, float]],
    elements: dict[tuple[str, int], dict[str, Any]],
) -> None:
    for (kind, identifier), element in elements.items():
        if kind != "node":
            continue
        coordinate = (float(element["lat"]), float(element["lon"]))
        existing = target.get(identifier)
        if existing is not None and (
            abs(existing[0] - coordinate[0]) > 1e-9
            or abs(existing[1] - coordinate[1]) > 1e-9
        ):
            raise ValueError(f"coordinate drift for OSM node {identifier}")
        target[identifier] = coordinate


def build_graph(
    elements: dict[tuple[str, int], dict[str, Any]],
    nodes: dict[int, tuple[float, float]],
    *,
    allowed_way_ids: set[int] | None,
) -> dict[int, list[tuple[int, float, int]]]:
    graph: dict[int, list[tuple[int, float, int]]] = {}

    def add_edge(start: int, end: int, way_id: int) -> None:
        if start not in nodes or end not in nodes:
            raise ValueError(f"way {way_id} references a missing node")
        distance = haversine_meters(nodes[start], nodes[end])
        graph.setdefault(start, []).append((end, distance, way_id))

    for (kind, way_id), way in elements.items():
        if kind != "way":
            continue
        if allowed_way_ids is not None and way_id not in allowed_way_ids:
            continue
        highway = way.get("tags", {}).get("highway")
        if allowed_way_ids is None and highway not in {
            "motorway",
            "motorway_link",
        }:
            continue

        way_nodes = way.get("nodes", [])
        tags = way.get("tags", {})
        reverse = tags.get("oneway") == "-1"
        one_way = reverse or tags.get("oneway") in {
            "yes",
            "1",
            "true",
        } or highway == "motorway"

        for index in range(1, len(way_nodes)):
            before = way_nodes[index - 1]
            after = way_nodes[index]
            if reverse:
                add_edge(after, before, way_id)
            else:
                add_edge(before, after, way_id)
            if not one_way:
                add_edge(after, before, way_id)

    for edges in graph.values():
        edges.sort(key=lambda value: (value[0], value[2]))
    return graph


def shortest_path(
    graph: dict[int, list[tuple[int, float, int]]],
    start: int,
    finish: int,
) -> tuple[list[int], list[int], float]:
    distances = {start: 0.0}
    previous: dict[int, tuple[int, int]] = {}
    queue = [(0.0, start)]

    while queue:
        distance, node_id = heapq.heappop(queue)
        if distance != distances.get(node_id):
            continue
        if node_id == finish:
            break
        for next_id, edge_distance, way_id in graph.get(node_id, []):
            candidate = distance + edge_distance
            if candidate >= distances.get(next_id, math.inf):
                continue
            distances[next_id] = candidate
            previous[next_id] = (node_id, way_id)
            heapq.heappush(queue, (candidate, next_id))

    if finish not in distances:
        raise ValueError(f"no directed path from {start} to {finish}")

    node_ids = [finish]
    way_ids: list[int] = []
    current = finish
    while current != start:
        prior, way_id = previous[current]
        node_ids.append(prior)
        way_ids.append(way_id)
        current = prior
    node_ids.reverse()
    way_ids.reverse()
    return node_ids, way_ids, distances[finish]


def route_through(
    graph: dict[int, list[tuple[int, float, int]]],
    checkpoints: list[int],
) -> tuple[list[int], list[int], float]:
    all_nodes: list[int] = []
    all_ways: list[int] = []
    total_distance = 0.0
    for start, finish in zip(checkpoints, checkpoints[1:]):
        node_ids, way_ids, distance = shortest_path(graph, start, finish)
        if all_nodes:
            node_ids = node_ids[1:]
        all_nodes.extend(node_ids)
        all_ways.extend(way_ids)
        total_distance += distance
    return all_nodes, all_ways, total_distance


def make_segment(
    *,
    identifier: str,
    route_shield: str,
    graph: dict[int, list[tuple[int, float, int]]],
    checkpoints: list[int],
    nodes: dict[int, tuple[float, float]],
) -> dict[str, Any]:
    node_ids, way_ids, distance = route_through(graph, checkpoints)
    return {
        "id": identifier,
        "route_shield": route_shield,
        "distance_meters": round(distance, 3),
        "checkpoint_node_ids": checkpoints,
        "node_ids": node_ids,
        "way_ids": way_ids,
        "coordinates": [
            {"latitude": nodes[node_id][0], "longitude": nodes[node_id][1]}
            for node_id in node_ids
        ],
    }


def main() -> None:
    args = parse_args()
    c2_document, c2_sha256 = load_json(args.c2_source)
    b_document, b_sha256 = load_json(args.b_source)
    kasai_document, kasai_sha256 = load_json(args.kasai_source)

    c2_elements = element_index(c2_document)
    b_elements = element_index(b_document)
    kasai_elements = element_index(kasai_document)

    c2_way_ids = relation_way_ids(
        c2_elements,
        C2_RELATION_ID,
        C2_RELATION_VERSION,
    )
    b_way_ids = relation_way_ids(
        b_elements,
        B_RELATION_ID,
        B_RELATION_VERSION,
    )

    nodes: dict[int, tuple[float, float]] = {}
    merge_nodes(nodes, c2_elements)
    merge_nodes(nodes, b_elements)
    merge_nodes(nodes, kasai_elements)

    c2_graph = build_graph(
        c2_elements,
        nodes,
        allowed_way_ids=c2_way_ids,
    )
    b_graph = build_graph(
        b_elements,
        nodes,
        allowed_way_ids=b_way_ids,
    )
    kasai_graph = build_graph(
        kasai_elements,
        nodes,
        allowed_way_ids=None,
    )

    segments = [
        make_segment(
            identifier="c2.outer.tomigaya-to-kasai",
            route_shield="C2",
            graph=c2_graph,
            checkpoints=C2_NORTH_EAST_CHECKPOINTS,
            nodes=nodes,
        ),
        make_segment(
            identifier="movement.kasai.c2-outer-to-b-west",
            route_shield="C2→B",
            graph=kasai_graph,
            checkpoints=KASAI_TRANSITION_CHECKPOINTS,
            nodes=nodes,
        ),
        make_segment(
            identifier="b.west.kasai-to-oi",
            route_shield="B",
            graph=b_graph,
            checkpoints=B_WEST_CHECKPOINTS,
            nodes=nodes,
        ),
        make_segment(
            identifier="c2.outer.oi-to-hatsudai-minami",
            route_shield="C2",
            graph=c2_graph,
            checkpoints=C2_YAMATE_CHECKPOINTS,
            nodes=nodes,
        ),
    ]

    entry_distance = haversine_meters(
        TOMIGAYA,
        nodes[C2_NORTH_EAST_CHECKPOINTS[0]],
    )
    exit_distance = haversine_meters(
        nodes[C2_YAMATE_CHECKPOINTS[-1]],
        HATSUDAI_MINAMI,
    )
    if entry_distance > 25 or exit_distance > 25:
        raise ValueError(
            "official facility-to-OSM boundary distance exceeds 25 meters"
        )

    output = {
        "schema_version": "1.0",
        "database_id": "kaido.c2-b-geographic-route.2026-07-29",
        "verification_state": "GEOMETRY_CANDIDATE_DIRECTION_REVIEWED",
        "checked_at": "2026-07-29",
        "licence": {
            "identifier": "ODbL-1.0",
            "attribution": "© OpenStreetMap contributors",
            "source_url": "https://www.openstreetmap.org/copyright",
            "licence_url": "https://opendatacommons.org/licenses/odbl/1-0/",
        },
        "sources": [
            {
                "role": "C2_GEOMETRY",
                "relation_id": C2_RELATION_ID,
                "relation_version": C2_RELATION_VERSION,
                "api_url": (
                    "https://api.openstreetmap.org/api/0.6/"
                    f"relation/{C2_RELATION_ID}/full.json"
                ),
                "input_sha256": c2_sha256,
            },
            {
                "role": "B_GEOMETRY",
                "relation_id": B_RELATION_ID,
                "relation_version": B_RELATION_VERSION,
                "api_url": (
                    "https://api.openstreetmap.org/api/0.6/"
                    f"relation/{B_RELATION_ID}/full.json"
                ),
                "input_sha256": b_sha256,
            },
            {
                "role": "KASAI_MOVEMENT_GEOMETRY",
                "api_url": (
                    "https://api.openstreetmap.org/api/0.6/map.json?"
                    "bbox=139.8460,35.6410,139.8620,35.6560"
                ),
                "input_sha256": kasai_sha256,
            },
        ],
        "operator_facilities": {
            "entrance": {
                "facility_id": "shutoko.entrance.tomigaya.c2.outer",
                "coordinate": {
                    "latitude": TOMIGAYA[0],
                    "longitude": TOMIGAYA[1],
                },
                "source_url": (
                    "https://www.shutoko.jp/use/network/map/"
                    "route-c2/tomigaya/"
                ),
                "osm_boundary_distance_meters": round(entry_distance, 3),
            },
            "exit": {
                "facility_id": "shutoko.exit.hatsudai-minami.c2.outer",
                "coordinate": {
                    "latitude": HATSUDAI_MINAMI[0],
                    "longitude": HATSUDAI_MINAMI[1],
                },
                "source_url": (
                    "https://www.shutoko.jp/use/network/map/"
                    "route-c2/hatsudaiminami/"
                ),
                "osm_boundary_distance_meters": round(exit_distance, 3),
            },
        },
        "segments": segments,
        "total_distance_meters": round(
            sum(segment["distance_meters"] for segment in segments),
            3,
        ),
        "limitations": [
            "OSM supplies geometry only and never authorizes RoutePlan movement.",
            "Official operator sources establish directional facilities and branch semantics.",
            "This database does not prove live position, traffic, toll, or field reliability.",
        ],
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True)
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
