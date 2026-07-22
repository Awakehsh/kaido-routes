# Kaido Routes

Kaido Routes is a route-first driving navigation concept. Instead of asking only
where a driver wants to arrive, it lets the driver choose which legal roads and
junction movements they want to experience, then executes that exact ordered
route safely.

The initial scope is the Shuto Expressway on iPhone, with Apple CarPlay as a
future product surface. The broader product may later cover other distinctive
Japanese driving roads. The project is not affiliated with or endorsed by
Metropolitan Expressway Company Limited.

## Current status

This repository defines product, domain, evidence, and test contracts plus a
pure Swift feasibility core. It does not yet contain an iPhone/CarPlay app,
production road database, or released provider integration. It includes a
bounded MapKit feasibility adapter, an offline directed-road graph inspector,
surface-routing hard gates, an OSM selected-path translator, an offline evidence
CLI, an explicit local live-probe command, a scalar-only cross-window stability
comparator, a checksummed routing-build manifest, and a bounded Valhalla
provider/HTTP boundary plus independent bounded OSRM and GraphHopper providers;
no live provider call runs in deterministic tests. Five private directional
entrance fixtures are bound to exact surface, transition, and expressway edge
chains on one shared OSM snapshot. Valhalla, OSRM, and GraphHopper each passed
45/45 repeated live requests across those fixtures and three origin classes,
for 135/135 final requests. Valhalla is therefore the leading shared open-source
implementation candidate for bounded surface routing and the first external HMM
comparison oracle. It remains behind a provider boundary: Swift owns route
occurrences, strict execution, recovery, egress, confidence, and multilingual
guidance. OSRM and GraphHopper remain executable independent controls.

Valhalla destinations are constrained by the reviewed approach heading and
tolerance with node snapping disabled. OSRM requires a manifest-bound
`data_version`, left-side-driving steps, and a complete unambiguous ordered
OSM-node path. GraphHopper aligns unsimplified directional `edge_key` and
`osm_way_id` details to one unique whole-path Kaido edge sequence and rejects
epoch-valued or drifting road timestamps. Deterministic tests still make no live
provider call. Long-running service operations, ODbL distribution review,
broader road coverage, field evidence, exact Daikoku-futo directional-mouth
evidence, and entrance release remain pending.

The first deterministic map-matching replay floor is also executable. Six
tracked synthetic fixtures contain 23 receive-ordered observations with exact
ground-truth edge and occurrence intervals, branch decisions, stacked geometry,
parallel roads at multiple accuracy bands, repeated occurrences,
15/30/60-second gaps, tunnel reacquisition, stale reordered timestamps, and four
source labels. A deliberately weak nearest-edge control
reproduces its declared safety failures twice per fixture. This does not make
nearest-edge matching viable; it establishes the comparison contract that
Valhalla Meili and the route-aware Swift HMM must beat without any false
high-confidence safety commit.

The manifest-bound Valhalla Meili oracle boundary is now deterministic as well.
It sends bounded `trace_attributes` `map_snap` requests with increasing point
times, one explicit global accuracy/search-radius policy, and no interpolation
merging. Response edge identity must translate from the same dataset through OSM
way, begin/end node, and digitized direction before an observation can name a
Kaido edge. Repeated traversals remain repeated and a point on a translated
segment boundary remains ambiguous. Valhalla exposes match type and distance,
not calibrated confidence or RoutePlan occurrence identity, so the adapter emits
only `LOW` confidence and cannot authorize a branch commit. A real shared-snapshot
controlled replay window now exercises the public CLI against the pinned 3.8.2
service: five reviewed entrance chains, three graph-derived accuracy bands, 15
fixtures, 195 observations per repeat, and 45 provider requests. The reports
were repeat-identical and returned 192/195 edge top-1 overall: 65/65 for exact
points, 65/65 for 5-meter displacement with 10-meter declared accuracy, and
62/65 for 10-meter displacement with 20-meter declared accuracy. All three
misses were LOW-confidence points at the Tomigaya entrance mouth; occurrence
identity remained 0/195 by design. This validates the real protocol and identity
bridge, not phone accuracy, tunnel behavior, or a live production dependency.

The first pure-Swift route-aware online Viterbi prototype now runs through the
same evaluator. On the six tracked fixtures it is deterministic, preserves all
21/21 truth occurrences, and produces no named safety failure; its 18/23 edge
top-1 includes deliberate abstention on indistinguishable stacked and parallel
geometry. On the same private five-entrance window it produced 190/195 edge
top-1 and 195/195 occurrence hypotheses. All five non-top-1 results were LOW
abstentions with no selected edge, while Meili's three misses contained two LOW
wrong-edge selections and one ambiguity. This establishes Swift as the live
RoutePlan matcher direction and Meili as an offline edge oracle, not calibrated
field accuracy or a production-ready confidence model.

