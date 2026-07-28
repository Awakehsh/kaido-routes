#!/usr/bin/env python3
"""Run the deterministic K7 release-to-iPhone operational E2E."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Any, Sequence

from build_k7_pre_drive_evidence_inputs import (
    EvidenceInputError,
    build_inputs,
    encoded_json,
    load_object,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
REVIEW = (
    REPOSITORY_ROOT
    / "data/product/pre-drive-evidence/"
    "k7-aoba-to-kohoku-source-review-2026-07-27.json"
)
DRAFT = (
    REPOSITORY_ROOT
    / "data/product/pre-drive-evidence/"
    "k7-aoba-to-kohoku-pre-drive-evidence-draft.json"
)
AUTHORING = (
    REPOSITORY_ROOT
    / "data/product/pre-drive-evidence/"
    "k7-aoba-to-kohoku-pre-drive-evidence-authoring.json"
)
EVIDENCE = (
    REPOSITORY_ROOT
    / "data/product/pre-drive-evidence/"
    "k7-aoba-to-kohoku-pre-drive-evidence.json"
)
NAVIGATION_RELEASE = (
    REPOSITORY_ROOT
    / "data/navigation/releases/"
    "k7-northwest-up-aoba-to-kohoku-navigation-release.json"
)
ATLAS_RELEASE = (
    REPOSITORY_ROOT
    / "data/route-atlas/releases/"
    "k7-northwest-up-aoba-to-kohoku-navigation-semantic-route-atlas-release.json"
)
PRODUCT_RELEASE = (
    REPOSITORY_ROOT
    / "data/product/releases/"
    "k7-northwest-up-aoba-to-kohoku-product-release.json"
)
STAGING_CONFIG = (
    REPOSITORY_ROOT
    / "data/product/releases/"
    "k7-northwest-up-aoba-to-kohoku-app-bundle-staging.json"
)
APP_DESCRIPTOR = (
    REPOSITORY_ROOT
    / "Apps/KaidoRoutesApp/Sources/"
    "BundledProductReleaseDescriptor+releasedK7AobaKohoku.swift"
)
PROJECT_SPEC = REPOSITORY_ROOT / "project.yml"
XCODE_PROJECT = REPOSITORY_ROOT / "KaidoRoutesApp.xcodeproj"
SIMULATOR_NAME = "Kaido Routes Preview"


class OperationalE2EError(RuntimeError):
    """Raised when one exact K7 operational boundary fails closed."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--simulator-id",
        help=(
            "exact available iOS Simulator UDID; defaults to the unique "
            f"{SIMULATOR_NAME!r} device"
        ),
    )
    parser.add_argument(
        "--skip-ui",
        action="store_true",
        help="run only deterministic release/staging checks, not the L3 App E2E",
    )
    return parser.parse_args()


def run(
    command: Sequence[str],
    *,
    label: str,
    allow_failure: bool = False,
) -> subprocess.CompletedProcess[bytes]:
    print(f"RUN: {label}", flush=True)
    try:
        completed = subprocess.run(
            list(command),
            cwd=REPOSITORY_ROOT,
            check=False,
        )
    except OSError as error:
        raise OperationalE2EError(f"cannot execute {label}: {error}") from error
    if completed.returncode != 0 and not allow_failure:
        raise OperationalE2EError(
            f"{label} failed with exit code {completed.returncode}"
        )
    return completed


