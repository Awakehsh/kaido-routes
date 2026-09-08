import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('audit_pa', Path(__file__).resolve().parents[1] / 'audit_parking_area_access.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def fixture():
    network = {'nodes': [{'node_id': n} for n in (1, 2, 4, 5)], 'ways': [],
               'edges': [{'from_node_id': a, 'to_node_id': b, 'route_memberships': [{'route_id': 'B'}]}
                         for a, b in ((1, 2), (2, 4), (4, 5))]}
    pa = {'parking_area_id': 'test.pa', 'base_name_ja': 'テスト', 'name_ja': 'テストPA',
          'official_page_url': 'https://example.org/pa', 'coordinate': {'latitude': 35, 'longitude': 139}}
    def way(i, nodes, tags=None):
        return {'type': 'way', 'id': i, 'version': 1, 'timestamp': '2026-01-01T00:00:00Z',
                'nodes': nodes, 'tags': tags or {'highway': 'service', 'oneway': 'yes'}}
    payload = {'elements': [{'type': 'node', 'id': n, 'lat': 35, 'lon': 139 + n * .0001} for n in range(1, 7)]
                           + [way(10, [2, 3]), way(11, [3, 4])]}
    return network, pa, payload, way


class ParkingAreaAuditTests(unittest.TestCase):
    def test_multiway_path_from_through_node_remains_unapproved(self):
        network, pa, payload, _ = fixture()
        result = module.audit(network, pa, payload)
        self.assertEqual(result['status'], 'NEEDS_IDENTITY_AND_DIRECTION_REVIEW')
        candidate, = result['candidates']
        self.assertEqual([w['way_id'] for w in candidate['ways']], [10, 11])
        self.assertTrue(candidate['access_has_existing_onward_edges'])
        self.assertEqual(candidate['return_node_id'], 4)

    def test_reverse_or_private_road_cannot_complete_path(self):
        for tags in ({'highway': 'service'}, {'highway': 'service', 'oneway': 'yes', 'access': 'private'},
                     {'highway': 'service', 'oneway': 'yes', 'motor_vehicle': 'no'},
                     {'highway': 'service', 'oneway': 'yes', 'access:conditional': 'no @ (Mo-Fr)'}):
            with self.subTest(tags=tags):
                network, pa, payload, _ = fixture()
                payload['elements'][-1]['tags'] = tags
                self.assertEqual(module.audit(network, pa, payload)['candidates'], [])

    def test_missing_return_is_not_synthesized(self):
        network, pa, payload, _ = fixture()
        payload['elements'][-1]['nodes'] = [3, 6]
        self.assertEqual(module.audit(network, pa, payload)['candidates'], [])

    def test_existing_named_parking_link_is_reported_without_duplicate_edges(self):
        network, pa, payload, way = fixture()
        network['ways'] = [{'way_id': 12}]
        payload['elements'] = payload['elements'][:-2] + [way(12, [2, 3, 4], {'highway': 'motorway_link', 'oneway': 'yes', 'name': 'テストパーキングエリア'})]
        result = module.audit(network, pa, payload)
        self.assertEqual(result['candidates'], [])
        self.assertEqual(result['existing_parking_way_candidates'][0]['way_id'], 12)

    def test_nearby_other_direction_is_visible_not_silently_selected(self):
        network, pa, payload, way = fixture()
        payload['elements'] += [way(12, [2, 6, 4])]
        network['nodes'].append({'node_id': 6})
        network['edges'].append({'from_node_id': 6, 'to_node_id': 5, 'route_memberships': []})
        result = module.audit(network, pa, payload)
        self.assertEqual({p['return_node_id'] for p in result['candidates']}, {4, 6})
        self.assertEqual(result['status'], 'NEEDS_IDENTITY_AND_DIRECTION_REVIEW')

    def test_named_polygon_is_evidence_not_approval(self):
        network, pa, payload, way = fixture()
        payload['elements'] += [{'type': 'node', 'id': n, 'lat': lat, 'lon': lon}
                                for n, lat, lon in ((20, 34.99, 138.99), (21, 35.01, 138.99), (22, 35.01, 139.01), (23, 34.99, 139.01))]
        payload['elements'].append(way(30, [20, 21, 22, 23, 20], {'highway': 'rest_area', 'name': 'テストPA (西行き)'}))
        result = module.audit(network, pa, payload)
        self.assertEqual(result['candidates'][0]['osm_rest_area_names_touched'], ['テストPA (西行き)'])
        self.assertEqual(result['status'], 'NEEDS_IDENTITY_AND_DIRECTION_REVIEW')


if __name__ == '__main__':
    unittest.main()
