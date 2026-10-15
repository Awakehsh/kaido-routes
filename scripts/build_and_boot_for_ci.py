#!/usr/bin/env python3
"""Build the App for testing on CI, then boot the test simulator.

A starting `xcodebuild` waits while CoreSimulator boots or reconfigures a
device, and a booting simulator starts dozens of daemons that take every core
of a three-core runner, so a build running beside the boot makes almost no
progress until it ends. The boot therefore starts once the build has
finished. The chosen device's UDID is written to `$GITHUB_OUTPUT` as
`device-id`.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Callable

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
    """Run the build, then `start_boot` once it has succeeded."""
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
        status = build.wait()
    if status != 0:
        return status, None
    try:
        return 0, start_boot()
    # SystemExit from an unavailable simulator included.
    except BaseException as error:
        print(f"[simulator] boot failed: {error}", file=sys.stderr)
        return 1, None


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
