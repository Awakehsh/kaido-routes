#!/usr/bin/env python3
"""Fail closed when a built Kaido Routes Release app drifts from distribution scope."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
from pathlib import Path
import re
import stat
import struct
import sys
from typing import Any
import zlib


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
EXPECTED_BUNDLE_IDENTIFIER = "app.kaidoroutes"
EXPECTED_DISPLAY_NAME = "Kaido Routes"
EXPECTED_CATEGORY = "public.app-category.navigation"
EXPECTED_MINIMUM_OS = "18.0"
EXPECTED_PLATFORM = "iPhoneOS"
ARM64_CPU_TYPE = 0x0100000C
MACHO_EXECUTE_FILE_TYPE = 2
LC_SEGMENT_64 = 0x19
LC_MAIN = 0x80000028
LC_BUILD_VERSION = 0x32
MACHO_PLATFORM_IOS = 2
EXPECTED_VERSION_PATTERN = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
EXPECTED_LOCALIZATIONS = {
    "en": (
        "Kaido Routes uses your location after you choose Current Location "
        "or start route navigation."
    ),
    "ja": "現在地の選択時とルート案内の開始後に、位置情報を使用します。",
    "zh-Hans": (
        "在你选择「当前位置」或开始路线导航后，Kaido Routes 会使用你的位置信息。"
    ),
}
EXPECTED_PRIVACY_REASONS = {
    "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
    "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
}
WHOLE_SHUTO_RESOURCE = "shuto-whole-network-20260804.json"
DATA_LICENSES_RESOURCE = "DATA-LICENSES.md"
EXPECTED_OSM_ATTRIBUTION = "© OpenStreetMap contributors"
EXPECTED_OSM_LICENSE = "ODbL-1.0"
EXPECTED_OSM_LICENSE_URI = (
    "https://opendatacommons.org/licenses/odbl/1-0/"
)
EXPECTED_COMPILED_ICONS = {
    "AppIcon60x60@2x.png": (120, 120),
    "AppIcon76x76@2x~ipad.png": (152, 152),
}
FORBIDDEN_RESOURCES = {
    "c2-b-20260729-geographic-route.json",
    "k7-aoba-kohoku-product-release.json",
    "k7-aoba-to-kohoku-pre-drive-evidence.json",
    "k7-northwest-260721-directed-database.json",
    "k7-northwest-up-aoba-to-kohoku-osm-directed-candidate.json",
    "k7-northwest-up-schematic-layout-candidate.svg",
    "route-atlas-attribution-catalog.json",
    "shuto-route-atlas-recognition-reference.svg",
    "synthetic-product-runtime-preview.json",
}
FIXED_ALLOWED_FILES = {
    "Assets.car",
    "Info.plist",
    "KaidoRoutes",
    DATA_LICENSES_RESOURCE,
    "LICENSE",
    "PkgInfo",
    "PrivacyInfo.xcprivacy",
    WHOLE_SHUTO_RESOURCE,
    "embedded.mobileprovision",
    "_CodeSignature/CodeResources",
}


class ReleaseBundleValidationError(RuntimeError):
    """A built app is not safe to treat as the scoped Release product."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "app",
        type=Path,
        help="built KaidoRoutes.app or an .xcarchive containing it",
    )
    parser.add_argument(
        "--repository-root",
        type=Path,
        default=REPOSITORY_ROOT,
        help=argparse.SUPPRESS,
    )
    return parser.parse_args()


def resolve_app_path(path: Path) -> Path:
    candidate = path.resolve()
    if candidate.suffix == ".xcarchive":
        candidate = candidate / "Products/Applications/KaidoRoutes.app"
    if not candidate.is_dir() or candidate.suffix != ".app":
        raise ReleaseBundleValidationError(
            "release input must be KaidoRoutes.app or an archive containing it"
        )
    return candidate


def read_plist(path: Path, label: str) -> dict[str, Any]:
    try:
        value = plistlib.loads(path.read_bytes())
    except (OSError, plistlib.InvalidFileException) as error:
        raise ReleaseBundleValidationError(
            f"cannot read {label}: {error}"
        ) from error
    if not isinstance(value, dict):
        raise ReleaseBundleValidationError(f"{label} must contain one dictionary")
    return value


