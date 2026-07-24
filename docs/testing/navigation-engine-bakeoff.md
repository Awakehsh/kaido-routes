# Navigation engine bake-off

**Status:** B0 is executable. B1 has a versioned fixture schema, graph-binding
validator, provider-neutral hard-gate runner, MapKit adapter, and a pure Swift
directed-road graph inspector plus an explicit local live-probe command. Five
private directional entrance fixtures now bind one reviewed surface approach,
entry transition, and target expressway edge. Manifest-bound Valhalla, OSRM, and
GraphHopper each passed the five fixtures x three origins x three-repeat final
window. MapKit retains one repeatable stacked-road geometry-only failure. No real
entrance fixture is released; private provider output remains outside the
repository.

**Checked:** 2026-07-23

## Decision to make

The bake-off answers four separate questions. It does not try to crown one
universal navigation SDK.

1. Can MapKit safely provide bounded surface access and egress for the released
   entrance set?
2. Which open-source router is the most useful fallback and analysis oracle?
3. Does a route-aware Swift matcher outperform generic map matching on Shuto's
   repeated, parallel, stacked, and tunnel cases?
4. Can the on-device Swift core meet deterministic correctness and performance
   budgets on the oldest supported iPhone?

## Candidate lanes

Do not compare tools outside the role they may own.

| Lane | Candidates | Required output |
|---|---|---|
| Surface access/egress | MapKit, Valhalla, OSRM, GraphHopper | directed approach/handoff geometry, steps, ETA, provider metadata |
| Generic map-match baseline | Valhalla Meili, OSRM Match, GraphHopper map matching | edge sequence, matched positions, confidence or alternatives where available |
| Kaido route-aware matcher | Swift HMM/online Viterbi | occurrence candidates, posterior/confidence, ambiguity reason, commit decisions |
| Strict compiler and recovery | Kaido Swift core only; generic engines may be negative controls | occurrence-preserving route, rejoin target, skipped occurrences, legal egress |
| Presentation | SwiftUI phone, UIKit/CarPlay adapter | identical semantic `GuidanceFrame` on both surfaces |

Commercial full-stack SDKs are not part of the first bake-off. Add one only after
a written build-versus-buy question, pricing snapshot, data-use review, and a
testable claim that the open architecture cannot meet.

## Fixture sets

### B0: synthetic domain fixtures

Use current `KR-D*` and `KR-S*` scenarios. They establish the contract before a
provider or Apple framework is introduced.

Add synthetic cases for:

- duplicated loop subsequences with fresh occurrence IDs;
- C2 plus required B-route movements;
- optional and required PA access;
- external toll-domain boundaries;
- missed exits and a second legal egress;
- stacked roads with identical or near-identical coordinates;
- tunnel gaps before, inside, and after a decision zone.

### B1: directional entrance corpus

Start with approximately ten exact entrance facilities. Each fixture records:

```text
fixture_id
network_snapshot_id
entrance_facility_id
target_carriageway and direction
surface_approach_anchor
entry_transition_edges
first_route_occurrence_id
forbidden early expressway edges
compatible exit policy
official and OSM evidence
checked_at
```

Before a conditional approach can enter the released corpus, a later fixture
version must also record the exact approach variant, evaluated departure/entry
time, local time zone, recurring movement rule, and its evidence. The v1 fixture
is intentionally insufficient for releasing a time-dependent approach.

For each entrance, choose at least three surface origins with different approach
geometry: simple same-side access, a cross-direction approach, and a case where
the geometrically nearest IC is incompatible.

Provider calls are live integration probes and are stored outside deterministic
CI. A reviewed result may later be reduced to a dated fixture if its licence
allows retention.

The tracked format lives under
[`benchmarks/surface-routing/`](../../benchmarks/surface-routing/README.md).
Synthetic fixtures must use visibly synthetic IDs. A non-synthetic fixture cannot
pass the Swift release validator without operator and structured-data evidence,
`RELEASED` classification, and no remaining release blockers.

### B2: matcher replay corpus

Build synthetic traces before collecting personal field traces:

- normal GPS noise at multiple accuracy bands;
- a parallel surface road below or beside the expressway;
- two stacked expressway carriageways;
- repeated passes over the same geometric edge;
- wrong branch with a plausible nearby planned branch;
- 15, 30, and 60 second observation gaps;
- signal return after a tunnel branch;
- stale timestamps and reordered events;
- phone-only, wired CarPlay, wireless CarPlay, and accessory-produced location
  source labels.

