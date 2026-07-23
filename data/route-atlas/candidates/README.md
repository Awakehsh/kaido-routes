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
