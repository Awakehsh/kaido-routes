from __future__ import annotations

import importlib.util
import json
import plistlib
import shutil
import stat
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).parents[2]
MODULE_PATH = REPOSITORY_ROOT / "scripts" / "validate_ios_release_bundle.py"
SPEC = importlib.util.spec_from_file_location(
    "validate_ios_release_bundle",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = validator
SPEC.loader.exec_module(validator)


def png_chunk(name: bytes, payload: bytes) -> bytes:
    body = name + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))


def write_png(
    path: Path,
    width: int,
    height: int,
    color_type: int = 2,
    cgbi: bool = False,
    opaque_alpha: bool = False,
) -> None:
    channels = 4 if color_type == 6 else 3
    pixel = (
        b"\x20\x20\x20" + (b"\xff" if opaque_alpha else b"\x20")
        if color_type == 6
        else b"\x20" * channels
    )
    row = b"\x00" + (pixel * width)
    compressor = zlib.compressobj(wbits=-15) if cgbi else None
    compressed = (
        compressor.compress(row * height) + compressor.flush()
        if compressor is not None
        else zlib.compress(row * height)
    )
    payload = b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            png_chunk(b"CgBI", b"") if cgbi else b"",
            png_chunk(
                b"IHDR",
                struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0),
            ),
            png_chunk(b"IDAT", compressed),
            png_chunk(b"IEND", b""),
        ]
    )
    path.write_bytes(payload)


