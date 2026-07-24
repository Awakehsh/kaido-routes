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
pure Swift feasibility core and an internal SwiftUI iPhone preview app. The app
links the local domain, routing, navigation, and presentation modules and renders
the tracked full-network and K7 Route Atlas assets. It remains explicitly
review-only: it has no released route bundle, measured position, active-route
highlight, voice, or CarPlay scene. The repository still has no production road
database or released provider integration. It includes a
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

The platform-light matcher-to-guidance-to-presentation boundary is executable
end to end for the pure Swift core.
`KaidoDomain` owns released frame semantics, while `GuidanceFramePlanner` accepts
an already resolved occurrence and fresh distance-to-DecisionZone observation.
`GuidanceProgressBridge` accepts only a HIGH Swift matcher estimate with an exact
RoutePlan occurrence, directed edge, and along-edge fraction. It accumulates the
version-bound corridor geometry to a reviewed DecisionZone entry offset. The
matcher's `distanceMeters` remains the lateral point-to-road residual and is
never interpreted as route progress.
`NavigationEngine` selects the most actionable released anchor, prevents stage
regression, updates its prompt ledger, and emits a one-shot voice command.
`KaidoPresentation` then projects the same occurrence-scoped `GuidanceFrame` into
phone, CarPlay, and independently localized voice values. Japanese sign text and
route shields remain visible in every locale. An optional released
`JunctionViewDefinition` carries independently rendered normalized branch paths,
left-indexed lane semantics, and evidence metadata; it must match the frame's
snapshot, movement occurrence, route shields, and Japanese sign target before
phone or CarPlay can consume it. Estimated positions cannot render as measured,
unconfirmed passage cannot use a positive open-road state, moving decision zones
expose no route editing, and Finish drive names its compiled exit first. KR-S17
proves planning from resolved progress, KR-S18 proves the
occurrence-scoped Swift matcher distance bridge through the same planner,
ledger, and presentation projection, and KR-U14 proves the junction-view
ownership boundary. Production corridor construction,
DecisionZone calibration, production navigation-state SwiftUI rendering,
CarPlay entitlement, accessibility validation, audio, and physical head-unit
behavior remain unimplemented or unproven.

The parked expert-authoring boundary is executable independently of SwiftUI.
`ExpertRouteEditorSession` starts from one exact directional entrance and a
snapshot-bound reviewed catalog. Its cursor names the incoming approach and
junction complex, exposes only that decision point's legal choices, appends
fresh movement and outgoing-edge occurrences, supports reviewed cycles and
parked undo, and compiles only after an explicit directional exit choice. UI
code cannot submit a future decision's choice or edit while moving. KR-U01
executes this stateful boundary; the internal iPhone shell does not yet compose
the editor session, and real released editor catalogs, labels, topology
rendering, and accessibility remain pending.

The live pure-Swift composition boundary is also concrete. A `NavigationSession`
actor owns one RoutePlan-bound matcher session and `NavigationEngine`, converts
each accepted matcher estimate into the conservative location observation,
selects the released DecisionZone for the current anchor occurrence, runs the
distance bridge, and returns one atomic snapshot plus optional prompt emission.
Initialization rejects mismatched route, snapshot, corridor, zone, or guidance
identities. Matcher reset/restart clears temporal evidence without rewinding
navigation progress. The first app scene is now present, but Core Location
callbacks, `NavigationSession` composition, lifecycle persistence, background
execution, and audio remain Apple-adapter work.

The pre-runtime release boundary is now explicit as well.
`NavigationReleaseBundle` accepts only one active `NetworkSnapshot`, one valid
`RoutePlan`, one locally valid reviewed editor catalog, one complete matcher
corridor, occurrence-scoped DecisionZones and released guidance, and an optional
registry of released junction views. It reuses the same runtime-composition
validation as `NavigationSession`, then adds whole-bundle coverage: every planned
junction-movement occurrence needs exactly one DecisionZone and at least one
released guidance definition. Embedded junction views must match one registry
entry exactly, and registry orphans fail closed. Repeated graph entities remain
distinct because coverage is keyed by occurrence ID. KR-D18 executes this
boundary with synthetic data; it does not release a real route or dataset.

