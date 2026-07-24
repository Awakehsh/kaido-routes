# iOS navigation architecture direction

**Status:** accepted and implemented for the platform-light feasibility core,
with the first internal SwiftUI iPhone composition target now present. The app
renders review-only Route Atlas assets and links the local domain, routing,
navigation, and presentation modules; it does not yet compose a released
`NavigationSession`, Core Location, voice, or CarPlay. The current bake-off
selects Valhalla as the leading shared implementation behind the bounded
surface-routing/oracle boundary and pure Swift for live RoutePlan matching,
subject to Apple-adapter, operations, and field evidence in
`docs/testing/navigation-engine-bakeoff.md`.

**Checked:** 2026-07-23

## Decision summary

Use a hybrid architecture:

1. Build the iPhone client in Swift.
2. Use SwiftUI for parked iPhone workflows and a UIKit/CarPlay scene adapter for
   the in-car surface.
3. Keep the route-first domain, strict route compiler, journey state machine,
   recovery, guidance, and route-aware matcher in platform-light Swift modules.
4. Keep MapKit as a bounded surface-access, egress, and geographic-presentation
   adapter, not as the default path-identity source and never as Shuto authority.
5. Maintain replaceable provider adapters and compare MapKit with Valhalla,
   OSRM, and GraphHopper on the same entrance fixtures.
6. Keep Valhalla Meili as the first open-source offline map-matching oracle and
   use the small route-aware Swift online Viterbi prototype as the live matcher
   direction. Feed it through the implemented Core Location boundary, pending
   device profiling and field calibration.
7. Do not make a commercial full-stack navigation SDK or a generic shortest-path
   engine the source of truth for route occurrences, junction movements, recovery,
   signs, toll boundaries, or egress.
8. Use Valhalla as the first shared open-source implementation candidate for
   bounded surface routing and the external HMM oracle, while retaining OSRM and
   GraphHopper as independent executable baselines.

This is not a plan to recreate nationwide navigation. Kaido owns the small,
safety-relevant Shuto subgraph and delegates bounded ordinary-road access and
egress to a provider.

## Why one navigation SDK is insufficient

MapKit returns an Apple-server route between a source and destination, including
geometry and steps. Its documented request model does not expose a custom road
graph or an ordered list of junction movements and repeated edge occurrences.
It is therefore suitable for a candidate surface leg, but not for compiling the
saved Kaido route.

A private B1 probe now gives this limitation a concrete gate: MapKit produced a
nominally successful ordinary-road candidate along Route 20, but the geometry
was vertically coincident with Route 4. The directed inspector could retain both
a continuous surface interpretation and a continuous expressway interpretation.
Provider avoid-highway metadata and maneuver text did not supply independent
path identity, so the candidate correctly failed closed. MapKit remains useful
for presentation and for candidates that bind unambiguously; it is `RETEST`, not
the sole surface-routing authority for the supported entrance set.

Valhalla, OSRM, and GraphHopper expose more graph and map-matching capability,
but their normal route services still solve a weighted path problem. Kaido must
preserve explicit roads, movements, and repetitions even when they are not the
shortest or fastest path. A generic provider may support that process, but cannot
own its semantics.

The Valhalla comparison preserves the path selected by Valhalla itself. Its
route shape is passed to `trace_attributes` with `shape_match=edge_walk` to
recover ordered edge attributes, OSM way IDs, beginning OSM nodes, and digitized
direction. Rematching a MapKit polyline with another engine would only create a
second inference and must not be treated as proof of MapKit's chosen road level.

The provider-neutral contract now accepts optional `selected_path_evidence`
only after a provider's complete path has been translated to exact Kaido
directed edge IDs and bound to the same network snapshot. The Swift inspector
then requires the evidence's provider dataset ID to match graph provenance and
checks path continuity, geometry, terminal anchor, expressway edges, and toll
domains. MapKit leaves the field absent.

The Swift `OSMSelectedPathTranslator` implements the exact translation. A
private shared-snapshot Valhalla 3.8.2 build and Kaido graph were produced from
one pinned Kanto source with the same explicit dataset ID. A later rebuild uses
the complete, same-day Japan PBF for administrative polygons while retaining the
bounded Kanto road input. Valhalla reports `has_admins=true`,
`has_timezones=true`, Tokyo as country `JP` / state `13`, and
`drive_on_right=false`. The three Shinjuku origins each passed three repeated
hard-gate runs after this rebuild: the translated paths contain one, eight, and
84 Kaido edges for same-side, cross-direction, and nearest-incompatible origins.
This proves the bounded path-identity and Japanese admin context contracts,
including the stacked Route 20/Route 4 case. It does not release the entrance or
approve production operations.

`SurfaceRoutingBuildManifest` records the engine image digest, provider dataset
ID, source and artifact checksums, admin/time-zone capabilities, the selected
path identity protocol, and checksummed admin observations. Structural validation binds
the manifest to Kaido graph provenance. The stricter release profile additionally
requires every mandatory source/artifact role, a Tokyo left-driving observation,
and zero release blockers. The private build intentionally remains `LAB_ONLY` because its
road coverage is bounded and operational, distribution, sign, lane, and field
review are incomplete.

`ValhallaSurfaceRouteProvider` and `URLSessionValhallaHTTPTransport` now implement
the bounded HTTP flow: POST one `/route`, pass that exact encoded shape to
`/trace_attributes` with `shape_match=edge_walk`, normalize the response, enforce
the manifest dataset ID, translate to Kaido edges, and only then return a generic
surface candidate. Deterministic tests use a transport stub; no live provider is
called from CI. The public probe CLI also requires an explicit
`--allow-live-valhalla` acknowledgement, validates the manifest, derives the
terminal OSM node from the reviewed approach edge, and uses bounded timeout and
response-size policies. A supervised private local 3x3 window passed through
this exact URLSession boundary; long-running service operations remain open.

The provider route request also binds the destination to the fixture's reviewed
heading and heading tolerance and sets destination `node_snap_tolerance=0`.
Without those fields, the expanded five-entrance corpus showed two fail-closed
errors: a stacked destination could terminate on the edge before the reviewed
approach, and a short final fractional edge could disappear into Valhalla's
default node snap. The constrained request restored one exact selected path
without weakening any inspector gate.

The independent OSRM baseline uses a deliberately weaker but still exact
identity contract. The adapter requests `annotations=nodes`, a full GeoJSON
shape, steps, one route, and the reviewed destination bearing. Its build must set
`osrm-extract --data_version` to the manifest/graph dataset ID; a missing or
different response `data_version` fails closed. `OSMNodePathTranslator` maps
every consecutive OSM node pair to exactly one Kaido directed edge and rejects
parallel-pair ambiguity rather than guessing an OSM way. The inspector then
binds the returned geometry to that complete edge sequence and applies the same
terminal, early-expressway, and toll gates.

The pinned car profile does not accept the combined `motorway,toll` exclusion
used by the default surface preference. The bounded adapter prioritizes
`exclude=motorway` when both preferences are requested, then treats every
expressway edge and forbidden toll domain as a Kaido graph hard gate. Provider
avoidance remains a search hint; it is not the safety decision.