def write_arm64_macho(
    path: Path,
    platform: int = validator.MACHO_PLATFORM_IOS,
) -> None:
    segment = struct.pack(
        "<II16sQQQQiiII",
        validator.LC_SEGMENT_64,
        72,
        b"__TEXT" + (b"\x00" * 10),
        0,
        256,
        0,
        256,
        5,
        5,
        0,
        0,
    )
    main = struct.pack("<IIQQ", validator.LC_MAIN, 24, 128, 0)
    build_version = struct.pack(
        "<6I",
        validator.LC_BUILD_VERSION,
        24,
        platform,
        0x00120000,
        0x001A0200,
        0,
    )
    header = struct.pack(
        "<8I",
        0xFEEDFACF,
        validator.ARM64_CPU_TYPE,
        0,
        validator.MACHO_EXECUTE_FILE_TYPE,
        3,
        len(segment) + len(main) + len(build_version),
        0,
        0,
    )
    path.write_bytes(
        header + segment + main + build_version + (b"\x00" * 128)
    )
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class ValidateIOSReleaseBundleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.repository = self.root / "repository"
        self.app = self.root / "KaidoRoutes.app"
        self.repository.mkdir()
        self.app.mkdir()

        source_resources = (
            self.repository / "Apps/KaidoRoutesApp/Resources"
        )
        source_resources.mkdir(parents=True)
        source_icon = (
            source_resources
            / "Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
        )
        source_icon.parent.mkdir(parents=True)
        write_png(source_icon, 1024, 1024)
        privacy = {
            "NSPrivacyTracking": False,
            "NSPrivacyTrackingDomains": [],
            "NSPrivacyCollectedDataTypes": [],
            "NSPrivacyAccessedAPITypes": [
                {
                    "NSPrivacyAccessedAPIType": category,
                    "NSPrivacyAccessedAPITypeReasons": reasons,
                }
                for category, reasons in validator.EXPECTED_PRIVACY_REASONS.items()
            ],
        }
        (source_resources / "PrivacyInfo.xcprivacy").write_bytes(
            plistlib.dumps(privacy)
        )
        (self.app / "PrivacyInfo.xcprivacy").write_bytes(
            plistlib.dumps(privacy)
        )

        data_directory = self.repository / "data/route-atlas/osm-derived"
        data_directory.mkdir(parents=True)
        snapshot = {
            "sources": {
                "osm": {
                    "attribution": validator.EXPECTED_OSM_ATTRIBUTION,
                    "licence": validator.EXPECTED_OSM_LICENSE,
                    "licence_uri": validator.EXPECTED_OSM_LICENSE_URI,
                    "source_uri": "https://example.invalid/source.osm.pbf",
                }
            }
        }
        encoded_snapshot = json.dumps(snapshot).encode("utf-8")
        (data_directory / validator.WHOLE_SHUTO_RESOURCE).write_bytes(
            encoded_snapshot
        )
        (self.app / validator.WHOLE_SHUTO_RESOURCE).write_bytes(
            encoded_snapshot
        )
        product_release = {
            "release_id": validator.C1_PRODUCT_RELEASE_ID,
            "runtime_use": {
                "evidence_scope": "RELEASED_ROAD",
                "live_input_policy": "FOREGROUND_WHEN_IN_USE",
            },
            "navigation_release": {
                "route_plan": {
                    "plan_id": validator.C1_ROUTE_PLAN_ID,
                    "entry_facility_id": validator.C1_ENTRY_FACILITY_ID,
                    "exit_facility_id": validator.C1_EXIT_FACILITY_ID,
                    "occurrences": [
                        {"id": f"fixture.{index}"}
                        for index in range(
                            validator.C1_ROUTE_OCCURRENCE_COUNT
                        )
                    ],
                }
            },
        }
        product_release["route_atlas_release"] = {
            "route_plan": product_release["navigation_release"]["route_plan"]
        }
        encoded_product_release = json.dumps(product_release).encode("utf-8")
        product_source = (
            self.repository / validator.C1_PRODUCT_RELEASE_SOURCE
        )
        product_source.parent.mkdir(parents=True)
        product_source.write_bytes(encoded_product_release)
        (self.app / validator.C1_PRODUCT_RELEASE_RESOURCE).write_bytes(
            encoded_product_release
        )
        wangan_release = json.loads(encoded_product_release)
        wangan_release["release_id"] = validator.WANGAN_PRODUCT_RELEASE_ID
        wangan_route_plan = wangan_release["navigation_release"]["route_plan"]
        wangan_route_plan.update(
            {
                "plan_id": validator.WANGAN_ROUTE_PLAN_ID,
                "entry_facility_id": validator.WANGAN_ENTRY_FACILITY_ID,
                "exit_facility_id": validator.WANGAN_EXIT_FACILITY_ID,
                "occurrences": [
                    {"id": f"wangan.fixture.{index}"}
                    for index in range(
                        validator.WANGAN_ROUTE_OCCURRENCE_COUNT
                    )
                ],
            }
        )
        wangan_release["route_atlas_release"]["route_plan"] = (
            wangan_route_plan
        )
        encoded_wangan_release = json.dumps(wangan_release).encode("utf-8")
        wangan_source = (
            self.repository / validator.WANGAN_PRODUCT_RELEASE_SOURCE
        )
        wangan_source.parent.mkdir(parents=True, exist_ok=True)
        wangan_source.write_bytes(encoded_wangan_release)
        (self.app / validator.WANGAN_PRODUCT_RELEASE_RESOURCE).write_bytes(
            encoded_wangan_release
        )
        c2_release = json.loads(encoded_product_release)
        c2_release["release_id"] = validator.C2_PRODUCT_RELEASE_ID
        c2_route_plan = c2_release["navigation_release"]["route_plan"]
        c2_route_plan.update(
            {
                "plan_id": validator.C2_ROUTE_PLAN_ID,
                "entry_facility_id": validator.C2_ENTRY_FACILITY_ID,
                "exit_facility_id": validator.C2_EXIT_FACILITY_ID,
                "occurrences": [
                    {"id": f"c2.fixture.{index}"}
                    for index in range(validator.C2_ROUTE_OCCURRENCE_COUNT)
                ],
            }
        )
        c2_release["route_atlas_release"]["route_plan"] = c2_route_plan
        encoded_c2_release = json.dumps(c2_release).encode("utf-8")
        c2_source = self.repository / validator.C2_PRODUCT_RELEASE_SOURCE
        c2_source.parent.mkdir(parents=True, exist_ok=True)
        c2_source.write_bytes(encoded_c2_release)
        (self.app / validator.C2_PRODUCT_RELEASE_RESOURCE).write_bytes(
            encoded_c2_release
        )
        daikoku_release = json.loads(encoded_product_release)
        daikoku_release["release_id"] = validator.DAIKOKU_PRODUCT_RELEASE_ID
        daikoku_route_plan = daikoku_release["navigation_release"][
            "route_plan"
        ]
        daikoku_route_plan.update(
            {
                "plan_id": validator.DAIKOKU_ROUTE_PLAN_ID,
                "entry_facility_id": validator.DAIKOKU_ENTRY_FACILITY_ID,
                "exit_facility_id": validator.DAIKOKU_EXIT_FACILITY_ID,
                "occurrences": [
                    {"id": f"daikoku.fixture.{index}"}
                    for index in range(
                        validator.DAIKOKU_ROUTE_OCCURRENCE_COUNT
                    )
                ],
            }
        )
        daikoku_release["route_atlas_release"]["route_plan"] = (
            daikoku_route_plan
        )
        encoded_daikoku_release = json.dumps(daikoku_release).encode("utf-8")
        daikoku_source = (
            self.repository / validator.DAIKOKU_PRODUCT_RELEASE_SOURCE
        )
        daikoku_source.parent.mkdir(parents=True, exist_ok=True)
        daikoku_source.write_bytes(encoded_daikoku_release)
        (self.app / validator.DAIKOKU_PRODUCT_RELEASE_RESOURCE).write_bytes(
            encoded_daikoku_release
        )
        scenic_release = json.loads(encoded_product_release)
        scenic_release["release_id"] = validator.SCENIC_PRODUCT_RELEASE_ID
        scenic_route_plan = scenic_release["navigation_release"]["route_plan"]
        scenic_route_plan.update(
            {
                "plan_id": validator.SCENIC_ROUTE_PLAN_ID,
                "entry_facility_id": validator.SCENIC_ENTRY_FACILITY_ID,
                "exit_facility_id": validator.SCENIC_EXIT_FACILITY_ID,
                "occurrences": [
                    {"id": f"scenic.fixture.{index}"}
                    for index in range(validator.SCENIC_ROUTE_OCCURRENCE_COUNT)
                ],
            }
        )
        scenic_release["route_atlas_release"]["route_plan"] = (
            scenic_route_plan
        )
        encoded_scenic_release = json.dumps(scenic_release).encode("utf-8")
        scenic_source = self.repository / validator.SCENIC_PRODUCT_RELEASE_SOURCE
        scenic_source.parent.mkdir(parents=True, exist_ok=True)
        scenic_source.write_bytes(encoded_scenic_release)
        (self.app / validator.SCENIC_PRODUCT_RELEASE_RESOURCE).write_bytes(
            encoded_scenic_release
        )
        data_licenses = "\n".join(
            (
                validator.EXPECTED_OSM_ATTRIBUTION,
                validator.EXPECTED_OSM_LICENSE,
                validator.EXPECTED_OSM_LICENSE_URI,
            )
        )
        (self.repository / validator.DATA_LICENSES_RESOURCE).write_text(
            data_licenses,
            encoding="utf-8",
        )
        (self.app / validator.DATA_LICENSES_RESOURCE).write_text(
            data_licenses,
            encoding="utf-8",
        )
        (self.repository / "LICENSE").write_text("Apache-2.0\n", encoding="utf-8")
        (self.app / "LICENSE").write_text("Apache-2.0\n", encoding="utf-8")

        info = {
            "CFBundleIdentifier": validator.EXPECTED_BUNDLE_IDENTIFIER,
            "CFBundleDisplayName": validator.EXPECTED_DISPLAY_NAME,
            "CFBundleExecutable": "KaidoRoutes",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "7",
            "CFBundlePackageType": "APPL",
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "DTPlatformName": "iphoneos",
            "LSApplicationCategoryType": validator.EXPECTED_CATEGORY,
            "MinimumOSVersion": validator.EXPECTED_MINIMUM_OS,
            "ITSAppUsesNonExemptEncryption": False,
            "UIDeviceFamily": [1],
            "NSLocationWhenInUseUsageDescription": (
                validator.EXPECTED_LOCALIZATIONS["en"]
            ),
        }
        (self.app / "Info.plist").write_bytes(plistlib.dumps(info))
        for name in ("Assets.car", "PkgInfo"):
            (self.app / name).write_bytes(b"fixture")
        write_arm64_macho(self.app / "KaidoRoutes")
        for name, (width, height) in validator.EXPECTED_COMPILED_ICONS.items():
            write_png(self.app / name, width, height)
        for locale, description in validator.EXPECTED_LOCALIZATIONS.items():
            local_directory = self.app / f"{locale}.lproj"
            local_directory.mkdir()
            (local_directory / "InfoPlist.strings").write_bytes(
                plistlib.dumps(
                    {"NSLocationWhenInUseUsageDescription": description}
                )
            )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def validate(self) -> dict[str, str]:
        return validator.validate_release_bundle(self.app, self.repository)

    def test_scoped_release_bundle_passes(self) -> None:
        result = self.validate()

        self.assertEqual(result["bundle_identifier"], "app.kaidoroutes")
        self.assertEqual(result["version"], "1.0.0")
        self.assertEqual(result["build"], "7")
        self.assertEqual(
            result["c1_product_release_sha256"],
            validator.sha256(self.app / validator.C1_PRODUCT_RELEASE_RESOURCE),
        )
        self.assertEqual(
            result["wangan_product_release_sha256"],
            validator.sha256(
                self.app / validator.WANGAN_PRODUCT_RELEASE_RESOURCE
            ),
        )
        self.assertEqual(
            result["c2_product_release_sha256"],
            validator.sha256(
                self.app / validator.C2_PRODUCT_RELEASE_RESOURCE
            ),
        )

    def test_repository_data_license_matches_distribution_contract(self) -> None:
        notice = (
            REPOSITORY_ROOT / validator.DATA_LICENSES_RESOURCE
        ).read_text(encoding="utf-8")

        for required_text in (
            validator.EXPECTED_OSM_ATTRIBUTION,
            validator.EXPECTED_OSM_LICENSE,
            validator.EXPECTED_OSM_LICENSE_URI,
        ):
            with self.subTest(required_text=required_text):
                self.assertIn(required_text, notice)

    def test_archive_path_resolves_the_product_app(self) -> None:
        archive = self.root / "KaidoRoutes.xcarchive"
        destination = archive / "Products/Applications/KaidoRoutes.app"
        destination.parent.mkdir(parents=True)
        shutil.copytree(self.app, destination)

        result = validator.validate_release_bundle(archive, self.repository)

        self.assertEqual(Path(result["app"]), destination.resolve())

    def test_internal_fixture_resource_is_rejected(self) -> None:
        leaked = next(iter(validator.FORBIDDEN_RESOURCES))
        (self.app / leaked).write_text("fixture", encoding="utf-8")

        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "internal or retained fixture",
        ):
            self.validate()

    def test_unexpected_distribution_file_is_rejected(self) -> None:
        (self.app / "unreviewed.json").write_text("{}", encoding="utf-8")

        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "outside the distribution allowlist",
        ):
            self.validate()

    def test_unreviewed_compiled_icon_name_is_rejected(self) -> None:
        write_png(self.app / "AppIconUnreviewedPayload.png", 120, 120)

        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "outside the distribution allowlist",
        ):
            self.validate()

    def test_symlinked_distribution_resource_is_rejected(self) -> None:
        bundled = self.app / validator.DATA_LICENSES_RESOURCE
        bundled.unlink()
        bundled.symlink_to(
            self.repository / validator.DATA_LICENSES_RESOURCE
        )

        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "contain no symlinks",
        ):
            self.validate()

    def test_debug_bundle_identifier_is_rejected(self) -> None:
        info_path = self.app / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleIdentifier"] = "app.kaidoroutes.preview"
        info_path.write_bytes(plistlib.dumps(info))

        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "bundle identifier",
        ):
            self.validate()

    def test_background_location_scope_is_rejected(self) -> None:
        info_path = self.app / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["UIBackgroundModes"] = ["location"]
        info_path.write_bytes(plistlib.dumps(info))

        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "background modes",
        ):
            self.validate()

    def test_privacy_manifest_drift_is_rejected(self) -> None:
        manifest_path = self.app / "PrivacyInfo.xcprivacy"
        manifest = plistlib.loads(manifest_path.read_bytes())
        manifest["NSPrivacyTracking"] = True
        manifest_path.write_bytes(plistlib.dumps(manifest))

        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "privacy manifest",
        ):
            self.validate()

    def test_transparent_app_store_icon_is_rejected(self) -> None:
        source = (
            self.repository
            / "Apps/KaidoRoutesApp/Resources/Assets.xcassets/AppIcon.appiconset"
            / "AppIcon-1024.png"
        )
        write_png(source, 1024, 1024, color_type=6)

        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "icon transparency",
        ):
            self.validate()

    def test_opaque_apple_optimized_compiled_icon_is_accepted(self) -> None:
        write_png(
            self.app / "AppIcon60x60@2x.png",
            120,
            120,
            color_type=6,
            cgbi=True,
            opaque_alpha=True,
        )

        result = self.validate()

        self.assertEqual(result["bundle_identifier"], "app.kaidoroutes")

    def test_non_iphone_or_non_application_bundle_is_rejected(self) -> None:
        info_path = self.app / "Info.plist"
        cases = [
            ("CFBundlePackageType", "BNDL", "package type"),
            ("CFBundleSupportedPlatforms", ["AppleTVOS"], "Release platform"),
            ("DTPlatformName", "appletvos", "build platform"),
        ]
        for key, value, message in cases:
            with self.subTest(key=key):
                info = plistlib.loads(info_path.read_bytes())
                original = info[key]
                info[key] = value
                info_path.write_bytes(plistlib.dumps(info))
                with self.assertRaisesRegex(
                    validator.ReleaseBundleValidationError,
                    message,
                ):
                    self.validate()
                info[key] = original
                info_path.write_bytes(plistlib.dumps(info))

    def test_macos_macho_is_rejected_even_when_info_plist_claims_ios(self) -> None:
        write_arm64_macho(self.app / "KaidoRoutes", platform=1)

        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "Mach-O build platform",
        ):
            self.validate()

    def test_fake_or_non_executable_app_binary_is_rejected(self) -> None:
        binary = self.app / "KaidoRoutes"
        binary.write_bytes(b"not a Mach-O")
        binary.chmod(0o644)

        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "executable permission",
        ):
            self.validate()

        binary.chmod(0o755)
        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "Mach-O header",
        ):
            self.validate()

        binary.write_bytes(
            struct.pack("<II", 0xFEEDFACF, validator.ARM64_CPU_TYPE)
            + (b"\x00" * 24)
        )
        binary.chmod(0o755)
        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "file type",
        ):
            self.validate()

    def test_bundled_license_hash_drift_is_rejected(self) -> None:
        (self.app / "LICENSE").write_text("changed\n", encoding="utf-8")

        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "LICENSE hash",
        ):
            self.validate()

    def test_bundled_data_license_hash_drift_is_rejected(self) -> None:
        (self.app / validator.DATA_LICENSES_RESOURCE).write_text(
            "changed\n",
            encoding="utf-8",
        )

        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "DATA-LICENSES.md hash",
        ):
            self.validate()

    def test_c1_foreground_release_drift_is_rejected(self) -> None:
        for path in (
            self.app / validator.C1_PRODUCT_RELEASE_RESOURCE,
            self.repository / validator.C1_PRODUCT_RELEASE_SOURCE,
        ):
            artifact = json.loads(path.read_text(encoding="utf-8"))
            artifact["runtime_use"]["live_input_policy"] = "DISABLED"
            path.write_text(json.dumps(artifact), encoding="utf-8")

        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "C1 product live-input policy",
        ):
            self.validate()

    def test_wangan_foreground_release_drift_is_rejected(self) -> None:
        for path in (
            self.app / validator.WANGAN_PRODUCT_RELEASE_RESOURCE,
            self.repository / validator.WANGAN_PRODUCT_RELEASE_SOURCE,
        ):
            artifact = json.loads(path.read_text(encoding="utf-8"))
            artifact["navigation_release"]["route_plan"][
                "exit_facility_id"
            ] = "shuto.ic.b.wrong"
            path.write_text(json.dumps(artifact), encoding="utf-8")

        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "Wangan exit facility",
        ):
            self.validate()

    def test_c2_foreground_release_drift_is_rejected(self) -> None:
        for path in (
            self.app / validator.C2_PRODUCT_RELEASE_RESOURCE,
            self.repository / validator.C2_PRODUCT_RELEASE_SOURCE,
        ):
            artifact = json.loads(path.read_text(encoding="utf-8"))
            artifact["navigation_release"]["route_plan"][
                "entry_facility_id"
            ] = "shuto.ic.c2.wrong"
            path.write_text(json.dumps(artifact), encoding="utf-8")

        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "C2 entry facility",
        ):
            self.validate()

    def test_osm_license_uri_drift_is_rejected(self) -> None:
        paths = (
            self.repository
            / "data/route-atlas/osm-derived"
            / validator.WHOLE_SHUTO_RESOURCE,
            self.app / validator.WHOLE_SHUTO_RESOURCE,
        )
        for path in paths:
            snapshot = json.loads(path.read_text(encoding="utf-8"))
            snapshot["sources"]["osm"]["licence_uri"] = (
                "https://example.invalid/wrong-license"
            )
            path.write_text(json.dumps(snapshot), encoding="utf-8")

        with self.assertRaisesRegex(
            validator.ReleaseBundleValidationError,
            "OSM licence URI",
        ):
            self.validate()


if __name__ == "__main__":
    unittest.main()
