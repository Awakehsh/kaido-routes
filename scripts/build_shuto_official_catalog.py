#!/usr/bin/env python3
"""Build the current official Shuto route, IC, JCT, and PA fact catalog.

The operator pages are the authority for facility names and directional
availability. This script records only the small set of facts needed by the
product; it never downloads or republishes operator maps or junction images.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
import re
import sys
from typing import Any
from urllib.parse import urljoin
from urllib.request import Request, urlopen

try:
    from bs4 import BeautifulSoup
except ImportError as error:  # pragma: no cover - exercised by CLI users
    raise SystemExit(
        "beautifulsoup4 is required to build the official catalog"
    ) from error


BASE_URL = "https://www.shutoko.jp"
NETWORK_MAP_URL = f"{BASE_URL}/use/network/map/"
JUNCTION_URL = f"{BASE_URL}/use/network/jct/"
PARKING_AREA_URL = f"{BASE_URL}/use/pa/"
USER_AGENT = "KaidoRoutes/1.0 official-fact-catalog-builder"
COORDINATE_PATTERN = re.compile(
    r"var\s+myLat\s*=\s*([0-9.]+)\s*;.*?"
    r"var\s+myLng\s*=\s*([0-9.]+)\s*;",
    re.DOTALL,
)
PA_COORDINATE_PATTERN = re.compile(
    r"!2d(13[0-9.]+)!3d(3[0-9.]+)"
)

ROUTE_IDS = {
    "route-c1": "C1",
    "route-c2": "C2",
    "route-y": "Y",
    "route-1u": "1_UENO",
    "route-1h": "1_HANEDA",
    "route-2": "2",
    "route-3": "3",
    "route-4": "4",
    "route-5": "5",
    "route-6mu": "6_MUKOJIMA",
    "route-6mi": "6_MISATO",
    "route-7": "7",
    "route-9": "9",
    "route-10": "10",
    "route-11": "11",
    "route-s1": "S1",
    "route-s2": "S2",
    "route-s5": "S5",
    "route-b": "B",
    "route-k1": "K1",
    "route-k2": "K2",
    "route-k3": "K3",
    "route-k6": "K6",
    "route-k7": "K7_YOKOHAMA_KITA",
    "route-k7ho": "K7_YOKOHAMA_HOKUSEI",
}

HEADING_ROUTE_IDS = {
    "高速都心環状線": "C1",
    "高速八重洲線": "Y",
    "高速1号上野線": "1_UENO",
    "高速1号羽田線": "1_HANEDA",
    "高速2号目黒線": "2",
    "高速3号渋谷線": "3",
    "高速4号新宿線": "4",
    "高速5号池袋線": "5",
    "高速6号向島線": "6_MUKOJIMA",
    "高速6号三郷線": "6_MISATO",
    "高速7号小松川線": "7",
    "高速9号深川線": "9",
    "高速10号晴海線": "10",
    "高速11号台場線": "11",
    "高速中央環状線": "C2",
    "高速川口線": "S1",
    "高速埼玉新都心線": "S2",
    "高速埼玉大宮線": "S5",
    "高速湾岸線": "B",
    "高速神奈川1号横羽線": "K1",
    "高速神奈川2号三ツ沢線": "K2",
    "高速神奈川3号狩場線": "K3",
    "高速神奈川5号大黒線": "K5",
    "高速神奈川6号川崎線": "K6",
    "高速神奈川7号横浜北線": "K7_YOKOHAMA_KITA",
    "高速神奈川7号横浜北西線": "K7_YOKOHAMA_HOKUSEI",
}

PA_ROUTE_IDS = {
    "羽田線": "1_HANEDA",
    "渋谷線": "3",
    "新宿線": "4",
    "池袋線": "5",
    "向島線": "6_MUKOJIMA",
    "三郷線": "6_MISATO",
    "深川線": "9",
    "台場線": "11",
    "湾岸線": "B",
    "川口線": "S1",
}


class CatalogError(RuntimeError):
    """Raised when an operator fact cannot be parsed without guessing."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument(
        "--checked-at",
        default=datetime.now(timezone.utc).date().isoformat(),
        help="Operator fact check date in YYYY-MM-DD form",
    )
    return parser.parse_args()


def fetch(url: str) -> tuple[bytes, str]:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=30) as response:
        body = response.read()
    return body, hashlib.sha256(body).hexdigest()


