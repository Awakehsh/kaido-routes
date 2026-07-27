#!/usr/bin/env python3
"""Build reviewed K7 Atlas, navigation, and product authoring inputs."""

from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import date, datetime, timedelta
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
ATLAS_DRAFT_PATH = (
    REPOSITORY_ROOT
    / "data/route-atlas/releases/"
    "k7-northwest-up-aoba-to-kohoku-navigation-semantic-"
    "route-atlas-release-draft.json"
)
NAVIGATION_DRAFT_PATH = (
    REPOSITORY_ROOT
    / "data/navigation/releases/"
    "k7-northwest-up-aoba-to-kohoku-navigation-release-draft.json"
)
REVIEW_PACKET_PATH = (
    REPOSITORY_ROOT
    / "data/navigation/candidates/"
    "k7-northwest-up-aoba-to-kohoku-navigation-review-packet.json"
)
REVIEWS_PATH = (
    REPOSITORY_ROOT
    / "data/navigation/candidates/"
    "k7-northwest-up-aoba-to-kohoku-navigation-release-reviews.json"
)
ATLAS_V1_PATH = (
    REPOSITORY_ROOT
    / "data/route-atlas/releases/"
    "k7-northwest-up-aoba-to-kohoku-route-atlas-release.json"
)
ATLAS_V1_AUTHORING_PATH = (
    REPOSITORY_ROOT
    / "data/route-atlas/releases/"
    "k7-northwest-up-aoba-to-kohoku-route-atlas-release-authoring.json"
)
DEFAULT_ATLAS_AUTHORING_PATH = (
    REPOSITORY_ROOT
    / "data/route-atlas/releases/"
    "k7-northwest-up-aoba-to-kohoku-navigation-semantic-"
    "route-atlas-release-authoring.json"
)
DEFAULT_NAVIGATION_AUTHORING_PATH = (
    REPOSITORY_ROOT
    / "data/navigation/releases/"
    "k7-northwest-up-aoba-to-kohoku-navigation-release-authoring.json"
)
DEFAULT_PRODUCT_AUTHORING_PATH = (
    REPOSITORY_ROOT
    / "data/product/releases/"
    "k7-northwest-up-aoba-to-kohoku-product-release-authoring.json"
)

EXPECTED_SCOPES = {
    "TOPOLOGY": "INDEPENDENT_TOPOLOGY_REVIEWER",
    "LAYOUT": "INDEPENDENT_LAYOUT_REVIEWER",
    "NAVIGATION_GUIDANCE": "INDEPENDENT_NAVIGATION_GUIDANCE_REVIEWER",
}
SOURCE_IDS = {
    "osm": "osm.geofabrik.kanto-260721.k7-directed",
    "opening": "shutoko.k7-opening-attachment.2019-09-26",
    "toll": "shutoko.aoba-up-toll-map.2021-07-27",
    "aoba": "shutoko.guide.k7-aoba.2026-07-23",
    "kohoku": "shutoko.guide.k7-kohoku.2026-07-23",
}
NAVIGATION_SOURCE_ROLES = {
    SOURCE_IDS["osm"]: [
        "DECISION_ZONE",
        "EDITOR_CATALOG",
        "MATCHER_CORRIDOR",
        "RUNTIME_POLICY",
    ],
    SOURCE_IDS["opening"]: ["EDITOR_CATALOG", "RUNTIME_POLICY"],
    SOURCE_IDS["toll"]: ["EDITOR_CATALOG", "RUNTIME_POLICY"],
    SOURCE_IDS["aoba"]: [
        "EDITOR_CATALOG",
        "EDITOR_PRESENTATION",
        "RUNTIME_POLICY",
    ],
    SOURCE_IDS["kohoku"]: [
        "DECISION_ZONE",
        "EDITOR_CATALOG",
        "EDITOR_PRESENTATION",
        "GUIDANCE",
        "RUNTIME_POLICY",
    ],
}


