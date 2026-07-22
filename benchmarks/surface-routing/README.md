# Surface-routing provider benchmark

This benchmark decides whether a provider can supply a bounded ordinary-road
leg to a verified directional entrance approach. It does not let the provider
author, optimize, or recover the Shuto route plan.

## Tracked and local material

```text
benchmarks/surface-routing/
├── schema/
│   ├── entrance-probe-fixture.schema.json
│   └── provider-probe-result.schema.json
├── fixtures/synthetic/
└── raw/ and runs/                    # local and gitignored
```

Tracked synthetic fixtures prove the format and evaluator without making a real
road claim. The first release corpus will contain approximately ten exact,
directional entrance facilities, each with at least these three origins:

1. `SAME_SIDE`: an already aligned ordinary-road approach;
2. `CROSS_DIRECTION`: a legal approach from the opposite direction;
3. `NEAREST_INCOMPATIBLE`: a nearby IC or facility that cannot join the selected
   route.

Real fixtures need a dated network snapshot, operator evidence, licensed
structured-data evidence, explicit release blockers, and review of every
retained field. Raw provider responses and live run output remain under the
ignored `raw/` and `runs/` paths until retention and redistribution rights are
reviewed.

## Two-stage probe

The provider adapter returns only a normalized `SurfaceRouteCandidate`:

- geometry;
- localized steps and notices;
- distance and ETA;
- provider-exposed highway and toll indicators;
- a disclosed provider failure when no candidate exists.

A separate `SurfaceCandidateInspector` binds that geometry to the versioned
Kaido road graph. It must establish the directed approach edge, terminal heading,
early expressway crossings, toll-domain crossings, and whether the binding is
unambiguous. A provider's `hasHighways == false` value cannot replace this graph
inspection.

Every successful candidate must pass all six gates:

1. correct directed approach anchor;
2. no expressway entry before the selected transition;
3. compatibility with the selected route occurrence;
4. no forbidden toll-domain crossing;
5. unambiguous geometry binding;
6. honest provider status.

An explicitly disclosed provider failure passes only the sixth gate and still
fails the supported-entrance run. A success response with no candidate fails the
status gate. Missing inspection evidence fails closed.

## Current implementation boundary

`KaidoSurfaceRouting` owns the provider-neutral fixture, candidate, inspection,
hard-gate, and normalized-result types. Its `DirectedRoadGraphInspector`
resamples candidate geometry, scores directed edges using distance and heading,
checks graph continuity, detects ambiguous parallel edges, and reports early
expressway and toll-domain crossings. It fails closed on invalid or mismatched
network snapshots. This is a surface-probe inspector, not the live Shuto matcher.

`KaidoAppleAdapters` contains the first `MKDirections` adapter. The adapter
requests automobile alternatives and asks MapKit to avoid highways and tolls for
the bounded surface leg, but those options are hints rather than proof.

No real entrance is released yet. The reviewed ten-entrance corpus, its licensed
road-graph snapshots, and the local live-probe command are the next evidence
tasks; deterministic CI does not call MapKit.

Run the offline checks with:

```sh
swift test
xcrun swift-format lint --strict --recursive Package.swift Sources Tests
python3 -m json.tool benchmarks/surface-routing/schema/entrance-probe-fixture.schema.json >/dev/null
python3 -m json.tool benchmarks/surface-routing/schema/provider-probe-result.schema.json >/dev/null
```
