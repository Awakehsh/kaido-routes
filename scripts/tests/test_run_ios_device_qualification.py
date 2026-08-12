from __future__ import annotations

import importlib.util
import io
import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
MODULE_PATH = SCRIPTS_DIR / "run_ios_device_qualification.py"
SPEC = importlib.util.spec_from_file_location(
    "run_ios_device_qualification",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
runner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = runner
SPEC.loader.exec_module(runner)

REPOSITORY_ROOT = Path(__file__).parents[2]
DEVICE_ID = "test-physical-device-id"


def physical_device(
    *,
    available: bool = True,
    simulator: bool = False,
    platform: str = runner.EXPECTED_PLATFORM,
    error: object | None = None,
) -> dict:
    return {
        "name": "Private Owner iPhone",
        "identifier": DEVICE_ID,
        "platform": platform,
        "operatingSystemVersion": "26.5 (23F77)",
        "available": available,
        "simulator": simulator,
        "modelName": "iPhone 13 Pro",
        "error": error,
    }


def passed_summary() -> dict:
    return {
        "devicesAndConfigurations": [
            {
                "device": {
                    "deviceId": DEVICE_ID,
                    "deviceName": "Private Owner iPhone",
                    "modelName": "iPhone 13 Pro",
                    "osVersion": "26.5",
                    "platform": "iOS",
                },
                "expectedFailures": 0,
                "failedTests": 0,
                "passedTests": 112,
                "skippedTests": 0,
            }
        ],
        "expectedFailures": 0,
        "failedTests": 0,
        "finishTime": 1784913035.243,
        "passedTests": 112,
        "result": "Passed",
        "skippedTests": 0,
        "startTime": 1784912940.72,
        "totalTestCount": 112,
    }


def passed_tests() -> dict:
    return {
        "testNodes": [
            {
                "children": [
                    {
                        "nodeIdentifier": (
                            "KaidoProductJourneyUITests/"
                            "testWholeShutoForegroundLocationStartsAndStopsThrough"
                            "CoreLocation()"
                        ),
                        "nodeType": "Test Case",
                        "result": "Passed",
                    },
                    {
                        "nodeIdentifier": (
                            "PhysicalAudioQualificationUITests/"
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


def release_summary() -> dict:
    summary = passed_summary()
    summary["passedTests"] = 1
    summary["totalTestCount"] = 1
    summary["devicesAndConfigurations"][0]["passedTests"] = 1
    return summary


def release_tests() -> dict:
    return {
        "testNodes": [
            {
                "children": [
                    {
                        "nodeIdentifier": runner.REQUIRED_RELEASE_SMOKE_TEST,
                        "nodeType": "Test Case",
                        "result": "Passed",
                    }
                ]
            }
        ]
    }


def release_build_settings() -> list[dict]:
    return [
        {
            "target": "KaidoRoutesApp",
            "buildSettings": {
                "CONFIGURATION": "Release",
                "PRODUCT_BUNDLE_IDENTIFIER": "app.kaidoroutes",
                "ENABLE_TESTABILITY": "NO",
            },
        }
    ]


def test_run_evidence(
    counts: dict,
    prefix: str,
) -> runner.TestRunEvidence:
    return runner.TestRunEvidence(
        counts=counts,
        xcresult_sha256=prefix * 64,
        summary_sha256=chr(ord(prefix) + 1) * 64,
        tests_sha256=chr(ord(prefix) + 2) * 64,
        log_sha256=chr(ord(prefix) + 3) * 64,
    )


def release_bundle_evidence() -> runner.ReleaseBundleEvidence:
    return runner.ReleaseBundleEvidence(
        version="1.0.0",
        build="7",
        app_bundle_sha256="k" * 64,
        whole_shuto_sha256="l" * 64,
        privacy_manifest_sha256="m" * 64,
        license_sha256="n" * 64,
        data_licenses_sha256="o" * 64,
        validation_log_sha256="p" * 64,
    )


class RunIOSDeviceQualificationTests(unittest.TestCase):
    def test_exact_online_physical_iphone_is_selected(self) -> None:
        device = runner.select_physical_ios_device(
            [
                physical_device(),
                {
                    **physical_device(),
                    "identifier": "simulator-id",
                    "platform": "com.apple.platform.iphonesimulator",
                    "simulator": True,
                },
            ],
            DEVICE_ID,
        )

        self.assertEqual(device.identifier, DEVICE_ID)
        self.assertEqual(device.model_name, "iPhone 13 Pro")
        self.assertEqual(device.os_version, "26.5 (23F77)")

    def test_simulator_unavailable_and_wrong_platform_fail_closed(self) -> None:
        cases = [
            (
                physical_device(
                    simulator=True,
                    platform="com.apple.platform.iphonesimulator",
                ),
                "not a physical iPhone",
            ),
            (
                physical_device(
                    available=False,
                    error={"description": "offline"},
                ),
                "unavailable",
            ),
            (
                physical_device(platform="com.apple.platform.watchos"),
                "not a physical iPhone",
            ),
            (
                {
                    **physical_device(),
                    "name": "Private Owner iPad",
                    "modelName": "iPad Pro (13-inch)",
                },
                "not an iPhone",
            ),
        ]
        for payload, message in cases:
            with self.subTest(message=message):
                with self.assertRaisesRegex(
                    runner.DeviceQualificationError,
                    message,
                ):
                    runner.select_physical_ios_device([payload], DEVICE_ID)

    def test_full_run_requires_opaque_identity_and_private_output(self) -> None:
        device = runner.select_physical_ios_device(
            [physical_device()],
            DEVICE_ID,
        )
        with self.assertRaisesRegex(
            runner.DeviceQualificationError,
            "must not be the device identifier",
        ):
            runner.validate_full_run_arguments(
                device=device,
                device_configuration_id=DEVICE_ID,
                output=Path("/tmp/new-device-output"),
                development_team=None,
                repository_root=REPOSITORY_ROOT,
            )
        with self.assertRaisesRegex(
            runner.DeviceQualificationError,
            "ignored research",
        ):
            runner.validate_full_run_arguments(
                device=device,
                device_configuration_id="iphone13pro-dashboard-v1",
                output=REPOSITORY_ROOT / "data/device-output",
                development_team=None,
                repository_root=REPOSITORY_ROOT,
            )

        with tempfile.TemporaryDirectory() as directory:
            configuration_id, output = runner.validate_full_run_arguments(
                device=device,
                device_configuration_id="iphone13pro-dashboard-v1",
                output=Path(directory) / "new-output",
                development_team="ABCDE12345",
                repository_root=REPOSITORY_ROOT,
            )
            self.assertEqual(
                configuration_id,
                "iphone13pro-dashboard-v1",
            )
            self.assertEqual(output, (Path(directory) / "new-output").resolve())
            runner.require_ignored_repository_output(
                output,
                REPOSITORY_ROOT,
            )

        runner.require_ignored_repository_output(
            REPOSITORY_ROOT / "research/evidence/future-ios-device-qualification",
            REPOSITORY_ROOT,
        )

    def test_xcresult_and_receipt_are_physical_coordinate_free_evidence(
        self,
    ) -> None:
        device = runner.select_physical_ios_device(
            [physical_device()],
            DEVICE_ID,
        )
        counts = runner.validate_xcresult_summary(
            passed_summary(),
            device,
        )
        release_counts = runner.validate_xcresult_summary(
            release_summary(),
            device,
        )
        receipt = runner.build_receipt(
            source_commit="a" * 40,
            device_configuration_id="iphone13pro-dashboard-v1",
            device=device,
            debug_baseline=test_run_evidence(counts, "b"),
            release_smoke=test_run_evidence(release_counts, "f"),
            release_build_settings_sha256="j" * 64,
            release_bundle=release_bundle_evidence(),
        )
        encoded = json.dumps(receipt, sort_keys=True)

        self.assertEqual(receipt["schema_version"], "1.5")
        self.assertEqual(counts["passed"], 112)
        self.assertEqual(counts["total"], 112)
        self.assertNotIn(DEVICE_ID, encoded)
        self.assertNotIn("Private Owner iPhone", encoded)
        self.assertTrue(receipt["device_scope"]["physical_device"])
        self.assertFalse(receipt["device_scope"]["simulator"])
        self.assertTrue(receipt["authority"]["app_physical_test_baseline"])
        self.assertTrue(
            receipt["authority"]["release_configuration_device_smoke"]
        )
        self.assertTrue(
            receipt["authority"]["foreground_location_start_stop_smoke"]
        )
        self.assertTrue(
            receipt["authority"]["installed_voice_lifecycle_smoke"]
        )
        self.assertTrue(
            receipt["authority"]["physical_audio_route_lifecycle_smoke"]
        )
        self.assertFalse(receipt["authority"]["road_release_authority"])
        self.assertFalse(receipt["authority"]["location_accuracy_qualified"])
        self.assertFalse(receipt["authority"]["acoustic_quality_qualified"])
        self.assertFalse(receipt["authority"]["carplay_qualified"])
        self.assertEqual(
            receipt["debug_baseline"]["evidence"][
                "xcresult_tests_sha256"
            ],
            "d" * 64,
        )
        self.assertEqual(
            receipt["release_smoke"]["bundle_identifier"],
            "app.kaidoroutes",
        )
        self.assertEqual(
            receipt["release_smoke"]["tests"]["total"],
            1,
        )
        self.assertFalse(receipt["release_smoke"]["enable_testability"])
        self.assertEqual(
            receipt["release_smoke"]["evidence"][
                "xcresult_tree_sha256"
            ],
            "f" * 64,
        )
        self.assertEqual(
            receipt["release_smoke"]["evidence"][
                "build_settings_sha256"
            ],
            "j" * 64,
        )
        self.assertEqual(receipt["release_smoke"]["version"], "1.0.0")
        self.assertEqual(receipt["release_smoke"]["build"], "7")
        self.assertEqual(
            receipt["release_smoke"]["evidence"][
                "app_bundle_tree_sha256"
            ],
            "k" * 64,
        )
        self.assertEqual(
            receipt["release_smoke"]["evidence"]["whole_shuto_sha256"],
            "l" * 64,
        )
        self.assertEqual(
            receipt["release_smoke"]["evidence"][
                "privacy_manifest_sha256"
            ],
            "m" * 64,
        )
        self.assertEqual(
            receipt["release_smoke"]["evidence"]["license_sha256"],
            "n" * 64,
        )
        self.assertEqual(
            receipt["release_smoke"]["evidence"][
                "data_licenses_sha256"
            ],
            "o" * 64,
        )
        self.assertEqual(
            receipt["release_smoke"]["evidence"][
                "bundle_validation_log_sha256"
            ],
            "p" * 64,
        )
        self.assertFalse(
            receipt["authority"][
                "app_store_distribution_signature_qualified"
            ]
        )

    def test_required_foreground_location_test_must_pass_exactly_once(
        self,
    ) -> None:
        self.assertEqual(
            runner.validate_required_foreground_location_test(passed_tests()),
            runner.REQUIRED_FOREGROUND_LOCATION_TEST,
        )

        missing = {"testNodes": []}
        with self.assertRaisesRegex(
            runner.DeviceQualificationError,
            "exactly one required foreground-location",
        ):
            runner.validate_required_foreground_location_test(missing)

        failed = passed_tests()
        failed["testNodes"][0]["children"][0]["result"] = "Failed"
        with self.assertRaisesRegex(
            runner.DeviceQualificationError,
            "did not pass",
        ):
            runner.validate_required_foreground_location_test(failed)

        duplicate = passed_tests()
        duplicate["testNodes"].append(passed_tests()["testNodes"][0])
        with self.assertRaisesRegex(
            runner.DeviceQualificationError,
            "exactly one required foreground-location",
        ):
            runner.validate_required_foreground_location_test(duplicate)

    def test_required_physical_audio_test_must_pass_exactly_once(
        self,
    ) -> None:
        self.assertEqual(
            runner.validate_required_physical_audio_test(passed_tests()),
            runner.REQUIRED_PHYSICAL_AUDIO_TEST,
        )

        missing = passed_tests()
        missing["testNodes"][0]["children"].pop()
        with self.assertRaisesRegex(
            runner.DeviceQualificationError,
            "exactly one required physical-audio",
        ):
            runner.validate_required_physical_audio_test(missing)

        failed = passed_tests()
        failed["testNodes"][0]["children"][1]["result"] = "Failed"
        with self.assertRaisesRegex(
            runner.DeviceQualificationError,
            "physical-audio lifecycle test did not pass",
        ):
            runner.validate_required_physical_audio_test(failed)

    def test_release_smoke_requires_exact_test_and_one_pass(self) -> None:
        device = runner.select_physical_ios_device(
            [physical_device()],
            DEVICE_ID,
        )
        counts = runner.validate_xcresult_summary(release_summary(), device)

        runner.validate_release_smoke_counts(counts)
        self.assertEqual(
            runner.validate_required_release_smoke_test(release_tests()),
            runner.REQUIRED_RELEASE_SMOKE_TEST,
        )

        too_many = {**counts, "total": 2, "passed": 2}
        with self.assertRaisesRegex(
            runner.DeviceQualificationError,
            "exactly one passing test",
        ):
            runner.validate_release_smoke_counts(too_many)

        failed = release_tests()
        failed["testNodes"][0]["children"][0]["result"] = "Failed"
        with self.assertRaisesRegex(
            runner.DeviceQualificationError,
            "did not pass",
        ):
            runner.validate_required_release_smoke_test(failed)

    def test_release_settings_are_formal_bundle_and_not_testable(self) -> None:
        self.assertEqual(
            runner.validate_release_build_settings(release_build_settings()),
            {
                "configuration": "Release",
                "bundle_identifier": "app.kaidoroutes",
                "enable_testability": False,
            },
        )

        invalid_cases = [
            ("CONFIGURATION", "Debug", "Release build configuration"),
            (
                "PRODUCT_BUNDLE_IDENTIFIER",
                "app.kaidoroutes.preview",
                "bundle identifier",
            ),
            ("ENABLE_TESTABILITY", "YES", "ENABLE_TESTABILITY=NO"),
        ]
        for key, value, message in invalid_cases:
            with self.subTest(key=key):
                payload = release_build_settings()
                payload[0]["buildSettings"][key] = value
                with self.assertRaisesRegex(
                    runner.DeviceQualificationError,
                    message,
                ):
                    runner.validate_release_build_settings(payload)

    def test_release_bundle_evidence_binds_the_validated_physical_app(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            derived_data = root / "derived"
            app = (
                derived_data
                / "Build/Products/Release-iphoneos/KaidoRoutes.app"
            )
            app.mkdir(parents=True)
            (app / "Info.plist").write_bytes(
                plistlib.dumps(
                    {
                        "CFBundleShortVersionString": "1.0.0",
                        "CFBundleVersion": "7",
                    }
                )
            )
            (app / runner.WHOLE_SHUTO_RESOURCE).write_bytes(b"whole-shuto")
            (app / "PrivacyInfo.xcprivacy").write_bytes(b"privacy")
            (app / "LICENSE").write_bytes(b"license")
            (app / "DATA-LICENSES.md").write_bytes(b"data licence")
            output = root / "private-output"
            output.mkdir()

            def write_validation_log(
                _: Path,
                validated_app: Path,
                log_path: Path,
            ) -> None:
                self.assertEqual(validated_app, app)
                log_path.write_text("validated\n", encoding="utf-8")

            with mock.patch.object(
                runner,
                "run_release_bundle_validator",
                side_effect=write_validation_log,
            ) as validate:
                evidence = runner.collect_release_bundle_evidence(
                    repository_root=REPOSITORY_ROOT,
                    derived_data=derived_data,
                    output=output,
                )

            validate.assert_called_once()
            self.assertEqual(evidence.version, "1.0.0")
            self.assertEqual(evidence.build, "7")
            self.assertEqual(len(evidence.app_bundle_sha256), 64)
            self.assertEqual(
                evidence.whole_shuto_sha256,
                runner.hash_file(app / runner.WHOLE_SHUTO_RESOURCE),
            )
            self.assertEqual(
                evidence.data_licenses_sha256,
                runner.hash_file(app / "DATA-LICENSES.md"),
            )
            self.assertEqual(
                evidence.validation_log_sha256,
                runner.hash_file(
                    output / "release-bundle-validation.private.log"
                ),
            )

    def test_xcresult_rejects_simulator_identity_failure_or_skip(self) -> None:
        device = runner.select_physical_ios_device(
            [physical_device()],
            DEVICE_ID,
        )
        cases: list[tuple[dict, str]] = []

        simulator = passed_summary()
        simulator["devicesAndConfigurations"][0]["device"]["platform"] = "iOS Simulator"
        cases.append((simulator, "identity does not match"))

        wrong_device = passed_summary()
        wrong_device["devicesAndConfigurations"][0]["device"][
            "deviceId"
        ] = "another-device"
        cases.append((wrong_device, "identity does not match"))

        failed = passed_summary()
        failed["result"] = "Failed"
        failed["failedTests"] = 1
        failed["passedTests"] = 111
        failed["devicesAndConfigurations"][0]["failedTests"] = 1
        failed["devicesAndConfigurations"][0]["passedTests"] = 111
        cases.append((failed, "zero-failure"))

        skipped = passed_summary()
        skipped["skippedTests"] = 1
        skipped["passedTests"] = 111
        skipped["devicesAndConfigurations"][0]["skippedTests"] = 1
        skipped["devicesAndConfigurations"][0]["passedTests"] = 111
        cases.append((skipped, "zero-failure"))

        for summary, message in cases:
            with self.subTest(message=message):
                with self.assertRaisesRegex(
                    runner.DeviceQualificationError,
                    message,
                ):
                    runner.validate_xcresult_summary(summary, device)

    def test_xcodebuild_command_keeps_device_and_signing_explicit(self) -> None:
        command = runner.xcodebuild_command(
            repository_root=REPOSITORY_ROOT,
            device_id=DEVICE_ID,
            result_bundle=Path("/tmp/private/KaidoRoutesApp.xcresult"),
            derived_data=Path("/tmp/derived"),
            development_team="ABCDE12345",
            allow_provisioning_updates=True,
        )

        self.assertIn(f"platform=iOS,id={DEVICE_ID}", command)
        self.assertEqual(command[command.index("-configuration") + 1], "Debug")
        self.assertNotIn("-only-testing:", " ".join(command))
        diagnostics_index = command.index("-collect-test-diagnostics")
        self.assertEqual(command[diagnostics_index + 1], "never")
        self.assertIn("-allowProvisioningUpdates", command)
        self.assertIn("DEVELOPMENT_TEAM=ABCDE12345", command)
        self.assertIn("CODE_SIGN_STYLE=Automatic", command)
        self.assertEqual(command[-1], "test")

    def test_release_command_runs_only_smoke_under_release_configuration(
        self,
    ) -> None:
        command = runner.release_smoke_xcodebuild_command(
            repository_root=REPOSITORY_ROOT,
            device_id=DEVICE_ID,
            result_bundle=Path("/tmp/private/ReleaseSmoke.xcresult"),
            derived_data=Path("/tmp/release-derived"),
            development_team="ABCDE12345",
            allow_provisioning_updates=True,
        )

        self.assertEqual(
            command[command.index("-scheme") + 1],
            "KaidoRoutesReleaseSmoke",
        )
        self.assertEqual(command[command.index("-configuration") + 1], "Release")
        self.assertIn(
            f"-only-testing:{runner.RELEASE_SMOKE_ONLY_TESTING}",
            command,
        )
        self.assertIn("CODE_SIGN_IDENTITY=Apple Development", command)
        self.assertNotIn("ENABLE_TESTABILITY=YES", command)
        self.assertEqual(command[-1], "test")

        settings_command = runner.release_build_settings_command(
            repository_root=REPOSITORY_ROOT,
            device_id=DEVICE_ID,
            development_team="ABCDE12345",
            allow_provisioning_updates=True,
        )
        self.assertEqual(
            settings_command[settings_command.index("-configuration") + 1],
            "Release",
        )
        self.assertIn("CODE_SIGN_STYLE=Automatic", settings_command)
        self.assertIn(
            "CODE_SIGN_IDENTITY=Apple Development",
            settings_command,
        )
        self.assertNotIn("ENABLE_TESTABILITY=YES", settings_command)
        self.assertEqual(settings_command[-1], "CODE_SIGN_IDENTITY=Apple Development")

    def test_release_failure_never_writes_combined_receipt(self) -> None:
        debug_evidence = test_run_evidence(
            runner.validate_xcresult_summary(
                passed_summary(),
                runner.select_physical_ios_device(
                    [physical_device()],
                    DEVICE_ID,
                ),
            ),
            "b",
        )
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "qualification"
            arguments = mock.Mock(
                device_id=DEVICE_ID,
                device_configuration_id="iphone13pro-dashboard-v1",
                output=output,
                preflight_only=False,
                development_team="ABCDE12345",
                allow_provisioning_updates=True,
                xcdevice_timeout=10,
                repository_root=REPOSITORY_ROOT,
            )
            stderr = io.StringIO()
            with (
                mock.patch.object(runner, "parse_arguments", return_value=arguments),
                mock.patch.object(
                    runner,
                    "run_json_command",
                    side_effect=[
                        [physical_device()],
                        release_build_settings(),
                    ],
                ),
                mock.patch.object(
                    runner,
                    "clean_source_commit",
                    return_value="a" * 40,
                ),
                mock.patch.object(
                    runner,
                    "require_ignored_repository_output",
                ),
                mock.patch.object(
                    runner,
                    "collect_xcresult_evidence",
                    return_value=(debug_evidence, passed_tests()),
                ),
                mock.patch.object(
                    runner,
                    "run_xcodebuild",
                    side_effect=[
                        None,
                        runner.DeviceQualificationError(
                            "Release smoke failed"
                        ),
                    ],
                ) as run_xcodebuild,
                mock.patch("sys.stderr", stderr),
            ):
                self.assertEqual(runner.main(), 1)

            self.assertEqual(run_xcodebuild.call_count, 2)
            self.assertIn("Release smoke failed", stderr.getvalue())
            self.assertTrue(output.is_dir())
            self.assertFalse((output / "qualification-run.json").exists())

    def test_source_commit_requires_a_clean_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            subprocess.run(
                ["git", "init", "-q"],
                cwd=repository,
                check=True,
            )
            (repository / "tracked.txt").write_text(
                "clean\n",
                encoding="utf-8",
            )
            subprocess.run(
                ["git", "add", "tracked.txt"],
                cwd=repository,
                check=True,
            )
            subprocess.run(
                [
                    "git",
                    "-c",
                    "user.name=Kaido Test",
                    "-c",
                    "user.email=kaido@example.com",
                    "commit",
                    "-q",
                    "-m",
                    "test",
                ],
                cwd=repository,
                check=True,
            )

            commit = runner.clean_source_commit(repository)
            self.assertRegex(commit, r"^[0-9a-f]{40}$")

            (repository / "tracked.txt").write_text(
                "dirty\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                runner.DeviceQualificationError,
                "clean worktree",
            ):
                runner.clean_source_commit(repository)

    def test_device_run_rechecks_the_clean_source_commit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=repository, check=True)
            tracked = repository / "tracked.txt"
            tracked.write_text("first\n", encoding="utf-8")
            subprocess.run(["git", "add", "tracked.txt"], cwd=repository, check=True)
            subprocess.run(
                [
                    "git",
                    "-c",
                    "user.name=Kaido Test",
                    "-c",
                    "user.email=kaido@example.com",
                    "commit",
                    "-q",
                    "-m",
                    "first",
                ],
                cwd=repository,
                check=True,
            )
            first_commit = runner.clean_source_commit(repository)
            runner.require_unchanged_clean_source_commit(
                repository,
                first_commit,
            )

            tracked.write_text("second\n", encoding="utf-8")
            with self.assertRaisesRegex(
                runner.DeviceQualificationError,
                "clean worktree",
            ):
                runner.require_unchanged_clean_source_commit(
                    repository,
                    first_commit,
                )

            subprocess.run(["git", "add", "tracked.txt"], cwd=repository, check=True)
            subprocess.run(
                [
                    "git",
                    "-c",
                    "user.name=Kaido Test",
                    "-c",
                    "user.email=kaido@example.com",
                    "commit",
                    "-q",
                    "-m",
                    "second",
                ],
                cwd=repository,
                check=True,
            )
            with self.assertRaisesRegex(
                runner.DeviceQualificationError,
                "source commit changed",
            ):
                runner.require_unchanged_clean_source_commit(
                    repository,
                    first_commit,
                )

    def test_directory_hash_is_deterministic_and_rejects_symlinks(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "result.xcresult"
            root.mkdir()
            (root / "a").write_bytes(b"alpha")
            nested = root / "nested"
            nested.mkdir()
            (nested / "b").write_bytes(b"beta")

            first = runner.hash_directory(root)
            second = runner.hash_directory(root)

            self.assertEqual(first, second)
            self.assertEqual(len(first), 64)
            (root / "link").symlink_to(root / "a")
            with self.assertRaisesRegex(
                runner.DeviceQualificationError,
                "symlink",
            ):
                runner.hash_directory(root)
            (root / "link").unlink()
            (root / "directory-link").symlink_to(nested, target_is_directory=True)
            with self.assertRaisesRegex(
                runner.DeviceQualificationError,
                "symlink",
            ):
                runner.hash_directory(root)


if __name__ == "__main__":
    unittest.main()
