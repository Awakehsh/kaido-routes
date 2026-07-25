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
from urllib.parse import urlparse


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
SHUTO_VEHICLE_CLASSES = {
    "LIGHT_MOTORCYCLE",
    "STANDARD",
    "MEDIUM",
    "LARGE",
    "EXTRA_LARGE",
}
SHUTO_PAYMENT_METHODS = {"ETC", "CASH"}
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
    "EDITOR_PRESENTATION",
    "RUNTIME_POLICY",
    "MATCHER_CORRIDOR",
    "DECISION_ZONE",
    "GUIDANCE",
    "JUNCTION_VIEW",
}
RELEASE_LOCALES = {"ja-JP", "zh-Hans", "en"}
PRODUCT_RUNTIME_EVIDENCE_SCOPES = {
    "SYNTHETIC_TEST_ONLY",
    "RELEASED_ROAD",
}
PRODUCT_LIVE_INPUT_POLICIES = {
    "DISABLED",
    "FOREGROUND_WHEN_IN_USE",
}
SAVED_ROUTE_ORIGINS = {"AUTHORED_HERE", "SHARED_IMPORT"}
SAVED_ROUTE_PLAN_RELATIONS = {"EXACT", "SNAPSHOT_DRIFT"}
EVENT_TYPES = {
    "ROUTE_COMPILE_REQUESTED",
    "SAVED_ROUTE_LIBRARY_LIFECYCLE_REQUESTED",
    "ROUTE_EDITOR_STARTED",
    "ROUTE_EDITOR_CHOICE_SELECTED",
    "ROUTE_EDITOR_CORRIDOR_MATCH_SUBMITTED",
    "ROUTE_EDITOR_CORRIDOR_RESOLUTION_REQUESTED",
    "ROUTE_EDITOR_LAP_DUPLICATION_REQUESTED",
    "ROUTE_EDITOR_UNDO_REQUESTED",
    "ROUTE_EDITOR_COMPILE_REQUESTED",
    "NAVIGATION_RELEASE_BUNDLE_VALIDATED",
    "NAVIGATION_RELEASE_ARTIFACT_VALIDATED",
    "NAVIGATION_RELEASE_ARTIFACT_AUTHORED",
    "PRODUCT_RELEASE_ARTIFACT_VALIDATED",
    "PRODUCT_RUNTIME_USE_EVALUATED",
    "PRODUCT_NAVIGATION_RUNTIME_CREATED",
    "ROUTE_ATLAS_RELEASE_VALIDATED",
    "ROUTE_ATLAS_RELEASE_AUTHORED",
    "PRE_DRIVE_EVIDENCE_BUNDLE_RESOLVED",
    "ROUTE_ATLAS_CONTEXT_VALIDATED",
    "NAVIGATION_STARTED",
    "LOCATION_UPDATED",
    "ENTRY_TRANSITION_EVIDENCE_OBSERVED",
    "SURFACE_EGRESS_MATCHER_OBSERVATION_RECEIVED",
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
        "entry_facility_id",
        "exit_facility_id",
        "status",
        "vehicle_class",
        "payment_method",
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
        if quote["vehicle_class"] not in SHUTO_VEHICLE_CLASSES:
            v.add(f"{context}.vehicle_class is unknown: {quote['vehicle_class']!r}")
        if quote["payment_method"] not in SHUTO_PAYMENT_METHODS:
            v.add(f"{context}.payment_method is unknown: {quote['payment_method']!r}")
        for field in (
            "entry_facility_id",
            "exit_facility_id",
            "vehicle_class",
            "tariff_version_id",
        ):
            if not isinstance(quote[field], str) or not quote[field].strip():
                v.add(f"{context}.{field} must be non-empty")
        if not is_datetime(quote["checked_at"]):
            v.add(f"{context}.checked_at must be an ISO date-time")
        reference = quote["official_query_reference"]
        parsed_reference = urlparse(reference) if isinstance(reference, str) else None
        if (
            parsed_reference is None
            or parsed_reference.scheme.lower() != "https"
            or not parsed_reference.netloc
        ):
            v.add(f"{context}.official_query_reference must be an HTTPS URI")
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
        if quote["status"] != "UNKNOWN" and (distance is None or amount is None):
            v.add(
                f"{context} requires tariff distance and amount for "
                f"{quote['status']}"
            )


def validate_pre_drive_evidence(v: Validation, given: dict[str, Any]) -> None:
    inputs = given.get("inputs")
    if not isinstance(inputs, dict) or "pre_drive_evidence" not in inputs:
        return
    evidence = inputs["pre_drive_evidence"]
    context = "given.inputs.pre_drive_evidence"
    session = inputs.get("pre_drive_session")
    session_context = "given.inputs.pre_drive_session"
    session_required = {
        "network_snapshot_id",
        "route_plan_id",
        "vehicle_class",
        "payment_method",
    }
    if not isinstance(session, dict):
        v.add(f"{context} requires {session_context}")
        return
    if not v.require_keys(session, session_required, session_context):
        return
    required = {
        "evaluated_at",
        "network_snapshot_id",
        "route_plan_id",
        "vehicle_class",
        "payment_method",
        "passage_evidence",
    }
    if not v.require_keys(evidence, required, context):
        return
    route_plan = given.get("route_plan")
    if not isinstance(route_plan, dict):
        v.add(f"{context} requires given.route_plan")
        return
    if session["network_snapshot_id"] != route_plan.get("network_snapshot_id"):
        v.add(f"{session_context}.network_snapshot_id must match given.route_plan")
    if session["route_plan_id"] != route_plan.get("plan_id"):
        v.add(f"{session_context}.route_plan_id must match given.route_plan")
    session_vehicle_class = session["vehicle_class"]
    if session_vehicle_class not in SHUTO_VEHICLE_CLASSES:
        v.add(f"{session_context}.vehicle_class is unknown")
    session_payment_method = session["payment_method"]
    if session_payment_method not in SHUTO_PAYMENT_METHODS:
        v.add(f"{session_context}.payment_method is unknown")
    if evidence["network_snapshot_id"] != route_plan.get("network_snapshot_id"):
        v.add(f"{context}.network_snapshot_id must match given.route_plan")
    if evidence["route_plan_id"] != route_plan.get("plan_id"):
        v.add(f"{context}.route_plan_id must match given.route_plan")
    vehicle_class = evidence["vehicle_class"]
    if vehicle_class not in SHUTO_VEHICLE_CLASSES:
        v.add(f"{context}.vehicle_class is unknown")
    if vehicle_class != session_vehicle_class:
        v.add(f"{context}.vehicle_class must match pre-drive session")
    payment_method = evidence["payment_method"]
    if payment_method not in SHUTO_PAYMENT_METHODS:
        v.add(f"{context}.payment_method is unknown")
    if payment_method != session_payment_method:
        v.add(f"{context}.payment_method must match pre-drive session")
    if not is_datetime(evidence["evaluated_at"]):
        v.add(f"{context}.evaluated_at must be an ISO date-time")
    passage_states = {
        "KNOWN_CLOSED",
        "PLANNED_CONFLICT",
        "NO_KNOWN_CONFLICT_REALTIME_UNCONFIRMED",
        "REALTIME_CONFIRMED_PASSABLE",
    }
    if evidence["passage_evidence"] not in passage_states:
        v.add(f"{context}.passage_evidence is unknown")
    quotes = given.get("tariff_quotes")
    if not isinstance(quotes, list) or not quotes:
        v.add(f"{context} requires at least one tariff quote")
        return
    entry_id = route_plan.get("entry_facility_id")
    exit_id = route_plan.get("exit_facility_id")
    for index, quote in enumerate(quotes):
        if not isinstance(quote, dict):
            continue
        if quote.get("entry_facility_id") != entry_id:
            v.add(
                f"given.tariff_quotes[{index}].entry_facility_id "
                "must match given.route_plan"
            )
        if quote.get("exit_facility_id") != exit_id:
            v.add(
                f"given.tariff_quotes[{index}].exit_facility_id "
                "must match given.route_plan"
            )
        if quote.get("vehicle_class") != vehicle_class:
            v.add(
                f"given.tariff_quotes[{index}].vehicle_class "
                "must match pre-drive evidence"
            )
        if quote.get("payment_method") != payment_method:
            v.add(
                f"given.tariff_quotes[{index}].payment_method "
                "must match pre-drive evidence"
            )
        checked_at = quote.get("checked_at")
        if is_datetime(checked_at) and is_datetime(evidence["evaluated_at"]):
            checked = datetime.fromisoformat(checked_at.replace("Z", "+00:00"))
            evaluated = datetime.fromisoformat(
                evidence["evaluated_at"].replace("Z", "+00:00")
            )
            if checked > evaluated:
                v.add(
                    f"given.tariff_quotes[{index}].checked_at "
                    "must not postdate pre-drive evaluation"
                )


def validate_pre_drive_evidence_bundle(
    v: Validation,
    given: dict[str, Any],
    events: Any,
) -> None:
    inputs = given.get("inputs")
    if not isinstance(inputs, dict) or "pre_drive_evidence_bundle" not in inputs:
        return
    manifest = inputs["pre_drive_evidence_bundle"]
    context = "given.inputs.pre_drive_evidence_bundle"
    required = {
        "schema_version",
        "release_id",
        "released_at",
        "evidence_scope",
        "product_release_id",
        "navigation_release_id",
        "network_snapshot_id",
        "route_plan_id",
        "source_registry",
        "records",
    }
    if not v.require_keys(manifest, required, context):
        return
    route_plan = given.get("route_plan")
    session = inputs.get("pre_drive_session")
    if not isinstance(route_plan, dict):
        v.add(f"{context} requires given.route_plan")
        return
    if not isinstance(session, dict):
        v.add(f"{context} requires given.inputs.pre_drive_session")
        return
    if manifest["schema_version"] != "1.0":
        v.add(f"{context}.schema_version must be '1.0'")
    for field in ("release_id", "product_release_id", "navigation_release_id"):
        if not isinstance(manifest[field], str) or not manifest[field].strip():
            v.add(f"{context}.{field} must be non-empty")
    if manifest["evidence_scope"] not in PRODUCT_RUNTIME_EVIDENCE_SCOPES:
        v.add(f"{context}.evidence_scope is unknown")
    if manifest["network_snapshot_id"] != route_plan.get("network_snapshot_id"):
        v.add(f"{context}.network_snapshot_id must match given.route_plan")
    if manifest["route_plan_id"] != route_plan.get("plan_id"):
        v.add(f"{context}.route_plan_id must match given.route_plan")
    if not is_datetime(manifest["released_at"]):
        v.add(f"{context}.released_at must be an ISO date-time")
        released_at = None
    else:
        released_at = datetime.fromisoformat(
            manifest["released_at"].replace("Z", "+00:00")
        )

    sources = manifest["source_registry"]
    sources_by_id: dict[str, dict[str, Any]] = {}
    if not isinstance(sources, list) or not sources:
        v.add(f"{context}.source_registry must be a non-empty array")
        sources = []
    for index, source in enumerate(sources):
        source_context = f"{context}.source_registry[{index}]"
        source_required = {
            "source_reference_id",
            "roles",
            "authority_name",
            "source_url",
            "content_sha256",
            "checked_at",
            "reviewer_id",
            "reviewed_at",
        }
        if not v.require_keys(source, source_required, source_context):
            continue
        source_id = source["source_reference_id"]
        if not isinstance(source_id, str) or not source_id.strip():
            v.add(f"{source_context}.source_reference_id must be non-empty")
            continue
        if source_id in sources_by_id:
            v.add(f"{source_context}.source_reference_id must be unique")
        sources_by_id[source_id] = source
        roles = source["roles"]
        if (
            not isinstance(roles, list)
            or not roles
            or len(roles) != len(set(roles))
            or any(role not in {"TARIFF_QUERY", "PASSAGE_REVIEW"} for role in roles)
        ):
            v.add(f"{source_context}.roles are invalid")
        for field in ("authority_name", "reviewer_id"):
            if not isinstance(source[field], str) or not source[field].strip():
                v.add(f"{source_context}.{field} must be non-empty")
        parsed_url = (
            urlparse(source["source_url"])
            if isinstance(source["source_url"], str)
            else None
        )
        if (
            parsed_url is None
            or parsed_url.scheme.lower() != "https"
            or not parsed_url.netloc
        ):
            v.add(f"{source_context}.source_url must be an HTTPS URI")
        digest = source["content_sha256"]
        if not isinstance(digest, str) or re.fullmatch(r"[0-9a-fA-F]{64}", digest) is None:
            v.add(f"{source_context}.content_sha256 must be SHA-256")
        checked_at = source["checked_at"]
        reviewed_at = source["reviewed_at"]
        if not is_datetime(checked_at):
            v.add(f"{source_context}.checked_at must be an ISO date-time")
        if not is_datetime(reviewed_at):
            v.add(f"{source_context}.reviewed_at must be an ISO date-time")
        if is_datetime(checked_at) and is_datetime(reviewed_at):
            checked = datetime.fromisoformat(checked_at.replace("Z", "+00:00"))
            reviewed = datetime.fromisoformat(reviewed_at.replace("Z", "+00:00"))
            if checked > reviewed:
                v.add(f"{source_context}.checked_at must not postdate review")
            if released_at is not None and reviewed > released_at:
                v.add(f"{source_context}.reviewed_at must not postdate release")

    records = manifest["records"]
    record_ids: set[str] = set()
    profiles: set[tuple[str, str]] = set()
    referenced_source_ids: set[str] = set()
    if not isinstance(records, list) or not records:
        v.add(f"{context}.records must be a non-empty array")
        records = []
    for index, record in enumerate(records):
        record_context = f"{context}.records[{index}]"
        record_required = {
            "record_id",
            "valid_from",
            "expires_at",
            "source_reference_ids",
            "evidence",
        }
        if not v.require_keys(record, record_required, record_context):
            continue
        record_id = record["record_id"]
        if not isinstance(record_id, str) or not record_id.strip():
            v.add(f"{record_context}.record_id must be non-empty")
        elif record_id in record_ids:
            v.add(f"{record_context}.record_id must be unique")
        record_ids.add(record_id)
        evidence = record["evidence"]
        evidence_required = {
            "evaluated_at",
            "network_snapshot_id",
            "route_plan_id",
            "vehicle_class",
            "payment_method",
            "passage_evidence",
            "tariff_quotes",
        }
        if not v.require_keys(evidence, evidence_required, f"{record_context}.evidence"):
            continue
        if evidence["network_snapshot_id"] != route_plan.get("network_snapshot_id"):
            v.add(f"{record_context}.evidence.network_snapshot_id must match route")
        if evidence["route_plan_id"] != route_plan.get("plan_id"):
            v.add(f"{record_context}.evidence.route_plan_id must match route")
        vehicle_class = evidence["vehicle_class"]
        payment_method = evidence["payment_method"]
        if vehicle_class not in SHUTO_VEHICLE_CLASSES:
            v.add(f"{record_context}.evidence.vehicle_class is unknown")
        if payment_method not in SHUTO_PAYMENT_METHODS:
            v.add(f"{record_context}.evidence.payment_method is unknown")
        profile = (vehicle_class, payment_method)
        if profile in profiles:
            v.add(f"{record_context} duplicates a tariff profile")
        profiles.add(profile)
        if evidence["passage_evidence"] == "REALTIME_CONFIRMED_PASSABLE":
            v.add(f"{record_context}.evidence cannot claim realtime authority")
        for field in ("evaluated_at",):
            if not is_datetime(evidence[field]):
                v.add(f"{record_context}.evidence.{field} must be an ISO date-time")
        if not is_datetime(record["valid_from"]):
            v.add(f"{record_context}.valid_from must be an ISO date-time")
        if not is_datetime(record["expires_at"]):
            v.add(f"{record_context}.expires_at must be an ISO date-time")
        if (
            released_at is not None
            and is_datetime(evidence["evaluated_at"])
            and is_datetime(record["valid_from"])
            and is_datetime(record["expires_at"])
        ):
            evaluated = datetime.fromisoformat(
                evidence["evaluated_at"].replace("Z", "+00:00")
            )
            valid_from = datetime.fromisoformat(
                record["valid_from"].replace("Z", "+00:00")
            )
            expires_at = datetime.fromisoformat(
                record["expires_at"].replace("Z", "+00:00")
            )
            if not evaluated <= valid_from <= released_at < expires_at:
                v.add(f"{record_context} has an invalid validity chronology")
        source_ids = record["source_reference_ids"]
        if (
            not isinstance(source_ids, list)
            or not source_ids
            or len(source_ids) != len(set(source_ids))
        ):
            v.add(f"{record_context}.source_reference_ids are invalid")
            source_ids = []
        roles: set[str] = set()
        for source_id in source_ids:
            referenced_source_ids.add(source_id)
            source = sources_by_id.get(source_id)
            if source is None:
                v.add(f"{record_context} references unknown source {source_id!r}")
            else:
                source_roles = source["roles"]
                if isinstance(source_roles, list):
                    roles.update(source_roles)
                if (
                    is_datetime(source["checked_at"])
                    and is_datetime(evidence["evaluated_at"])
                ):
                    source_checked_at = datetime.fromisoformat(
                        source["checked_at"].replace("Z", "+00:00")
                    )
                    evidence_evaluated_at = datetime.fromisoformat(
                        evidence["evaluated_at"].replace("Z", "+00:00")
                    )
                    if source_checked_at > evidence_evaluated_at:
                        v.add(
                            f"{record_context} source {source_id!r} "
                            "must not postdate evidence evaluation"
                        )
        for role in ("TARIFF_QUERY", "PASSAGE_REVIEW"):
            if role not in roles:
                v.add(f"{record_context} requires {role}")
        quotes = evidence["tariff_quotes"]
        temporary_given = {
            "tariff_quotes": quotes,
            "route_plan": route_plan,
            "inputs": {
                "pre_drive_evidence": {
                    key: evidence[key]
                    for key in (
                        "evaluated_at",
                        "network_snapshot_id",
                        "route_plan_id",
                        "vehicle_class",
                        "payment_method",
                        "passage_evidence",
                    )
                },
                "pre_drive_session": {
                    "network_snapshot_id": evidence["network_snapshot_id"],
                    "route_plan_id": evidence["route_plan_id"],
                    "vehicle_class": vehicle_class,
                    "payment_method": payment_method,
                },
            },
        }
        validate_tariff_quotes(v, quotes)
        validate_pre_drive_evidence(v, temporary_given)

    for source_id in sources_by_id.keys() - referenced_source_ids:
        v.add(f"{context}.source_registry contains orphan {source_id!r}")

    if not isinstance(events, list):
        return
    allowed_payload_keys = {
        "product_release_id",
        "product_released_at",
        "navigation_release_id",
        "evidence_scope",
        "resolved_at",
        "vehicle_class",
        "payment_method",
    }
    for index, event in enumerate(events):
        if (
            not isinstance(event, dict)
            or event.get("type") != "PRE_DRIVE_EVIDENCE_BUNDLE_RESOLVED"
        ):
            continue
        payload = event.get("payload")
        event_context = (
            f"when[{index}] PRE_DRIVE_EVIDENCE_BUNDLE_RESOLVED"
        )
        if not isinstance(payload, dict):
            continue
        unsupported = sorted(payload.keys() - allowed_payload_keys)
        if unsupported:
            v.add(
                f"{event_context} payload has unsupported keys: "
                + ", ".join(unsupported)
            )
        for field in (
            "product_release_id",
            "product_released_at",
            "navigation_release_id",
            "evidence_scope",
            "resolved_at",
        ):
            if field not in payload:
                v.add(f"{event_context}.payload.{field} is required")
        if payload.get("product_release_id") != manifest["product_release_id"]:
            v.add(f"{event_context}.payload.product_release_id must match bundle")
        if not is_datetime(payload.get("product_released_at")):
            v.add(
                f"{event_context}.payload.product_released_at "
                "must be an ISO date-time"
            )
        elif released_at is not None:
            product_released_at = datetime.fromisoformat(
                payload["product_released_at"].replace("Z", "+00:00")
            )
            if product_released_at > released_at:
                v.add(
                    f"{event_context}.payload.product_released_at "
                    "must not postdate bundle"
                )
        if payload.get("navigation_release_id") != manifest["navigation_release_id"]:
            v.add(f"{event_context}.payload.navigation_release_id must match bundle")
        if payload.get("evidence_scope") != manifest["evidence_scope"]:
            v.add(f"{event_context}.payload.evidence_scope must match bundle")
        if not is_datetime(payload.get("resolved_at")):
            v.add(f"{event_context}.payload.resolved_at must be an ISO date-time")
        if (
            "vehicle_class" in payload
            and payload["vehicle_class"] not in SHUTO_VEHICLE_CLASSES
        ):
            v.add(f"{event_context}.payload.vehicle_class is unknown")
        if (
            "payment_method" in payload
            and payload["payment_method"] not in SHUTO_PAYMENT_METHODS
        ):
            v.add(f"{event_context}.payload.payment_method is unknown")


def validate_saved_route_library(v: Validation, given: dict[str, Any]) -> None:
    inputs = given.get("inputs")
    if not isinstance(inputs, dict) or "saved_route_library" not in inputs:
        return
    value = inputs["saved_route_library"]
    context = "given.inputs.saved_route_library"
    required = {
        "schema_version",
        "saved_route_id",
        "display_name",
        "saved_at",
        "origin",
        "evidence_state",
        "template_parameters",
        "release_candidates",
    }
    if not v.require_keys(value, required, context):
        return
    if not isinstance(given.get("route_plan"), dict):
        v.add(f"{context} requires given.route_plan")
        return
    for field in ("saved_route_id", "display_name"):
        if not isinstance(value[field], str) or not value[field].strip():
            v.add(f"{context}.{field} must be non-empty")
    if value["schema_version"] != "1.0":
        v.add(f"{context}.schema_version must be '1.0'")
    if not is_datetime(value["saved_at"]):
        v.add(f"{context}.saved_at must be an ISO date-time")
    if value["origin"] not in SAVED_ROUTE_ORIGINS:
        v.add(f"{context}.origin is unknown")
    if value["evidence_state"] not in EVIDENCE_CLASSES - {"SYNTHETIC"}:
        v.add(f"{context}.evidence_state is unknown")
    parameters = value["template_parameters"]
    if not isinstance(parameters, dict) or not all(
        isinstance(key, str)
        and key.strip()
        and isinstance(parameter, str)
        and parameter.strip()
        for key, parameter in parameters.items()
    ):
        v.add(f"{context}.template_parameters must contain non-empty strings")
    candidates = value["release_candidates"]
    if not isinstance(candidates, list):
        v.add(f"{context}.release_candidates must be an array")
        return
    release_ids: set[str] = set()
    for index, candidate in enumerate(candidates):
        candidate_context = f"{context}.release_candidates[{index}]"
        if not v.require_keys(
            candidate,
            {"release_id", "route_plan_relation"},
            candidate_context,
        ):
            continue
        release_id = candidate["release_id"]
        if not isinstance(release_id, str) or not release_id.strip():
            v.add(f"{candidate_context}.release_id must be non-empty")
        elif release_id in release_ids:
            v.add(f"{candidate_context}.release_id must be unique")
        release_ids.add(release_id)
        relation = candidate["route_plan_relation"]
        if relation not in SAVED_ROUTE_PLAN_RELATIONS:
            v.add(f"{candidate_context}.route_plan_relation is unknown")
        if relation == "SNAPSHOT_DRIFT":
            snapshot_id = candidate.get("network_snapshot_id")
            if not isinstance(snapshot_id, str) or not snapshot_id.strip():
                v.add(
                    f"{candidate_context}.network_snapshot_id is required "
                    "for SNAPSHOT_DRIFT"
                )
            elif snapshot_id == given["route_plan"].get("network_snapshot_id"):
                v.add(
                    f"{candidate_context}.network_snapshot_id must differ "
                    "from given.route_plan"
                )
    lifecycle = value.get("lifecycle")
    if lifecycle is not None:
        lifecycle_context = f"{context}.lifecycle"
        required_lifecycle = {
            "imported_record_id",
            "imported_display_name",
            "imported_saved_at",
            "renamed_display_name",
        }
        if v.require_keys(lifecycle, required_lifecycle, lifecycle_context):
            for field in (
                "imported_record_id",
                "imported_display_name",
                "renamed_display_name",
            ):
                if not isinstance(lifecycle[field], str) or not lifecycle[field].strip():
                    v.add(f"{lifecycle_context}.{field} must be non-empty")
            if not is_datetime(lifecycle["imported_saved_at"]):
                v.add(f"{lifecycle_context}.imported_saved_at must be an ISO date-time")
            if lifecycle["imported_record_id"] == value["saved_route_id"]:
                v.add(
                    f"{lifecycle_context}.imported_record_id must differ "
                    "from saved_route_id"
                )


def validate_saved_route_lifecycle_events(
    v: Validation,
    given: dict[str, Any],
    events: Any,
) -> None:
    inputs = given.get("inputs")
    library = (
        inputs.get("saved_route_library")
        if isinstance(inputs, dict)
        else None
    )
    lifecycle = library.get("lifecycle") if isinstance(library, dict) else None
    lifecycle_events = (
        [
            (index, event)
            for index, event in enumerate(events)
            if isinstance(event, dict)
            and event.get("type") == "SAVED_ROUTE_LIBRARY_LIFECYCLE_REQUESTED"
        ]
        if isinstance(events, list)
        else []
    )
    if lifecycle is None:
        for index, _ in lifecycle_events:
            v.add(
                f"when[{index}] SAVED_ROUTE_LIBRARY_LIFECYCLE_REQUESTED "
                "requires given.inputs.saved_route_library.lifecycle"
            )
        return
    if len(lifecycle_events) != 1:
        v.add(
            "given.inputs.saved_route_library.lifecycle requires exactly one "
            "SAVED_ROUTE_LIBRARY_LIFECYCLE_REQUESTED event"
        )
    for index, event in lifecycle_events:
        has_prior_compile = any(
            isinstance(prior, dict)
            and prior.get("type") == "ROUTE_COMPILE_REQUESTED"
            for prior in events[:index]
        )
        if not has_prior_compile:
            v.add(
                f"when[{index}] SAVED_ROUTE_LIBRARY_LIFECYCLE_REQUESTED "
                "requires an earlier ROUTE_COMPILE_REQUESTED event"
            )
        if event.get("payload") != {}:
            v.add(
                f"when[{index}] SAVED_ROUTE_LIBRARY_LIFECYCLE_REQUESTED "
                "payload must be empty"
            )


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


def validate_route_editor_presentation(v: Validation, given: dict[str, Any]) -> None:
    inputs = given.get("inputs")
    if (
        not isinstance(inputs, dict)
        or "route_editor_presentation_catalog" not in inputs
    ):
        return
    presentation = inputs["route_editor_presentation_catalog"]
    editor_catalog = inputs.get("expert_route_editor_catalog")
    if not isinstance(presentation, dict):
        v.add("given.inputs.route_editor_presentation_catalog must be an object")
        return
    if not isinstance(editor_catalog, dict):
        v.add(
            "route editor presentation requires expert_route_editor_catalog"
        )
        return
    required = {
        "presentation_catalog_id",
        "network_snapshot_id",
        "entrances",
        "decision_points",
        "choices",
    }
    if not v.require_keys(
        presentation,
        required,
        "given.inputs.route_editor_presentation_catalog",
    ):
        return
    if (
        not isinstance(presentation["presentation_catalog_id"], str)
        or not presentation["presentation_catalog_id"].strip()
    ):
        v.add(
            "given.inputs.route_editor_presentation_catalog."
            "presentation_catalog_id must be non-empty"
        )
    if presentation["network_snapshot_id"] != editor_catalog.get(
        "network_snapshot_id"
    ):
        v.add(
            "route editor presentation network_snapshot_id must match "
            "expert_route_editor_catalog"
        )

    expected_ids = {
        "entrances": {
            item.get("facility_id")
            for item in editor_catalog.get("entrances", [])
            if isinstance(item, dict)
            and isinstance(item.get("facility_id"), str)
        },
        "decision_points": {
            item.get("decision_point_id")
            for item in editor_catalog.get("decision_points", [])
            if isinstance(item, dict)
            and isinstance(item.get("decision_point_id"), str)
        },
        "choices": {
            choice.get("choice_id")
            for decision in editor_catalog.get("decision_points", [])
            if isinstance(decision, dict)
            for choice in decision.get("choices", [])
            if isinstance(choice, dict)
            and isinstance(choice.get("choice_id"), str)
        },
    }
    id_fields = {
        "entrances": "facility_id",
        "decision_points": "decision_point_id",
        "choices": "choice_id",
    }

    def validate_localized_text(value: Any, context: str) -> None:
        if not isinstance(value, dict) or set(value.keys()) != RELEASE_LOCALES:
            v.add(f"{context} must cover every release locale exactly")
            return
        for locale, text in value.items():
            if not isinstance(text, str) or not text.strip():
                v.add(f"{context}.{locale} must be non-empty")

    for collection, id_field in id_fields.items():
        values = presentation[collection]
        if not isinstance(values, list) or not values:
            v.add(
                "given.inputs.route_editor_presentation_catalog."
                f"{collection} must be a non-empty array"
            )
            continue
        actual_ids: list[str] = []
        for index, item in enumerate(values):
            context = (
                "given.inputs.route_editor_presentation_catalog."
                f"{collection}[{index}]"
            )
            if not isinstance(item, dict):
                v.add(f"{context} must be an object")
                continue
            required_fields = {id_field, "title"}
            if collection == "choices":
                required_fields.add("detail")
            if not v.require_keys(item, required_fields, context):
                continue
            item_id = item[id_field]
            if not isinstance(item_id, str) or not item_id.strip():
                v.add(f"{context}.{id_field} must be non-empty")
            else:
                actual_ids.append(item_id)
            validate_localized_text(item["title"], f"{context}.title")
            if collection == "choices":
                validate_localized_text(item["detail"], f"{context}.detail")
        if len(actual_ids) != len(set(actual_ids)):
            v.add(
                f"route editor presentation {collection} IDs must be unique"
            )
        if set(actual_ids) != expected_ids[collection]:
            v.add(
                f"route editor presentation {collection} must exactly cover "
                "the expert editor catalog"
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


def validate_navigation_runtime_policy(
    v: Validation, given: dict[str, Any]
) -> None:
    inputs = given.get("inputs")
    if not isinstance(inputs, dict) or "navigation_runtime_policy" not in inputs:
        return

    policy = inputs["navigation_runtime_policy"]
    required = {
        "runtime_policy_id",
        "network_snapshot_id",
        "route_plan_id",
        "entry_transition",
        "recovery_candidates",
        "egress_options",
    }
    if not v.require_keys(
        policy,
        required,
        "given.inputs.navigation_runtime_policy",
    ):
        return

    route_plan = given.get("route_plan")
    snapshot = given.get("network_snapshot")
    if not isinstance(route_plan, dict) or not isinstance(snapshot, dict):
        v.add(
            "given.inputs.navigation_runtime_policy requires a network snapshot "
            "and RoutePlan"
        )
        return

    context = "given.inputs.navigation_runtime_policy"
    for field in ("runtime_policy_id", "network_snapshot_id", "route_plan_id"):
        if not isinstance(policy[field], str) or not policy[field].strip():
            v.add(f"{context}.{field} must be non-empty")
    if policy["network_snapshot_id"] != snapshot.get("id"):
        v.add(f"{context}.network_snapshot_id must match given.network_snapshot.id")
    if policy["route_plan_id"] != route_plan.get("plan_id"):
        v.add(f"{context}.route_plan_id must match given.route_plan.plan_id")

    occurrences = route_plan.get("occurrences")
    occurrence_by_id = (
        {
            occurrence.get("occurrence_id"): occurrence
            for occurrence in occurrences
            if isinstance(occurrence, dict)
            and isinstance(occurrence.get("occurrence_id"), str)
        }
        if isinstance(occurrences, list)
        else {}
    )
    occurrence_ids = set(occurrence_by_id)
    first_occurrence_id = (
        occurrences[0].get("occurrence_id")
        if isinstance(occurrences, list)
        and occurrences
        and isinstance(occurrences[0], dict)
        else None
    )

    entry = policy["entry_transition"]
    entry_required = {
        "facility_id",
        "directed_edge_ids",
        "first_route_occurrence_id",
    }
    if v.require_keys(entry, entry_required, f"{context}.entry_transition"):
        if entry["facility_id"] != route_plan.get("entry_facility_id"):
            v.add(
                f"{context}.entry_transition.facility_id must match "
                "given.route_plan.entry_facility_id"
            )
        edge_ids = entry["directed_edge_ids"]
        if (
            not isinstance(edge_ids, list)
            or not edge_ids
            or not all(
                isinstance(edge_id, str) and edge_id.strip()
                for edge_id in edge_ids
            )
            or len(edge_ids) != len(set(edge_ids))
        ):
            v.add(
                f"{context}.entry_transition.directed_edge_ids must be "
                "unique non-empty strings"
            )
        if entry["first_route_occurrence_id"] != first_occurrence_id:
            v.add(
                f"{context}.entry_transition.first_route_occurrence_id must "
                "name the first RoutePlan occurrence"
            )
        corridor = inputs.get("matcher_corridor")
        if not isinstance(corridor, dict):
            v.add(f"{context}.entry_transition requires given.inputs.matcher_corridor")
        elif isinstance(edge_ids, list) and all(
            isinstance(edge_id, str) and edge_id.strip() for edge_id in edge_ids
        ):
            corridor_edges = corridor.get("edges")
            edge_by_id = {
                edge.get("directed_edge_id"): edge
                for edge in corridor_edges
                if isinstance(edge, dict)
                and isinstance(edge.get("directed_edge_id"), str)
            } if isinstance(corridor_edges, list) else {}
            if len(edge_ids) < 2:
                v.add(
                    f"{context}.entry_transition requires at least two "
                    "reviewed directed edges"
                )
            for edge_id in edge_ids:
                if edge_id not in edge_by_id:
                    v.add(
                        f"{context}.entry_transition edge {edge_id!r} "
                        "is missing from matcher_corridor"
                    )
            for current_id, next_id in zip(edge_ids, edge_ids[1:]):
                successors = edge_by_id.get(current_id, {}).get("successor_edge_ids")
                if not isinstance(successors, list) or next_id not in successors:
                    v.add(
                        f"{context}.entry_transition edge {current_id!r} "
                        f"does not lead to {next_id!r}"
                    )
            corridor_occurrences = corridor.get("occurrences")
            first_binding = next(
                (
                    occurrence
                    for occurrence in corridor_occurrences
                    if isinstance(occurrence, dict)
                    and occurrence.get("occurrence_id") == first_occurrence_id
                ),
                None,
            ) if isinstance(corridor_occurrences, list) else None
            first_edge_id = (
                first_binding.get("directed_edge_id")
                if isinstance(first_binding, dict)
                else None
            )
            final_edge_id = edge_ids[-1] if edge_ids else None
            final_successors = edge_by_id.get(final_edge_id, {}).get(
                "successor_edge_ids"
            )
            if (
                not isinstance(first_edge_id, str)
                or (
                    final_edge_id != first_edge_id
                    and (
                        not isinstance(final_successors, list)
                        or first_edge_id not in final_successors
                    )
                )
            ):
                v.add(
                    f"{context}.entry_transition final edge must lead to "
                    "the first RoutePlan occurrence binding"
                )

    recovery_candidates = policy["recovery_candidates"]
    if not isinstance(recovery_candidates, list):
        v.add(f"{context}.recovery_candidates must be an array")
        recovery_candidates = []
    if route_plan.get("recovery_policy") == "SAFE_REJOIN" and not recovery_candidates:
        v.add(f"{context}.recovery_candidates requires a released safe rejoin")
    if route_plan.get("recovery_policy") != "SAFE_REJOIN" and recovery_candidates:
        v.add(
            f"{context}.recovery_candidates are allowed only for SAFE_REJOIN"
        )
    recovery_keys: set[tuple[str, tuple[str, ...], bool, bool]] = set()
    for index, candidate in enumerate(recovery_candidates):
        candidate_context = f"{context}.recovery_candidates[{index}]"
        candidate_required = {
            "target_occurrence_id",
            "recovery_occurrence_ids",
            "released",
            "stays_in_allowed_toll_domain",
        }
        if not v.require_keys(candidate, candidate_required, candidate_context):
            continue
        target_id = candidate["target_occurrence_id"]
        if (
            not isinstance(target_id, str)
            or not target_id.strip()
            or target_id not in occurrence_ids
        ):
            v.add(f"{candidate_context}.target_occurrence_id is unknown")
        else:
            target_index = occurrence_by_id[target_id].get("index")
            first_index = occurrences[0].get("index")
            if (
                not isinstance(target_index, int)
                or isinstance(target_index, bool)
                or not isinstance(first_index, int)
                or isinstance(first_index, bool)
                or target_index <= first_index
            ):
                v.add(
                    f"{candidate_context}.target_occurrence_id must be later "
                    "than the first RoutePlan occurrence"
                )
        recovery_ids = candidate["recovery_occurrence_ids"]
        valid_recovery_ids = (
            isinstance(recovery_ids, list)
            and bool(recovery_ids)
            and all(
                isinstance(occurrence_id, str) and occurrence_id.strip()
                for occurrence_id in recovery_ids
            )
            and len(recovery_ids) == len(set(recovery_ids))
        )
        if not valid_recovery_ids:
            v.add(
                f"{candidate_context}.recovery_occurrence_ids must be "
                "unique non-empty strings"
            )
        if candidate["released"] is not True:
            v.add(f"{candidate_context}.released must be true")
        if candidate["stays_in_allowed_toll_domain"] is not True:
            v.add(
                f"{candidate_context}.stays_in_allowed_toll_domain must be true"
            )
        if isinstance(target_id, str) and valid_recovery_ids:
            key = (
                target_id,
                tuple(recovery_ids),
                candidate["released"] is True,
                candidate["stays_in_allowed_toll_domain"] is True,
            )
            if key in recovery_keys:
                v.add(f"duplicate navigation runtime recovery candidate: {target_id}")
            recovery_keys.add(key)

    egress_options = policy["egress_options"]
    if not isinstance(egress_options, list) or not egress_options:
        v.add(f"{context}.egress_options must contain a released egress")
        egress_options = []
    egress_ids: set[str] = set()
    for index, option in enumerate(egress_options):
        option_context = f"{context}.egress_options[{index}]"
        option_required = {
            "egress_option_id",
            "first_eligible_occurrence_id",
            "exit_facility_id",
            "egress_occurrence_ids",
            "released",
        }
        if not v.require_keys(option, option_required, option_context):
            continue
        option_id = option["egress_option_id"]
        if not isinstance(option_id, str) or not option_id.strip():
            v.add(f"{option_context}.egress_option_id must be non-empty")
        elif option_id in egress_ids:
            v.add(f"duplicate navigation runtime egress option: {option_id}")
        else:
            egress_ids.add(option_id)
        first_eligible = option["first_eligible_occurrence_id"]
        if (
            not isinstance(first_eligible, str)
            or first_eligible not in occurrence_ids
        ):
            v.add(f"{option_context}.first_eligible_occurrence_id is unknown")
        if option["exit_facility_id"] != route_plan.get("exit_facility_id"):
            v.add(
                f"{option_context}.exit_facility_id must match "
                "given.route_plan.exit_facility_id"
            )
        egress_occurrence_ids = option["egress_occurrence_ids"]
        if (
            not isinstance(egress_occurrence_ids, list)
            or not egress_occurrence_ids
            or not all(
                isinstance(occurrence_id, str) and occurrence_id.strip()
                for occurrence_id in egress_occurrence_ids
            )
            or len(egress_occurrence_ids) != len(set(egress_occurrence_ids))
        ):
            v.add(
                f"{option_context}.egress_occurrence_ids must be "
                "unique non-empty strings"
            )
        if option["released"] is not True:
            v.add(f"{option_context}.released must be true")


def validate_entry_transition_admission(
    v: Validation, given: dict[str, Any], events: Any
) -> None:
    inputs = given.get("inputs")
    if not isinstance(inputs, dict) or "entry_transition_admission" not in inputs:
        return
    admission = inputs["entry_transition_admission"]
    context = "given.inputs.entry_transition_admission"
    required = {"product_release_id", "navigation_release_id", "runtime_policy_id"}
    if not v.require_keys(admission, required, context):
        return
    for field in required:
        if not isinstance(admission[field], str) or not admission[field].strip():
            v.add(f"{context}.{field} must be non-empty")

    entry = inputs.get("entry_transition")
    corridor = inputs.get("matcher_corridor")
    route_plan = given.get("route_plan")
    if not isinstance(entry, dict) or not isinstance(corridor, dict) or not isinstance(
        route_plan, dict
    ):
        v.add(
            f"{context} requires entry_transition, matcher_corridor, and route_plan"
        )
        return
    edge_ids = entry.get("directed_edge_ids")
    corridor_edges = corridor.get("edges")
    edge_by_id = {
        edge.get("directed_edge_id"): edge
        for edge in corridor_edges
        if isinstance(edge, dict) and isinstance(edge.get("directed_edge_id"), str)
    } if isinstance(corridor_edges, list) else {}
    if not isinstance(edge_ids, list) or len(edge_ids) < 2:
        v.add(f"{context} requires at least two entry transition edges")
    else:
        for edge_id in edge_ids:
            if edge_id not in edge_by_id:
                v.add(f"{context} entry edge {edge_id!r} is missing from matcher_corridor")
        for current_id, next_id in zip(edge_ids, edge_ids[1:]):
            successors = edge_by_id.get(current_id, {}).get("successor_edge_ids")
            if not isinstance(successors, list) or next_id not in successors:
                v.add(f"{context} entry edge {current_id!r} does not lead to {next_id!r}")

    if not isinstance(events, list):
        return
    for index, event in enumerate(events):
        if not isinstance(event, dict) or event.get("type") != (
            "ENTRY_TRANSITION_EVIDENCE_OBSERVED"
        ):
            continue
        payload = event.get("payload")
        event_context = f"when[{index}].payload"
        required_payload = {
            "observation_id",
            "directed_edge_id",
            "candidate_edge_ids",
            "confidence",
            "heading_error_degrees",
            "source",
        }
        if not v.require_keys(payload, required_payload, event_context):
            continue
        if not isinstance(payload["observation_id"], str) or not payload[
            "observation_id"
        ].strip():
            v.add(f"{event_context}.observation_id must be non-empty")
        if payload["confidence"] not in {"LOST", "LOW", "MEDIUM", "HIGH"}:
            v.add(f"{event_context}.confidence is unknown")
        if payload["source"] != "CORE_LOCATION_ROUTE_AWARE_MATCHER":
            v.add(f"{event_context}.source is unknown")
        candidates = payload["candidate_edge_ids"]
        if not isinstance(candidates, list) or not all(
            isinstance(edge_id, str) and edge_id.strip() for edge_id in candidates
        ):
            v.add(f"{event_context}.candidate_edge_ids must be a string array")
        heading_error = payload["heading_error_degrees"]
        if (
            not isinstance(heading_error, (int, float))
            or isinstance(heading_error, bool)
            or not math.isfinite(heading_error)
            or heading_error < 0
            or heading_error > 180
        ):
            v.add(
                f"{event_context}.heading_error_degrees must be finite from 0 through 180"
            )


def validate_surface_egress_matcher_admission(
    v: Validation, given: dict[str, Any], events: Any
) -> None:
    inputs = given.get("inputs")
    if not isinstance(inputs, dict) or "surface_egress_matcher_admission" not in inputs:
        return
    admission = inputs["surface_egress_matcher_admission"]
    context = "given.inputs.surface_egress_matcher_admission"
    required = {
        "product_release_id",
        "navigation_release_id",
        "journey_plan_id",
        "runtime_policy_id",
        "handoff_anchor_id",
        "corridor_id",
        "provider_dataset_id",
        "candidate_id",
        "egress_option_id",
        "exit_facility_id",
        "occurrences",
    }
    if not v.require_keys(admission, required, context):
        return
    extra = sorted(set(admission) - required)
    if extra:
        v.add(f"{context} has unsupported keys: {', '.join(extra)}")
    for field in required - {"occurrences"}:
        if not isinstance(admission[field], str) or not admission[field].strip():
            v.add(f"{context}.{field} must be non-empty")

    options = inputs.get("precomputed_egress_options")
    option = None
    if isinstance(options, list):
        option = next(
            (
                value
                for value in options
                if isinstance(value, dict)
                and value.get("egress_option_id") == admission.get("egress_option_id")
            ),
            None,
        )
    if (
        not isinstance(option, dict)
        or option.get("released") is not True
        or option.get("exit_facility_id") != admission.get("exit_facility_id")
    ):
        v.add(f"{context} must match one released precomputed egress option")

    occurrences = admission["occurrences"]
    if not isinstance(occurrences, list) or not occurrences:
        v.add(f"{context}.occurrences must be a non-empty array")
        return
    occurrence_ids: set[str] = set()
    geometry_by_edge: dict[str, Any] = {}
    for index, occurrence in enumerate(occurrences):
        occurrence_context = f"{context}.occurrences[{index}]"
        occurrence_required = {
            "occurrence_id",
            "index",
            "directed_edge_id",
            "coordinates",
        }
        if not v.require_keys(occurrence, occurrence_required, occurrence_context):
            continue
        occurrence_extra = sorted(set(occurrence) - occurrence_required)
        if occurrence_extra:
            v.add(
                f"{occurrence_context} has unsupported keys: "
                + ", ".join(occurrence_extra)
            )
        occurrence_id = occurrence["occurrence_id"]
        if not isinstance(occurrence_id, str) or not occurrence_id.strip():
            v.add(f"{occurrence_context}.occurrence_id must be non-empty")
        elif occurrence_id in occurrence_ids:
            v.add(f"{occurrence_context}.occurrence_id must be unique")
        else:
            occurrence_ids.add(occurrence_id)
        if occurrence["index"] != index:
            v.add(f"{occurrence_context}.index must equal path order {index}")
        edge_id = occurrence["directed_edge_id"]
        if not isinstance(edge_id, str) or not edge_id.strip():
            v.add(f"{occurrence_context}.directed_edge_id must be non-empty")
        coordinates = occurrence["coordinates"]
        if not isinstance(coordinates, list) or len(coordinates) < 2:
            v.add(f"{occurrence_context}.coordinates must contain at least two points")
            continue
        for coordinate_index, coordinate in enumerate(coordinates):
            coordinate_context = f"{occurrence_context}.coordinates[{coordinate_index}]"
            if not isinstance(coordinate, dict) or set(coordinate) != {
                "latitude",
                "longitude",
            }:
                v.add(f"{coordinate_context} must contain latitude and longitude")
                continue
            latitude = coordinate["latitude"]
            longitude = coordinate["longitude"]
            if (
                not isinstance(latitude, (int, float))
                or isinstance(latitude, bool)
                or not math.isfinite(latitude)
                or latitude < -90
                or latitude > 90
                or not isinstance(longitude, (int, float))
                or isinstance(longitude, bool)
                or not math.isfinite(longitude)
                or longitude < -180
                or longitude > 180
            ):
                v.add(f"{coordinate_context} is invalid")
        if isinstance(edge_id, str):
            prior_geometry = geometry_by_edge.get(edge_id)
            if prior_geometry is not None and prior_geometry != coordinates:
                v.add(f"{occurrence_context} repeated edge geometry must be identical")
            geometry_by_edge[edge_id] = coordinates

    if not isinstance(events, list):
        return
    for index, event in enumerate(events):
        if (
            not isinstance(event, dict)
            or event.get("type") != "SURFACE_EGRESS_MATCHER_OBSERVATION_RECEIVED"
        ):
            continue
        payload = event.get("payload")
        event_context = f"when[{index}].payload"
        event_required = {
            "observation_id",
            "coordinate",
            "horizontal_accuracy_m",
            "course_degrees",
            "speed_meters_per_second",
            "source",
        }
        if not v.require_keys(payload, event_required, event_context):
            continue
        if (
            not isinstance(payload["observation_id"], str)
            or not payload["observation_id"].strip()
        ):
            v.add(f"{event_context}.observation_id must be non-empty")
        coordinate = payload["coordinate"]
        if not isinstance(coordinate, dict) or set(coordinate) != {
            "latitude",
            "longitude",
        }:
            v.add(f"{event_context}.coordinate must contain latitude and longitude")
        else:
            latitude = coordinate["latitude"]
            longitude = coordinate["longitude"]
            if (
                not isinstance(latitude, (int, float))
                or isinstance(latitude, bool)
                or not math.isfinite(latitude)
                or latitude < -90
                or latitude > 90
                or not isinstance(longitude, (int, float))
                or isinstance(longitude, bool)
                or not math.isfinite(longitude)
                or longitude < -180
                or longitude > 180
            ):
                v.add(f"{event_context}.coordinate is invalid")
        for field in ("horizontal_accuracy_m", "speed_meters_per_second"):
            value = payload[field]
            if (
                not isinstance(value, (int, float))
                or isinstance(value, bool)
                or not math.isfinite(value)
                or value < 0
                or (field == "horizontal_accuracy_m" and value == 0)
            ):
                v.add(f"{event_context}.{field} is invalid")
        course = payload["course_degrees"]
        if (
            not isinstance(course, (int, float))
            or isinstance(course, bool)
            or not math.isfinite(course)
            or course < 0
            or course >= 360
        ):
            v.add(f"{event_context}.course_degrees is invalid")
        if payload["source"] not in {
            "PHONE",
            "WIRED_CARPLAY",
            "WIRELESS_CARPLAY",
            "ACCESSORY",
        }:
            v.add(f"{event_context}.source is unknown")
        if "is_simulated_by_software" in payload and not isinstance(
            payload["is_simulated_by_software"], bool
        ):
            v.add(f"{event_context}.is_simulated_by_software must be boolean")


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
        "route_editor_presentation_catalog",
        "navigation_runtime_policy",
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
        navigation_release_date = None
    else:
        navigation_release_date = datetime.fromisoformat(
            inputs["navigation_release_released_at"].replace("Z", "+00:00")
        ).date()

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
        elif (
            navigation_release_date is not None
            and date.fromisoformat(source["checked_at"]) > navigation_release_date
        ):
            v.add(f"{context}.checked_at cannot follow the navigation release")

    presentation_catalog = inputs["route_editor_presentation_catalog"]
    presentation_catalog_id = (
        presentation_catalog.get("presentation_catalog_id")
        if isinstance(presentation_catalog, dict)
        else None
    )
    expected_keys: list[tuple[str, Any]] = [
        ("EDITOR_CATALOG", inputs["navigation_release_editor_catalog_id"]),
        ("EDITOR_PRESENTATION", presentation_catalog_id),
    ]
    runtime_policy = inputs["navigation_runtime_policy"]
    if isinstance(runtime_policy, dict):
        expected_keys.append(
            ("RUNTIME_POLICY", runtime_policy.get("runtime_policy_id"))
        )
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
        elif (
            navigation_release_date is not None
            and date.fromisoformat(evidence["checked_at"]) > navigation_release_date
        ):
            v.add(f"{context}.checked_at cannot follow the navigation release")
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


def validate_navigation_release_authoring_events(
    v: Validation,
    given: dict[str, Any],
    events: Any,
) -> None:
    if not isinstance(events, list):
        return
    inputs = given.get("inputs")
    has_artifact_inputs = (
        isinstance(inputs, dict)
        and "navigation_release_asset_evidence" in inputs
    )
    allowed_payload_keys = {
        "draft_schema_version",
        "configuration_schema_version",
    }
    for index, event in enumerate(events):
        if (
            not isinstance(event, dict)
            or event.get("type")
            != "NAVIGATION_RELEASE_ARTIFACT_AUTHORED"
        ):
            continue
        if not has_artifact_inputs:
            v.add(
                f"when[{index}] NAVIGATION_RELEASE_ARTIFACT_AUTHORED "
                "requires navigation release artifact inputs"
            )
        payload = event.get("payload")
        if not isinstance(payload, dict):
            continue
        unsupported = sorted(payload.keys() - allowed_payload_keys)
        if unsupported:
            v.add(
                f"when[{index}] NAVIGATION_RELEASE_ARTIFACT_AUTHORED "
                "payload has unsupported keys: "
                + ", ".join(unsupported)
            )
        for key, value in payload.items():
            if key in allowed_payload_keys and (
                not isinstance(value, str) or not value.strip()
            ):
                v.add(f"when[{index}].payload.{key} must be non-empty")


def validate_route_atlas_release_authoring_events(
    v: Validation,
    given: dict[str, Any],
    events: Any,
) -> None:
    if not isinstance(events, list):
        return
    inputs = given.get("inputs")
    required_inputs = {
        "route_atlas_sources",
        "route_atlas_topology",
        "route_atlas",
    }
    has_artifact_inputs = (
        isinstance(given.get("route_plan"), dict)
        and isinstance(inputs, dict)
        and required_inputs.issubset(inputs)
    )
    allowed_payload_keys = {
        "draft_schema_version",
        "configuration_schema_version",
    }
    for index, event in enumerate(events):
        if (
            not isinstance(event, dict)
            or event.get("type") != "ROUTE_ATLAS_RELEASE_AUTHORED"
        ):
            continue
        if not has_artifact_inputs:
            v.add(
                f"when[{index}] ROUTE_ATLAS_RELEASE_AUTHORED "
                "requires Route Atlas release inputs"
            )
        payload = event.get("payload")
        if not isinstance(payload, dict):
            continue
        unsupported = sorted(payload.keys() - allowed_payload_keys)
        if unsupported:
            v.add(
                f"when[{index}] ROUTE_ATLAS_RELEASE_AUTHORED "
                "payload has unsupported keys: "
                + ", ".join(unsupported)
            )
        for key, value in payload.items():
            if key in allowed_payload_keys and (
                not isinstance(value, str) or not value.strip()
            ):
                v.add(f"when[{index}].payload.{key} must be non-empty")


def validate_product_release_artifact(
    v: Validation, given: dict[str, Any]
) -> None:
    inputs = given.get("inputs")
    if not isinstance(inputs, dict) or not any(
        key.startswith("product_release_") for key in inputs
    ):
        return

    required_inputs = {
        "product_release_id",
        "product_release_released_at",
        "product_runtime_evidence_scope",
        "product_live_input_policy",
        "product_release_expected_missing_editor_entity_ids",
        "navigation_release_id",
        "navigation_release_released_at",
        "navigation_release_editor_catalog_id",
        "navigation_release_sources",
        "navigation_release_asset_evidence",
        "expert_route_editor_catalog",
        "route_editor_presentation_catalog",
        "navigation_runtime_policy",
        "matcher_corridor",
        "decision_zones",
        "released_guidance",
        "route_atlas_sources",
        "route_atlas_topology",
        "route_atlas",
    }
    missing = sorted(required_inputs - inputs.keys())
    if missing:
        v.add("product release inputs are missing: " + ", ".join(missing))
        return

    evidence_scope = inputs["product_runtime_evidence_scope"]
    if evidence_scope not in PRODUCT_RUNTIME_EVIDENCE_SCOPES:
        v.add(
            "given.inputs.product_runtime_evidence_scope must be "
            "SYNTHETIC_TEST_ONLY or RELEASED_ROAD"
        )
    live_input_policy = inputs["product_live_input_policy"]
    if live_input_policy not in PRODUCT_LIVE_INPUT_POLICIES:
        v.add(
            "given.inputs.product_live_input_policy must be DISABLED or "
            "FOREGROUND_WHEN_IN_USE"
        )
    if (
        evidence_scope == "SYNTHETIC_TEST_ONLY"
        and live_input_policy != "DISABLED"
    ):
        v.add("synthetic product release live input must be DISABLED")

    source_licences = [
        source.get("licence_identifier")
        for source_key in ("navigation_release_sources", "route_atlas_sources")
        for source in inputs.get(source_key, [])
        if isinstance(source, dict)
    ]
    if evidence_scope == "SYNTHETIC_TEST_ONLY" and any(
        licence != "SYNTHETIC_TEST_ONLY" for licence in source_licences
    ):
        v.add("synthetic product runtime sources must be SYNTHETIC_TEST_ONLY")
    if evidence_scope == "RELEASED_ROAD" and any(
        licence == "SYNTHETIC_TEST_ONLY" for licence in source_licences
    ):
        v.add("released-road product runtime cannot contain synthetic sources")

    release_id = inputs["product_release_id"]
    if not isinstance(release_id, str) or not release_id.strip():
        v.add("given.inputs.product_release_id must be non-empty")

    released_at = inputs["product_release_released_at"]
    product_datetime = None
    if not is_datetime(released_at):
        v.add("given.inputs.product_release_released_at must be an ISO date-time")
    else:
        product_datetime = datetime.fromisoformat(released_at.replace("Z", "+00:00"))

    navigation_released_at = inputs["navigation_release_released_at"]
    if product_datetime is not None and is_datetime(navigation_released_at):
        navigation_datetime = datetime.fromisoformat(
            navigation_released_at.replace("Z", "+00:00")
        )
        try:
            if navigation_datetime > product_datetime:
                v.add(
                    "given.inputs.navigation_release_released_at cannot follow "
                    "the product release"
                )
        except TypeError:
            v.add(
                "product and navigation release date-times must use comparable "
                "timezone forms"
            )

    expected_missing = inputs[
        "product_release_expected_missing_editor_entity_ids"
    ]
    if (
        not isinstance(expected_missing, list)
        or not all(
            isinstance(entity_id, str) and entity_id.strip()
            for entity_id in expected_missing
        )
        or len(expected_missing) != len(set(expected_missing))
    ):
        v.add(
            "given.inputs.product_release_expected_missing_editor_entity_ids "
            "must be unique non-empty strings"
        )
        expected_missing = []

    snapshot = given.get("network_snapshot")
    snapshot_id = snapshot.get("id") if isinstance(snapshot, dict) else None
    route_plan = given.get("route_plan")
    route_plan_id = (
        route_plan.get("plan_id") if isinstance(route_plan, dict) else None
    )
    actual_distance = (
        route_plan.get("actual_distance_km")
        if isinstance(route_plan, dict)
        else None
    )
    if (
        not isinstance(actual_distance, (int, float))
        or isinstance(actual_distance, bool)
        or not math.isfinite(actual_distance)
        or actual_distance <= 0
    ):
        v.add(
            "product release RoutePlan.actual_distance_km must be finite "
            "and positive"
        )

    catalog = inputs["expert_route_editor_catalog"]
    required_editor_entity_ids: set[str] = set()
    if not isinstance(catalog, dict):
        v.add("given.inputs.expert_route_editor_catalog must be an object")
    else:
        if catalog.get("network_snapshot_id") != snapshot_id:
            v.add(
                "product release editor catalog network_snapshot_id must match "
                "given.network_snapshot.id"
            )
        entrances = catalog.get("entrances")
        decisions = catalog.get("decision_points")
        if not isinstance(entrances, list) or not isinstance(decisions, list):
            v.add(
                "product release editor catalog must contain entrance and "
                "decision-point arrays"
            )
        else:
            for entrance in entrances:
                if not isinstance(entrance, dict):
                    continue
                initial_edge_id = entrance.get("initial_edge_id")
                if isinstance(initial_edge_id, str) and initial_edge_id.strip():
                    required_editor_entity_ids.add(initial_edge_id)
            for decision in decisions:
                if not isinstance(decision, dict):
                    continue
                incoming_approach_id = decision.get("incoming_approach_id")
                if (
                    isinstance(incoming_approach_id, str)
                    and incoming_approach_id.strip()
                ):
                    required_editor_entity_ids.add(incoming_approach_id)
                choices = decision.get("choices")
                if not isinstance(choices, list):
                    continue
                for choice in choices:
                    if not isinstance(choice, dict):
                        continue
                    for field in ("movement_id", "outgoing_edge_id"):
                        entity_id = choice.get(field)
                        if isinstance(entity_id, str) and entity_id.strip():
                            required_editor_entity_ids.add(entity_id)

    topology = inputs["route_atlas_topology"]
    atlas_entity_ids: set[str] = set()
    if not isinstance(topology, dict):
        v.add("given.inputs.route_atlas_topology must be an object")
    else:
        if topology.get("network_snapshot_id") != snapshot_id:
            v.add(
                "product release Route Atlas topology network_snapshot_id must "
                "match given.network_snapshot.id"
            )
        edges = topology.get("edges")
        if not isinstance(edges, list):
            v.add("given.inputs.route_atlas_topology.edges must be an array")
        else:
            route_entity_values: list[str] = []
            for edge in edges:
                entity_id = (
                    edge.get("route_entity_id") if isinstance(edge, dict) else None
                )
                if not isinstance(entity_id, str) or not entity_id.strip():
                    v.add(
                        "every product release Route Atlas topology edge must "
                        "name a non-empty route_entity_id"
                    )
                    continue
                route_entity_values.append(entity_id)
            if len(route_entity_values) != len(set(route_entity_values)):
                v.add(
                    "product release Route Atlas route_entity_id values must be "
                    "unique"
                )
            atlas_entity_ids = set(route_entity_values)

    atlas = inputs["route_atlas"]
    if not isinstance(atlas, dict):
        v.add("given.inputs.route_atlas must be an object")
    else:
        if atlas.get("network_snapshot_id") != snapshot_id:
            v.add(
                "product release Route Atlas network_snapshot_id must match "
                "given.network_snapshot.id"
            )
        if atlas.get("route_plan_id") != route_plan_id:
            v.add(
                "product release Route Atlas route_plan_id must match "
                "given.route_plan.plan_id"
            )
        topology_id = (
            topology.get("topology_slice_id")
            if isinstance(topology, dict)
            else None
        )
        if atlas.get("topology_slice_id") != topology_id:
            v.add(
                "product release Route Atlas topology_slice_id must match its "
                "topology input"
            )

    route_occurrence_entity_ids = {
        occurrence.get("entity_id")
        for occurrence in (
            route_plan.get("occurrences", [])
            if isinstance(route_plan, dict)
            else []
        )
        if isinstance(occurrence, dict)
        and isinstance(occurrence.get("entity_id"), str)
        and occurrence.get("entity_id").strip()
    }
    missing_route_entities = sorted(route_occurrence_entity_ids - atlas_entity_ids)
    if missing_route_entities:
        v.add(
            "product release Route Atlas is missing RoutePlan entities: "
            + ", ".join(missing_route_entities)
        )

    derived_missing = sorted(required_editor_entity_ids - atlas_entity_ids)
    if sorted(expected_missing) != derived_missing:
        v.add(
            "given.inputs.product_release_expected_missing_editor_entity_ids "
            "must exactly match derived missing editor entities: "
            + json.dumps(derived_missing)
        )

    if product_datetime is not None:
        product_date = product_datetime.date()
        dated_evidence: list[tuple[str, Any]] = []
        for index, source in enumerate(inputs.get("route_atlas_sources", [])):
            if isinstance(source, dict):
                dated_evidence.append(
                    (
                        f"given.inputs.route_atlas_sources[{index}].checked_at",
                        source.get("checked_at"),
                    )
                )
        if isinstance(topology, dict):
            topology_evidence = topology.get("evidence")
            if isinstance(topology_evidence, dict):
                dated_evidence.append(
                    (
                        "given.inputs.route_atlas_topology.evidence.checked_at",
                        topology_evidence.get("checked_at"),
                    )
                )
        if isinstance(atlas, dict):
            atlas_evidence = atlas.get("evidence")
            if isinstance(atlas_evidence, dict):
                dated_evidence.append(
                    (
                        "given.inputs.route_atlas.evidence.checked_at",
                        atlas_evidence.get("checked_at"),
                    )
                )
        for context, checked_at in dated_evidence:
            if is_date(checked_at) and date.fromisoformat(checked_at) > product_date:
                v.add(f"{context} cannot follow the product release")


def validate_product_runtime_use_cases(
    v: Validation, given: dict[str, Any], events: Any
) -> None:
    inputs = given.get("inputs")
    if not isinstance(inputs, dict) or "product_runtime_use_cases" not in inputs:
        return

    cases = inputs["product_runtime_use_cases"]
    if not isinstance(cases, list) or not cases:
        v.add("given.inputs.product_runtime_use_cases must be a non-empty array")
        return

    case_ids: set[str] = set()
    required_case_keys = {
        "case_id",
        "evidence_scope",
        "live_input_policy",
        "navigation_sources",
        "route_atlas_sources",
    }
    for case_index, case in enumerate(cases):
        context = f"given.inputs.product_runtime_use_cases[{case_index}]"
        if not v.require_keys(case, required_case_keys, context):
            continue
        extra_keys = sorted(set(case) - required_case_keys)
        if extra_keys:
            v.add(f"{context} has unsupported keys: {', '.join(extra_keys)}")

        case_id = case["case_id"]
        if not isinstance(case_id, str) or not SLUG_RE.fullmatch(case_id):
            v.add(f"{context}.case_id must be a lowercase stable identifier")
        elif case_id in case_ids:
            v.add(f"duplicate product runtime-use case id: {case_id}")
        else:
            case_ids.add(case_id)

        if case["evidence_scope"] not in PRODUCT_RUNTIME_EVIDENCE_SCOPES:
            v.add(f"{context}.evidence_scope is unknown")
        if case["live_input_policy"] not in PRODUCT_LIVE_INPUT_POLICIES:
            v.add(f"{context}.live_input_policy is unknown")

        source_ids: set[str] = set()
        for source_key in ("navigation_sources", "route_atlas_sources"):
            sources = case[source_key]
            if not isinstance(sources, list) or not sources:
                v.add(f"{context}.{source_key} must be a non-empty array")
                continue
            for source_index, source in enumerate(sources):
                source_context = (
                    f"{context}.{source_key}[{source_index}]"
                )
                required_source_keys = {"source_id", "licence_identifier"}
                if not v.require_keys(
                    source, required_source_keys, source_context
                ):
                    continue
                extra_source_keys = sorted(
                    set(source) - required_source_keys
                )
                if extra_source_keys:
                    v.add(
                        f"{source_context} has unsupported keys: "
                        + ", ".join(extra_source_keys)
                    )
                source_id = source["source_id"]
                if (
                    not isinstance(source_id, str)
                    or not source_id.strip()
                ):
                    v.add(f"{source_context}.source_id must be non-empty")
                elif source_id in source_ids:
                    v.add(
                        f"{context} has duplicate source_id: {source_id}"
                    )
                else:
                    source_ids.add(source_id)
                licence = source["licence_identifier"]
                if not isinstance(licence, str) or not licence.strip():
                    v.add(
                        f"{source_context}.licence_identifier must be non-empty"
                    )

    if isinstance(events, list):
        for index, event in enumerate(events):
            if (
                isinstance(event, dict)
                and event.get("type") == "PRODUCT_RUNTIME_USE_EVALUATED"
            ):
                payload = event.get("payload")
                case_id = (
                    payload.get("case_id")
                    if isinstance(payload, dict)
                    else None
                )
                if case_id not in case_ids:
                    v.add(
                        f"when[{index}] product runtime-use event references "
                        f"unknown case_id: {case_id!r}"
                    )


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
        validate_pre_drive_evidence(v, given)
        validate_pre_drive_evidence_bundle(v, given, scenario["when"])
        validate_saved_route_library(v, given)
        validate_saved_route_lifecycle_events(v, given, scenario["when"])
        validate_guidance_anchors(v, given)
        validate_entrance_recommendation(v, given)
        validate_matcher_guidance_inputs(v, given)
        validate_expert_route_editor(v, given)
        validate_route_editor_presentation(v, given)
        validate_released_guidance(v, given)
        validate_navigation_runtime_policy(v, given)
        validate_entry_transition_admission(v, given, scenario["when"])
        validate_surface_egress_matcher_admission(
            v, given, scenario["when"]
        )
        validate_navigation_release_artifact(v, given)
        validate_navigation_release_authoring_events(
            v,
            given,
            scenario["when"],
        )
        validate_route_atlas_release_authoring_events(
            v,
            given,
            scenario["when"],
        )
        validate_product_release_artifact(v, given)
        validate_product_runtime_use_cases(v, given, scenario["when"])
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
