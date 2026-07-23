#!/usr/bin/env python3
"""Build the non-navigable Shuto Route Atlas context from MLIT N06-2025."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import zipfile
from pathlib import Path
from typing import Any


SOURCE_REFERENCE_ID = "mlit.nlni.n06-2025.current-shuto"
GEOJSON_MEMBER_SUFFIX = "/UTF-8/N06-25_HighwaySection.geojson"
EXPECTED_COVERAGE = {
    "source_feature_count": 86,
    "path_count": 86,
    "vertex_count": 3584,
    "route_name_count": 26,
}
EXPECTED_SOURCE_CRS = "urn:ogc:def:crs:EPSG::6668"
EXPECTED_SOURCE_CRS_ID = "EPSG:6668"
USE_STATUS = {
    "1": "COMPLETE",
    "2": "PROVISIONAL",
}
ADDITIONAL_CURRENT_SHUTO_ROUTE_NAMES = {
    "高速横浜環状北西線",
}


class BuildError(RuntimeError):
    """A fail-closed source, parsing, or coverage error."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise BuildError(f"cannot read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise BuildError(f"expected a JSON object in {path}")
    return value


def load_source_archive(
    archive_path: Path,
    expected_sha256: str,
) -> dict[str, Any]:
    actual_sha256 = sha256(archive_path)
    if actual_sha256 != expected_sha256:
        raise BuildError(
            "source archive checksum mismatch: "
            f"expected {expected_sha256}, got {actual_sha256}"
        )
    try:
        with zipfile.ZipFile(archive_path) as archive:
            candidates = [
                name
                for name in archive.namelist()
                if name.endswith(GEOJSON_MEMBER_SUFFIX)
            ]
            if len(candidates) != 1:
                raise BuildError(
                    "expected exactly one UTF-8 HighwaySection GeoJSON member, "
                    f"found {len(candidates)}"
                )
            with archive.open(candidates[0]) as handle:
                value = json.load(handle)
    except (OSError, zipfile.BadZipFile, json.JSONDecodeError) as error:
        raise BuildError(f"cannot read source archive: {error}") from error
    if not isinstance(value, dict):
        raise BuildError("source GeoJSON must be an object")
    return value


def selected_features(
    geojson: dict[str, Any],
) -> list[tuple[int, dict[str, Any]]]:
    crs = geojson.get("crs")
    crs_properties = crs.get("properties") if isinstance(crs, dict) else None
    crs_name = (
        crs_properties.get("name")
        if isinstance(crs_properties, dict)
        else None
    )
    if crs_name != EXPECTED_SOURCE_CRS:
        raise BuildError(
            "source CRS mismatch: "
            f"expected {EXPECTED_SOURCE_CRS!r}, got {crs_name!r}"
        )
    features = geojson.get("features")
    if not isinstance(features, list):
        raise BuildError("source GeoJSON has no feature array")

    selected: list[tuple[int, dict[str, Any]]] = []
    for source_index, feature in enumerate(features):
        if not isinstance(feature, dict):
            raise BuildError(f"source feature {source_index} is not an object")
        properties = feature.get("properties")
        if not isinstance(properties, dict):
            raise BuildError(
                f"source feature {source_index} has no property object"
            )
        route_name = properties.get("N06_007")
        if not isinstance(route_name, str) or not (
            route_name.startswith("首都高速")
            or route_name in ADDITIONAL_CURRENT_SHUTO_ROUTE_NAMES
        ):
            continue
        if str(properties.get("N06_003")) != "9999":
            continue
        if str(properties.get("N06_008")) != "5":
            continue
        selected.append((source_index, feature))
    return selected


def coordinate_parts(
    feature: dict[str, Any],
    source_index: int,
) -> list[list[list[float]]]:
    geometry = feature.get("geometry")
    if not isinstance(geometry, dict):
        raise BuildError(f"selected feature {source_index} has no geometry")
    geometry_type = geometry.get("type")
    coordinates = geometry.get("coordinates")
    if geometry_type == "MultiLineString" and isinstance(coordinates, list):
        parts = coordinates
    elif geometry_type == "LineString" and isinstance(coordinates, list):
        parts = [coordinates]
    else:
        raise BuildError(
            f"selected feature {source_index} has unsupported geometry "
            f"{geometry_type!r}"
        )

    validated: list[list[list[float]]] = []
    for part_index, part in enumerate(parts):
        if not isinstance(part, list) or len(part) < 2:
            raise BuildError(
                f"selected feature {source_index} part {part_index} "
                "must contain at least two vertices"
            )
        vertices: list[list[float]] = []
        for vertex_index, coordinate in enumerate(part):
            if (
                not isinstance(coordinate, list)
                or len(coordinate) < 2
                or isinstance(coordinate[0], bool)
                or isinstance(coordinate[1], bool)
                or not isinstance(coordinate[0], (int, float))
                or not isinstance(coordinate[1], (int, float))
                or not math.isfinite(coordinate[0])
                or not math.isfinite(coordinate[1])
            ):
                raise BuildError(
                    f"selected feature {source_index} part {part_index} "
                    f"has invalid vertex {vertex_index}"
                )
            vertices.append([float(coordinate[0]), float(coordinate[1])])
        validated.append(vertices)
    return validated