def clean_text(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def route_slug(href: str) -> str:
    match = re.search(r"/use/network/map/([^/]+)/", href)
    if not match:
        raise CatalogError(f"cannot identify route from {href}")
    return match.group(1)


def split_directions(value: str) -> list[str]:
    normalized = clean_text(value)
    if normalized in {"", "-", "－"}:
        return []
    return [
        part.strip()
        for part in re.split(r"[、,]", normalized)
        if part.strip()
    ]


def parse_network_map(
    document: bytes,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    soup = BeautifulSoup(document, "html.parser")
    routes: list[dict[str, Any]] = []
    facilities: list[dict[str, Any]] = []
    seen_route_ids: set[str] = set()

    for section in soup.select("li.c-attach-border__item"):
        heading = section.select_one("h3")
        table = section.select_one("table")
        if heading is None or table is None:
            continue
        heading_text = clean_text(heading.get_text(" ", strip=True))
        section_route_id = next(
            (
                route_id
                for prefix, route_id in HEADING_ROUTE_IDS.items()
                if heading_text.startswith(prefix)
            ),
            None,
        )
        if section_route_id is None:
            raise CatalogError(
                f"unmapped official route heading {heading_text}"
            )
        rows = table.select("tbody tr")
        for row in rows:
            cells = row.find_all(["th", "td"], recursive=False)
            if len(cells) < 4:
                continue
            link = cells[0].find("a", href=True)
            if link is None:
                continue
            slug = route_slug(str(link["href"]))
            route_id = ROUTE_IDS.get(slug)
            if route_id is None:
                raise CatalogError(f"unmapped official route slug {slug}")
            if section_route_id not in seen_route_ids:
                routes.append(
                    {
                        "route_id": section_route_id,
                        "official_name_ja": heading_text,
                        "operational_status": (
                            "LONG_TERM_CLOSED"
                            if "利用できません" in heading_text
                            or "通行止め" in heading_text
                            else "AVAILABLE"
                        ),
                    }
                )
                seen_route_ids.add(section_route_id)

            facility_text = clean_text(cells[0].get_text(" ", strip=True))
            facility_name = clean_text(link.get_text(" ", strip=True))
            facilities.append(
                {
                    "facility_id": (
                        "shuto.ic."
                        f"{section_route_id.lower().replace('_', '-')}."
                        f"{str(link['href']).rstrip('/').split('/')[-1]}"
                    ),
                    "route_id": section_route_id,
                    "official_page_route_slug": slug,
                    "name_ja": facility_name,
                    "reading_ja": clean_text(cells[1].get_text(" ", strip=True)),
                    "official_page_url": urljoin(BASE_URL, str(link["href"])),
                    "entrance_directions": split_directions(
                        cells[2].get_text(" ", strip=True)
                    ),
                    "exit_directions": split_directions(
                        cells[3].get_text(" ", strip=True)
                    ),
                    "etc_only": "ETC専用" in facility_text,
                    "operational_status": (
                        "UNAVAILABLE"
                        if "利用できません" in facility_text
                        else "AVAILABLE"
                    ),
                }
            )

    if len(routes) < 20 or len(facilities) < 100:
        raise CatalogError(
            f"operator map parse was incomplete: {len(routes)} routes, "
            f"{len(facilities)} facilities"
        )
    return routes, facilities


def add_facility_coordinate(
    facility: dict[str, Any],
) -> dict[str, Any]:
    body, body_hash = fetch(facility["official_page_url"])
    text = body.decode("utf-8", errors="replace")
    coordinate_match = COORDINATE_PATTERN.search(text)
    if coordinate_match is None:
        raise CatalogError(
            f"official coordinate missing for {facility['official_page_url']}"
        )
    result = dict(facility)
    result["coordinate"] = {
        "latitude": float(coordinate_match.group(1)),
        "longitude": float(coordinate_match.group(2)),
    }
    result["source_sha256"] = body_hash
    return result


def parse_junctions(document: bytes) -> list[dict[str, Any]]:
    soup = BeautifulSoup(document, "html.parser")
    junctions: list[dict[str, Any]] = []
    for link in soup.select('a[href*="/routeguide/jct_"]'):
        name = clean_text(link.get_text(" ", strip=True))
        if not name:
            continue
        junctions.append(
            {
                "junction_id": (
                    "shuto.jct."
                    + str(link["href"]).rstrip("/").split("/")[-1]
                ),
                "name_ja": name,
                "official_detail_reference": urljoin(
                    BASE_URL, str(link["href"])
                ),
            }
        )
    if len(junctions) < 35:
        raise CatalogError(
            f"operator junction parse was incomplete: {len(junctions)}"
        )
    return junctions


def add_junction_detail_hash(
    junction: dict[str, Any],
) -> dict[str, Any]:
    body, body_hash = fetch(junction["official_detail_reference"])
    if body.startswith(b"\xff\xd8\xff"):
        media_type = "image/jpeg"
    elif body.startswith(b"\x89PNG\r\n\x1a\n"):
        media_type = "image/png"
    else:
        raise CatalogError(
            "official JCT detail is no longer a supported image for "
            + junction["official_detail_reference"]
        )
    result = dict(junction)
    result["official_detail_media_type"] = media_type
    result["official_detail_sha256"] = body_hash
    return result


def parse_parking_areas(document: bytes) -> list[dict[str, Any]]:
    soup = BeautifulSoup(document, "html.parser")
    target_table = None
    for table in soup.select("table"):
        if "休憩施設名" in table.get_text(" ", strip=True):
            target_table = table
            break
    if target_table is None:
        raise CatalogError("operator PA table was not found")

    parking_areas: list[dict[str, Any]] = []
    current_route_name = ""
    for row in target_table.select("tbody tr"):
        cells = row.find_all("td", recursive=False)
        if not cells:
            continue
        link_cell_index = next(
            (
                index
                for index, cell in enumerate(cells[:2])
                if cell.find("a", href=True) is not None
            ),
            None,
        )
        if link_cell_index is None:
            continue
        if link_cell_index == 1:
            current_route_name = clean_text(cells[0].get_text(" ", strip=True))
        link = cells[link_cell_index].find("a", href=True)
        if link is None:
            continue
        name = clean_text(link.get_text(" ", strip=True))
        direction_match = re.search(r"（([^）]+)）", name)
        base_name = re.sub(r"（[^）]+）", "", name).removesuffix("PA")
        slug = str(link["href"]).rstrip("/").split("/")[-1]
        parking_areas.append(
            {
                "parking_area_id": f"shuto.pa.{slug}",
                "name_ja": name,
                "base_name_ja": base_name,
                "official_route_name_ja": current_route_name,
                "route_id": PA_ROUTE_IDS.get(current_route_name),
                "direction_ja": (
                    direction_match.group(1)
                    if direction_match is not None
                    else None
                ),
                "official_page_url": str(link["href"]),
                "dynamic_status": "REALTIME_UNCONFIRMED",
            }
        )
    if len(parking_areas) < 15:
        raise CatalogError(
            f"operator PA parse was incomplete: {len(parking_areas)}"
        )
    return parking_areas


def add_parking_area_coordinate(
    parking_area: dict[str, Any],
) -> dict[str, Any]:
    body, body_hash = fetch(parking_area["official_page_url"])
    match = PA_COORDINATE_PATTERN.search(
        body.decode("utf-8", errors="replace")
    )
    if match is None:
        raise CatalogError(
            "official PA coordinate missing for "
            + parking_area["official_page_url"]
        )
    result = dict(parking_area)
    result["coordinate"] = {
        "latitude": float(match.group(2)),
        "longitude": float(match.group(1)),
    }
    result["source_sha256"] = body_hash
    return result


def build_catalog(checked_at: str) -> dict[str, Any]:
    network_document, network_hash = fetch(NETWORK_MAP_URL)
    junction_document, junction_hash = fetch(JUNCTION_URL)
    parking_document, parking_hash = fetch(PARKING_AREA_URL)
    routes, facilities = parse_network_map(network_document)
    with ThreadPoolExecutor(max_workers=8) as executor:
        facilities = list(executor.map(add_facility_coordinate, facilities))
    facility_ids = [facility["facility_id"] for facility in facilities]
    if len(facility_ids) != len(set(facility_ids)):
        raise CatalogError("directional facility IDs are not unique")
    junctions = parse_junctions(junction_document)
    with ThreadPoolExecutor(max_workers=8) as executor:
        junctions = list(
            executor.map(add_junction_detail_hash, junctions)
        )
    parking_areas = parse_parking_areas(parking_document)
    with ThreadPoolExecutor(max_workers=8) as executor:
        parking_areas = list(
            executor.map(add_parking_area_coordinate, parking_areas)
        )

    return {
        "schema_version": "1.0",
        "catalog_id": f"kaido.shuto.official-facts.{checked_at}",
        "checked_at": checked_at,
        "authority": "SHUTOKO_OPERATOR_CURRENT_PAGES",
        "limitations": [
            (
                "The catalog records route and facility facts only; operator "
                "maps and junction images are not redistributed."
            ),
            (
                "Parking-area operating status is dynamic and remains "
                "REALTIME_UNCONFIRMED without a current provider response."
            ),
        ],
        "sources": [
            {
                "role": "ROUTES_AND_DIRECTIONAL_IC",
                "url": NETWORK_MAP_URL,
                "sha256": network_hash,
            },
            {
                "role": "JUNCTION_DIRECTORY",
                "url": JUNCTION_URL,
                "sha256": junction_hash,
                "operator_as_of": "2026-07-01",
            },
            {
                "role": "PARKING_AREA_DIRECTORY",
                "url": PARKING_AREA_URL,
                "sha256": parking_hash,
                "operator_as_of": "2024-12",
            },
        ],
        "routes": routes,
        "directional_facilities": facilities,
        "junctions": junctions,
        "parking_areas": parking_areas,
    }


def main() -> int:
    arguments = parse_arguments()
    try:
        catalog = build_catalog(arguments.checked_at)
        with open(arguments.output, "w", encoding="utf-8") as stream:
            json.dump(
                catalog,
                stream,
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            )
            stream.write("\n")
    except (CatalogError, OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(
        "PASS: recorded "
        f"{len(catalog['routes'])} routes, "
        f"{len(catalog['directional_facilities'])} IC names, "
        f"{len(catalog['junctions'])} junction references, and "
        f"{len(catalog['parking_areas'])} parking areas"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