OSRM's default car profile is right-driving unless a way tag, profile setting,
or location-dependent property overrides it. The private LAB_ONLY build first
failed this gate, then used the official `--location-dependent-data` mechanism
and returned `driving_side=left` for every diagnostic step. All nine Shinjuku
runs passed through `OSRMSurfaceRouteProvider`, `URLSessionOSRMHTTPTransport`,
and the public probe CLI with one path variant and no unmatched, ambiguous, or
disconnected selected edges. The synthetic bounded driving-side polygon proves
the mechanism only; a release boundary source, broader coverage, operations,
distribution review, and field evidence remain blockers.

The independent GraphHopper 11.0 baseline uses a different exact identity
protocol rather than pretending it retains a complete OSM node path. The build
disables route-point simplification at import and request time and exposes
directional `edge_key`, `osm_way_id`, and `country` path details. Every detail
array must exactly partition all route point-pairs. `OSMWayPointPathTranslator`
then requires the complete path to resolve to exactly one same-way, continuous
Kaido directed-edge sequence from the same dataset. Short rounded point pairs
may have more than one local candidate only when whole-path continuity collapses
them to the same unique sequence. Provider edge keys are provider-local and
never become Kaido IDs. Missing points, gaps, unresolved parallel ambiguity,
changed way identity, disconnected edges, and repeated edges fail closed.

`GraphHopperSurfaceRouteProvider` verifies `/info` before every `/route`: engine
version, profile, required encoded values, and a non-epoch road timestamp must
match the checksummed manifest. Its URLSession transport exposes only these two
GET endpoints with the same 15-second and 8 MiB limits as the other self-hosted
adapters. A private Shinjuku 3x3 run passed all six gates with 1, 8, and 44
translated Kaido edges and no unmatched, ambiguous, or disconnected result.
GraphHopper 11.0's navigation response conversion hard-codes a right-driving
field, so its prose remains diagnostic; Kaido retains Japanese driving-side and
Japanese, Chinese, and English `GuidanceFrame` ownership.

A shared-snapshot expansion then bound five directional entrances and three
origin classes per entrance. Every final GraphHopper, OSRM, and Valhalla window
passed 45/45 requests, or 135/135 total. GraphHopper and OSRM chose almost the
same distances; Valhalla chose longer legal surface paths for several difficult
origins. The result selects an architecture, not a universal shortest-path
winner: Valhalla leads because it covers both routing and HMM comparison, while
Swift hard gates and occurrence semantics remain authoritative and the other
two engines remain executable controls.

Valhalla route narration is provider prose, not product guidance. The adapter
requests only an explicitly supported Japanese or English locale and currently
returns the primary route candidate. Chinese guidance, actual Japanese sign
text, route shields, transliteration, lane semantics, and all three product
locales remain structured `GuidanceFrame` data owned and versioned by Kaido.

## System boundary

```text
┌──────────────────────────────── Apple client ───────────────────────────────┐
│                                                                            │
│  SwiftUI iPhone UI                 UIKit + CarPlay templates                │
│          │                                      │                           │
│          └──────────── Presentation snapshots ──┘                           │
│                                 │                                          │
│                     NavigationSession actor                                │
│                                 │                                          │
│  Core Location ──► Observation normalizer ──► Route-aware matcher          │
│                                 │                    │                     │
│                                 └────────► Journey reducer                 │
│                                               │                            │
│                                      Guidance planner ──► TTS              │
│                                               │                            │
│  MapKit / provider ──► SurfaceRouteCandidate ─┤                            │
│  Snapshot store ─────► Strict route compiler ─┘                            │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
                                  ▲
                                  │ versioned compiled snapshot
                                  │
┌──────────────────────────── Offline data toolchain ────────────────────────┐
│ OSM candidate graph + operator evidence + review records                   │
│     ──► topology validation ──► movement/sign review ──► released snapshot │
└────────────────────────────────────────────────────────────────────────────┘
```

The presentation layer never infers route progress. It renders immutable
snapshots from the navigation session. MapKit, Core Location, CarPlay, and TTS
are adapters around the domain rather than dependencies of it.

## Swift module boundaries

Start as one Swift package with a small number of targets. Split further only
when measurements or independent release needs justify it.

| Module | Owns | Must not import |
|---|---|---|
| `KaidoDomain` | IDs, graph entities, occurrences, released guidance/frame semantics, status, evidence metadata, value types | MapKit, Core Location, CarPlay, SwiftUI |
| `KaidoRouting` | strict compilation, parked route-editor session, entrance ranking, recovery search, egress precomputation | SwiftUI, CarPlay |
| `KaidoNavigation` | journey reducer, route-aware matcher, confidence, prompt scheduling | SwiftUI, CarPlay |
| `KaidoSurfaceRouting` | provider-neutral surface requests, candidates, fixture validation, inspection gates, probe records | MapKit, Core Location, route-plan mutation |
| `KaidoData` | versioned snapshot loading, spatial index, migration and integrity checks | UI frameworks |
| `KaidoAppleAdapters` | Core Location, Core Motion, MapKit, AVFAudio, lifecycle translation | route-policy decisions |
| `KaidoPresentation` | phone and CarPlay presentation snapshots and localized formatting | graph search implementation |
| app targets | iPhone scene, CarPlay scene, dependency composition | duplicated domain rules |
| test support | portable E2E adapter, replay clock, provider probes, benchmark reporting | live services in deterministic suites |

Use Swift value types at module boundaries. The implemented `NavigationSession`
actor serializes the route-bound matcher, conservative matcher-to-location
projection, navigation reducer, DecisionZone distance bridge, prompt emission,
restriction, tunnel, CarPlay-ownership, and Finish drive events. Its internal
state transitions remain pure reducer functions so deterministic simulation does
not need an actor, clock, device, or main thread. Matcher reset/restart never
rewinds engine progress. The actor does not fabricate entry-transition forward
continuity from one matcher estimate; that stronger evidence remains a separate
adapter input before automatic strict-route entry.

The pure Swift guidance and presentation path now implements this boundary.
`GuidanceFramePlanner` consumes a `NavigationSnapshot`, RoutePlan-bound released
definitions, and one fresh resolved occurrence/distance observation. It never
reads coordinates or mutates RoutePlan progress. `NavigationEngine` owns the
prompt ledger and returns a transient matching `GuidancePromptEmission` only when
a reviewed threshold is first crossed.

`NavigationPresentationProjector` consumes one immutable `NavigationSnapshot`
plus one occurrence-scoped `GuidanceFrame` and produces phone, CarPlay, and voice
values. Both visual surfaces carry the same route-plan ID, current occurrence,
anchor occurrence, next movement, DecisionZone, prompt and anchor IDs, prompt
stage, distance, Japanese and localized decision-point names, maneuver, lane
preparation, marker certainty, route shield, Japanese sign target, passage
evidence, interaction policy, an optional released `JunctionViewDefinition`, and
an optional Finish drive exit; only
`isPrimarySurface` differs across a CarPlay handoff. The voice locale is selected
separately from the interface locale. `voice.shouldSpeak` is true only when the
request carries an emission matching the frame and persisted engine ledger.

