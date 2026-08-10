#!/usr/bin/env python3
"""Verify the committed snapshot still matches its facility candidate review.

The builder applies dated, evidence-bound candidate exclusions at stacked or
shared-collector junctions. This check keeps that binding honest between
rebuilds: the snapshot must record the exact review it was built from, every
exclusion must still name a real facility, the excluded candidate must be
absent, and the facility must keep at least one candidate on that side.

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

    print(
        f"PASS: {snapshot_path.name} matches {review_path.name} "
        f"with {len(exclusions)} reviewed exclusions"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
