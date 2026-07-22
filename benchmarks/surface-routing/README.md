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
│   ├── provider-probe-cross-window-summary.schema.json
│   ├── osm-selected-path-translation-request.schema.json
│   ├── osm-node-path-translation-request.schema.json
│   ├── osm-way-point-path-translation-request.schema.json
│   └── surface-routing-build-manifest.schema.json
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

Place probe origins inside the reviewed directed surface edge rather than
exactly on an OSM junction node. Keep the source node in the evidence record,
but avoid introducing an artificial first-sample tie between otherwise distinct
outgoing edges.

## Two-stage probe

The provider adapter returns only a normalized `SurfaceRouteCandidate`:

- geometry;
- localized steps and notices;
- distance and ETA;
- provider-exposed highway and toll indicators;
- optional complete selected-path evidence already translated to exact Kaido
  directed edge IDs from the same network snapshot;
- a disclosed provider failure when no candidate exists.

Opaque providers omit selected-path evidence. An adapter must also omit it when
the provider path is partial, when its dataset is not bound to the fixture's
network snapshot, or when it was inferred by rematching another provider's
polyline. The raw provider dataset ID remains in the evidence for audit.

A separate `SurfaceCandidateInspector` binds that geometry to the versioned
Kaido road graph. It must establish the directed approach edge, terminal heading,
early expressway crossings, toll-domain crossings, and whether the binding is
unambiguous. A provider's `hasHighways == false` value cannot replace this graph
inspection.

When complete same-snapshot selected-path evidence is present, the inspector
restricts binding to that exact ordered edge sequence. It still verifies every
edge exists, the sequence is directly continuous and ends on the approach edge,
the candidate geometry follows the asserted path, and the provider dataset ID
equals the graph provenance's `source_dataset_id`. Missing, duplicate,
disconnected, wrong-snapshot, wrong-dataset, or geometry-inconsistent evidence
fails closed.

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
hard-gate, normalized-result, and OSM selected-path translation types. Its
`OSMSelectedPathTranslator` expands provider OSM way/start-node/direction
identity onto exact Kaido edges, trims partial first and last edges against the
provider route geometry, and rejects cross-dataset, missing, ambiguous,
reversed, repeated, or disconnected identity. `OSMNodePathTranslator`
independently resolves complete ordered node paths and fails whenever one node
pair identifies zero or multiple directed edges. Its
`OSMWayPointPathTranslator` handles providers that expose directional edge keys
and OSM way IDs for every unsimplified route point-pair. It requires exact
dataset identity and ordered progress on same-way directed Kaido edges. Local
point-pair ambiguity caused by short or rounded geometry is accepted only when
whole-path continuity leaves one unique, nonrepeating Kaido edge sequence;
missing, simplified, unresolved ambiguous, or reused provider-edge identity
fails closed. Its
`DirectedRoadGraphInspector` resamples candidate geometry, scores directed edges
using distance and heading,
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

A private stacked-road pilot now establishes a provider boundary: a MapKit
candidate can have ordinary-road instructions and `has_highways=false` while its
polyline still admits continuous surface and expressway interpretations. The
inspector fails that candidate closed and withholds conclusive crossing arrays.
MapKit remains a bounded adapter under test, but it cannot satisfy the entire B1
role with geometry-only evidence.

A private manifest-bound Valhalla build now proves the selected-path and admin
boundaries: three runs for each of the same-side, cross-direction, and
nearest-incompatible Shinjuku origins passed all six gates after exact
translation. The build uses complete Japan administrative input, resolves Tokyo
as `JP` / state `13`, reports `drive_on_right=false`, and binds the engine image,
sources, tiles, admin/time-zone databases, and Kaido graph by checksum. The PBF,
tiles, routes, and raw edge evidence remain ignored private research data.

The public `ValhallaSurfaceRouteProvider` performs one `/route` request, sends
the returned encoded polyline unchanged to `/trace_attributes` with
`shape_match=edge_walk`, validates the provider dataset ID, and translates the
complete OSM identity before returning one candidate. The concrete URLSession
transport is deliberately only HTTP I/O. The first adapter returns the primary
candidate even when alternatives are preferred; provider operations and
alternate-response normalization remain separate evidence work.

Valhalla narrative prose is accepted only in its supported Japanese or English
locale. It does not supply Kaido's multilingual navigation contract: Japanese,
Chinese, and English signs, terminology, and speech remain structured
`GuidanceFrame` data owned by the Swift core.

No real entrance is released yet. A supervised private local HTTP window now
passes all nine Shinjuku runs through the public URLSession adapter and the same
six hard gates. Long-running service supervision, broader road coverage, ODbL
distribution review, retained sign/lane/temporal evidence, and field checks
remain release blockers.