Every trace has ground-truth occurrence intervals and branch decisions. Raw field
traces remain ignored and private; tracked derivatives must be deliberately
redacted and licensed.

The first tracked B2 floor is executable under
[`benchmarks/map-matching/`](../../benchmarks/map-matching/README.md). Six
synthetic fixtures contain 23 observations and cover the listed gap bands,
stacked geometry, a parallel surface/expressway pair at multiple accuracy bands,
repeated occurrences, a noisy wrong branch, tunnel reacquisition, reordered
stale timestamps, and all four source labels. The
shared Swift evaluator reports edge and occurrence correctness, gap durations,
and named safety failures. Its nearest-edge negative control intentionally
ignores heading, transitions, occurrences, age, and source; a passing replay
means it reproduced the fixture's expected failures deterministically.

The first Meili adapter boundary is also executable without a live CI call. It
posts `trace_attributes` with `shape_match=map_snap`, increasing point times,
`interpolation_distance=0`, and one disclosed global `gps_accuracy` and
`search_radius` derived from the trace. The response must retain `osm_changeset`,
OSM way, begin/end OSM nodes, digitized direction, and the one-to-one
`matched_points` fields. Provider edges then expand to exact same-dataset Kaido
edges; repeat traversal is preserved and an observation at a translated segment
boundary stays ambiguous.

For the pinned Valhalla 3.8.2 serializer, `edge.end_osm_node_id` alone does not
materialize the `end_node` JSON object. The request also includes `node.type` to
activate the node category; the end OSM node ID remains the identity field and
the diagnostic node type is not used for matching.

Meili exposes `matched`, `interpolated`, or `unmatched` plus distance, but no
calibrated confidence and no RoutePlan occurrence. The bridge therefore emits
at most `LOW`, and the shared evaluator correctly reports occurrence identity as
unavailable. Reordered observed time is rejected instead of silently sorted,
because the official API requires an increasing time sequence. The adapter is a
batch oracle, not an online safety matcher.

The first ignored same-snapshot window ran five reviewed entrance chains across
three controlled graph-derived accuracy bands. The 15 fixtures contain 195
observations per repeat; three repeats made 45 provider requests. Reports were
value-identical. Edge top-1 was 65/65 for exact points, 65/65 for 5-meter
displacement with 10-meter declared accuracy, and 62/65 for 10-meter displacement
with 20-meter declared accuracy. All three LOW misses occurred at the Tomigaya
entrance mouth and occurrence remained 0/195. These are protocol and identity
metrics, not phone, CarPlay, tunnel, or production calibration claims.

The first route-aware Swift online Viterbi prototype is executable through the
same CLI and evaluator. On the six tracked fixtures it is repeat-identical with
18/23 edge top-1, 21/21 occurrence, and zero named safety failures. Its five
non-top-1 results are abstentions or delayed commitment on the exact cases where
nearest-edge produced unsafe HIGH output.

On the same private entrance window, Swift produced 190/195 edge top-1 and
195/195 occurrence hypotheses. All five non-top-1 points were LOW abstentions
with no selected directed edge. Meili produced 192/195 and 0/195 respectively;
two of its three Tomigaya misses selected a wrong ordinary-road edge at LOW and
one stayed ambiguous. Track edge coverage, wrong selections, abstentions, and
occurrence accuracy separately; top-1 alone would hide the safer tradeoff.

The same algorithm now runs only through the public incremental
`RouteMatcherSession`; the replay path is an adapter over that session rather
than a second batch implementation. Six lifecycle/complexity tests prove
stream/batch parity, stale-state immutability, reset/restart behavior, invalid
receive-order rejection, spatial exclusion of 100 distant edges, and a
configurable seven-state cap over 200 repeated occurrences. KR-S16 additionally
projects matcher confidence and occurrence output into `NavigationEngine`.
These are deterministic architecture gates, not latency or battery evidence.

The Apple input boundary is also executable. Nine focused tests drive
`CoreLocationObservationAdapter` through source-provenance separation, explicit
wired/wireless field cohorts, software-simulation policy, invalid/future fixes,
motion-field sanitization, callback order, a stale no-signal delivery, receive-
time reversal, and `RouteMatcherSession`. The system source reader uses
`CLLocation.sourceInformation`; deterministic tests inject source facts because
desktop-created locations are not iPhone/head-unit evidence.