def run_json(command: Sequence[str], *, label: str) -> Any:
    try:
        completed = subprocess.run(
            list(command),
            cwd=REPOSITORY_ROOT,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as error:
        raise OperationalE2EError(f"cannot execute {label}: {error}") from error
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise OperationalE2EError(
            f"{label} failed" + (f": {detail}" if detail else "")
        )
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise OperationalE2EError(f"{label} did not return JSON") from error


def require_exact_bytes(actual: Path, expected: Path, label: str) -> None:
    try:
        actual_bytes = actual.read_bytes()
        expected_bytes = expected.read_bytes()
    except OSError as error:
        raise OperationalE2EError(f"cannot compare {label}: {error}") from error
    if actual_bytes != expected_bytes:
        raise OperationalE2EError(f"{label} drifted from deterministic output")
    digest = hashlib.sha256(actual_bytes).hexdigest()
    print(f"PASS: {label} matched byte-for-byte ({digest})")


def require_nested_release_identity() -> None:
    product = load_object(PRODUCT_RELEASE)
    navigation = load_object(NAVIGATION_RELEASE)
    atlas = load_object(ATLAS_RELEASE)
    if product.get("navigation_release") != navigation:
        raise OperationalE2EError(
            "product navigation release drifted from the tracked release"
        )
    if product.get("route_atlas_release") != atlas:
        raise OperationalE2EError(
            "product Route Atlas release drifted from the tracked release"
        )
    print("PASS: product embeds the exact tracked navigation and Route Atlas releases")


def run_release_and_staging_e2e(temporary_root: Path) -> None:
    draft, authoring = build_inputs(load_object(REVIEW))
    generated_draft = temporary_root / "pre-drive-evidence-draft.json"
    generated_authoring = temporary_root / "pre-drive-evidence-authoring.json"
    generated_draft.write_bytes(encoded_json(draft))
    generated_authoring.write_bytes(encoded_json(authoring))
    require_exact_bytes(generated_draft, DRAFT, "reviewed evidence draft")
    require_exact_bytes(
        generated_authoring,
        AUTHORING,
        "reviewed evidence authoring config",
    )

    generated_evidence = temporary_root / "pre-drive-evidence.json"
    run(
        (
            "swift",
            "run",
            "kaido-release",
            "build-pre-drive-evidence",
            "--product-artifact",
            str(PRODUCT_RELEASE),
            "--draft",
            str(generated_draft),
            "--config",
            str(generated_authoring),
            "--output",
            str(generated_evidence),
        ),
        label="author K7 pre-drive evidence",
    )
    require_exact_bytes(
        generated_evidence,
        EVIDENCE,
        "authored pre-drive evidence",
    )

    run(
        (
            "swift",
            "run",
            "kaido-release",
            "validate-navigation",
            "--artifact",
            str(NAVIGATION_RELEASE),
        ),
        label="validate K7 navigation release",
    )
    run(
        (
            "swift",
            "run",
            "kaido-atlas",
            "validate-release",
            "--artifact",
            str(ATLAS_RELEASE),
        ),
        label="validate K7 Route Atlas release",
    )
    run(
        (
            "swift",
            "run",
            "kaido-release",
            "validate-product",
            "--artifact",
            str(PRODUCT_RELEASE),
        ),
        label="validate joint K7 product release",
    )
    run(
        (
            "swift",
            "run",
            "kaido-release",
            "validate-pre-drive-evidence",
            "--product-artifact",
            str(PRODUCT_RELEASE),
            "--manifest",
            str(generated_evidence),
        ),
        label="validate K7 pre-drive evidence",
    )
    require_nested_release_identity()

    staging = temporary_root / "app-staging"
    run(
        (
            "swift",
            "run",
            "kaido-release",
            "prepare-app-bundle",
            "--product-artifact",
            str(PRODUCT_RELEASE),
            "--config",
            str(STAGING_CONFIG),
            "--pre-drive-evidence-manifest",
            str(generated_evidence),
            "--output",
            str(staging),
        ),
        label="stage the exact K7 App bundle",
    )
    require_exact_bytes(
        staging / "Resources/k7-aoba-kohoku-product-release.json",
        PRODUCT_RELEASE,
        "staged product resource",
    )
    require_exact_bytes(
        staging / "Resources/k7-aoba-to-kohoku-pre-drive-evidence.json",
        EVIDENCE,
        "staged pre-drive evidence resource",
    )
    require_exact_bytes(
        staging
        / "Sources/BundledProductReleaseDescriptor+releasedK7AobaKohoku.swift",
        APP_DESCRIPTOR,
        "App compile-time release descriptor",
    )

    resource_path = (
        "data/product/pre-drive-evidence/"
        "k7-aoba-to-kohoku-pre-drive-evidence.json"
    )
    try:
        project_spec = PROJECT_SPEC.read_text(encoding="utf-8")
        project_file = (
            XCODE_PROJECT / "project.pbxproj"
        ).read_text(encoding="utf-8")
    except OSError as error:
        raise OperationalE2EError(
            f"cannot inspect Xcode resource declarations: {error}"
        ) from error
    if resource_path not in project_spec:
        raise OperationalE2EError("project.yml omits the K7 evidence resource")
    if EVIDENCE.name not in project_file:
        raise OperationalE2EError(
            "generated Xcode project omits the K7 evidence resource"
        )
    print("PASS: XcodeGen source and generated project include the evidence resource")


def resolve_simulator_id(requested_id: str | None) -> str:
    inventory = run_json(
        ("xcrun", "simctl", "list", "devices", "available", "-j"),
        label="read Simulator inventory",
    )
    if not isinstance(inventory, dict) or not isinstance(
        inventory.get("devices"), dict
    ):
        raise OperationalE2EError("Simulator inventory has an invalid shape")
    candidates = [
        item
        for devices in inventory["devices"].values()
        if isinstance(devices, list)
        for item in devices
        if isinstance(item, dict)
        and item.get("isAvailable") is True
        and (
            item.get("udid") == requested_id
            if requested_id is not None
            else item.get("name") == SIMULATOR_NAME
        )
    ]
    if len(candidates) != 1:
        target = requested_id or SIMULATOR_NAME
        raise OperationalE2EError(
            f"expected exactly one available Simulator matching {target!r}"
        )
    identifier = candidates[0].get("udid")
    if not isinstance(identifier, str) or not identifier:
        raise OperationalE2EError("selected Simulator has no UDID")
    return identifier


def run_app_e2e(simulator_id: str, temporary_root: Path) -> None:
    boot = run(
        ("xcrun", "simctl", "boot", simulator_id),
        label="boot K7 E2E Simulator",
        allow_failure=True,
    )
    if boot.returncode not in (0, 149):
        raise OperationalE2EError(
            f"Simulator boot failed with exit code {boot.returncode}"
        )
    run(
        ("xcrun", "simctl", "bootstatus", simulator_id, "-b"),
        label="wait for K7 E2E Simulator",
    )
    run(
        (
            "xcodebuild",
            "test",
            "-quiet",
            "-project",
            str(XCODE_PROJECT),
            "-scheme",
            "KaidoRoutesApp",
            "-destination",
            f"platform=iOS Simulator,id={simulator_id}",
            "-resultBundlePath",
            str(temporary_root / "K7OperationalE2E.xcresult"),
            "-only-testing:KaidoRoutesAppTests/"
            "BundledProductReleaseCatalogTests/"
            "testHashBoundPreDriveEvidenceLoadsForOneExactForegroundRelease",
            "-only-testing:KaidoRoutesAppTests/"
            "KaidoProductJourneyModelTests/"
            "testBundledK7EvidenceAuthorsReviewsAndStartsReleasedRuntime",
            "-only-testing:KaidoRoutesAppTests/"
            "KaidoProductJourneyModelTests/"
            "testBundledK7InformationExpiresWithoutBlockingNavigation",
            "-only-testing:KaidoRoutesAppTests/"
            "KaidoProductJourneyModelTests/"
            "testCurrentKnownClosureStillBlocksNavigationStart",
            "-only-testing:KaidoRoutesAppUITests/"
            "KaidoProductJourneyUITests/"
            "testK7OperationalEvidenceAuthorsReviewsAndStartsReleasedRuntime",
            "-only-testing:KaidoRoutesAppUITests/"
            "KaidoProductJourneyUITests/"
            "testExpiredK7InformationWarnsWithoutBlockingReleasedRuntime",
            "CODE_SIGNING_ALLOWED=NO",
        ),
        label="run K7 release-to-navigation App E2E",
    )
    print(
        "PASS: K7 App E2E loaded the hash-bound release, resolved ¥400 and "
        "7.1 km, retained realtime-unconfirmed status, proved expiry warns "
        "without blocking, kept known closure blocking, entered the released "
        "runtime, and exposed opt-in foreground location"
    )


def main() -> int:
    arguments = parse_arguments()
    try:
        with tempfile.TemporaryDirectory(prefix="kaido-k7-operational-e2e.") as value:
            temporary_root = Path(value)
            run_release_and_staging_e2e(temporary_root)
            if not arguments.skip_ui:
                run_app_e2e(
                    resolve_simulator_id(arguments.simulator_id),
                    temporary_root,
                )
    except (EvidenceInputError, OSError, OperationalE2EError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("PASS: K7 operational E2E completed without live network access")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
