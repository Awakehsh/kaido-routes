import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "audit_shuto_network.py"
SPEC = importlib.util.spec_from_file_location("audit_shuto_network", SCRIPT)
AUDIT = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(AUDIT)


def edge(edge_id, from_node, to_node, kind="LINK"):
    return {
        "edge_id": edge_id,
        "from_node_id": from_node,
        "to_node_id": to_node,
        "kind": kind,
        "length_meters": 100.0,
    }


def facility(facility_id, name, entry=(), exit_=(), distance=10.0):
    return {
        "facility_id": facility_id,
        "name_ja": name,
        "entry_edge_candidates": [{"distance_meters": distance, "edge_id": e} for e in entry],
        "exit_edge_candidates": [{"distance_meters": distance, "edge_id": e} for e in exit_],
    }


def network():
    # Carriageway 1→2→3. 甲's exit ramp leaves at 2 for the surface at 10;
    # 乙's entrance ramp comes from the surface at 11 onto 2.
    return {
        "database_id": "db",
        "edges": [
            edge("m.1", 1, 2, kind="MAINLINE"),
            edge("m.2", 2, 3, kind="MAINLINE"),
            edge("x.out", 2, 10),
            edge("e.in", 11, 2),
        ],
        "directional_facilities": [
            facility("f.ko", "甲", exit_=["x.out"]),
            facility("f.otsu", "乙", entry=["e.in"]),
        ],
        "nodes": [],
    }


def exceptions(**changes):
    base = {
        "database_id": "db",
        "candidate_distance_limit_meters": 400,
        "mainline_termini": [
            {"node_id": 1, "kind": "dead_start", "reason": "route begins at a surface road"},
            {"node_id": 3, "kind": "dead_end", "reason": "route ends at a surface road"},
        ],
        "candidate_distance_exceptions": [],
        "ramp_continuations": [],
        "named_unbound_ramps": [],
    }
    base.update(changes)
    return base


