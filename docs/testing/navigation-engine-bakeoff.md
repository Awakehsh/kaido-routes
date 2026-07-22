# Navigation engine bake-off

**Status:** B0 is executable. B1 has a versioned fixture schema, synthetic
three-origin fixture, provider-neutral hard-gate runner, MapKit adapter, and a
pure Swift directed-road graph inspector plus an explicit local live-probe
command. No real entrance fixture is released; private provider output remains
outside the repository.

**Checked:** 2026-07-22

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

### Initial decision rule

Use MapKit for the first app spike if all released entrance fixtures pass. Keep
Valhalla as the first fallback candidate because it provides open routing,
runtime costing, and map matching in one portable engine. OSRM and GraphHopper
remain independent baselines so the decision does not overfit one open-source
implementation.

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
   existing 16 scenarios executable at L1/L2.
2. **In progress:** the fixture format, normalized result, offline hard-gate
   evaluator, MapKit candidate adapter, and synthetic directed-road graph
   inspector plus local live-probe command are complete. The private Iikura
   vertical slice has passed a three-run scalar batch per origin but remains
   `RETEST`. The inspector now compares observed sample displacement with
   directed graph travel distance; a synthetic longer-detour case passes while
   an equal-geometry parallel-edge case remains ambiguous. The private Shibakoen
   outer pilot then passed all three same-day origin batches without loosening
   its ambiguity gate, but it exposed a temporal-movement data gap and still
   remains `RETEST`. Build the reviewed ten-entrance corpus, repeat all three
   origins for cross-time stability, profile longer inspections, and promote
   only evidence whose licence, temporal-rule, and field-review gates pass.
3. Run Valhalla, OSRM, and GraphHopper against the same surface fixtures.
4. Implement the nearest-edge negative control and replay harness.
5. Add Valhalla Meili as the first matcher oracle.
6. Implement the route-aware Swift HMM and compare calibration.
7. Add SwiftUI phone presentation, then the CarPlay adapter.
8. Perform passenger-observed tunnel and entry tests only after synthetic and
   simulator gates pass.

The next coding task is the evidence-backed remainder of step 2, not an iPhone
screen.

## Sources checked 2026-07-22

- [Swift Testing](https://developer.apple.com/xcode/swift-testing/)
- [XCTest and XCUIAutomation](https://developer.apple.com/documentation/xctest)
- [Valhalla Meili](https://valhalla.github.io/valhalla/meili/)
- [Valhalla map-matching API](https://valhalla.github.io/valhalla/api/map-matching/api-reference/)
- [OSRM route and match services](https://github.com/Project-OSRM/osrm-backend)
- [GraphHopper routing and map matching](https://github.com/graphhopper/graphhopper)
- [Newson and Krumm HMM map-matching paper and public test data](https://www.microsoft.com/research/publication/hidden-markov-map-matching-noise-sparseness/)