`JunctionViewDefinition` is renderer-neutral data, not a retained provider image.
It contains normalized approach, selected, and alternative paths; zero-based
left-to-right allowed and preferred lane indices; route shields; the Japanese
sign target; a checked date; and source-reference IDs. It is bound to one network
snapshot and movement occurrence. Only `RELEASED` evidence projects. Phone and
CarPlay receive the same immutable value; the later Apple adapter may rasterize
it for `CPManeuver.junctionImage` and map its lanes to supported CarPlay lane
guidance APIs without owning or inferring road semantics.

The projector fails closed when prompt, anchor occurrence, movement occurrence,
or DecisionZone identity is absent; the frame does not belong to the current
occurrence; distance is invalid; a voice emission disagrees with the frame or
ledger; the Japanese decision-point name is absent or drifts from its Japanese
localized value; any release locale is incomplete; a locale replaces the
Japanese sign target; CarPlay ownership contradicts connection state; or the
selected Finish drive exit lacks a name in the interface locale. A junction inset
also fails closed when its evidence is not released, normalized geometry or lane
indices are invalid, or its snapshot, movement occurrence, route shields, or
Japanese sign target drift from the active guidance request.
Only `REALTIME_CONFIRMED_PASSABLE` may authorize a positive open-road color;
`NO_KNOWN_CONFLICT_REALTIME_UNCONFIRMED` remains explicitly unconfirmed.
LOW/projected or ambiguous positions become `ESTIMATED` or `UNRESOLVED`, and a
moving decision zone exposes no route editor or required phone touch.

The released frame, pure planner, ledger update, and semantic projection are
executable. `GuidanceProgressBridge` now derives distance-to-DecisionZone from a
HIGH Swift estimate only when along-edge progress, RoutePlan occurrence, directed
edge, complete version-bound corridor geometry, and reviewed DecisionZone entry
offset agree. It never consumes the matcher's lateral residual as route distance.
KR-S17 injects an already resolved scalar; KR-S18 executes the matcher bridge
through planning, ledger, and projection. Production corridor construction and
zone calibration remain data/field gates. Dynamic layout, accessibility,
installed voice discovery, SwiftUI lifecycle, `CPMapTemplate`, audio routing,
and physical display timing remain adapter work and device gates.

`NavigationSession` now owns the executable runtime ordering of these pieces.
One matcher observation produces one atomic update containing matcher diagnostics,
the resulting `NavigationSnapshot`, bridge status, resolved progress when safe,
and at most one matching prompt emission. Initialization validates exact
RoutePlan, snapshot, occurrence corridor, DecisionZone, and released-guidance
bindings before accepting observations. Core Location callback ownership,
background lifecycle, persistence/restoration, audio scheduling, and app-scene
composition are still unimplemented Apple boundaries.

`NavigationReleaseBundle` is the platform-light pre-runtime eligibility gate.
It keeps an active `NetworkSnapshot`, compiled `RoutePlan`, reviewed editor
catalog, `RouteMatcherCorridor`, DecisionZone definitions, released guidance,
and optional junction-view registry in one value. The bundle reuses
`NavigationSession`'s route/corridor/zone/guidance validator rather than defining
a second runtime identity policy. It additionally requires the catalog to use
the same snapshot and contain the route's directional entrance, initial edge,
and exit; requires exactly one DecisionZone and at least one released guidance
definition for every planned junction-movement occurrence; and requires every
embedded junction view to match one released registry value exactly. Duplicate
movement zones, missing repeated-occurrence assets, unregistered views, and
orphaned views fail closed. This is release-asset integrity, not evidence
promotion: KR-D18's synthetic `ACTIVE` and `RELEASED` values do not establish
real-road eligibility.

`RouteAtlasRelease` is the separate renderer-neutral map-integrity gate. Its
`RouteAtlasTopologySlice` is the separately released, dated graph truth for
exactly the network coverage that may be visible. `RouteAtlasDefinition`
contains normalized
north-up layout nodes and paths, but every layout node and topology edge must be
covered exactly once, every path endpoint must agree with the bound topology
nodes, and every rendered successor set must be an exact translation of the
reviewed graph, with one unique route-entity identity per topology edge.
Geometry contact never creates a connection. The definition contains no
independently authored display labels; future route shields and names must
resolve from separately released metadata bound to the same snapshot.
Every topology and layout evidence ID must resolve through a decoded
`RouteAtlasSourceRegistry` record with an explicit topology/layout role,
authority, HTTPS source, content SHA-256, checked date, and licence identifier. Unresolved,
duplicate, invalid, or role-mismatched source records fail closed. The complete
network snapshot, RoutePlan, source registry, topology slice, and definition are
Codable as a versioned `RouteAtlasReleaseArtifact`; decoding never bypasses the
same release validator.
Every RoutePlan occurrence has its own binding in exact RoutePlan order, while
repeated occurrences may intentionally reference the same schematic segment.
Snapshot drift, missing or extra coverage, an invented connection, incomplete
occurrence binding, or anything short of released dated topology and layout
evidence fails closed. KR-D19 executes
an invented-connection rejection with synthetic data. This gate proves internal
consistency only; the repository still has no released real Shuto topology slice
or reviewed production atlas layout.

`RouteAtlasContextBundle` is a separate, permanently non-authoritative layer for
full-network geographic recognition. Its only accepted navigation role is
`CONTEXT_ONLY`; it exposes source-derived display paths but no directed edge,
successor, occurrence, junction movement, route selection, current-position, or
realtime semantics. A separately decoded source record must resolve the exact
source-reference ID, HTTPS locations, archive SHA-256, ISO dates, current-state
usage scope, CC BY 4.0 identifier, attribution, and transformation disclosure.
The context definition also fixes one north-up local equirectangular projection,
normalized unit-square coordinates, exact selected-feature/path/vertex/route-name
counts, unique source-feature/part identity, and finite in-bounds points.
Promotion to navigation authority, source drift, missing attribution, projection
drift, coverage drift, or geometry drift fails closed. KR-D20 executes the
authority boundary with synthetic data.

The first tracked context artifact is reconstructed directly from the checksummed
MLIT National Land Numerical Information N06-2025 archive. It uses only
current-state records (`N06_003 == 9999`), designated urban expressways
(`N06_008 == 5`), and route names beginning with `首都高速` plus the separately
operator-reconciled `高速横浜環状北西線`; all selected multiline parts and
vertices are retained without simplification. The importer
requires the source-declared JGD2011 `EPSG:6668` CRS before projection. The pinned
archive produces 86 source features, 86 paths, 3,584 vertices, and 26 route
names, with one provisional-use path retained and visibly distinguishable.
Those 26 names are source metadata, not released display labels. Twenty-five
operator route names match directly. Feature 1414 / record `EA02_373001` names
its Yokohama Kohoku-to-Aoba geometry `高速横浜環状北西線`; one current,
checksummed operator-page reconciliation maps that bounded feature to K7
Yokohama Northwest for recognition only.
Its source reference date is 2025-12-31. The operator's 2026-07-01 Navi Map is
a later currentness review source, not copied presentation data and not proof of
directed topology. `kaido-atlas validate` checks the decoded source/context
bundle, while the Python builder verifies the raw ZIP checksum before producing
the artifact. None of these checks releases a real Kaido topology slice.