The privacy/performance calibration boundary is executable too. Thirteen tests
cover the in-memory `PRIVATE_RAW_LOCATION` trace, coordinate-free scalar report,
exact snapshot/matcher/device/transport scoping, annotation validity, held-out
floor, false-`HIGH` blocking, categorical reliability bins, nearest-rank p95,
synthetic/simulated exclusion, and the measured Apple-adapter-to-matcher path.
The default 30 held-out samples per observed cohort is a provisional minimum,
not a release threshold. `STATISTICAL_FLOOR_MET_NOT_RELEASE_APPROVAL` explicitly
does not promote a route or confidence policy. The internal iPhone app now
provides a foreground-only capture harness around this path. It validates the
exact review-only K7 candidate corridor, requests location only after explicit
run metadata, rejects simulated fixes, retains raw trace data only in memory,
and emits no more than a coordinate-free report. No real device trace has run
yet.

### B3: guidance fixtures

For each critical movement, record deterministic prompt anchors and the same
structured guidance in `ja-JP`, `zh-Hans`, and `en`. Test presentation snapshots,
not acoustic quality, in CI. Pronunciation and audio interruption require device
tests.

## Surface-router test

### Hard gates

A candidate fails a supported entrance if any of these occurs:

- the route terminates at an IC centroid, wrong carriageway, wrong ramp, or
  unsafe stopping point rather than the directed approach anchor;
- it enters any expressway before the selected transition;
- it reaches a facility direction that cannot join the selected route;
- it crosses a forbidden toll-domain boundary;
- returned geometry cannot be unambiguously bound to the approach anchor;
- the provider cannot disclose a failure and instead returns a misleading
  success.

The supported entrance set requires a 100% hard-gate pass. Failure may shrink the
released set or trigger a provider change; it cannot be averaged away by good ETA.

Graph coverage is part of fixture validity. If route samples fall outside the
reviewed directed graph, or the graph cannot resolve one continuous topology,
the inspection fails closed. Diagnostic fallback matches may still be retained
for local analysis, but they cannot assert that an expressway or toll boundary
was actually crossed. A conclusive crossing claim requires one unambiguous,
continuous inspected path.

### Recorded metrics

- request success and error class;
- cold and warm response latency;
- directed-graph inspection latency, recorded separately from provider latency;
- route distance and ETA;
- last-500-meter maneuver count and decision complexity;
- distance from final geometry to the directed anchor;
- unintended expressway-edge count;
- result stability across repeated requests and departure times;
- online, offline, rate-limit, licence, and retention constraints.

The surface feasibility inspector still searches its bounded graph directly;
its latency is evidence-tool telemetry, not a production matcher budget. The
separate live matcher session now has a fixed-grid corridor index and synthetic
tests proving that distant roads are excluded from an observation query and
active occurrence states are capped. Benchmark that implementation on the
eventual device matrix while retaining the same fail-closed topology semantics.

### Accepted implementation direction

Keep the provider boundary and use Valhalla as the first shared open-source
surface-routing and map-matching oracle. It provides runtime costing, exact
provider-selected OSM identity, Japan administration context, and HMM matching
in one portable engine. Swift remains the authority for the RoutePlan, entrance
compatibility, recovery, tunnel progress, and guidance. OSRM and GraphHopper
remain independent baselines so the decision does not overfit Valhalla. MapKit
remains useful for geographic presentation and any bounded entrance whose opaque
path independently passes every gate; it is not the default path-identity source.

The current private evidence does not satisfy the MapKit condition. A Route 4
up pilot passed its same-side and cross-direction batches, but its approach from
a nearby incompatible down entrance failed all three runs: Route 20 and Route 4
are vertically stacked, and the MapKit geometry did not identify which level it
used. This is `RETEST` for MapKit's surface role, not evidence that the provider
actually took the expressway. The Valhalla probe therefore retains its own
selected edge sequence, using `trace_attributes` plus `shape_match=edge_walk`;
rematching MapKit output is not a substitute.

