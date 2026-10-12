#!/usr/bin/env python3
"""Apply operator-announced facility closures to the whole-network snapshot.

The official catalog the network was built from records which directions each
interchange serves on the day it was checked. An operator notice can later
abolish an exit or close one direction of an entrance for years. This step
takes those directions out of the facility and unbinds the closed ramp from
every facility that had it as a candidate, so neither the closed facility nor
a neighbour bound to the same ramp by radius is offered or planned through it.

A facility left with no open direction becomes `UNAVAILABLE` with no ramp
bound, like the catalog's unavailable facilities. Graph geometry is
untouched, so `network_snapshot_id` stays and `database_id` gains the review's
revision.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

ROLES = (
    ("entrance_directions", "closed_entrance_directions", "entry_edge_candidates"),
    ("exit_directions", "closed_exit_directions", "exit_edge_candidates"),
)


class FacilityClosureError(RuntimeError):
    pass


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--network", required=True, type=Path)
    parser.add_argument("--review", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def apply_review(network: dict[str, Any], review: dict[str, Any]) -> dict[str, Any]:
    if review.get("schema_version") != "1.0":
        raise FacilityClosureError("unsupported facility closure review schema")
    if review.get("network_snapshot_id") != network["network_snapshot_id"]:
        raise FacilityClosureError(
            "review was taken against a different network snapshot"
        )
    applied = json.loads(json.dumps(network))
    facilities = {
        facility["facility_id"]: facility
        for facility in applied["directional_facilities"]
    }
    bound_before = {
        facility["facility_id"]: {
            key: bool(facility[key]) for _, _, key in ROLES
        }
        for facility in applied["directional_facilities"]
    }
    closed_edges: set[str] = set()
    seen: set[str] = set()
    for closure in review["closures"]:
        facility_id = closure["facility_id"]
        if facility_id in seen:
            raise FacilityClosureError(f"facility {facility_id} closed twice")
        seen.add(facility_id)
        facility = facilities.get(facility_id)
        if facility is None:
            raise FacilityClosureError(f"unknown facility {facility_id}")
        if not closure.get("evidence") or not closure.get("reason"):
            raise FacilityClosureError(f"closure of {facility_id} carries no evidence")
        if not any(closure[closed_key] for _, closed_key, _ in ROLES):
            raise FacilityClosureError(f"closure of {facility_id} closes no direction")
        for directions_key, closed_key, _ in ROLES:
            for direction in closure[closed_key]:
                if direction not in facility[directions_key]:
                    raise FacilityClosureError(
                        f"{facility_id} has no open {directions_key} {direction}"
                    )
        bound = {
            candidate["edge_id"]
            for _, _, key in ROLES
            for candidate in facility[key]
        }
        for edge_id in closure["closed_ramp_edge_ids"]:
            if edge_id not in bound:
                raise FacilityClosureError(
                    f"{edge_id} is not a ramp candidate of {facility_id}"
                )
        closed_edges.update(closure["closed_ramp_edge_ids"])

        remaining = {
            directions_key: [
                direction
                for direction in facility[directions_key]
                if direction not in closure[closed_key]
            ]
            for directions_key, closed_key, _ in ROLES
        }
        if not any(remaining.values()):
            # The catalog keeps an unavailable facility's official directions
            # and binds no ramp to it; a fully closed facility reads the same.
            facility["operational_status"] = "UNAVAILABLE"
            facility["geometry_match_state"] = "UNRESOLVED"
            for _, _, key in ROLES:
                facility[key] = []
            continue
        for directions_key, _, key in ROLES:
            facility[directions_key] = remaining[directions_key]
            if not remaining[directions_key]:
                facility[key] = []

    for facility in applied["directional_facilities"]:
        for directions_key, _, key in ROLES:
            facility[key] = [
                candidate
                for candidate in facility[key]
                if candidate["edge_id"] not in closed_edges
            ]
            if (
                facility["operational_status"] == "AVAILABLE"
                and facility[directions_key]
                and bound_before[facility["facility_id"]][key]
                and not facility[key]
            ):
                raise FacilityClosureError(
                    f"closing {sorted(closed_edges)} leaves "
                    f"{facility['facility_id']} without any {key}"
                )
    return applied


def main() -> int:
    arguments = parse_arguments()
    network = json.loads(arguments.network.read_text())
    review = json.loads(arguments.review.read_text())
    try:
        if review.get("input_database_sha256") != sha256(arguments.network):
            raise FacilityClosureError("review input database hash does not match")
        applied = apply_review(network, review)
    except FacilityClosureError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    applied["sources"]["facility_closure_review"] = {
        "review_id": review["review_id"],
        "checked_at": review["checked_at"],
        "sha256": sha256(arguments.review),
        "closed_facility_count": len(review["closures"]),
    }
    applied["database_id"] = (
        applied["database_id"]
        + "+facility-closures-"
        + review["checked_at"].replace("-", "")
    )
    # Byte-identical serialisation to `build_shuto_network.py`, so applying
    # the review shows up as the facilities it closes and nothing else.
    arguments.output.write_text(
        json.dumps(
            applied,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"wrote {arguments.output}: database_id={applied['database_id']}")
    facilities = {
        facility["facility_id"]: facility
        for facility in applied["directional_facilities"]
    }
    for closure in review["closures"]:
        facility = facilities[closure["facility_id"]]
        print(
            f"  {facility['facility_id']}: {facility['operational_status']} "
            f"entrances={facility['entrance_directions']} "
            f"exits={facility['exit_directions']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