The renderer-neutral Route Atlas integrity boundary is executable too.
`RouteAtlasRelease` accepts one active snapshot, exact RoutePlan, released dated
topology slice, and separately released normalized layout. Layout nodes and topology edges
must have exact coverage; path endpoints and legal successor sets must match the
reviewed graph; topology route-entity identity is unique; and every RoutePlan
occurrence remains separately bound in exact order even when repeated
occurrences share one schematic segment. Coordinate crossings never author graph
connectivity, and the layout type contains no arbitrary display labels. Topology
and layout evidence IDs must resolve to explicit dated, licensed, role-matched
source records with pinned content SHA-256 values in the versioned Codable
release artifact. KR-D19 proves that one
visually invented connection blocks release. This verifies
internal consistency only: the repository still has no released real Shuto
topology slice or production atlas layout.

The full-network recognition layer is now data-derived instead of hand drawn.
`RouteAtlasContextBundle` accepts only `CONTEXT_ONLY` geometry with a matching
source record, current-state scope, CC BY 4.0 attribution and transformation
notice, reviewed source-archive SHA-256, fixed north-up projection, and exact
coverage counters. The pinned MLIT N06-2025 current-state archive produces 86
Shuto source features, 86 paths, 3,584 unsimplified JGD2011 `EPSG:6668`
vertices, and 26 route-name strings. Twenty-five operator names match directly.
The remaining source record is the 38-vertex `高速横浜環状北西線`; one dated,
checksummed operator-page reconciliation maps it to K7 Yokohama Northwest for
recognition only. This gives the presentation a recognizable
full-network frame but no
direction, legal junction movement, selectable topology, RoutePlan occurrence,
position, or realtime authority. KR-D20 proves that promotion to navigation
authority fails closed. The source date is 2025-12-31, so the separately
reviewed operator map dated 2026-07-01 remains a later currentness comparison,
not copied data or proof that a navigable topology is released.

A renderer-neutral recognition design now places Kaido-owned route-code
capsules only on source vertices whose MLIT route name has a direct or explicitly
reconciled match in the operator's current 26-route table. All 26 operator names
are represented with 28 marks. The deterministic standalone SVG is tracked with
visible MLIT / CC BY 4.0 attribution and explicit `REVIEW_ONLY` and
`navigation_authority=false` metadata. The recognition layout is non-selectable
and non-navigable; it improves familiar network recognition without pretending
that route direction or connectivity has been released.

The first real-source directed atlas candidate is also tracked without promoting
it to release data. It binds the K7 Northwest up direction from the exact
Yokohama Aoba entrance identity to the Yokohama Kohoku exit identity, reverses
all 38 retained MLIT centerline vertices into RoutePlan order, and resolves four
dated, checksummed MLIT/operator sources. The candidate remains
`OFFICIAL_CHECKED`: the MLIT line has no carriageway, ramp, or legal-successor
identity, operator diagrams are not distributable layout assets, and field,
production-layout, and realtime reviews remain open. KR-D21 proves that only
`UNRELEASED_ATLAS_TOPOLOGY_EVIDENCE` and `UNRELEASED_ATLAS_EVIDENCE` block it.

The next K7 candidate adds an isolated ODbL-derived directed database from the
pinned Geofabrik Kanto 2026-07-21 PBF. It preserves 13 exact one-way OSM ways
from the Yokohama Aoba toll-plaza split through the K7 Northwest up carriageway
to the Yokohama Kohoku exit terminal, plus the immediate K7 Yokohama North and
Daisan-Keihin alternatives at the two operator-reviewed divergences. All 257
retained nodes, the Aoba incoming/non-route split, and all three source-adjacent
motor-road connections at the Kohoku terminal remain explicit. Two are named
one-way Kawamuki Line carriageways; the third is an unnamed `tertiary` way
without an explicit `oneway` tag. A dated Yokohama City opening notice
identifies that third corridor as the temporary passage used at the 2020
opening. A current municipal page reports that surrounding infrastructure work
completed in March 2022 and the land-readjustment project ended in July 2023;
the final replotting map does not map that exact OSM way to a current road
identity. Its present physical status, legal direction, and permitted exit
movement therefore remain unconfirmed. Way tags, direction,
extraction bounds, source hashes, OSM timestamp, and reconstruction commands
remain explicit. A deterministic audit now proves exact source adjacency at 14
entry, route, divergence, and exit checkpoints with 19 outgoing successors and
no applicable turn-restriction relation. It deliberately reports legal review
as incomplete because the third surface way's current road-level direction and
movement remain unconfirmed. The tracked
[field-verification plan](docs/testing/k7-yokohama-kohoku-surface-field-verification.md)
and coordinate-free manifest validator make that gap executable without
committing raw field media. This closes the structured directed-candidate gap,
not release: topology and layout stay
`CANDIDATE` until independent lawful field/topology review, production layout,
attribution integration, and realtime review are complete. KR-D22 proves that
the internally coherent 13-occurrence, 15-edge artifact still fails release
with only the two unreleased-evidence issues. KR-D23 proves that source-complete
successor enumeration, a historic official identity, and later area completion
cannot substitute for current road-level legal review.