The public-service protocol probe first established the response shape without
claiming a hard-gate pass. The follow-up private build closes that gap: Valhalla
3.8.2 tiles and the Kaido graph were generated from one pinned extract, assigned
the same dataset ID, and tested through the production hard-gate types. Across
three runs per Shinjuku origin, all nine candidates were accepted. The translated
paths initially contained 1, 8, and 44 Kaido edges for same-side,
cross-direction, and nearest-incompatible origins respectively, with no
unmatched, ambiguous, or disconnected selected edges. The first build explicitly
disabled admin enrichment because a regional extract cannot close Japan/Tokyo
polygons. A later manifest-bound rebuild uses a complete same-day Japan admin
input and pinned timezone data. It reports `JP`, Tokyo state `13`, and
`drive_on_right=false`; all nine hard-gate runs remain accepted, with translated
path counts of 1, 8, and 84 after Japanese driving-side and country costing take
effect. This is a bounded path/admin feasibility pass, not a released entrance
or final provider choice.

The OSRM comparator now passes the same bounded path gate through its public
Swift adapter. Its first default-car build correctly failed because every Tokyo
step reported right-side driving. A manifest-bound LAB_ONLY rebuild supplies
left-side context through OSRM's official location-dependent data mechanism and
sets `--data_version 2026072101`; missing or drifting response identity is a hard
failure. `annotations=nodes` produced complete 1-, 8-, and 44-edge paths for the
three Shinjuku origins. Across three public-CLI runs per origin, all nine were
accepted with no unmatched, ambiguous, or disconnected edge. This establishes
OSRM as an independent surface baseline, not a route-plan owner or released
Japan data build.

The GraphHopper 11.0 comparator now passes the same boundary through a third
public Swift adapter. The first bounded import correctly failed build identity
because `/info.data_date` was the Unix epoch after extraction had removed the
source PBF replication timestamp. The accepted manifest restores the known
source header timestamp and binds it with the JAR, JRE digest, profile, graph
cache, and Kaido graph checksums. Import-time and response-time simplification
are disabled. Aligned `edge_key`, `osm_way_id`, and `country` path details cover
every point-pair and translate into complete 1-, 8-, and 44-edge Kaido paths.
Across three public-CLI runs per origin, all nine were accepted with one path
variant and no unmatched, ambiguous, or disconnected edge. GraphHopper
navigation driving-side output remains excluded from product guidance.

The next private expansion used one source PBF and Kaido graph for Hatsudai-
minami -> C2 inner, Tomigaya -> C2 outer, Ariake -> Bayshore east, Rinkai-
fukutoshin -> Bayshore west, and Ooi -> Bayshore east. Each final engine window
passed 45/45 requests, for 135/135 across the three engines. GraphHopper and OSRM
selected nearly identical distances. Valhalla selected materially longer but
still hard-gate-valid ordinary-road routes for several nearest-incompatible
origins. Those differences require path and field review; shortest is not a
safety verdict.

This expansion also found two adapter-level requirements. GraphHopper six-digit
geometry may locally fit multiple very short same-way segments, so translation
now accepts it only when whole-path continuity leaves one unique directed-edge
sequence. Valhalla destinations now carry the reviewed heading and tolerance and
set `node_snap_tolerance=0`; otherwise a stacked-road anchor can correlate to the
wrong direction or lose the final fractional edge at a nearby intersection. True
parallel ambiguity still fails closed.

Daikoku-futo Bayshore east remains outside the fixture set. The operator page
confirms directional access at the named complex, but a page center is not a
directional entrance mouth and the current OSM near-center chain does not yield
one reviewed Bayshore-east transition. Product data must identify the exact
mouth; it cannot manufacture a connection to complete a target count.

## Matcher test

### Hard gates

- zero false `HIGH`-confidence branch commits in the safety corpus;
- no backward occurrence jump caused by repeated geometry;
- no `STRICT_ROUTE` entry from geofence-only evidence;
- no branch commit inside a no-observation tunnel gap;
- correct route/deviation classification after the evidence threshold is met;
- explicit `LOW` or `LOST` state while candidates remain unresolved;
- same deterministic result for the same trace, snapshot, and configuration.

### Quality metrics

- directed-edge top-1 and top-k accuracy;
- route-occurrence accuracy;
- branch-decision precision and recall;
- false high-confidence commits;
- ambiguity duration;
- signal-reacquisition time and distance;
- negative log likelihood or equivalent path score;
- confidence calibration using Brier score and reliability bins;
- per-fix CPU time and peak memory.

