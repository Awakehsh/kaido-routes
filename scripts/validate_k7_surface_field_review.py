#!/usr/bin/env python3
"""Validate a coordinate-free Yokohama Kohoku surface field review."""

from __future__ import annotations

import argparse
from datetime import date, datetime
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


EXPECTED_SCHEMA_VERSION = "1.1"
EXPECTED_PLAN_ID = "k7-yokohama-kohoku-surface-field-verification"
EXPECTED_TOP_LEVEL_KEYS = {
    "schema_version",
    "plan_id",
    "target",
    "privacy_contract",
    "collection",
    "observations",
    "conclusions",
}
EXPECTED_TARGET = {
    "network_snapshot_id": (
        "shutoko.candidate.osm-geofabrik-kanto-260721.k7-northwest"
    ),
    "exit_facility_id": ("shutoko.exit.yokohama-kohoku.k7-northwest.up"),
    "incoming_osm_way_id": 734299106,
    "via_osm_node_id": 7473451738,
    "surface_osm_way_id": 776884422,
    "source_direction": "FORWARD",
}
EXPECTED_PRIVACY_CONTRACT = {
    "manifest_classification": "PRIVATE_COORDINATE_FREE_REVIEW",
    "raw_evidence_storage": "IGNORED_PRIVATE_STORAGE_ONLY",
    "raw_media_embedded": False,
    "coordinates_embedded": False,
    "device_metadata_embedded": False,
}
EXPECTED_COLLECTION_KEYS = {
    "captured_at",
    "observer_role",
    "driver_interaction",
    "expressway_stop_required",
    "unsafe_positioning_required",
    "lawful_travel_only",
    "raw_evidence_sha256",
}
EXPECTED_CHECKPOINT_VIEWS = {
    "EXIT_RAMP_SIGNAL_APPROACH": (
        "The lawful passenger view approaching the surface signal, including "
        "lane arrows and every direction or turn restriction controlling the "
        "exit movement."
    ),
    "UNRESOLVED_CORRIDOR_EAST_MOUTH": (
        "Both sides of the passage mouth at the exit intersection, including "
        "no-entry, one-way, motor-access, closure, and construction signs."
    ),
    "UNRESOLVED_CORRIDOR_WEST_MOUTH_EASTBOUND": (
        "The west mouth approached toward the exit intersection, including "
        "every sign and lane marking controlling eastbound entry."
    ),
    "UNRESOLVED_CORRIDOR_WEST_MOUTH_WESTBOUND": (
        "The west mouth viewed in the exit-to-west direction, including every "
        "sign and lane marking controlling westbound passage."
    ),
}
EXPECTED_CHECKPOINT_IDS = set(EXPECTED_CHECKPOINT_VIEWS)
EXPECTED_OBSERVATION_KEYS = {
    "checkpoint_id",
    "status",
    "required_view",
    "sign_findings",
    "evidence_sha256",
}
EXPECTED_CONCLUSION_KEYS = {
    "current_physical_status",
    "current_legal_direction",
    "permitted_exit_movement",
    "reviewed_by",
    "reviewer_role",
    "reviewed_at",
    "valid_through",
}
OBSERVER_ROLES = {"PASSENGER"}
REVIEWER_ROLES = {"INDEPENDENT_REVIEWER"}
PHYSICAL_STATES = {"ACTIVE", "CLOSED", "REMOVED"}
LEGAL_DIRECTIONS = {
    "FORWARD_ONLY",
    "REVERSE_ONLY",
    "BIDIRECTIONAL",
    "NO_MOTOR_ACCESS",
}
EXIT_MOVEMENTS = {"ALLOWED", "PROHIBITED"}
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
MAX_REVIEW_VALIDITY_DAYS = 31
REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
TRACKED_TEMPLATE_PATH = (
    REPOSITORY_ROOT / "docs/testing/fixtures/"
    "k7-yokohama-kohoku-surface-field-review.template.json"
).resolve()
FORBIDDEN_PRIVATE_KEYS = {
    "coordinate",
    "coordinates",
    "device_id",
    "file_path",
    "gps",
    "latitude",
    "location",
    "longitude",
    "raw_path",
}


