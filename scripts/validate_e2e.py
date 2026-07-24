#!/usr/bin/env python3
"""Validate Kaido Routes portable E2E scenarios without dependencies."""

from __future__ import annotations

import json
import math
import re
import sys
from datetime import date, datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_PATH = ROOT / "e2e" / "schema" / "scenario.schema.json"
SCENARIO_DIR = ROOT / "e2e" / "scenarios"

LAYERS = {"DOMAIN", "SIMULATION", "IPHONE_UI", "CARPLAY", "FIELD"}
EVIDENCE_CLASSES = {
    "SYNTHETIC",
    "COMMUNITY_CANDIDATE",
    "OFFICIAL_CHECKED",
    "FIELD_CHECKED",
    "RELEASED",
    "STALE_REVIEW_REQUIRED",
}
SNAPSHOT_STATES = {"ACTIVE", "PROPOSED", "RETIRED", "TEST"}
OCCURRENCE_KINDS = {"EDGE", "JUNCTION_MOVEMENT", "PA_VISIT"}
RECOVERY_POLICIES = {"STRICT", "SAFE_REJOIN", "SAFE_EXIT", "MANUAL_WHEN_PARKED"}
TARIFF_QUOTE_STATUSES = {"VERIFIED_QUERY", "ESTIMATED", "UNKNOWN"}
TARIFF_VERSION_STATUSES = {"ACTIVE", "PROPOSED", "RETIRED"}
GUIDANCE_STAGES = {"PREVIEW", "PREPARE", "COMMIT", "RECOVERY", "FINISH"}
GUIDANCE_MANEUVERS = {
    "STAY_MAINLINE",
    "KEEP_LEFT",
    "KEEP_RIGHT",
    "TAKE_EXIT_LEFT",
    "TAKE_EXIT_RIGHT",
    "MERGE_LEFT",
    "MERGE_RIGHT",
}
GUIDANCE_LANE_PREPARATIONS = {
    "NONE",
    "STAY_MAINLINE",
    "KEEP_LEFT",
    "KEEP_RIGHT",
    "USE_LEFT_LANES",
    "USE_RIGHT_LANES",
}
NAVIGATION_RELEASE_ASSET_ROLES = {
    "EDITOR_CATALOG",
    "MATCHER_CORRIDOR",
    "DECISION_ZONE",
    "GUIDANCE",
    "JUNCTION_VIEW",
}
EVENT_TYPES = {
    "ROUTE_COMPILE_REQUESTED",
    "ROUTE_EDITOR_STARTED",
    "ROUTE_EDITOR_CHOICE_SELECTED",
    "ROUTE_EDITOR_CORRIDOR_MATCH_SUBMITTED",
    "ROUTE_EDITOR_CORRIDOR_RESOLUTION_REQUESTED",
    "ROUTE_EDITOR_LAP_DUPLICATION_REQUESTED",
    "ROUTE_EDITOR_UNDO_REQUESTED",
    "ROUTE_EDITOR_COMPILE_REQUESTED",
    "NAVIGATION_RELEASE_BUNDLE_VALIDATED",
    "NAVIGATION_RELEASE_ARTIFACT_VALIDATED",
    "ROUTE_ATLAS_RELEASE_VALIDATED",
    "ROUTE_ATLAS_CONTEXT_VALIDATED",
    "NAVIGATION_STARTED",
    "LOCATION_UPDATED",
    "MATCHER_SESSION_STARTED",
    "MATCHER_OBSERVATION_RECEIVED",
    "MATCHER_SESSION_RESET",
    "TUNNEL_ENTERED",
    "TUNNEL_EXITED",
    "BRANCH_OBSERVED",
    "RESTRICTION_UPDATED",
    "CARPLAY_CONNECTED",
    "CARPLAY_DISCONNECTED",
    "USER_ACTION",
    "TARIFF_QUOTED",
    "TARIFF_SELECTION_REQUESTED",
    "GUIDANCE_ANCHOR_REACHED",
    "GUIDANCE_PROGRESS_UPDATED",
}
ASSERTION_CATEGORIES = {"DOMAIN", "NAVIGATION", "UI", "SAFETY", "TOLL", "EVIDENCE"}
MATCHERS = {
    "EQUALS",
    "NOT_EQUALS",
    "CONTAINS",
    "ONE_OF",
    "PRESENT",
    "ABSENT",
    "LESS_THAN",
    "GREATER_THAN",
}
ID_RE = re.compile(r"^KR-[A-Z][0-9]{2}$")
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")


