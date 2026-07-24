#!/usr/bin/env python3
"""Validate a private exact-record K7 road-register identity review."""

from __future__ import annotations

import argparse
from datetime import date, datetime
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


EXPECTED_SCHEMA_VERSION = "1.0"
EXPECTED_REVIEW_ID = "k7-yokohama-kohoku-exact-road-register-review"
EXPECTED_TARGET = {
    "network_snapshot_id": (
        "shutoko.candidate.osm-geofabrik-kanto-260721.k7-northwest"
    ),
    "exit_facility_id": "shutoko.exit.yokohama-kohoku.k7-northwest.up",
    "incoming_osm_way_id": 734299106,
    "via_osm_node_id": 7473451738,
    "surface_osm_way_id": 776884422,
    "source_direction": "FORWARD",
}
EXPECTED_PRIVACY_CONTRACT = {
    "manifest_classification": "PRIVATE_COORDINATE_FREE_OFFICIAL_RECORD_REVIEW",
    "raw_record_storage": "IGNORED_PRIVATE_STORAGE_ONLY",
    "raw_record_embedded": False,
    "coordinates_embedded": False,
    "copied_map_geometry_embedded": False,
}
EXPECTED_TOP_LEVEL_KEYS = {
    "schema_version",
    "review_id",
    "target",
    "privacy_contract",
    "record_collection",
    "exact_mapping_review",
    "conclusions",
}
EXPECTED_COLLECTION_KEYS = {
    "status",
    "obtained_at",
    "obtained_via",
    "official_authority",
    "register_map_id",
    "register_map_name_ja",
    "record_current_through",
    "official_record_reference",
    "raw_record_sha256",
}
EXPECTED_MAPPING_KEYS = {
    "status",
    "recognized_route_identifier",
    "recognized_route_name_ja",
    "compared_osm_way_ids",
    "selected_osm_way_id",
    "mapping_basis",
    "record_evidence_sha256",
}
EXPECTED_CONCLUSION_KEYS = {
    "reviewed_by",
    "reviewer_role",
    "reviewed_at",
    "valid_through",
}
EXPECTED_AUTHORITY = "City of Yokohama Road Survey Division"
EXPECTED_REGISTER_MAP_ID = 66
EXPECTED_REGISTER_MAP_NAME_JA = "認定路線図"
EXPECTED_COMPARED_WAY_IDS = [734299108, 734299111, 776884422]
EXPECTED_SELECTED_WAY_ID = 776884422
OBTAINED_VIA = {"ROAD_SURVEY_DIVISION_COUNTER"}
REVIEWER_ROLES = {"INDEPENDENT_ROAD_IDENTITY_REVIEWER"}
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
MAX_REVIEW_VALIDITY_DAYS = 31
MAX_RECORD_AGE_DAYS = 31
REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
TRACKED_TEMPLATE_PATH = (
    REPOSITORY_ROOT / "docs/testing/fixtures/"
    "k7-yokohama-kohoku-road-register-review.template.json"
).resolve()


