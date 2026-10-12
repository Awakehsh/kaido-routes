# Parking access source reviews

These source-reviewed OpenStreetMap path records supplement the distributed
whole-Shuto database. They are OSM-derived database material under ODbL 1.0,
with © OpenStreetMap contributors attribution and the licence at
https://opendatacommons.org/licenses/odbl/1-0/. The root Apache licence does not
relicense them. Coordinates are public road geometry, never personal traces.
Operator pages are linked and hashed; their images and HTML are not distributed.

The 2026-09-07 review supplies Daikoku's interior. The 2026-09-08 review applies
to that exact output (input SHA-256 is checked) and supplies the other 18 paths.
Schema 1.1 preserves source way and segment identity across multi-way paths,
existing parking links and repeated segments. Its separate connecting-way
record restores the Oi eastbound return's missing Bayshore mainline; this road
retains B membership and is never classified as parking.

Replay the two reviews in date order with `scripts/apply_parking_access_review.py`.
Use the unaugmented 2026-08-04 database as input to the first review. To reread
source geometry for the selected paths, pass `--selection` with the 1.1 review
to `scripts/build_parking_access_review.py`; a changed node sequence requires
renewed review rather than silently changing segment identities.

The 2026-09-14 facility candidate patch applies to the 2026-09-08 output
(input SHA-256 is checked) and re-points the ramp candidates of ten facilities
the network build had bound to the wrong ramp — the operator's real ramp is a
route-relation member the build types as mainline, the only nearby links were
the opposite role's, a rest-area ramp sat closer than the plaza, or a split
interchange keeps its ramps beyond the candidate radius — and unbinds the
横浜港北 twin listed under 横浜北西線, whose ramps belong to 横浜北線. Each
patch names its OSM way evidence and the pairing counts it must reach; replay
it after the parking reviews with `scripts/apply_facility_candidate_patch.py`,
which refuses an output whose patched facilities do not pair as reviewed.

The 2026-10-12 facility closure review applies to the 2026-09-14 output (input
SHA-256 is checked) and records the operator notice of 2026-07-17, with the
two independent reports used to confirm it while the operator site refused
scripted fetches: from 2026-10-18 23:00 the C1 新富町 exit is abolished in both
directions and the 内回り 銀座 entrance closes for about three years. Each
closure names the closed directions and the closed ramp edges; replay it
with `scripts/apply_facility_closure_review.py`, which removes those directions,
unbinds the closed ramps from every facility that had them as candidates, marks
a facility left with no open direction `UNAVAILABLE`, and refuses a closure that
would leave a neighbour without a ramp.

The 2026-10-12 topology review applies to the closure output (input SHA-256 is
checked). It restores carriageway ways the builder left outside the graph
(Route 1 Haneda southbound's rebuilt section, the start of K3 at 本牧JCT),
removes construction structures the builder admitted as motorway, and cuts
the link chains OSM draws straight across a surface road from an exit into an
entrance. `scripts/build_topology_review.py` reads each named way at the
version current at the extract's timestamp and the surface roads at each
crossing; replay with `scripts/apply_topology_review.py`, which refuses a
restored chain that does not close a carriageway dead end or dead start, a
removal that is not an admitted construction structure, and a cut that does
not break the exit-to-entrance continuation it names.

The 2026-10-12 facility candidate patch (schema 1.1) applies to the topology
output and re-derives every facility's ramps, so that each ramp binds at most
one interchange name; it also adds the 東銀座 exit and corrects the 大橋JCT
node list and coordinate. Replay it last with
`scripts/apply_facility_candidate_patch.py`. The audit exceptions in
`data/network/shuto-network-audit-exceptions.json` are bound to its output's
`database_id`.

Source review establishes the recorded static path, not current opening status,
field accuracy or navigation admission for an arbitrary route.
