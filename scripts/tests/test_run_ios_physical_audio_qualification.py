from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import unittest


SCRIPTS_DIR = Path(__file__).parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))
MODULE_PATH = SCRIPTS_DIR / "run_ios_physical_audio_qualification.py"
SPEC = importlib.util.spec_from_file_location(
    "run_ios_physical_audio_qualification",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
runner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = runner
SPEC.loader.exec_module(runner)

REPOSITORY_ROOT = Path(__file__).parents[2]
DEVICE_ID = "private-test-device-id"


def physical_device() -> runner.PhysicalIOSDevice:
    return runner.PhysicalIOSDevice(
        identifier=DEVICE_ID,
        name="Private Owner iPhone",
        model_name="iPhone 13 Pro",
        os_version="26.5.2 (23F84)",
    )


def passed_summary() -> dict:
    return {
        "devicesAndConfigurations": [
            {
                "device": {
                    "deviceId": DEVICE_ID,
                    "deviceName": "Private Owner iPhone",
                    "modelName": "iPhone 13 Pro",
                    "osVersion": "26.5.2",
                    "platform": "iOS",
                },
                "expectedFailures": 0,
                "failedTests": 0,
                "passedTests": 1,
                "skippedTests": 0,
            }
        ],
        "expectedFailures": 0,
        "failedTests": 0,
        "finishTime": 1785226000.0,
        "passedTests": 1,
        "result": "Passed",
        "skippedTests": 0,
        "startTime": 1785225900.0,
        "totalTestCount": 1,
    }


def passed_tests() -> dict:
    return {
        "testNodes": [
            {
                "children": [
                    {
                        "nodeIdentifier": (
                            "PhysicalAudioQualificationTests/"
                            "testInstalledVoicesCompleteThroughTheVoicePrompt"
                            "OutputRoute()"
                        ),
                        "nodeType": "Test Case",
                        "result": "Passed",
                    }
                ]
            }
        ]
    }


class RunIOSPhysicalAudioQualificationTests(unittest.TestCase):
    def test_command_runs_only_the_app_hosted_audio_test(self) -> None:
        command = runner.xcodebuild_command(
            repository_root=REPOSITORY_ROOT,
            device_id=DEVICE_ID,
            result_bundle=Path("/tmp/private/audio.xcresult"),
            derived_data=Path("/tmp/private/DerivedData"),
            development_team="ABCDE12345",
            allow_provisioning_updates=True,
        )

        self.assertIn(
            f"-only-testing:{runner.XCODE_ONLY_TESTING}",
            command,
        )
        self.assertNotIn("KaidoRoutesAppUITests", " ".join(command))
        self.assertIn("-allowProvisioningUpdates", command)
        self.assertIn("DEVELOPMENT_TEAM=ABCDE12345", command)
        self.assertEqual(command[-1], "test")

    def test_receipt_is_coordinate_free_and_grants_audio_only(self) -> None:
        device = physical_device()
        counts = runner.validate_xcresult_summary(
            passed_summary(),
            device,
        )
        receipt = runner.build_receipt(
            source_commit="a" * 40,
            device_configuration_id="iphone13pro-speaker-audio-v1",
            device=device,
            counts=counts,
            xcresult_sha256="b" * 64,
            summary_sha256="c" * 64,
            tests_sha256="d" * 64,
            log_sha256="e" * 64,
        )
        encoded = json.dumps(receipt, sort_keys=True)

        self.assertNotIn(DEVICE_ID, encoded)
        self.assertNotIn(device.name, encoded)
        self.assertEqual(receipt["tests"]["total"], 1)
        self.assertFalse(
            receipt["authority"]["app_physical_test_baseline"]
        )
        self.assertFalse(
            receipt["authority"]["foreground_location_start_stop_smoke"]
        )
        self.assertTrue(
            receipt["authority"]["installed_voice_lifecycle_smoke"]
        )
        self.assertTrue(
            receipt["authority"]["physical_audio_route_lifecycle_smoke"]
        )
        self.assertFalse(
            receipt["authority"]["acoustic_quality_qualified"]
        )
        self.assertFalse(receipt["authority"]["pronunciation_qualified"])

    def test_required_audio_test_must_pass_exactly_once(self) -> None:
        self.assertEqual(
            runner.validate_required_test(
                passed_tests(),
                runner.REQUIRED_PHYSICAL_AUDIO_TEST,
                "App-hosted physical-audio lifecycle",
            ),
            runner.REQUIRED_PHYSICAL_AUDIO_TEST,
        )

        failed = passed_tests()
        failed["testNodes"][0]["children"][0]["result"] = "Failed"
        with self.assertRaisesRegex(
            runner.DeviceQualificationError,
            "did not pass",
        ):
            runner.validate_required_test(
                failed,
                runner.REQUIRED_PHYSICAL_AUDIO_TEST,
                "App-hosted physical-audio lifecycle",
            )


if __name__ == "__main__":
    unittest.main()
