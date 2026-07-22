# iOS navigation architecture direction

**Status:** accepted and implemented for the platform-light feasibility core;
provider selection remains subject to the bake-off in
`docs/testing/navigation-engine-bakeoff.md`.

**Checked:** 2026-07-22

## Decision summary

Use a hybrid architecture:

1. Build the iPhone client in Swift.
2. Use SwiftUI for parked iPhone workflows and a UIKit/CarPlay scene adapter for
   the in-car surface.
3. Keep the route-first domain, strict route compiler, journey state machine,
   recovery, guidance, and route-aware matcher in platform-light Swift modules.
4. Treat MapKit as the first surface-access and surface-egress route provider,
   not as the authority for the Shuto route.
5. Maintain replaceable provider adapters and compare MapKit with Valhalla,
   OSRM, and GraphHopper on the same entrance fixtures.
6. Use Valhalla Meili as the first open-source map-matching oracle while a small
   route-aware Swift matcher is developed and calibrated.
7. Do not make a commercial full-stack navigation SDK or a generic shortest-path
   engine the source of truth for route occurrences, junction movements, recovery,
   signs, toll boundaries, or egress.

This is not a plan to recreate nationwide navigation. Kaido owns the small,
safety-relevant Shuto subgraph and delegates bounded ordinary-road access and
egress to a provider.

## Why one navigation SDK is insufficient

MapKit returns an Apple-server route between a source and destination, including
geometry and steps. Its documented request model does not expose a custom road
graph or an ordered list of junction movements and repeated edge occurrences.
It is therefore suitable for a candidate surface leg, but not for compiling the
saved Kaido route.

Valhalla, OSRM, and GraphHopper expose more graph and map-matching capability,
but their normal route services still solve a weighted path problem. Kaido must
preserve explicit roads, movements, and repetitions even when they are not the
shortest or fastest path. A generic provider may support that process, but cannot
own its semantics.

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
| `KaidoDomain` | IDs, graph entities, occurrences, status, evidence metadata, value types | MapKit, Core Location, CarPlay, SwiftUI |
| `KaidoRouting` | strict compilation, entrance ranking, recovery search, egress precomputation | SwiftUI, CarPlay |
| `KaidoNavigation` | journey reducer, route-aware matcher, confidence, prompt scheduling | SwiftUI, CarPlay |
| `KaidoSurfaceRouting` | provider-neutral surface requests, candidates, fixture validation, inspection gates, probe records | MapKit, Core Location, route-plan mutation |
| `KaidoData` | versioned snapshot loading, spatial index, migration and integrity checks | UI frameworks |
| `KaidoAppleAdapters` | Core Location, Core Motion, MapKit, AVFAudio, lifecycle translation | route-policy decisions |
| `KaidoPresentation` | phone and CarPlay presentation snapshots and localized formatting | graph search implementation |
| app targets | iPhone scene, CarPlay scene, dependency composition | duplicated domain rules |
| test support | portable E2E adapter, replay clock, provider probes, benchmark reporting | live services in deterministic suites |

Use Swift value types at module boundaries. A `NavigationSession` actor serializes
location, provider, restriction, and user events. Its internal state transitions
remain pure reducer functions so that deterministic simulation does not need an
actor, clock, device, or main thread.

The local environment observed on 2026-07-22 is Xcode 26.3 with Swift 6.2.4.
That is a development fact, not yet the minimum deployment target.

## UI and rendering direction

### iPhone

- SwiftUI owns route discovery, pre-drive review, guided customization, settings,
  evidence status, and the driving shell.
- The Shuto overview is a custom schematic renderer, initially implemented with
  SwiftUI `Canvas`/`Path` or a shared Core Graphics renderer. It is not a MapKit
  geographic map.
- The bounded surface access and egress screens may use MapKit for geographic
  context and render accepted provider geometry as overlays.
- Complex authoring is disabled while moving.

### CarPlay

- Use the navigation entitlement and a `CPMapTemplate` root.
- Draw the base map or schematic in the CarPlay window; use CarPlay templates for
  interaction, route preview, maneuvers, lane guidance, and alerts.
- A dedicated CarPlay adapter consumes the same `GuidanceFrame` as the phone. It
  cannot contain its own progress, recovery, or route-selection logic.
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

The pure Swift lifecycle scenario proves this ownership boundary only. CarPlay
entitlement, scene connection order, audio routing, simulator rendering, process
termination, and wired/wireless head-unit behavior remain platform integration
and field-test gates.

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

### Candidate generation

- Query directed edges from an R-tree or equivalent spatial index using the
  reported horizontal accuracy plus a bounded margin.
- Include expected route occurrences and a limited legal deviation neighborhood.
- Keep the same edge entity at different route occurrences as distinct states.
- Record location source, including whether Core Location reports a CarPlay or
  other external accessory.

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

`GuidanceFrame` contains the Japanese sign target, route shield, localized
explanation, lane preparation, maneuver, distance, confidence, and prompt ID.
Adapters may shorten layout-specific copy but cannot change the target movement.

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
| Apple MapKit | surface access/egress and geographic presentation | native Swift integration, route geometry and steps, CarPlay-compatible platform | server route is opaque; no custom graph or documented occurrence sequence | **First surface adapter** |
| Valhalla | open-source routing and HMM matching oracle; possible fallback | MIT, dynamic costing, map matching, portable C++ and offline support | integration/data build weight; generic graph IDs and routing objectives | **First open-source comparator** |
| OSRM | performance and generic match baseline | fast C++ route/match services, MLD/CH, permissive licence | optimized fastest-path service; weaker runtime policy customization | **Secondary comparator** |
| GraphHopper | configurable server baseline | Apache 2.0, turn restrictions, custom models, map matching | Java/server footprint; generic route semantics | **Secondary comparator** |
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

## Sources checked 2026-07-22

- [Apple MapKit for SwiftUI](https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui)
- [Apple `MKDirections.Request`](https://developer.apple.com/documentation/mapkit/mkdirections/request)
- [Apple `MKRoute` geometry](https://developer.apple.com/documentation/mapkit/mkroute/polyline)
- [Apple CarPlay navigation integration](https://developer.apple.com/documentation/carplay/integrating-carplay-with-your-navigation-app)
- [Apple background location guidance](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
- [Apple external-accessory location source](https://developer.apple.com/documentation/corelocation/cllocationsourceinformation/isproducedbyaccessory)
- [Apple Core Motion](https://developer.apple.com/documentation/coremotion/)
- [Swift Testing](https://developer.apple.com/xcode/swift-testing/)
- [Swift Package Manager](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/)
- [Valhalla project and licence](https://github.com/valhalla/valhalla)
- [Valhalla Meili map matching](https://valhalla.github.io/valhalla/meili/)
- [Valhalla map-matching API](https://valhalla.github.io/valhalla/api/map-matching/api-reference/)
- [OSRM backend and services](https://github.com/Project-OSRM/osrm-backend)
- [OSRM licence](https://raw.githubusercontent.com/Project-OSRM/osrm-backend/master/LICENSE.TXT)
- [GraphHopper open-source engine](https://github.com/graphhopper/graphhopper)
- [Newson and Krumm, HMM map matching](https://www.microsoft.com/research/publication/hidden-markov-map-matching-noise-sparseness/)
- [Mapbox navigation pricing reference](https://www.mapbox.com/pricing)