The first real-source directed candidate covers K7 Northwest up from the exact
Yokohama Aoba entrance identity to the Yokohama Kohoku exit identity. It reverses
the source-order MLIT feature 1414 geometry into RoutePlan order and preserves
all 38 vertices. Four dated, checksummed MLIT/operator sources resolve the
bounded corridor and facility movements. Both topology and layout remain
`OFFICIAL_CHECKED`: the source geometry has no carriageway, ramp, or
legal-successor identity, operator diagrams are not distributable Kaido layout
assets, and production-layout, field, and realtime reviews remain open. KR-D21
executes the requirement that this candidate fail release with only the two
unreleased-evidence issues.

The next candidate introduces an ODbL-isolated, snapshot-bound directed data
slice rather than promoting the MLIT centerline. The pinned Geofabrik Kanto
2026-07-21 PBF yields a continuous 13-way one-way chain from the Yokohama Aoba
toll-plaza split, through the K7 Northwest up carriageway, to the Yokohama
Kohoku exit terminal. The topology also retains one immediate alternative at
each operator-reviewed decision: continue onto K7 Yokohama North instead of the
first exit branch, or continue to Daisan-Keihin instead of Yokohama Kohoku exit.
The source-bound facility checks also retain the Aoba incoming/non-route split
and all three motor-road successors at the Kohoku terminal. Two are named
one-way `川向線` ways; OSM way `776884422` is an unnamed `tertiary` way
without an explicit `oneway` tag. Yokohama's 2020 opening notice identifies
that corridor as the temporary passage then used inside the land-readjustment
area. A current municipal page reports that surrounding infrastructure work
completed in March 2022 and the project ended in July 2023, but the final
replotting map does not map the exact OSM way to a current road identity. Those
sources cannot establish its present physical status, legal direction, or
permitted exit movement. The derivative database preserves 257 route
and alternative nodes, complete
selected-way tags, parent PBF and bounded-extract hashes, extraction bounds, OSM
timestamp, and reconstruction tooling. Its 13 route occurrences, 15 topology
edges, and 15 layout segments pass internal identity and successor validation.
A separate deterministic audit compares the complete source adjacency at 14
entry, route, divergence, and exit checkpoints. The pinned extract yields 19
outgoing successors and no applicable turn-restriction relation. This proves
source translation completeness, not road legality: the third surface way has
an official historic identity but no current road-level direction or
permitted-movement review. The coordinate-free field-review validator requires
four current, safely collected, hash-bound checkpoints and still grants no
Route Atlas release authority.
Both evidence states remain `CANDIDATE`; OSM community directionality plus
current operator diagram agreement does not replace independent field/topology
review, a released production layout, OSM attribution integration, or realtime
review. KR-D22 preserves the directed-candidate boundary; KR-D23 preserves the
separate source-complete versus legal-review boundary.

The first Kaido-owned K7 schematic candidate replaces raw source geometry only
in the layout definition. It covers the same 15 topology edges, preserves both
expressway divergences and all 13 occurrence bindings, and carries a separate
Apache-2.0 layout source record. The renderer visibly terminates at
`osm.node.7473451738`; none of the three adjacent surface ways is present in
the layout. KR-D24 proves that the resulting artifact has no structural release
issue beyond the two intentional candidate evidence states. This advances
production layout review without granting topology, surface-movement, or
navigation authority.

The local environment observed on 2026-07-22 is Xcode 26.3 with Swift 6.2.4.
That is a development fact, not yet the minimum deployment target.

## UI and rendering direction

### iPhone

- SwiftUI owns route discovery, pre-drive review, guided customization, settings,
  evidence status, and the driving shell.
- The Shuto overview is a custom renderer, initially implemented with
  SwiftUI `Canvas`/`Path` or a shared Core Graphics renderer. It is not a MapKit
  geographic map.
- The persistent frame is deliberately dual-layer: source-derived geographic
  context establishes the recognizable full-network shape, while an independently
  released `RouteAtlasRelease` alone may add selectable topology, RoutePlan
  occurrence state, direction, legal movement, and position.
- This renderer is the persistent `Route Atlas` for the supported Shuto slice,
  not a decorative preview. Its system and route views keep a stable north-up
  frame so the driver can retain network context. An approach-aligned
  `JunctionViewDefinition` inset may expand near a reviewed decision, but it
  does not rotate, replace, or become the authority for the atlas.
- The schematic may simplify distance and dense junction spacing, but it
  preserves the recognizable relative geography of the released Shuto slice:
  central and outer route structure, radial corridors, the Bayshore axis, Tokyo
  Bay, and the Tokyo-to-Yokohama relationship. Kaido generates this geometry
  from its own reviewed data and styling; operator map images, labels, and
  artwork are evidence references, not distributable presentation assets.
- The atlas is derived from the active versioned network snapshot and
  `RoutePlan`. It distinguishes the current occurrence, passed and future
  occurrences, repeated traversals, recovery and egress paths, and
  released-versus-context-only topology. Unsupported or unreleased corridors
  cannot appear selectable or look equivalent to released navigable coverage.
- Phone and CarPlay receive an already validated `RouteAtlasRelease`; renderers
  never infer connectivity from line intersections or author an alternate
  successor graph. Before real released topology and layout evidence exist,
  concept compositions must be marked topology-unverified and not for
  navigation.
- A precise vehicle bead requires fresh route-resolved evidence. Degraded,
  ambiguous, tunnel, or stacked-road positioning renders an honest segment or
  uncertainty halo rather than a falsely precise point.
- The bounded surface access and egress screens may use MapKit for geographic
  context and render accepted provider geometry as overlays.
- A junction inset is drawn from `JunctionViewDefinition` with a Kaido-owned
  vector renderer. SwiftUI must not retain or reproduce third-party junction
  artwork.
- Complex authoring is disabled while moving.
- SwiftUI renders `ExpertRouteEditorSnapshot` and submits stable reviewed choice
  or lap-candidate IDs. `KaidoRouting`, not the view tree, owns the current
  incoming approach, legal movement set, reviewed closed-sequence matching,
  fresh occurrence creation, grouped parked undo, and explicit exit completion.
  KR-U01 and KR-U02 execute this pure boundary; the internal SwiftUI editor uses
  a synthetic catalog and does not release real Shuto authoring data.
