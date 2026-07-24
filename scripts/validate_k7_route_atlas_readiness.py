#!/usr/bin/env python3
"""Validate the hash-bound K7 Route Atlas candidate readiness package."""

from __future__ import annotations

import argparse
from datetime import date, datetime
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

from validate_k7_surface_field_review import (
    FieldReviewError,
    evaluate as evaluate_field_review,
    validate_review_input_path,
)


EXPECTED_SCHEMA_VERSION = "1.0"
EXPECTED_READINESS_ID = (
    "shutoko.k7-northwest.aoba-up-to-kohoku-up." "route-atlas-readiness.2026-07-24"
)
EXPECTED_SCOPE = "ROUTE_ATLAS_CANDIDATE"
EXPECTED_TARGET = {
    "network_snapshot_id": (
        "shutoko.candidate.osm-geofabrik-kanto-260721.k7-northwest"
    ),
    "route_plan_id": (
        "shutoko.plan.k7-northwest.aoba-up-to-kohoku-up." "osm-directed-candidate"
    ),
    "topology_slice_id": (
        "shutoko.topology.k7-northwest." "osm-directed-candidate.2026-07-23"
    ),
    "atlas_id": ("shutoko.atlas.k7-northwest." "schematic-layout-candidate.2026-07-23"),
    "exit_facility_id": ("shutoko.exit.yokohama-kohoku.k7-northwest.up"),
    "route_occurrence_count": 13,
    "topology_edge_count": 15,
    "layout_segment_count": 15,
}
EXPECTED_ROAD_TARGET = {
    "network_snapshot_id": EXPECTED_TARGET["network_snapshot_id"],
    "exit_facility_id": EXPECTED_TARGET["exit_facility_id"],
    "incoming_osm_way_id": 734299106,
    "via_osm_node_id": 7473451738,
    "surface_osm_way_id": 776884422,
    "source_direction": "FORWARD",
}
EXPECTED_BINDING_PATHS = {
    "ROUTE_ATLAS_CANDIDATE": (
        "data/route-atlas/candidates/"
        "k7-northwest-up-aoba-to-kohoku-schematic-layout-candidate.json"
    ),
    "DIRECTED_SOURCE_REVIEW": (
        "data/route-atlas/candidates/"
        "k7-northwest-up-aoba-to-kohoku-osm-directed-review.json"
    ),
    "SOURCE_SUCCESSOR_AUDIT": (
        "data/route-atlas/osm-derived/" "k7-northwest-260721-successor-audit.json"
    ),
    "SCHEMATIC_LAYOUT_SOURCE": (
        "data/route-atlas/design/" "k7-northwest-up-schematic-layout-candidate.json"
    ),
    "TOPOLOGY_RELEASE_REVIEW": (
        "data/route-atlas/candidates/"
        "k7-northwest-up-aoba-to-kohoku-topology-release-review.template.json"
    ),
    "LAYOUT_RELEASE_REVIEW": (
        "data/route-atlas/candidates/"
        "k7-northwest-up-aoba-to-kohoku-layout-release-review.template.json"
    ),
    "ROAD_REGISTER_REVIEW": (
        "data/route-atlas/candidates/"
        "k7-northwest-up-aoba-to-kohoku-road-register-review.json"
    ),
    "FIELD_REVIEW_TEMPLATE": (
        "docs/testing/fixtures/" "k7-yokohama-kohoku-surface-field-review.template.json"
    ),
    "ODBL_DISTRIBUTION_REVIEW": (
        "data/route-atlas/osm-derived/" "k7-northwest-260721-distribution-review.json"
    ),
}
EXPECTED_DISTRIBUTION_REVIEW_ID = (
    "shutoko.k7-northwest.osm-derived-distribution.2026-07-24"
)
EXPECTED_ODBL_LICENCE_URL = "https://opendatacommons.org/licenses/odbl/1-0/"
EXPECTED_OSM_ATTRIBUTION = "© OpenStreetMap contributors"
EXPECTED_OSM_ATTRIBUTION_URL = "https://www.openstreetmap.org/copyright"
EXPECTED_DISTRIBUTION_BINDING_PATHS = {
    "DERIVATIVE_DATABASE": (
        "data/route-atlas/osm-derived/" "k7-northwest-260721-directed-database.json"
    ),
    "SOURCE_SUCCESSOR_AUDIT": (
        "data/route-atlas/osm-derived/" "k7-northwest-260721-successor-audit.json"
    ),
    "DISTRIBUTION_README": "data/route-atlas/osm-derived/README.md",
    "ATTRIBUTION_CATALOG": (
        "data/route-atlas/attribution/" "route-atlas-attribution-catalog.json"
    ),
    "ATTRIBUTION_MODEL": ("Apps/KaidoRoutesApp/Sources/RouteAtlasAttribution.swift"),
    "ATTRIBUTION_VIEW": ("Apps/KaidoRoutesApp/Sources/RouteAtlasHomeView.swift"),
    "APP_PROJECT_MANIFEST": "project.yml",
}
EXPECTED_DISTRIBUTION_REFERENCE_URLS = {
    "https://www.openstreetmap.org/copyright",
    "https://opendatacommons.org/licenses/odbl/1-0/",
    "https://osmfoundation.org/wiki/Licence/Attribution_Guidelines",
}
EXPECTED_OSM_SOURCE_ID = "osm.geofabrik.kanto-260721.k7-directed"
EXPECTED_AUDIT_ID = (
    "shutoko.k7-northwest.aoba-up-to-kohoku-up." "successor-audit.2026-07-23"
)
EXPECTED_ROAD_REVIEW_ID = "shutoko.k7-northwest.kohoku-surface-road-register.2026-07-24"
EXPECTED_REGISTER_URL = "https://wwwm.city.yokohama.lg.jp/yokohama/Portal"
EXPECTED_ROAD_SOURCE_REFERENCES = {
    "yokohama.road-register-access.2026-07-24": {
        "source_reference_id": "yokohama.road-register-access.2026-07-24",
        "authority_name": "City of Yokohama",
        "source_url": (
            "https://www.city.yokohama.lg.jp/kurashi/"
            "machizukuri-kankyo/doro/tetsuzuki/daichosys.html"
        ),
        "content_sha256": (
            "d3969d3cc62c04208abbffa2fa6c36d2f15fc6e509302f8f335697bc227fe9b6"
        ),
        "source_last_updated_at": "2026-01-20",
        "checked_at": "2026-07-24",
        "licence_identifier": "GOVERNMENT_FACTUAL_REFERENCE_ONLY",
    },
    "yokohama.road-name-faq.2026-07-24": {
        "source_reference_id": "yokohama.road-name-faq.2026-07-24",
        "authority_name": "City of Yokohama",
        "source_url": (
            "https://www.city.yokohama.lg.jp/faq/kukyoku/"
            "doro/doro-chosa/20211014144003932.html"
        ),
        "content_sha256": (
            "9c5e2027622f51e1682e52c4e370f3ca02d22ccfff9c839fb79c1c5d0266b06f"
        ),
        "source_last_updated_at": "2026-03-19",
        "checked_at": "2026-07-24",
        "licence_identifier": "GOVERNMENT_FACTUAL_REFERENCE_ONLY",
    },
    "yokohama.road-register-currentness.2026-07-24": {
        "source_reference_id": "yokohama.road-register-currentness.2026-07-24",
        "authority_name": "City of Yokohama",
        "source_url": (
            "https://wwwm.city.yokohama.lg.jp/yokohama-sp/yokohama-sp/"
            "Content/pages/up_date/5_michi/koushin.html"
        ),
        "content_sha256": (
            "33d94d39759fa1d5d7438c9c7b41ee412b6aa9dacd828019d25e935e415a07f9"
        ),
        "recognized_route_data_current_through": "2026-07-03",
        "checked_at": "2026-07-24",
        "licence_identifier": "GOVERNMENT_FACTUAL_REFERENCE_ONLY",
    },
    "yokohama.recognized-route-terms.2026-07-24": {
        "source_reference_id": "yokohama.recognized-route-terms.2026-07-24",
        "authority_name": "City of Yokohama",
        "source_url": (
            "https://wwwm.city.yokohama.lg.jp/yokohama/"
            "PositionSelect?mid=66"
        ),
        "content_sha256": (
            "ed482c2fd7b92c88ec68e06d15c2d517339120f57acda8234aceca18c177ee83"
        ),
        "checked_at": "2026-07-24",
        "licence_identifier": "GOVERNMENT_FACTUAL_REFERENCE_ONLY",
    },
    "yokohama.plan-drawing-terms.2026-07-24": {
        "source_reference_id": "yokohama.plan-drawing-terms.2026-07-24",
        "authority_name": "City of Yokohama",
        "source_url": (
            "https://wwwm.city.yokohama.lg.jp/yokohama/"
            "PositionSelect?mid=67"
        ),
        "content_sha256": (
            "e98aa1e272f7aca3bb8c52dd2855fae6038bb29902aa00ff63a58ca27295d102"
        ),
        "checked_at": "2026-07-24",
        "licence_identifier": "GOVERNMENT_FACTUAL_REFERENCE_ONLY",
    },
    "yokohama.k7-northwest.brochure.2026-07-23": {
        "source_reference_id": "yokohama.k7-northwest.brochure.2026-07-23",
        "authority_name": "City of Yokohama",
        "source_url": (
            "https://www.city.yokohama.lg.jp/kurashi/machizukuri-kankyo/"
            "doro/kousokudoro/kanjodouro.files/0006_20220315.pdf"
        ),
        "content_sha256": (
            "ff4e905661ab7006464fc867ab48b3b3de311bfae438db8af41817633f550d01"
        ),
        "checked_at": "2026-07-23",
        "licence_identifier": "GOVERNMENT_FACTUAL_REFERENCE_ONLY",
    },
    "yokohama.kawamuki-opening.2020-02-06": {
        "source_reference_id": "yokohama.kawamuki-opening.2020-02-06",
        "authority_name": "City of Yokohama",
        "source_url": (
            "https://www.city.yokohama.lg.jp/city-info/koho-kocho/press/"
            "doro/2019/0206-kawamukousen.files/0005_20200206.pdf"
        ),
        "archive_url": (
            "https://web.archive.org/web/20200327180920id_/https://"
            "www.city.yokohama.lg.jp/city-info/koho-kocho/press/doro/"
            "2019/0206-kawamukousen.files/0005_20200206.pdf"
        ),
        "content_sha256": (
            "bca0774b5e80dd4bb1ed3ce3960d053e953b8cd376f2864c10f7df47eb9a7c35"
        ),
        "published_at": "2020-02-06",
        "checked_at": "2026-07-23",
        "licence_identifier": "GOVERNMENT_FACTUAL_REFERENCE_ONLY",
    },
}
EXPECTED_ROAD_SUPPORTING_FINDINGS = {
    "official_exit_connection": {
        "status": "CORRIDOR_LEVEL_ONLY",
        "finding": "Yokohama Kohoku Exit connects to Kawamuki Line.",
        "source_reference_ids": ["yokohama.k7-northwest.brochure.2026-07-23"],
    },
    "official_corridor_identity": {
        "status": "HISTORICAL_CORRIDOR_IDENTITY",
        "recognized_route_identifier": "CITY_ROAD_HIGASHIKATA_NO_342",
        "recognized_route_name_ja": "市道東方町第342号線",
        "urban_plan_name_ja": "都市計画道路川向線",
        "source_reference_ids": ["yokohama.kawamuki-opening.2020-02-06"],
    },
    "exact_osm_way_mapping": {
        "status": "UNCONFIRMED",
        "reason_code": "CORRIDOR_EVIDENCE_DOES_NOT_ISOLATE_EXACT_WAY",
        "reason": (
            "The official corridor descriptions do not uniquely distinguish "
            "OSM way 776884422 from the two named Kawamuki Line carriageways "
            "that leave the same exit-terminal node."
        ),
    },
}
EXPECTED_TOPOLOGY_REVIEW_ID = (
    "shutoko.k7-northwest.aoba-up-to-kohoku-up." "topology-release-review.2026-07-24"
)
EXPECTED_LAYOUT_REVIEW_ID = (
    "shutoko.k7-northwest.aoba-up-to-kohoku-up." "layout-release-review.2026-07-24"
)
EXPECTED_TOPOLOGY_REVIEW_TARGET = {
    "network_snapshot_id": EXPECTED_TARGET["network_snapshot_id"],
    "route_plan_id": EXPECTED_TARGET["route_plan_id"],
    "topology_slice_id": EXPECTED_TARGET["topology_slice_id"],
    "exit_facility_id": EXPECTED_TARGET["exit_facility_id"],
    "route_occurrence_count": 13,
    "topology_edge_count": 15,
    "source_adjacency_checkpoint_count": 14,
    "source_successor_count": 19,
}
EXPECTED_LAYOUT_REVIEW_TARGET = {
    "network_snapshot_id": EXPECTED_TARGET["network_snapshot_id"],
    "route_plan_id": EXPECTED_TARGET["route_plan_id"],
    "topology_slice_id": EXPECTED_TARGET["topology_slice_id"],
    "atlas_id": EXPECTED_TARGET["atlas_id"],
    "layout_node_count": 16,
    "layout_segment_count": 15,
    "route_occurrence_binding_count": 13,
    "rendered_surface_successor_count": 0,
}
EXPECTED_TOPOLOGY_REVIEW_BINDINGS = {
    "ROUTE_ATLAS_CANDIDATE": {
        "repository_path": EXPECTED_BINDING_PATHS["ROUTE_ATLAS_CANDIDATE"],
        "content_sha256": (
            "1d6c428a5f0f26c647fe935471238e04767e150970f845231c4c21e7db030977"
        ),
    },
    "SOURCE_SUCCESSOR_AUDIT": {
        "repository_path": EXPECTED_BINDING_PATHS["SOURCE_SUCCESSOR_AUDIT"],
        "content_sha256": (
            "63b8f76d5f04c15aff80c688666de4a425f12b4f636c40ee0d36d8772b18e27e"
        ),
    },
    "ROAD_REGISTER_REVIEW": {
        "repository_path": EXPECTED_BINDING_PATHS["ROAD_REGISTER_REVIEW"],
        "content_sha256": (
            "8ada39b0f476eb5d025fdd0f0c8f91c5cb2c07136bd11c24c810cfee85f4ff8f"
        ),
    },
    "FIELD_REVIEW_TEMPLATE": {
        "repository_path": EXPECTED_BINDING_PATHS["FIELD_REVIEW_TEMPLATE"],
        "content_sha256": (
            "d16ce46aff643902df9c05815fd929ced64a79b788d470976a0ea2ad7a64abd2"
        ),
    },
}
EXPECTED_LAYOUT_REVIEW_BINDINGS = {
    "ROUTE_ATLAS_CANDIDATE": {
        "repository_path": EXPECTED_BINDING_PATHS["ROUTE_ATLAS_CANDIDATE"],
        "content_sha256": (
            "1d6c428a5f0f26c647fe935471238e04767e150970f845231c4c21e7db030977"
        ),
    },
    "SCHEMATIC_LAYOUT_SOURCE": {
        "repository_path": EXPECTED_BINDING_PATHS["SCHEMATIC_LAYOUT_SOURCE"],
        "content_sha256": (
            "1b0c8463ca029288ebe5af05fc158525f8cdd838b4194b2d9ab9e0fa43768239"
        ),
    },
    "SCHEMATIC_LAYOUT_SVG": {
        "repository_path": (
            "data/route-atlas/design/" "k7-northwest-up-schematic-layout-candidate.svg"
        ),
        "content_sha256": (
            "9dafa2e15569e2cd2fad04f17af38c1d0a28d7d046e2de1bf4c5f48aaa2abd2b"
        ),
    },
    "ATTRIBUTION_CATALOG": {
        "repository_path": (
            "data/route-atlas/attribution/" "route-atlas-attribution-catalog.json"
        ),
        "content_sha256": (
            "feb7fc889b4b639a8898ecda57bc1f75070b14f5b0027d25ecdc89ccc8a5f0d2"
        ),
    },
}
MAX_RELEASE_REVIEW_VALIDITY_DAYS = 31
EXPECTED_TOPOLOGY_REVIEW_KEYS = {
    "schema_version",
    "review_id",
    "review_type",
    "assessed_at",
    "navigation_authority",
    "target",
    "artifact_bindings",
    "required_checks",
    "private_field_review_manifest_sha256",
    "decision",
}
EXPECTED_LAYOUT_REVIEW_KEYS = {
    "schema_version",
    "review_id",
    "review_type",
    "assessed_at",
    "navigation_authority",
    "target",
    "artifact_bindings",
    "required_checks",
    "decision",
}
EXPECTED_UNRESOLVED_SUCCESSOR = {
    "direction": "FORWARD",
    "incoming_way_id": 734299106,
    "reason_code": "CURRENT_ROAD_IDENTITY_AND_DIRECTION_UNCONFIRMED",
    "via_node_id": 7473451738,
    "way_id": 776884422,
}
ALLOWED_EVIDENCE_STATES = {
    "CANDIDATE",
    "OFFICIAL_CHECKED",
    "FIELD_CHECKED",
    "RELEASED",
}
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


