#!/usr/bin/env python3
"""Build deterministic K7 Route Atlas final release inputs."""

from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import date
import json
import os
from pathlib import Path
import sys
import tempfile
from typing import Any

import validate_k7_route_atlas_readiness as readiness_validator


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CANDIDATE_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/candidates/"
    "k7-northwest-up-aoba-to-kohoku-schematic-layout-candidate.json"
)
TOPOLOGY_REVIEW_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/candidates/"
    "k7-northwest-up-aoba-to-kohoku-topology-release-review.json"
)
LAYOUT_REVIEW_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/candidates/"
    "k7-northwest-up-aoba-to-kohoku-layout-release-review.json"
)
DEFAULT_DRAFT_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/releases/"
    "k7-northwest-up-aoba-to-kohoku-route-atlas-release-draft.json"
)
DEFAULT_AUTHORING_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/releases/"
    "k7-northwest-up-aoba-to-kohoku-route-atlas-release-authoring.json"
)


class ReleaseInputError(ValueError):
    """Raised when deterministic release inputs cannot be built safely."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--as-of",
        required=True,
        type=date.fromisoformat,
        help="deterministic review assessment date in YYYY-MM-DD form",
    )
    parser.add_argument("--draft", type=Path, default=DEFAULT_DRAFT_PATH)
    parser.add_argument("--config", type=Path, default=DEFAULT_AUTHORING_PATH)
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
        json.dumps(
            value,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n"
    ).encode("utf-8")


def build_inputs(
    candidate: dict[str, Any],
    topology_review: dict[str, Any],
    layout_review: dict[str, Any],
    as_of: date,
    repository_root: Path = REPOSITORY_ROOT,
) -> tuple[dict[str, Any], dict[str, Any]]:
    readiness_validator.validate_candidate(candidate)
    topology_complete, topology_reviewer_id, topology_status = (
        readiness_validator.evaluate_topology_release_review(
            topology_review,
            as_of,
            repository_root.resolve(),
            "RELEASED",
        )
    )
    layout_complete, _layout_reviewer_id, _layout_status = (
        readiness_validator.evaluate_layout_release_review(
            layout_review,
            as_of,
            repository_root.resolve(),
            "RELEASED",
            topology_complete,
            topology_status,
            topology_reviewer_id,
        )
    )
    if not topology_complete or not layout_complete:
        raise ReleaseInputError("Route Atlas release reviews are not current")

    draft = readiness_validator.release_draft_projection(candidate)
    topology_reviewed_at = readiness_validator.release_review_date(
        topology_review,
        "topology_release_review",
    )
    layout_reviewed_at = readiness_validator.release_review_date(
        layout_review,
        "layout_release_review",
    )
    candidate_topology = candidate["topology_slice"]["evidence"]
    candidate_layout = candidate["definition"]["evidence"]
    authoring = {
        "schema_version": "1.0",
        "source_registry": deepcopy(candidate["source_registry"]),
        "topology_evidence": {
            "checked_at": topology_reviewed_at.isoformat(),
            "source_reference_ids": deepcopy(
                candidate_topology["source_reference_ids"]
            ),
            "state": "RELEASED",
        },
        "layout_evidence": {
            "checked_at": layout_reviewed_at.isoformat(),
            "source_reference_ids": deepcopy(candidate_layout["source_reference_ids"]),
            "state": "RELEASED",
        },
    }
    readiness_validator.validate_release_inputs(
        candidate,
        draft,
        authoring,
        topology_review,
        layout_review,
    )
    return draft, authoring


def write_inputs(
    draft_path: Path,
    authoring_path: Path,
    as_of: date,
) -> tuple[Path, Path]:
    draft_destination = draft_path.resolve()
    authoring_destination = authoring_path.resolve()
    if draft_destination == authoring_destination:
        raise ReleaseInputError("draft and config outputs must be different files")
    for destination in (draft_destination, authoring_destination):
        if destination.exists():
            raise ReleaseInputError(f"output already exists: {destination}")

    draft, authoring = build_inputs(
        load_object(CANDIDATE_PATH),
        load_object(TOPOLOGY_REVIEW_PATH),
        load_object(LAYOUT_REVIEW_PATH),
        as_of,
    )
    pending: list[tuple[Path, Path]] = []
    try:
        for destination, content in (
            (draft_destination, encoded_json(draft)),
            (authoring_destination, encoded_json(authoring)),
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
    return draft_destination, authoring_destination


def main() -> int:
    arguments = parse_arguments()
    try:
        draft, authoring = write_inputs(
            arguments.draft,
            arguments.config,
            arguments.as_of,
        )
    except (
        OSError,
        ReleaseInputError,
        readiness_validator.ReadinessError,
    ) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"PASS: wrote deterministic K7 Route Atlas release inputs: {draft}")
    print(f"PASS: wrote deterministic K7 Route Atlas release inputs: {authoring}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
