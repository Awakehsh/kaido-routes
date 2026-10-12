#!/usr/bin/env python3
"""Audit the committed whole-Shuto snapshot for graph and binding defects.

Each check stands for a defect a review has had to repair, so a rebuild or a
later patch that reintroduces one fails CI instead of shipping:

- Every carriageway (`MAINLINE`) dead end and dead start is a listed real
  terminus. Route 1 Haneda southbound once stopped for 1.8 km because its
  rebuilt section sat outside the route relation.
- No ramp is bound to two differently named facilities, judged by where it
  meets the surface. The builder bound every same-route edge within 750 m,
  so interchanges started and ended on their neighbours' ramps.
- A candidate further than the distance limit from its facility is a listed,
  reviewed exception.
- No facility binds a ramp a closure review closed.
- An exit ramp ends and an entrance ramp starts: following an exit past its
  toll point never reaches another interchange's exit, nor does tracing an
  entrance back reach another's entrance. OSM draws some interchanges' exit
  and entrance as one chain across the surface road, which let routes and
  fare paths turn back without leaving the toll road.

Exceptions live in `data/network/shuto-network-audit-exceptions.json`, bound to
the snapshot's `database_id` so a changed snapshot forces their review. Stale
exceptions fail too. Run from the repository root; exits non-zero with every
finding listed.
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
SNAPSHOT_DIRECTORY = REPOSITORY_ROOT / "data" / "route-atlas" / "osm-derived"
REVIEW_DIRECTORY = REPOSITORY_ROOT / "data" / "route-atlas" / "reviews"
EXCEPTIONS_PATH = REPOSITORY_ROOT / "data" / "network" / "shuto-network-audit-exceptions.json"
SIDES = {"entry": "entry_edge_candidates", "exit": "exit_edge_candidates"}


def mainline_termini(network: dict[str, Any]) -> dict[tuple[int, str], str]:
    """(node, dead_end|dead_start) -> one carriageway edge that ends or starts there."""
    outgoing: dict[int, int] = defaultdict(int)
    incoming: dict[int, int] = defaultdict(int)
    for edge in network["edges"]:
        outgoing[edge["from_node_id"]] += 1
        incoming[edge["to_node_id"]] += 1
    termini: dict[tuple[int, str], str] = {}
    for edge in network["edges"]:
        if edge["kind"] != "MAINLINE":
            continue
        if outgoing[edge["to_node_id"]] == 0:
            termini.setdefault((edge["to_node_id"], "dead_end"), edge["edge_id"])
        if incoming[edge["from_node_id"]] == 0:
            termini.setdefault((edge["from_node_id"], "dead_start"), edge["edge_id"])
    return termini


SURFACE_SEARCH_METERS = 3_000.0


def surface_ends(
    edge: dict[str, Any],
    side: str,
    outgoing: dict[int, list[dict[str, Any]]],
    incoming: dict[int, list[dict[str, Any]]],
) -> set[int]:
    """Where the candidate's ramp meets the surface: the dead ends an exit
    leads to, or the dead starts an entrance comes from. They identify the
    toll point, so two interchanges reaching the same one share a ramp."""
    forward = side == "exit"
    ends: set[int] = set()
    seen = {edge["edge_id"]}
    frontier = [(edge, 0.0)]
    while frontier:
        current, travelled = frontier.pop()
        node = current["to_node_id"] if forward else current["from_node_id"]
        nexts = outgoing[node] if forward else incoming[node]
        if not nexts:
            ends.add(node)
        for following in nexts:
            distance = travelled + following["length_meters"]
            if following["edge_id"] not in seen and distance <= SURFACE_SEARCH_METERS:
                seen.add(following["edge_id"])
                frontier.append((following, distance))
    return ends


def continues_to_other_toll_point(
    edge: dict[str, Any],
    side: str,
    name: str,
    toll_points: dict[str, dict[str, set[str]]],
    outgoing: dict[int, list[dict[str, Any]]],
    incoming: dict[int, list[dict[str, Any]]],
) -> bool:
    """Past an exit candidate a drive should only reach the surface, and
    before an entrance candidate it should only come from it. Reaching
    another interchange's toll point of the same role means the ramp rejoins
    the expressway, as a chain drawn across a surface road does."""
    forward = side == "exit"
    seen = {edge["edge_id"]}
    frontier = [edge]
    while frontier:
        current = frontier.pop()
        node = current["to_node_id"] if forward else current["from_node_id"]
        for following in outgoing[node] if forward else incoming[node]:
            if following["edge_id"] in seen:
                continue
            if toll_points[side].get(following["edge_id"], {name}) - {name}:
                return True
            seen.add(following["edge_id"])
            frontier.append(following)
    return False


def audit(
    network: dict[str, Any],
    exceptions: dict[str, Any],
    closed_edge_ids: set[str],
) -> list[str]:
    findings: list[str] = []
    if exceptions.get("database_id") != network["database_id"]:
        return [
            "audit exceptions were reviewed against "
            f"{exceptions.get('database_id')}, not {network['database_id']}"
        ]

    termini = mainline_termini(network)
    listed = {
        (item["node_id"], item["kind"]): item for item in exceptions["mainline_termini"]
    }
    for key, edge_id in sorted(termini.items()):
        if key not in listed:
            findings.append(
                f"carriageway {key[1].replace('_', ' ')} at node {key[0]} ({edge_id}) "
                "is not a listed terminus"
            )
        elif not listed[key].get("reason"):
            findings.append(f"terminus at node {key[0]} carries no reason")
    for key in sorted(set(listed) - set(termini)):
        findings.append(f"listed terminus at node {key[0]} ({key[1]}) is no longer one")

    edges = {edge["edge_id"]: edge for edge in network["edges"]}
    outgoing: dict[int, list[dict[str, Any]]] = defaultdict(list)
    incoming: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for edge in network["edges"]:
        if edge["kind"] == "PARKING":
            continue
        outgoing[edge["from_node_id"]].append(edge)
        incoming[edge["to_node_id"]].append(edge)

    limit = exceptions["candidate_distance_limit_meters"]
    distance_exceptions = {
        (item["facility_id"], item["edge_id"]): item
        for item in exceptions["candidate_distance_exceptions"]
    }
    continuation_exceptions = {
        (item["facility_id"], item["side"], item["edge_id"]): item
        for item in exceptions["ramp_continuations"]
    }
    used_distance: set[tuple[str, str]] = set()
    used_continuation: set[tuple[str, str, str]] = set()
    toll_points: dict[str, dict[str, set[str]]] = {side: defaultdict(set) for side in SIDES}
    roles: dict[str, set[tuple[str, str]]] = defaultdict(set)
    for facility in network["directional_facilities"]:
        for side, key in SIDES.items():
            for candidate in facility[key]:
                toll_points[side][candidate["edge_id"]].add(facility["name_ja"])
                roles[candidate["edge_id"]].add((facility["name_ja"], side))
    owners: dict[tuple[str, int], set[str]] = defaultdict(set)
    for facility in network["directional_facilities"]:
        for side, key in SIDES.items():
            for candidate in facility[key]:
                edge_id = candidate["edge_id"]
                where = f"{facility['facility_id']} {side} {edge_id}"
                edge = edges.get(edge_id)
                if edge is None or edge["kind"] == "PARKING":
                    findings.append(f"{where} is not a drivable edge")
                    continue
                if edge_id in closed_edge_ids:
                    findings.append(f"{where} binds a closed ramp")
                if candidate["distance_meters"] > limit:
                    exception = distance_exceptions.get((facility["facility_id"], edge_id))
                    if exception is None or not exception.get("reason"):
                        findings.append(
                            f"{where} is {candidate['distance_meters']:.0f} m from the "
                            f"facility, beyond {limit} m, without a reviewed exception"
                        )
                    used_distance.add((facility["facility_id"], edge_id))
                if continues_to_other_toll_point(
                    edge, side, facility["name_ja"], toll_points, outgoing, incoming
                ):
                    exception = continuation_exceptions.get((facility["facility_id"], side, edge_id))
                    if exception is None or not exception.get("reason"):
                        findings.append(
                            f"{where} continues past its toll point to another interchange's"
                        )
                    used_continuation.add((facility["facility_id"], side, edge_id))
                    continue
                for node in surface_ends(edge, side, outgoing, incoming):
                    owners[(side, node)].add(facility["name_ja"])
    for edge_id, bound in sorted(roles.items()):
        if len({name for name, _ in bound}) > 1 or len({side for _, side in bound}) > 1:
            findings.append(
                f"edge {edge_id} is bound as "
                + ", ".join(f"{name} {side}" for name, side in sorted(bound))
            )
    for (side, node), names in sorted(owners.items()):
        if len(names) > 1:
            findings.append(
                f"{side} ramp meeting the surface at node {node} is bound to "
                + ", ".join(sorted(names))
            )
    for key in sorted(set(distance_exceptions) - used_distance):
        findings.append(f"distance exception {key[0]} {key[1]} no longer applies")
    for key in sorted(set(continuation_exceptions) - used_continuation):
        findings.append(f"ramp continuation exception {key[0]} {key[1]} {key[2]} no longer applies")
    return findings


def closed_ramps(network: dict[str, Any]) -> set[str]:
    recorded = network["sources"].get("facility_closure_review")
    if not recorded:
        return set()
    review = json.loads((REVIEW_DIRECTORY / f"{recorded['review_id']}.json").read_text())
    return {
        edge_id
        for closure in review["closures"]
        for edge_id in closure["closed_ramp_edge_ids"]
    }


def main() -> int:
    snapshots = sorted(SNAPSHOT_DIRECTORY.glob("shuto-whole-network-*.json"))
    if len(snapshots) != 1:
        print(f"FAIL: expected one whole-network snapshot, found {len(snapshots)}")
        return 1
    network = json.loads(snapshots[0].read_text())
    exceptions = json.loads(EXCEPTIONS_PATH.read_text())
    findings = audit(network, exceptions, closed_ramps(network))
    if findings:
        for finding in findings:
            print(f"FAIL: {finding}")
        return 1
    candidates = sum(
        len(facility[key])
        for facility in network["directional_facilities"]
        for key in SIDES.values()
    )
    print(
        f"PASS: {snapshots[0].name}: {len(exceptions['mainline_termini'])} listed "
        f"termini, {candidates} candidates on exclusive ramps, "
        f"{len(exceptions['candidate_distance_exceptions'])} reviewed distance exceptions"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
