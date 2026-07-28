#!/usr/bin/env python3
"""Build deterministic K7 pre-drive evidence inputs from one reviewed snapshot."""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REVIEW_PATH = (
    REPOSITORY_ROOT
    / "data/product/pre-drive-evidence/"
    "k7-aoba-to-kohoku-source-review-2026-07-27.json"
)
DEFAULT_DRAFT_PATH = (
    REPOSITORY_ROOT
    / "data/product/pre-drive-evidence/"
    "k7-aoba-to-kohoku-pre-drive-evidence-draft.json"
)
DEFAULT_AUTHORING_PATH = (
    REPOSITORY_ROOT
    / "data/product/pre-drive-evidence/"
    "k7-aoba-to-kohoku-pre-drive-evidence-authoring.json"
)

VEHICLE_CLASSES = (
    "LIGHT_MOTORCYCLE",
    "STANDARD",
    "MEDIUM",
    "LARGE",
    "EXTRA_LARGE",
)
PAYMENT_METHODS = ("ETC", "CASH")
PASSAGE_RESULT = "NO_KNOWN_CONFLICT_REALTIME_UNCONFIRMED"


class EvidenceInputError(ValueError):
    """Raised when a reviewed K7 evidence snapshot cannot be projected safely."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review", type=Path, default=DEFAULT_REVIEW_PATH)
    parser.add_argument("--draft", type=Path, default=DEFAULT_DRAFT_PATH)
    parser.add_argument("--config", type=Path, default=DEFAULT_AUTHORING_PATH)
    return parser.parse_args()


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EvidenceInputError(f"cannot read {path}: {error}") from error
    if not isinstance(value, dict):
        raise EvidenceInputError(f"{path} must contain one JSON object")
    return value


def encoded_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")


def parse_date_time(value: Any, field: str) -> datetime:
    if not isinstance(value, str) or not value or value.strip() != value:
        raise EvidenceInputError(f"{field} must be one normalized timestamp")
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError as error:
        raise EvidenceInputError(f"{field} must be ISO 8601") from error
    if parsed.tzinfo is None:
        raise EvidenceInputError(f"{field} must include an offset")
    return parsed


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def tariff_digest_input(
    review: dict[str, Any],
    observation: dict[str, Any],
) -> str:
    tariff = review["tariff_query"]
    return "|".join(
        (
            f"{tariff['origin_label']} to {tariff['destination_label']}",
            tariff["requested_departure_at"],
            observation["vehicle_class"],
            observation["official_label"],
            str(observation["cash_yen"]),
            str(observation["etc_yen"]),
            str(observation["etc2_yen"]),
            str(observation["normal_duration_minutes"]),
            str(observation["traffic_duration_minutes"]),
            str(observation["distance_km"]),
        )
    )


def passage_digest_input(review: dict[str, Any]) -> str:
    passage = review["passage_review"]
    return "|".join(
        (
            "mew-ti",
            passage["checked_at"],
            f"restriction_count={passage['restriction_count']}",
            "K7_NORTHWEST_MATCHES="
            f"{passage['k7_northwest_restriction_count']}",
            f"result={passage['result']}",
        )
    )


def validate_review(review: dict[str, Any]) -> None:
    if review.get("schema_version") != "1.0":
        raise EvidenceInputError("unsupported source-review schema")
    required_text = (
        "review_id",
        "reviewer_id",
        "release_id",
        "reviewed_at",
        "released_at",
        "valid_from",
        "expires_at",
    )
    for field in required_text:
        value = review.get(field)
        if not isinstance(value, str) or not value or value.strip() != value:
            raise EvidenceInputError(f"{field} must be normalized")

    reviewed_at = parse_date_time(review["reviewed_at"], "reviewed_at")
    released_at = parse_date_time(review["released_at"], "released_at")
    valid_from = parse_date_time(review["valid_from"], "valid_from")
    expires_at = parse_date_time(review["expires_at"], "expires_at")
    if not reviewed_at <= valid_from <= released_at < expires_at:
        raise EvidenceInputError("review validity chronology is invalid")

    tariff = review.get("tariff_query")
    passage = review.get("passage_review")
    if not isinstance(tariff, dict) or not isinstance(passage, dict):
        raise EvidenceInputError("tariff and passage reviews are required")
    tariff_checked = parse_date_time(tariff.get("checked_at"), "tariff.checked_at")
    requested_departure = parse_date_time(
        tariff.get("requested_departure_at"),
        "tariff.requested_departure_at",
    )
    passage_checked = parse_date_time(
        passage.get("checked_at"),
        "passage.checked_at",
    )
    if not tariff_checked <= reviewed_at or not passage_checked <= reviewed_at:
        raise EvidenceInputError("source checks cannot follow review")
    if requested_departure.date() != reviewed_at.date():
        raise EvidenceInputError("tariff query must target the review date")
    for field, expected in (
        ("origin_label", "Yokohama Aoba"),
        ("destination_label", "Yokohama Kohoku"),
    ):
        if tariff.get(field) != expected:
            raise EvidenceInputError(f"tariff {field} drifted")
    if not str(tariff.get("source_url", "")).startswith("https://"):
        raise EvidenceInputError("tariff source must use HTTPS")
    if not str(passage.get("source_url", "")).startswith("https://"):
        raise EvidenceInputError("passage source must use HTTPS")

    observations = tariff.get("observations")
    if not isinstance(observations, list):
        raise EvidenceInputError("tariff observations are required")
    by_class = {
        value.get("vehicle_class"): value
        for value in observations
        if isinstance(value, dict)
    }
    if tuple(by_class) != VEHICLE_CLASSES or len(observations) != len(by_class):
        raise EvidenceInputError("tariff observations must cover five classes once")
    for vehicle_class, observation in by_class.items():
        required_numbers = (
            "cash_yen",
            "etc_yen",
            "etc2_yen",
            "normal_duration_minutes",
            "traffic_duration_minutes",
        )
        if any(
            not isinstance(observation.get(field), int)
            or observation[field] < 0
            for field in required_numbers
        ):
            raise EvidenceInputError(
                f"{vehicle_class} tariff observation has invalid integers"
            )
        if observation["etc_yen"] != observation["etc2_yen"]:
            raise EvidenceInputError(
                f"{vehicle_class} ETC and ETC2 query results drifted"
            )
        if observation.get("distance_km") != 7.1:
            raise EvidenceInputError(f"{vehicle_class} route distance drifted")
        if sha256_text(tariff_digest_input(review, observation)) != observation.get(
            "content_sha256"
        ):
            raise EvidenceInputError(
                f"{vehicle_class} normalized tariff digest drifted"
            )

    if passage.get("result") != PASSAGE_RESULT:
        raise EvidenceInputError("passage review must remain realtime-unconfirmed")
    if passage.get("k7_northwest_restriction_count") != 0:
        raise EvidenceInputError("K7 Northwest has a reviewed conflict")
    if (
        not isinstance(passage.get("restriction_count"), int)
        or passage["restriction_count"] < 0
    ):
        raise EvidenceInputError("passage restriction count is invalid")
    if sha256_text(passage_digest_input(review)) != passage.get("content_sha256"):
        raise EvidenceInputError("normalized passage digest drifted")


def review_date(review: dict[str, Any]) -> str:
    return parse_date_time(review["reviewed_at"], "reviewed_at").date().isoformat()


def source_id(
    review: dict[str, Any],
    kind: str,
    suffix: str = "",
) -> str:
    base = (
        "shutoko.pre-drive-source.k7-aoba-to-kohoku."
        f"{kind}.{review_date(review)}"
    )
    return f"{base}.{suffix.lower()}" if suffix else base


def build_inputs(
    review: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any]]:
    validate_review(review)
    tariff = review["tariff_query"]
    passage = review["passage_review"]
    observations = tariff["observations"]

    source_registry = [
        {
            "authority_name": tariff["authority_name"],
            "checked_at": tariff["checked_at"],
            "content_sha256": observation["content_sha256"],
            "reviewed_at": review["reviewed_at"],
            "reviewer_id": review["reviewer_id"],
            "roles": ["TARIFF_QUERY"],
            "source_reference_id": source_id(
                review,
                "tariff",
                observation["vehicle_class"],
            ),
            "source_url": tariff["source_url"],
        }
        for observation in observations
    ]
    passage_source_id = source_id(review, "passage")
    source_registry.append(
        {
            "authority_name": passage["authority_name"],
            "checked_at": passage["checked_at"],
            "content_sha256": passage["content_sha256"],
            "reviewed_at": review["reviewed_at"],
            "reviewer_id": review["reviewer_id"],
            "roles": ["PASSAGE_REVIEW"],
            "source_reference_id": passage_source_id,
            "source_url": passage["source_url"],
        }
    )

    records: list[dict[str, Any]] = []
    for observation in observations:
        vehicle_class = observation["vehicle_class"]
        tariff_source_id = source_id(review, "tariff", vehicle_class)
        for payment_method in PAYMENT_METHODS:
            amount_field = "etc_yen" if payment_method == "ETC" else "cash_yen"
            profile = f"{vehicle_class.lower()}.{payment_method.lower()}"
            evidence_date = review_date(review)
            records.append(
                {
                    "evidence": {
                        "evaluated_at": review["reviewed_at"],
                        "passage_evidence": PASSAGE_RESULT,
                        "payment_method": payment_method,
                        "tariff_quotes": [
                            {
                                "checked_at": tariff["checked_at"],
                                "estimated_amount_yen": observation[amount_field],
                                "official_query_reference": tariff["source_url"],
                                "quote_id": (
                                    "shutoko.pre-drive-quote."
                                    f"k7-aoba-to-kohoku.{profile}.{evidence_date}"
                                ),
                                "status": "VERIFIED_QUERY",
                                "tariff_distance_km": observation["distance_km"],
                                "tariff_version_id": (
                                    "shutoko.tariff-query."
                                    f"k7-aoba-to-kohoku.{profile}.{evidence_date}"
                                ),
                                "tariff_version_status": "ACTIVE",
                            }
                        ],
                        "vehicle_class": vehicle_class,
                    },
                    "expires_at": review["expires_at"],
                    "record_id": (
                        "shutoko.pre-drive-record."
                        f"k7-aoba-to-kohoku.{profile}.{evidence_date}"
                    ),
                    "source_reference_ids": [
                        tariff_source_id,
                        passage_source_id,
                    ],
                    "valid_from": review["valid_from"],
                }
            )

    draft = {
        "records": records,
        "schema_version": "1.0",
        "source_registry": source_registry,
    }
    authoring = {
        "release_id": review["release_id"],
        "released_at": review["released_at"],
        "schema_version": "1.0",
    }
    return draft, authoring


def write_inputs(
    review_path: Path,
    draft_path: Path,
    authoring_path: Path,
) -> tuple[Path, Path]:
    destinations = (draft_path.resolve(), authoring_path.resolve())
    if destinations[0] == destinations[1]:
        raise EvidenceInputError("draft and config outputs must differ")
    for destination in destinations:
        if destination.exists():
            raise EvidenceInputError(f"output already exists: {destination}")

    draft, authoring = build_inputs(load_object(review_path.resolve()))
    pending: list[tuple[Path, Path]] = []
    try:
        for destination, content in zip(
            destinations,
            (encoded_json(draft), encoded_json(authoring)),
        ):
            destination.parent.mkdir(parents=True, exist_ok=True)
            descriptor, temporary_name = tempfile.mkstemp(
                prefix=f".{destination.name}.",
                dir=destination.parent,
            )
            temporary = Path(temporary_name)
            with os.fdopen(descriptor, "wb") as handle:
                os.fchmod(handle.fileno(), 0o644)
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
            pending.append((temporary, destination))
        for temporary, destination in pending:
            os.replace(temporary, destination)
    finally:
        for temporary, _destination in pending:
            temporary.unlink(missing_ok=True)
    return destinations


def main() -> int:
    arguments = parse_arguments()
    try:
        draft, authoring = write_inputs(
            arguments.review,
            arguments.draft,
            arguments.config,
        )
    except (OSError, EvidenceInputError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"PASS: wrote deterministic K7 pre-drive evidence input: {draft}")
    print(f"PASS: wrote deterministic K7 pre-drive evidence input: {authoring}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