- The pre-drive adapter consumes only the compiled exact RoutePlan. A
  same-snapshot reviewed-distance catalog may populate actual distance by
  walking ordered occurrences; a separate uniquely active tariff record supplies
  tariff distance and toll evidence. SwiftUI renders the resulting KR-U04
  projection and cannot derive one distance from the other. The internal
  synthetic review keeps navigation start locked until a coherent released
  bundle exists.
- A synthetic language-preview adapter independently selects the interface and
  guidance-voice locales from one validated `GuidanceFrame`. It renders the
  Japanese sign target and route shield unchanged beside localized explanatory
  text. It supplies no prompt emission and therefore has no speech authority.
  KR-U05 and KR-U11 cover this adapter boundary; complete app localization,
  pronunciation review, and the audio lifecycle remain pending.

### CarPlay

- Use the navigation entitlement and a `CPMapTemplate` root.
- Draw the base map or schematic in the CarPlay window; use CarPlay templates for
  interaction, route preview, maneuvers, lane guidance, and alerts.
- CarPlay keeps the same north-up `Route Atlas` state as the phone, with more
  space assigned to the map and the next-decision overlay. It does not create an
  independently rotating map, occurrence cursor, or recovery path.
- A dedicated CarPlay adapter consumes the same `GuidanceFrame` as the phone. It
  cannot contain its own progress, recovery, or route-selection logic.
- On supported system versions, the adapter renders the shared normalized
  junction definition into `CPManeuver.junctionImage` and CarPlay lane guidance.
  It must fall back to the same maneuver, sign, and route-shield text when those
  presentation APIs are unavailable; it cannot source missing lane data from
  MapKit narration.
- Connecting or disconnecting CarPlay changes only the active presentation
  surface. The shared `NavigationSession` retains the RoutePlan, current
  occurrence, confidence, recovery state, and emitted-prompt ledger. Disconnect
  falls back to iPhone presentation without requiring a phone touch or replaying
  an already emitted prompt.
- Do not depend on iOS 27 route-sharing or new panel APIs for the first slice.
  They may be added later behind availability checks.

Apple's CarPlay sample explicitly lets a navigation app draw a custom map while
`CPMapTemplate` supplies the interaction overlay. This supports the topology-map
direction without requiring an Apple base map on the CarPlay surface.

The pure Swift lifecycle and presentation scenarios prove this ownership
boundary only. CarPlay entitlement, scene connection order, audio routing,
simulator rendering, process termination, and wired/wireless head-unit behavior
remain platform integration and field-test gates.

## Routing responsibilities

### Strict Shuto route compiler

The compiled route is an ordered occurrence sequence. It is constructed from
exact directional facilities and legal movements, not from a list of coordinates.

Compilation is deterministic:

```text
template or expert choices
→ resolve exact network snapshot
→ validate reviewed route components in directional order
→ expand each legal movement or reviewed lap template
→ assign fresh, collision-free occurrence IDs
→ validate closures, PA, boundaries and evidence
→ attach guidance and recovery anchors
→ emit immutable RoutePlan
```

No shortest-path algorithm may remove an explicit lap, movement, road, or PA.
For a manually authored route, compilation is validation and expansion rather
than route optimization.

Circuit names are presentation metadata. For example, a reviewed practical C2
circuit retains its separately modeled B edges and the exact movements at both
route boundaries. Likewise, `toll_domain_id` is carried per occurrence and
checked before the plan becomes executable. Unknown classification is not
silently treated as the current domain.

Curated template generation may later use a bounded depth-first or beam search
over legal movements. Its objective is to satisfy explicit route constraints,
not to minimize arrival time.

### Entrance recommendation

Use a two-stage algorithm.

1. Hard filter exact entrance direction, payment/vehicle constraints, known
   restrictions, allowed toll domains, released transition evidence, and legal
   reachability to an allowed join occurrence.
2. Rank the survivors with a documented score or Pareto ordering over surface
   ETA, last-500-meter complexity, Shuto lead-in, route difficulty, exit policy,
   and evidence freshness.

The surface provider supplies candidate geometry and ETA. It does not decide
that a facility is compatible.

The routing result exposes one structured `EntranceRecommendationSelection`
with exact facility, target carriageway, join occurrence, ETA, straight-line
distance rank, and stable hard-filter reasons. Rejected candidates retain their
reason codes. KR-U13 requires the iPhone adapter to render those values without
re-ranking candidates or inferring direction from display labels. The internal
implementation uses a synthetic set bound to the parked editor; live location,
provider routing, and released entrance evidence remain separate gates.

### Deviation recovery

Recovery is a constrained multi-target search from the observed road state to a
set of later occurrences in the active route plan.

For the small Shuto graph, use Dijkstra or A* without contraction preprocessing.
Evaluate a vector cost lexicographically:

```text
hard invalidity                         must equal zero
unreleased movement or external exit    must equal zero
number of required route occurrences lost
decision-zone risk and short-weave load
recovery distance
recovery expected time
```

Search only a bounded future-occurrence horizon. Keep every feasible result with
its chosen occurrence ID, skipped occurrences, evidence state, and added path.
The selected plan never becomes an A-to-B destination route.

If no released rejoin exists, return `NO_RELEASED_REJOIN`. A separate safe-egress
policy may then mark the original route interrupted.

### Finish-drive egress

Precompute eligible egress paths for loop occurrences using reverse shortest-path
search from exact exit facilities. Runtime `FINISH_DRIVE` selects the next legal
option consistent with the accepted return policy. It never reverses the graph or
unlocks an arbitrary exit connector.

## Route-aware map matching

Nearest-road snapping is unsafe on stacked carriageways, parallel ramps, tunnels,
and repeated route geometry. Use a hidden Markov model with an online Viterbi or
bounded beam decoder.

The executable comparison floor lives under `benchmarks/map-matching/`. Its six
synthetic fixtures contain receive-ordered observations, explicit ground-truth
occurrence intervals, branch decisions, source labels, and expected failures for
a deliberately weak `NearestEdgeNegativeControl`. The shared evaluator detects
false high-confidence edge and branch choices, unresolved high-confidence ties,
stale high-confidence fixes, missing occurrence identity, backward occurrence
jumps, and branch commits made inside an observation gap. The negative control
does not become a fallback matcher merely because its expected failures are
reproducible.

### Apple observation boundary

`CoreLocationObservationAdapter` is the only Apple-framework entry point into
the live matcher. It converts each `CLLocation` callback batch into ordered
`RouteMatcherObservation` values while preserving the fix timestamp, callback
receive timestamp, deterministic observation ID, horizontal accuracy, valid
course/speed evidence, and source provenance. Invalid coordinates, non-positive
horizontal accuracy, unrepresentable or future timestamps, and software-
simulated locations are recorded as typed rejections. Simulation can be admitted
only through an explicit testing policy.

Apple source evidence and CarPlay test context are different fields:

- `CLLocation.sourceInformation.isProducedByAccessory` means an external
  accessory such as CarPlay or MFi produced the location; it does not identify
  wired versus wireless transport.
- `isSimulatedBySoftware` records software simulation and is rejected by the
  production default.
