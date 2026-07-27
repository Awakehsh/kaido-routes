#!/usr/bin/env python3
"""Prepare a fail-closed private K7 Route Atlas release-review packet."""

from __future__ import annotations

import argparse
from datetime import date
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from typing import Any

import validate_k7_route_atlas_readiness as readiness_validator


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
READINESS_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/candidates/"
    "k7-northwest-up-aoba-to-kohoku-release-readiness.json"
)
CANDIDATE_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/candidates/"
    "k7-northwest-up-aoba-to-kohoku-schematic-layout-candidate.json"
)
TOPOLOGY_REVIEW_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/candidates/"
    "k7-northwest-up-aoba-to-kohoku-topology-release-review.template.json"
)
LAYOUT_REVIEW_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/candidates/"
    "k7-northwest-up-aoba-to-kohoku-layout-release-review.template.json"
)
SCHEMATIC_SVG_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/design/"
    "k7-northwest-up-schematic-layout-candidate.svg"
)

EXPECTED_BLOCKERS = [
    "UNRELEASED_ATLAS_EVIDENCE",
    "UNRELEASED_ATLAS_TOPOLOGY_EVIDENCE",
]
EXPECTED_CANDIDATE_KEYS = {
    "schema_version",
    "network_snapshot",
    "route_plan",
    "topology_slice",
    "definition",
    "source_registry",
}
EXPECTED_PACKET_FILES = {
    "README.md",
    "layout-release-review.json",
    "packet-manifest.json",
    "route-atlas-release-authoring.json",
    "route-atlas-release-draft.json",
    "topology-release-review.json",
}


class ReleasePacketError(ValueError):
    """Raised when a private release-review packet cannot be prepared safely."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--as-of",
        required=True,
        type=date.fromisoformat,
        help="readiness evaluation date in YYYY-MM-DD form",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help=(
            "new packet directory; in-repository output must stay under "
            "ignored research/"
        ),
    )
    return parser.parse_args()


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReleasePacketError(f"cannot read {path.name}: {error}") from error
    if not isinstance(value, dict):
        raise ReleasePacketError(f"{path.name} must contain one JSON object")
    return value


def encoded_json(value: Any) -> bytes:
    return (
        json.dumps(
            value,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n"
    ).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def repository_path(path: Path) -> str:
    return path.resolve().relative_to(REPOSITORY_ROOT).as_posix()


def validate_output_path(output: Path) -> Path:
    destination = output.resolve()
    if destination.exists():
        raise ReleasePacketError("release-review packet output already exists")
    if destination == REPOSITORY_ROOT:
        raise ReleasePacketError("repository root cannot be a packet output")
    try:
        relative = destination.relative_to(REPOSITORY_ROOT)
    except ValueError:
        return destination
    if not relative.parts or relative.parts[0] != "research":
        raise ReleasePacketError(
            "release-review packets inside the repository must stay under "
            "ignored research/"
        )
    return destination


def validate_candidate(candidate: dict[str, Any]) -> None:
    if set(candidate) != EXPECTED_CANDIDATE_KEYS:
        raise ReleasePacketError("Route Atlas candidate keys have drifted")
    topology = candidate.get("topology_slice")
    definition = candidate.get("definition")
    if not isinstance(topology, dict) or not isinstance(definition, dict):
        raise ReleasePacketError("Route Atlas candidate content is incomplete")
    topology_evidence = topology.get("evidence")
    layout_evidence = definition.get("evidence")
    if (
        not isinstance(topology_evidence, dict)
        or topology_evidence.get("state") != "CANDIDATE"
        or not isinstance(layout_evidence, dict)
        or layout_evidence.get("state") != "CANDIDATE"
    ):
        raise ReleasePacketError(
            "packet preparation cannot promote Route Atlas evidence"
        )


def prepare(output: Path, as_of: date) -> dict[str, Any]:
    destination = validate_output_path(output)
    readiness = load_object(READINESS_PATH)
    try:
        report = readiness_validator.evaluate(
            readiness,
            as_of,
            REPOSITORY_ROOT,
        )
    except readiness_validator.ReadinessError as error:
        raise ReleasePacketError(f"K7 readiness package is invalid: {error}") from error
    if (
        report.get("status") != "BLOCKED"
        or report.get("blocker_codes") != EXPECTED_BLOCKERS
        or report.get("navigation_authority") is not False
    ):
        raise ReleasePacketError(
            "K7 readiness no longer has the exact review-only blocker set"
        )

    candidate = load_object(CANDIDATE_PATH)
    validate_candidate(candidate)
    topology = dict(candidate["topology_slice"])
    definition = dict(candidate["definition"])
    topology_evidence = topology.pop("evidence")
    layout_evidence = definition.pop("evidence")
    draft = {
        "schema_version": "1.0",
        "network_snapshot": candidate["network_snapshot"],
        "route_plan": candidate["route_plan"],
        "topology_slice": topology,
        "definition": definition,
    }
    authoring = {
        "schema_version": "1.0",
        "source_registry": candidate["source_registry"],
        "topology_evidence": topology_evidence,
        "layout_evidence": layout_evidence,
    }

    topology_review_bytes = TOPOLOGY_REVIEW_PATH.read_bytes()
    layout_review_bytes = LAYOUT_REVIEW_PATH.read_bytes()
    draft_bytes = encoded_json(draft)
    authoring_bytes = encoded_json(authoring)
    source_bindings = [
        {
            "repository_path": repository_path(path),
            "content_sha256": sha256_bytes(path.read_bytes()),
        }
        for path in (
            CANDIDATE_PATH,
            TOPOLOGY_REVIEW_PATH,
            LAYOUT_REVIEW_PATH,
            SCHEMATIC_SVG_PATH,
        )
    ]
    generated_bindings = [
        {
            "filename": filename,
            "content_sha256": sha256_bytes(content),
        }
        for filename, content in (
            ("route-atlas-release-draft.json", draft_bytes),
            ("route-atlas-release-authoring.json", authoring_bytes),
            ("topology-release-review.json", topology_review_bytes),
            ("layout-release-review.json", layout_review_bytes),
        )
    ]
    manifest = {
        "schema_version": "1.0",
        "packet_id": (
            "shutoko.k7-northwest.aoba-up-to-kohoku-up."
            "exit-handoff-route-atlas-release-review"
        ),
        "as_of": as_of.isoformat(),
        "scope": "EXIT_HANDOFF_ONLY_ROUTE_ATLAS_CANDIDATE",
        "navigation_authority": False,
        "candidate_ready_for_release_validation": False,
        "expected_blocker_codes": EXPECTED_BLOCKERS,
        "source_bindings": source_bindings,
        "generated_bindings": generated_bindings,
    }
    manifest_bytes = encoded_json(manifest)
    readme_bytes = review_instructions(as_of).encode("utf-8")

    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(
        tempfile.mkdtemp(
            prefix=f".{destination.name}.",
            dir=destination.parent,
        )
    )
    try:
        files = {
            "README.md": readme_bytes,
            "layout-release-review.json": layout_review_bytes,
            "packet-manifest.json": manifest_bytes,
            "route-atlas-release-authoring.json": authoring_bytes,
            "route-atlas-release-draft.json": draft_bytes,
            "topology-release-review.json": topology_review_bytes,
        }
        if set(files) != EXPECTED_PACKET_FILES:
            raise ReleasePacketError("release-review packet file set drifted")
        for filename, content in files.items():
            (temporary / filename).write_bytes(content)
        os.replace(temporary, destination)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise
    return manifest


def review_instructions(as_of: date) -> str:
    return f"""# K7 Route Atlas release-review packet