class Validation:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.errors: list[str] = []

    def add(self, message: str) -> None:
        self.errors.append(f"{self.path.relative_to(ROOT)}: {message}")

    def require_keys(self, value: Any, keys: set[str], context: str) -> bool:
        if not isinstance(value, dict):
            self.add(f"{context} must be an object")
            return False
        missing = sorted(keys - value.keys())
        if missing:
            self.add(f"{context} is missing: {', '.join(missing)}")
            return False
        return True


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def is_date(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    try:
        date.fromisoformat(value)
    except ValueError:
        return False
    return True


def is_datetime(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return True


def validate_evidence(v: Validation, evidence: Any) -> None:
    required = {"classification", "sources", "limitations", "release_blockers"}
    if not v.require_keys(evidence, required, "evidence"):
        return

    classification = evidence["classification"]
    if classification not in EVIDENCE_CLASSES:
        v.add(f"unknown evidence classification: {classification!r}")

    sources = evidence["sources"]
    if not isinstance(sources, list):
        v.add("evidence.sources must be an array")
        return
    if classification != "SYNTHETIC" and not sources:
        v.add(f"{classification} evidence requires at least one source")

    source_ids: set[str] = set()
    for index, source in enumerate(sources):
        context = f"evidence.sources[{index}]"
        if not v.require_keys(source, {"id", "uri", "checked_at", "supports"}, context):
            continue
        source_id = source["id"]
        if not isinstance(source_id, str) or not SLUG_RE.fullmatch(source_id):
            v.add(f"{context}.id must be a lowercase stable identifier")
        elif source_id in source_ids:
            v.add(f"duplicate evidence source id: {source_id}")
        source_ids.add(source_id)
        uri = source["uri"]
        if not isinstance(uri, str) or ":" not in uri:
            v.add(f"{context}.uri must be an absolute URI")
        if not is_date(source["checked_at"]):
            v.add(f"{context}.checked_at must be an ISO date")
        if not isinstance(source["supports"], str) or not source["supports"].strip():
            v.add(f"{context}.supports must be non-empty")

    for field in ("limitations", "release_blockers"):
        if not isinstance(evidence[field], list) or not all(
            isinstance(item, str) and item.strip() for item in evidence[field]
        ):
            v.add(f"evidence.{field} must be an array of non-empty strings")


def validate_snapshot(v: Validation, snapshot: Any) -> None:
    if not v.require_keys(snapshot, {"id", "status", "effective_at"}, "given.network_snapshot"):
        return
    if not isinstance(snapshot["id"], str) or not snapshot["id"].strip():
        v.add("given.network_snapshot.id must be non-empty")
    if snapshot["status"] not in SNAPSHOT_STATES:
        v.add(f"unknown network snapshot status: {snapshot['status']!r}")
    if not is_datetime(snapshot["effective_at"]):
        v.add("given.network_snapshot.effective_at must be an ISO date-time")


def validate_route_plan(v: Validation, route_plan: Any, network_snapshot_id: Any) -> None:
    required = {
        "plan_id",
        "network_snapshot_id",
        "entry_facility_id",
        "exit_facility_id",
        "recovery_policy",
        "occurrences",
    }
    if not v.require_keys(route_plan, required, "given.route_plan"):
        return
    if route_plan["network_snapshot_id"] != network_snapshot_id:
        v.add("given.route_plan.network_snapshot_id must match given.network_snapshot.id")
    if route_plan["recovery_policy"] not in RECOVERY_POLICIES:
        v.add(f"unknown recovery policy: {route_plan['recovery_policy']!r}")

    occurrences = route_plan["occurrences"]
    if not isinstance(occurrences, list) or not occurrences:
        v.add("given.route_plan.occurrences must be a non-empty array")
        return

    occurrence_ids: set[str] = set()
    indexes: list[int] = []
    parking_groups: dict[str, list[dict[str, Any]]] = {}
    for position, occurrence in enumerate(occurrences):
        context = f"given.route_plan.occurrences[{position}]"
        required_occurrence = {"occurrence_id", "index", "kind", "entity_id"}
        if not v.require_keys(occurrence, required_occurrence, context):
            continue
        occurrence_id = occurrence["occurrence_id"]
        if not isinstance(occurrence_id, str) or not occurrence_id.strip():
            v.add(f"{context}.occurrence_id must be non-empty")
        elif occurrence_id in occurrence_ids:
            v.add(f"duplicate occurrence_id: {occurrence_id}")
        occurrence_ids.add(occurrence_id)
        index = occurrence["index"]
        if not isinstance(index, int) or isinstance(index, bool) or index < 0:
            v.add(f"{context}.index must be a non-negative integer")
        else:
            indexes.append(index)
        if occurrence["kind"] not in OCCURRENCE_KINDS:
            v.add(f"{context}.kind is unknown: {occurrence['kind']!r}")
        if not isinstance(occurrence["entity_id"], str) or not occurrence["entity_id"].strip():
            v.add(f"{context}.entity_id must be non-empty")
        parking_area_id = occurrence.get("parking_area_id")
        if parking_area_id is not None:
            if not isinstance(parking_area_id, str) or not parking_area_id.strip():
                v.add(f"{context}.parking_area_id must be non-empty when present")
            else:
                parking_groups.setdefault(parking_area_id, []).append(occurrence)
        elif occurrence.get("kind") == "PA_VISIT":
            v.add(f"{context} PA_VISIT requires parking_area_id")
        toll_domain_id = occurrence.get("toll_domain_id")
        if toll_domain_id is not None and (
            not isinstance(toll_domain_id, str) or not toll_domain_id.strip()
        ):
            v.add(f"{context}.toll_domain_id must be non-empty when present")

    if indexes != list(range(len(occurrences))):
        v.add("route occurrence indexes must be contiguous and match array order from zero")

    for parking_area_id, group in parking_groups.items():
        visits = [item for item in group if item.get("kind") == "PA_VISIT"]
        if len(visits) != 1:
            v.add(f"parking area {parking_area_id!r} requires exactly one PA_VISIT")
            continue
        visit_index = visits[0].get("index")
        if not isinstance(visit_index, int) or isinstance(visit_index, bool):
            continue
        access_movements = [
            item
            for item in group
            if item.get("kind") == "JUNCTION_MOVEMENT"
            and isinstance(item.get("index"), int)
            and item["index"] < visit_index
        ]
        return_movements = [
            item
            for item in group
            if item.get("kind") == "JUNCTION_MOVEMENT"
            and isinstance(item.get("index"), int)
            and item["index"] > visit_index
        ]
        if not access_movements:
            v.add(f"parking area {parking_area_id!r} requires an access movement before PA_VISIT")
        if not return_movements:
            v.add(f"parking area {parking_area_id!r} requires a return movement after PA_VISIT")
        optional_values = {item.get("optional", False) for item in group}
        if len(optional_values) != 1:
            v.add(f"parking area {parking_area_id!r} has inconsistent optional flags")


def validate_tariff_quotes(v: Validation, quotes: Any) -> None:
    if not isinstance(quotes, list):
        v.add("given.tariff_quotes must be an array")
        return

    quote_ids: set[str] = set()
    required = {
        "quote_id",
        "status",
        "vehicle_class",
        "tariff_version_id",
        "tariff_version_status",
        "checked_at",
        "official_query_reference",
    }
    for index, quote in enumerate(quotes):
        context = f"given.tariff_quotes[{index}]"
        if not v.require_keys(quote, required, context):
            continue
        quote_id = quote["quote_id"]
        if not isinstance(quote_id, str) or not quote_id.strip():
            v.add(f"{context}.quote_id must be non-empty")
        elif quote_id in quote_ids:
            v.add(f"duplicate tariff quote_id: {quote_id}")
        quote_ids.add(quote_id)
        if quote["status"] not in TARIFF_QUOTE_STATUSES:
            v.add(f"{context}.status is unknown: {quote['status']!r}")
        if quote["tariff_version_status"] not in TARIFF_VERSION_STATUSES:
            v.add(
                f"{context}.tariff_version_status is unknown: "
                f"{quote['tariff_version_status']!r}"
            )
        for field in ("vehicle_class", "tariff_version_id"):
            if not isinstance(quote[field], str) or not quote[field].strip():
                v.add(f"{context}.{field} must be non-empty")
        if not is_datetime(quote["checked_at"]):
            v.add(f"{context}.checked_at must be an ISO date-time")
        reference = quote["official_query_reference"]
        if not isinstance(reference, str) or ":" not in reference:
            v.add(f"{context}.official_query_reference must be an absolute URI")
        distance = quote.get("tariff_distance_km")
        if distance is not None and (
            not isinstance(distance, (int, float))
            or isinstance(distance, bool)
            or distance < 0
        ):
            v.add(f"{context}.tariff_distance_km must be non-negative")
        amount = quote.get("estimated_amount_yen")
        if amount is not None and (
            not isinstance(amount, int) or isinstance(amount, bool) or amount < 0
        ):
            v.add(f"{context}.estimated_amount_yen must be a non-negative integer")


def validate_guidance_anchors(v: Validation, given: dict[str, Any]) -> None:
    inputs = given.get("inputs")
    if not isinstance(inputs, dict) or "guidance_anchors" not in inputs:
        return
    anchors = inputs["guidance_anchors"]
    if not isinstance(anchors, list) or not anchors:
        v.add("given.inputs.guidance_anchors must be a non-empty array")
        return
    route_plan = given.get("route_plan")
    if not isinstance(route_plan, dict):
        v.add("given.inputs.guidance_anchors requires given.route_plan")
        return
    occurrences = route_plan.get("occurrences", [])
    occurrence_ids = {
        occurrence.get("occurrence_id")
        for occurrence in occurrences
        if isinstance(occurrence, dict)
    }

    keys: set[tuple[str, str]] = set()
    prompt_ids: set[str] = set()
    for index, anchor in enumerate(anchors):
        context = f"given.inputs.guidance_anchors[{index}]"
        if not v.require_keys(anchor, {"occurrence_id", "anchor_id", "prompt_id"}, context):
            continue
        values = [anchor["occurrence_id"], anchor["anchor_id"], anchor["prompt_id"]]
        if not all(isinstance(value, str) and value.strip() for value in values):
            v.add(f"{context} identifiers must be non-empty strings")
            continue
        occurrence_id, anchor_id, prompt_id = values
        if occurrence_id not in occurrence_ids:
            v.add(f"{context}.occurrence_id references an unknown route occurrence")
        key = (occurrence_id, anchor_id)
        if key in keys:
            v.add(f"duplicate guidance anchor key: {occurrence_id} + {anchor_id}")
        keys.add(key)
        if prompt_id in prompt_ids:
            v.add(f"duplicate guidance prompt_id: {prompt_id}")
        prompt_ids.add(prompt_id)


def validate_entrance_recommendation(v: Validation, given: dict[str, Any]) -> None:
    inputs = given.get("inputs")
    if not isinstance(inputs, dict):
        return
    route_template = inputs.get("route_template")
    candidates = inputs.get("entrance_candidates")
    if route_template is None and candidates is None:
        return
    if not isinstance(route_template, dict):
        v.add("given.inputs.route_template must be an object")
        return
    if not isinstance(candidates, list) or not candidates:
        v.add("given.inputs.entrance_candidates must be a non-empty array")
        return

    context = "given.inputs.route_template"
    if v.require_keys(
        route_template,
        {"template_id", "allowed_join_occurrence_ids"},
        context,
    ):
        template_id = route_template["template_id"]
        if not isinstance(template_id, str) or not template_id.strip():
            v.add(f"{context}.template_id must be non-empty")
        allowed_joins = route_template["allowed_join_occurrence_ids"]
        if not isinstance(allowed_joins, list) or not allowed_joins:
            v.add(f"{context}.allowed_join_occurrence_ids must be a non-empty array")
        elif not all(
            isinstance(join_id, str) and join_id.strip()
            for join_id in allowed_joins
        ):
            v.add(f"{context}.allowed_join_occurrence_ids must contain non-empty strings")
        elif len(allowed_joins) != len(set(allowed_joins)):
            v.add(f"{context}.allowed_join_occurrence_ids must be unique")

    facility_ids: set[str] = set()
    required = {
        "facility_id",
        "target_carriageway_id",
        "straight_line_distance_km",
        "surface_eta_minutes",
        "legal_join_occurrence_ids",
    }
    for index, candidate in enumerate(candidates):
        context = f"given.inputs.entrance_candidates[{index}]"
        if not v.require_keys(candidate, required, context):
            continue
        for field in ("facility_id", "target_carriageway_id"):
            value = candidate[field]
            if not isinstance(value, str) or not value.strip():
                v.add(f"{context}.{field} must be non-empty")
        facility_id = candidate["facility_id"]
        if isinstance(facility_id, str):
            if facility_id in facility_ids:
                v.add(f"duplicate entrance candidate facility_id: {facility_id}")
            facility_ids.add(facility_id)
        for field in ("straight_line_distance_km", "surface_eta_minutes"):
            value = candidate[field]
            if (
                not isinstance(value, (int, float))
                or isinstance(value, bool)
                or not math.isfinite(value)
                or value < 0
            ):
                v.add(f"{context}.{field} must be finite and non-negative")
        join_ids = candidate["legal_join_occurrence_ids"]
        if not isinstance(join_ids, list):
            v.add(f"{context}.legal_join_occurrence_ids must be an array")
        elif not all(
            isinstance(join_id, str) and join_id.strip() for join_id in join_ids
        ):
            v.add(f"{context}.legal_join_occurrence_ids must contain non-empty strings")
        elif len(join_ids) != len(set(join_ids)):
            v.add(f"{context}.legal_join_occurrence_ids must be unique")
        availability = candidate.get("approach_availability", "AVAILABLE")
        if availability not in {"AVAILABLE", "UNAVAILABLE", "UNKNOWN"}:
            v.add(f"{context}.approach_availability is unknown: {availability!r}")


def validate_matcher_guidance_inputs(v: Validation, given: dict[str, Any]) -> None:
    inputs = given.get("inputs")
    if not isinstance(inputs, dict):
        return
    corridor = inputs.get("matcher_corridor")
    bridge = inputs.get("guidance_progress_bridge")
    if corridor is None and bridge is None:
        return

    route_plan = given.get("route_plan")
    if not isinstance(route_plan, dict):
        v.add("matcher guidance inputs require given.route_plan")
        return
    network_snapshot = given.get("network_snapshot")
    snapshot_id = network_snapshot.get("id") if isinstance(network_snapshot, dict) else None
    plan_id = route_plan.get("plan_id")
    route_occurrences = route_plan.get("occurrences", [])
    route_occurrence_by_id = {
        occurrence.get("occurrence_id"): occurrence
        for occurrence in route_occurrences
        if isinstance(occurrence, dict)
        and isinstance(occurrence.get("occurrence_id"), str)
    }

    if corridor is not None:
        corridor_required = {
            "corridor_id",
            "network_snapshot_id",
            "route_plan_id",
            "edges",
            "occurrences",
        }
        if not v.require_keys(corridor, corridor_required, "given.inputs.matcher_corridor"):
            return
        if corridor["network_snapshot_id"] != snapshot_id:
            v.add("given.inputs.matcher_corridor.network_snapshot_id must match the snapshot")
        if corridor["route_plan_id"] != plan_id:
            v.add("given.inputs.matcher_corridor.route_plan_id must match the RoutePlan")

        edges = corridor["edges"]
        edge_ids = {
            edge.get("directed_edge_id")
            for edge in edges
            if isinstance(edge, dict) and isinstance(edge.get("directed_edge_id"), str)
        } if isinstance(edges, list) else set()
        if not isinstance(edges, list) or not edges:
            v.add("given.inputs.matcher_corridor.edges must be a non-empty array")

        occurrences = corridor["occurrences"]
        if not isinstance(occurrences, list) or not occurrences:
            v.add("given.inputs.matcher_corridor.occurrences must be a non-empty array")
        else:
            for index, occurrence in enumerate(occurrences):
                context = f"given.inputs.matcher_corridor.occurrences[{index}]"
                required = {"occurrence_id", "index", "directed_edge_id"}
                if not v.require_keys(occurrence, required, context):
                    continue
                route_occurrence = route_occurrence_by_id.get(occurrence["occurrence_id"])
                if route_occurrence is None:
                    v.add(f"{context}.occurrence_id must name a RoutePlan occurrence")
                    continue
                if occurrence["index"] != route_occurrence.get("index"):
                    v.add(f"{context}.index must match the RoutePlan occurrence")
                if occurrence["directed_edge_id"] not in edge_ids:
                    v.add(f"{context}.directed_edge_id must name a corridor edge")
                if (
                    route_occurrence.get("kind") == "EDGE"
                    and occurrence["directed_edge_id"] != route_occurrence.get("entity_id")
                ):
                    v.add(f"{context}.directed_edge_id must match the RoutePlan EDGE entity")

    if bridge is None:
        return
    if corridor is None:
        v.add("given.inputs.guidance_progress_bridge requires matcher_corridor")
        return
    bridge_required = {
        "decision_zone_id",
        "network_snapshot_id",
        "route_plan_id",
        "movement_occurrence_id",
        "entry_offset_meters",
    }
    if not v.require_keys(bridge, bridge_required, "given.inputs.guidance_progress_bridge"):
        return
    if bridge["network_snapshot_id"] != snapshot_id:
        v.add("given.inputs.guidance_progress_bridge.network_snapshot_id must match the snapshot")
    if bridge["route_plan_id"] != plan_id:
        v.add("given.inputs.guidance_progress_bridge.route_plan_id must match the RoutePlan")
    if not isinstance(bridge["decision_zone_id"], str) or not bridge["decision_zone_id"].strip():
        v.add("given.inputs.guidance_progress_bridge.decision_zone_id must be non-empty")
    movement = route_occurrence_by_id.get(bridge["movement_occurrence_id"])
    if movement is None or movement.get("kind") != "JUNCTION_MOVEMENT":
        v.add("given.inputs.guidance_progress_bridge.movement_occurrence_id must name a junction movement")
    offset = bridge["entry_offset_meters"]
    if (
        not isinstance(offset, (int, float))
        or isinstance(offset, bool)
        or offset < 0
    ):
        v.add("given.inputs.guidance_progress_bridge.entry_offset_meters must be non-negative")


def validate_expert_route_editor(v: Validation, given: dict[str, Any]) -> None:
    inputs = given.get("inputs")
    if not isinstance(inputs, dict) or "expert_route_editor_catalog" not in inputs:
        return
    catalog = inputs["expert_route_editor_catalog"]
    required = {"network_snapshot_id", "entrances", "decision_points"}
    if not v.require_keys(catalog, required, "given.inputs.expert_route_editor_catalog"):
        return
    snapshot = given.get("network_snapshot")
    snapshot_id = snapshot.get("id") if isinstance(snapshot, dict) else None
    if catalog["network_snapshot_id"] != snapshot_id:
        v.add("expert route editor catalog must match given.network_snapshot.id")

    entrances = catalog["entrances"]
    decisions = catalog["decision_points"]
    if not isinstance(entrances, list) or not entrances:
        v.add("expert route editor catalog entrances must be a non-empty array")
        entrances = []
    if not isinstance(decisions, list) or not decisions:
        v.add("expert route editor catalog decision_points must be a non-empty array")
        decisions = []

    decision_by_id: dict[str, dict[str, Any]] = {}
    choice_ids: set[str] = set()
    for index, decision in enumerate(decisions):
        context = f"given.inputs.expert_route_editor_catalog.decision_points[{index}]"
        decision_required = {
            "decision_point_id",
            "incoming_approach_id",
            "junction_complex_id",
            "choices",
        }
        if not v.require_keys(decision, decision_required, context):
            continue
        decision_id = decision["decision_point_id"]
        if not isinstance(decision_id, str) or not decision_id.strip():
            v.add(f"{context}.decision_point_id must be non-empty")
        elif decision_id in decision_by_id:
            v.add(f"duplicate editor decision_point_id: {decision_id}")
        else:
            decision_by_id[decision_id] = decision
        for field in ("incoming_approach_id", "junction_complex_id"):
            if not isinstance(decision[field], str) or not decision[field].strip():
                v.add(f"{context}.{field} must be non-empty")
        choices = decision["choices"]
        if not isinstance(choices, list) or not choices:
            v.add(f"{context}.choices must be a non-empty array")
            continue
        for choice_index, choice in enumerate(choices):
            choice_context = f"{context}.choices[{choice_index}]"
            choice_required = {
                "choice_id",
                "movement_id",
                "movement_toll_domain_id",
                "outgoing_edge_id",
                "outgoing_edge_toll_domain_id",
            }
            if not v.require_keys(choice, choice_required, choice_context):
                continue
            for field in choice_required:
                if not isinstance(choice[field], str) or not choice[field].strip():
                    v.add(f"{choice_context}.{field} must be non-empty")
            choice_id = choice["choice_id"]
            if not isinstance(choice_id, str) or not choice_id.strip():
                v.add(f"{choice_context}.choice_id must be non-empty")
            else:
                if choice_id in choice_ids:
                    v.add(f"duplicate editor choice_id: {choice_id}")
                choice_ids.add(choice_id)
            destinations = [
                key
                for key in ("next_decision_point_id", "exit_facility_id")
                if isinstance(choice.get(key), str) and choice[key].strip()
            ]
            if len(destinations) != 1:
                v.add(f"{choice_context} must name exactly one editor destination")
        movement_ids = [
            choice.get("movement_id")
            for choice in choices
            if isinstance(choice, dict)
            and isinstance(choice.get("movement_id"), str)
        ]
        if len(movement_ids) != len(set(movement_ids)):
            v.add(f"{context}.choices must not repeat a movement")

    entrance_ids: set[str] = set()
    for index, entrance in enumerate(entrances):
        context = f"given.inputs.expert_route_editor_catalog.entrances[{index}]"
        entrance_required = {
            "facility_id",
            "initial_edge_id",
            "initial_edge_toll_domain_id",
            "first_decision_point_id",
        }
        if not v.require_keys(entrance, entrance_required, context):
            continue
        for field in entrance_required:
            if not isinstance(entrance[field], str) or not entrance[field].strip():
                v.add(f"{context}.{field} must be non-empty")
        facility_id = entrance["facility_id"]
        if not isinstance(facility_id, str) or not facility_id.strip():
            v.add(f"{context}.facility_id must be non-empty")
        else:
            if facility_id in entrance_ids:
                v.add(f"duplicate editor entrance facility_id: {facility_id}")
            entrance_ids.add(facility_id)
        first_decision_point_id = entrance["first_decision_point_id"]
        if (
            isinstance(first_decision_point_id, str)
            and first_decision_point_id not in decision_by_id
        ):
            v.add(f"{context}.first_decision_point_id must name a decision point")

    for decision_id, decision in decision_by_id.items():
        for choice in decision.get("choices", []):
            if not isinstance(choice, dict):
                continue
            next_id = choice.get("next_decision_point_id")
            if isinstance(next_id, str) and next_id not in decision_by_id:
                v.add(
                    f"editor decision {decision_id!r} references unknown next decision {next_id!r}"
                )

    lap_templates = catalog.get("lap_templates", [])
    if not isinstance(lap_templates, list):
        v.add("expert route editor catalog lap_templates must be an array")
        lap_templates = []
    lap_template_ids: set[str] = set()
    for index, template in enumerate(lap_templates):
        context = f"given.inputs.expert_route_editor_catalog.lap_templates[{index}]"
        required = {"template_id", "start_decision_point_id", "choice_ids"}
        if not v.require_keys(template, required, context):
            continue
        template_id = template["template_id"]
        if not isinstance(template_id, str) or not template_id.strip():
            v.add(f"{context}.template_id must be non-empty")
        elif template_id in lap_template_ids:
            v.add(f"duplicate editor lap template_id: {template_id}")
        else:
            lap_template_ids.add(template_id)
        start_decision_id = template["start_decision_point_id"]
        if (
            not isinstance(start_decision_id, str)
            or not start_decision_id.strip()
            or start_decision_id not in decision_by_id
        ):
            v.add(f"{context}.start_decision_point_id must name a decision point")
            continue
        choice_sequence = template["choice_ids"]
        if (
            not isinstance(choice_sequence, list)
            or not choice_sequence
            or not all(
                isinstance(choice_id, str) and choice_id.strip()
                for choice_id in choice_sequence
            )
        ):
            v.add(f"{context}.choice_ids must be a non-empty string array")
            continue

        current_decision_id = start_decision_id
        forms_closed_sequence = True
        for choice_id in choice_sequence:
            decision = decision_by_id.get(current_decision_id)
            choices = decision.get("choices", []) if decision else []
            choice = next(
                (
                    candidate
                    for candidate in choices
                    if isinstance(candidate, dict)
                    and candidate.get("choice_id") == choice_id
                ),
                None,
            )
            next_decision_id = (
                choice.get("next_decision_point_id")
                if isinstance(choice, dict)
                else None
            )
            if (
                not isinstance(next_decision_id, str)
                or next_decision_id not in decision_by_id
            ):
                forms_closed_sequence = False
                break
            current_decision_id = next_decision_id
        if not forms_closed_sequence or current_decision_id != start_decision_id:
            v.add(f"{context} must form a reviewed closed choice sequence")

    for entrance in entrances:
        if not isinstance(entrance, dict):
            continue
        pending = [entrance.get("first_decision_point_id")]
        visited: set[str] = set()
        has_exit = False
        while pending:
            decision_id = pending.pop()
            if not isinstance(decision_id, str) or decision_id in visited:
                continue
            visited.add(decision_id)
            decision = decision_by_id.get(decision_id)
            if decision is None:
                continue
            for choice in decision.get("choices", []):
                if not isinstance(choice, dict):
                    continue
                exit_id = choice.get("exit_facility_id")
                if isinstance(exit_id, str) and exit_id.strip():
                    has_exit = True
                    break
                pending.append(choice.get("next_decision_point_id"))
            if has_exit:
                break
        if not has_exit:
            v.add(
                f"editor entrance {entrance.get('facility_id')!r} has no reachable exit"
            )


def validate_released_guidance(v: Validation, given: dict[str, Any]) -> None:
    inputs = given.get("inputs")
    if not isinstance(inputs, dict) or "released_guidance" not in inputs:
        return
    definitions = inputs["released_guidance"]
    if not isinstance(definitions, list) or not definitions:
        v.add("given.inputs.released_guidance must be a non-empty array")
        return
    route_plan = given.get("route_plan")
    if not isinstance(route_plan, dict):
        v.add("given.inputs.released_guidance requires given.route_plan")
        return
    occurrences = route_plan.get("occurrences", [])
    occurrence_by_id = {
        occurrence.get("occurrence_id"): occurrence
        for occurrence in occurrences
        if isinstance(occurrence, dict)
        and isinstance(occurrence.get("occurrence_id"), str)
    }
    required_locales = {"ja-JP", "zh-Hans", "en"}
    anchor_keys: set[tuple[str, str]] = set()
    prompt_ids: set[str] = set()

    for index, definition in enumerate(definitions):
        context = f"given.inputs.released_guidance[{index}]"
        required = {
            "occurrence_id",
            "anchor_id",
            "prompt_id",
            "trigger_distance_meters",
            "frame",
        }
        if not v.require_keys(definition, required, context):
            continue
        identifiers = [
            definition["occurrence_id"],
            definition["anchor_id"],
            definition["prompt_id"],
        ]
        if not all(isinstance(value, str) and value.strip() for value in identifiers):
            v.add(f"{context} identifiers must be non-empty strings")
            continue
        occurrence_id, anchor_id, prompt_id = identifiers
        anchor_occurrence = occurrence_by_id.get(occurrence_id)
        if anchor_occurrence is None:
            v.add(f"{context}.occurrence_id references an unknown route occurrence")
        key = (occurrence_id, anchor_id)
        if key in anchor_keys:
            v.add(f"duplicate released guidance anchor key: {occurrence_id} + {anchor_id}")
        anchor_keys.add(key)
        if prompt_id in prompt_ids:
            v.add(f"duplicate released guidance prompt_id: {prompt_id}")
        prompt_ids.add(prompt_id)

        trigger = definition["trigger_distance_meters"]
        if (
            not isinstance(trigger, (int, float))
            or isinstance(trigger, bool)
            or trigger < 0
        ):
            v.add(f"{context}.trigger_distance_meters must be non-negative")

        frame = definition["frame"]
        frame_required = {
            "movement_occurrence_id",
            "decision_zone_id",
            "stage",
            "decision_point_name_ja",
            "localized_decision_point_names",
            "maneuver",
            "lane_preparation",
            "route_shields",
            "japanese_sign_text",
            "localized_content",
        }
        if not v.require_keys(frame, frame_required, f"{context}.frame"):
            continue
        movement_id = frame["movement_occurrence_id"]
        movement = occurrence_by_id.get(movement_id)
        if movement is None:
            v.add(f"{context}.frame.movement_occurrence_id is unknown")
        elif movement.get("kind") != "JUNCTION_MOVEMENT":
            v.add(f"{context}.frame.movement_occurrence_id must name a junction movement")
        elif anchor_occurrence is not None and movement.get("index", -1) < anchor_occurrence.get(
            "index", -1
        ):
            v.add(f"{context}.frame movement cannot precede its anchor occurrence")
        for key_name in ("decision_zone_id", "decision_point_name_ja", "japanese_sign_text"):
            if not isinstance(frame[key_name], str) or not frame[key_name].strip():
                v.add(f"{context}.frame.{key_name} must be a non-empty string")
        if frame["stage"] not in GUIDANCE_STAGES:
            v.add(f"{context}.frame.stage is unknown")
        if frame["maneuver"] not in GUIDANCE_MANEUVERS:
            v.add(f"{context}.frame.maneuver is unknown")
        if frame["lane_preparation"] not in GUIDANCE_LANE_PREPARATIONS:
            v.add(f"{context}.frame.lane_preparation is unknown")
        route_shields = frame["route_shields"]
        if (
            not isinstance(route_shields, list)
            or not route_shields
            or not all(isinstance(shield, str) and shield.strip() for shield in route_shields)
        ):
            v.add(f"{context}.frame.route_shields must be non-empty strings")
        localized_names = frame["localized_decision_point_names"]
        localized_content = frame["localized_content"]
        if not isinstance(localized_names, dict) or set(localized_names) != required_locales:
            v.add(f"{context}.frame.localized_decision_point_names must contain ja-JP, zh-Hans, and en")
        elif localized_names.get("ja-JP") != frame["decision_point_name_ja"]:
            v.add(f"{context}.frame Japanese decision-point name must be preserved exactly")
        elif not all(isinstance(name, str) and name.strip() for name in localized_names.values()):
            v.add(f"{context}.frame localized decision-point names must be non-empty")
        if not isinstance(localized_content, dict) or set(localized_content) != required_locales:
            v.add(f"{context}.frame.localized_content must contain ja-JP, zh-Hans, and en")
        else:
            for locale, content in localized_content.items():
                content_required = {
                    "display_text",
                    "spoken_text",
                    "spoken_forms",
                    "preserved_japanese_sign_text",
                }
                if not isinstance(content, dict) or not content_required.issubset(content):
                    v.add(f"{context}.frame.localized_content[{locale}] is incomplete")
                    continue
                if content.get("preserved_japanese_sign_text") != frame["japanese_sign_text"]:
                    v.add(f"{context}.frame.localized_content[{locale}] must preserve Japanese sign text")
                for text_key in ("display_text", "spoken_text"):
                    if not isinstance(content[text_key], str) or not content[text_key].strip():
                        v.add(f"{context}.frame.localized_content[{locale}].{text_key} is empty")
                spoken_forms = content["spoken_forms"]
                if (
                    not isinstance(spoken_forms, dict)
                    or not spoken_forms
                    or not all(
                        isinstance(key, str)
                        and key.strip()
                        and isinstance(value, str)
                        and value.strip()
                        for key, value in spoken_forms.items()
                    )
                ):
                    v.add(f"{context}.frame.localized_content[{locale}].spoken_forms is invalid")


def validate_navigation_release_artifact(
    v: Validation, given: dict[str, Any]
) -> None:
    inputs = given.get("inputs")
    if (
        not isinstance(inputs, dict)
        or "navigation_release_asset_evidence" not in inputs
    ):
        return

    required_inputs = {
        "navigation_release_id",
        "navigation_release_released_at",
        "navigation_release_editor_catalog_id",
        "navigation_release_sources",
        "navigation_release_asset_evidence",
        "expert_route_editor_catalog",
        "matcher_corridor",
        "decision_zones",
        "released_guidance",
    }
    missing = sorted(required_inputs - inputs.keys())
    if missing:
        v.add(
            "navigation release artifact inputs are missing: "
            + ", ".join(missing)
        )
        return

    for field in ("navigation_release_id", "navigation_release_editor_catalog_id"):
        if not isinstance(inputs[field], str) or not inputs[field].strip():
            v.add(f"given.inputs.{field} must be non-empty")
    if not is_datetime(inputs["navigation_release_released_at"]):
        v.add(
            "given.inputs.navigation_release_released_at must be an ISO date-time"
        )

    sources = inputs["navigation_release_sources"]
    if not isinstance(sources, list) or not sources:
        v.add("given.inputs.navigation_release_sources must be a non-empty array")
        sources = []
    source_by_id: dict[str, dict[str, Any]] = {}
    for index, source in enumerate(sources):
        context = f"given.inputs.navigation_release_sources[{index}]"
        required = {
            "source_reference_id",
            "roles",
            "authority_name",
            "source_url",
            "content_sha256",
            "checked_at",
            "licence_identifier",
        }
        if not v.require_keys(source, required, context):
            continue
        source_id = source["source_reference_id"]
        if not isinstance(source_id, str) or not source_id.strip():
            v.add(f"{context}.source_reference_id must be non-empty")
        elif source_id in source_by_id:
            v.add(f"duplicate navigation release source: {source_id}")
        else:
            source_by_id[source_id] = source
        roles = source["roles"]
        if (
            not isinstance(roles, list)
            or not roles
            or not all(isinstance(role, str) for role in roles)
            or len(roles) != len(set(roles))
            or not set(roles).issubset(NAVIGATION_RELEASE_ASSET_ROLES)
        ):
            v.add(f"{context}.roles must be unique known asset roles")
        for field in ("authority_name", "licence_identifier"):
            if not isinstance(source[field], str) or not source[field].strip():
                v.add(f"{context}.{field} must be non-empty")
        if (
            not isinstance(source["source_url"], str)
            or not source["source_url"].startswith("https://")
        ):
            v.add(f"{context}.source_url must be HTTPS")
        if (
            not isinstance(source["content_sha256"], str)
            or re.fullmatch(r"[0-9a-fA-F]{64}", source["content_sha256"])
            is None
        ):
            v.add(f"{context}.content_sha256 must contain 64 hexadecimal characters")
        if not is_date(source["checked_at"]):
            v.add(f"{context}.checked_at must be an ISO date")

    expected_keys: list[tuple[str, str]] = [
        ("EDITOR_CATALOG", inputs["navigation_release_editor_catalog_id"])
    ]
    corridor = inputs["matcher_corridor"]
    if isinstance(corridor, dict):
        expected_keys.append(("MATCHER_CORRIDOR", corridor.get("corridor_id")))
    for zone in inputs["decision_zones"] if isinstance(inputs["decision_zones"], list) else []:
        if isinstance(zone, dict):
            expected_keys.append(("DECISION_ZONE", zone.get("decision_zone_id")))
    for guidance in (
        inputs["released_guidance"]
        if isinstance(inputs["released_guidance"], list)
        else []
    ):
        if isinstance(guidance, dict):
            expected_keys.append(("GUIDANCE", guidance.get("prompt_id")))
    for view in inputs.get("junction_views", []):
        if isinstance(view, dict):
            expected_keys.append(("JUNCTION_VIEW", view.get("view_id")))

    normalized_expected: set[tuple[str, str]] = set()
    for role, asset_id in expected_keys:
        if not isinstance(asset_id, str) or not asset_id.strip():
            v.add(f"navigation release {role} asset identity must be non-empty")
            continue
        key = (role, asset_id)
        if key in normalized_expected:
            v.add(f"duplicate navigation release asset identity: {role}:{asset_id}")
        normalized_expected.add(key)

    evidence_values = inputs["navigation_release_asset_evidence"]
    if not isinstance(evidence_values, list) or not evidence_values:
        v.add(
            "given.inputs.navigation_release_asset_evidence must be a non-empty array"
        )
        evidence_values = []
    evidence_by_key: dict[tuple[str, str], dict[str, Any]] = {}
    used_source_ids: set[str] = set()
    junction_view_by_id = {
        view.get("view_id"): view
        for view in inputs.get("junction_views", [])
        if isinstance(view, dict)
    }
    for index, evidence in enumerate(evidence_values):
        context = f"given.inputs.navigation_release_asset_evidence[{index}]"
        required = {
            "role",
            "asset_id",
            "state",
            "checked_at",
            "source_reference_ids",
        }
        if not v.require_keys(evidence, required, context):
            continue
        role = evidence["role"]
        asset_id = evidence["asset_id"]
        if role not in NAVIGATION_RELEASE_ASSET_ROLES:
            v.add(f"{context}.role is unknown")
            continue
        if not isinstance(asset_id, str) or not asset_id.strip():
            v.add(f"{context}.asset_id must be non-empty")
            continue
        key = (role, asset_id)
        if key in evidence_by_key:
            v.add(f"duplicate navigation release asset evidence: {role}:{asset_id}")
        else:
            evidence_by_key[key] = evidence
        if key not in normalized_expected:
            v.add(f"orphan navigation release asset evidence: {role}:{asset_id}")
        if evidence["state"] != "RELEASED":
            v.add(f"{context}.state must be RELEASED")
        if not is_date(evidence["checked_at"]):
            v.add(f"{context}.checked_at must be an ISO date")
        source_ids = evidence["source_reference_ids"]
        if (
            not isinstance(source_ids, list)
            or not source_ids
            or not all(
                isinstance(source_id, str) and source_id.strip()
                for source_id in source_ids
            )
            or len(source_ids) != len(set(source_ids))
        ):
            v.add(f"{context}.source_reference_ids must be unique non-empty strings")
            source_ids = []
        for source_id in source_ids:
            used_source_ids.add(source_id)
            source = source_by_id.get(source_id)
            if source is None:
                v.add(f"{context} references unknown source {source_id!r}")
            elif role not in source.get("roles", []):
                v.add(f"{context} source {source_id!r} does not support role {role}")
        if role == "JUNCTION_VIEW":
            view = junction_view_by_id.get(asset_id)
            embedded = view.get("evidence") if isinstance(view, dict) else None
            embedded_source_ids = (
                embedded.get("source_reference_ids")
                if isinstance(embedded, dict)
                else None
            )
            if (
                not isinstance(embedded, dict)
                or not isinstance(embedded_source_ids, list)
                or not all(
                    isinstance(source_id, str)
                    for source_id in embedded_source_ids
                )
                or evidence["checked_at"] != embedded.get("checked_at")
                or set(source_ids) != set(embedded_source_ids)
            ):
                v.add(f"{context} must match embedded junction-view evidence")

    for role, asset_id in sorted(normalized_expected):
        if (role, asset_id) not in evidence_by_key:
            v.add(f"missing navigation release asset evidence: {role}:{asset_id}")
    for source_id in source_by_id:
        if source_id not in used_source_ids:
            v.add(f"orphan navigation release source: {source_id}")


def validate_timeline(v: Validation, events: Any) -> set[str]:
    if not isinstance(events, list) or not events:
        v.add("when must be a non-empty array")
        return set()

    event_ids: set[str] = set()
    previous_at = -1
    for index, event in enumerate(events):
        context = f"when[{index}]"
        if not v.require_keys(event, {"id", "at_ms", "type", "payload"}, context):
            continue
        event_id = event["id"]
        if not isinstance(event_id, str) or not SLUG_RE.fullmatch(event_id):
            v.add(f"{context}.id must be a lowercase stable identifier")
        elif event_id in event_ids:
            v.add(f"duplicate event id: {event_id}")
        event_ids.add(event_id)
        at_ms = event["at_ms"]
        if not isinstance(at_ms, int) or isinstance(at_ms, bool) or at_ms < 0:
            v.add(f"{context}.at_ms must be a non-negative integer")
        elif at_ms < previous_at:
            v.add(f"{context}.at_ms must not move backwards")
        else:
            previous_at = at_ms
        if event["type"] not in EVENT_TYPES:
            v.add(f"{context}.type is unknown: {event['type']!r}")
        if not isinstance(event["payload"], dict):
            v.add(f"{context}.payload must be an object")
    return event_ids


def validate_assertions(v: Validation, assertions: Any, event_ids: set[str]) -> None:
    if not isinstance(assertions, list) or not assertions:
        v.add("then must be a non-empty array")
        return

    assertion_ids: set[str] = set()
    for index, assertion in enumerate(assertions):
        context = f"then[{index}]"
        required = {"id", "after", "category", "subject", "matcher", "rationale"}
        if not v.require_keys(assertion, required, context):
            continue
        assertion_id = assertion["id"]
        if not isinstance(assertion_id, str) or not SLUG_RE.fullmatch(assertion_id):
            v.add(f"{context}.id must be a lowercase stable identifier")
        elif assertion_id in assertion_ids:
            v.add(f"duplicate assertion id: {assertion_id}")
        assertion_ids.add(assertion_id)
        after = assertion["after"]
        if after != "INITIAL" and after not in event_ids:
            v.add(f"{context}.after references unknown event: {after!r}")
        if assertion["category"] not in ASSERTION_CATEGORIES:
            v.add(f"{context}.category is unknown: {assertion['category']!r}")
        matcher = assertion["matcher"]
        if matcher not in MATCHERS:
            v.add(f"{context}.matcher is unknown: {matcher!r}")
        if matcher not in {"PRESENT", "ABSENT"} and "expected" not in assertion:
            v.add(f"{context}.expected is required for matcher {matcher}")
        if not isinstance(assertion["subject"], str) or not assertion["subject"].strip():
            v.add(f"{context}.subject must be non-empty")
        if not isinstance(assertion["rationale"], str) or not assertion["rationale"].strip():
            v.add(f"{context}.rationale must be non-empty")


def validate_scenario(path: Path, seen_ids: set[str]) -> list[str]:
    v = Validation(path)
    try:
        scenario = load_json(path)
    except (OSError, json.JSONDecodeError) as error:
        v.add(f"cannot parse JSON: {error}")
        return v.errors

    required = {
        "schema_version",
        "id",
        "title",
        "layer",
        "tags",
        "purpose",
        "evidence",
        "given",
        "when",
        "then",
    }
    if not v.require_keys(scenario, required, "scenario"):
        return v.errors

    if scenario["schema_version"] != "1.0":
        v.add("schema_version must be '1.0'")
    scenario_id = scenario["id"]
    if not isinstance(scenario_id, str) or not ID_RE.fullmatch(scenario_id):
        v.add("id must match KR-[A-Z][0-9][0-9]")
    elif scenario_id in seen_ids:
        v.add(f"duplicate scenario id: {scenario_id}")
    seen_ids.add(scenario_id)
    if scenario["layer"] not in LAYERS:
        v.add(f"unknown layer: {scenario['layer']!r}")
    if not isinstance(scenario["tags"], list) or not scenario["tags"]:
        v.add("tags must be a non-empty array")
    elif len(scenario["tags"]) != len(set(scenario["tags"])):
        v.add("tags must be unique")

    validate_evidence(v, scenario["evidence"])
    given = scenario["given"]
    if v.require_keys(given, {"network_snapshot", "inputs", "system_state"}, "given"):
        validate_snapshot(v, given["network_snapshot"])
        if "route_plan" in given:
            validate_route_plan(
                v,
                given["route_plan"],
                given["network_snapshot"].get("id")
                if isinstance(given["network_snapshot"], dict)
                else None,
            )
        if "tariff_quotes" in given:
            validate_tariff_quotes(v, given["tariff_quotes"])
        validate_guidance_anchors(v, given)
        validate_entrance_recommendation(v, given)
        validate_matcher_guidance_inputs(v, given)
        validate_expert_route_editor(v, given)
        validate_released_guidance(v, given)
        validate_navigation_release_artifact(v, given)
        if not isinstance(given["inputs"], dict):
            v.add("given.inputs must be an object")
        if not isinstance(given["system_state"], dict):
            v.add("given.system_state must be an object")

    event_ids = validate_timeline(v, scenario["when"])
    validate_assertions(v, scenario["then"], event_ids)
    return v.errors


def main() -> int:
    try:
        load_json(SCHEMA_PATH)
    except (OSError, json.JSONDecodeError) as error:
        print(f"FAIL: cannot parse {SCHEMA_PATH.relative_to(ROOT)}: {error}", file=sys.stderr)
        return 1

    paths = sorted(SCENARIO_DIR.glob("*.json"))
    if not paths:
        print(f"FAIL: no scenarios found under {SCENARIO_DIR.relative_to(ROOT)}", file=sys.stderr)
        return 1

    seen_ids: set[str] = set()
    errors: list[str] = []
    for path in paths:
        errors.extend(validate_scenario(path, seen_ids))

    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1

    print(f"PASS: parsed schema and validated {len(paths)} portable E2E scenarios")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