class FieldReviewError(RuntimeError):
    """A malformed field-review package."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("review", type=Path)
    parser.add_argument(
        "--as-of",
        required=True,
        type=date.fromisoformat,
        help="deterministic review date in YYYY-MM-DD form",
    )
    parser.add_argument("--report", type=Path)
    return parser.parse_args()


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise FieldReviewError(f"cannot read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise FieldReviewError("field review must be a JSON object")
    return value


def parse_timestamp(value: Any, field: str) -> datetime:
    if not isinstance(value, str) or not value:
        raise FieldReviewError(f"{field} must be an RFC 3339 timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise FieldReviewError(f"{field} must be an RFC 3339 timestamp") from error
    if parsed.tzinfo is None:
        raise FieldReviewError(f"{field} must include a timezone")
    return parsed


def valid_sha256_values(values: Any) -> bool:
    return (
        isinstance(values, list)
        and bool(values)
        and len(values) == len(set(values))
        and all(
            isinstance(value, str) and SHA256_PATTERN.fullmatch(value)
            for value in values
        )
    )


def contains_private_key(value: Any) -> bool:
    if isinstance(value, dict):
        return any(
            str(key).lower() in FORBIDDEN_PRIVATE_KEYS or contains_private_key(child)
            for key, child in value.items()
        )
    if isinstance(value, list):
        return any(contains_private_key(child) for child in value)
    return False


def require_exact_keys(
    value: dict[str, Any],
    expected: set[str],
    field: str,
) -> None:
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        unexpected = sorted(actual - expected)
        details: list[str] = []
        if missing:
            details.append("missing " + ", ".join(missing))
        if unexpected:
            details.append("unexpected " + ", ".join(unexpected))
        raise FieldReviewError(f"{field} keys have drifted: " + "; ".join(details))


def validate_review_input_path(path: Path) -> None:
    resolved = path.resolve()
    if resolved == TRACKED_TEMPLATE_PATH:
        return
    try:
        relative = resolved.relative_to(REPOSITORY_ROOT)
    except ValueError:
        return
    if not relative.parts or relative.parts[0] != "research":
        raise FieldReviewError(
            "completed field reviews inside the repository must stay under "
            "ignored research/"
        )


def evaluate(
    review: dict[str, Any],
    as_of: date,
) -> dict[str, Any]:
    require_exact_keys(review, EXPECTED_TOP_LEVEL_KEYS, "field review")
    if (
        review.get("schema_version") != EXPECTED_SCHEMA_VERSION
        or review.get("plan_id") != EXPECTED_PLAN_ID
        or review.get("target") != EXPECTED_TARGET
        or review.get("privacy_contract") != EXPECTED_PRIVACY_CONTRACT
    ):
        raise FieldReviewError("field review identity has drifted")
    if contains_private_key(review):
        raise FieldReviewError(
            "field review contains a forbidden private-location field"
        )

    blockers: list[str] = []
    collection = review.get("collection")
    observations = review.get("observations")
    conclusions = review.get("conclusions")
    if (
        not isinstance(collection, dict)
        or not isinstance(observations, list)
        or not isinstance(conclusions, dict)
    ):
        raise FieldReviewError("field review sections are incomplete")
    require_exact_keys(collection, EXPECTED_COLLECTION_KEYS, "collection")
    require_exact_keys(conclusions, EXPECTED_CONCLUSION_KEYS, "conclusions")

    observer_role = collection.get("observer_role")
    if observer_role not in OBSERVER_ROLES:
        blockers.append("SAFE_OBSERVER_ROLE_UNCONFIRMED")
    if collection.get("driver_interaction") is not False:
        blockers.append("DRIVER_INTERACTION_NOT_FORBIDDEN")
    if collection.get("expressway_stop_required") is not False:
        blockers.append("EXPRESSWAY_STOP_NOT_FORBIDDEN")
    if collection.get("unsafe_positioning_required") is not False:
        blockers.append("UNSAFE_POSITIONING_NOT_FORBIDDEN")
    if collection.get("lawful_travel_only") is not True:
        blockers.append("LAWFUL_TRAVEL_UNCONFIRMED")

    captured_at: datetime | None = None
    try:
        captured_at = parse_timestamp(
            collection.get("captured_at"),
            "collection.captured_at",
        )
    except FieldReviewError:
        blockers.append("CAPTURE_TIME_UNCONFIRMED")

    raw_hashes = collection.get("raw_evidence_sha256")
    if not valid_sha256_values(raw_hashes):
        blockers.append("RAW_EVIDENCE_HASHES_MISSING")
        raw_hash_set: set[str] = set()
    else:
        raw_hash_set = set(raw_hashes)

    observation_ids = {
        item.get("checkpoint_id") for item in observations if isinstance(item, dict)
    }
    if observation_ids != EXPECTED_CHECKPOINT_IDS or len(observations) != len(
        EXPECTED_CHECKPOINT_IDS
    ):
        raise FieldReviewError("field checkpoint coverage has drifted")
    bound_hash_set: set[str] = set()
    for observation in observations:
        if not isinstance(observation, dict):
            raise FieldReviewError("field observation must be an object")
        require_exact_keys(
            observation,
            EXPECTED_OBSERVATION_KEYS,
            f"checkpoint {observation.get('checkpoint_id')}",
        )
        checkpoint_id = observation["checkpoint_id"]
        if observation.get("required_view") != EXPECTED_CHECKPOINT_VIEWS[checkpoint_id]:
            raise FieldReviewError(
                f"checkpoint {checkpoint_id} required view has drifted"
            )
        if observation.get("status") != "CAPTURED":
            blockers.append(f"CHECKPOINT_PENDING:{checkpoint_id}")
        evidence_hashes = observation.get("evidence_sha256")
        if not valid_sha256_values(evidence_hashes):
            blockers.append(f"CHECKPOINT_EVIDENCE_MISSING:{checkpoint_id}")
        elif not set(evidence_hashes).issubset(raw_hash_set):
            blockers.append(f"CHECKPOINT_EVIDENCE_UNBOUND:{checkpoint_id}")
        else:
            bound_hash_set.update(evidence_hashes)
        sign_findings = observation.get("sign_findings")
        if not isinstance(sign_findings, list) or not all(
            isinstance(finding, str) and finding.strip() for finding in sign_findings
        ):
            raise FieldReviewError(
                f"checkpoint {checkpoint_id} has invalid sign findings"
            )
        if observation.get("status") == "CAPTURED" and not sign_findings:
            blockers.append(f"CHECKPOINT_FINDINGS_MISSING:{checkpoint_id}")
    if raw_hash_set - bound_hash_set:
        blockers.append("RAW_EVIDENCE_HASHES_UNREFERENCED")

    physical_status = conclusions.get("current_physical_status")
    legal_direction = conclusions.get("current_legal_direction")
    exit_movement = conclusions.get("permitted_exit_movement")
    if physical_status not in PHYSICAL_STATES:
        blockers.append("CURRENT_PHYSICAL_STATUS_UNCONFIRMED")
    if legal_direction not in LEGAL_DIRECTIONS:
        blockers.append("CURRENT_LEGAL_DIRECTION_UNCONFIRMED")
    if exit_movement not in EXIT_MOVEMENTS:
        blockers.append("PERMITTED_EXIT_MOVEMENT_UNCONFIRMED")
    if (
        exit_movement == "ALLOWED"
        and (
            physical_status != "ACTIVE"
            or legal_direction not in {"FORWARD_ONLY", "BIDIRECTIONAL"}
        )
    ) or (legal_direction == "NO_MOTOR_ACCESS" and exit_movement != "PROHIBITED"):
        blockers.append("FIELD_CONCLUSIONS_CONFLICT")
    if (
        not isinstance(conclusions.get("reviewed_by"), str)
        or not conclusions["reviewed_by"].strip()
    ):
        blockers.append("REVIEWER_UNCONFIRMED")
    if conclusions.get("reviewer_role") not in REVIEWER_ROLES:
        blockers.append("INDEPENDENT_REVIEWER_UNCONFIRMED")

    reviewed_at: datetime | None = None
    try:
        reviewed_at = parse_timestamp(
            conclusions.get("reviewed_at"),
            "conclusions.reviewed_at",
        )
    except FieldReviewError:
        blockers.append("REVIEW_TIME_UNCONFIRMED")
    try:
        valid_through = date.fromisoformat(conclusions.get("valid_through"))
    except (TypeError, ValueError):
        valid_through = None
        blockers.append("REVIEW_VALIDITY_UNCONFIRMED")

    if captured_at is not None and captured_at.date() > as_of:
        blockers.append("CAPTURE_TIME_IN_FUTURE")
    if reviewed_at is not None and reviewed_at.date() > as_of:
        blockers.append("REVIEW_TIME_IN_FUTURE")
    if (
        captured_at is not None
        and reviewed_at is not None
        and reviewed_at < captured_at
    ):
        blockers.append("REVIEW_PRECEDES_CAPTURE")
    if valid_through is not None and valid_through < as_of:
        blockers.append("FIELD_REVIEW_STALE")
    if (
        valid_through is not None
        and reviewed_at is not None
        and valid_through < reviewed_at.date()
    ):
        blockers.append("REVIEW_VALIDITY_PRECEDES_REVIEW")
    if (
        valid_through is not None
        and reviewed_at is not None
        and (valid_through - reviewed_at.date()).days > MAX_REVIEW_VALIDITY_DAYS
    ):
        blockers.append("REVIEW_VALIDITY_WINDOW_TOO_LONG")

    blockers = sorted(set(blockers))
    return {
        "schema_version": EXPECTED_SCHEMA_VERSION,
        "plan_id": EXPECTED_PLAN_ID,
        "target": EXPECTED_TARGET,
        "as_of": as_of.isoformat(),
        "field_review_complete": not blockers,
        "route_release_authority": False,
        "manifest_classification": EXPECTED_PRIVACY_CONTRACT["manifest_classification"],
        "raw_evidence_file_count": (len(raw_hash_set) if raw_hash_set else 0),
        "current_physical_status": physical_status,
        "current_legal_direction": legal_direction,
        "permitted_exit_movement": exit_movement,
        "blockers": blockers,
    }


def write_report(report: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    arguments = parse_arguments()
    try:
        validate_review_input_path(arguments.review)
        review = load_object(arguments.review)
        report = evaluate(review, arguments.as_of)
        if arguments.report is not None:
            write_report(report, arguments.report)
    except (OSError, FieldReviewError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    if report["field_review_complete"]:
        digest = hashlib.sha256(
            json.dumps(report, sort_keys=True).encode("utf-8")
        ).hexdigest()
        print(
            "PASS: current surface field review is complete; "
            f"coordinate-free report digest {digest}"
        )
        return 0
    print(
        "BLOCKED: current surface field review is incomplete: "
        + ", ".join(report["blockers"])
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