Accuracy without calibration is insufficient. A matcher that is wrong but
uncertain may degrade safely; a matcher that is wrong and reports `HIGH` fails.

### Algorithms under comparison

1. nearest directed edge: negative control;
2. generic HMM result from Valhalla Meili;
3. generic OSRM and GraphHopper match results;
4. Kaido HMM using distance, heading, time, graph transition, and route prior;
5. Kaido HMM plus calibrated Core Motion/accessory-source evidence.

Use the same candidate radius bands and replay points where the engine allows it.
Document unavoidable differences instead of normalizing them away.

## Strict-route and recovery test

Generic routers are not expected to pass strict route semantics; they act as
negative controls that demonstrate where waypoint routing differs.

Required assertions:

- every requested occurrence remains ordered and unique;
- loops and repeated edges survive compilation and export;
- an illegal movement blocks compilation;
- recovery selects a named later occurrence in the original plan;
- no recovery path takes an exit when a released rejoin exists;
- `FINISH_DRIVE` uses a declared future egress option;
- closures and external boundaries are hard constraints;
- all decisions are reproducible from snapshot and inputs.

Recovery candidates are ranked lexicographically by validity, route preservation,
risk, distance, and time. The test report prints the whole cost vector, not only a
single opaque score.

## Provisional performance budgets

These are spike budgets, not release claims. Measure them on the oldest device in
the eventual support matrix and revise with evidence.

| Operation | Initial p95 budget | Reason |
|---|---:|---|
| load released Shuto snapshot | 1 s cold | ready before route review completes |
| compile a saved route | 100 ms | no visible authoring delay |
| evaluate one location observation | 50 ms | comfortably below normal location cadence |
| compute recovery candidates | 250 ms | early enough to prepare the next safe prompt |
| render a presentation snapshot | 16 ms target, no correctness dependency | smooth UI without tying navigation state to frames |

Missing a performance budget triggers profiling. It never permits weakening a
safety or route-preservation assertion.

## Test implementation

### Pure Swift

- Use a Swift package for `KaidoDomain`, routing, navigation, and the portable
  scenario adapter.
- Use Swift Testing for parameterized domain/replay suites.
- Use XCTest/XCUIAutomation for UI, performance baselines, and CarPlay simulator
  integration where Swift Testing is not the documented fit.
- Inject clocks, locations, provider responses, restrictions, and voice output.
- Run pure tests from the command line without an iOS simulator.

### Provider probes

Each provider adapter emits one normalized record:

```text
provider and version
request inputs and timestamp
status and raw error class
candidate polyline reference
normalized steps
distance and ETA
highway/toll indicators if available
anchor-binding result
hard-gate results
latency and environment
retention/licence classification
```

Do not commit raw provider payloads until retention and redistribution rights are
reviewed. A report may keep scalar metrics and hashes when allowed.

The current Swift runner fails closed when the graph inspection is missing. An
explicit provider error passes only `HONEST_PROVIDER_STATUS`; the entrance run
still fails. A success response with zero candidates is an invalid response.

### Device and field

- Driver drives; passenger or automated logger observes.
- Record iPhone model, OS, mount, wired/wireless CarPlay, head unit, location
  source information, timestamps, and configuration hash.
- Record wired/wireless as a passenger-declared field configuration and Core
  Location external-accessory/simulation flags as separate runtime evidence.
- Compare phone-only and accessory-produced fixes separately.
- Never tune using a test drive and report the same drive as independent proof.
- Keep a held-out field route for the release gate.

## Report shape

Every bake-off report begins with hard gates:

```text
candidate
role under test
version and licence snapshot
fixtures attempted / passed / failed
hard-gate failures with fixture IDs
quality metrics
performance metrics
operational and data risks
decision: KEEP | KEEP_AS_ORACLE | RETEST | REJECT_FOR_ROLE
```

A weighted feature score can summarize survivors, but it cannot override a hard
gate.

## Execution order