class ReadinessError(RuntimeError):
    """A malformed or drifting release-readiness package."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("readiness", type=Path)
    parser.add_argument(
        "--as-of",
        required=True,
        type=date.fromisoformat,
        help="deterministic assessment date in YYYY-MM-DD form",
    )
    parser.add_argument(
        "--repository-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    parser.add_argument(
        "--field-review",
        type=Path,
        help="optional ignored private field-review manifest",
    )
    parser.add_argument("--report", type=Path)
    return parser.parse_args()


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReadinessError(f"cannot read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise ReadinessError(f"{path} must contain a JSON object")
    return value


def parse_timestamp(value: Any, field: str) -> datetime:
    if not isinstance(value, str) or not value:
        raise ReadinessError(f"{field} must be an RFC 3339 timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise ReadinessError(f"{field} must be an RFC 3339 timestamp") from error
    if parsed.tzinfo is None:
        raise ReadinessError(f"{field} must include a timezone")
    return parsed


def parse_iso_date(value: Any, field: str) -> date:
    try:
        return date.fromisoformat(value)
    except (TypeError, ValueError) as error:
        raise ReadinessError(f"{field} must be an ISO date") from error


def require_nonempty(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ReadinessError(f"{field} must be a non-empty string")
    return value


def is_exact_string_set(value: Any, expected: set[str]) -> bool:
    return (
        isinstance(value, list)
        and all(isinstance(item, str) for item in value)
        and len(value) == len(set(value))
        and set(value) == expected
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise ReadinessError(f"cannot hash {path}: {error}") from error
    return digest.hexdigest()


def load_bound_documents(
    readiness: dict[str, Any],
    repository_root: Path,
) -> dict[str, dict[str, Any]]:
    bindings = readiness.get("artifact_bindings")
    if not isinstance(bindings, list):
        raise ReadinessError("artifact_bindings must be an array")
    by_role: dict[str, dict[str, Any]] = {}
    for binding in bindings:
        if not isinstance(binding, dict):
            raise ReadinessError("artifact binding must be an object")
        role = binding.get("role")
        if not isinstance(role, str):
            raise ReadinessError("artifact binding role must be a string")
        if role in by_role:
            raise ReadinessError(f"duplicate artifact binding role {role!r}")
        if role not in EXPECTED_BINDING_PATHS:
            raise ReadinessError(f"unknown artifact binding role {role!r}")
        expected_path = EXPECTED_BINDING_PATHS[role]
        if binding.get("repository_path") != expected_path:
            raise ReadinessError(f"artifact binding path drifted for {role}")
        expected_digest = binding.get("content_sha256")
        if (
            not isinstance(expected_digest, str)
            or SHA256_PATTERN.fullmatch(expected_digest) is None
        ):
            raise ReadinessError(f"artifact binding digest is invalid for {role}")
        path = (repository_root / expected_path).resolve()
        try:
            path.relative_to(repository_root)
        except ValueError as error:
            raise ReadinessError(
                f"artifact binding escapes repository root for {role}"
            ) from error
        actual_digest = sha256(path)
        if actual_digest != expected_digest:
            raise ReadinessError(
                f"artifact binding digest drifted for {role}: "
                f"expected {expected_digest}, got {actual_digest}"
            )
        by_role[role] = load_object(path)
    if set(by_role) != set(EXPECTED_BINDING_PATHS):
        missing = sorted(set(EXPECTED_BINDING_PATHS) - set(by_role))
        raise ReadinessError(
            "artifact binding coverage is incomplete: " + ", ".join(missing)
        )
    return by_role


def validate_candidate(candidate: dict[str, Any]) -> tuple[str, str]:
    snapshot = candidate.get("network_snapshot")
    route_plan = candidate.get("route_plan")
    topology = candidate.get("topology_slice")
    definition = candidate.get("definition")
    source_registry = candidate.get("source_registry")
    if not all(
        isinstance(value, dict)
        for value in (
            snapshot,
            route_plan,
            topology,
            definition,
            source_registry,
        )
    ):
        raise ReadinessError("Route Atlas candidate sections are incomplete")
    if (
        candidate.get("schema_version") != "1.0"
        or snapshot.get("id") != EXPECTED_TARGET["network_snapshot_id"]
        or snapshot.get("status") != "ACTIVE"
        or route_plan.get("plan_id") != EXPECTED_TARGET["route_plan_id"]
        or route_plan.get("network_snapshot_id") != snapshot.get("id")
        or route_plan.get("exit_facility_id") != EXPECTED_TARGET["exit_facility_id"]
        or topology.get("topology_slice_id") != EXPECTED_TARGET["topology_slice_id"]
        or topology.get("network_snapshot_id") != snapshot.get("id")
        or definition.get("atlas_id") != EXPECTED_TARGET["atlas_id"]
        or definition.get("network_snapshot_id") != snapshot.get("id")
        or definition.get("route_plan_id") != route_plan.get("plan_id")
        or definition.get("topology_slice_id") != topology.get("topology_slice_id")
    ):
        raise ReadinessError("Route Atlas candidate identity has drifted")
    occurrences = route_plan.get("occurrences")
    topology_edges = topology.get("edges")
    segments = definition.get("segments")
    bindings = definition.get("occurrence_bindings")
    if (
        not isinstance(occurrences, list)
        or len(occurrences) != EXPECTED_TARGET["route_occurrence_count"]
        or not isinstance(topology_edges, list)
        or len(topology_edges) != EXPECTED_TARGET["topology_edge_count"]
        or not isinstance(segments, list)
        or len(segments) != EXPECTED_TARGET["layout_segment_count"]
        or not isinstance(bindings, list)
        or len(bindings) != len(occurrences)
        or not all(isinstance(item, dict) for item in occurrences)
        or not all(isinstance(item, dict) for item in bindings)
    ):
        raise ReadinessError("Route Atlas candidate coverage has drifted")
    occurrence_ids = [item.get("occurrence_id") for item in occurrences]
    if (
        [item.get("index") for item in occurrences] != list(range(len(occurrences)))
        or [item.get("occurrence_id") for item in bindings] != occurrence_ids
        or [item.get("occurrence_index") for item in bindings]
        != list(range(len(bindings)))
    ):
        raise ReadinessError("Route Atlas candidate occurrence order has drifted")
    topology_evidence = topology.get("evidence")
    layout_evidence = definition.get("evidence")
    if (
        not isinstance(topology_evidence, dict)
        or topology_evidence.get("state") not in ALLOWED_EVIDENCE_STATES
        or not isinstance(layout_evidence, dict)
        or layout_evidence.get("state") not in ALLOWED_EVIDENCE_STATES
    ):
        raise ReadinessError("Route Atlas evidence state is invalid")
    references = source_registry.get("references")
    if not isinstance(references, list):
        raise ReadinessError("Route Atlas source registry is invalid")
    osm_sources = [
        source
        for source in references
        if isinstance(source, dict)
        and source.get("source_reference_id") == EXPECTED_OSM_SOURCE_ID
    ]
    if len(osm_sources) != 1:
        raise ReadinessError("Route Atlas OSM source binding has drifted")
    osm_source = osm_sources[0]
    if (
        osm_source.get("licence_identifier") != "ODbL-1.0"
        or osm_source.get("licence_url") != EXPECTED_ODBL_LICENCE_URL
        or osm_source.get("attribution") != EXPECTED_OSM_ATTRIBUTION
        or osm_source.get("attribution_url") != EXPECTED_OSM_ATTRIBUTION_URL
        or not is_exact_string_set(
            osm_source.get("roles"),
            {"TOPOLOGY_EVIDENCE", "LAYOUT_EVIDENCE"},
        )
    ):
        raise ReadinessError("Route Atlas ODbL source contract has drifted")
    terminal_segments = [
        segment
        for segment in segments
        if isinstance(segment, dict)
        and segment.get("topology_edge_id")
        == "shutoko.topology-edge.osm-way.734299106.forward"
    ]
    if (
        len(terminal_segments) != 1
        or terminal_segments[0].get("to_node_id") != "osm.node.7473451738"
        or terminal_segments[0].get("successor_segment_ids") != []
    ):
        raise ReadinessError("Route Atlas candidate surface boundary has drifted")
    return topology_evidence["state"], layout_evidence["state"]


def validate_directed_review(review: dict[str, Any]) -> str:
    if (
        review.get("schema_version") != "1.0"
        or review.get("network_snapshot_id") != EXPECTED_TARGET["network_snapshot_id"]
        or review.get("route_plan_id") != EXPECTED_TARGET["route_plan_id"]
        or review.get("navigation_authority") is not False
    ):
        raise ReadinessError("directed source review identity has drifted")
    successor_audit = review.get("successor_audit")
    if (
        not isinstance(successor_audit, dict)
        or successor_audit.get("audit_id") != EXPECTED_AUDIT_ID
        or successor_audit.get("state")
        != "SOURCE_ADJACENCY_COMPLETE_LEGAL_REVIEW_INCOMPLETE"
        or successor_audit.get("navigation_authority") is not False
        or successor_audit.get("unresolved_legal_successors")
        != [EXPECTED_UNRESOLVED_SUCCESSOR]
    ):
        raise ReadinessError("directed legal-successor review has drifted")
    evidence = review.get("legal_successor_evidence")
    unresolved = (
        [
            item
            for item in evidence
            if isinstance(item, dict)
            and item.get("incoming_way_id") == 734299106
            and item.get("via_node_id") == 7473451738
            and item.get("way_id") == 776884422
            and item.get("direction") == "FORWARD"
        ]
        if isinstance(evidence, list)
        else []
    )
    if len(unresolved) != 1:
        raise ReadinessError("target legal-successor evidence has drifted")
    target = unresolved[0]
    if (
        target.get("source_adjacency_exact") is not True
        or target.get("current_physical_status") != "UNCONFIRMED"
        or target.get("current_legal_direction") != "UNCONFIRMED"
        or target.get("permitted_exit_movement") != "UNCONFIRMED"
        or target.get("release_eligible") is not False
    ):
        raise ReadinessError("target legal-successor state has drifted")
    candidate_state = review.get("candidate_state")
    if candidate_state not in ALLOWED_EVIDENCE_STATES:
        raise ReadinessError("directed source review evidence state is invalid")
    return candidate_state


def validate_successor_audit(audit: dict[str, Any]) -> None:
    summary = audit.get("summary")
    checkpoints = audit.get("checkpoints")
    if (
        audit.get("schema_version") != "1.0"
        or audit.get("audit_id") != EXPECTED_AUDIT_ID
        or audit.get("network_snapshot_id") != EXPECTED_TARGET["network_snapshot_id"]
        or audit.get("route_plan_id") != EXPECTED_TARGET["route_plan_id"]
        or audit.get("navigation_authority") is not False
        or audit.get("licence") != "ODbL-1.0"
        or audit.get("licence_url") != EXPECTED_ODBL_LICENCE_URL
        or audit.get("attribution") != EXPECTED_OSM_ATTRIBUTION
        or audit.get("attribution_url") != EXPECTED_OSM_ATTRIBUTION_URL
        or audit.get("unresolved_legal_successors") != [EXPECTED_UNRESOLVED_SUCCESSOR]
        or not isinstance(summary, dict)
        or summary.get("checkpoint_count") != 14
        or summary.get("observed_successor_count") != 19
        or summary.get("source_adjacency_exact") is not True
        or summary.get("legal_review_complete") is not False
        or summary.get("unresolved_legal_successor_count") != 1
        or not isinstance(checkpoints, list)
        or len(checkpoints) != 14
        or not all(
            isinstance(checkpoint, dict)
            and checkpoint.get("source_adjacency_exact") is True
            for checkpoint in checkpoints
        )
    ):
        raise ReadinessError("source successor audit has drifted")


def validate_layout_source(layout: dict[str, Any]) -> str:
    terminal = layout.get("terminal_boundary")
    source = layout.get("source_reference")
    if (
        layout.get("schema_version") != "1.0"
        or layout.get("network_snapshot_id") != EXPECTED_TARGET["network_snapshot_id"]
        or layout.get("route_plan_id") != EXPECTED_TARGET["route_plan_id"]
        or layout.get("topology_slice_id") != EXPECTED_TARGET["topology_slice_id"]
        or layout.get("status") not in ALLOWED_EVIDENCE_STATES
        or layout.get("navigation_authority") is not False
        or not isinstance(source, dict)
        or source.get("licence_identifier") != "Apache-2.0"
        or not isinstance(terminal, dict)
        or terminal.get("topology_node_id") != "osm.node.7473451738"
        or terminal.get("rendered_successor_topology_edge_ids") != []
        or terminal.get("unrendered_surface_successor_osm_way_ids")
        != [734299108, 734299111, 776884422]
    ):
        raise ReadinessError("schematic layout source has drifted")
    return layout["status"]


def evaluate_road_register_review(
    review: dict[str, Any],
    as_of: date,
) -> tuple[bool, list[str]]:
    sources = review.get("source_references")
    method = review.get("review_method")
    findings = review.get("supporting_findings")
    identity = review.get("current_road_identity")
    scope_limits = review.get("scope_limits")
    decision = review.get("decision")
    if not isinstance(sources, list):
        raise ReadinessError("road-register source_references must be an array")
    sources_by_id: dict[str, dict[str, Any]] = {}
    for source in sources:
        if not isinstance(source, dict):
            raise ReadinessError("road-register source reference must be an object")
        source_id = source.get("source_reference_id")
        if not isinstance(source_id, str):
            raise ReadinessError("road-register source_reference_id must be a string")
        if source_id in sources_by_id:
            raise ReadinessError(
                f"duplicate road-register source reference {source_id!r}"
            )
        digest = source.get("content_sha256")
        if not isinstance(digest, str) or SHA256_PATTERN.fullmatch(digest) is None:
            raise ReadinessError(
                f"road-register source digest is invalid for {source_id!r}"
            )
        checked_at = parse_iso_date(
            source.get("checked_at"),
            f"road_register_review.source_references[{source_id}].checked_at",
        )
        if checked_at > as_of:
            raise ReadinessError("road-register source check is dated in the future")
        for field in (
            "published_at",
            "source_last_updated_at",
            "recognized_route_data_current_through",
        ):
            if field not in source:
                continue
            source_date = parse_iso_date(
                source[field],
                f"road_register_review.source_references[{source_id}].{field}",
            )
            if source_date > as_of:
                raise ReadinessError(
                    f"road-register source {field} is dated in the future"
                )
        sources_by_id[source_id] = source
    if sources_by_id != EXPECTED_ROAD_SOURCE_REFERENCES:
        raise ReadinessError("road-register source reference contract has drifted")
    if (
        review.get("schema_version") != "1.1"
        or review.get("review_id") != EXPECTED_ROAD_REVIEW_ID
        or review.get("target") != EXPECTED_ROAD_TARGET
        or review.get("navigation_authority") is not False
        or not isinstance(method, dict)
        or method.get("interactive_register_url") != EXPECTED_REGISTER_URL
        or method.get("recognized_route_map_id") != 66
        or method.get("recognized_route_map_name_ja") != "認定路線図"
        or method.get("rejected_register_maps")
        != [
            {
                "map_id": 67,
                "map_name_ja": "平面図・補正図・別図・補正別図",
                "reason_code": "NOT_RECOGNIZED_ROUTE_MAP",
            }
        ]
        or not is_exact_string_set(
            method.get("available_register_layers"),
            {
                "ROAD_LEDGER_PLAN",
                "ROAD_AREA_BOUNDARY",
                "RECOGNIZED_ROUTE",
            },
        )
        or method.get("online_update_lag_warning_recorded") is not True
        or method.get("online_material_is_legal_proof") is not False
        or method.get("latest_legal_record_requires_office_review") is not True
        or findings != EXPECTED_ROAD_SUPPORTING_FINDINGS
        or not isinstance(identity, dict)
        or not isinstance(scope_limits, dict)
        or set(scope_limits)
        != {
            "current_physical_status",
            "current_legal_direction",
            "permitted_exit_movement",
        }
        or not all(
            value == "OUTSIDE_ROAD_REGISTER_IDENTITY_REVIEW"
            for value in scope_limits.values()
        )
        or not isinstance(decision, dict)
    ):
        raise ReadinessError("road-register review contract has drifted")
    checked_at = parse_iso_date(
        review.get("checked_at"),
        "road_register_review.checked_at",
    )
    if checked_at > as_of:
        raise ReadinessError("road-register review is dated in the future")
    status = method.get("exact_record_review_status")
    identity_status = identity.get("status")
    if status == "PENDING":
        if (
            method.get("exact_record_reference") is not None
            or identity_status != "UNCONFIRMED"
            or decision.get("status") != "BLOCKED"
            or not is_exact_string_set(
                decision.get("blocker_codes"),
                {
                    "CURRENT_ROAD_IDENTITY_UNCONFIRMED",
                    "EXACT_RECOGNIZED_ROUTE_RECORD_NOT_OBTAINED",
                },
            )
        ):
            raise ReadinessError(
                "pending road-register review is internally inconsistent"
            )
        return False, ["CURRENT_ROAD_IDENTITY_UNCONFIRMED"]
    if status == "CONFLICT":
        if identity_status != "CONFLICT" or decision.get("status") != "BLOCKED":
            raise ReadinessError("conflicting road-register review is inconsistent")
        return False, ["CURRENT_ROAD_IDENTITY_CONFLICT"]
    if status != "CONFIRMED":
        raise ReadinessError("road-register exact_record_review_status is invalid")
    if (
        identity_status != "CONFIRMED"
        or decision.get("status") != "READY_FOR_TOPOLOGY_REVIEW"
        or decision.get("blocker_codes") != []
    ):
        raise ReadinessError(
            "confirmed road-register review is internally inconsistent"
        )
    require_nonempty(
        method.get("exact_record_reference"),
        "road_register_review.exact_record_reference",
    )
    for field in (
        "recognized_route_identifier",
        "recognized_route_name_ja",
        "osm_way_mapping_basis",
        "reviewed_by",
    ):
        require_nonempty(
            identity.get(field),
            f"road_register_review.current_road_identity.{field}",
        )
    reviewed_at = parse_timestamp(
        identity.get("reviewed_at"),
        "road_register_review.current_road_identity.reviewed_at",
    )
    valid_through = parse_iso_date(
        identity.get("valid_through"),
        "road_register_review.current_road_identity.valid_through",
    )
    if reviewed_at.date() > as_of:
        raise ReadinessError("road-register review time is in the future")
    if valid_through < as_of:
        return False, ["CURRENT_ROAD_IDENTITY_REVIEW_STALE"]
    return True, []


def canonical_sha256(value: Any) -> str:
    return hashlib.sha256(
        json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
    ).hexdigest()


def validate_release_review_bindings(
    review: dict[str, Any],
    expected: dict[str, dict[str, str]],
    repository_root: Path,
    field: str,
) -> None:
    bindings = review.get("artifact_bindings")
    if not isinstance(bindings, list):
        raise ReadinessError(f"{field}.artifact_bindings must be an array")
    actual: dict[str, dict[str, str]] = {}
    for binding in bindings:
        if not isinstance(binding, dict) or set(binding) != {
            "role",
            "repository_path",
            "content_sha256",
        }:
            raise ReadinessError(f"{field} contains an invalid artifact binding")
        role = binding.get("role")
        if not isinstance(role, str):
            raise ReadinessError(f"{field} binding role must be a string")
        if role in actual:
            raise ReadinessError(f"{field} contains duplicate binding {role!r}")
        path_value = binding.get("repository_path")
        digest = binding.get("content_sha256")
        if (
            not isinstance(path_value, str)
            or not isinstance(digest, str)
            or SHA256_PATTERN.fullmatch(digest) is None
        ):
            raise ReadinessError(f"{field} binding is invalid for {role!r}")
        path = (repository_root / path_value).resolve()
        try:
            path.relative_to(repository_root)
        except ValueError as error:
            raise ReadinessError(f"{field} binding escapes the repository") from error
        if sha256(path) != digest:
            raise ReadinessError(f"{field} binding digest drifted for {role!r}")
        actual[role] = {
            "repository_path": path_value,
            "content_sha256": digest,
        }
    if actual != expected:
        raise ReadinessError(f"{field} artifact binding contract has drifted")


def evaluate_release_review_decision(
    decision: dict[str, Any],
    as_of: date,
    expected_reviewer_role: str,
    field: str,
) -> tuple[bool, str | None]:
    if set(decision) != {
        "status",
        "reviewer_id",
        "reviewer_role",
        "reviewed_at",
        "valid_through",
        "blocker_codes",
    }:
        raise ReadinessError(f"{field} decision keys have drifted")
    reviewer_id = require_nonempty(
        decision.get("reviewer_id"),
        f"{field}.decision.reviewer_id",
    )
    if decision.get("reviewer_role") != expected_reviewer_role:
        raise ReadinessError(f"{field} reviewer role has drifted")
    if decision.get("blocker_codes") != []:
        raise ReadinessError(f"{field} approved decision retains blockers")
    reviewed_at = parse_timestamp(
        decision.get("reviewed_at"),
        f"{field}.decision.reviewed_at",
    )
    valid_through = parse_iso_date(
        decision.get("valid_through"),
        f"{field}.decision.valid_through",
    )
    if reviewed_at.date() > as_of:
        raise ReadinessError(f"{field} review time is in the future")
    if valid_through < reviewed_at.date():
        raise ReadinessError(f"{field} validity precedes review")
    if (valid_through - reviewed_at.date()).days > MAX_RELEASE_REVIEW_VALIDITY_DAYS:
        raise ReadinessError(f"{field} validity window is too long")
    return valid_through >= as_of, reviewer_id


def evaluate_topology_release_review(
    review: dict[str, Any],
    as_of: date,
    repository_root: Path,
    topology_state: str,
    road_identity_complete: bool,
    field_review_complete: bool,
    field_review_manifest_sha256: str,
) -> tuple[bool, str | None, str]:
    decision = review.get("decision")
    checks = review.get("required_checks")
    if (
        set(review) != EXPECTED_TOPOLOGY_REVIEW_KEYS
        or review.get("schema_version") != "1.0"
        or review.get("review_id") != EXPECTED_TOPOLOGY_REVIEW_ID
        or review.get("review_type") != "TOPOLOGY_RELEASE_REVIEW"
        or review.get("target") != EXPECTED_TOPOLOGY_REVIEW_TARGET
        or review.get("navigation_authority") is not False
        or not isinstance(decision, dict)
        or not isinstance(checks, dict)
    ):
        raise ReadinessError("topology release review identity has drifted")
    assessed_at = parse_iso_date(
        review.get("assessed_at"),
        "topology_release_review.assessed_at",
    )
    if assessed_at > as_of:
        raise ReadinessError("topology release review is dated in the future")
    validate_release_review_bindings(
        review,
        EXPECTED_TOPOLOGY_REVIEW_BINDINGS,
        repository_root,
        "topology_release_review",
    )
    status = decision.get("status")
    if status == "PENDING":
        if (
            checks
            != {
                "candidate_structure": "SATISFIED",
                "source_adjacency": "SATISFIED",
                "current_road_identity": "PENDING",
                "current_surface_field_review": "PENDING",
                "exact_legal_successor_review": "PENDING",
            }
            or review.get("private_field_review_manifest_sha256") is not None
            or decision
            != {
                "status": "PENDING",
                "reviewer_id": None,
                "reviewer_role": "UNASSIGNED",
                "reviewed_at": None,
                "valid_through": None,
                "blocker_codes": [
                    "CURRENT_ROAD_IDENTITY_UNCONFIRMED",
                    "CURRENT_SURFACE_FIELD_REVIEW_INCOMPLETE",
                    "INDEPENDENT_TOPOLOGY_REVIEW_INCOMPLETE",
                ],
            }
        ):
            raise ReadinessError("pending topology release review has drifted")
        return False, None, status
    if status != "APPROVED":
        raise ReadinessError("topology release review status is invalid")
    if (
        topology_state != "RELEASED"
        or not road_identity_complete
        or not field_review_complete
        or checks
        != {
            "candidate_structure": "SATISFIED",
            "source_adjacency": "SATISFIED",
            "current_road_identity": "SATISFIED",
            "current_surface_field_review": "SATISFIED",
            "exact_legal_successor_review": "SATISFIED",
        }
        or review.get("private_field_review_manifest_sha256")
        != field_review_manifest_sha256
    ):
        raise ReadinessError("approved topology release prerequisites are incomplete")
    current, reviewer_id = evaluate_release_review_decision(
        decision,
        as_of,
        "INDEPENDENT_TOPOLOGY_REVIEWER",
        "topology_release_review",
    )
    return current, reviewer_id, status


def evaluate_layout_release_review(
    review: dict[str, Any],
    as_of: date,
    repository_root: Path,
    layout_state: str,
    topology_review_complete: bool,
    topology_review_status: str,
    topology_reviewer_id: str | None,
) -> tuple[bool, str | None, str]:
    decision = review.get("decision")
    checks = review.get("required_checks")
    if (
        set(review) != EXPECTED_LAYOUT_REVIEW_KEYS
        or review.get("schema_version") != "1.0"
        or review.get("review_id") != EXPECTED_LAYOUT_REVIEW_ID
        or review.get("review_type") != "LAYOUT_RELEASE_REVIEW"
        or review.get("target") != EXPECTED_LAYOUT_REVIEW_TARGET
        or review.get("navigation_authority") is not False
        or not isinstance(decision, dict)
        or not isinstance(checks, dict)
    ):
        raise ReadinessError("layout release review identity has drifted")
    assessed_at = parse_iso_date(
        review.get("assessed_at"),
        "layout_release_review.assessed_at",
    )
    if assessed_at > as_of:
        raise ReadinessError("layout release review is dated in the future")
    validate_release_review_bindings(
        review,
        EXPECTED_LAYOUT_REVIEW_BINDINGS,
        repository_root,
        "layout_release_review",
    )
    status = decision.get("status")
    if status == "PENDING":
        if checks != {
            "topology_release_review": "PENDING",
            "layout_identity_and_coverage": "SATISFIED",
            "endpoint_and_successor_geometry": "SATISFIED",
            "surface_boundary_exclusion": "SATISFIED",
            "attribution_presentation": "SATISFIED",
            "independent_layout_review": "PENDING",
        } or decision != {
            "status": "PENDING",
            "reviewer_id": None,
            "reviewer_role": "UNASSIGNED",
            "reviewed_at": None,
            "valid_through": None,
            "blocker_codes": [
                "TOPOLOGY_RELEASE_REVIEW_INCOMPLETE",
                "INDEPENDENT_LAYOUT_REVIEW_INCOMPLETE",
            ],
        }:
            raise ReadinessError("pending layout release review has drifted")
        return False, None, status
    if status != "APPROVED":
        raise ReadinessError("layout release review status is invalid")
    if (
        layout_state != "RELEASED"
        or topology_review_status != "APPROVED"
        or checks
        != {
            "topology_release_review": "SATISFIED",
            "layout_identity_and_coverage": "SATISFIED",
            "endpoint_and_successor_geometry": "SATISFIED",
            "surface_boundary_exclusion": "SATISFIED",
            "attribution_presentation": "SATISFIED",
            "independent_layout_review": "SATISFIED",
        }
    ):
        raise ReadinessError("approved layout release prerequisites are incomplete")
    current, reviewer_id = evaluate_release_review_decision(
        decision,
        as_of,
        "INDEPENDENT_LAYOUT_REVIEWER",
        "layout_release_review",
    )
    if reviewer_id == topology_reviewer_id:
        raise ReadinessError("topology and layout reviews require different reviewers")
    return current and topology_review_complete, reviewer_id, status


def validate_distribution_review(
    review: dict[str, Any],
    as_of: date,
    repository_root: Path,
) -> None:
    if (
        review.get("schema_version") != "1.0"
        or review.get("review_id") != EXPECTED_DISTRIBUTION_REVIEW_ID
        or review.get("classification") != "DERIVATIVE_DATABASE"
        or review.get("status") != "TECHNICAL_REVIEW_COMPLETE"
        or review.get("legal_advice") is not False
        or review.get("navigation_authority") is not False
    ):
        raise ReadinessError("ODbL distribution review identity has drifted")
    require_nonempty(
        review.get("reviewed_by"),
        "distribution_review.reviewed_by",
    )
    reviewed_at = parse_timestamp(
        review.get("reviewed_at"),
        "distribution_review.reviewed_at",
    )
    if reviewed_at.date() > as_of:
        raise ReadinessError("distribution review time is in the future")

    licence = review.get("licence")
    if review.get("scope") != {
        "database_id": "osm.geofabrik.kanto-260721.k7-northwest-directed",
        "network_snapshot_id": EXPECTED_TARGET["network_snapshot_id"],
        "route_plan_id": EXPECTED_TARGET["route_plan_id"],
        "source_snapshot_at": "2026-07-21T20:21:50Z",
    }:
        raise ReadinessError("ODbL distribution review scope has drifted")
    if licence != {
        "identifier": "ODbL-1.0",
        "url": EXPECTED_ODBL_LICENCE_URL,
        "attribution": EXPECTED_OSM_ATTRIBUTION,
        "attribution_url": EXPECTED_OSM_ATTRIBUTION_URL,
    }:
        raise ReadinessError("ODbL distribution review licence has drifted")

    bindings = review.get("artifact_bindings")
    if not isinstance(bindings, list):
        raise ReadinessError("distribution review artifact_bindings must be an array")
    bound_paths: dict[str, Path] = {}
    for binding in bindings:
        if not isinstance(binding, dict):
            raise ReadinessError("distribution review binding must be an object")
        role = binding.get("role")
        if not isinstance(role, str):
            raise ReadinessError("distribution review binding role must be a string")
        if role in bound_paths:
            raise ReadinessError(f"duplicate distribution review binding {role!r}")
        if role not in EXPECTED_DISTRIBUTION_BINDING_PATHS:
            raise ReadinessError(f"unknown distribution review binding {role!r}")
        expected_path = EXPECTED_DISTRIBUTION_BINDING_PATHS[role]
        if binding.get("repository_path") != expected_path:
            raise ReadinessError(f"distribution review binding path drifted for {role}")
        expected_digest = binding.get("content_sha256")
        if (
            not isinstance(expected_digest, str)
            or SHA256_PATTERN.fullmatch(expected_digest) is None
        ):
            raise ReadinessError(
                f"distribution review binding digest is invalid for {role}"
            )
        path = (repository_root / expected_path).resolve()
        try:
            path.relative_to(repository_root)
        except ValueError as error:
            raise ReadinessError(
                f"distribution review binding escapes repository root for {role}"
            ) from error
        actual_digest = sha256(path)
        if actual_digest != expected_digest:
            raise ReadinessError(
                f"distribution review binding digest drifted for {role}: "
                f"expected {expected_digest}, got {actual_digest}"
            )
        bound_paths[role] = path
    if set(bound_paths) != set(EXPECTED_DISTRIBUTION_BINDING_PATHS):
        missing = sorted(set(EXPECTED_DISTRIBUTION_BINDING_PATHS) - set(bound_paths))
        raise ReadinessError(
            "distribution review binding coverage is incomplete: " + ", ".join(missing)
        )

    database = load_object(bound_paths["DERIVATIVE_DATABASE"])
    audit = load_object(bound_paths["SOURCE_SUCCESSOR_AUDIT"])
    catalog = load_object(bound_paths["ATTRIBUTION_CATALOG"])
    for name, document in (("database", database), ("successor audit", audit)):
        if (
            document.get("licence") != "ODbL-1.0"
            or document.get("licence_url") != EXPECTED_ODBL_LICENCE_URL
            or document.get("attribution") != EXPECTED_OSM_ATTRIBUTION
            or document.get("attribution_url") != EXPECTED_OSM_ATTRIBUTION_URL
            or document.get("navigation_authority") is not False
        ):
            raise ReadinessError(f"ODbL {name} notice has drifted")

    entries = catalog.get("entries")
    k7_entries = (
        [
            entry
            for entry in entries
            if isinstance(entry, dict) and entry.get("mode_id") == "k7Evidence"
        ]
        if isinstance(entries, list)
        else []
    )
    if (
        catalog.get("schema_version") != "1.0"
        or catalog.get("catalog_id") != "kaido.route-atlas-attribution.2026-07-24"
        or len(k7_entries) != 1
    ):
        raise ReadinessError("in-product attribution catalog has drifted")
    k7 = k7_entries[0]
    if (
        k7.get("resource_name") != "k7-northwest-up-schematic-layout-candidate"
        or k7.get("attribution") != EXPECTED_OSM_ATTRIBUTION
        or k7.get("source_url") != EXPECTED_OSM_ATTRIBUTION_URL
        or k7.get("licence_identifier") != "ODbL-1.0"
        or k7.get("licence_url") != EXPECTED_ODBL_LICENCE_URL
        or k7.get("navigation_authority") is not False
        or k7.get("presentation")
        != {
            "always_visible": True,
            "placement": "ADJACENT_TO_MAP",
            "requires_interaction": False,
            "native_links": True,
            "source_accessibility_identifier": ("route-atlas-attribution-source"),
            "licence_accessibility_identifier": ("route-atlas-attribution-licence"),
        }
    ):
        raise ReadinessError("K7 in-product attribution contract has drifted")

    distribution = review.get("database_distribution")
    expected_database_path = EXPECTED_DISTRIBUTION_BINDING_PATHS["DERIVATIVE_DATABASE"]
    expected_readme_path = EXPECTED_DISTRIBUTION_BINDING_PATHS["DISTRIBUTION_README"]
    if distribution != {
        "public_repository_url": "https://github.com/Awakehsh/kaido-routes",
        "database_repository_path": expected_database_path,
        "database_download_url": (
            "https://raw.githubusercontent.com/Awakehsh/kaido-routes/main/"
            + expected_database_path
        ),
        "entire_derivative_database_distributed": True,
        "machine_readable": True,
        "internet_access_charge": "FREE",
        "reconstruction_instructions_repository_path": expected_readme_path,
        "reconstruction_instructions_url": (
            "https://github.com/Awakehsh/kaido-routes/blob/main/" + expected_readme_path
        ),
        "parent_pbf_url": (
            "https://download.geofabrik.de/asia/japan/" "kanto-260721.osm.pbf"
        ),
        "parent_pbf_sha256": (
            "b13cc6eabacbd5a0362265cc5fd1eaf512d87c241ce3ab9daba4f8263b8d35ac"
        ),
        "bounded_extract_sha256": (
            "36bd95c1987842099dc7b3953c38e623951a1a5eb6c9a38400786c47c6ddc0f3"
        ),
        "additional_restrictions": False,
    }:
        raise ReadinessError("ODbL database access offer has drifted")

    produced_work = review.get("produced_work_attribution")
    if produced_work != {
        "catalog_mode_id": "k7Evidence",
        "placement": "ADJACENT_TO_MAP",
        "always_visible": True,
        "requires_interaction": False,
        "native_links": True,
        "source_accessibility_identifier": ("route-atlas-attribution-source"),
        "licence_accessibility_identifier": ("route-atlas-attribution-licence"),
    }:
        raise ReadinessError("ODbL produced-work attribution has drifted")

    references = review.get("primary_references")
    if not isinstance(references, list):
        raise ReadinessError("distribution review primary references are missing")
    reference_urls: set[str] = set()
    for reference in references:
        if (
            not isinstance(reference, dict)
            or not isinstance(reference.get("url"), str)
            or reference["url"] in reference_urls
            or not isinstance(reference.get("supports"), list)
            or not reference["supports"]
            or not all(
                isinstance(value, str) and value for value in reference["supports"]
            )
        ):
            raise ReadinessError("distribution review primary reference is invalid")
        checked_at = parse_iso_date(
            reference.get("checked_at"),
            "distribution_review.primary_reference.checked_at",
        )
        if checked_at > as_of:
            raise ReadinessError(
                "distribution review primary reference is dated in the future"
            )
        reference_urls.add(reference["url"])
    if reference_urls != EXPECTED_DISTRIBUTION_REFERENCE_URLS:
        raise ReadinessError("distribution review primary references have drifted")

    readme = bound_paths["DISTRIBUTION_README"].read_text(encoding="utf-8")
    project_manifest = bound_paths["APP_PROJECT_MANIFEST"].read_text(encoding="utf-8")
    for notice in (
        EXPECTED_OSM_ATTRIBUTION,
        EXPECTED_OSM_ATTRIBUTION_URL,
        EXPECTED_ODBL_LICENCE_URL,
    ):
        if notice not in readme:
            raise ReadinessError("distribution README notice has drifted")
    if (
        EXPECTED_DISTRIBUTION_BINDING_PATHS["ATTRIBUTION_CATALOG"]
        not in project_manifest
    ):
        raise ReadinessError("app attribution catalog is not bundled")


def evaluate_distribution(
    readiness: dict[str, Any],
    review: dict[str, Any],
    as_of: date,
    repository_root: Path,
) -> tuple[bool, list[str]]:
    distribution = readiness.get("distribution_readiness")
    if distribution != {
        "licence_identifier": "ODbL-1.0",
        "licence_url": EXPECTED_ODBL_LICENCE_URL,
        "required_attribution": EXPECTED_OSM_ATTRIBUTION,
        "attribution_url": EXPECTED_OSM_ATTRIBUTION_URL,
        "review_binding_role": "ODBL_DISTRIBUTION_REVIEW",
        "review_id": EXPECTED_DISTRIBUTION_REVIEW_ID,
        "implementation_status": "TECHNICAL_REVIEW_COMPLETE",
    }:
        raise ReadinessError("ODbL distribution contract has drifted")
    validate_distribution_review(review, as_of, repository_root)
    return True, []


def evaluate(
    readiness: dict[str, Any],
    as_of: date,
    repository_root: Path,
    field_review_override: dict[str, Any] | None = None,
) -> dict[str, Any]:
    repository_root = repository_root.resolve()
    if (
        readiness.get("schema_version") != EXPECTED_SCHEMA_VERSION
        or readiness.get("readiness_id") != EXPECTED_READINESS_ID
        or readiness.get("scope") != EXPECTED_SCOPE
        or readiness.get("target") != EXPECTED_TARGET
    ):
        raise ReadinessError("release-readiness identity has drifted")
    assessed_at = parse_iso_date(
        readiness.get("assessed_at"),
        "assessed_at",
    )
    if assessed_at > as_of:
        raise ReadinessError("release-readiness assessment is in the future")

    documents = load_bound_documents(readiness, repository_root)
    topology_state, layout_state = validate_candidate(
        documents["ROUTE_ATLAS_CANDIDATE"]
    )
    directed_review_state = validate_directed_review(
        documents["DIRECTED_SOURCE_REVIEW"]
    )
    validate_successor_audit(documents["SOURCE_SUCCESSOR_AUDIT"])
    layout_source_state = validate_layout_source(documents["SCHEMATIC_LAYOUT_SOURCE"])
    if directed_review_state != topology_state:
        raise ReadinessError("directed review and topology evidence states disagree")
    if layout_source_state != layout_state:
        raise ReadinessError("layout source and atlas evidence states disagree")
    road_identity_complete, road_blockers = evaluate_road_register_review(
        documents["ROAD_REGISTER_REVIEW"],
        as_of,
    )

    field_review = (
        field_review_override
        if field_review_override is not None
        else documents["FIELD_REVIEW_TEMPLATE"]
    )
    try:
        field_report = evaluate_field_review(field_review, as_of)
    except FieldReviewError as error:
        raise ReadinessError(f"surface field review is invalid: {error}") from error
    if field_report.get("route_release_authority") is not False:
        raise ReadinessError("surface field review cannot grant release authority")
    field_complete = field_report["field_review_complete"]
    field_review_manifest_sha256 = canonical_sha256(field_review)

    (
        topology_review_complete,
        topology_reviewer_id,
        topology_review_status,
    ) = evaluate_topology_release_review(
        documents["TOPOLOGY_RELEASE_REVIEW"],
        as_of,
        repository_root,
        topology_state,
        road_identity_complete,
        field_complete,
        field_review_manifest_sha256,
    )
    (
        layout_review_complete,
        _layout_reviewer_id,
        layout_review_status,
    ) = evaluate_layout_release_review(
        documents["LAYOUT_RELEASE_REVIEW"],
        as_of,
        repository_root,
        layout_state,
        topology_review_complete,
        topology_review_status,
        topology_reviewer_id,
    )

    distribution_complete, distribution_blockers = evaluate_distribution(
        readiness,
        documents["ODBL_DISTRIBUTION_REVIEW"],
        as_of,
        repository_root,
    )
    topology_released = topology_state == "RELEASED" and topology_review_complete
    layout_released = layout_state == "RELEASED" and layout_review_complete

    blockers = list(road_blockers)
    if not field_complete:
        blockers.append("CURRENT_SURFACE_FIELD_REVIEW_INCOMPLETE")
    if not topology_released:
        blockers.append("UNRELEASED_ATLAS_TOPOLOGY_EVIDENCE")
    if not layout_released:
        blockers.append("UNRELEASED_ATLAS_EVIDENCE")
    blockers.extend(distribution_blockers)
    blockers = sorted(set(blockers))

    gate_states = {
        "ARTIFACT_BINDINGS": "SATISFIED",
        "DIRECTED_CANDIDATE_STRUCTURE": "SATISFIED",
        "SOURCE_ADJACENCY": "SATISFIED",
        "CURRENT_ROAD_IDENTITY": ("SATISFIED" if road_identity_complete else "BLOCKED"),
        "CURRENT_SURFACE_FIELD_REVIEW": ("SATISFIED" if field_complete else "BLOCKED"),
        "TOPOLOGY_RELEASE_EVIDENCE": ("SATISFIED" if topology_released else "BLOCKED"),
        "LAYOUT_RELEASE_EVIDENCE": ("SATISFIED" if layout_released else "BLOCKED"),
        "ODBL_DISTRIBUTION": ("SATISFIED" if distribution_complete else "BLOCKED"),
    }
    satisfied_gate_ids = sorted(
        gate_id for gate_id, status in gate_states.items() if status == "SATISFIED"
    )
    blocked_gate_ids = sorted(
        gate_id for gate_id, status in gate_states.items() if status == "BLOCKED"
    )
    candidate_ready = not blockers

    realtime = readiness.get("realtime_context")
    if realtime != {
        "status": "REALTIME_UNCONFIRMED",
        "release_blocking": False,
    }:
        raise ReadinessError("realtime context must remain unconfirmed")

    report = {
        "schema_version": EXPECTED_SCHEMA_VERSION,
        "readiness_id": EXPECTED_READINESS_ID,
        "as_of": as_of.isoformat(),
        "scope": EXPECTED_SCOPE,
        "target": EXPECTED_TARGET,
        "status": ("READY_FOR_RELEASE_VALIDATION" if candidate_ready else "BLOCKED"),
        "candidate_ready_for_release_validation": candidate_ready,
        "navigation_authority": False,
        "gate_states": gate_states,
        "satisfied_gate_ids": satisfied_gate_ids,
        "blocked_gate_ids": blocked_gate_ids,
        "blocker_codes": blockers,
        "field_review_blockers": field_report["blockers"],
        "field_review_input": (
            "PRIVATE_OVERRIDE"
            if field_review_override is not None
            else "TRACKED_TEMPLATE"
        ),
        "field_review_manifest_sha256": field_review_manifest_sha256,
        "topology_release_review_status": topology_review_status,
        "topology_release_review_current": topology_review_complete,
        "layout_release_review_status": layout_review_status,
        "layout_release_review_current": layout_review_complete,
        "distribution_review_id": EXPECTED_DISTRIBUTION_REVIEW_ID,
        "distribution_review_status": "TECHNICAL_REVIEW_COMPLETE",
        "realtime_status": realtime["status"],
        "realtime_release_blocking": False,
    }

    expected = readiness.get("expected_decision")
    if not isinstance(expected, dict):
        raise ReadinessError("expected_decision must be an object")
    derived_expected = {
        "status": report["status"],
        "candidate_ready_for_release_validation": candidate_ready,
        "navigation_authority": False,
        "satisfied_gate_ids": satisfied_gate_ids,
        "blocked_gate_ids": blocked_gate_ids,
        "blocker_codes": blockers,
    }
    if field_review_override is None and expected != derived_expected:
        raise ReadinessError(
            "expected_decision does not match the derived readiness result"
        )
    return report


def write_report(report: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    arguments = parse_arguments()
    try:
        readiness = load_object(arguments.readiness)
        if arguments.field_review is not None:
            validate_review_input_path(arguments.field_review)
            field_review = load_object(arguments.field_review)
        else:
            field_review = None
        report = evaluate(
            readiness,
            arguments.as_of,
            arguments.repository_root,
            field_review,
        )
        if arguments.report is not None:
            write_report(report, arguments.report)
    except (OSError, FieldReviewError, ReadinessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    if report["candidate_ready_for_release_validation"]:
        print(
            "PASS: K7 Route Atlas candidate is ready for the authoritative "
            "release validator; this readiness report grants no navigation "
            "authority"
        )
        return 0
    print(
        "BLOCKED: K7 Route Atlas candidate is not release-ready: "
        + ", ".join(report["blocker_codes"])
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