As of: {as_of.isoformat()}

This packet prepares the first real-source K7 scope from the exact Yokohama
Aoba up entrance to the Yokohama Kohoku up exit handoff. It deliberately
excludes all ordinary-road successors and releases no surface-egress leg.

## Authority boundary

The packet grants no navigation or release authority. Both generated evidence
records remain `CANDIDATE`, and both review manifests remain `PENDING`.
`kaido-atlas build-release` must reject this packet until independent review is
complete and the reviewed authoring evidence is explicitly promoted in a
separate release change.

## Review order

1. An independent topology reviewer compares the exact candidate, successor
   audit, official operator material, and the exit-only boundary. Google Maps
   may corroborate the route but cannot replace operator or lawful-road
   evidence.
2. Only after topology approval, a different independent layout reviewer
   verifies one-to-one coverage, endpoint geometry, the terminal boundary,
   attribution, and the absence of rendered surface successors.
3. The maintainer integrates the signed review records, rebinds every changed
   SHA-256, re-runs K7 readiness, and only then creates released authoring
   evidence.

Official references are retained in `route-atlas-release-authoring.json`.
Current corroboration may also use this coordinate-only Google Maps route:

https://www.google.com/maps/dir/?api=1&origin=35.544075%2C139.5406531&destination=35.515365%2C139.5892964&travelmode=driving

The official K7 facility and branch references are:

- https://www.shutoko.jp/use/network/map/route-k7ho/
- https://www.shutoko.jp/use/network/map/route-k7ho/yokohamaaoba/
- https://www.shutoko.jp/use/network/map/route-k7ho/yokohamakohoku/
- https://www.shutoko.jp/use/safety/branch_k7/

## Fail-closed preflight

```sh
swift run kaido-atlas build-release \\
  --draft route-atlas-release-draft.json \\
  --config route-atlas-release-authoring.json \\
  --output route-atlas-release.json
```

The unreviewed packet must fail and must not create the output artifact.
"""


def main() -> int:
    arguments = parse_arguments()
    try:
        manifest = prepare(arguments.output, arguments.as_of)
    except (OSError, ReleasePacketError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        "PASS: prepared fail-closed K7 Route Atlas release-review packet; "
        f"blockers {', '.join(manifest['expected_blocker_codes'])}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