1. **Complete:** implement the pure Swift portable-scenario adapter and make the
   current 56 scenarios with 369 semantic assertions executable at L1/L2. KR-S16
   crosses the incremental matcher-to-navigation boundary; KR-S17 crosses
   resolved progress through frame planning, the prompt ledger, and projection;
   KR-S18 crosses HIGH Swift matcher along-edge progress through exact route
   geometry to that same guidance path without using lateral residual;
   KR-U01 crosses the parked expert-editor cursor and exact RoutePlan compilation
   boundary; KR-U02 adds reviewed closed-lap candidate matching, value
   duplication with fresh occurrence IDs, and grouped undo; KR-U03 adds
   parked-only freehand-corridor ambiguity resolution without giving gesture
   matching occurrence authority; KR-U04 through U09,
   KR-U10 through U12, and KR-U14 cross the shared presentation projection
   boundary, including one released junction-view definition shared by phone and
   CarPlay and localized accessibility semantics with non-color branch/lane
   cues; KR-U13 carries direction-first entrance selection and rejected-nearer
   reasons into an iPhone-intended explanation without giving UI ranking
   authority; KR-D25 round-trips one provenance-covered navigation release
   artifact and rejects unknown artifact schemas before runtime.
2. **Complete for the first five graph-bound fixtures:** the fixture format,
   graph-binding validator, normalized result, offline hard-gate
   evaluator, MapKit candidate adapter, and synthetic directed-road graph
   inspector plus local live-probe command are complete. The private Iikura
   vertical slice has passed a three-run scalar batch per origin but remains
   `RETEST`. The inspector now compares observed sample displacement with
   directed graph travel distance; a synthetic longer-detour case passes while
   an equal-geometry parallel-edge case remains ambiguous. The private Shibakoen
   outer pilot then passed all three same-day origin batches without loosening
   its ambiguity gate, but it exposed a temporal-movement data gap and still
   remains `RETEST`. Build the reviewed ten-entrance corpus, repeat all three
   origins for cross-time stability, aggregate separate scalar windows, profile
   longer inspections, and promote only evidence whose licence, temporal-rule,
   and field-review gates pass. A later same-day window kept all six Iikura and
   Shibakoen origin batches hard-gate clean, but Shibakoen cross-direction changed
   from a 468 m accepted route to 143 m, proving that one internally stable batch
   cannot establish cross-window stability. The private Shibuya pilot then
   passed all three origin batches on a complete graph. The private Shinjuku up
   pilot passed its short same-side and cross-direction batches, while its
   Hatsudai nearest-incompatible batch failed 0/3 with 19 stacked-road ambiguous
   edges per run. Keep the failure; it is the first evidence that geometry-only
   provider output cannot satisfy the whole corpus. The next expansion binds
   Hatsudai-minami, Tomigaya, Ariake, Rinkai-fukutoshin, and Ooi to one exact
   surface/transition/expressway chain. Daikoku-futo remains blocked on exact
   directional-mouth evidence rather than being inferred from the named complex.
3. **Complete for the bounded path protocol:** shared-snapshot Valhalla tiles, exact
   OSM way/node/direction translation, partial-edge trimming, and the actual
   Shinjuku three-by-three hard-gate comparison are executable. The Swift core
   rejects mismatched datasets, missing/ambiguous paths, reversed direction,
   repeated edges, and discontinuity.
4. **Complete for the implementation boundary:** a checksummed build-manifest
   schema and Swift validator bind source, image, tiles, admin/timezone databases,
   Kaido graph, dataset identity, and observed Tokyo driving side. The private
   Japan-admin build passes structural validation and intentionally fails release
   validation only on declared lab blockers. The bounded Valhalla provider,
   response normalizer, edge-walk sequence, and URLSession transport are
   implemented with deterministic transport fixtures. A supervised local HTTP
   window then passed all three origins three times through the public CLI, with
   one resolved path variant per origin and no unmatched, ambiguous, or
   disconnected selected edges. Long-running service operations, ODbL
   distribution review, broader coverage, and field evidence remain open.
5. **Complete for the bounded OSRM baseline:** the response normalizer requires
   manifest-bound `data_version`, left-side steps, full GeoJSON, and ordered OSM
   nodes. The node-pair translator rejects missing, parallel, repeated, and
   cross-dataset paths. A supervised Shinjuku 3x3 window passed through the
   public URLSession adapter. Release-quality administration, broader coverage,
   operations, distribution review, and field evidence remain open.