The matcher now also exposes a fixture-independent incremental
`RouteMatcherSession`. A version-bound RoutePlan corridor supplies directed
edges, explicit legal successors, and occurrence bindings; a fixed-grid spatial
index limits each observation to nearby edges, while a score beam and active
state cap bound repeated-lap growth. Batch and streamed results are identical on
all tracked fixtures. KR-S16 sends stale, post-gap, confirmed, and reset session
updates through `NavigationEngine`, proving that only fresh HIGH evidence can
advance an occurrence and that a matcher restart cannot move navigation
backward. `CoreLocationObservationAdapter` now converts Apple callback batches
into receive-ordered matcher observations, preserves raw source provenance,
rejects invalid, future, and software-simulated fixes by default, and keeps
field-declared wired/wireless calibration cohorts separate from what Core
Location can actually prove.

The device-evidence boundary is now executable without pretending that desktop
tests are field evidence. `CoreLocationMatcherCalibrationSession` measures the
actual adapter-to-matcher pipeline and builds an in-memory
`PRIVATE_RAW_LOCATION` trace; it performs no file I/O. The shared evaluator can
emit a coordinate-free scalar report with p95 timings and confidence reliability
bins only within one exact snapshot, matcher configuration, device configuration,
and declared transport context. Mixed configurations fail closed, and synthetic
or software-simulated samples can never satisfy the field statistical floor.
No iPhone/head-unit trace has been collected yet, so device performance and
confidence calibration remain unproven.

The platform-light guidance-to-presentation boundary is executable end to end.
`KaidoDomain` owns released frame semantics, while `GuidanceFramePlanner` accepts
an already resolved occurrence and fresh distance-to-DecisionZone observation.
`NavigationEngine` selects the most actionable released anchor, prevents stage
regression, updates its prompt ledger, and emits a one-shot voice command.
`KaidoPresentation` then projects the same occurrence-scoped `GuidanceFrame` into
phone, CarPlay, and independently localized voice values. Japanese sign text and
route shields remain visible in every locale, estimated positions cannot render
as measured, unconfirmed passage cannot use a positive open-road state, moving
decision zones expose no route editing, and Finish drive names its compiled exit
first. KR-S17 proves this pure Swift chain, but the adapter that derives remaining
DecisionZone distance from matcher/graph progress, SwiftUI, CarPlay entitlement,
accessibility, audio, and physical head-unit behavior remain unimplemented.

The feasibility core currently executes portable scenarios for twenty-two hard
properties that must remain proven as the product expands:

1. repeated road segments remain distinct ordered occurrences;
2. only legal directional junction movements can be authored and executed;
3. navigation stays honest when tunnel or stacked-road positioning is uncertain,
   keeps route-candidate resolution separate from raw fix quality, and requires a
   consistent post-gap window before resuming an exact occurrence;
4. a current-location recommendation selects a compatible directional entrance
   approach that is available at the predicted entry time, not merely the
   nearest IC name;
5. a deviation rejoins the active route plan instead of becoming a generic
   destination reroute;
6. Japanese, Simplified Chinese, and English guidance preserve the same physical
   sign target in both text and voice.
7. PA visits require an exact directional access-and-return path; operational
   closures skip a whole optional PA subgraph but block a required occurrence.
8. adding another reviewed lap copies values into fresh, contiguous occurrences
   instead of aliasing the first traversal;
9. a reviewed circuit template must contain every required route edge and
   boundary movement in order, including any separately named route used to
   close the circuit;
10. every strict route occurrence is classified against an allowed toll-domain
    policy, and external or unknown domains fail closed.
11. tariff selection requires exactly one `ACTIVE` version; proposed and retired
    versions remain visible evidence but cannot supply the payable amount.
12. deterministic guidance anchors emit once per occurrence, suppress duplicate
    location triggers, and remain independently eligible on a later lap.
13. a newly known blocking restriction during a drive activates a released
    rejoin to the existing RoutePlan without abrupt guidance or moving-time edits.
14. a CarPlay disconnect returns presentation to iPhone while the shared route
    occurrence and occurrence-scoped prompt ledger continue unchanged.
15. a versioned shared-route document preserves its network snapshot, evidence
    state, template intent, and every repeated or optional occurrence on import.
16. guided template parameters compile only through one exact approved,
    snapshot-bound variant whose required route components still validate.
