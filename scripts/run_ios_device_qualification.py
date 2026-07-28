#!/usr/bin/env python3
"""Run the complete App test scheme on one exact physical iPhone."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Any, Sequence


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
EXPECTED_PLATFORM = "com.apple.platform.iphoneos"
EXPECTED_SUMMARY_PLATFORM = "iOS"
EXPECTED_SCHEME = "KaidoRoutesApp"
EXPECTED_BUNDLE_IDENTIFIER = "app.kaidoroutes.preview"
RECEIPT_SCHEMA_VERSION = "1.1"
RECEIPT_CLASSIFICATION = "PRIVATE_COORDINATE_FREE_IOS_DEVICE_TEST"
REQUIRED_FOREGROUND_LOCATION_TEST = (
    "KaidoProductJourneyUITests/"
    "testK7ForegroundLocationStartsAndStopsThroughCoreLocation()"
)
SAFE_IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,80}$")
SAFE_TEAM_PATTERN = re.compile(r"^[A-Z0-9]{5,20}$")


class DeviceQualificationError(RuntimeError):
    """A physical-device preflight, test, or evidence failure."""


@dataclass(frozen=True)
class PhysicalIOSDevice:
    identifier: str
    name: str
    model_name: str
    os_version: str


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--device-id",
        required=True,
        help="exact xcdevice identifier; retained only in private raw evidence",
    )
    parser.add_argument(
        "--device-configuration-id",
        help=(
            "opaque non-device identifier for this model/OS/mount configuration; "
            "required for a full run"
        ),
    )
    parser.add_argument(
        "--output",
        type=Path,
        help=(
            "new private evidence directory; in-repository output must be under "
            "ignored research/"
        ),
    )
    parser.add_argument(
        "--preflight-only",
        action="store_true",
        help="verify that the exact destination is an online physical iPhone",
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


def run_json_command(command: Sequence[str], field: str) -> Any:
    try:
        completed = subprocess.run(
            list(command),
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as error:
        raise DeviceQualificationError(f"cannot execute {field}: {error}") from error
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise DeviceQualificationError(
            f"{field} failed" + (f": {detail}" if detail else "")
        )
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise DeviceQualificationError(f"{field} did not return JSON") from error


def select_physical_ios_device(
    payload: Any,
    device_id: str,
) -> PhysicalIOSDevice:
    if not isinstance(payload, list):
        raise DeviceQualificationError("xcdevice inventory must be a JSON array")
    matches = [
        item
        for item in payload
        if isinstance(item, dict) and item.get("identifier") == device_id
    ]
    if len(matches) != 1:
        raise DeviceQualificationError(
            "the exact requested device is not present exactly once"
        )
    item = matches[0]
    if item.get("platform") != EXPECTED_PLATFORM or item.get("simulator") is not False:
        raise DeviceQualificationError(
            "the exact requested destination is not a physical iPhone"
        )
    if item.get("available") is not True or item.get("error") is not None:
        raise DeviceQualificationError(
            "the exact requested physical iPhone is unavailable"
        )
    name = normalized_text(item.get("name"))
    model_name = normalized_text(item.get("modelName"))
    os_version = normalized_text(item.get("operatingSystemVersion"))
    if not name or not model_name or not os_version:
        raise DeviceQualificationError(
            "physical iPhone inventory metadata is incomplete"
        )
    return PhysicalIOSDevice(
        identifier=device_id,
        name=name,
        model_name=model_name,
        os_version=os_version,
    )


def validate_full_run_arguments(
    device: PhysicalIOSDevice,
    device_configuration_id: str | None,
    output: Path | None,
    development_team: str | None,
    repository_root: Path,
) -> tuple[str, Path]:
    configuration_id = normalized_text(device_configuration_id)
    if (
        not configuration_id
        or SAFE_IDENTIFIER_PATTERN.fullmatch(configuration_id) is None
        or configuration_id in {device.identifier, device.name}
    ):
        raise DeviceQualificationError(
            "device configuration ID must be opaque and must not be the device "
            "identifier or name"
        )
    if output is None:
        raise DeviceQualificationError("a new private output directory is required")
    destination = output.resolve()
    validate_private_output_path(destination, repository_root.resolve())
    if destination.exists():
        raise DeviceQualificationError(
            "private device qualification output already exists"
        )
    if development_team is not None and (
        SAFE_TEAM_PATTERN.fullmatch(development_team) is None
    ):
        raise DeviceQualificationError("development team identifier is invalid")
    return configuration_id, destination


def validate_private_output_path(path: Path, repository_root: Path) -> None:
    try:
        relative = path.relative_to(repository_root)
    except ValueError:
        return
    if not relative.parts or relative.parts[0] != "research":
        raise DeviceQualificationError(
            "device qualification output inside the repository must stay under "
            "ignored research/"
        )


def require_ignored_repository_output(
    path: Path,
    repository_root: Path,
) -> None:
    try:
        path.relative_to(repository_root)
    except ValueError:
        return
    try:
        completed = subprocess.run(
            ["git", "check-ignore", "-q", str(path)],
            cwd=repository_root,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
    except OSError as error:
        raise DeviceQualificationError(
            f"cannot verify private output ignore rule: {error}"
        ) from error
    if completed.returncode != 0:
        raise DeviceQualificationError(
            "in-repository device qualification output is not ignored"
        )


def clean_source_commit(repository_root: Path) -> str:
    try:
        status = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=repository_root,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        ).stdout
        commit = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=repository_root,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise DeviceQualificationError(
            f"cannot resolve source checkout: {error}"
        ) from error
    if status:
        raise DeviceQualificationError(
            "physical-device qualification requires a clean worktree"
        )
    if re.fullmatch(r"[0-9a-f]{40}", commit) is None:
        raise DeviceQualificationError("source commit identity is invalid")
    return commit


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
            f"cannot execute physical-device xcodebuild: {error}"
        ) from error
    if completed.returncode != 0:
        raise DeviceQualificationError(
            "physical-device App tests failed; private log and result bundle "
            "were retained"
        )


def validate_xcresult_summary(
    summary: Any,
    device: PhysicalIOSDevice,
) -> dict[str, Any]:
    if not isinstance(summary, dict):
        raise DeviceQualificationError("xcresult summary must be an object")
    devices = summary.get("devicesAndConfigurations")
    if not isinstance(devices, list) or len(devices) != 1:
        raise DeviceQualificationError(
            "xcresult must contain exactly one device configuration"
        )
    configuration = devices[0]
    if not isinstance(configuration, dict):
        raise DeviceQualificationError("xcresult device configuration is invalid")
    summary_device = configuration.get("device")
    if not isinstance(summary_device, dict):
        raise DeviceQualificationError("xcresult device metadata is missing")
    if (
        summary_device.get("deviceId") != device.identifier
        or summary_device.get("platform") != EXPECTED_SUMMARY_PLATFORM
        or normalized_text(summary_device.get("modelName")) != device.model_name
        or normalized_text(summary_device.get("osVersion"))
        != inventory_os_version(device.os_version)
    ):
        raise DeviceQualificationError(
            "xcresult physical-device identity does not match preflight"
        )

    integer_fields = [
        "totalTestCount",
        "passedTests",
        "failedTests",
        "skippedTests",
        "expectedFailures",
    ]
    counts: dict[str, int] = {}
    for field in integer_fields:
        value = summary.get(field)
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            raise DeviceQualificationError(
                f"xcresult {field} must be a non-negative integer"
            )
        counts[field] = value
    if (
        summary.get("result") != "Passed"
        or counts["totalTestCount"] <= 0
        or counts["passedTests"] != counts["totalTestCount"]
        or counts["failedTests"] != 0
        or counts["skippedTests"] != 0
        or counts["expectedFailures"] != 0
        or configuration.get("failedTests") != 0
        or configuration.get("skippedTests") != 0
        or configuration.get("expectedFailures") != 0
        or configuration.get("passedTests") != counts["passedTests"]
    ):
        raise DeviceQualificationError(
            "xcresult is not a complete zero-failure, zero-skip pass"
        )
    start_time = parse_epoch(summary.get("startTime"), "startTime")
    finish_time = parse_epoch(summary.get("finishTime"), "finishTime")
    if finish_time < start_time:
        raise DeviceQualificationError("xcresult finish time precedes start time")
    return {
        "total": counts["totalTestCount"],
        "passed": counts["passedTests"],
        "failed": counts["failedTests"],
        "skipped": counts["skippedTests"],
        "expected_failures": counts["expectedFailures"],
        "started_at": iso8601(start_time),
        "finished_at": iso8601(finish_time),
    }


def validate_required_foreground_location_test(payload: Any) -> str:
    matches: list[dict[str, Any]] = []

    def visit(value: Any) -> None:
        if isinstance(value, dict):
            if value.get("nodeIdentifier") == REQUIRED_FOREGROUND_LOCATION_TEST:
                matches.append(value)
            for nested in value.values():
                visit(nested)
        elif isinstance(value, list):
            for nested in value:
                visit(nested)

    visit(payload)
    if len(matches) != 1:
        raise DeviceQualificationError(
            "xcresult must contain exactly one required foreground-location "
            "lifecycle test"
        )
    if matches[0].get("result") != "Passed":
        raise DeviceQualificationError(
            "required foreground-location lifecycle test did not pass"
        )
    return REQUIRED_FOREGROUND_LOCATION_TEST


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
            "bundle_identifier": EXPECTED_BUNDLE_IDENTIFIER,
            "worktree_clean": True,
        },
        "device_scope": {
            "device_configuration_id": device_configuration_id,
            "model_name": device.model_name,
            "os_version": inventory_os_version(device.os_version),
            "platform": EXPECTED_SUMMARY_PLATFORM,
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
            "app_physical_test_baseline": True,
            "foreground_location_start_stop_smoke": True,
            "road_release_authority": False,
            "location_accuracy_qualified": False,
            "acoustic_quality_qualified": False,
            "pronunciation_qualified": False,
            "carplay_qualified": False,
            "background_navigation_qualified": False,
        },
    }


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            while chunk := source.read(1024 * 1024):
                digest.update(chunk)
    except OSError as error:
        raise DeviceQualificationError(
            f"cannot hash private evidence: {error}"
        ) from error
    return digest.hexdigest()


def hash_directory(path: Path) -> str:
    if not path.is_dir():
        raise DeviceQualificationError("xcresult bundle is missing")
    digest = hashlib.sha256()
    entries = sorted(path.rglob("*"))
    if any(item.is_symlink() for item in entries):
        raise DeviceQualificationError("xcresult bundle contains a symlink")
    files = [item for item in entries if item.is_file()]
    if not files:
        raise DeviceQualificationError("xcresult bundle contains no files")
    for item in files:
        relative = item.relative_to(path).as_posix().encode("utf-8")
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        try:
            size = item.stat().st_size
        except OSError as error:
            raise DeviceQualificationError(
                f"cannot inspect xcresult evidence: {error}"
            ) from error
        digest.update(size.to_bytes(8, "big"))
        try:
            with item.open("rb") as source:
                while chunk := source.read(1024 * 1024):
                    digest.update(chunk)
        except OSError as error:
            raise DeviceQualificationError(
                f"cannot hash xcresult evidence: {error}"
            ) from error
    return digest.hexdigest()


def encoded_json(value: Any) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8")


def normalized_text(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def inventory_os_version(value: str) -> str:
    return value.split(" (", maxsplit=1)[0]


def parse_epoch(value: Any, field: str) -> datetime:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise DeviceQualificationError(f"xcresult {field} is invalid")
    try:
        return datetime.fromtimestamp(float(value), tz=timezone.utc)
    except (OverflowError, OSError, ValueError) as error:
        raise DeviceQualificationError(f"xcresult {field} is invalid") from error


def iso8601(value: datetime) -> str:
    return value.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def write_bytes(path: Path, data: bytes) -> None:
    try:
        path.write_bytes(data)
    except OSError as error:
        raise DeviceQualificationError(
            f"cannot write private qualification evidence: {error}"
        ) from error


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
        device = select_physical_ios_device(inventory, arguments.device_id)
        if arguments.preflight_only:
            print(
                "PASS: exact destination is an online physical iPhone; "
                f"model {device.model_name}; iOS "
                f"{inventory_os_version(device.os_version)}"
            )
            return 0

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
        with tempfile.TemporaryDirectory(prefix="kaido-device-derived-data.") as temp:
            command = xcodebuild_command(
                repository_root=repository_root,
                device_id=device.identifier,
                result_bundle=result_bundle,
                derived_data=Path(temp) / "DerivedData",
                development_team=arguments.development_team,
                allow_provisioning_updates=arguments.allow_provisioning_updates,
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
        summary_data = encoded_json(summary)
        summary_path = output / "xcresult-summary.private.json"
        write_bytes(summary_path, summary_data)
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
        validate_required_foreground_location_test(tests)
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
        if device.identifier.encode("utf-8") in receipt_data:
            raise DeviceQualificationError(
                "coordinate-free receipt contains a private device identity"
            )
        write_bytes(output / "qualification-run.json", receipt_data)
    except DeviceQualificationError as error:
        print(f"BLOCKED: {error}", file=sys.stderr)
        return 1

    print(
        "PASS: physical iPhone App baseline completed; "
        f"{counts['passed']}/{counts['total']} tests passed; "
        "coordinate-free receipt written inside private evidence output"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
