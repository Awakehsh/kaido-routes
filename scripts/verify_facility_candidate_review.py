#!/usr/bin/env python3
"""Verify the committed snapshot still matches its facility candidate review.

The builder applies dated, evidence-bound candidate corrections at ambiguous
or ramp-boundary locations. This check keeps that binding honest between
rebuilds: the snapshot must record the exact review it was built from, every
exclusion, rebinding, and replacement must still name a real facility, and the
facility must keep the exact reviewed result.

Run from the repository root. Exits non-zero with a specific reason.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
SNAPSHOT_DIRECTORY = REPOSITORY_ROOT / "data" / "route-atlas" / "osm-derived"
REVIEW_DIRECTORY = REPOSITORY_ROOT / "data" / "network"

SIDE_KEYS = {
    "entry": "entry_edge_candidates",
    "exit": "exit_edge_candidates",
}


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


def sole_match(directory: Path, pattern: str) -> Path:
    matches = sorted(directory.glob(pattern))
    if len(matches) != 1:
        fail(
            f"expected exactly one {pattern} in {directory}, found "
            f"{len(matches)}"
        )
    return matches[0]


def main() -> int:
    snapshot_path = sole_match(
        SNAPSHOT_DIRECTORY, "shuto-whole-network-*.json"
    )
    review_path = sole_match(
        REVIEW_DIRECTORY, "shuto-facility-candidate-review-*.json"
    )

    snapshot = json.loads(snapshot_path.read_bytes())
    review_bytes = review_path.read_bytes()
    review = json.loads(review_bytes)

    recorded = snapshot.get("sources", {}).get("facility_candidate_review")
    if not recorded:
        fail(f"{snapshot_path.name} records no facility candidate review")
    if recorded.get("review_id") != review.get("review_id"):
        fail(
            "snapshot was built from review "
            f"{recorded.get('review_id')}, not {review.get('review_id')}"
        )
    actual_sha = hashlib.sha256(review_bytes).hexdigest()
    if recorded.get("sha256") != actual_sha:
        fail(
            f"{review_path.name} changed since the snapshot was built; "
            "rebuild the snapshot instead of editing the review alone"
        )

    exclusions = review.get("excluded_candidates", [])
    if recorded.get("excluded_candidate_count") != len(exclusions):
        fail("snapshot records a different exclusion count than the review")
    rebindings = review.get("entry_boundary_rebindings", [])
    if recorded.get("entry_boundary_rebinding_count") != len(rebindings):
        fail(
            "snapshot records a different entry rebinding count than the review"
        )
    replacements = review.get("entry_candidate_replacements", [])
    if recorded.get("entry_candidate_replacement_count") != len(replacements):
        fail(
            "snapshot records a different entry replacement count than the review"
        )

    facilities = {
        facility["facility_id"]: facility
        for facility in snapshot["directional_facilities"]
    }
    for exclusion in exclusions:
        facility = facilities.get(exclusion["facility_id"])
        if facility is None:
            fail(f"review names unknown facility {exclusion['facility_id']}")
        key = SIDE_KEYS.get(exclusion["side"])
        if key is None:
            fail(f"review has an invalid side {exclusion['side']!r}")
        candidates = facility[key]
        if any(
            candidate["edge_id"] == exclusion["edge_id"]
            for candidate in candidates
        ):
            fail(
                "excluded candidate is still present: "
                f"{exclusion['facility_id']} {exclusion['edge_id']}"
            )
        if not candidates:
            fail(
                "review left no candidate for "
                f"{exclusion['facility_id']} ({exclusion['side']})"
            )
        for field in ("reason", "evidence"):
            if not exclusion.get(field):
                fail(
                    f"exclusion {exclusion['edge_id']} is missing {field}"
                )

    for rebinding in rebindings:
        facility = facilities.get(rebinding["facility_id"])
        if facility is None:
            fail(
                "entry boundary rebinding names unknown facility "
                + rebinding["facility_id"]
            )
        candidates = facility["entry_edge_candidates"]
        if any(
            candidate["edge_id"] == rebinding["anchor_edge_id"]
            for candidate in candidates
        ):
            fail(
                "entry boundary anchor is still a route candidate: "
                + rebinding["facility_id"]
            )
        matching = [
            candidate
            for candidate in candidates
            if candidate["edge_id"] == rebinding["boundary_edge_id"]
        ]
        if len(matching) != 1:
            fail(
                "entry boundary candidate is not uniquely present: "
                + rebinding["facility_id"]
            )
        if matching[0]["distance_meters"] != rebinding["distance_meters"]:
            fail(
                "entry boundary candidate distance differs from review: "
                + rebinding["facility_id"]
            )
        for field in ("reason", "evidence"):
            if not rebinding.get(field):
                fail(
                    "entry boundary rebinding is missing " + field
                )

    for replacement in replacements:
        facility = facilities.get(replacement["facility_id"])
        if facility is None:
            fail(
                "entry candidate replacement names unknown facility "
                + replacement["facility_id"]
            )
        candidates = facility["entry_edge_candidates"]
        if candidates != [
            {
                "edge_id": replacement["boundary_edge_id"],
                "distance_meters": replacement["distance_meters"],
            }
        ]:
            fail(
                "entry candidate replacement result differs from review: "
                + replacement["facility_id"]
            )
        for field in ("reason", "evidence"):
            if not replacement.get(field):
                fail("entry candidate replacement is missing " + field)

    print(
        f"PASS: {snapshot_path.name} matches {review_path.name} "
        f"with {len(exclusions)} reviewed exclusions and "
        f"{len(rebindings)} entry boundary rebindings and "
        f"{len(replacements)} entry candidate replacements"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