- a connected CarPlay scene is stored as `CONNECTED_TRANSPORT_UNKNOWN` unless a
  passenger-operated field run explicitly declares wired or wireless context;
- `WIRED_CARPLAY` and `WIRELESS_CARPLAY` in matcher fixtures are calibration
  cohorts, not claims about the physical GPS source.

The system source-evidence reader is replaceable for deterministic tests, but
production uses Core Location's values unchanged. Nine focused tests cover
source separation, simulation policy, invalid/future fixes, motion-field
sanitization, callback order, stale no-signal delivery, receive-time reversal,
and the live matcher handoff. They do not replace iPhone/head-unit field tests.

### Private trace and calibration boundary

`CoreLocationMatcherCalibrationSession` executes the actual
`CoreLocationObservationAdapter` → `RouteMatcherSession` path in callback order
and measures both stages with monotonic uptime. It records accepted estimates,
adapter rejections, matcher rejections, source provenance, and timings through
`CoreLocationPrivateTraceRecorder`.

The privacy split is structural rather than a naming convention:

- `MatcherPrivateTrace` is always `PRIVATE_RAW_LOCATION`. It contains coordinates,
  observation IDs, route-plan ID, device/OS, mount, and optional head-unit detail.
  The recorder is memory-only and offers no persistence API.
- `MatcherCalibrationReport` has no coordinate, observation ID, trace ID,
  route-plan ID, device model, mount, or head-unit field. It contains an opaque
  device-configuration ID, scalar counts, nearest-rank p95 timings, and observed
  reliability bins.
- raw inputs remain under ignored private storage. Only a deliberately reviewed,
  coordinate-free report is structurally eligible for tracking.

Evaluation is scoped to exactly one network snapshot, matcher algorithm/config,
device configuration, and field transport context. Combining phone, wired,
wireless, or unknown-transport runs by accident fails. Ground-truth annotations
must name accepted matched observations; attaching truth to a rejected sample is
an error rather than a silently ignored record.

The provisional evaluator requires held-out samples per observed source cohort
and blocks on any annotated false `HIGH` edge or occurrence. Its default 30-
sample floor is only a small-sample guard, not statistical proof or release
approval. Synthetic collection and software-simulated samples have explicit
non-field gate states and cannot satisfy the field floor. Current confidence is
categorical, so Brier score remains unavailable until the matcher emits a
calibrated probability; observed accuracy by confidence bin is descriptive only.

Thirteen focused tests cover raw/report separation, mixed-scope rejection,
held-out sufficiency, false-`HIGH` blocking, synthetic/simulated exclusion,
annotation validity, p95 calculation, Apple provenance mapping, real pipeline
timing, adapter rejection, and matcher receive-order rejection. These tests
prove the recording/evaluation contract, not any iPhone performance result.

The internal iPhone shell now supplies the first real Apple lifecycle adapter
for this evidence boundary. Its foreground-only calibration panel requires
explicit device/mount metadata and transport scope before requesting when-in-use
location. A bundled loader joins the exact tracked K7 ODbL database to its
candidate RoutePlan, verifies 13 occurrence edges plus two divergence
alternatives, and refuses any snapshot, facility, timestamp, direction,
occurrence, or licence drift while requiring `navigation_authority=false`.
Delegate batches feed the existing calibration session unchanged. Raw traces
remain in memory and are destroyed on discard; the UI exposes only counts,
cohort/confidence status, and the coordinate-free report gate. This adapter does
not create a
`NavigationSession`, render position, run in the background, or turn candidate
data into release evidence. No real device trace has run yet.

### Candidate generation

- Query directed edges from an R-tree or equivalent spatial index using the
  reported horizontal accuracy plus a bounded margin.
- Include expected route occurrences and a limited legal deviation neighborhood.
- Keep the same edge entity at different route occurrences as distinct states.
- Record Core Location external-accessory evidence separately from the declared
  phone/wired/wireless field calibration cohort.

### Emission cost

Combine:

- perpendicular distance normalized by horizontal accuracy;
- course/heading agreement when accuracy and speed make it meaningful;
- direction and level/structure compatibility;
- a route-occurrence prior that prefers the active plan but never makes an
  impossible observation appear valid.

### Transition cost

Compare the legal graph path between candidate states with observed elapsed time,
displacement, speed, and feasible movements. Penalize impossible direction changes,
unobserved decision zones, backward occurrence jumps, and implausible travel time.

### Confidence and commit policy

Confidence is derived from candidate separation and calibrated on replay data. It
is not a renamed GPS accuracy value. A branch or phase transition commits only
when the winning path is sufficiently separated from alternatives and the
required movement evidence is present.

Adapters therefore report route-candidate resolution separately from observation
quality. `AMBIGUOUS` keeps the topology marker unresolved and blocks occurrence
progress even if the coordinate itself is fresh and accurate. `RESOLVED` must
name exactly one occurrence after combining the winner and retained candidate
IDs; contradictory resolved evidence fails closed. A later explicit singleton
may clear that ambiguity. This prevents a stacked carriageway or repeated route
entity from being committed merely because one provisional candidate was first.

Valhalla Meili implements an HMM/Viterbi matcher and exposes configurable emission
and transition parameters, so it is the first external oracle. Its output still
uses Valhalla edges and must be translated before comparison with Kaido occurrences.

`ValhallaMatcherReplayOracle` now implements that bounded comparison path. It
uses the manifest-bound `osm_changeset` and expands each provider edge through
OSM way ID, begin/end node ID, and digitized direction on the exact Kaido graph.
Unlike strict selected-route translation, the provider-edge translator preserves
repeated traversal. A matched point's along-edge fraction selects one translated
segment only when it is not within the declared boundary tolerance; otherwise
the result stays ambiguous.

Valhalla 3.8.2's JSON serializer emits `end_node` only when at least one node
category attribute is active. The bounded request therefore includes `node.type`
alongside `edge.end_osm_node_id`; omitting that activation field produces no end
node identity even though the edge filter itself is present.

The batch request preserves increasing observation time and disables Meili point
interpolation. Because Meili accepts one trace-level GPS accuracy and search
radius rather than Kaido's per-observation accuracy values, the adapter records
the maximum reported accuracy and derives one disclosed bounded radius. A stale
point received out of timestamp order is rejected rather than reordered, so the
batch oracle cannot claim to model that online case.

Most importantly, `matched` is not treated as `HIGH`. The documented response
contains match type and distance but no calibrated confidence and no RoutePlan
occurrence. The adapter emits `LOW`, leaves occurrence absent, and cannot advance
the journey reducer.

The first private same-snapshot controlled window used five reviewed entrance
chains at exact geometry, 5-meter displacement with 10-meter declared accuracy,
and 10-meter displacement with 20-meter declared accuracy. Across 15 fixtures,
195 observations per repeat, and 45 provider requests, every repeated report was
value-identical and edge top-1 was 192/195. All three LOW-confidence misses were
at the first Tomigaya entrance-mouth observations; later ramp and merge points
recovered. Occurrence remained 0/195 by design. This is protocol and identity
evidence from synthetic graph-derived observations, not device calibration or a
reason to give Meili live navigation authority.