def build_paths(
    selected: list[tuple[int, dict[str, Any]]],
) -> tuple[list[dict[str, Any]], list[tuple[float, float]]]:
    paths: list[dict[str, Any]] = []
    all_coordinates: list[tuple[float, float]] = []
    for source_index, feature in selected:
        properties = feature["properties"]
        source_record_id = properties.get("N06_004")
        route_name = properties.get("N06_007")
        status = USE_STATUS.get(str(properties.get("N06_009")))
        if not isinstance(source_record_id, str) or not source_record_id.strip():
            raise BuildError(
                f"selected feature {source_index} has no N06_004 record ID"
            )
        if not isinstance(route_name, str) or not route_name.strip():
            raise BuildError(
                f"selected feature {source_index} has no N06_007 route name"
            )
        if status is None:
            raise BuildError(
                f"selected feature {source_index} has unsupported use status "
                f"{properties.get('N06_009')!r}"
            )

        source_feature_id = f"mlit.n06-2025.feature.{source_index:04d}"
        for part_index, coordinates in enumerate(
            coordinate_parts(feature, source_index)
        ):
            all_coordinates.extend((point[0], point[1]) for point in coordinates)
            paths.append(
                {
                    "path_id": (
                        f"{source_feature_id}.part.{part_index:03d}"
                    ),
                    "source_feature_id": source_feature_id,
                    "source_record_id": source_record_id,
                    "source_part_index": part_index,
                    "route_name_ja": route_name,
                    "use_status": status,
                    "_source_coordinates": coordinates,
                }
            )
    return paths, all_coordinates


def project(
    paths: list[dict[str, Any]],
    all_coordinates: list[tuple[float, float]],
) -> dict[str, float]:
    if not all_coordinates:
        raise BuildError("selected context has no coordinates")
    longitudes = [point[0] for point in all_coordinates]
    latitudes = [point[1] for point in all_coordinates]
    minimum_longitude = min(longitudes)
    maximum_longitude = max(longitudes)
    minimum_latitude = min(latitudes)
    maximum_latitude = max(latitudes)
    center_longitude = (minimum_longitude + maximum_longitude) / 2
    center_latitude = (minimum_latitude + maximum_latitude) / 2
    longitude_scale = math.cos(math.radians(center_latitude))
    projected_width = (
        maximum_longitude - minimum_longitude
    ) * longitude_scale
    projected_height = maximum_latitude - minimum_latitude
    extent = max(projected_width, projected_height)
    if extent <= 0:
        raise BuildError("selected context has a degenerate geographic extent")

    uniform_scale = 0.92 / extent
    for path in paths:
        points = []
        for longitude, latitude in path.pop("_source_coordinates"):
            x = 0.5 + (
                (longitude - center_longitude)
                * longitude_scale
                * uniform_scale
            )
            y = 0.5 - ((latitude - center_latitude) * uniform_scale)
            points.append({"x": round(x, 9), "y": round(y, 9)})
        path["points"] = points

    return {
        "minimum_longitude": minimum_longitude,
        "maximum_longitude": maximum_longitude,
        "minimum_latitude": minimum_latitude,
        "maximum_latitude": maximum_latitude,
    }


def coverage(paths: list[dict[str, Any]]) -> dict[str, int]:
    return {
        "source_feature_count": len(
            {path["source_feature_id"] for path in paths}
        ),
        "path_count": len(paths),
        "vertex_count": sum(len(path["points"]) for path in paths),
        "route_name_count": len({path["route_name_ja"] for path in paths}),
    }


def build(
    archive_path: Path,
    source_path: Path,
) -> dict[str, Any]:
    source = load_json(source_path)
    if source.get("source_reference_id") != SOURCE_REFERENCE_ID:
        raise BuildError(
            "source reference mismatch: expected "
            f"{SOURCE_REFERENCE_ID!r}, got "
            f"{source.get('source_reference_id')!r}"
        )
    if source.get("source_crs") != EXPECTED_SOURCE_CRS_ID:
        raise BuildError(
            "source record CRS mismatch: expected "
            f"{EXPECTED_SOURCE_CRS_ID!r}, got {source.get('source_crs')!r}"
        )
    expected_sha256 = source.get("archive_sha256")
    if not isinstance(expected_sha256, str) or len(expected_sha256) != 64:
        raise BuildError("source reference has no valid archive SHA-256")

    geojson = load_source_archive(archive_path, expected_sha256)
    paths, all_coordinates = build_paths(selected_features(geojson))
    bounds = project(paths, all_coordinates)
    actual_coverage = coverage(paths)
    if actual_coverage != EXPECTED_COVERAGE:
        raise BuildError(
            "selected source coverage mismatch: "
            f"expected {EXPECTED_COVERAGE}, got {actual_coverage}"
        )

    return {
        "schema_version": "1.0",
        "context_id": "shuto.context.mlit-n06-2025-current",
        "navigation_role": "CONTEXT_ONLY",
        "source_reference_id": SOURCE_REFERENCE_ID,
        "projection": {
            "kind": "LOCAL_EQUIRECTANGULAR",
            "north_up": True,
            "source_crs": EXPECTED_SOURCE_CRS_ID,
            "coordinate_space": "NORMALIZED_UNIT_SQUARE",
            **bounds,
        },
        "coverage": actual_coverage,
        "paths": paths,
    }


def main() -> int:
    args = parse_args()
    try:
        artifact = build(args.archive, args.source)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(
                artifact,
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
    except (BuildError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    coverage_value = artifact["coverage"]
    print(
        "PASS: built context-only Route Atlas artifact with "
        f"{coverage_value['source_feature_count']} features, "
        f"{coverage_value['path_count']} paths, "
        f"{coverage_value['vertex_count']} vertices, and "
        f"{coverage_value['route_name_count']} route names"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
