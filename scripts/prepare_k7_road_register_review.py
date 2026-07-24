#!/usr/bin/env python3
"""Initialize one private K7 exact road-register review safely."""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

from validate_k7_road_register_review import (
    RoadRegisterReviewError,
    TRACKED_TEMPLATE_PATH,
    validate_review_input_path,
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help=(
            "new private manifest path; in-repository output must be under "
            "ignored research/"
        ),
    )
    return parser.parse_args()


def prepare(output: Path) -> str:
    destination = output.resolve()
    if destination == TRACKED_TEMPLATE_PATH:
        raise RoadRegisterReviewError(
            "the tracked road-register review template is immutable"
        )
    validate_review_input_path(destination)
    if destination.exists():
        raise RoadRegisterReviewError(
            "private road-register review manifest already exists"
        )
    try:
        template = TRACKED_TEMPLATE_PATH.read_bytes()
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(template)
    except OSError as error:
        raise RoadRegisterReviewError(
            f"cannot initialize private road-register review manifest: {error}"
        ) from error
    return hashlib.sha256(template).hexdigest()


def main() -> int:
    arguments = parse_arguments()
    try:
        digest = prepare(arguments.output)
    except RoadRegisterReviewError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        "PASS: initialized private coordinate-free road-register review; "
        f"template SHA-256 {digest}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