17. an incremental matcher session cannot advance navigation on stale or first
    post-gap evidence, and resetting matcher evidence cannot move RoutePlan
    progress backward.
18. phone and CarPlay consume one occurrence and next-movement projection, while
    connection state changes only which surface is primary.
19. Japanese sign targets and route shields survive all three interface locales,
    while UI and guidance-voice languages remain independently selectable.
20. estimated or unresolved positions and realtime-unconfirmed road status retain
    conservative presentation semantics on every surface.
21. pre-drive review keeps actual distance, tariff distance, toll evidence, and
    live-passage evidence separate; moving decision zones cannot request route
    editing, and Finish drive names the compiled exit before branch guidance.
22. fresh resolved route progress chooses one released occurrence-scoped frame,
    skips obsolete catch-up prompts, never regresses after distance jitter, and
    sends voice only with a matching one-shot engine emission.

## Repository map

- [`docs/product/principles.md`](docs/product/principles.md): product promise and non-goals.
- [`docs/product/custom-route-builder.md`](docs/product/custom-route-builder.md): curated and expert route-authoring model.
- [`docs/architecture/domain-contract.md`](docs/architecture/domain-contract.md): stable route and road-network concepts.
- [`docs/architecture/journey-lifecycle.md`](docs/architecture/journey-lifecycle.md): surface access, entry recognition, recovery, and legal egress.
- [`docs/architecture/ios-navigation-architecture.md`](docs/architecture/ios-navigation-architecture.md): accepted Swift, CarPlay, routing, matching, and provider boundaries.
- [`docs/agents/context-architecture.md`](docs/agents/context-architecture.md): how coding agents should load and preserve context.
- [`docs/testing/e2e-strategy.md`](docs/testing/e2e-strategy.md): layered verification strategy.
- [`docs/testing/scenario-catalog.md`](docs/testing/scenario-catalog.md): behavior inventory and implementation order.
- [`docs/testing/navigation-engine-bakeoff.md`](docs/testing/navigation-engine-bakeoff.md): hard-gated comparison plan for surface routers and map matchers.
- [`docs/contributing/route-evidence.md`](docs/contributing/route-evidence.md): evidence gates for route data.
- [`docs/contributing/licensing.md`](docs/contributing/licensing.md): Apache-2.0 and third-party material boundaries.
- [`e2e/`](e2e/README.md): portable, machine-readable behavior scenarios.
- [`benchmarks/surface-routing/`](benchmarks/surface-routing/README.md): directional entrance fixtures and provider hard gates.
- [`benchmarks/map-matching/`](benchmarks/map-matching/README.md): deterministic matcher replay fixtures, evaluator, and negative control.
- [`Sources/`](Sources): platform-light Swift domain, routing, navigation,
  presentation, and scenario-adapter modules.
- [`Tests/`](Tests): Swift Testing suites that execute the portable scenarios.

`research/` is a local, ignored notebook for source discovery and raw analysis.
It is deliberately not part of the public repository. Verified conclusions must
be rewritten into a tracked contract or evidence record with direct source links.

## Documentation audiences

Tracked English Markdown, JSON scenarios, and code are the authoritative source
for coding agents and open-source contributors. Substantial project-owner
summaries may be rendered as self-contained Chinese HTML files on the Desktop.
Those HTML files are presentation snapshots rather than a second source of truth:
they should summarize and link to the tracked contracts, not define behavior that
the repository does not contain.

## Build and contract validation

The package uses only the Swift toolchain and Foundation. Run the executable
scenario suite and the independent schema validator:

```sh
swift test
swift run kaido-scenarios e2e/scenarios
swift run kaido-matcher-replay benchmarks/map-matching/fixtures/synthetic
python3 scripts/validate_e2e.py
```

`swift test` executes the domain and simulation semantics in process. The CLI
prints a result for every scenario and assertion. The Python validator remains
an independent L0 check for the portable envelope, route-occurrence identity,
event ordering, evidence references, and assertion references.

## Safety

Kaido Routes is for lawful route planning, driving assistance, and road-culture
discovery. On-road signs, police directions, and traffic controls always take
priority over the app. The product must not reward speed, lap time, unsafe phone
interaction, or attempts to evade enforcement.

## License

Kaido Routes is open-source software licensed under the
[Apache License 2.0](LICENSE). The licence permits commercial and noncommercial
use, modification, and distribution under its terms, including its notice and
patent provisions.

Separately identified third-party software, data, and assets remain under their
own terms. In particular, the project licence does not grant rights to operator
maps, traffic-service payloads, or an OSM-derived database.