class RoadRegisterReviewError(RuntimeError):
    """A malformed private road-register review package."""


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
        raise RoadRegisterReviewError(f"cannot read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise RoadRegisterReviewError("road-register review must be a JSON object")
    return value


def require_exact_keys(
    value: dict[str, Any],
    expected: set[str],
    field: str,
) -> None:
    actual = set(value)
    if actual == expected:
        return
    missing = sorted(expected - actual)
    unexpected = sorted(actual - expected)
    details: list[str] = []
    if missing:
        details.append("missing " + ", ".join(missing))
    if unexpected:
        details.append("unexpected " + ", ".join(unexpected))
    raise RoadRegisterReviewError(f"{field} keys have drifted: " + "; ".join(details))


def parse_timestamp(value: Any, field: str) -> datetime:
    if not isinstance(value, str) or not value:
        raise RoadRegisterReviewError(f"{field} must be an RFC 3339 timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise RoadRegisterReviewError(
            f"{field} must be an RFC 3339 timestamp"
        ) from error
    if parsed.tzinfo is None:
        raise RoadRegisterReviewError(f"{field} must include a timezone")
    return parsed


def parse_date(value: Any, field: str) -> date:
    if not isinstance(value, str) or not value:
        raise RoadRegisterReviewError(f"{field} must be an ISO date")
    try:
        return date.fromisoformat(value)
    except ValueError as error:
        raise RoadRegisterReviewError(f"{field} must be an ISO date") from error


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


def nonempty_text(value: Any, maximum_length: int = 500) -> bool:
    return (
        isinstance(value, str)
        and value == value.strip()
        and 0 < len(value) <= maximum_length
        and "data:" not in value.lower()
    )


def validate_review_input_path(path: Path) -> None:
    resolved = path.resolve()
    if resolved == TRACKED_TEMPLATE_PATH:
        return
    try:
        relative = resolved.relative_to(REPOSITORY_ROOT)
    except ValueError:
        return
    if not relative.parts or relative.parts[0] != "research":
        raise RoadRegisterReviewError(
            "completed road-register reviews inside the repository must stay "
            "under ignored research/"
        )


def evaluate(
    review: dict[str, Any],
    as_of: date,
) -> dict[str, Any]:
    require_exact_keys(review, EXPECTED_TOP_LEVEL_KEYS, "road-register review")
    if (
        review.get("schema_version") != EXPECTED_SCHEMA_VERSION
        or review.get("review_id") != EXPECTED_REVIEW_ID
        or review.get("target") != EXPECTED_TARGET
        or review.get("privacy_contract") != EXPECTED_PRIVACY_CONTRACT
    ):
        raise RoadRegisterReviewError("road-register review identity has drifted")

    collection = review.get("record_collection")
    mapping = review.get("exact_mapping_review")
    conclusions = review.get("conclusions")
    if (
        not isinstance(collection, dict)
        or not isinstance(mapping, dict)
        or not isinstance(conclusions, dict)
    ):
        raise RoadRegisterReviewError("road-register review sections are incomplete")
    require_exact_keys(collection, EXPECTED_COLLECTION_KEYS, "record_collection")
    require_exact_keys(mapping, EXPECTED_MAPPING_KEYS, "exact_mapping_review")
    require_exact_keys(conclusions, EXPECTED_CONCLUSION_KEYS, "conclusions")

    if (
        collection.get("official_authority") != EXPECTED_AUTHORITY
        or collection.get("register_map_id") != EXPECTED_REGISTER_MAP_ID
        or collection.get("register_map_name_ja") != EXPECTED_REGISTER_MAP_NAME_JA
        or mapping.get("compared_osm_way_ids") != EXPECTED_COMPARED_WAY_IDS
    ):
        raise RoadRegisterReviewError(
            "official register or compared-way identity has drifted"
        )

    blockers: list[str] = []
    if collection.get("status") != "OBTAINED":
        blockers.append("OFFICIAL_RECORD_NOT_OBTAINED")
    if collection.get("obtained_via") not in OBTAINED_VIA:
        blockers.append("OFFICIAL_RECORD_METHOD_UNCONFIRMED")

    obtained_at: datetime | None
    try:
        obtained_at = parse_timestamp(
            collection.get("obtained_at"),
            "record_collection.obtained_at",
        )
    except RoadRegisterReviewError:
        obtained_at = None
        blockers.append("OFFICIAL_RECORD_TIME_UNCONFIRMED")
    try:
        record_current_through = parse_date(
            collection.get("record_current_through"),
            "record_collection.record_current_through",
        )
    except RoadRegisterReviewError:
        record_current_through = None
        blockers.append("OFFICIAL_RECORD_CURRENTNESS_UNCONFIRMED")

    if not nonempty_text(collection.get("official_record_reference"), 200):
        blockers.append("OFFICIAL_RECORD_REFERENCE_MISSING")
    raw_hashes = collection.get("raw_record_sha256")
    if valid_sha256_values(raw_hashes):
        raw_hash_set = set(raw_hashes)
    else:
        raw_hash_set: set[str] = set()
        blockers.append("RAW_OFFICIAL_RECORD_HASHES_MISSING")

    if mapping.get("status") != "CONFIRMED":
        blockers.append("EXACT_OSM_WAY_MAPPING_UNCONFIRMED")
    if mapping.get("selected_osm_way_id") != EXPECTED_SELECTED_WAY_ID:
        blockers.append("EXACT_OSM_WAY_SELECTION_UNCONFIRMED")
    if not nonempty_text(mapping.get("recognized_route_identifier"), 200):
        blockers.append("RECOGNIZED_ROUTE_IDENTIFIER_UNCONFIRMED")
    if not nonempty_text(mapping.get("recognized_route_name_ja"), 200):
        blockers.append("RECOGNIZED_ROUTE_NAME_UNCONFIRMED")
    if not nonempty_text(mapping.get("mapping_basis")):
        blockers.append("EXACT_OSM_WAY_MAPPING_BASIS_MISSING")
    evidence_hashes = mapping.get("record_evidence_sha256")
    if not valid_sha256_values(evidence_hashes):
        blockers.append("EXACT_MAPPING_EVIDENCE_MISSING")
        bound_hash_set: set[str] = set()
    elif not set(evidence_hashes).issubset(raw_hash_set):
        blockers.append("EXACT_MAPPING_EVIDENCE_UNBOUND")
        bound_hash_set = set()
    else:
        bound_hash_set = set(evidence_hashes)
    if raw_hash_set - bound_hash_set:
        blockers.append("RAW_OFFICIAL_RECORD_HASHES_UNREFERENCED")

    if not nonempty_text(conclusions.get("reviewed_by"), 200):
        blockers.append("ROAD_IDENTITY_REVIEWER_UNCONFIRMED")
    if conclusions.get("reviewer_role") not in REVIEWER_ROLES:
        blockers.append("INDEPENDENT_ROAD_IDENTITY_REVIEW_UNCONFIRMED")
    try:
        reviewed_at = parse_timestamp(
            conclusions.get("reviewed_at"),
            "conclusions.reviewed_at",
        )
    except RoadRegisterReviewError:
        reviewed_at = None
        blockers.append("ROAD_IDENTITY_REVIEW_TIME_UNCONFIRMED")
    try:
        valid_through = parse_date(
            conclusions.get("valid_through"),
            "conclusions.valid_through",
        )
    except RoadRegisterReviewError:
        valid_through = None
        blockers.append("ROAD_IDENTITY_REVIEW_VALIDITY_UNCONFIRMED")

    if obtained_at is not None and obtained_at.date() > as_of:
        blockers.append("OFFICIAL_RECORD_TIME_IN_FUTURE")
    if record_current_through is not None and record_current_through > as_of:
        blockers.append("OFFICIAL_RECORD_CURRENTNESS_IN_FUTURE")
    if (
        record_current_through is not None
        and obtained_at is not None
        and record_current_through > obtained_at.date()
    ):
        blockers.append("OFFICIAL_RECORD_CURRENTNESS_POSTDATES_ACQUISITION")
    if reviewed_at is not None and reviewed_at.date() > as_of:
        blockers.append("ROAD_IDENTITY_REVIEW_TIME_IN_FUTURE")
    if (
        obtained_at is not None
        and reviewed_at is not None
        and reviewed_at < obtained_at
    ):
        blockers.append("ROAD_IDENTITY_REVIEW_PRECEDES_RECORD")
    if (
        record_current_through is not None
        and reviewed_at is not None
        and record_current_through > reviewed_at.date()
    ):
        blockers.append("OFFICIAL_RECORD_CURRENTNESS_POSTDATES_REVIEW")
    if (
        record_current_through is not None
        and reviewed_at is not None
        and (reviewed_at.date() - record_current_through).days > MAX_RECORD_AGE_DAYS
    ):
        blockers.append("OFFICIAL_RECORD_TOO_OLD")
    if valid_through is not None and valid_through < as_of:
        blockers.append("ROAD_IDENTITY_REVIEW_STALE")
    if (
        valid_through is not None
        and reviewed_at is not None
        and valid_through < reviewed_at.date()
    ):
        blockers.append("ROAD_IDENTITY_REVIEW_VALIDITY_PRECEDES_REVIEW")
    if (
        valid_through is not None
        and reviewed_at is not None
        and (valid_through - reviewed_at.date()).days > MAX_REVIEW_VALIDITY_DAYS
    ):
        blockers.append("ROAD_IDENTITY_REVIEW_VALIDITY_WINDOW_TOO_LONG")
    if (
        valid_through is not None
        and record_current_through is not None
        and (valid_through - record_current_through).days > MAX_REVIEW_VALIDITY_DAYS
    ):
        blockers.append("ROAD_IDENTITY_RECORD_VALIDITY_WINDOW_TOO_LONG")

    blockers = sorted(set(blockers))
    return {
        "schema_version": EXPECTED_SCHEMA_VERSION,
        "review_id": EXPECTED_REVIEW_ID,
        "target": EXPECTED_TARGET,
        "as_of": as_of.isoformat(),
        "road_identity_review_complete": not blockers,
        "route_release_authority": False,
        "manifest_classification": EXPECTED_PRIVACY_CONTRACT["manifest_classification"],
        "raw_record_file_count": len(raw_hash_set),
        "record_current_through": (
            record_current_through.isoformat()
            if record_current_through is not None
            else None
        ),
        "recognized_route_identifier": mapping.get("recognized_route_identifier"),
        "recognized_route_name_ja": mapping.get("recognized_route_name_ja"),
        "selected_osm_way_id": mapping.get("selected_osm_way_id"),
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
    except (OSError, RoadRegisterReviewError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    if report["road_identity_review_complete"]:
        digest = hashlib.sha256(
            json.dumps(report, sort_keys=True).encode("utf-8")
        ).hexdigest()
        print(
            "PASS: exact current road identity is independently reviewed; "
            f"coordinate-free report digest {digest}"
        )
        return 0
    print(
        "BLOCKED: exact current road identity review is incomplete: "
        + ", ".join(report["blockers"])
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
