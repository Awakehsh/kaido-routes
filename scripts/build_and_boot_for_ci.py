#!/usr/bin/env python3
"""Build the App for testing on CI and boot the test simulator alongside it.

A starting `xcodebuild` waits while CoreSimulator boots or reconfigures a
device, even when it builds for a generic simulator, so booting first and
building in parallel only delays the build. The boot therefore starts once
xcodebuild has planned the build and runs alongside compilation. The chosen
device's UDID is written to `$GITHUB_OUTPUT` as `device-id`.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
from pathlib import Path
from typing import Callable

BUILD_PLANNED_MARKER = "ComputeTargetDependencyGraph"
TEST_LOCATION = "35.6586,139.7454"


def newest_device(simctl_devices: dict, device_type: str, runtime_prefix: str) -> dict:
    """Pick the available device of `device_type` on the newest matching runtime."""

    def runtime_version(identifier: str) -> tuple[int, ...]:
        return tuple(int(part) for part in identifier.rsplit(".iOS-", 1)[-1].split("-"))

    candidates = [
        (runtime, device)
        for runtime, devices in simctl_devices["devices"].items()
        if runtime.startswith(runtime_prefix)
        for device in devices
        if device.get("isAvailable") and device.get("deviceTypeIdentifier") == device_type
    ]
    if not candidates:
        raise SystemExit(f"simulator unavailable: {device_type} {runtime_prefix}".rstrip())
    runtime, device = max(candidates, key=lambda candidate: runtime_version(candidate[0]))
    return {**device, "runtime": runtime}


def boot(device_type: str, runtime_prefix: str, content_size: str) -> str:
    listing = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        check=True,
        capture_output=True,
        text=True,
    )
    device = newest_device(json.loads(listing.stdout), device_type, runtime_prefix)
    udid = device["udid"]
    print(f"[simulator] {device['name']} on {device['runtime']} ({device['state']})", flush=True)
    if device["state"] != "Booted":
        subprocess.run(["xcrun", "simctl", "boot", udid], check=True)
    subprocess.run(
        ["xcrun", "simctl", "bootstatus", udid], check=True, stdout=subprocess.DEVNULL
    )
    subprocess.run(["xcrun", "simctl", "location", udid, "set", TEST_LOCATION], check=True)
    subprocess.run(["xcrun", "simctl", "ui", udid, "content_size", content_size], check=True)
    print("[simulator] ready", flush=True)
    return udid


def build_and_boot(
    build_command: list[str],
    build_log: Path,
    start_boot: Callable[[], str],
) -> tuple[int, str | None]:
    """Run the build, starting `start_boot` on a thread once the build is planned."""
    outcome: dict[str, object] = {}

    def run_boot() -> None:
        try:
            outcome["udid"] = start_boot()
        # SystemExit from an unavailable simulator included; reported once
        # the build has finished so its log stays whole.
        except BaseException as error:
            outcome["error"] = error

    boot_thread = threading.Thread(target=run_boot)
    with build_log.open("w", encoding="utf-8") as log, subprocess.Popen(
        build_command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
    ) as build:
        assert build.stdout is not None
        for line in build.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            log.write(line)
            if line.startswith(BUILD_PLANNED_MARKER) and boot_thread.ident is None:
                boot_thread.start()
        status = build.wait()
    if boot_thread.ident is None:
        print(
            f"[simulator] not booted: xcodebuild ended without {BUILD_PLANNED_MARKER}",
            file=sys.stderr,
        )
        return status or 1, None
    boot_thread.join()
    if "error" in outcome:
        print(f"[simulator] boot failed: {outcome['error']}", file=sys.stderr)
        return status or 1, None
    return status, str(outcome["udid"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--test-plan", required=True)
    parser.add_argument("--device-type", required=True)
    parser.add_argument("--runtime-prefix", default="")
    parser.add_argument("--content-size", default="large")
    parser.add_argument("--derived-data", type=Path, required=True)
    parser.add_argument("--build-log", type=Path, required=True)
    args = parser.parse_args()
    command = [
        "xcodebuild",
        "build-for-testing",
        "-project", "KaidoRoutesApp.xcodeproj",
        "-scheme", "KaidoRoutesApp",
        "-testPlan", args.test_plan,
        "-destination", "generic/platform=iOS Simulator",
        "-derivedDataPath", str(args.derived_data),
        "ARCHS=arm64",
        "CODE_SIGNING_ALLOWED=NO",
    ]
    status, udid = build_and_boot(
        command,
        args.build_log,
        lambda: boot(args.device_type, args.runtime_prefix, args.content_size),
    )
    if udid is not None and "GITHUB_OUTPUT" in os.environ:
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            output.write(f"device-id={udid}\n")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
