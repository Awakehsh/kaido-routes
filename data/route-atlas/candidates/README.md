# Route Atlas release candidates

This directory contains real-source candidates that intentionally do not pass
`RouteAtlasRelease`. A candidate may preserve reviewed identities and geometry
without claiming that the remaining navigation and distribution gates are
complete.

## K7 Northwest up direction

`k7-northwest-up-aoba-to-kohoku-candidate.json` is generated from:

- MLIT N06-2025 feature 1414 / record `EA02_373001`, including all 38 retained
  centerline vertices in reverse source order;
- the current operator K7 Northwest route page;
- the operator Yokohama Aoba junction/entrance guide; and
- the operator Yokohama Kohoku junction/exit guide.

The candidate records one directed route occurrence from the exact Yokohama
Aoba K7 Northwest up entrance identity to the Yokohama Kohoku K7 Northwest up
exit identity. Its topology and layout evidence remain `OFFICIAL_CHECKED`, not
`RELEASED`.

The source review lists the remaining blockers. In particular, MLIT supplies an
undirected centerline rather than carriageway, ramp, or legal-successor
identity. Operator diagrams are factual review references, not distributable
Kaido layout assets. The candidate therefore cannot enable selection,
positioning, progress, recovery, or guidance.

Rebuild:

```sh
python3 scripts/build_k7_route_atlas_candidate.py \
  --context data/route-atlas/context/mlit-n06-2025-current-shuto-context.json \
  --route-catalog data/route-atlas/context/operator-route-mark-catalog-2026-07-23.json \
  --review data/route-atlas/candidates/k7-northwest-up-aoba-to-kohoku-source-review.json \
  --output data/route-atlas/candidates/k7-northwest-up-aoba-to-kohoku-candidate.json
```

Release validation must fail with only:

```text
UNRELEASED_ATLAS_EVIDENCE
UNRELEASED_ATLAS_TOPOLOGY_EVIDENCE
```

KR-D21 preserves this boundary in the portable scenario suite.

## OSM-directed K7 Northwest candidate

`k7-northwest-up-aoba-to-kohoku-osm-directed-candidate.json` advances the
candidate from one undirected MLIT centerline occurrence to:

- 13 exact one-way OSM route occurrences;
- 257 retained OSM nodes;
- the Yokohama Aoba entrance-to-K7 chain;
- the K7 Northwest up carriageway;
- the first branch toward Daisan-Keihin / Yokohama Kohoku exit;
- the later Yokohama Kohoku exit versus Daisan-Keihin branch; and
- one explicit immediate alternative at each of the two divergences.

The source-bound facility checks additionally retain the Aoba incoming and
non-route split ways plus all three source-adjacent motor-road successors at the
Kohoku surface terminal. Two are named one-way `川向線` ways. OSM way
`776884422` is an unnamed `tertiary` way without an explicit `oneway` tag.
Surface egress remains a separate bounded leg; these records prove the candidate
does not end at an unconnected coordinate without claiming that every surface
movement has completed legal review.

The underlying database is isolated under
`data/route-atlas/osm-derived/` and remains ODbL-1.0 data with OpenStreetMap
contributor attribution. Parent PBF and bounded-extract hashes, source
timestamp, extraction bounds, pyosmium version, exact way IDs, and
reconstruction commands are retained. The generated ODbL audit under
`data/route-atlas/osm-derived/k7-northwest-260721-successor-audit.json`
compares every declared successor with every motor-road way leaving 14 exact
checkpoint nodes. Its 19 source successors match exactly and no applicable
turn-restriction relation is present in the pinned extract.

The official Aoba and Kohoku guides corroborate the selected expressway movement
semantics, while the Yokohama municipal brochure confirms that the facility
connects to Kawamuki Line. The 2020 municipal opening notice gives the third
corridor a historic temporary-passage identity. A current municipal page
reports that surrounding infrastructure work completed in March 2022 and the
project ended in July 2023; the final replotting map still does not map OSM way
`776884422` to a current road identity or traffic direction. None relicenses the
OSM database or becomes a layout asset. Both candidate evidence states
therefore remain `CANDIDATE`, not `RELEASED`. Independent lawful road-level
review, production layout release review, in-product attribution, and realtime
review remain open.

KR-D22 executes the complete 13-occurrence / 15-edge artifact and requires
release validation to fail with only:

```text
UNRELEASED_ATLAS_EVIDENCE
UNRELEASED_ATLAS_TOPOLOGY_EVIDENCE
```

KR-D23 separately requires the same release block after the exact source
successor audit passes. Source adjacency completeness is not legal-successor
release evidence.

## K7 schematic layout candidate

`k7-northwest-up-aoba-to-kohoku-schematic-layout-candidate.json` replaces raw
source geometry only at the presentation layer. Its Kaido-owned normalized
layout remains bound to the same 15 candidate topology edges, preserves both
reviewed expressway divergences and all 13 occurrence bindings, and has a
separate Apache-2.0 layout source record with a pinned SHA-256 value.

The corresponding generated SVG is
`../design/k7-northwest-up-schematic-layout-candidate.svg`. It visibly stops at
the Yokohama Kohoku exit terminal and renders none of the three adjacent surface
ways. OpenStreetMap attribution remains present. KR-D24 requires the artifact
to fail release with only `UNRELEASED_ATLAS_EVIDENCE` and
`UNRELEASED_ATLAS_TOPOLOGY_EVIDENCE`.

Rebuild the layout artifact, scenario, and SVG:

```sh
python3 scripts/build_k7_schematic_layout_candidate.py \
  --base-candidate data/route-atlas/candidates/k7-northwest-up-aoba-to-kohoku-osm-directed-candidate.json \
  --layout data/route-atlas/design/k7-northwest-up-schematic-layout-candidate.json \
  --candidate-output data/route-atlas/candidates/k7-northwest-up-aoba-to-kohoku-schematic-layout-candidate.json \
  --scenario-output e2e/scenarios/kr-d24-k7-schematic-stops-at-surface-boundary.json \
  --svg-output data/route-atlas/design/k7-northwest-up-schematic-layout-candidate.svg
```
