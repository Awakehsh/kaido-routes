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

Source review establishes the recorded static path, not current opening status,
field accuracy or navigation admission for an arbitrary route.
