from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).parents[2]
MODULE_PATH = REPOSITORY_ROOT / "scripts" / "build_and_boot_for_ci.py"
SPEC = importlib.util.spec_from_file_location("build_and_boot_for_ci", MODULE_PATH)
assert SPEC and SPEC.loader
ci = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = ci
SPEC.loader.exec_module(ci)

PRO = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
DEVICES = {
    "devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-6": [
            {"udid": "A", "name": "iPhone 17 Pro", "state": "Shutdown",
             "isAvailable": True, "deviceTypeIdentifier": PRO},
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
            {"udid": "B", "name": "iPhone 17 Pro", "state": "Shutdown",
             "isAvailable": True, "deviceTypeIdentifier": PRO},
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-26-10": [
            {"udid": "C", "name": "iPhone 17 Pro", "state": "Shutdown",
             "isAvailable": False, "deviceTypeIdentifier": PRO},
        ],
    }
}


def script(*lines: str) -> list[str]:
    return [sys.executable, "-c", "; ".join(lines)]


class NewestDeviceTests(unittest.TestCase):
    def test_picks_the_newest_available_runtime(self) -> None:
        self.assertEqual(ci.newest_device(DEVICES, PRO, "")["udid"], "B")

    def test_a_runtime_prefix_narrows_the_choice(self) -> None:
        device = ci.newest_device(DEVICES, PRO, "com.apple.CoreSimulator.SimRuntime.iOS-18-")
        self.assertEqual(device["udid"], "A")

    def test_no_match_stops_the_job(self) -> None:
        with self.assertRaises(SystemExit):
            ci.newest_device(DEVICES, "com.apple.CoreSimulator.SimDeviceType.iPhone-SE", "")


class BuildAndBootTests(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.log = Path(directory.name) / "build.log"
        self.boots: list[str] = []

    def boot(self) -> str:
        self.boots.append("boot")
        return "UDID"

    def test_boots_after_the_build_succeeds(self) -> None:
        status, udid = ci.build_and_boot(
            script("print('ComputeTargetDependencyGraph')", "print('** TEST BUILD SUCCEEDED **')"),
            self.log,
            self.boot,
        )
        self.assertEqual((status, udid, self.boots), (0, "UDID", ["boot"]))
        self.assertIn("TEST BUILD SUCCEEDED", self.log.read_text())

    def test_a_failed_build_boots_nothing(self) -> None:
        status, udid = ci.build_and_boot(
            script("print('ComputeTargetDependencyGraph')", "raise SystemExit(65)"),
            self.log,
            self.boot,
        )
        self.assertEqual((status, udid, self.boots), (65, None, []))

    def test_a_failed_boot_fails_a_successful_build(self) -> None:
        def broken_boot() -> str:
            raise SystemExit("simulator unavailable")

        status, udid = ci.build_and_boot(
            script("print('ComputeTargetDependencyGraph')"), self.log, broken_boot
        )
        self.assertEqual((status, udid), (1, None))


if __name__ == "__main__":
    unittest.main()
