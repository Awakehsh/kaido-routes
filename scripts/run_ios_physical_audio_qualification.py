#!/usr/bin/env python3
"""Qualify installed voices and the voice-prompt route on one physical iPhone."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Any, Sequence

from run_ios_device_qualification import (
    DeviceQualificationError,
    EXPECTED_BUNDLE_IDENTIFIER,
    EXPECTED_SCHEME,
    PhysicalIOSDevice,
    clean_source_commit,
    encoded_json,
    hash_directory,
    hash_file,
    require_ignored_repository_output,
    run_json_command,
    select_physical_ios_device,
    validate_full_run_arguments,
    validate_required_test,
    validate_xcresult_summary,
    write_bytes,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
RECEIPT_SCHEMA_VERSION = "1.0"
RECEIPT_CLASSIFICATION = (
    "PRIVATE_COORDINATE_FREE_IOS_PHYSICAL_AUDIO_TEST"
)
REQUIRED_PHYSICAL_AUDIO_TEST = (
    "PhysicalAudioQualificationTests/"
    "testInstalledVoicesCompleteThroughTheVoicePromptOutputRoute()"
)
XCODE_ONLY_TESTING = (
    "KaidoRoutesAppTests/PhysicalAudioQualificationTests/"
    "testInstalledVoicesCompleteThroughTheVoicePromptOutputRoute"
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--device-id",
        required=True,
        help="exact xcdevice identifier; retained only in private raw evidence",
    )
    parser.add_argument(
        "--device-configuration-id",
        required=True,
        help="opaque non-device identifier for this model/OS/audio route",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help=(
            "new private evidence directory; in-repository output must be "
            "under ignored research/"
        ),
    )
    parser.add_argument(
        "--development-team",
        help="optional Apple development team used for automatic device signing",
    )
    parser.add_argument(
        "--allow-provisioning-updates",
        action="store_true",
        help="explicitly permit xcodebuild to update provisioning",
    )
    parser.add_argument(
        "--xcdevice-timeout",
        type=int,
        default=10,
        help="xcdevice discovery timeout in seconds",
    )
    parser.add_argument(
        "--repository-root",
        type=Path,
        default=REPOSITORY_ROOT,
        help=argparse.SUPPRESS,
    )
    return parser.parse_args()


def xcodebuild_command(
    repository_root: Path,
    device_id: str,
    result_bundle: Path,
    derived_data: Path,
    development_team: str | None,
    allow_provisioning_updates: bool,
) -> list[str]:
    command = [
        "xcodebuild",
        "-project",
        str(repository_root / "KaidoRoutesApp.xcodeproj"),
        "-scheme",
        EXPECTED_SCHEME,
        "-destination",
        f"platform=iOS,id={device_id}",
        "-derivedDataPath",
        str(derived_data),
        "-resultBundlePath",
        str(result_bundle),
        "-collect-test-diagnostics",
        "never",
        f"-only-testing:{XCODE_ONLY_TESTING}",
    ]
    if allow_provisioning_updates:
        command.append("-allowProvisioningUpdates")
    if development_team is not None:
        command.extend(
            [
                f"DEVELOPMENT_TEAM={development_team}",
                "CODE_SIGN_STYLE=Automatic",
            ]
        )
    command.append("test")
    return command


def run_xcodebuild(
    command: Sequence[str],
    repository_root: Path,
    log_path: Path,
) -> None:
    try:
        with log_path.open("wb") as log:
            completed = subprocess.run(
                list(command),
                cwd=repository_root,
                check=False,
                stdout=log,
                stderr=subprocess.STDOUT,
            )
    except OSError as error:
        raise DeviceQualificationError(
            f"cannot execute physical-audio xcodebuild: {error}"
        ) from error
    if completed.returncode != 0:
        raise DeviceQualificationError(
            "physical-audio App-hosted test failed; private log and result "
            "bundle were retained"
        )


def build_receipt(
    source_commit: str,
    device_configuration_id: str,
    device: PhysicalIOSDevice,
    counts: dict[str, Any],
    xcresult_sha256: str,
    summary_sha256: str,
    tests_sha256: str,
    log_sha256: str,
) -> dict[str, Any]:
    return {
        "schema_version": RECEIPT_SCHEMA_VERSION,
        "classification": RECEIPT_CLASSIFICATION,
        "source": {
            "commit": source_commit,
            "scheme": EXPECTED_SCHEME,
            "test_target": "KaidoRoutesAppTests",
            "required_test": REQUIRED_PHYSICAL_AUDIO_TEST,
            "bundle_identifier": EXPECTED_BUNDLE_IDENTIFIER,
            "worktree_clean": True,
        },
        "device_scope": {
            "device_configuration_id": device_configuration_id,
            "model_name": device.model_name,
            "os_version": device.os_version.split(" (", maxsplit=1)[0],
            "platform": "iOS",
            "physical_device": True,
            "simulator": False,
        },
        "tests": counts,
        "evidence": {
            "xcresult_tree_sha256": xcresult_sha256,
            "xcresult_summary_sha256": summary_sha256,
            "xcresult_tests_sha256": tests_sha256,
            "xcodebuild_log_sha256": log_sha256,
        },
        "privacy_contract": {
            "device_identifier_embedded": False,
            "device_name_embedded": False,
            "coordinates_embedded": False,
            "raw_location_trace_embedded": False,
            "raw_audio_embedded": False,
            "raw_evidence_storage": "IGNORED_PRIVATE_STORAGE_ONLY",
        },
        "authority": {
            "app_physical_test_baseline": False,
            "foreground_location_start_stop_smoke": False,
            "installed_voice_lifecycle_smoke": True,
            "physical_audio_route_lifecycle_smoke": True,
            "road_release_authority": False,
            "location_accuracy_qualified": False,
            "acoustic_quality_qualified": False,
            "pronunciation_qualified": False,
            "carplay_qualified": False,
            "background_navigation_qualified": False,
        },
    }


def main() -> int:
    arguments = parse_arguments()
    if arguments.xcdevice_timeout <= 0:
        print("ERROR: xcdevice timeout must be positive", file=sys.stderr)
        return 1
    try:
        inventory = run_json_command(
            [
                "xcrun",
                "xcdevice",
                "list",
                "--timeout",
                str(arguments.xcdevice_timeout),
            ],
            "xcdevice discovery",
        )
        device = select_physical_ios_device(
            inventory,
            arguments.device_id,
        )
        repository_root = arguments.repository_root.resolve()
        configuration_id, output = validate_full_run_arguments(
            device=device,
            device_configuration_id=arguments.device_configuration_id,
            output=arguments.output,
            development_team=arguments.development_team,
            repository_root=repository_root,
        )
        require_ignored_repository_output(output, repository_root)
        source_commit = clean_source_commit(repository_root)
        try:
            output.mkdir(parents=True, exist_ok=False)
        except OSError as error:
            raise DeviceQualificationError(
                f"cannot create private qualification output: {error}"
            ) from error

        result_bundle = output / "KaidoRoutesApp.xcresult"
        log_path = output / "xcodebuild.log"
        with tempfile.TemporaryDirectory(
            prefix="kaido-device-audio-derived-data."
        ) as temp:
            command = xcodebuild_command(
                repository_root=repository_root,
                device_id=device.identifier,
                result_bundle=result_bundle,
                derived_data=Path(temp) / "DerivedData",
                development_team=arguments.development_team,
                allow_provisioning_updates=(
                    arguments.allow_provisioning_updates
                ),
            )
            run_xcodebuild(command, repository_root, log_path)

        summary = run_json_command(
            [
                "xcrun",
                "xcresulttool",
                "get",
                "test-results",
                "summary",
                "--path",
                str(result_bundle),
                "--format",
                "json",
            ],
            "xcresult summary",
        )
        counts = validate_xcresult_summary(summary, device)
        if counts["total"] != 1 or counts["passed"] != 1:
            raise DeviceQualificationError(
                "physical-audio result must contain exactly one passing test"
            )
        summary_data = encoded_json(summary)
        write_bytes(output / "xcresult-summary.private.json", summary_data)

        tests = run_json_command(
            [
                "xcrun",
                "xcresulttool",
                "get",
                "test-results",
                "tests",
                "--path",
                str(result_bundle),
                "--format",
                "json",
            ],
            "xcresult tests",
        )
        validate_required_test(
            tests,
            REQUIRED_PHYSICAL_AUDIO_TEST,
            "App-hosted physical-audio lifecycle",
        )
        tests_data = encoded_json(tests)
        write_bytes(output / "xcresult-tests.private.json", tests_data)

        receipt = build_receipt(
            source_commit=source_commit,
            device_configuration_id=configuration_id,
            device=device,
            counts=counts,
            xcresult_sha256=hash_directory(result_bundle),
            summary_sha256=hashlib.sha256(summary_data).hexdigest(),
            tests_sha256=hashlib.sha256(tests_data).hexdigest(),
            log_sha256=hash_file(log_path),
        )
        receipt_data = encoded_json(receipt)
        if (
            device.identifier.encode("utf-8") in receipt_data
            or device.name.encode("utf-8") in receipt_data
        ):
            raise DeviceQualificationError(
                "coordinate-free receipt contains a private device identity"
            )
        write_bytes(output / "qualification-run.json", receipt_data)
    except DeviceQualificationError as error:
        print(f"BLOCKED: {error}", file=sys.stderr)
        return 1

    print(
        "PASS: physical iPhone audio lifecycle completed; 1/1 App-hosted "
        "test passed; coordinate-free receipt written inside private evidence"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