The OSRM baseline has its own fail-closed path. `OSRMSurfaceRouteProvider`
requests one full GeoJSON route with `annotations=nodes`, checks response
`data_version` against the manifest, requires left-driving steps, and passes the
ordered node sequence to `OSMNodePathTranslator`. Every consecutive node pair
must resolve to exactly one directed Kaido edge; missing and parallel pairs are
rejected. OSRM maneuver fields are diagnostic only and do not supply localized
product guidance.

A private LAB_ONLY MLD build now passes the same supervised Shinjuku 3x3 run
through the public OSRM URLSession adapter. The selected paths contain 1, 8, and
44 exact Kaido edges, with no unmatched, ambiguous, disconnected, early
expressway, or forbidden-toll result. The build uses a synthetic bounded
left-driving polygon, so this is a provider-baseline pass rather than a released
entrance or a release-quality Japan data build.

The GraphHopper 11.0 baseline uses a third fail-closed identity path. Every
request first verifies `/info` version, profile, required encoded values, and a
non-epoch road timestamp against the manifest. `/route` must return unencoded,
unsimplified geometry whose `edge_key`, `osm_way_id`, and `country` path details
exactly partition every point-pair. Provider edge keys remain provider-local;
only the aligned way identity and geometry can translate them to Kaido edges.

A private `LAB_ONLY` GraphHopper build passes the same supervised Shinjuku 3x3
run through the public URLSession adapter. The three paths contain 1, 8, and 44
exact Kaido edges with one accepted path variant and zero unmatched, ambiguous,
or disconnected results. Its JAR, JRE image, timestamped PBF, configuration,
graph cache, and Kaido graph are checksum-bound. GraphHopper's navigation-layer
driving-side field is not trusted; Japanese, Chinese, and English product
guidance remains Kaido-owned.

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

Run the same hard-gate pipeline against a self-hosted, manifest-bound Valhalla
service only with an explicit live-provider acknowledgement:

```sh
swift run kaido-surface-probe \
  --fixture research/path/to/entrance.json \
  --graph research/path/to/directed-road-graph.json \
  --origin example.origin.same-side \
  --manifest research/path/to/surface-routing-build-manifest.json \
  --base-url http://127.0.0.1:18002 \
  --allow-live-valhalla \
  --repeat 3 \
  --pretty
```

Run the independent manifest-bound OSRM baseline through the same pipeline:

```sh
swift run kaido-surface-probe \
  --fixture research/path/to/entrance.json \
  --graph research/path/to/directed-road-graph.json \
  --origin example.origin.same-side \
  --manifest research/path/to/surface-routing-build-manifest.json \
  --base-url http://127.0.0.1:18003 \
  --allow-live-osrm \
  --repeat 3 \
  --pretty
```

Run the manifest-bound GraphHopper baseline with the same explicit boundary:

```sh
swift run kaido-surface-probe \
  --fixture research/path/to/entrance.json \
  --graph research/path/to/directed-road-graph.json \
  --origin example.origin.same-side \
  --manifest research/path/to/surface-routing-build-manifest.json \
  --base-url http://127.0.0.1:18989 \
  --allow-live-graphhopper \
  --repeat 3 \
  --pretty
```

The CLI derives the provider-specific terminal OSM node or way identity from
the reviewed approach edge, validates the manifest structurally, records only
the service origin, and marks
provider data `REVIEW_REQUIRED`. The URLSession transport has a 15-second
request timeout and an 8 MiB response limit. One-shot output is raw local data;
repeat output is still local scalar evidence, not permission to publish it.

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
bounded Overpass JSON or OSM API XML extract into the inspector's directed-edge
format. It preserves OSM way, segment, digitized direction, and node lineage in
explicit fields plus every edge ID, along with the source
snapshot timestamp and ODbL attribution in graph provenance. OSM XML has no
Overpass base timestamp, so `--source-snapshot-at` is mandatory for that input.
The generated graph is ODbL data and must remain outside the Apache-2.0 code
boundary unless a deliberate data release is prepared.

```sh
python3 scripts/build_osm_surface_graph.py \
  --input research/evidence/bounded-map.osm \
  --input-format osm-xml \
  --source-snapshot-at 2026-07-22T14:00:00Z \
  --source-dataset-id reviewed-routing-dataset-id \
  --source-uri 'https://api.openstreetmap.org/api/0.6/map?bbox=reviewed-bounds' \
  --network-snapshot-id private.reviewed.snapshot \
  --expressway-toll-domain-id jp.shuto \
  --output research/evidence/bounded-surface-graph.json
```

