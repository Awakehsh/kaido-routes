#!/usr/bin/env python3
"""Build deterministic K7 navigation-semantic Atlas and navigation drafts."""

from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import json
import math
import os
from pathlib import Path
import sys
import tempfile
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DATABASE_PATH = (
    REPOSITORY_ROOT
    / "data/route-atlas/osm-derived/"
    "k7-northwest-260721-directed-database.json"
)
ATLAS_V1_PATH = (
    REPOSITORY_ROOT
    / "data/route-atlas/releases/"
    "k7-northwest-up-aoba-to-kohoku-route-atlas-release.json"
)
DEFAULT_ATLAS_DRAFT_PATH = (
    REPOSITORY_ROOT
    / "data/route-atlas/releases/"
    "k7-northwest-up-aoba-to-kohoku-navigation-semantic-"
    "route-atlas-release-draft.json"
)
DEFAULT_NAVIGATION_DRAFT_PATH = (
    REPOSITORY_ROOT
    / "data/navigation/releases/"
    "k7-northwest-up-aoba-to-kohoku-navigation-release-draft.json"
)
DEFAULT_REVIEW_PACKET_PATH = (
    REPOSITORY_ROOT
    / "data/navigation/candidates/"
    "k7-northwest-up-aoba-to-kohoku-navigation-review-packet.json"
)

EXPECTED_DATABASE_SHA256 = (
    "f3b84117a6aec2c016ad9a3f362bd666e7ff1bd93a873e571398dbb517a21ef2"
)
EXPECTED_ATLAS_V1_SHA256 = (
    "ddf292769c3bb3cf13d3ac9d23ef36cb0c8a03ff471701ae9a9b05af4edc3d4a"
)
EXPECTED_ROUTE_WAY_IDS = [
    574920138,
    692426107,
    692426101,
    850400096,
    692755609,
    692798735,
    686983570,
    782596968,
    915062290,
    686983572,
    783581372,
    734299101,
    734299106,
]
ENTRY_TRANSITION_WAY_IDS = [574920138, 692426107]
ROUTE_PARTITIONS = [
    [692426101, 850400096, 692755609, 692798735],
    [686983570],
    [782596968, 915062290],
    [686983572],
    [783581372, 734299101, 734299106],
]
ALTERNATIVE_WAY_IDS = [686983567, 367046943]

SNAPSHOT_ID = "shutoko.candidate.osm-geofabrik-kanto-260721.k7-northwest"
ROUTE_PLAN_ID = "shutoko.plan.k7-northwest.aoba-up-to-kohoku-up.navigation-v1"
ENTRY_FACILITY_ID = "shutoko.entrance.yokohama-aoba.k7-northwest.up"
EXIT_FACILITY_ID = "shutoko.exit.yokohama-kohoku.k7-northwest.up"
TOLL_DOMAIN_ID = "shutoko.toll-domain"

EDGE_A_ID = "shutoko.edge.k7-northwest.aoba-entry-to-kohoku-shared-branch.up"
MOVEMENT_A_ID = (
    "shutoko.movement.kohoku.k7-up-to-daisan-keihin-and-kohoku-exit"
)
EDGE_B_ID = "shutoko.edge.kohoku.shared-branch-to-exit-branch.up"
MOVEMENT_B_ID = "shutoko.movement.kohoku.shared-branch-to-kohoku-exit.up"
EDGE_C_ID = "shutoko.edge.kohoku-exit-ramp-to-directional-handoff.up"

OCCURRENCE_IDS = [
    "shutoko.occurrence.k7-navigation.aoba-to-kohoku.approach.0",
    "shutoko.occurrence.k7-navigation.aoba-to-kohoku.shared-branch.1",
    "shutoko.occurrence.k7-navigation.aoba-to-kohoku.shared-corridor.2",
    "shutoko.occurrence.k7-navigation.aoba-to-kohoku.exit-branch.3",
    "shutoko.occurrence.k7-navigation.aoba-to-kohoku.exit-ramp.4",
]
ENTITY_IDS = [EDGE_A_ID, MOVEMENT_A_ID, EDGE_B_ID, MOVEMENT_B_ID, EDGE_C_ID]
KINDS = ["EDGE", "JUNCTION_MOVEMENT", "EDGE", "JUNCTION_MOVEMENT", "EDGE"]

