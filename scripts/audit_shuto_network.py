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
- No ramp that OSM names after an interchange is left unbound: a link chain
  between a carriageway and the surface that no facility binds must not
  pass a toll booth or junction node carrying a facility's name. The
  2026-10-12 facility review dropped 扇大橋's exit from S1 as another
  interchange's ramp and never bound its S1 entrance or 浦安's second exit,
  though OSM names each after its interchange.

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
NAME_SUFFIXES = ("出入口", "出口", "入口", "料金所", "IC")


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


def facility_named(name: str, facility_names: set[str]) -> str | None:
    """The facility an OSM node name refers to, ignoring the ramp-role and
    IC suffixes OSM adds (扇大橋, 浦安出口, 高井戸IC)."""
    for suffix in ("",) + NAME_SUFFIXES:
        if name.endswith(suffix) and name[: len(name) - len(suffix)] in facility_names:
            return name[: len(name) - len(suffix)]
    return None


def named_unbound_ramps(
    network: dict[str, Any],
    owned_surface_ends: set[tuple[str, int]],
    closed_edge_ids: set[str],
    outgoing: dict[int, list[dict[str, Any]]],
    incoming: dict[int, list[dict[str, Any]]],
) -> dict[tuple[str, int], set[str]]:
    """(side, surface node) -> facility names on the link chain of a ramp
    whose surface end no facility binds. The chain runs from the surface end
    to the carriageway it leaves or joins; its junction and toll-booth nodes
    are where OSM names an interchange. A chain that reaches no carriageway
    is no ramp. Parking-area ramps, which end at a PA interior rather than
    the surface, and ramps a closure review closed are unbound by design."""
    facility_names = {facility["name_ja"] for facility in network["directional_facilities"]}
    node_names: dict[int, str] = {}
    for node in network["nodes"]:
        tags = node.get("tags") or {}
        if tags.get("name") and (
            tags.get("highway") == "motorway_junction" or tags.get("barrier") == "toll_booth"
        ):
            node_names[node["node_id"]] = tags["name"]
    parking_nodes = {
        node
        for edge in network["edges"]
        if edge["kind"] == "PARKING"
        for node in (edge["from_node_id"], edge["to_node_id"])
    }
    found: dict[tuple[str, int], set[str]] = {}
    for node_id in (set(outgoing) | set(incoming)) - parking_nodes:
        if incoming[node_id] and not outgoing[node_id]:
            side, toward_carriageway = "exit", incoming
        elif outgoing[node_id] and not incoming[node_id]:
            side, toward_carriageway = "entry", outgoing
        else:
            continue
        if (side, node_id) in owned_surface_ends or any(
            edge["kind"] != "LINK" for edge in toward_carriageway[node_id]
        ):
            # A carriageway terminus is the terminus check's, not a ramp.
            continue
        names: set[str] = set()
        closed = False
        reaches_carriageway = False
        seen: set[str] = set()
        frontier = [(node_id, 0.0)]
        while frontier:
            node, travelled = frontier.pop()
            if node in node_names:
                named = facility_named(node_names[node], facility_names)
                if named:
                    names.add(named)
            for following in toward_carriageway[node]:
                distance = travelled + following["length_meters"]
                reaches_carriageway = reaches_carriageway or following["kind"] == "MAINLINE"
                if (
                    following["kind"] != "LINK"
                    or following["edge_id"] in seen
                    or distance > SURFACE_SEARCH_METERS
                ):
                    continue
                seen.add(following["edge_id"])
                closed = closed or following["edge_id"] in closed_edge_ids
                frontier.append(
                    (following["from_node_id"] if side == "exit" else following["to_node_id"], distance)
                )
        if names and reaches_carriageway and not closed:
            found[(side, node_id)] = names
    return found


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
    named_exceptions = {
        (item["side"], item["node_id"]): item for item in exceptions["named_unbound_ramps"]
    }
    named = named_unbound_ramps(network, set(owners), closed_edge_ids, outgoing, incoming)
    for key, names in sorted(named.items()):
        exception = named_exceptions.get(key)
        if exception is None or not exception.get("reason"):
            findings.append(
                f"unbound {key[0]} ramp meeting the surface at node {key[1]} is named "
                + ", ".join(sorted(names))
            )
    for key in sorted(set(named_exceptions) - set(named)):
        findings.append(f"named unbound ramp exception {key[0]} {key[1]} no longer applies")
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