Omit `--source-dataset-id` for ordinary geometry-only probes. Supplying it is a
strong claim that the provider routing graph was built from the exact reviewed
dataset represented by this Kaido graph. A timestamp, public-server status
value, or successful best-effort way translation is not sufficient by itself.

Translate retained OSM provider identity and evaluate a candidate without a
live provider call:

```sh
swift run kaido-surface-evidence translate \
  --graph research/evidence/bounded-surface-graph.json \
  --request research/evidence/osm-path-translation-request.json \
  --pretty > research/evidence/selected-path-evidence.json

swift run kaido-surface-evidence evaluate \
  --graph research/evidence/bounded-surface-graph.json \
  --fixture research/evidence/entrance.json \
  --origin example.origin.same-side \
  --candidate research/evidence/candidate-with-selected-path.json \
  --expected-provider-id valhalla.local \
  --pretty > research/evidence/evaluation.json
```

The translation request must contain the provider dataset ID, complete ordered
edge references, route coordinates, and the reviewed terminal OSM node. It is
raw local evidence and remains subject to the same retention and licence rules
as provider output.

Validate a checksummed routing build before using its path evidence:

```sh
swift run kaido-surface-evidence validate-manifest \
  --manifest research/evidence/surface-routing-build-manifest.json \
  --graph research/evidence/bounded-surface-graph.json \
  --profile structural \
  --pretty
```

`structural` binds identity and checks metadata, including a road source,
routing tiles, and the exact Kaido graph artifact, without pretending a lab
build is releasable. `release-candidate` additionally requires all mandatory
source and artifact roles, complete admin/time-zone and selected-path identity
capabilities, a checksummed Tokyo left-driving observation,
`RELEASE_CANDIDATE` intended use, and zero blockers.
The manifest is audit metadata, not permission to redistribute its referenced
data.

Validate that a directional entrance fixture references one continuous surface
approach, entry transition, and target expressway edge in the same graph:

```sh
swift run kaido-surface-evidence validate-fixture \
  --fixture research/evidence/entrance.json \
  --graph research/evidence/bounded-surface-graph.json \
  --profile STRUCTURAL \
  --pretty
```

`RELEASE_CANDIDATE` additionally requires an explicit target expressway edge
and all existing release evidence gates. A structural pass proves graph binding,
not operator, sign, lane, field, or redistribution review.

Normalize retained Valhalla route and exact edge-walk responses offline:

```sh
swift run kaido-surface-evidence normalize-valhalla \
  --route-response research/evidence/route.json \
  --trace-response research/evidence/trace-attributes.json \
  --graph research/evidence/bounded-surface-graph.json \
  --provider-id valhalla.local \
  --provider-dataset-id 2026072101 \
  --candidate-id example.candidate \
  --terminal-osm-node-id 123456 \
  --pretty
```

Normalize a retained OSRM response only when its `data_version` is set and
matches graph provenance:

```sh
swift run kaido-surface-evidence normalize-osrm \
  --route-response research/evidence/route.json \
  --graph research/evidence/bounded-surface-graph.json \
  --provider-id osrm.local \
  --provider-dataset-id 2026072101 \
  --candidate-id example.candidate \
  --pretty
```

Normalize retained GraphHopper `/info` and `/route` responses through the same
manifest and point-pair identity checks without a provider call:

```sh
swift run kaido-surface-evidence normalize-graphhopper \
  --graph research/evidence/bounded-surface-graph.json \
  --manifest research/evidence/surface-routing-build-manifest.json \
  --info-response research/evidence/info.json \
  --route-response research/evidence/route.json \
  --candidate-id example.candidate \
  --provider-id graphhopper.local \
  --pretty
```

Run the offline checks with:

```sh
swift test
python3 -m unittest discover -s scripts/tests
xcrun swift-format lint --strict --recursive Package.swift Sources Tests
python3 -m json.tool benchmarks/surface-routing/schema/entrance-probe-fixture.schema.json >/dev/null
python3 -m json.tool benchmarks/surface-routing/schema/provider-probe-result.schema.json >/dev/null
python3 -m json.tool benchmarks/surface-routing/schema/provider-probe-stability-summary.schema.json >/dev/null
python3 -m json.tool benchmarks/surface-routing/schema/provider-probe-cross-window-summary.schema.json >/dev/null
python3 -m json.tool benchmarks/surface-routing/schema/osm-selected-path-translation-request.schema.json >/dev/null
python3 -m json.tool benchmarks/surface-routing/schema/osm-node-path-translation-request.schema.json >/dev/null
python3 -m json.tool benchmarks/surface-routing/schema/osm-way-point-path-translation-request.schema.json >/dev/null
python3 -m json.tool benchmarks/surface-routing/schema/surface-routing-build-manifest.schema.json >/dev/null
```