TOPOLOGY_ID = "shutoko.topology.k7-northwest.navigation-semantic.2026-07-27"
ATLAS_ID = "shutoko.atlas.k7-northwest.navigation-semantic.2026-07-27"
EDITOR_CATALOG_ID = "shutoko.editor-catalog.k7-aoba-to-kohoku.navigation-v1"
PRESENTATION_CATALOG_ID = (
    "shutoko.editor-presentation.k7-aoba-to-kohoku.navigation-v1"
)
RUNTIME_POLICY_ID = "shutoko.runtime-policy.k7-aoba-to-kohoku.navigation-v1"
MATCHER_CORRIDOR_ID = "shutoko.matcher-corridor.k7-aoba-to-kohoku.navigation-v1"


class CandidateBuildError(ValueError):
    """Raised when pinned inputs cannot produce the exact reviewed drafts."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--atlas-draft", type=Path, default=DEFAULT_ATLAS_DRAFT_PATH)
    parser.add_argument(
        "--navigation-draft",
        type=Path,
        default=DEFAULT_NAVIGATION_DRAFT_PATH,
    )
    parser.add_argument(
        "--review-packet",
        type=Path,
        default=DEFAULT_REVIEW_PACKET_PATH,
    )
    return parser.parse_args()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def load_pinned(path: Path, expected_sha256: str) -> dict[str, Any]:
    try:
        encoded = path.read_bytes()
        value = json.loads(encoded)
    except (OSError, json.JSONDecodeError) as error:
        raise CandidateBuildError(f"cannot read {path}: {error}") from error
    if sha256_bytes(encoded) != expected_sha256:
        raise CandidateBuildError(f"pinned input hash drifted: {path}")
    if not isinstance(value, dict):
        raise CandidateBuildError(f"{path} must contain one JSON object")
    return value


def encoded_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")


def directed_edge_id(way_id: int) -> str:
    return f"shutoko.edge.osm-way.{way_id}.forward"


def old_topology_edge_id(way_id: int) -> str:
    return f"shutoko.topology-edge.osm-way.{way_id}.forward"


def old_segment_id(way_id: int) -> str:
    return f"shutoko.schematic-segment.osm-way.{way_id}.forward"


def semantic_topology_edge_id(entity_id: str) -> str:
    return entity_id.replace("shutoko.", "shutoko.topology-", 1)


def semantic_segment_id(entity_id: str) -> str:
    return entity_id.replace("shutoko.", "shutoko.schematic-", 1)


def haversine_meters(
    lhs: tuple[float, float],
    rhs: tuple[float, float],
) -> float:
    earth_radius_meters = 6_371_008.8
    lhs_latitude, lhs_longitude = map(math.radians, lhs)
    rhs_latitude, rhs_longitude = map(math.radians, rhs)
    latitude_delta = rhs_latitude - lhs_latitude
    longitude_delta = rhs_longitude - lhs_longitude
    haversine = (
        math.sin(latitude_delta / 2) ** 2
        + math.cos(lhs_latitude)
        * math.cos(rhs_latitude)
        * math.sin(longitude_delta / 2) ** 2
    )
    return 2 * earth_radius_meters * math.asin(math.sqrt(haversine))


def build(
    database: dict[str, Any],
    atlas_v1: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    validate_inputs(database, atlas_v1)
    nodes = {node["id"]: node for node in database["nodes"]}
    ways = {way["id"]: way for way in database["ways"]}
    old_segments = {
        segment["segment_id"]: segment
        for segment in atlas_v1["definition"]["segments"]
    }
    old_layout_nodes = {
        node["topology_node_id"]: node
        for node in atlas_v1["definition"]["nodes"]
    }

    route_plan = build_route_plan(nodes, ways)
    atlas_draft = build_atlas_draft(
        atlas_v1,
        route_plan,
        old_segments,
        old_layout_nodes,
    )
    navigation_draft = build_navigation_draft(
        database,
        atlas_v1,
        route_plan,
        nodes,
        ways,
    )
    review_packet = build_review_packet(
        route_plan,
        atlas_draft,
        navigation_draft,
    )
    return atlas_draft, navigation_draft, review_packet


def validate_inputs(database: dict[str, Any], atlas_v1: dict[str, Any]) -> None:
    if database.get("database_id") != (
        "osm.geofabrik.kanto-260721.k7-northwest-directed"
    ):
        raise CandidateBuildError("directed database identity drifted")
    route = database.get("route", {})
    if route.get("way_ids") != EXPECTED_ROUTE_WAY_IDS:
        raise CandidateBuildError("directed route way sequence drifted")
    if route.get("entry_facility_id") != ENTRY_FACILITY_ID:
        raise CandidateBuildError("entry facility identity drifted")
    if route.get("exit_facility_id") != EXIT_FACILITY_ID:
        raise CandidateBuildError("exit facility identity drifted")
    if atlas_v1.get("network_snapshot", {}).get("id") != SNAPSHOT_ID:
        raise CandidateBuildError("Atlas v1 snapshot identity drifted")
    if atlas_v1.get("topology_slice", {}).get("evidence", {}).get("state") != (
        "RELEASED"
    ):
        raise CandidateBuildError("Atlas v1 topology is not released")
    if atlas_v1.get("definition", {}).get("evidence", {}).get("state") != (
        "RELEASED"
    ):
        raise CandidateBuildError("Atlas v1 layout is not released")


def coordinates_for_way(
    way_id: int,
    ways: dict[int, dict[str, Any]],
    nodes: dict[int, dict[str, Any]],
) -> list[dict[str, float]]:
    try:
        way = ways[way_id]
        return [
            {
                "latitude": nodes[node_id]["lat"],
                "longitude": nodes[node_id]["lon"],
            }
            for node_id in way["nodes"]
        ]
    except KeyError as error:
        raise CandidateBuildError(
            f"missing geometry for OSM way {way_id}: {error}"
        ) from error


def concatenate(values: list[list[dict[str, float]]]) -> list[dict[str, float]]:
    result: list[dict[str, float]] = []
    for value in values:
        if result and value and result[-1] == value[0]:
            result.extend(value[1:])
        else:
            result.extend(value)
    return result


def build_route_plan(
    nodes: dict[int, dict[str, Any]],
    ways: dict[int, dict[str, Any]],
) -> dict[str, Any]:
    distance_meters = 0.0
    for partition in ROUTE_PARTITIONS:
        for way_id in partition:
            coordinates = coordinates_for_way(way_id, ways, nodes)
            distance_meters += sum(
                haversine_meters(
                    (lhs["latitude"], lhs["longitude"]),
                    (rhs["latitude"], rhs["longitude"]),
                )
                for lhs, rhs in zip(coordinates, coordinates[1:])
            )
    return {
        "plan_id": ROUTE_PLAN_ID,
        "network_snapshot_id": SNAPSHOT_ID,
        "entry_facility_id": ENTRY_FACILITY_ID,
        "exit_facility_id": EXIT_FACILITY_ID,
        "recovery_policy": "STRICT",
        "actual_distance_km": round(distance_meters / 1000, 9),
        "occurrences": [
            {
                "occurrence_id": occurrence_id,
                "index": index,
                "kind": KINDS[index],
                "entity_id": ENTITY_IDS[index],
                "toll_domain_id": TOLL_DOMAIN_ID,
            }
            for index, occurrence_id in enumerate(OCCURRENCE_IDS)
        ],
    }


def concatenate_old_segment_points(
    partition: list[int],
    old_segments: dict[str, dict[str, Any]],
) -> list[dict[str, float]]:
    values = [deepcopy(old_segments[old_segment_id(way_id)]["points"]) for way_id in partition]
    return concatenate(values)


def build_atlas_draft(
    atlas_v1: dict[str, Any],
    route_plan: dict[str, Any],
    old_segments: dict[str, dict[str, Any]],
    old_layout_nodes: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    endpoint_pairs = [
        ("osm.node.6441357525", "osm.node.6988179578"),
        ("osm.node.6988179578", "osm.node.7299284526"),
        ("osm.node.7299284526", "osm.node.4435202077"),
        ("osm.node.4435202077", "osm.node.7308295746"),
        ("osm.node.7308295746", "osm.node.7473451738"),
    ]
    selected_topology_ids = [
        semantic_topology_edge_id(entity_id) for entity_id in ENTITY_IDS
    ]
    selected_segment_ids = [semantic_segment_id(entity_id) for entity_id in ENTITY_IDS]
    alternative_topology_ids = [
        old_topology_edge_id(way_id) for way_id in ALTERNATIVE_WAY_IDS
    ]
    alternative_segment_ids = [old_segment_id(way_id) for way_id in ALTERNATIVE_WAY_IDS]
    successor_indexes = [[1, "alt0"], [2], [3, "alt1"], [4], []]
    topology_edges: list[dict[str, Any]] = []
    segments: list[dict[str, Any]] = []
    for index, entity_id in enumerate(ENTITY_IDS):
        successor_topology_ids = [
            (
                alternative_topology_ids[int(value.removeprefix("alt"))]
                if isinstance(value, str)
                else selected_topology_ids[value]
            )
            for value in successor_indexes[index]
        ]
        successor_segment_ids = [
            (
                alternative_segment_ids[int(value.removeprefix("alt"))]
                if isinstance(value, str)
                else selected_segment_ids[value]
            )
            for value in successor_indexes[index]
        ]
        from_node_id, to_node_id = endpoint_pairs[index]
        topology_edges.append(
            {
                "edge_id": selected_topology_ids[index],
                "from_node_id": from_node_id,
                "to_node_id": to_node_id,
                "route_entity_id": entity_id,
                "successor_edge_ids": successor_topology_ids,
            }
        )
        segments.append(
            {
                "segment_id": selected_segment_ids[index],
                "topology_edge_id": selected_topology_ids[index],
                "from_node_id": from_node_id,
                "to_node_id": to_node_id,
                "points": concatenate_old_segment_points(
                    ROUTE_PARTITIONS[index],
                    old_segments,
                ),
                "successor_segment_ids": successor_segment_ids,
            }
        )

    for alternative_index, way_id in enumerate(ALTERNATIVE_WAY_IDS):
        old_topology = next(
            edge
            for edge in atlas_v1["topology_slice"]["edges"]
            if edge["edge_id"] == alternative_topology_ids[alternative_index]
        )
        topology_edges.append(deepcopy(old_topology))
        segments.append(deepcopy(old_segments[alternative_segment_ids[alternative_index]]))

    node_ids = sorted(
        {
            value
            for edge in topology_edges
            for value in (edge["from_node_id"], edge["to_node_id"])
        }
    )
    return {
        "schema_version": "1.0",
        "network_snapshot": deepcopy(atlas_v1["network_snapshot"]),
        "route_plan": deepcopy(route_plan),
        "topology_slice": {
            "topology_slice_id": TOPOLOGY_ID,
            "network_snapshot_id": SNAPSHOT_ID,
            "nodes": [{"node_id": node_id} for node_id in node_ids],
            "edges": topology_edges,
        },
        "definition": {
            "atlas_id": ATLAS_ID,
            "network_snapshot_id": SNAPSHOT_ID,
            "route_plan_id": ROUTE_PLAN_ID,
            "topology_slice_id": TOPOLOGY_ID,
            "nodes": [deepcopy(old_layout_nodes[node_id]) for node_id in node_ids],
            "segments": segments,
            "occurrence_bindings": [
                {
                    "occurrence_id": OCCURRENCE_IDS[index],
                    "occurrence_index": index,
                    "segment_id": selected_segment_ids[index],
                }
                for index in range(len(OCCURRENCE_IDS))
            ],
        },
    }


def matcher_edge(
    edge_id: str,
    coordinates: list[dict[str, float]],
    successors: list[str],
) -> dict[str, Any]:
    return {
        "directed_edge_id": edge_id,
        "coordinates": coordinates,
        "successor_edge_ids": successors,
    }


def localized_text(japanese: str, chinese: str, english: str) -> dict[str, str]:
    return {"ja-JP": japanese, "zh-Hans": chinese, "en": english}


def localized_guidance(
    display: tuple[str, str, str],
    spoken: tuple[str, str, str],
    sign_text: str,
) -> dict[str, Any]:
    locales = ["ja-JP", "zh-Hans", "en"]
    spoken_forms = [
        {"K7": "ケーセブン"},
        {"K7": "首都高速神奈川七号横滨西北线"},
        {"K7": "Shuto Expressway Route K7"},
    ]
    return {
        locale: {
            "display_text": display[index],
            "spoken_text": spoken[index],
            "spoken_forms": spoken_forms[index],
            "preserved_japanese_sign_text": sign_text,
        }
        for index, locale in enumerate(locales)
    }


def guidance_definition(
    *,
    anchor_occurrence_id: str,
    anchor_id: str,
    prompt_id: str,
    movement_occurrence_id: str,
    decision_zone_id: str,
    trigger_distance_meters: float,
    decision_names: tuple[str, str, str],
    maneuver: str,
    lane_preparation: str,
    sign_text: str,
    display: tuple[str, str, str],
    spoken: tuple[str, str, str],
) -> dict[str, Any]:
    return {
        "anchor": {
            "occurrence_id": anchor_occurrence_id,
            "anchor_id": anchor_id,
            "prompt_id": prompt_id,
        },
        "trigger_distance_meters": trigger_distance_meters,
        "frame_template": {
            "movement_occurrence_id": movement_occurrence_id,
            "decision_zone_id": decision_zone_id,
            "stage": "PREPARE",
            "decision_point_name_ja": decision_names[0],
            "localized_decision_point_names": localized_text(*decision_names),
            "maneuver": maneuver,
            "lane_preparation": lane_preparation,
            "presentation_source": {
                "route_shields": ["K7"],
                "japanese_sign_text": sign_text,
                "localized_content": localized_guidance(
                    display,
                    spoken,
                    sign_text,
                ),
            },
        },
    }


def build_navigation_draft(
    database: dict[str, Any],
    atlas_v1: dict[str, Any],
    route_plan: dict[str, Any],
    nodes: dict[int, dict[str, Any]],
    ways: dict[int, dict[str, Any]],
) -> dict[str, Any]:
    route_matcher_ids = [
        EDGE_A_ID,
        directed_edge_id(686983570),
        EDGE_B_ID,
        directed_edge_id(686983572),
        EDGE_C_ID,
    ]
    entry_matcher_ids = [directed_edge_id(value) for value in ENTRY_TRANSITION_WAY_IDS]
    alternative_matcher_ids = [directed_edge_id(value) for value in ALTERNATIVE_WAY_IDS]
    route_coordinates = [
        concatenate(
            [coordinates_for_way(way_id, ways, nodes) for way_id in partition]
        )
        for partition in ROUTE_PARTITIONS
    ]
    matcher_edges = [
        matcher_edge(
            entry_matcher_ids[0],
            coordinates_for_way(ENTRY_TRANSITION_WAY_IDS[0], ways, nodes),
            [entry_matcher_ids[1]],
        ),
        matcher_edge(
            entry_matcher_ids[1],
            coordinates_for_way(ENTRY_TRANSITION_WAY_IDS[1], ways, nodes),
            [route_matcher_ids[0]],
        ),
        matcher_edge(
            route_matcher_ids[0],
            route_coordinates[0],
            [route_matcher_ids[1], alternative_matcher_ids[0]],
        ),
        matcher_edge(route_matcher_ids[1], route_coordinates[1], [route_matcher_ids[2]]),
        matcher_edge(
            route_matcher_ids[2],
            route_coordinates[2],
            [route_matcher_ids[3], alternative_matcher_ids[1]],
        ),
        matcher_edge(route_matcher_ids[3], route_coordinates[3], [route_matcher_ids[4]]),
        matcher_edge(route_matcher_ids[4], route_coordinates[4], []),
        matcher_edge(
            alternative_matcher_ids[0],
            coordinates_for_way(ALTERNATIVE_WAY_IDS[0], ways, nodes),
            [],
        ),
        matcher_edge(
            alternative_matcher_ids[1],
            coordinates_for_way(ALTERNATIVE_WAY_IDS[1], ways, nodes),
            [],
        ),
    ]

    first_decision_id = "shutoko.decision.kohoku.k7-up-shared-branch"
    second_decision_id = "shutoko.decision.kohoku.shared-corridor-exit-branch"
    first_choice_id = "shutoko.choice.kohoku.k7-up-to-shared-exit-corridor"
    second_choice_id = "shutoko.choice.kohoku.shared-corridor-to-exit"
    first_zone_id = "shutoko.decision-zone.kohoku.k7-up-shared-branch.v1"
    second_zone_id = "shutoko.decision-zone.kohoku.exit-left-branch.v1"
    first_prompt_id = "shutoko.guidance.kohoku.k7-up-shared-branch.prepare.v1"
    second_prompt_id = "shutoko.guidance.kohoku.exit-left-branch.prepare.v1"

    return {
        "schema_version": "1.0",
        "editor_catalog_id": EDITOR_CATALOG_ID,
        "network_snapshot": deepcopy(atlas_v1["network_snapshot"]),
        "route_plan": deepcopy(route_plan),
        "editor_catalog": {
            "network_snapshot_id": SNAPSHOT_ID,
            "entrances": [
                {
                    "facility_id": ENTRY_FACILITY_ID,
                    "initial_edge_id": EDGE_A_ID,
                    "initial_edge_toll_domain_id": TOLL_DOMAIN_ID,
                    "first_decision_point_id": first_decision_id,
                }
            ],
            "decision_points": [
                {
                    "decision_point_id": first_decision_id,
                    "incoming_approach_id": EDGE_A_ID,
                    "junction_complex_id": "shutoko.junction.yokohama-kohoku",
                    "choices": [
                        {
                            "choice_id": first_choice_id,
                            "movement_id": MOVEMENT_A_ID,
                            "movement_toll_domain_id": TOLL_DOMAIN_ID,
                            "outgoing_edge_id": EDGE_B_ID,
                            "outgoing_edge_toll_domain_id": TOLL_DOMAIN_ID,
                            "destination": {"decision_point_id": second_decision_id},
                        }
                    ],
                },
                {
                    "decision_point_id": second_decision_id,
                    "incoming_approach_id": EDGE_B_ID,
                    "junction_complex_id": "shutoko.junction.yokohama-kohoku",
                    "choices": [
                        {
                            "choice_id": second_choice_id,
                            "movement_id": MOVEMENT_B_ID,
                            "movement_toll_domain_id": TOLL_DOMAIN_ID,
                            "outgoing_edge_id": EDGE_C_ID,
                            "outgoing_edge_toll_domain_id": TOLL_DOMAIN_ID,
                            "destination": {"exit_facility_id": EXIT_FACILITY_ID},
                        }
                    ],
                },
            ],
            "lap_templates": [],
        },
        "editor_presentation_catalog": {
            "presentation_catalog_id": PRESENTATION_CATALOG_ID,
            "network_snapshot_id": SNAPSHOT_ID,
            "entrances": [
                {
                    "facility_id": ENTRY_FACILITY_ID,
                    "title": localized_text(
                        "横浜青葉入口（K7上り）",
                        "横滨青叶入口（K7 上行）",
                        "Yokohama Aoba Entrance (K7 up)",
                    ),
                }
            ],
            "decision_points": [
                {
                    "decision_point_id": first_decision_id,
                    "title": localized_text(
                        "横浜港北JCT 第三京浜・出口分岐",
                        "横滨港北 JCT 第三京滨・出口分岔",
                        "Yokohama Kohoku JCT Daisan-Keihin / exit branch",
                    ),
                },
                {
                    "decision_point_id": second_decision_id,
                    "title": localized_text(
                        "横浜港北出口分岐",
                        "横滨港北出口分岔",
                        "Yokohama Kohoku Exit branch",
                    ),
                },
            ],
            "choices": [
                {
                    "choice_id": first_choice_id,
                    "title": localized_text(
                        "第三京浜・横浜港北出口へ",
                        "驶向第三京滨・横滨港北出口",
                        "Toward Daisan-Keihin / Yokohama Kohoku Exit",
                    ),
                    "detail": localized_text(
                        "K7上りから左へ分岐",
                        "从 K7 上行在左侧分岔",
                        "Branch left from K7 up",
                    ),
                },
                {
                    "choice_id": second_choice_id,
                    "title": localized_text(
                        "横浜港北出口へ",
                        "驶向横滨港北出口",
                        "Take Yokohama Kohoku Exit",
                    ),
                    "detail": localized_text(
                        "第三京浜直進ではなく左へ分岐",
                        "不要直行第三京滨，在左侧分岔",
                        "Branch left instead of continuing to Daisan-Keihin",
                    ),
                },
            ],
        },
        "runtime_policy": {
            "runtime_policy_id": RUNTIME_POLICY_ID,
            "network_snapshot_id": SNAPSHOT_ID,
            "route_plan_id": ROUTE_PLAN_ID,
            "entry_transition": {
                "facility_id": ENTRY_FACILITY_ID,
                "directed_edge_ids": entry_matcher_ids,
                "first_route_occurrence_id": OCCURRENCE_IDS[0],
            },
            "recovery_candidates": [],
            "egress_options": [
                {
                    "egress_option_id": (
                        "shutoko.egress.kohoku.directional-exit-handoff.v1"
                    ),
                    "first_eligible_occurrence_id": OCCURRENCE_IDS[3],
                    "exit_facility_id": EXIT_FACILITY_ID,
                    "egress_occurrence_ids": [OCCURRENCE_IDS[3], OCCURRENCE_IDS[4]],
                    "released": True,
                }
            ],
        },
        "matcher_corridor": {
            "corridor_id": MATCHER_CORRIDOR_ID,
            "network_snapshot_id": SNAPSHOT_ID,
            "route_plan_id": ROUTE_PLAN_ID,
            "edges": matcher_edges,
            "occurrences": [
                {
                    "occurrence_id": OCCURRENCE_IDS[index],
                    "index": index,
                    "directed_edge_id": route_matcher_ids[index],
                }
                for index in range(len(OCCURRENCE_IDS))
            ],
        },
        "decision_zones": [
            {
                "decision_zone_id": first_zone_id,
                "network_snapshot_id": SNAPSHOT_ID,
                "route_plan_id": ROUTE_PLAN_ID,
                "movement_occurrence_id": OCCURRENCE_IDS[1],
                "entry_offset_meters": 0,
            },
            {
                "decision_zone_id": second_zone_id,
                "network_snapshot_id": SNAPSHOT_ID,
                "route_plan_id": ROUTE_PLAN_ID,
                "movement_occurrence_id": OCCURRENCE_IDS[3],
                "entry_offset_meters": 0,
            },
        ],
        "released_guidance": [
            guidance_definition(
                anchor_occurrence_id=OCCURRENCE_IDS[0],
                anchor_id="PREPARE",
                prompt_id=first_prompt_id,
                movement_occurrence_id=OCCURRENCE_IDS[1],
                decision_zone_id=first_zone_id,
                trigger_distance_meters=400,
                decision_names=(
                    "横浜港北JCT 第三京浜・出口分岐",
                    "横滨港北 JCT 第三京滨・出口分岔",
                    "Yokohama Kohoku JCT Daisan-Keihin / exit branch",
                ),
                maneuver="TAKE_EXIT_LEFT",
                lane_preparation="USE_LEFT_LANES",
                sign_text="第三京浜・出口へ",
                display=(
                    "第三京浜・横浜港北出口方面へ左分岐",
                    "左侧分岔驶向第三京滨・横滨港北出口",
                    "Branch left for Daisan-Keihin / Yokohama Kohoku Exit",
                ),
                spoken=(
                    "左に分岐して、第三京浜と横浜港北出口方面へ進んでください",
                    "请从左侧分岔，驶向第三京滨和横滨港北出口方向",
                    "Take the left branch for Daisan-Keihin and Yokohama Kohoku Exit",
                ),
            ),
            guidance_definition(
                anchor_occurrence_id=OCCURRENCE_IDS[2],
                anchor_id="PREPARE",
                prompt_id=second_prompt_id,
                movement_occurrence_id=OCCURRENCE_IDS[3],
                decision_zone_id=second_zone_id,
                trigger_distance_meters=250,
                decision_names=(
                    "横浜港北出口分岐",
                    "横滨港北出口分岔",
                    "Yokohama Kohoku Exit branch",
                ),
                maneuver="TAKE_EXIT_LEFT",
                lane_preparation="USE_LEFT_LANES",
                sign_text="出口へ",
                display=(
                    "横浜港北出口へ左分岐",
                    "左侧分岔驶向横滨港北出口",
                    "Branch left for Yokohama Kohoku Exit",
                ),
                spoken=(
                    "左に分岐して、横浜港北出口へ進んでください",
                    "请从左侧分岔，驶向横滨港北出口",
                    "Take the left branch for Yokohama Kohoku Exit",
                ),
            ),
        ],
        "junction_views": [],
    }


def build_review_packet(
    route_plan: dict[str, Any],
    atlas_draft: dict[str, Any],
    navigation_draft: dict[str, Any],
) -> dict[str, Any]:
    atlas_bytes = encoded_json(atlas_draft)
    navigation_bytes = encoded_json(navigation_draft)
    return {
        "schema_version": "1.0",
        "candidate_id": "k7-aoba-to-kohoku-navigation-v1",
        "prepared_at": "2026-07-27",
        "input_bindings": {
            "directed_database": {
                "path": str(DATABASE_PATH.relative_to(REPOSITORY_ROOT)),
                "sha256": EXPECTED_DATABASE_SHA256,
            },
            "route_atlas_v1": {
                "path": str(ATLAS_V1_PATH.relative_to(REPOSITORY_ROOT)),
                "sha256": EXPECTED_ATLAS_V1_SHA256,
            },
        },
        "candidate_bindings": {
            "atlas_draft_sha256": sha256_bytes(atlas_bytes),
            "navigation_draft_sha256": sha256_bytes(navigation_bytes),
            "network_snapshot_id": SNAPSHOT_ID,
            "route_plan_id": ROUTE_PLAN_ID,
            "actual_distance_km": route_plan["actual_distance_km"],
            "occurrence_ids": OCCURRENCE_IDS,
        },
        "review_scopes": {
            "topology": [
                "EntryTransition ends at the first strict-route occurrence.",
                "The five semantic occurrences preserve the exact selected OSM way order.",
                "The two non-selected expressway alternatives remain explicit and non-authoring.",
                "The terminal node excludes every ordinary-road successor.",
            ],
            "layout": [
                "Every v2 segment is an exact concatenation of released v1 segment points.",
                "Every topology node and edge has exactly one layout binding.",
                "No coordinate contact creates a legal successor.",
            ],
            "navigation_guidance": [
                "Editor choices compile the exact five-occurrence RoutePlan.",
                "Matcher geometry retains complete OSM nodes and both branch alternatives.",
                "DecisionZone entry offset zero denotes the exact branch node.",
                "Guidance preserves Japanese sign text and K7 in every locale.",
                "The first action branches left from K7; the second takes the left exit branch.",
            ],
        },
        "primary_sources": [
            {
                "source_reference_id": "shutoko.guide.k7-aoba.2026-07-23",
                "scope": "directional Yokohama Aoba K7 entrance",
            },
            {
                "source_reference_id": "shutoko.guide.k7-kohoku.2026-07-23",
                "scope": "K7 up shared branch and Yokohama Kohoku exit-left movement",
            },
            {
                "source_reference_id": "shutoko.k7-opening-attachment.2019-09-26",
                "scope": "K7 Aoba-to-Kohoku route identity and approximate line length",
            },
            {
                "source_reference_id": "osm.geofabrik.kanto-260721.k7-directed",
                "scope": "directed geometry, node identity, and branch alternatives",
            },
        ],
        "release_boundaries": [
            "No realtime passage claim.",
            "No ordinary-road or SURFACE_EGRESS release.",
            "No field matcher reliability claim.",
            "No pronunciation, acoustic, background-location, or CarPlay qualification.",
            "Review approval authorizes only the exact hash-bound static assets.",
        ],
        "review_decisions": {
            "topology": "PENDING",
            "layout": "PENDING",
            "navigation_guidance": "PENDING",
        },
    }


def write_new(path: Path, content: bytes) -> None:
    destination = path.resolve()
    if destination.exists():
        raise CandidateBuildError(f"output already exists: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.",
        dir=destination.parent,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            os.fchmod(handle.fileno(), 0o644)
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


def main() -> int:
    arguments = parse_arguments()
    try:
        database = load_pinned(DATABASE_PATH, EXPECTED_DATABASE_SHA256)
        atlas_v1 = load_pinned(ATLAS_V1_PATH, EXPECTED_ATLAS_V1_SHA256)
        atlas_draft, navigation_draft, review_packet = build(database, atlas_v1)
        outputs = [
            (arguments.atlas_draft, encoded_json(atlas_draft)),
            (arguments.navigation_draft, encoded_json(navigation_draft)),
            (arguments.review_packet, encoded_json(review_packet)),
        ]
        if len({path.resolve() for path, _ in outputs}) != len(outputs):
            raise CandidateBuildError("candidate outputs must be different files")
        for path, _ in outputs:
            if path.resolve().exists():
                raise CandidateBuildError(f"output already exists: {path.resolve()}")
        for path, content in outputs:
            write_new(path, content)
    except (OSError, CandidateBuildError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    for path, content in outputs:
        print(f"PASS: wrote {path.resolve()} sha256={sha256_bytes(content)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