6. **Complete for the bounded GraphHopper baseline:** `/info` and `/route` are
   manifest-gated; unencoded unsimplified point-pairs carry aligned directional
   edge-key, OSM-way, and country detail; the complete point path must resolve
   to one unique Kaido directed-edge sequence. A supervised Shinjuku 3x3 window passed through the public
   URLSession adapter. Timestamp-build scripting, broader coverage, operations,
   distribution review, and field evidence remain open.
7. **Complete for the five-entrance three-engine window:** each engine passed
   45/45 final requests on one shared snapshot. Valhalla route destinations now
   bind reviewed heading/tolerance and disable node snapping; provider route
   differences remain a field-review task, not a reason to weaken hard gates.
8. **Complete for the external oracle boundary:** the schema, six-fixture
   synthetic replay corpus, 23-observation ground truth, shared evaluator, CLI,
   and deterministic nearest-edge negative control are executable. The
   manifest-bound Meili request/normalization/translation bridge is deterministic
   and deliberately LOW-confidence. Its first private same-snapshot controlled
   window made 45 requests and recorded repeat-identical 192/195 edge top-1,
   three Tomigaya entrance-mouth misses, and the expected 0/195 occurrence result.
9. **Partial complete:** the route-aware Swift online Viterbi prototype, both
   tracked/private comparisons, a fixture-independent incremental session,
   version-bound corridor, spatial index, bounded state beam, vertical KR-S16
   scenario, Core Location observation/provenance adapter, private trace recorder,
   scoped reliability evaluator, timed calibration session, and occurrence-bound
   distance bridge are executable. The `NavigationSession` actor now serializes
   that matcher, engine, bridge, and one-shot emission into atomic updates and
   rejects mismatched runtime composition. KR-S18 proves that only HIGH along-edge
   progress on the exact RoutePlan corridor becomes DecisionZone distance; the
   lateral matcher residual is never route progress.
   The foreground-only internal iPhone capture harness now executes the real
   delegate-to-adapter-to-matcher path against the exact review-only K7 candidate
   corridor without persisting raw coordinates or claiming navigation authority.
   Next run the target device matrix and collect independently annotated held-out
   evidence; no current test substitutes for that field work.
10. **Partial complete:** released frame semantics live in `KaidoDomain`, and the
    pure `GuidanceFramePlanner` selects a most-actionable, non-regressing frame
    from fresh resolved occurrence/distance input. `NavigationEngine` owns the
    prompt ledger and one-shot emission; `KaidoPresentation` projects that frame
    into phone, CarPlay, and independently selected voice values. KR-S17 executes
    planning from resolved progress, including no catch-up speech and no
    restoration replay. KR-S18 adds the deterministic Swift matcher-to-distance
    bridge. The internal iPhone shell now adds a synthetic, text-only KR-U05/KR-U11
    projection that keeps interface and voice locales independent and preserves
    the Japanese sign and shield without acquiring speech authority. It also
    executes KR-U06/U07/U08/U12 through a synthetic driving surface: a stale LOW
    engine observation remains estimated and realtime-unconfirmed, a moving
    DecisionZone locks editing, and engine-owned Finish selection names one
    released synthetic exit before branch guidance. A fourth state crosses
    KR-U09/KR-U10/KR-U14 by changing only engine-owned surface ownership and rendering
    one immutable occurrence-bound junction definition with exact path and lane
    values on iPhone. The same actual panel now projects localized accessibility
    labels, non-color branch/lane cues, a tested 4.5:1 critical text contrast
    floor, and a single-column accessibility Dynamic Type layout. Standard and
    AXXXL local XCUITests cover this bounded panel; they do not instantiate
    CarPlay or qualify the full app. Next add production corridor/DecisionZone
    construction and calibration, then bind actual `NavigationSession` state to
    the SwiftUI phone renderer, followed by full-app accessibility review, the
    `CPMapTemplate` adapter, and audio lifecycle.