`RouteAwareSwiftMatcher` is now the first executable platform-light alternative.
Its hidden state is `(directed edge, RoutePlan occurrence)`. Geometry distance
and heading form the emission score; forward occurrence order, along-edge
progress, elapsed time, speed, and graph connectivity constrain transitions.
It consumes fixes in receive order, never advances on a stale fix, and caps
ambiguous or first post-gap evidence at LOW. It emits no prediction-only HIGH
commit inside an observation gap.

On the six tracked fixtures the prototype is deterministic with 18/23 edge
top-1, 21/21 occurrence, and no named safety failure. The edge count deliberately
does not reward guessing: three stacked points and one equal parallel-road point
abstain, while the first noisy wrong-branch point remains uncommitted. On the
same private five-entrance window it produced 190/195 edge top-1 and 195/195
occurrence hypotheses. All five non-top-1 results were LOW abstentions with no
selected edge. Meili produced 192/195 edge top-1 and 0/195 occurrence, with two
LOW wrong-edge selections and one ambiguity at Tomigaya.

This selects pure Swift for the live matcher boundary. `RouteMatcherSession` now
turns the algorithm into a fixture-independent incremental API: the session is
bound to one RoutePlan and versioned `RouteMatcherCorridor`, accepts observations
in receive order, retains temporal path state, rejects invalid receive ordering, and
supports explicit reset or restart at a reviewed occurrence. A fixed-grid
spatial index measures only nearby corridor edges before expanding their route
occurrence states. A score beam and configurable active-state cap bound growth
when the same edge appears across many laps. Diagnostics expose indexed/query
edge counts, active states, and accepted observations without making those
values navigation authority.

The replay adapter now uses this same session rather than a separate batch
implementation, and streamed output is value-identical to batch output on
all tracked fixtures. KR-S16 drives the public session through the scenario
adapter and `NavigationEngine`: stale evidence does not mutate the session, the
first post-gap occurrence hypothesis remains LOW, a fresh second observation
may commit HIGH, and restarting the matcher cannot move navigation backward.

For HIGH unambiguous Swift results, `MatcherEstimate.fractionAlongEdge` carries
the selected geometry projection separately from `distanceMeters`, which is the
lateral point-to-road residual. `GuidanceProgressBridge` accumulates the
remaining current edge, complete intervening route occurrences, and the reviewed
offset to the target movement's DecisionZone. Every binding is occurrence-scoped,
so a repeated edge on another lap is not interchangeable. LOW results, external
oracle estimates without along-edge progress, skipped occurrences, incomplete
geometry, and ID drift fail closed. KR-S18 proves this deterministic boundary;
it is not a substitute for field-calibrated geometry or prompt timing.

This is still not a calibrated production engine. The trace and reliability
pipeline now exists, but the current grid has only synthetic complexity coverage
and zero iPhone/head-unit calibration traces. No on-device CPU, memory, thermal,
or battery profile exists. Actual device evidence is the next core gate. C++ or
Rust is not justified unless profiling this bounded implementation exposes a
measured failure that cannot be fixed within the Swift boundary.

## Tunnel behavior

When GPS observations stop:

1. preserve the last reliable candidate set and occurrence progress;
2. propagate only along legal expected movements using elapsed time and the last
   reliable speed as weak evidence;
3. optionally use Core Motion turn/acceleration evidence only when device
   availability and mounting calibration are known;
4. increase uncertainty continuously;
5. do not commit an ambiguous tunnel branch during the gap;
6. on signal return, replay a short buffered window before confirming a new state.

The feasibility reducer makes that final step explicit. After a low or lost
tunnel observation, signal reacquisition is `PENDING`. A single good coordinate
does not advance the route or restore a precise topology marker. At least two
high-confidence occurrence-level candidate sets must arrive within a bounded
gap and intersect to one exact current-or-later occurrence before the state is
`CONFIRMED`. Entity IDs are insufficient because the same road may appear in
multiple route occurrences. The initial two-observation and five-second values
are deterministic spike parameters, not field-calibrated release thresholds;
replay and field evidence must calibrate them separately for phone, wired,
wireless, and accessory-produced location sources.

Core Motion can provide attitude, rotation rate, and acceleration, but phone
placement varies and inertial drift accumulates. It is supporting evidence, not a
promise of precise tunnel dead reckoning. Some Core Location fixes may be produced
by a CarPlay accessory; record that source and compare it separately rather than
assuming every head unit supplies better tunnel positioning.

## Guidance architecture

Guidance is derived from released movement semantics and deterministic anchors:

```text
matched occurrence and progress
→ next DecisionZone
→ prompt stage
→ structured GuidanceFrame
→ localized display + reviewed spoken form
→ phone / CarPlay / AVSpeech adapters
```

The executable `GuidanceFrame` is a `KaidoDomain` value containing prompt, anchor,
anchor occurrence, movement occurrence, and DecisionZone identity; prompt stage;
distance; Japanese and localized decision-point names; maneuver; lane
preparation; Japanese sign target; route shields; and localized display and
spoken content. It may also contain one validated `JunctionViewDefinition` for
the same movement occurrence. Position confidence remains part of the paired
`NavigationSnapshot`. Adapters may shorten layout-specific copy but cannot
change the target movement or reconstruct missing guidance semantics.

Prompt scheduling is occurrence-scoped. Each released
`GuidanceAnchorDefinition` binds one `occurrence_id + anchor_id` pair to one
unique prompt ID. The navigation engine emits that pair once, suppresses repeated
location triggers, and rejects delayed anchors that no longer belong to the
current occurrence. An equivalent anchor on a later lap remains eligible because
its occurrence ID is different. The ledger belongs to the shared navigation
core; phone, CarPlay, and speech adapters consume emissions but cannot retrigger
them independently. Restoring a navigation snapshot also restores emitted keys
from prompt IDs, so an adapter or process lifecycle transition does not replay a
prompt merely because the engine value was reconstructed.

`ReleasedGuidanceDefinition` binds that identity to a reviewed trigger distance
and immutable frame template. For one anchor occurrence, thresholds advance from
the outer instruction toward the most actionable eligible instruction. If a fix
jumps across several thresholds, the planner emits only the most actionable
prompt; it does not play historical catch-up speech. Once a later stage has been
emitted, distance jitter cannot regress the active frame to an earlier stage.
Stale timestamps, a non-current occurrence, LOW/ambiguous route evidence, and
post-gap reacquisition cannot update the frame or authorize voice. The engine
returns a transient `GuidancePromptEmission`; the frame itself never means
“speak now.”

## Snapshot storage direction

For the first small graph:

- keep source fixtures human-reviewable and separate by licence;
- compile a read-only, versioned snapshot for the app;
- use SQLite with an R-tree or an equivalent compact index for geometry lookup and
  metadata, then build small in-memory adjacency arrays for search;
- store saved route plans as occurrence-based records tied to a snapshot ID;
- reject incompatible or partially migrated snapshots before navigation.