class ReleaseInputError(ValueError):
    """Raised when reviewed release inputs are incomplete or drifted."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--as-of",
        required=True,
        type=date.fromisoformat,
        help="deterministic review assessment date in YYYY-MM-DD form",
    )
    parser.add_argument(
        "--atlas-config",
        type=Path,
        default=DEFAULT_ATLAS_AUTHORING_PATH,
    )
    parser.add_argument(
        "--navigation-config",
        type=Path,
        default=DEFAULT_NAVIGATION_AUTHORING_PATH,
    )
    parser.add_argument(
        "--product-config",
        type=Path,
        default=DEFAULT_PRODUCT_AUTHORING_PATH,
    )
    return parser.parse_args()


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReleaseInputError(f"cannot read {path}: {error}") from error
    if not isinstance(value, dict):
        raise ReleaseInputError(f"{path} must contain one JSON object")
    return value


def encoded_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")


def sha256_json(value: Any) -> str:
    return hashlib.sha256(encoded_json(value)).hexdigest()


def parse_datetime(value: str) -> datetime:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (TypeError, ValueError) as error:
        raise ReleaseInputError(f"invalid review timestamp: {value}") from error


def validate_reviews(
    reviews: dict[str, Any],
    packet: dict[str, Any],
    atlas_draft: dict[str, Any],
    navigation_draft: dict[str, Any],
    as_of: date,
) -> dict[str, dict[str, Any]]:
    if reviews.get("schema_version") != "1.0":
        raise ReleaseInputError("review schema version is not 1.0")
    if reviews.get("candidate_id") != packet.get("candidate_id"):
        raise ReleaseInputError("review candidate identity drifted")
    expected_bindings = packet.get("candidate_bindings")
    if reviews.get("candidate_bindings") != expected_bindings:
        raise ReleaseInputError("review candidate bindings drifted")
    if expected_bindings.get("atlas_draft_sha256") != sha256_json(atlas_draft):
        raise ReleaseInputError("reviewed Atlas draft hash drifted")
    if expected_bindings.get("navigation_draft_sha256") != sha256_json(
        navigation_draft
    ):
        raise ReleaseInputError("reviewed navigation draft hash drifted")

    values = reviews.get("reviews")
    if not isinstance(values, list) or len(values) != len(EXPECTED_SCOPES):
        raise ReleaseInputError("exactly three independent reviews are required")
    by_scope: dict[str, dict[str, Any]] = {}
    reviewer_ids: set[str] = set()
    for value in values:
        if not isinstance(value, dict):
            raise ReleaseInputError("review entries must be objects")
        scope = value.get("scope")
        if scope not in EXPECTED_SCOPES or scope in by_scope:
            raise ReleaseInputError("review scopes are missing, duplicated, or unknown")
        if value.get("reviewer_role") != EXPECTED_SCOPES[scope]:
            raise ReleaseInputError(f"{scope} reviewer role drifted")
        reviewer_id = value.get("reviewer_id")
        if not isinstance(reviewer_id, str) or not reviewer_id.strip():
            raise ReleaseInputError(f"{scope} reviewer identity is empty")
        if reviewer_id in reviewer_ids:
            raise ReleaseInputError("release scopes require different reviewers")
        reviewer_ids.add(reviewer_id)
        if value.get("status") != "APPROVED" or value.get("blocker_codes") != []:
            raise ReleaseInputError(f"{scope} review is not approved")
        record_sha = value.get("review_record_sha256")
        if (
            not isinstance(record_sha, str)
            or len(record_sha) != 64
            or any(character not in "0123456789abcdef" for character in record_sha)
        ):
            raise ReleaseInputError(f"{scope} review record hash is invalid")
        reviewed_at = parse_datetime(value.get("reviewed_at"))
        try:
            valid_through = date.fromisoformat(value.get("valid_through"))
        except (TypeError, ValueError) as error:
            raise ReleaseInputError(
                f"{scope} review validity date is invalid"
            ) from error
        if reviewed_at.date() > as_of or as_of > valid_through:
            raise ReleaseInputError(f"{scope} review is not current")
        by_scope[scope] = value
    if set(by_scope) != set(EXPECTED_SCOPES):
        raise ReleaseInputError("review scope coverage is incomplete")
    return by_scope


def navigation_sources(atlas_v1: dict[str, Any]) -> dict[str, Any]:
    references = {
        value["source_reference_id"]: value
        for value in atlas_v1["source_registry"]["references"]
    }
    missing = set(NAVIGATION_SOURCE_ROLES).difference(references)
    if missing:
        raise ReleaseInputError(
            f"navigation sources are missing from Atlas v1: {sorted(missing)}"
        )
    projected: list[dict[str, Any]] = []
    for source_id in SOURCE_IDS.values():
        source = references[source_id]
        projected.append(
            {
                "id": source_id,
                "roles": NAVIGATION_SOURCE_ROLES[source_id],
                "authority_name": source["authority_name"],
                "source_url": source["source_url"],
                "content_sha256": source["content_sha256"],
                "checked_at": source["checked_at"],
                "licence_identifier": source["licence_identifier"],
            }
        )
    return {"references": projected}


def evidence(
    role: str,
    asset_id: str,
    checked_at: str,
    source_reference_ids: list[str],
) -> dict[str, Any]:
    return {
        "role": role,
        "asset_id": asset_id,
        "state": "RELEASED",
        "checked_at": checked_at,
        "source_reference_ids": source_reference_ids,
    }


def build_inputs(
    atlas_draft: dict[str, Any],
    navigation_draft: dict[str, Any],
    packet: dict[str, Any],
    reviews: dict[str, Any],
    atlas_v1: dict[str, Any],
    atlas_v1_authoring: dict[str, Any],
    as_of: date,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    by_scope = validate_reviews(
        reviews,
        packet,
        atlas_draft,
        navigation_draft,
        as_of,
    )
    topology_date = parse_datetime(by_scope["TOPOLOGY"]["reviewed_at"]).date()
    layout_date = parse_datetime(by_scope["LAYOUT"]["reviewed_at"]).date()
    navigation_reviewed_at = parse_datetime(
        by_scope["NAVIGATION_GUIDANCE"]["reviewed_at"]
    )
    latest_reviewed_at = max(
        parse_datetime(value["reviewed_at"]) for value in by_scope.values()
    )
    navigation_checked_at = navigation_reviewed_at.date().isoformat()

    atlas_authoring = {
        "schema_version": "1.0",
        "source_registry": deepcopy(atlas_v1_authoring["source_registry"]),
        "topology_evidence": {
            "checked_at": topology_date.isoformat(),
            "source_reference_ids": deepcopy(
                atlas_v1_authoring["topology_evidence"]["source_reference_ids"]
            ),
            "state": "RELEASED",
        },
        "layout_evidence": {
            "checked_at": layout_date.isoformat(),
            "source_reference_ids": deepcopy(
                atlas_v1_authoring["layout_evidence"]["source_reference_ids"]
            ),
            "state": "RELEASED",
        },
    }

    editor_catalog_id = navigation_draft["editor_catalog_id"]
    presentation_id = navigation_draft["editor_presentation_catalog"][
        "presentation_catalog_id"
    ]
    runtime_policy_id = navigation_draft["runtime_policy"]["runtime_policy_id"]
    corridor_id = navigation_draft["matcher_corridor"]["corridor_id"]
    decision_zone_ids = [
        value["decision_zone_id"] for value in navigation_draft["decision_zones"]
    ]
    prompt_ids = [
        value["anchor"]["prompt_id"]
        for value in navigation_draft["released_guidance"]
    ]
    navigation_authoring = {
        "schema_version": "1.0",
        "release_id": "shutoko.navigation.k7-aoba-to-kohoku.2026-07-27",
        "released_at": latest_reviewed_at.isoformat(),
        "source_registry": navigation_sources(atlas_v1),
        "asset_evidence": [
            evidence(
                "EDITOR_CATALOG",
                editor_catalog_id,
                navigation_checked_at,
                list(SOURCE_IDS.values()),
            ),
            evidence(
                "EDITOR_PRESENTATION",
                presentation_id,
                navigation_checked_at,
                [SOURCE_IDS["aoba"], SOURCE_IDS["kohoku"]],
            ),
            evidence(
                "RUNTIME_POLICY",
                runtime_policy_id,
                navigation_checked_at,
                list(SOURCE_IDS.values()),
            ),
            evidence(
                "MATCHER_CORRIDOR",
                corridor_id,
                navigation_checked_at,
                [SOURCE_IDS["osm"]],
            ),
            *[
                evidence(
                    "DECISION_ZONE",
                    zone_id,
                    navigation_checked_at,
                    [SOURCE_IDS["osm"], SOURCE_IDS["kohoku"]],
                )
                for zone_id in decision_zone_ids
            ],
            *[
                evidence(
                    "GUIDANCE",
                    prompt_id,
                    navigation_checked_at,
                    [SOURCE_IDS["kohoku"]],
                )
                for prompt_id in prompt_ids
            ],
        ],
    }
    product_authoring = {
        "schema_version": "1.0",
        "release_id": "shutoko.product.k7-aoba-to-kohoku.2026-07-27",
        "released_at": (latest_reviewed_at + timedelta(seconds=1)).isoformat(),
    }
    return atlas_authoring, navigation_authoring, product_authoring


def write_new(path: Path, content: bytes) -> None:
    destination = path.resolve()
    if destination.exists():
        raise ReleaseInputError(f"output already exists: {destination}")
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
        outputs = build_inputs(
            load_object(ATLAS_DRAFT_PATH),
            load_object(NAVIGATION_DRAFT_PATH),
            load_object(REVIEW_PACKET_PATH),
            load_object(REVIEWS_PATH),
            load_object(ATLAS_V1_PATH),
            load_object(ATLAS_V1_AUTHORING_PATH),
            arguments.as_of,
        )
        destinations = [
            arguments.atlas_config,
            arguments.navigation_config,
            arguments.product_config,
        ]
        if len({value.resolve() for value in destinations}) != len(destinations):
            raise ReleaseInputError("release input outputs must be different files")
        for destination in destinations:
            if destination.resolve().exists():
                raise ReleaseInputError(
                    f"output already exists: {destination.resolve()}"
                )
        for destination, value in zip(destinations, outputs):
            write_new(destination, encoded_json(value))
    except (OSError, ReleaseInputError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    for destination in destinations:
        print(f"PASS: wrote reviewed K7 release input: {destination.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