11. **Partial complete:** the snapshot-bound `ExpertRouteEditorSession` exposes
    only legal choices for the exact incoming approach/JCT, creates fresh
    occurrences across cycles, locks moving-time interaction, supports grouped
    parked undo, and requires an explicit directional exit before RoutePlan
    compilation. Its reviewed lap templates expose candidates only for exact
    authored closed sequences; duplication copies semantic values under fresh
    occurrence IDs. `ParkedCorridorResolutionSession` separately requires an
    exact snapshot/current-cursor match, never authors from zero or one candidate
    automatically, and keeps ambiguity pending until an explicit parked choice.
    KR-U01 through KR-U03 execute these boundaries. The internal iPhone
    preview now renders the session snapshot, stable choice IDs, and lap
    candidates from a synthetic catalog, preserves repeated occurrences, and
    gates compilation through the session. Its synthetic Canvas is covered by a
    real XCUITest drag but supplies only a fixed two-choice match. Next build
    released editor catalogs, reviewed layout matching and calibrated snapping
    tolerances, production labels/topology rendering, and full accessibility
    validation without moving graph logic into UI.
12. Perform passenger-observed tunnel and entry tests only after synthetic and
   simulator gates pass.

The next provider tasks are exact cross-engine route-difference review, a
directional-mouth evidence decision for Daikoku-futo, and eventual expansion of
the released facility corpus. The thin internal iPhone capture harness around the
memory-only logger is complete. The next evidence task is passenger-safe held-out
runs and performance profiles around entrance mouths, stacked roads, and tunnel
reacquisition. This is not yet product navigation and not a C++ or Rust rewrite.

## Sources checked 2026-07-23

- [Swift Testing](https://developer.apple.com/xcode/swift-testing/)
- [XCTest and XCUIAutomation](https://developer.apple.com/documentation/xctest)
- [Apple `CLLocation` source information](https://developer.apple.com/documentation/corelocation/cllocation/sourceinformation)
- [Apple external-accessory location source](https://developer.apple.com/documentation/corelocation/cllocationsourceinformation/isproducedbyaccessory)
- [Apple software-simulation location source](https://developer.apple.com/documentation/corelocation/cllocationsourceinformation/issimulatedbysoftware)
- [Valhalla Meili](https://valhalla.github.io/valhalla/meili/)
- [Valhalla map-matching API](https://valhalla.github.io/valhalla/api/map-matching/api-reference/)
- [Valhalla 3.8.2 trace-attribute JSON serializer](https://github.com/valhalla/valhalla/blob/3.8.2/src/tyr/trace_serializer.cc)
- [Valhalla route locations, heading, and heading tolerance](https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/)
- [Valhalla 3.8.2 node-snap configuration](https://github.com/valhalla/valhalla/blob/3.8.2/scripts/valhalla_build_config)
- [Valhalla status API](https://valhalla.github.io/valhalla/api/status/)
- [Valhalla Mjolnir tile build guide](https://valhalla.github.io/valhalla/mjolnir/getting_started_guide/)
- [Valhalla dataset and build identification](https://valhalla.github.io/valhalla/concepts/change-identification/)
- [Timezone Boundary Builder data licence](https://github.com/evansiroky/timezone-boundary-builder/blob/master/DATA_LICENSE)
- [OSRM route and match services](https://github.com/Project-OSRM/osrm-backend)
- [OSRM HTTP API and node annotations](https://github.com/Project-OSRM/osrm-backend/blob/0844e3af77896d11998ef6db356a553056652c8e/docs/http.md)
- [OSRM location-dependent left-driving test](https://github.com/Project-OSRM/osrm-backend/blob/0844e3af77896d11998ef6db356a553056652c8e/features/car/side_bias.feature)
- [GraphHopper 11.0 release](https://github.com/graphhopper/graphhopper/releases/tag/11.0)
- [GraphHopper 11.0 local HTTP API](https://github.com/graphhopper/graphhopper/blob/69e50f6e2cfaf0a8e69752df9953ee5f1ac276a4/docs/web/api-doc.md)
- [GraphHopper directional `edge_key` detail](https://github.com/graphhopper/graphhopper/blob/69e50f6e2cfaf0a8e69752df9953ee5f1ac276a4/core/src/main/java/com/graphhopper/util/details/EdgeKeyDetails.java)
- [GraphHopper `osm_way_id` encoded value](https://github.com/graphhopper/graphhopper/blob/69e50f6e2cfaf0a8e69752df9953ee5f1ac276a4/core/src/main/java/com/graphhopper/routing/ev/OSMWayID.java)
- [Osmium output header options](https://docs.osmcode.org/osmium/latest/osmium-output-headers.html)
- [Newson and Krumm HMM map-matching paper and public test data](https://www.microsoft.com/research/publication/hidden-markov-map-matching-noise-sparseness/)