Do not use SwiftData object relationships as the routing graph. The graph needs
explicit adjacency, stable IDs, spatial queries, and deterministic snapshot
loading rather than UI-oriented object persistence.

## Provider comparison

| Candidate | Best role | Strength | Product mismatch | Direction |
|---|---|---|---|---|
| Custom Swift core | strict Shuto route, recovery, occurrence-aware matching | exact semantics, on-device, deterministic | highest implementation and calibration work | **Required** |
| Apple MapKit | surface access/egress and geographic presentation | native Swift integration, route geometry and steps, CarPlay-compatible platform | server route is opaque; stacked-road path identity is unavailable | **Keep as bounded adapter; RETEST for full B1** |
| Valhalla | first shared open-source surface router and HMM matching oracle | MIT, dynamic costing, map matching, portable C++ and offline support; own route shape can be edge-walked into exact OSM identity | route ranking differs from the other engines; integration/data build weight, operations, distribution, broader coverage, and field review remain | **Leading implementation candidate behind the provider boundary; not RoutePlan authority** |
| OSRM | performance and generic match baseline | fast C++ route/match services, MLD/CH, BSD-2-Clause; complete route node annotations can bind to the Kaido graph | node-pair identity fails on parallel pairs; build must add dataset and left-driving context; generic fastest-path semantics | **Bounded surface baseline proven; release inputs and operations pending** |
| GraphHopper | independent configurable surface baseline | Apache 2.0, turn restrictions, custom models, directional edge keys, and OSM way path details | Java/server footprint; no full OSM node path; import/request simplification must stay disabled; navigation driving-side output is not trustworthy | **Manifest/path protocol and bounded adapter proven; release inputs and operations pending** |
| Commercial full-stack SDK | later build-versus-buy reference | mature maps, traffic, guidance, CarPlay in some products | metered cost, service terms, rerouting authority and data control | **Deferred** |

No provider passes by feature count. Each provider is evaluated only for the
bounded role it may own.

## Dependency rules

- Domain modules do not import Apple frameworks.
- Provider responses are translated into Kaido value types at the boundary.
- Live service output is never a deterministic CI fixture unless reduced to a
  dated, reviewable scalar or geometry record with appropriate licence.
- A provider failure cannot mutate or erase the selected Shuto `RoutePlan`.
- Commercial SDK evaluation requires a separate cost, data-use, and licence
  review before code integration.

## Sources checked 2026-07-23

- [Apple MapKit for SwiftUI](https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui)
- [Apple `MKDirections.Request`](https://developer.apple.com/documentation/mapkit/mkdirections/request)
- [Apple `MKRoute` geometry](https://developer.apple.com/documentation/mapkit/mkroute/polyline)
- [Apple CarPlay navigation integration](https://developer.apple.com/documentation/carplay/integrating-carplay-with-your-navigation-app)
- [Apple `CPManeuver` junction images and maneuver metadata](https://developer.apple.com/documentation/carplay/cpmaneuver)
- [Apple `CPLaneGuidance`](https://developer.apple.com/documentation/carplay/cplaneguidance)
- [Apple background location guidance](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
- [Apple `CLLocation` source information](https://developer.apple.com/documentation/corelocation/cllocation/sourceinformation)
- [Apple external-accessory location source](https://developer.apple.com/documentation/corelocation/cllocationsourceinformation/isproducedbyaccessory)
- [Apple software-simulation location source](https://developer.apple.com/documentation/corelocation/cllocationsourceinformation/issimulatedbysoftware)
- [Apple location timestamp](https://developer.apple.com/documentation/corelocation/cllocation/timestamp)
- [Apple Core Motion](https://developer.apple.com/documentation/coremotion/)
- [Swift Testing](https://developer.apple.com/xcode/swift-testing/)
- [Swift Package Manager](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/)
- [Valhalla project and licence](https://github.com/valhalla/valhalla)
- [Valhalla official Docker images](https://github.com/valhalla/valhalla/blob/master/docker/README.md)
- [Valhalla Mjolnir tile build guide](https://valhalla.github.io/valhalla/mjolnir/getting_started_guide/)
- [Valhalla dataset and build identification](https://valhalla.github.io/valhalla/concepts/change-identification/)
- [Valhalla route location heading and tolerance](https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/)
- [Valhalla 3.8.2 node-snap configuration](https://github.com/valhalla/valhalla/blob/3.8.2/scripts/valhalla_build_config)
- [Valhalla Meili map matching](https://valhalla.github.io/valhalla/meili/)
- [Valhalla map-matching API](https://valhalla.github.io/valhalla/api/map-matching/api-reference/)
- [Valhalla `trace_attributes` and `edge_walk`](https://valhalla.github.io/valhalla/api/map-matching/api-reference/)
- [OSRM backend and services](https://github.com/Project-OSRM/osrm-backend)
- [OSRM HTTP route, annotation, and `data_version` contract](https://github.com/Project-OSRM/osrm-backend/blob/0844e3af77896d11998ef6db356a553056652c8e/docs/http.md)
- [OSRM car-profile driving-side handler](https://github.com/Project-OSRM/osrm-backend/blob/0844e3af77896d11998ef6db356a553056652c8e/profiles/lib/way_handlers.lua)
- [OSRM location-dependent left-driving test](https://github.com/Project-OSRM/osrm-backend/blob/0844e3af77896d11998ef6db356a553056652c8e/features/car/side_bias.feature)
- [OSRM licence](https://raw.githubusercontent.com/Project-OSRM/osrm-backend/master/LICENSE.TXT)
- [GraphHopper 11.0 release](https://github.com/graphhopper/graphhopper/releases/tag/11.0)
- [GraphHopper 11.0 local HTTP API](https://github.com/graphhopper/graphhopper/blob/69e50f6e2cfaf0a8e69752df9953ee5f1ac276a4/docs/web/api-doc.md)
- [GraphHopper directional `edge_key` detail](https://github.com/graphhopper/graphhopper/blob/69e50f6e2cfaf0a8e69752df9953ee5f1ac276a4/core/src/main/java/com/graphhopper/util/details/EdgeKeyDetails.java)
- [GraphHopper `osm_way_id` encoded value](https://github.com/graphhopper/graphhopper/blob/69e50f6e2cfaf0a8e69752df9953ee5f1ac276a4/core/src/main/java/com/graphhopper/routing/ev/OSMWayID.java)
- [GraphHopper 11.0 navigation driving-side conversion](https://github.com/graphhopper/graphhopper/blob/69e50f6e2cfaf0a8e69752df9953ee5f1ac276a4/navigation/src/main/java/com/graphhopper/navigation/NavigateResponseConverter.java#L417)
- [Osmium output header options](https://docs.osmcode.org/osmium/latest/osmium-output-headers.html)
- [Newson and Krumm, HMM map matching](https://www.microsoft.com/research/publication/hidden-markov-map-matching-noise-sparseness/)
- [Mapbox navigation pricing reference](https://www.mapbox.com/pricing)