def read_json_object(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReleaseBundleValidationError(
            f"cannot read {label}: {error}"
        ) from error
    if not isinstance(value, dict):
        raise ReleaseBundleValidationError(f"{label} must contain one object")
    return value


def require_equal(actual: Any, expected: Any, label: str) -> None:
    if actual != expected:
        raise ReleaseBundleValidationError(
            f"{label} drifted: expected {expected!r}, got {actual!r}"
        )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise ReleaseBundleValidationError(
            f"cannot hash {path.name}: {error}"
        ) from error
    return digest.hexdigest()


def paeth_predictor(left: int, above: int, upper_left: int) -> int:
    estimate = left + above - upper_left
    left_distance = abs(estimate - left)
    above_distance = abs(estimate - above)
    upper_left_distance = abs(estimate - upper_left)
    if left_distance <= above_distance and left_distance <= upper_left_distance:
        return left
    if above_distance <= upper_left_distance:
        return above
    return upper_left


def png_has_transparent_pixels(
    data: bytes,
    width: int,
    height: int,
    bit_depth: int,
    color_type: int,
    interlace: int,
    is_cgbi: bool,
) -> bool:
    if bit_depth != 8 or interlace != 0:
        raise ReleaseBundleValidationError(
            "app icons must use non-interlaced 8-bit PNG encoding"
        )
    channels_by_color_type = {0: 1, 2: 3, 4: 2, 6: 4}
    channels = channels_by_color_type.get(color_type)
    if channels is None:
        raise ReleaseBundleValidationError(
            f"app icon PNG color type {color_type} is unsupported"
        )

    offset = 8
    idat = bytearray()
    has_transparency_chunk = False
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        payload_start = offset + 8
        payload_end = payload_start + length
        if payload_end + 4 > len(data):
            raise ReleaseBundleValidationError("app icon PNG chunk is truncated")
        if chunk_type == b"IDAT":
            idat.extend(data[payload_start:payload_end])
        elif chunk_type == b"tRNS":
            has_transparency_chunk = True
        offset = payload_end + 4
        if chunk_type == b"IEND":
            break
    if has_transparency_chunk:
        return True

    try:
        encoded_rows = zlib.decompress(idat, -15 if is_cgbi else 15)
    except zlib.error as error:
        raise ReleaseBundleValidationError(
            f"cannot decode app icon PNG: {error}"
        ) from error
    row_byte_count = width * channels
    expected_byte_count = height * (row_byte_count + 1)
    if len(encoded_rows) != expected_byte_count:
        raise ReleaseBundleValidationError("app icon PNG row data is invalid")

    previous = bytearray(row_byte_count)
    rows: list[bytearray] = []
    cursor = 0
    for _ in range(height):
        filter_type = encoded_rows[cursor]
        encoded = encoded_rows[cursor + 1 : cursor + 1 + row_byte_count]
        cursor += row_byte_count + 1
        row = bytearray(row_byte_count)
        for index, value in enumerate(encoded):
            left = row[index - channels] if index >= channels else 0
            above = previous[index]
            upper_left = previous[index - channels] if index >= channels else 0
            if filter_type == 0:
                decoded = value
            elif filter_type == 1:
                decoded = value + left
            elif filter_type == 2:
                decoded = value + above
            elif filter_type == 3:
                decoded = value + ((left + above) // 2)
            elif filter_type == 4:
                decoded = value + paeth_predictor(left, above, upper_left)
            else:
                raise ReleaseBundleValidationError(
                    f"app icon PNG uses invalid filter {filter_type}"
                )
            row[index] = decoded & 0xFF
        rows.append(row)
        previous = row

    if color_type == 4:
        return any(row[index] != 255 for row in rows for index in range(1, len(row), 2))
    if color_type == 6:
        return any(row[index] != 255 for row in rows for index in range(3, len(row), 4))
    return False


def png_identity(path: Path) -> tuple[int, int, int, bool]:
    try:
        data = path.read_bytes()
    except OSError as error:
        raise ReleaseBundleValidationError(
            f"cannot read PNG {path.name}: {error}"
        ) from error
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ReleaseBundleValidationError(f"{path.name} is not a valid PNG")
    offset = 8
    ihdr: bytes | None = None
    is_cgbi = False
    found_iend = False
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        payload_start = offset + 8
        payload_end = payload_start + length
        if payload_end + 4 > len(data):
            raise ReleaseBundleValidationError(
                f"{path.name} contains a truncated PNG chunk"
            )
        if chunk_type == b"CgBI":
            is_cgbi = True
        elif chunk_type == b"IHDR":
            if ihdr is not None or length != 13:
                raise ReleaseBundleValidationError(
                    f"{path.name} contains an invalid IHDR"
                )
            ihdr = data[payload_start:payload_end]
        elif chunk_type == b"IEND":
            found_iend = True
            break
        offset = payload_end + 4
    if ihdr is None or not found_iend:
        raise ReleaseBundleValidationError(
            f"{path.name} has no complete PNG header and trailer"
        )
    (
        width,
        height,
        bit_depth,
        color_type,
        compression,
        filter_method,
        interlace,
    ) = struct.unpack(">IIBBBBB", ihdr)
    if compression != 0 or filter_method != 0:
        raise ReleaseBundleValidationError("app icon PNG encoding is invalid")
    return (
        width,
        height,
        bit_depth,
        png_has_transparent_pixels(
            data,
            width,
            height,
            bit_depth,
            color_type,
            interlace,
            is_cgbi,
        ),
    )


def validate_arm64_macho(path: Path) -> None:
    try:
        if path.is_symlink():
            raise ReleaseBundleValidationError(
                "Release executable must not be a symlink"
            )
        metadata = path.stat()
        data = path.read_bytes()
    except OSError as error:
        raise ReleaseBundleValidationError(
            f"cannot inspect Release executable: {error}"
        ) from error
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_size <= 8:
        raise ReleaseBundleValidationError(
            "Release executable must be one non-empty regular file"
        )
    if metadata.st_mode & 0o111 == 0:
        raise ReleaseBundleValidationError(
            "Release executable has no executable permission bit"
        )
    if len(data) < 32:
        raise ReleaseBundleValidationError(
            "Release executable has no complete Mach-O header"
        )
    magic = data[:4]
    if magic == b"\xcf\xfa\xed\xfe":
        byte_order = "<"
    elif magic == b"\xfe\xed\xfa\xcf":
        byte_order = ">"
    else:
        raise ReleaseBundleValidationError(
            "Release executable is not a 64-bit Mach-O binary"
        )
    (
        _,
        cpu_type,
        _,
        file_type,
        command_count,
        command_bytes,
        _,
        _,
    ) = struct.unpack(f"{byte_order}8I", data[:32])
    require_equal(cpu_type, ARM64_CPU_TYPE, "Release executable architecture")
    require_equal(
        file_type,
        MACHO_EXECUTE_FILE_TYPE,
        "Release Mach-O file type",
    )
    if command_count < 1 or command_count > 4096 or command_bytes < 8:
        raise ReleaseBundleValidationError(
            "Release executable has an invalid load-command table"
        )
    commands_end = 32 + command_bytes
    if commands_end > len(data):
        raise ReleaseBundleValidationError(
            "Release executable load commands exceed the file"
        )

    command_offset = 32
    has_text_segment = False
    has_main_entry = False
    build_version_platforms: list[int] = []
    for _ in range(command_count):
        if command_offset + 8 > commands_end:
            raise ReleaseBundleValidationError(
                "Release executable load-command header is truncated"
            )
        command, command_size = struct.unpack(
            f"{byte_order}2I",
            data[command_offset : command_offset + 8],
        )
        if (
            command_size < 8
            or command_size % 8 != 0
            or command_offset + command_size > commands_end
        ):
            raise ReleaseBundleValidationError(
                "Release executable has an invalid load-command size"
            )
        if command == LC_SEGMENT_64:
            if command_size < 72:
                raise ReleaseBundleValidationError(
                    "Release executable has a truncated 64-bit segment"
                )
            segment_name = data[
                command_offset + 8 : command_offset + 24
            ].split(b"\x00", maxsplit=1)[0]
            if segment_name == b"__TEXT":
                has_text_segment = True
        elif command == LC_MAIN:
            if command_size < 24:
                raise ReleaseBundleValidationError(
                    "Release executable has a truncated main entry command"
                )
            entry_offset = struct.unpack(
                f"{byte_order}Q",
                data[command_offset + 8 : command_offset + 16],
            )[0]
            if entry_offset <= 0 or entry_offset >= len(data):
                raise ReleaseBundleValidationError(
                    "Release executable main entry is outside the file"
                )
            has_main_entry = True
        elif command == LC_BUILD_VERSION:
            if command_size < 24:
                raise ReleaseBundleValidationError(
                    "Release executable has a truncated build-version command"
                )
            platform = struct.unpack(
                f"{byte_order}I",
                data[command_offset + 8 : command_offset + 12],
            )[0]
            build_version_platforms.append(platform)
        command_offset += command_size
    if command_offset != commands_end:
        raise ReleaseBundleValidationError(
            "Release executable load-command count and size disagree"
        )
    if not has_text_segment or not has_main_entry:
        raise ReleaseBundleValidationError(
            "Release executable lacks a __TEXT segment or LC_MAIN entry"
        )
    require_equal(
        build_version_platforms,
        [MACHO_PLATFORM_IOS],
        "Release Mach-O build platform",
    )


def validate_info_plist(app: Path) -> tuple[str, str]:
    info = read_plist(app / "Info.plist", "Release Info.plist")
    require_equal(
        info.get("CFBundleIdentifier"),
        EXPECTED_BUNDLE_IDENTIFIER,
        "Release bundle identifier",
    )
    require_equal(
        info.get("CFBundleDisplayName"),
        EXPECTED_DISPLAY_NAME,
        "Release display name",
    )
    require_equal(
        info.get("CFBundleExecutable"),
        "KaidoRoutes",
        "Release executable",
    )
    require_equal(info.get("CFBundlePackageType"), "APPL", "bundle package type")
    require_equal(
        info.get("CFBundleSupportedPlatforms"),
        [EXPECTED_PLATFORM],
        "Release platform",
    )
    require_equal(info.get("DTPlatformName"), "iphoneos", "build platform")
    require_equal(
        info.get("LSApplicationCategoryType"),
        EXPECTED_CATEGORY,
        "App Store category",
    )
    require_equal(
        info.get("MinimumOSVersion"),
        EXPECTED_MINIMUM_OS,
        "minimum iOS version",
    )
    require_equal(
        info.get("ITSAppUsesNonExemptEncryption"),
        False,
        "export-compliance declaration",
    )
    require_equal(info.get("UIDeviceFamily"), [1], "target device family")
    if "UIBackgroundModes" in info:
        raise ReleaseBundleValidationError(
            "Release declares background modes outside the current product scope"
        )
    for key in (
        "NSLocationAlwaysUsageDescription",
        "NSLocationAlwaysAndWhenInUseUsageDescription",
    ):
        if key in info:
            raise ReleaseBundleValidationError(
                f"Release declares unsupported always-on location key {key}"
            )
    require_equal(
        info.get("NSLocationWhenInUseUsageDescription"),
        EXPECTED_LOCALIZATIONS["en"],
        "base location usage description",
    )

    version = info.get("CFBundleShortVersionString")
    if not isinstance(version, str) or EXPECTED_VERSION_PATTERN.fullmatch(version) is None:
        raise ReleaseBundleValidationError("Release marketing version is not semantic")
    build = info.get("CFBundleVersion")
    if not isinstance(build, str) or not build.isdigit() or int(build) < 1:
        raise ReleaseBundleValidationError(
            "Release build number must be a positive decimal integer"
        )
    validate_arm64_macho(app / "KaidoRoutes")
    return version, build


def validate_privacy_manifest(app: Path, repository_root: Path) -> None:
    manifest_path = app / "PrivacyInfo.xcprivacy"
    source_path = (
        repository_root
        / "Apps/KaidoRoutesApp/Resources/PrivacyInfo.xcprivacy"
    )
    manifest = read_plist(manifest_path, "bundled privacy manifest")
    source = read_plist(source_path, "source privacy manifest")
    require_equal(manifest, source, "bundled privacy manifest")
    require_equal(manifest.get("NSPrivacyTracking"), False, "privacy tracking")
    require_equal(
        manifest.get("NSPrivacyTrackingDomains"), [], "tracking domains"
    )
    require_equal(
        manifest.get("NSPrivacyCollectedDataTypes"), [], "collected data types"
    )
    entries = manifest.get("NSPrivacyAccessedAPITypes")
    if not isinstance(entries, list):
        raise ReleaseBundleValidationError(
            "privacy manifest required-reason APIs must be a list"
        )
    reasons: dict[str, Any] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            raise ReleaseBundleValidationError(
                "privacy manifest required-reason entry is invalid"
            )
        category = entry.get("NSPrivacyAccessedAPIType")
        if not isinstance(category, str) or category in reasons:
            raise ReleaseBundleValidationError(
                "privacy manifest required-reason categories are invalid"
            )
        reasons[category] = entry.get("NSPrivacyAccessedAPITypeReasons")
    require_equal(reasons, EXPECTED_PRIVACY_REASONS, "required-reason APIs")


def validate_localizations(app: Path) -> None:
    actual_localizations = {
        path.name.removesuffix(".lproj")
        for path in app.glob("*.lproj")
        if path.is_dir()
    }
    require_equal(
        actual_localizations,
        set(EXPECTED_LOCALIZATIONS),
        "Release localizations",
    )
    for locale, description in EXPECTED_LOCALIZATIONS.items():
        strings = read_plist(
            app / f"{locale}.lproj/InfoPlist.strings",
            f"{locale} InfoPlist.strings",
        )
        require_equal(
            strings.get("NSLocationWhenInUseUsageDescription"),
            description,
            f"{locale} location usage description",
        )


def validate_distribution_files(app: Path, repository_root: Path) -> None:
    bundle_paths = list(app.rglob("*"))
    symlinks = sorted(
        path.relative_to(app).as_posix()
        for path in bundle_paths
        if path.is_symlink()
    )
    if symlinks:
        raise ReleaseBundleValidationError(
            "Release bundle must be self-contained and contain no symlinks: "
            + ", ".join(symlinks)
        )
    actual_files = {
        path.relative_to(app).as_posix()
        for path in bundle_paths
        if path.is_file()
    }
    leaked = sorted(
        path for path in actual_files if Path(path).name in FORBIDDEN_RESOURCES
    )
    if leaked:
        raise ReleaseBundleValidationError(
            "Release contains internal or retained fixture resources: "
            + ", ".join(leaked)
        )

    allowed_files = set(FIXED_ALLOWED_FILES)
    allowed_files.update(
        f"{locale}.lproj/InfoPlist.strings"
        for locale in EXPECTED_LOCALIZATIONS
    )
    allowed_files.update(EXPECTED_COMPILED_ICONS)
    unexpected = sorted(actual_files - allowed_files)
    if unexpected:
        raise ReleaseBundleValidationError(
            "Release contains files outside the distribution allowlist: "
            + ", ".join(unexpected)
        )

    for required in FIXED_ALLOWED_FILES - {
        "embedded.mobileprovision",
        "_CodeSignature/CodeResources",
    }:
        if required not in actual_files:
            raise ReleaseBundleValidationError(
                f"Release is missing required file {required}"
            )
    source_pairs = {
        DATA_LICENSES_RESOURCE: repository_root / DATA_LICENSES_RESOURCE,
        "LICENSE": repository_root / "LICENSE",
        WHOLE_SHUTO_RESOURCE: (
            repository_root
            / "data/route-atlas/osm-derived"
            / WHOLE_SHUTO_RESOURCE
        ),
    }
    for bundled_name, source_path in source_pairs.items():
        require_equal(
            sha256(app / bundled_name),
            sha256(source_path),
            f"bundled {bundled_name} hash",
        )


def validate_osm_distribution_license(app: Path) -> None:
    snapshot = read_json_object(
        app / WHOLE_SHUTO_RESOURCE,
        "bundled whole-Shuto snapshot",
    )
    sources = snapshot.get("sources")
    osm = sources.get("osm") if isinstance(sources, dict) else None
    if not isinstance(osm, dict):
        raise ReleaseBundleValidationError(
            "bundled whole-Shuto snapshot has no OSM source object"
        )
    require_equal(
        osm.get("attribution"),
        EXPECTED_OSM_ATTRIBUTION,
        "whole-Shuto OSM attribution",
    )
    require_equal(
        osm.get("licence"),
        EXPECTED_OSM_LICENSE,
        "whole-Shuto OSM licence",
    )
    require_equal(
        osm.get("licence_uri"),
        EXPECTED_OSM_LICENSE_URI,
        "whole-Shuto OSM licence URI",
    )
    source_uri = osm.get("source_uri")
    if not isinstance(source_uri, str) or not source_uri.startswith("https://"):
        raise ReleaseBundleValidationError(
            "whole-Shuto OSM source URI must be one HTTPS URI"
        )

    try:
        notice = (app / DATA_LICENSES_RESOURCE).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise ReleaseBundleValidationError(
            f"cannot read bundled {DATA_LICENSES_RESOURCE}: {error}"
        ) from error
    for required_text in (
        EXPECTED_OSM_ATTRIBUTION,
        EXPECTED_OSM_LICENSE,
        EXPECTED_OSM_LICENSE_URI,
    ):
        if required_text not in notice:
            raise ReleaseBundleValidationError(
                f"bundled {DATA_LICENSES_RESOURCE} omits {required_text}"
            )


def validate_app_icons(app: Path, repository_root: Path) -> None:
    source = (
        repository_root
        / "Apps/KaidoRoutesApp/Resources/Assets.xcassets/AppIcon.appiconset"
        / "AppIcon-1024.png"
    )
    width, height, bit_depth, has_transparency = png_identity(source)
    require_equal((width, height), (1024, 1024), "App Store icon dimensions")
    require_equal(bit_depth, 8, "App Store icon bit depth")
    require_equal(has_transparency, False, "App Store icon transparency")

    built_icons = {path.name: path for path in app.glob("AppIcon*.png")}
    require_equal(
        set(built_icons),
        set(EXPECTED_COMPILED_ICONS),
        "compiled app icon files",
    )
    for name, expected_size in EXPECTED_COMPILED_ICONS.items():
        icon = built_icons[name]
        width, height, bit_depth, has_transparency = png_identity(icon)
        if (
            (width, height) != expected_size
            or bit_depth != 8
            or has_transparency
        ):
            raise ReleaseBundleValidationError(
                f"compiled icon {icon.name} has invalid size, depth, or transparency"
            )


def validate_release_bundle(
    input_path: Path,
    repository_root: Path = REPOSITORY_ROOT,
) -> dict[str, str]:
    app = resolve_app_path(input_path)
    root = repository_root.resolve()
    version, build = validate_info_plist(app)
    validate_privacy_manifest(app, root)
    validate_localizations(app)
    validate_distribution_files(app, root)
    validate_osm_distribution_license(app)
    validate_app_icons(app, root)
    return {
        "app": str(app),
        "bundle_identifier": EXPECTED_BUNDLE_IDENTIFIER,
        "version": version,
        "build": build,
        "whole_shuto_sha256": sha256(app / WHOLE_SHUTO_RESOURCE),
    }


def main() -> int:
    args = parse_arguments()
    try:
        result = validate_release_bundle(args.app, args.repository_root)
    except ReleaseBundleValidationError as error:
        print(f"Release bundle validation failed: {error}", file=sys.stderr)
        return 1
    print(
        "Release bundle validated: "
        f"{result['bundle_identifier']} "
        f"{result['version']} ({result['build']}), "
        f"whole-Shuto {result['whole_shuto_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
