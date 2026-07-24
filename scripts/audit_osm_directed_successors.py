#!/usr/bin/env python3
"""Audit exact directed successors around a bounded OSM RoutePlan candidate."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


EXPECTED_SCHEMA_VERSION = "1.0"
EXPECTED_LICENCE = "ODbL-1.0"
EXPECTED_LICENCE_URL = "https://opendatacommons.org/licenses/odbl/1-0/"
EXPECTED_ATTRIBUTION = "© OpenStreetMap contributors"
EXPECTED_ATTRIBUTION_URL = "https://www.openstreetmap.org/copyright"
MOTOR_ROAD_HIGHWAYS = {
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
FORWARD_ONEWAY_VALUES = {"1", "true", "yes"}
REVERSE_ONEWAY_VALUES = {"-1", "reverse"}
TWO_WAY_VALUES = {"0", "false", "no"}


class SuccessorAuditError(RuntimeError):
    """A fail-closed source-adjacency or review error."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-extract", required=True, type=Path)
    parser.add_argument("--review", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SuccessorAuditError(f"cannot read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise SuccessorAuditError(f"expected a JSON object in {path}")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(value: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def way_registry(
    source_extract: dict[str, Any],
) -> dict[int, dict[str, Any]]:
    values = source_extract.get("ways")
    boundary_values = source_extract.get("boundary_ways")
    if not isinstance(values, list) or not isinstance(boundary_values, list):
        raise SuccessorAuditError(
            "source extract has no ways or endpoint boundary ways"
        )
    ways: dict[int, dict[str, Any]] = {}
    for value in values + boundary_values:
        if (
            not isinstance(value, dict)
            or not isinstance(value.get("id"), int)
            or value["id"] in ways
            or not isinstance(value.get("nodes"), list)
            or len(value["nodes"]) < 2
            or not isinstance(value.get("tags"), dict)
        ):
            raise SuccessorAuditError("source extract contains an invalid way")
        ways[value["id"]] = value
    return ways


def outgoing_directions(
    way: dict[str, Any],
    node_id: int,
) -> list[str]:
    nodes = way["nodes"]
    positions = [index for index, candidate in enumerate(nodes) if candidate == node_id]
    if not positions:
        return []
    if positions not in ([0], [len(nodes) - 1]):
        raise SuccessorAuditError(
            f"way {way['id']} intersects checkpoint node {node_id} "
            "away from one exact endpoint"
        )
    tags = way["tags"]
    highway = tags.get("highway")
    if highway not in MOTOR_ROAD_HIGHWAYS:
        return []
    access_values = {
        str(tags.get(key, "")).lower() for key in ("access", "vehicle", "motor_vehicle")
    }
    if access_values.intersection({"no", "private"}):
        return []
    oneway = str(tags.get("oneway", "")).lower()
    if oneway in FORWARD_ONEWAY_VALUES:
        return ["FORWARD"] if positions == [0] else []
    if oneway in REVERSE_ONEWAY_VALUES:
        return ["REVERSE"] if positions == [len(nodes) - 1] else []
    if oneway not in TWO_WAY_VALUES and oneway:
        raise SuccessorAuditError(
            f"way {way['id']} has unsupported oneway value {oneway!r}"
        )
    if positions == [0]:
        return ["FORWARD"]
    return ["REVERSE"]


def restriction_policy(
    source_extract: dict[str, Any],
    incoming_way_id: int,
    via_node_id: int,
) -> tuple[set[int], set[int], list[int]]:
    forbidden: set[int] = set()
    only: set[int] = set()
    relation_ids: list[int] = []
    relations = source_extract.get("relations")
    if not isinstance(relations, list):
        raise SuccessorAuditError("source extract has no restriction registry")
    for relation in relations:
        if not isinstance(relation, dict):
            raise SuccessorAuditError("invalid restriction relation")
        tags = relation.get("tags")
        members = relation.get("members")
        if not isinstance(tags, dict) or not isinstance(members, list):
            raise SuccessorAuditError("invalid restriction relation")
        from_ids = {
            member.get("ref")
            for member in members
            if member.get("type") == "way" and member.get("role") == "from"
        }
        via_nodes = {
            member.get("ref")
            for member in members
            if member.get("type") == "node" and member.get("role") == "via"
        }
        if incoming_way_id not in from_ids or via_node_id not in via_nodes:
            continue
        if any(
            member.get("role") == "via" and member.get("type") != "node"
            for member in members
        ):
            raise SuccessorAuditError(
                f"restriction {relation.get('id')} uses an unsupported via way"
            )
        restriction = tags.get("restriction")
        if not isinstance(restriction, str) or "restriction:conditional" in tags:
            raise SuccessorAuditError(
                f"restriction {relation.get('id')} is incomplete or conditional"
            )
        to_ids = {
            member.get("ref")
            for member in members
            if member.get("type") == "way" and member.get("role") == "to"
        }
        if len(to_ids) != 1:
            raise SuccessorAuditError(
                f"restriction {relation.get('id')} has no exact to-way"
            )
        relation_ids.append(relation["id"])
        if restriction.startswith("no_"):
            forbidden.update(to_ids)
        elif restriction.startswith("only_"):
            only.update(to_ids)
        else:
            raise SuccessorAuditError(
                f"restriction {relation.get('id')} has unsupported semantics"
            )
    return forbidden, only, sorted(relation_ids)


def expected_checkpoints(
    review: dict[str, Any],
) -> list[dict[str, Any]]:
    route = review.get("route")
    alternatives = review.get("divergence_alternatives")
    boundaries = review.get("facility_boundary_checks")
    if (
        not isinstance(route, dict)
        or not isinstance(route.get("way_ids"), list)
        or not isinstance(alternatives, list)
        or not isinstance(boundaries, dict)
        or not isinstance(
            boundaries.get("exit_surface_successor_way_ids"),
            list,
        )
    ):
        raise SuccessorAuditError("review has no complete successor declaration")
    route_way_ids = route["way_ids"]
    alternative_by_predecessor = {
        alternative["after_way_id"]: alternative for alternative in alternatives
    }
    checkpoints = [
        {
            "checkpoint_id": "entry-choice",
            "incoming_way_id": boundaries["entry_predecessor_way_id"],
            "via_node_id": route["entry_node_id"],
            "expected_successors": [
                {
                    "way_id": route_way_ids[0],
                    "role": "SELECTED_ROUTE",
                },
                {
                    "way_id": boundaries["entry_nonroute_successor_way_id"],
                    "role": "ENTRY_NONROUTE_ALTERNATIVE",
                },
            ],
        }
    ]
    for index, incoming_way_id in enumerate(route_way_ids):
        expected: list[dict[str, Any]] = []
        if index + 1 < len(route_way_ids):
            expected.append(
                {
                    "way_id": route_way_ids[index + 1],
                    "role": "SELECTED_ROUTE",
                }
            )
        else:
            expected.extend(
                {
                    "way_id": way_id,
                    "role": "SURFACE_EGRESS_CANDIDATE",
                }
                for way_id in boundaries["exit_surface_successor_way_ids"]
            )
        alternative = alternative_by_predecessor.get(incoming_way_id)
        if alternative is not None:
            expected.append(
                {
                    "way_id": alternative["way_id"],
                    "role": alternative["role"],
                }
            )
        checkpoints.append(
            {
                "checkpoint_id": f"after-osm-way-{incoming_way_id}",
                "incoming_way_id": incoming_way_id,
                "via_node_id": None,
                "expected_successors": expected,
            }
        )
    return checkpoints


def successor_record(
    way: dict[str, Any],
    direction: str,
    role: str | None = None,
) -> dict[str, Any]:
    tags = way["tags"]
    record: dict[str, Any] = {
        "way_id": way["id"],
        "direction": direction,
        "highway": tags["highway"],
        "oneway": tags.get("oneway", "UNSPECIFIED"),
    }
    if role is not None:
        record["role"] = role
    if isinstance(tags.get("name"), str):
        record["name"] = tags["name"]
    if isinstance(tags.get("ref"), str):
        record["ref"] = tags["ref"]
    return record


def legal_successor_evidence(
    review: dict[str, Any],
    unresolved: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    evidence = review.get("legal_successor_evidence")
    source_references = review.get("source_references")
    if not isinstance(evidence, list) or not isinstance(
        source_references,
        list,
    ):
        raise SuccessorAuditError("legal successor evidence registry is incomplete")
    source_reference_ids = {
        reference.get("source_reference_id")
        for reference in source_references
        if isinstance(reference, dict)
        and isinstance(reference.get("source_reference_id"), str)
    }
    unresolved_keys = {
        (
            item["incoming_way_id"],
            item["via_node_id"],
            item["way_id"],
            item["direction"],
        )
        for item in unresolved
    }
    evidence_keys: set[tuple[int, int, int, str]] = set()
    for item in evidence:
        if not isinstance(item, dict):
            raise SuccessorAuditError(
                "legal successor evidence contains an invalid record"
            )
        key = (
            item.get("incoming_way_id"),
            item.get("via_node_id"),
            item.get("way_id"),
            item.get("direction"),
        )
        if key in evidence_keys or key not in unresolved_keys:
            raise SuccessorAuditError("legal successor evidence identity has drifted")
        road_identity = item.get("road_identity")
        current_area_infrastructure = item.get("current_area_infrastructure")
        current_road_identity = item.get("current_road_identity")
        historical_connection = item.get("historical_planned_exit_connection")
        if (
            item.get("source_adjacency_exact") is not True
            or item.get("current_physical_status") != "UNCONFIRMED"
            or item.get("current_legal_direction") != "UNCONFIRMED"
            or item.get("permitted_exit_movement") != "UNCONFIRMED"
            or item.get("release_eligible") is not False
            or not isinstance(item.get("field_verification_plan_id"), str)
            or not item["field_verification_plan_id"]
            or not isinstance(road_identity, dict)
            or road_identity.get("status") != "OFFICIAL_CHECKED"
            or road_identity.get("classification")
            != "HISTORICAL_LAND_READJUSTMENT_TEMPORARY_PASSAGE"
            or road_identity.get("scope") != "CORRIDOR_AT_2020_OPENING"
            or not isinstance(
                road_identity.get("source_published_at"),
                str,
            )
            or not isinstance(
                road_identity.get("source_reference_ids"),
                list,
            )
            or not road_identity["source_reference_ids"]
            or not set(road_identity["source_reference_ids"]).issubset(
                source_reference_ids
            )
            or not isinstance(current_area_infrastructure, dict)
            or current_area_infrastructure.get("status") != "OFFICIAL_CHECKED"
            or current_area_infrastructure.get("infrastructure_completed_at")
            != "2022-03"
            or current_area_infrastructure.get("project_closed_at") != "2023-07-25"
            or current_area_infrastructure.get("exact_way_identity_status")
            != "UNCONFIRMED"
            or not isinstance(
                current_area_infrastructure.get("source_reference_ids"),
                list,
            )
            or not current_area_infrastructure["source_reference_ids"]
            or not set(current_area_infrastructure["source_reference_ids"]).issubset(
                source_reference_ids
            )
            or not isinstance(current_road_identity, dict)
            or current_road_identity.get("status") != "UNCONFIRMED"
            or current_road_identity.get("classification") != "UNCONFIRMED"
            or not isinstance(
                current_road_identity.get("source_reference_ids"),
                list,
            )
            or not current_road_identity["source_reference_ids"]
            or not set(current_road_identity["source_reference_ids"]).issubset(
                source_reference_ids
            )
            or not isinstance(historical_connection, dict)
            or historical_connection.get("status") != "OFFICIAL_CHECKED_AT_PUBLICATION"
            or not isinstance(
                historical_connection.get("source_published_at"),
                str,
            )
            or not isinstance(
                historical_connection.get("source_reference_ids"),
                list,
            )
            or not historical_connection["source_reference_ids"]
            or not set(historical_connection["source_reference_ids"]).issubset(
                source_reference_ids
            )
        ):
            raise SuccessorAuditError(
                "legal successor evidence must separate historic corridor "
                "identity, current area completion, and unresolved road-level "
                "movement"
            )
        evidence_keys.add(key)
    if evidence_keys != unresolved_keys:
        raise SuccessorAuditError(
            "every unresolved legal successor needs one evidence record"
        )
    return evidence


def build_audit(
    source_extract: dict[str, Any],
    review: dict[str, Any],
    source_extract_sha256: str,
) -> dict[str, Any]:
    source = source_extract.get("source")
    expected_source = review.get("source_extract")
    audit_review = review.get("successor_audit")
    if (
        source_extract.get("schema_version") != EXPECTED_SCHEMA_VERSION
        or not isinstance(source, dict)
        or not isinstance(expected_source, dict)
        or source_extract_sha256 != expected_source.get("expected_extract_sha256")
        or source.get("input_sha256") != expected_source.get("parent_pbf_sha256")
        or source.get("source_snapshot_at") != expected_source.get("source_snapshot_at")
        or not isinstance(audit_review, dict)
        or audit_review.get("state")
        != "SOURCE_ADJACENCY_COMPLETE_LEGAL_REVIEW_INCOMPLETE"
        or audit_review.get("navigation_authority") is not False
    ):
        raise SuccessorAuditError("successor audit source identity has drifted")

    ways = way_registry(source_extract)
    route = review["route"]
    route_way_ids = route["way_ids"]
    checkpoints = expected_checkpoints(review)
    results: list[dict[str, Any]] = []
    restriction_ids: set[int] = set()
    for checkpoint in checkpoints:
        incoming_way_id = checkpoint["incoming_way_id"]
        incoming = ways.get(incoming_way_id)
        if incoming is None:
            raise SuccessorAuditError(f"incoming way {incoming_way_id} is absent")
        via_node_id = checkpoint["via_node_id"]
        if via_node_id is None:
            if incoming_way_id not in route_way_ids:
                raise SuccessorAuditError(
                    f"checkpoint {checkpoint['checkpoint_id']} has no via node"
                )
            via_node_id = incoming["nodes"][-1]
        if via_node_id not in incoming["nodes"]:
            raise SuccessorAuditError(
                f"incoming way {incoming_way_id} misses via node {via_node_id}"
            )

        forbidden, only, checkpoint_restrictions = restriction_policy(
            source_extract,
            incoming_way_id,
            via_node_id,
        )
        restriction_ids.update(checkpoint_restrictions)
        observed: list[dict[str, Any]] = []
        observed_keys: set[tuple[int, str]] = set()
        for way in ways.values():
            if way["id"] == incoming_way_id:
                continue
            for direction in outgoing_directions(way, via_node_id):
                if way["id"] in forbidden:
                    continue
                if only and way["id"] not in only:
                    continue
                key = (way["id"], direction)
                if key in observed_keys:
                    raise SuccessorAuditError(
                        f"duplicate successor {key} at node {via_node_id}"
                    )
                observed_keys.add(key)
                observed.append(successor_record(way, direction))
        observed.sort(key=lambda item: (item["way_id"], item["direction"]))

        expected_records: list[dict[str, Any]] = []
        expected_keys: set[tuple[int, str]] = set()
        for expected in checkpoint["expected_successors"]:
            way = ways.get(expected["way_id"])
            if way is None:
                raise SuccessorAuditError(
                    f"declared successor way {expected['way_id']} is absent"
                )
            directions = outgoing_directions(way, via_node_id)
            if len(directions) != 1:
                raise SuccessorAuditError(
                    f"declared successor way {way['id']} has no exact direction"
                )
            record = successor_record(
                way,
                directions[0],
                expected["role"],
            )
            expected_records.append(record)
            expected_keys.add((way["id"], directions[0]))
        if expected_keys != observed_keys:
            missing = sorted(expected_keys - observed_keys)
            unexpected = sorted(observed_keys - expected_keys)
            raise SuccessorAuditError(
                f"successor mismatch at {checkpoint['checkpoint_id']}: "
                f"missing={missing}, unexpected={unexpected}"
            )
        results.append(
            {
                "checkpoint_id": checkpoint["checkpoint_id"],
                "incoming_way_id": incoming_way_id,
                "via_node_id": via_node_id,
                "declared_successors": expected_records,
                "observed_successors": observed,
                "restriction_relation_ids": checkpoint_restrictions,
                "source_adjacency_exact": True,
            }
        )

    unresolved = audit_review.get("unresolved_legal_successors")
    if not isinstance(unresolved, list) or not unresolved:
        raise SuccessorAuditError(
            "legal review must identify its unresolved successors"
        )
    observed_triplets = {
        (
            result["incoming_way_id"],
            result["via_node_id"],
            successor["way_id"],
            successor["direction"],
        )
        for result in results
        for successor in result["observed_successors"]
    }
    for item in unresolved:
        if (
            not isinstance(item, dict)
            or (
                item.get("incoming_way_id"),
                item.get("via_node_id"),
                item.get("way_id"),
                item.get("direction"),
            )
            not in observed_triplets
            or not isinstance(item.get("reason_code"), str)
            or not item["reason_code"]
        ):
            raise SuccessorAuditError(
                "unresolved legal successor declaration has drifted"
            )
    successor_evidence = legal_successor_evidence(review, unresolved)

    total_successors = sum(len(result["observed_successors"]) for result in results)
    return {
        "schema_version": EXPECTED_SCHEMA_VERSION,
        "audit_id": audit_review["audit_id"],
        "review_id": review["review_id"],
        "network_snapshot_id": review["network_snapshot_id"],
        "route_plan_id": review["route_plan_id"],
        "state": audit_review["state"],
        "navigation_authority": False,
        "licence": EXPECTED_LICENCE,
        "licence_url": EXPECTED_LICENCE_URL,
        "attribution": EXPECTED_ATTRIBUTION,
        "attribution_url": EXPECTED_ATTRIBUTION_URL,
        "source": {
            "bounded_extract_sha256": source_extract_sha256,
            "parent_pbf_sha256": source["input_sha256"],
            "source_snapshot_at": source["source_snapshot_at"],
        },
        "summary": {
            "checkpoint_count": len(results),
            "observed_successor_count": total_successors,
            "restriction_relation_count": len(restriction_ids),
            "source_adjacency_exact": True,
            "legal_review_complete": False,
            "unresolved_legal_successor_count": len(unresolved),
            "historical_road_identity_reviewed_count": sum(
                item["road_identity"]["status"] == "OFFICIAL_CHECKED"
                for item in successor_evidence
            ),
            "current_area_infrastructure_reviewed_count": sum(
                item["current_area_infrastructure"]["status"] == "OFFICIAL_CHECKED"
                for item in successor_evidence
            ),
            "current_road_identity_confirmed_count": sum(
                item["current_road_identity"]["status"] != "UNCONFIRMED"
                for item in successor_evidence
            ),
            "current_legal_direction_confirmed_count": sum(
                item["current_legal_direction"] != "UNCONFIRMED"
                for item in successor_evidence
            ),
            "field_verification_required": True,
        },
        "checkpoints": results,
        "unresolved_legal_successors": unresolved,
        "legal_successor_evidence": successor_evidence,
        "release_blockers": audit_review["release_blockers"],
    }


def build_scenario(
    candidate: dict[str, Any],
    audit: dict[str, Any],
    review: dict[str, Any],
) -> dict[str, Any]:
    definition = json.loads(json.dumps(candidate["definition"]))
    for binding in definition["occurrence_bindings"]:
        binding["index"] = binding.pop("occurrence_index")
    return {
        "schema_version": "1.0",
        "id": "KR-D23",
        "title": ("Completed K7 exit-area works do not prove current legal movement"),
        "layer": "DOMAIN",
        "tags": [
            "route-atlas",
            "k7",
            "successor-audit",
            "release-gate",
        ],
        "purpose": (
            "Prove that exact source adjacency, an official historic corridor "
            "identity, and later area-infrastructure completion cannot "
            "substitute for the exact road's current identity, legal "
            "direction, permitted movement, and production-layout review."
        ),
        "evidence": {
            "classification": "OFFICIAL_CHECKED",
            "sources": [
                {
                    "id": "osm-geofabrik-kanto-260721",
                    "uri": review["source_extract"]["source_url"],
                    "checked_at": review["checked_at"],
                    "supports": (
                        "The pinned ODbL extract enumerates every motor-road "
                        "successor at fourteen route and facility checkpoints."
                    ),
                },
                {
                    "id": "yokohama-kawamuki-opening-2020",
                    "uri": next(
                        reference.get(
                            "archive_url",
                            reference["source_url"],
                        )
                        for reference in review["source_references"]
                        if reference["source_reference_id"]
                        == "yokohama.kawamuki-opening.2020-02-06"
                    ),
                    "checked_at": review["checked_at"],
                    "supports": (
                        "The municipal opening notice identifies the third "
                        "way's corridor as the temporary passage then used "
                        "inside the land-readjustment area."
                    ),
                },
                {
                    "id": "yokohama-kawamukou-completion-2026",
                    "uri": next(
                        reference["source_url"]
                        for reference in review["source_references"]
                        if reference["source_reference_id"]
                        == "yokohama.kawamukou-completion.2026-06-02"
                    ),
                    "checked_at": review["checked_at"],
                    "supports": (
                        "The current municipal project page reports that "
                        "surrounding infrastructure work completed in March "
                        "2022 and the project ended in July 2023."
                    ),
                },
                {
                    "id": "yokohama-kawamukou-replotting-2023",
                    "uri": next(
                        reference["source_url"]
                        for reference in review["source_references"]
                        if reference["source_reference_id"]
                        == "yokohama.kawamukou-replotting.2023-01-12"
                    ),
                    "checked_at": review["checked_at"],
                    "supports": (
                        "The final municipal replotting map records the "
                        "completed land parcels but publishes no mapping to "
                        "the exact OSM way or current traffic direction."
                    ),
                },
            ],
            "limitations": [
                (
                    "The 2020 corridor identity and later area completion do "
                    "not map the exact OSM way to a current road identity or "
                    "prove its physical status, legal direction, or permitted "
                    "exit movement."
                )
            ],
            "release_blockers": audit["release_blockers"],
        },
        "given": {
            "network_snapshot": candidate["network_snapshot"],
            "route_plan": candidate["route_plan"],
            "inputs": {
                "route_atlas_sources": candidate["source_registry"]["references"],
                "route_atlas_topology": candidate["topology_slice"],
                "route_atlas": definition,
            },
            "system_state": {
                "successor_checkpoint_count": audit["summary"]["checkpoint_count"],
                "source_adjacency_exact": audit["summary"]["source_adjacency_exact"],
                "legal_review_complete": audit["summary"]["legal_review_complete"],
                "unresolved_legal_successor_count": audit["summary"][
                    "unresolved_legal_successor_count"
                ],
                "historical_road_identity_reviewed_count": audit["summary"][
                    "historical_road_identity_reviewed_count"
                ],
                "current_area_infrastructure_reviewed_count": audit["summary"][
                    "current_area_infrastructure_reviewed_count"
                ],
                "current_road_identity_confirmed_count": audit["summary"][
                    "current_road_identity_confirmed_count"
                ],
                "current_legal_direction_confirmed_count": audit["summary"][
                    "current_legal_direction_confirmed_count"
                ],
                "field_verification_required": audit["summary"][
                    "field_verification_required"
                ],
            },
        },
        "when": [
            {
                "id": "attempt-release",
                "at_ms": 0,
                "type": "ROUTE_ATLAS_RELEASE_VALIDATED",
                "payload": {},
            }
        ],
        "then": [
            {
                "id": "legal-review-gap-remains-blocking",
                "after": "attempt-release",
                "category": "SAFETY",
                "subject": "route_atlas.status",
                "matcher": "EQUALS",
                "expected": "BLOCKED",
                "rationale": (
                    "A historic corridor identity and completed surrounding "
                    "works do not establish the exact road's current lawful "
                    "state."
                ),
            },
            {
                "id": "topology-release-remains-required",
                "after": "attempt-release",
                "category": "EVIDENCE",
                "subject": "route_atlas.error_codes",
                "matcher": "CONTAINS",
                "expected": "UNRELEASED_ATLAS_TOPOLOGY_EVIDENCE",
                "rationale": (
                    "The source-complete audit remains a candidate until "
                    "current legal direction and exit movement are reviewed."
                ),
            },
            {
                "id": "production-layout-remains-required",
                "after": "attempt-release",
                "category": "EVIDENCE",
                "subject": "route_atlas.error_codes",
                "matcher": "CONTAINS",
                "expected": "UNRELEASED_ATLAS_EVIDENCE",
                "rationale": (
                    "No official or raw source geometry becomes a released "
                    "Kaido production schematic."
                ),
            },
        ],
    }


def main() -> int:
    arguments = parse_arguments()
    try:
        source_extract = load_object(arguments.source_extract)
        review = load_object(arguments.review)
        audit = build_audit(
            source_extract,
            review,
            sha256(arguments.source_extract),
        )
        write_json(audit, arguments.output)
    except (OSError, SuccessorAuditError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        "PASS: audited "
        f"{audit['summary']['checkpoint_count']} checkpoints and "
        f"{audit['summary']['observed_successor_count']} exact successors; "
        "source adjacency is complete and legal review remains blocked"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
