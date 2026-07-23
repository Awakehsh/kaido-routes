#!/usr/bin/env python3
"""Build the blocked K7 Northwest directed Route Atlas candidate."""

from __future__ import annotations

import argparse
import json
import math
import sys
from datetime import date, datetime
from pathlib import Path
from typing import Any


EXPECTED_CONTEXT_ID = "shuto.context.mlit-n06-2025-current"
EXPECTED_ROUTE_NAME = "高速横浜環状北西線"
EXPECTED_FEATURE_ID = "mlit.n06-2025.feature.1414"
EXPECTED_RECORD_ID = "EA02_373001"
EXPECTED_VERTEX_COUNT = 38
EXPECTED_RECONCILED_ROUTE_ID = "shutoko.k7.yokohama-northwest"


class CandidateBuildError(RuntimeError):
    """A fail-closed K7 candidate source or identity error."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context", required=True, type=Path)
    parser.add_argument("--route-catalog", required=True, type=Path)
    parser.add_argument("--review", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CandidateBuildError(f"cannot read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise CandidateBuildError(f"expected a JSON object in {path}")
    return value


def valid_sha256(value: Any) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def valid_point(value: Any) -> bool:
    return (
        isinstance(value, dict)
        and all(
            not isinstance(value.get(axis), bool)
            and isinstance(value.get(axis), (int, float))
            and math.isfinite(value[axis])
            and 0 <= value[axis] <= 1
            for axis in ("x", "y")
        )
    )


def validated_path(
    context: dict[str, Any],
    review: dict[str, Any],
) -> dict[str, Any]:
    binding = review.get("context_binding")
    if (
        context.get("context_id") != EXPECTED_CONTEXT_ID
        or context.get("navigation_role") != "CONTEXT_ONLY"
        or not isinstance(binding, dict)
        or binding.get("context_id") != EXPECTED_CONTEXT_ID
        or binding.get("route_name_ja") != EXPECTED_ROUTE_NAME
        or binding.get("source_feature_id") != EXPECTED_FEATURE_ID
        or binding.get("source_record_id") != EXPECTED_RECORD_ID
        or binding.get("expected_vertex_count") != EXPECTED_VERTEX_COUNT
        or binding.get("source_order_start_ja") != "横浜港北JCT"
        or binding.get("source_order_end_ja") != "横浜青葉"
        or binding.get("candidate_direction") != "REVERSED_FROM_SOURCE_ORDER"
    ):
        raise CandidateBuildError("K7 Northwest context binding has drifted")
    paths = [
        path
        for path in context.get("paths", [])
        if isinstance(path, dict)
        and path.get("route_name_ja") == EXPECTED_ROUTE_NAME
        and path.get("source_feature_id") == EXPECTED_FEATURE_ID
        and path.get("source_record_id") == EXPECTED_RECORD_ID
    ]
    if len(paths) != 1:
        raise CandidateBuildError(
            "expected exactly one K7 Northwest context source path"
        )
    points = paths[0].get("points")
    if (
        not isinstance(points, list)
        or len(points) != EXPECTED_VERTEX_COUNT
        or not all(valid_point(point) for point in points)
    ):
        raise CandidateBuildError("K7 Northwest context geometry has drifted")
    return paths[0]


def validate_catalog(
    catalog: dict[str, Any],
    review: dict[str, Any],
) -> None:
    reconciliations = catalog.get("naming_reconciliations")
    references = review.get("source_references")
    if not isinstance(reconciliations, list) or len(reconciliations) != 1:
        raise CandidateBuildError("K7 Northwest catalog reconciliation is missing")
    reconciliation = reconciliations[0]
    if (
        not isinstance(reconciliation, dict)
        or reconciliation.get("operator_route_id")
        != EXPECTED_RECONCILED_ROUTE_ID
        or reconciliation.get("context_route_name_ja") != EXPECTED_ROUTE_NAME
        or reconciliation.get("context_source_feature_id")
        != EXPECTED_FEATURE_ID
        or reconciliation.get("context_source_record_id") != EXPECTED_RECORD_ID
    ):
        raise CandidateBuildError("K7 Northwest catalog reconciliation has drifted")
    if not isinstance(references, list):
        raise CandidateBuildError("candidate source registry is missing")
    operator_reference = next(
        (
            reference
            for reference in references
            if isinstance(reference, dict)
            and reference.get("source_reference_id")
            == "shutoko.route.k7-northwest.2026-07-23"
        ),
        None,
    )
    if (
        operator_reference is None
        or operator_reference.get("source_url")
        != reconciliation.get("operator_source_url")
        or operator_reference.get("content_sha256")
        != reconciliation.get("operator_content_sha256")
    ):
        raise CandidateBuildError(
            "K7 Northwest operator source identity has drifted"
        )


def validated_review(review: dict[str, Any]) -> None:
    try:
        date.fromisoformat(review.get("checked_at"))
    except (TypeError, ValueError) as error:
        raise CandidateBuildError("candidate review date is invalid") from error
    if (
        review.get("schema_version") != "1.0"
        or review.get("candidate_state") != "OFFICIAL_CHECKED"
        or review.get("navigation_authority") is not False
        or not isinstance(review.get("network_snapshot_id"), str)
        or not review["network_snapshot_id"]
        or not isinstance(review.get("release_blockers"), list)
        or len(review["release_blockers"]) < 5
    ):
        raise CandidateBuildError("candidate review boundary is incomplete")
    try:
        datetime.fromisoformat(review.get("network_effective_at"))
    except (TypeError, ValueError) as error:
        raise CandidateBuildError(
            "candidate network effective time is invalid"
        ) from error
    plan = review.get("route_plan")
    if not isinstance(plan, dict) or not all(
        isinstance(plan.get(key), str) and plan[key]
        for key in (
            "plan_id",
            "entry_facility_id",
            "exit_facility_id",
            "route_entity_id",
        )
    ):
        raise CandidateBuildError("candidate RoutePlan identity is incomplete")
    references = review.get("source_references")
    topology_ids = review.get("topology_evidence_source_ids")
    layout_ids = review.get("layout_evidence_source_ids")
    claims = review.get("reviewed_claims")
    if (
        not isinstance(references, list)
        or len(references) != 4
        or not isinstance(topology_ids, list)
        or not isinstance(layout_ids, list)
        or not isinstance(claims, list)
        or len(claims) != 3
    ):
        raise CandidateBuildError("candidate evidence coverage is incomplete")
    references_by_id: dict[str, dict[str, Any]] = {}
    reference_ids: set[str] = set()
    for reference in references:
        if not isinstance(reference, dict):
            raise CandidateBuildError("candidate source reference is invalid")
        reference_id = reference.get("source_reference_id")
        roles = reference.get("roles")
        if (
            not isinstance(reference_id, str)
            or not reference_id
            or reference_id in reference_ids
            or not isinstance(roles, list)
            or not roles
            or not set(roles).issubset(
                {"TOPOLOGY_EVIDENCE", "LAYOUT_EVIDENCE"}
            )
            or not isinstance(reference.get("authority_name"), str)
            or not str(reference.get("source_url", "")).startswith("https://")
            or not valid_sha256(reference.get("content_sha256"))
            or not isinstance(reference.get("licence_identifier"), str)
        ):
            raise CandidateBuildError("candidate source reference is invalid")
        try:
            date.fromisoformat(reference.get("checked_at"))
        except (TypeError, ValueError) as error:
            raise CandidateBuildError(
                "candidate source checked date is invalid"
            ) from error
        reference_ids.add(reference_id)
        references_by_id[reference_id] = reference
    if (
        len(set(topology_ids)) != len(topology_ids)
        or len(set(layout_ids)) != len(layout_ids)
        or set(topology_ids) | set(layout_ids) != reference_ids
        or not set(layout_ids).issubset(set(topology_ids))
        or any(
            "TOPOLOGY_EVIDENCE" not in references_by_id[source_id]["roles"]
            for source_id in topology_ids
        )
        or any(
            "LAYOUT_EVIDENCE" not in references_by_id[source_id]["roles"]
            for source_id in layout_ids
        )
    ):
        raise CandidateBuildError("candidate evidence roles have drifted")
    claim_ids: set[str] = set()
    for claim in claims:
        if not isinstance(claim, dict):
            raise CandidateBuildError("candidate reviewed claim is invalid")
        claim_id = claim.get("claim_id")
        claim_sources = claim.get("source_reference_ids")
        if (
            not isinstance(claim_id, str)
            or not claim_id
            or claim_id in claim_ids
            or not isinstance(claim.get("value"), str)
            or not claim["value"]
            or not isinstance(claim_sources, list)
            or not claim_sources
            or not set(claim_sources).issubset(reference_ids)
        ):
            raise CandidateBuildError("candidate reviewed claim is invalid")
        claim_ids.add(claim_id)


def build(
    context: dict[str, Any],
    catalog: dict[str, Any],
    review: dict[str, Any],
) -> dict[str, Any]:
    validated_review(review)
    path = validated_path(context, review)
    validate_catalog(catalog, review)
    plan = review["route_plan"]
    directed_points = list(reversed(path["points"]))
    aoba_node_id = "shutoko.node.k7-northwest.aoba-up-entry"
    kohoku_node_id = "shutoko.node.k7-northwest.kohoku-up-exit"
    topology_edge_id = "shutoko.topology-edge.k7-northwest.up.aoba-to-kohoku"
    segment_id = "shutoko.segment.k7-northwest.up.aoba-to-kohoku"
    occurrence_id = "shutoko.occurrence.k7-northwest.up.aoba-to-kohoku.0"
    snapshot_id = review["network_snapshot_id"]
    route_plan_id = plan["plan_id"]
    topology_slice_id = "shutoko.topology.k7-northwest.candidate.2026-07-23"
    evidence = {
        "state": review["candidate_state"],
        "checked_at": review["checked_at"],
    }
    return {
        "schema_version": "1.0",
        "network_snapshot": {
            "id": snapshot_id,
            "status": "ACTIVE",
            "effective_at": review["network_effective_at"],
        },
        "route_plan": {
            "plan_id": route_plan_id,
            "network_snapshot_id": snapshot_id,
            "entry_facility_id": plan["entry_facility_id"],
            "exit_facility_id": plan["exit_facility_id"],
            "recovery_policy": "STRICT",
            "occurrences": [
                {
                    "occurrence_id": occurrence_id,
                    "index": 0,
                    "kind": "EDGE",
                    "entity_id": plan["route_entity_id"],
                }
            ],
        },
        "source_registry": {
            "references": review["source_references"],
        },
        "topology_slice": {
            "topology_slice_id": topology_slice_id,
            "network_snapshot_id": snapshot_id,
            "nodes": [
                {"node_id": aoba_node_id},
                {"node_id": kohoku_node_id},
            ],
            "edges": [
                {
                    "edge_id": topology_edge_id,
                    "route_entity_id": plan["route_entity_id"],
                    "from_node_id": aoba_node_id,
                    "to_node_id": kohoku_node_id,
                    "successor_edge_ids": [],
                }
            ],
            "evidence": {
                **evidence,
                "source_reference_ids": review[
                    "topology_evidence_source_ids"
                ],
            },
        },
        "definition": {
            "atlas_id": "shutoko.atlas.k7-northwest.candidate.2026-07-23",
            "network_snapshot_id": snapshot_id,
            "route_plan_id": route_plan_id,
            "topology_slice_id": topology_slice_id,
            "nodes": [
                {
                    "topology_node_id": aoba_node_id,
                    "point": directed_points[0],
                },
                {
                    "topology_node_id": kohoku_node_id,
                    "point": directed_points[-1],
                },
            ],
            "segments": [
                {
                    "segment_id": segment_id,
                    "topology_edge_id": topology_edge_id,
                    "from_node_id": aoba_node_id,
                    "to_node_id": kohoku_node_id,
                    "successor_segment_ids": [],
                    "points": directed_points,
                }
            ],
            "occurrence_bindings": [
                {
                    "occurrence_id": occurrence_id,
                    "occurrence_index": 0,
                    "segment_id": segment_id,
                }
            ],
            "evidence": {
                **evidence,
                "source_reference_ids": review["layout_evidence_source_ids"],
            },
        },
    }


def main() -> int:
    args = parse_args()
    try:
        artifact = build(
            load_object(args.context),
            load_object(args.route_catalog),
            load_object(args.review),
        )
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(artifact, ensure_ascii=False, indent=2, sort_keys=True)
            + "\n",
            encoding="utf-8",
        )
    except (CandidateBuildError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        "PASS: built OFFICIAL_CHECKED K7 Northwest candidate with "
        f"{len(artifact['definition']['segments'][0]['points'])} retained "
        "MLIT vertices; navigation authority remains false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