A Kaido-owned fixed-north-up schematic now replaces raw source geometry for a
second K7 candidate artifact. Its 15 visible segments bind one-to-one to the
same candidate topology edges, both expressway divergences are expanded, and
all 13 occurrence bindings remain exact. The layout visibly stops at the
Yokohama Kohoku exit terminal and renders none of the three source-adjacent
surface ways. Its generated SVG carries OpenStreetMap attribution. This is a
production-layout candidate, not released navigation evidence: KR-D24 requires
release validation to fail with only the two expected unreleased topology and
layout evidence issues.

The feasibility core currently executes portable scenarios for the following
hard properties that must remain proven as the product expands:

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
23. a HIGH route-aware matcher estimate exposes along-edge progress separately
    from lateral residual, and only an exact snapshot-, RoutePlan-, occurrence-,
    edge-, and DecisionZone-bound corridor may convert it into guidance distance.
24. parked route authoring starts from an exact directional entrance, exposes
    only the current incoming approach's reviewed choices, preserves cycles as
    fresh occurrences, rejects moving-time edits, and finishes only through an
    explicit directional exit.
25. phone and CarPlay consume one released, normalized junction-view definition;
    snapshot, movement occurrence, lane, route-shield, Japanese-sign, and evidence
    drift fail closed before any adapter renders an inset.
26. a navigation release bundle binds the active snapshot, RoutePlan, reviewed
    editor catalog, matcher corridor, every movement occurrence's DecisionZone
    and guidance, and any junction-view registry before runtime composition.
27. a Route Atlas exactly covers one reviewed topology slice, preserves every
    route occurrence, and rejects any visual connection absent from the graph.
28. full-network geographic context remains permanently non-navigable and fails
    closed on source, licence, projection, coverage, geometry, or authority
    drift.
29. a real official-checked directed atlas candidate remains blocked until both
    its topology evidence and production layout are explicitly released.

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
- [`Apps/KaidoRoutesApp/`](Apps/KaidoRoutesApp/README.md): internal SwiftUI
  iPhone shell, preview, and Simulator workflow.
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
swift run kaido-atlas validate \
  --source data/route-atlas/context/mlit-n06-2025-current-source.json \
  --context data/route-atlas/context/mlit-n06-2025-current-shuto-context.json
python3 scripts/validate_e2e.py
```

`swift test` executes the domain and simulation semantics in process. The CLI
prints a result for every scenario and assertion. The Python validator remains
an independent L0 check for the portable envelope, route-occurrence identity,
event ordering, evidence references, and assertion references.
`kaido-atlas validate-release --artifact <file>` decodes and validates a future
versioned topology/layout release artifact through the same source-registry and
graph-integrity gate; no real Shuto release artifact exists yet.

Generate or open the tracked iPhone project and run the internal preview:

```sh
xcodegen generate
open KaidoRoutesApp.xcodeproj
./scripts/run_ios_preview.sh
```

The Simulator app requires no device signing. It renders review-only assets and
cannot claim released navigation authority. See
[`Apps/KaidoRoutesApp/README.md`](Apps/KaidoRoutesApp/README.md) for Xcode,
Preview Canvas, regeneration, and test instructions.

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