class AuditShutoNetworkTests(unittest.TestCase):
    def test_a_clean_network_passes(self):
        self.assertEqual(AUDIT.audit(network(), exceptions(), set()), [])

    def test_exceptions_reviewed_against_another_database_fail(self):
        findings = AUDIT.audit(network(), exceptions(database_id="older"), set())
        self.assertEqual(len(findings), 1)
        self.assertIn("older", findings[0])

    def test_an_unlisted_carriageway_end_and_a_stale_listing_fail(self):
        extended = network()
        extended["edges"].append(edge("m.3", 3, 4, kind="MAINLINE"))
        self.assertEqual(
            AUDIT.audit(extended, exceptions(), set()),
            [
                "carriageway dead end at node 4 (m.3) is not a listed terminus",
                "listed terminus at node 3 (dead_end) is no longer one",
            ],
        )

    def test_a_ramp_bound_to_two_interchanges_fails(self):
        shared = network()
        shared["directional_facilities"].append(facility("f.hei", "丙", exit_=["x.out"]))
        findings = AUDIT.audit(shared, exceptions(), set())
        self.assertIn("edge x.out is bound as 丙 exit, 甲 exit", findings)
        self.assertIn("exit ramp meeting the surface at node 10 is bound to 丙, 甲", findings)

    def test_one_ramp_bound_as_entrance_and_exit_fails(self):
        both = network()
        both["directional_facilities"][1]["exit_edge_candidates"] = [
            {"distance_meters": 1.0, "edge_id": "e.in"}
        ]
        self.assertIn(
            "edge e.in is bound as 乙 entry, 乙 exit",
            AUDIT.audit(both, exceptions(), set()),
        )

    def test_two_ramps_to_one_surface_end_bound_to_two_names_fail(self):
        merged = network()
        merged["edges"] += [edge("y.out", 3, 13), edge("y.tail", 13, 10)]
        merged["directional_facilities"].append(facility("f.hei", "丙", exit_=["y.out"]))
        findings = AUDIT.audit(
            merged,
            exceptions(mainline_termini=exceptions()["mainline_termini"][:1]),
            set(),
        )
        self.assertEqual(findings, ["exit ramp meeting the surface at node 10 is bound to 丙, 甲"])

    def test_a_distant_candidate_needs_a_reasoned_exception(self):
        distant = network()
        distant["directional_facilities"][0] = facility("f.ko", "甲", exit_=["x.out"], distance=650.0)
        self.assertEqual(
            AUDIT.audit(distant, exceptions(), set()),
            ["f.ko exit x.out is 650 m from the facility, beyond 400 m, without a reviewed exception"],
        )
        reviewed = exceptions(candidate_distance_exceptions=[
            {"facility_id": "f.ko", "edge_id": "x.out", "reason": "split interchange"},
        ])
        self.assertEqual(AUDIT.audit(distant, reviewed, set()), [])
        self.assertEqual(
            AUDIT.audit(network(), reviewed, set()),
            ["distance exception f.ko x.out no longer applies"],
        )

    def test_an_exit_that_runs_on_to_another_interchanges_exit_fails(self):
        chained = network()
        chained["edges"] += [edge("z.out", 3, 14), edge("z.on", 14, 15)]
        chained["directional_facilities"] += [
            facility("f.hei", "丙", exit_=["z.out"]),
            facility("f.tei", "丁", exit_=["z.on"]),
        ]
        findings = AUDIT.audit(
            chained,
            exceptions(mainline_termini=exceptions()["mainline_termini"][:1]),
            set(),
        )
        self.assertEqual(findings, ["f.hei exit z.out continues past its toll point to another interchange's"])
        reviewed = exceptions(
            mainline_termini=exceptions()["mainline_termini"][:1],
            ramp_continuations=[
                {"facility_id": "f.hei", "side": "exit", "edge_id": "z.out", "reason": "OSM joins them"},
            ],
        )
        self.assertEqual(AUDIT.audit(chained, reviewed, set()), [])

    def test_closed_and_parking_bindings_fail(self):
        parked = network()
        parked["edges"].append(edge("pa", 12, 13, kind="PARKING"))
        parked["directional_facilities"].append(facility("f.hei", "丙", exit_=["pa"]))
        findings = AUDIT.audit(parked, exceptions(), {"x.out"})
        self.assertIn("f.ko exit x.out binds a closed ramp", findings)
        self.assertIn("f.hei exit pa is not a drivable edge", findings)

    def test_an_unbound_ramp_named_after_an_interchange_needs_a_reasoned_exception(self):
        # 乙's second entrance comes from the surface at 20 through a toll
        # booth OSM names after it, and no facility binds it.
        named = network()
        named["edges"] += [edge("f.in", 20, 21), edge("f.on", 21, 2)]
        named["nodes"].append({"node_id": 21, "tags": {"barrier": "toll_booth", "name": "乙入口"}})
        self.assertEqual(
            AUDIT.audit(named, exceptions(), set()),
            ["unbound entry ramp meeting the surface at node 20 is named 乙"],
        )
        reviewed = exceptions(named_unbound_ramps=[
            {"side": "entry", "node_id": 20, "reason": "a second surface start of a bound ramp"},
        ])
        self.assertEqual(AUDIT.audit(named, reviewed, set()), [])
        self.assertEqual(
            AUDIT.audit(network(), reviewed, set()),
            ["named unbound ramp exception entry 20 no longer applies"],
        )

    def test_closed_parking_and_carriageway_free_chains_are_not_unbound_ramps(self):
        named = network()
        named["edges"] += [
            edge("c.in", 20, 21), edge("c.on", 21, 2),  # closed ramp
            edge("p.ret", 30, 31, kind="PARKING"), edge("p.on", 31, 2),  # PA return
            edge("s.in", 40, 41), edge("s.out", 41, 42),  # reaches no carriageway
        ]
        named["nodes"] += [
            {"node_id": node, "tags": {"highway": "motorway_junction", "name": "乙"}}
            for node in (21, 31, 41)
        ]
        self.assertEqual(AUDIT.audit(named, exceptions(), {"c.in"}), [])


if __name__ == "__main__":
    unittest.main()
