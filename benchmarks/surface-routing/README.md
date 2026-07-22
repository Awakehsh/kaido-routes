# Surface-routing provider benchmark

This benchmark decides whether a provider can supply a bounded ordinary-road
leg to a verified directional entrance approach. It does not let the provider
author, optimize, or recover the Shuto route plan.

## Tracked and local material

```text
benchmarks/surface-routing/
├── schema/
│   ├── entrance-probe-fixture.schema.json
│   ├── provider-probe-result.schema.json
│   ├── provider-probe-stability-summary.schema.json
│   └── provider-probe-cross-window-summary.schema.json
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
uses a bounded sequence beam to preserve graph continuity, and compares the
observed distance between consecutive samples with directed graph travel between
their along-edge projections. This transition-distance penalty can reject a
connected detour that is geometrically close but materially longer. Skipped
connector edges remain visible to the hard gates, while truly equal-cost
parallel paths remain ambiguous. The inspector also reports early expressway and
toll-domain crossings and fails closed on invalid or mismatched network
snapshots.

The transition factor is an uncalibrated feasibility heuristic, not a confidence
model. Connector lookup is hop-bounded and currently retains one deterministic
connector path per edge pair. This is a surface-probe inspector, not the live
Shuto matcher or a replacement for the planned Valhalla and Swift HMM comparison.

`KaidoAppleAdapters` contains the first `MKDirections` adapter. The adapter
requests automobile alternatives and asks MapKit to avoid highways and tolls for
the bounded surface leg, but those options are hints rather than proof.

No real entrance is released yet. The local live-probe command is implemented;
the reviewed ten-entrance corpus, licensed road-graph snapshots, repeated runs,
and field checks remain evidence tasks. Deterministic CI does not call MapKit.

The local command requires an explicit live-provider acknowledgement and writes
one normalized JSON result to stdout. The result records provider and local
inspection latency separately so routing-network delay is not confused with
directed-graph matching cost:

```sh
swift run kaido-surface-probe \
  --fixture research/path/to/entrance.json \
  --graph research/path/to/directed-road-graph.json \
  --origin example.origin.same-side \
  --allow-live-mapkit \
  --pretty \
  > benchmarks/surface-routing/runs/example.json
```

For short-term repeatability checks, `--repeat` runs requests sequentially and
emits only counts and scalar ranges:

```sh
swift run kaido-surface-probe \
  --fixture research/path/to/entrance.json \
  --graph research/path/to/directed-road-graph.json \
  --origin example.origin.same-side \
  --allow-live-mapkit \
  --repeat 3 \
  --pretty
```

The repeat summary excludes coordinates, instructions, edge IDs, candidate IDs,
and path hashes. It distinguishes `STABLE_PASS`, `VARIABLE_PASS`, and `FAIL`, but
never overrides a failed hard gate. `SCALAR_LOCAL_ONLY` describes reduced local
retention; it does not mean the provider's terms have been reviewed.

A short repeat batch can be internally stable while a later window returns a
different route. Compare two or more retained scalar summaries with:

```sh
swift run kaido-surface-probe \
  --compare-summary research/path/window-a.json \
  --compare-summary research/path/window-b.json \
  --pretty
```

The cross-window result is `FAIL` if any batch failed and `VARIABLE_PASS` when a
batch already reported variation, a passing batch lacks an accepted-distance
range, or the accepted-distance ranges have no common value. Because scalar
summaries intentionally omit path identity, the result always declares
`route_identity_comparable_across_windows=false`; `STABLE_PASS` means only that
the retained scalar evidence did not expose variation.

Both real inputs remain under ignored `research/`; raw output remains under
ignored `runs/`. One-shot results record `RAW_LOCAL_ONLY`, and the MapKit adapter
still reports `REVIEW_REQUIRED`. Do not commit or redistribute provider geometry,
instructions, raw output, or scalar output until the relevant terms have been
reviewed.

For private feasibility work, `scripts/build_osm_surface_graph.py` converts a
bounded Overpass JSON extract into the inspector's directed-edge format. It
preserves OSM way and node lineage in every ID plus the OSM base timestamp and
ODbL attribution in graph provenance. The generated graph is ODbL data and must
remain outside the Apache-2.0 code boundary unless a deliberate data release is
prepared.

Run the offline checks with:

```sh
swift test
xcrun swift-format lint --strict --recursive Package.swift Sources Tests
python3 -m json.tool benchmarks/surface-routing/schema/entrance-probe-fixture.schema.json >/dev/null
python3 -m json.tool benchmarks/surface-routing/schema/provider-probe-result.schema.json >/dev/null
python3 -m json.tool benchmarks/surface-routing/schema/provider-probe-stability-summary.schema.json >/dev/null
python3 -m json.tool benchmarks/surface-routing/schema/provider-probe-cross-window-summary.schema.json >/dev/null
```
