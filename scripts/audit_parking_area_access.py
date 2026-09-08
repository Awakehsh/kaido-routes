#!/usr/bin/env python3
"""Inventory PA paths for identity/direction review; never modify the network.

Unlike the single-way importer, this audit includes connected multi-way service
roads, missing motorway links and existing named PA links. A candidate is not
an approved PA binding. One shortest directed path per boundary pair is shown;
this is a bounded discovery inventory, not an exhaustive parking-lane model.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import heapq
import json
import math
from pathlib import Path
import urllib.request

API = "https://api.openstreetmap.org/api/0.6"


def distance(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    h = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 12_742_017.6 * math.asin(min(1, math.sqrt(h)))


def inside(point, polygon):
    y, x = point
    result = False
    for (ay, ax), (by, bx) in zip(polygon, polygon[1:] + polygon[:1]):
        if (ay > y) != (by > y) and x < (bx-ax)*(y-ay)/(by-ay)+ax:
            result = not result
    return result


def audit(network, pa, payload):
    coordinates = {e['id']: (e['lat'], e['lon']) for e in payload['elements'] if e['type'] == 'node'}
    ways = {e['id']: e for e in payload['elements'] if e['type'] == 'way'}
    known = {n['node_id'] for n in network['nodes']}
    present = {w['way_id'] for w in network['ways']}
    incoming, outgoing = defaultdict(list), defaultdict(list)
    for e in network['edges']:
        incoming[e['to_node_id']].append(e)
        outgoing[e['from_node_id']].append(e)
    polygons = [(w, [coordinates[n] for n in w['nodes']]) for w in ways.values()
                if w.get('tags', {}).get('highway') == 'rest_area'
                and all(n in coordinates for n in w['nodes'])]
    adjacency = defaultdict(list)
    for w in ways.values():
        t = w.get('tags', {})
        if w['id'] in present or t.get('highway') not in ('service', 'motorway_link') or t.get('oneway') != 'yes':
            continue
        access = next((t[k] for k in ('motorcar', 'motor_vehicle', 'vehicle', 'access') if k in t), None)
        if access not in (None, 'yes', 'designated', 'permissive', 'customers'):
            continue
        if any(k.endswith(':conditional') for k in t) or t.get('area') == 'yes':
            continue
        for i, (a, b) in enumerate(zip(w['nodes'], w['nodes'][1:])):
            if a in coordinates and b in coordinates:
                adjacency[a].append((b, w['id'], i, distance(coordinates[a], coordinates[b])))
    point = (pa['coordinate']['latitude'], pa['coordinate']['longitude'])
    paths = []
    for start in sorted(known.intersection(adjacency)):
        if not incoming[start] or distance(coordinates[start], point) > 800:
            continue
        queue = [(0, start, [])]
        visited = set()
        while queue:
            length, node, path = heapq.heappop(queue)
            if node in visited or length > 2000:
                continue
            visited.add(node)
            if node != start and node in known:
                if outgoing[node]:
                    paths.append((start, node, path, length))
                continue
            for target, way, segment, meters in adjacency[node]:
                heapq.heappush(queue, (length+meters, target, path+[(way, segment, node, target)]))
    candidates = []
    for start, end, path, length in paths:
        positions = [coordinates[n] for _, _, a, b in path for n in (a, b)]
        closest = min(distance(p, point) for p in positions)
        if closest > 400:
            continue
        touched = sorted({w['tags'].get('name', str(w['id'])) for w, polygon in polygons
                          if any(inside(p, polygon) for p in positions)})
        ids = list(dict.fromkeys(w for w, _, _, _ in path))
        candidates.append({
            'access_node_id': start, 'return_node_id': end,
            'length_meters': round(length, 3), 'closest_approach_meters': round(closest, 3),
            'osm_rest_area_names_touched': touched,
            'access_has_existing_onward_edges': bool(outgoing[start]),
            'return_has_existing_incoming_edges': bool(incoming[end]),
            'access_route_ids': sorted({m['route_id'] for e in incoming[start] for m in e['route_memberships']}),
            'return_route_ids': sorted({m['route_id'] for e in outgoing[end] for m in e['route_memberships']}),
            'ways': [{'way_id': i, 'version': ways[i]['version'], 'timestamp': ways[i]['timestamp'],
                      'url': f'https://www.openstreetmap.org/way/{i}', 'tags': ways[i].get('tags', {})} for i in ids],
            'segments': [{'way_id': w, 'segment_index': i, 'from_node_id': a, 'to_node_id': b} for w, i, a, b in path],
        })
    named = []
    for w in ways.values():
        name = w.get('tags', {}).get('name', '')
        touched = sorted({area['tags'].get('name', '') for area, polygon in polygons
                          if pa['base_name_ja'] in area['tags'].get('name', '')
                          and any(n in coordinates and inside(coordinates[n], polygon) for n in w['nodes'])})
        named_pa = pa['base_name_ja'] in name and ('PA' in name or 'パーキング' in name)
        if w['id'] in present and w.get('tags', {}).get('highway') == 'motorway_link' and (named_pa or touched):
            named.append({'way_id': w['id'], 'name': name, 'osm_rest_area_names_touched': touched,
                          'url': f'https://www.openstreetmap.org/way/{w["id"]}'})
    return {'parking_area_id': pa['parking_area_id'], 'name_ja': pa['name_ja'],
            'official_page_url': pa['official_page_url'], 'status': 'NEEDS_IDENTITY_AND_DIRECTION_REVIEW' if candidates or named else 'NO_PATH_IN_BOUNDED_READ',
            'candidates': candidates, 'existing_parking_way_candidates': named,
            'nearby_osm_rest_areas': [{'way_id': w['id'], 'name': w['tags'].get('name')} for w, _ in polygons]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--network', type=Path, required=True)
    parser.add_argument('--cache-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--read-at', required=True)
    parser.add_argument('--offline', action='store_true', help='Require previously read map payloads; do not fetch.')
    args = parser.parse_args()
    raw = args.network.read_bytes()
    network = json.loads(raw)
    args.cache_dir.mkdir(parents=True, exist_ok=True)
    reports = []
    for pa in network['parking_areas']:
        if pa.get('interior_edge_ids'):
            continue
        lat, lon = pa['coordinate']['latitude'], pa['coordinate']['longitude']
        url = f'{API}/map.json?bbox={lon-.004},{lat-.003},{lon+.004},{lat+.003}'
        cache = args.cache_dir / (pa['parking_area_id'] + '.json')
        if not args.offline:
            request = urllib.request.Request(url, headers={'User-Agent': 'kaido-routes parking-area audit'})
            with urllib.request.urlopen(request, timeout=30) as response:
                cache.write_bytes(response.read())
        payload = cache.read_bytes()
        report = audit(network, pa, json.loads(payload))
        report['source'] = {'url': url, 'sha256': hashlib.sha256(payload).hexdigest()}
        reports.append(report)
    result = {'kind': 'PARKING_ACCESS_CANDIDATE_AUDIT', 'read_at': args.read_at,
              'network_snapshot_id': network['network_snapshot_id'], 'network_sha256': hashlib.sha256(raw).hexdigest(),
              'attribution': '© OpenStreetMap contributors', 'licence': 'ODbL-1.0',
              'licence_uri': 'https://opendatacommons.org/licenses/odbl/1-0/',
              'limitations': ['Not an approved access review or importer input.',
                             'One shortest directed path per boundary pair; bounded to 800 m starts and 2 km paths.',
                             'A nearby official label or an OSM area name does not establish legal directional access.',
                             'Current OSM geometry is not proof of geometry in the pinned historical extract.',
                             'NO_PATH_IN_BOUNDED_READ does not mean no road exists.'],
              'parking_areas': reports}
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True)+'\n')
    print(f'Audited {len(reports)} parking areas; {sum(len(r["candidates"]) for r in reports)} candidate paths; none approved.')


if __name__ == '__main__':
    main()
