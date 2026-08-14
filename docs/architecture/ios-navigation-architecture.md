# iOS navigation architecture direction

**Status:** accepted and implemented for the platform-light core and default
whole-Shuto iPhone journey. The App loads the dated 2026-08-04 directed graph
with 26 route entries, 151 IC names, 39 JCTs, and 19 PAs. Its route-first home
offers named experiences, automatic direction-valid entrance/exit pairing,
1–3 laps for loops, and exact custom routes before the optional destination.
The selected Kaido-owned `RoutePlan` then drives review and a labeled replay of
bounded surface legs, entry, expressway progress, exit, egress, finish, and
checkpoint reconstruction. Candidate whole-Shuto live start remains
fail-closed as `WHOLE_SHUTO_NAVIGATION_RELEASE_REQUIRED`.

`ShutoNetworkDatabase` preserves graph bounds, explicit limitations, official
catalog and facility-review hashes, and OSM source/licence metadata rather than
discarding those fields at decode. `ShutoPlannedRouteRuntimeCompiler` validates
the selected facilities, graph edges, occurrence order, geometry, distance,
and snapshot, then compiles the route-aware matcher corridor, DecisionZones,
reviewed guidance, and graph-derived recovery candidates. Recovery derivation
runs independently for each alternative outgoing edge and binds the candidate
to both the RoutePlan divergence occurrence and the observed directed edge;
runtime selection refuses a candidate authored for a different branch. Because
the graph is a planning candidate, those recovery paths are marked unreleased:
a deviation becomes unavailable/route-interrupted instead of executing an
unreviewed movement. The compiler also emits a deterministic
`ShutoRouteLiveReleaseCoverage` report for every graph decision and recovery
branch. Known JCT decisions are counted separately from non-JCT graph
divergences such as directional exit splits, so missing JCT guidance is not
conflated with missing surface re-entry recovery. The report quantifies missing
review but grants no authority. Every result
carries a deterministic `ShutoRuntimeAssetIdentity`: the
network-artifact SHA-256 covers
the complete canonical decoded database, while the route-runtime SHA-256 binds
the exact `RoutePlan` and all route-local runtime inputs to that artifact hash.
It is explicitly not the joint authority-bearing `KaidoProductRelease`. This is
an integrity and restoration boundary, not a promotion of OSM/provider surface
geometry, unreviewed movements, or the candidate graph to released-road, lane,
realtime, or field authority.

`inspect-network-live-coverage` builds the snapshot-wide authoring worklist
without enumerating every possible entry/exit RoutePlan. For the 2026-08-04
snapshot it identifies 37 JCTs with graph choices, 120 incoming approaches, and
241 candidate incoming/outgoing movement pairs. Twenty exact definitions are
currently released and 221 still require legal/sign review. Graph adjacency is
inventory only: it does not assert that every pair is a lawful movement.

The default App always exposes labeled replay using the deterministic 15 m/s
trace with at most 30 meters between samples and an explicit 20x wall-clock
multiplier. `WholeShutoPlanningLocationController` owns a when-in-use foreground
Core Location lifecycle for the planning origin only. It cannot create a live
navigation session from the candidate graph. The live enrollment seam accepts
only one `KaidoLiveJourneyAdmission` whose complete selected `RoutePlan` equals
one foreground-authorized `KaidoProductRelease` and whose immutable
`JourneyPlan` contains release-bound surface access and egress legs. It then
constructs `KaidoProductNavigationRuntime`, `ShutoLiveDriveSession`, both
boundary adapters, and the observation adapter before attaching the shared
serial foreground location controller. Device fixes reject invalid, stale,
future-dated, ambiguous, and distributed-build simulated input and require a
unique HIGH occurrence commit before progress. The seam cannot mint
`EntryTransitionAdmissionContext`,
`SurfaceEgressAdmissionContext`, or an `isReleased` surface option from an asset
hash or a MapKit response. Neither the current planning location path nor replay
supplies background-navigation or tunnel dead-reckoning authority.

`ShutoJunctionGuidanceCompiler` contains 20 snapshot- and source-hash-bound
movement definitions. They cover every divergent JCT on the C1 inner catalog
loop and on the Bayshore corridor in both directions. Admission still requires
the exact adjacent edges, shared JCT node, route direction, occurrence order,
and operator-detail hash. The App may render and speak only the reviewed branch
or continuation, Japanese sign target, and route shields. Lane indices remain
`NOT_RELEASED`; insufficient approach-specific evidence keeps the other
transitions silent.

The default shell persists interface and guidance-voice languages separately,
preserves Japanese physical sign text and route shields, and exposes geographic
and whole-route track-map presentations. OSM attribution is a separate adjacent
native surface and never grants navigation authority. The previous C2 and K7
artifacts remain deterministic regression fixtures, not product coverage limits
or active delivery tracks.

Open boundaries remain explicit: no passenger-safe field, tunnel, acoustic, or
CarPlay qualification exists; there is no background navigation service or
CarPlay scene; dynamic passage and traffic remain unconfirmed without a current
provider; and lane guidance remains unreleased. Enrolling live navigation
requires a real validated joint `KaidoProductRelease` plus released surface
provider and field evidence; this is an external evidence boundary, not a value
an asset-integrity hash may synthesize. Valhalla remains the leading
shared surface-routing/offline-oracle candidate behind a bounded adapter, while
the pure-Swift route-aware matcher owns live RoutePlan matching.

**Checked:** 2026-08-14

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
9. Let the product accept a current position or arbitrary resolvable address at
   both ends. Kaido ranks compatible directional entrances and exits and owns
   the Shuto graph search. At route choice, the provider may calculate the two
   ordinary-road legs for every exact Kaido candidate. A complete result set
   may replace surface-distance proxies with provider ETA for ranking and may
   supply comparable full-journey preview metrics. A partial result set retains
   deterministic Kaido ordering and Shuto-only metrics. The provider cannot
   replace a route or change its ordered movements.
10. Generate the distributable Shuto graph from pinned route relations plus
    only connected motorway links. Join current operator route, IC-direction,
    JCT, and PA facts without copying operator maps or images.
11. Keep unavailable facilities in the catalog for honest display, but exclude
    them from route search. The long-term-closed Yaesu Route is the first
    concrete case.
12. Keep recommendation and customization in the same route-choice stage.
    Whole-network customization may pin an exact direction-valid entrance,
    direction-valid exit, and route-cost style, but only the graph planner may
    emit the resulting ordered `RoutePlan`. Draft UI state has no route
    authority.
13. Separate route selection from simulation start with one parked journey
    review. The review is ready only when the latest exact `RoutePlan` and both
    bounded surface legs are present. A missing access or egress result fails
    closed with retry; it never skips directly to entry, exit, or a shorter
    synthetic journey.

This is not a plan to recreate nationwide navigation. Kaido owns the small,
safety-relevant whole-Shuto snapshot and delegates bounded ordinary-road access
and egress to a provider.

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
continuity from one matcher estimate. Before strict-route entry, the ordinary
matcher path may update confidence diagnostics but cannot advance an occurrence
or schedule guidance. `CoreLocationEntryTransitionAdapter` instead consumes the
immutable admission context supplied by `KaidoProductNavigationRuntime`, matches
against the exact release-bound corridor, and emits a package-only
`EntryTransitionEvidence`. The actor rejects simulation, stale/replayed or
receive-reversed observations, release identity drift, non-HIGH or ambiguous
matches, missing/mismatched heading, and skipped transition edges. It derives
forward continuity from the accepted edge history and restarts route matching at
the exact first occurrence only after strict-route entry. The current 45-degree
heading and ten-second age gates are conservative implementation thresholds, not
field-calibrated release values. The Core Location adapter preserves
`courseAccuracy` and `speedAccuracy` on the matcher observation as well as in
calibration provenance. A reported course uncertainty larger than the baseline
heading sigma reduces that bearing's emission weight, while speed uncertainty
widens the time-distance transition tolerance. Invalid negative uncertainty
remains absent evidence. KR-S19 executes the positive and fail-closed paths.

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

`GuidanceSpeechScheduler` is the platform-light final admission boundary. It is
bound to one exact RoutePlan and keys consumption by prompt, anchor, and anchor
occurrence. Persistent frames, duplicate adapter delivery, another RoutePlan,
and inconsistent phone/CarPlay identities cannot create speech. A newer
occurrence-scoped prompt may replace an older active prompt. An interruption
consumes and drops the active prompt; ending the interruption never replays it or
any prompt that arrived while audio was unavailable.

`GuidanceSpeechCoordinator` connects that scheduler to an injected output.
The iOS `AVSpeechGuidanceOutput` resolves only the requested reviewed locale,
enumerates only voices already installed on the device, excludes novelty and
personal voices, and ranks premium, enhanced, then default quality. The locale's
release identifier is translated to an exact synthesis locale before voice
resolution: Japanese uses `ja-JP`, Simplified Chinese uses `zh-CN`, and English
uses `en-US`. A generic release-language tag such as `zh-Hans` or `en` is not
passed directly to the Apple voice API.
The locale's
system default is only an equal-quality tie-break, so a generic accessibility
character cannot displace a higher-quality normal voice. A persisted explicit
identifier is stored independently for each synthesis locale and may override
automatic quality ranking only while it remains an eligible exact-locale
installed voice; removal falls back to the ranked result.
The chosen identifier, name, locale, and quality remain observable without
granting speech authority.
Short guidance keeps Apple's neutral rate and pitch; app-side tuning does not
slow or lower compact voices in a way that exaggerates synthetic cadence. These
values do not rewrite reviewed spoken content. Parked audition and admitted
navigation speech use the same utterance configurator for rate, pitch,
pre-delay, and post-delay, so audition cannot silently differ in timing.
`NavigationVoicePresentation` separately preserves the exact released
`spokenText`, its reviewed term-level `spokenForms`, and a derived
`synthesisText`. `GuidanceSpokenFormRenderer` applies exact source terms
longest-first against the original string, never cascades through replacement
output, and leaves an already expanded surrounding form unchanged.
`GuidanceSpeechCommand` carries both identities: exact offline-audio lookup
continues to use `spokenText`, while `AVSpeechGuidanceOutput` alone passes
`synthesisText` to Apple.
The output
uses `AVAudioSession.Mode.voicePrompt` with temporary `duckOthers` and
`interruptSpokenAudioAndMixWithOthers`, activates audio only for an admitted
prompt, and deactivates with `notifyOthersOnDeactivation`. It observes Apple
audio interruptions, cancels current synthesis, and deliberately does not
resume stale navigation speech. Missing installed voices and audio-session
configuration or activation failures remain typed, observable blocked states.
This implements reviewed-form delivery, scheduling, and lifecycle ownership;
actual pronunciation, output-route timing, interruption behavior on real
phone/CarPlay hardware, and driver comprehension remain device evidence gates.
The app cannot download an Apple
voice asset; when a device has only default quality, the preview says so rather
than claiming neural or enhanced synthesis, and exposes the device Spoken
Content installation path after real voice resolution.

`GuidanceAudioRelease` is an optional higher-quality offline output layer, not a
second guidance authority. Its manifest is bound to one exact product release,
navigation release, network snapshot, and RoutePlan. It must contain exactly one
record for every released guidance anchor occurrence and each supported speech
locale. Each record preserves the exact reviewed spoken string and hashes both
that string and one flat mono PCM16 WAV resource. Sample rate, duration, byte
count, non-silence, generation or recording provenance, model revision, voice
identifier, licence identifier, source URL, and generation/review chronology
are validated before the pack can be admitted. Schema 1.2 additionally embeds a
reviewer ID, review timestamp, and passed pronunciation, intelligibility, and
audio-quality decisions for the exact WAV hash in every asset record. One
missing, extra, duplicate, corrupt, pending, rejected, future-reviewed, or
identity-drifted record rejects the whole pack.

`ReleasedGuidanceAudioOutput` performs only exact
`RoutePlan + prompt + anchor + anchor occurrence + locale + spoken text`
resolution. A match is played by `AVAudioPlayerGuidancePlayback` through the
same temporary `voicePrompt` audio-session policy. A miss or playback-start
failure falls back to `AVSpeechGuidanceOutput`; a failure after recorded audio
has started is terminal and cannot replay the consumed prompt in another voice.
The product-release catalog must explicitly declare and SHA-256-pin an audio
manifest before the runtime composes this output. A product may declare multiple
independently complete packs. Each choice has one stable selection ID, localized
display names, an exact audio release ID, and a manifest hash; duplicate or
partial choices reject catalog construction. The parked user explicitly selects
the installed device voice or one declared pack. That preference is scoped to
the product release and frozen when its navigation runtime is created. A stale
choice clears to the device voice instead of selecting another pack. No audio
release is present in the current preview catalog. Locally generated auditions
are selection evidence only and cannot enter navigation unless they are
reviewed, complete, declared, and packaged through this release gate.

`GuidanceAudioRecordingWorklistCodec` derives the complete immutable recording
surface directly from one validated product release. It carries exact
occurrence/text identity and deterministic filenames but no model choice or
release authority. `GuidanceAudioReviewChecklistCodec` prepares one deterministic
checklist bound to the exact worklist and local WAV hashes with every decision
`PENDING`; it never contains audio bytes. `GuidanceAudioReleaseAuthor` combines
that human-completed checklist with exactly one reviewed provenance profile per
supported locale and local PCM16 WAV files, recalculates hashes and metadata,
then re-runs the complete release gate. Synthetic product and audio evidence
scopes must agree; a released-road product requires `RELEASED_ASSET`. The
`kaido-release` CLI exposes worklist export, review preparation, manifest build,
and independent manifest/resource validation without permitting manual prompt
identity or text substitution.

The parked pre-drive sound check is a separate Apple-adapter boundary.
`GuidanceVoiceSetupModel` may select Japanese, Simplified Chinese, or English,
persist a device-local installed-voice preference for each language, and always
supplies the corresponding fixed representative route-shield/destination
sample. If an explicit preference has a higher-ranked installed candidate, the
model may audition that exact candidate without mutating navigation. Only an
exact completed audition plus explicit user confirmation persists the
candidate; resolved-voice drift fails closed and its later output callbacks
cannot reopen confirmation.
`AVSpeechVoiceAuditionOutput` receives only an exact locale, optional identifier,
and sample text. It has no RoutePlan, occurrence, frame, emission, prompt, or
ledger input, so audition cannot enter `GuidanceSpeechScheduler` or consume
one-shot authority. The App derives audition admission from its declared parked
interaction context and treats any other context as moving and blocked. The
admitted navigation output reads the preference only while resolving a voice
for a real `GuidanceSpeechCommand`; all scheduling, replacement, and
exactly-once behavior remain unchanged.
`GuidanceAudioSourceSetupModel` separately owns the product-scoped playback
source choice. It never receives route progress or prompt authority. Its menu
shows only the device voice and complete hash-bound packs already admitted by
the selected foreground product. The fixed sound-check sample continues to
audition the installed device voice; an offline pack does not claim an audition
sample that its exact release did not contain.

`JunctionViewDefinition` is renderer-neutral data, not a retained provider image.
It contains normalized approach, selected, and alternative paths; zero-based
left-to-right allowed and preferred lane indices; route shields; the Japanese
sign target; a checked date; and source-reference IDs. It is bound to one network
snapshot and movement occurrence. Only `RELEASED` evidence projects. Phone and
CarPlay receive the same immutable value; the later Apple adapter may rasterize
it for `CPManeuver.junctionImage` and map its lanes to supported CarPlay lane
guidance APIs without owning or inferring road semantics.

The whole-Shuto candidate network also supports narrower
`ShutoJunctionMovementDefinition` values when branch direction and sign text are
reviewed but lane indices are not. These definitions are snapshot-bound to one
exact adjacent-edge transition and JCT node and never become
`JunctionViewDefinition` or CarPlay lane guidance. The phone may render only
their reviewed branch path, Japanese sign target, and shields while stating
that lane indices are not released. Any source-hash, snapshot, direction, node,
edge, or occurrence drift suppresses the inset.

For the current candidate snapshot, the 20 exact definitions cover every
divergent JCT on the C1 inner catalog loop and on the Bayshore corridor in both
directions. The route planner promotes each exact reviewed outgoing edge
occurrence to `JUNCTION_MOVEMENT`; `ShutoPlannedRouteRuntimeCompiler` then binds
its incoming occurrence as the anchor and compiles one DecisionZone plus one
commit-stage `ReleasedGuidanceDefinition` for that occurrence. The catalog
preserves approach-specific Japanese sign targets, route shields, and a reviewed
left, right, or mainline-continuation instruction. The App projects phone and
voice from the same `NavigationSessionUpdate`. None of these definitions
implies lane preparation; lane preparation remains `NONE`, and every transition
without sufficient approach-specific evidence remains silent and neutral. The
current evidence-blocked set and reasons are recorded in
`docs/product/principles.md`, not inferred from missing code.

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
through planning, ledger, and projection. The whole-Shuto runtime compiler now
constructs the candidate corridor and occurrence-bound zones used by replay.
A future live path may reuse those semantic inputs only after an exact
`KaidoProductRelease` independently admits them; the candidate assets cannot
create that authority. Passenger-safe field calibration of matcher and prompt
timing remains a separate evidence gate. The synthetic driving/JCT panel now
has a KR-U09 accessibility baseline: localized assistive projection, non-color
branch/lane cues, actual theme-token contrast checks, and standard plus AXXXL
Simulator UI tests. A separate app panel decodes one complete
`SYNTHETIC_TEST_ONLY` joint release, constructs
`KaidoProductNavigationRuntime`, binds the Apple observation and entry adapters,
and publishes only actor-returned snapshots plus a presentation projection
constructed from the exact same update. Each strict-route update projects phone,
CarPlay, and voice from the same frame. An update without a transient prompt
emission may refresh the visual projection but cannot speak, while a missing or
invalid frame exposes no driving surface. The panel's explicit fixed synthetic
trace exercises that full path without attaching a location manager or creating
UI-owned occurrence progress. A separate foreground controller can construct an
automotive `CLLocationManager` only after a release-bound live-input authority
matches the actor's exact product release, navigation release, runtime policy,
snapshot, RoutePlan, and matcher corridor. It requests When In Use authorization
only after an explicit start, serializes callback batches, and stops plus drains
the current callback before inactive/background checkpointing. The bundled
synthetic scene supplies a typed authority blocker, constructs no manager, and
keeps strict entry locked. Real-road released assets, full-app focus and
interaction review, installed voice discovery, `CPMapTemplate`, audio routing,
device-matrix layout, and physical display timing remain adapter work and device
gates. Separately, the default candidate whole-Shuto journey has a foreground
`WholeShutoPlanningLocationController` for planning location. Live start selects
an admission by full `RoutePlan` equality, rejects zero or multiple matches, and
attaches Core Location only after the release runtime and surface adapters
construct successfully. Inactive/background first stops and drains location,
then checkpoints; returning active never resumes location without the user's
explicit Resume Navigation action. The distributed bundle currently supplies no
whole-Shuto live admissions, so it still fails closed as
`WHOLE_SHUTO_NAVIGATION_RELEASE_REQUIRED`. It cannot inherit the K7 fixture's
road-evidence or live-input authority merely because location permission or
device fixes exist.

`run_ios_device_qualification.py` makes the first of those gates repeatable. It
accepts only one exact online physical iPhone, binds the complete App scheme to
a clean source commit, requires a zero-failure/zero-skip physical `.xcresult`,
and requires the named default whole-Shuto foreground planning-location
`testWholeShutoForegroundLocationStartsAndStopsThroughCoreLocation()`
permission/start/stop UI test to pass exactly once. It hashes the result tree,
summary, test tree, and build log into a receipt without device ID, device name,
coordinates, raw traces, audio, or paths. The receipt grants only
planning-location lifecycle smoke; it deliberately keeps live navigation,
location accuracy,
acoustic, pronunciation, road, CarPlay, and background-navigation authority
false.

`NavigationSession` now owns the executable runtime ordering of these pieces.
One matcher observation produces one atomic update containing matcher diagnostics,
the resulting `NavigationSnapshot`, bridge status, resolved progress when safe,
and at most one matching prompt emission. Initialization validates exact
RoutePlan, snapshot, occurrence corridor, DecisionZone, and released-guidance
bindings before accepting observations. Its raw initializer is package-only.
External adapters construct `KaidoProductNavigationRuntime` from one validated
`KaidoProductRelease`; the runtime retains that release and Route Atlas and
creates the session from the exact released RoutePlan,
`ReleasedNavigationRuntimePolicy`, corridor, DecisionZones, and guidance without
accepting independent replacements. The policy supplies the only eligible
directional entry transition, released in-domain recovery candidates, and legal
egress options. Every recovery candidate must identify an exact divergence
occurrence and trigger directed edge, begin with that same edge, and rejoin a
strictly later RoutePlan occurrence. Off-plan observations only select a
candidate with the same trigger edge. The release gate additionally requires
every transition edge to
exist in the same matcher corridor, every consecutive pair to be an explicit
successor, and the final transition edge to lead to the first RoutePlan
occurrence binding. The internal app now owns a foreground-only synthetic
composition pipeline and an input-disconnected SwiftUI scene. The app model
retains the `NavigationPresentationProjection` returned from the same atomic
update used for speech scheduling. SwiftUI renders only that value; it does not
recompute occurrence, movement, prompt, DecisionZone, sign, shield, lane, or
distance semantics. A later update with the same active frame and no emission
updates the display with `voice.shouldSpeak=false` and cannot replay the prompt.
The foreground location controller owns only source lifecycle and ordered
delivery; it feeds raw callback batches through the existing Apple adapters and
never owns matching, occurrence progress, guidance, or presentation.

`NavigationSessionCheckpoint` schema 2.0 is the process-restoration boundary.
It stores only coordinate-free reducer state and binds it to the exact product
release, navigation release, journey plan, runtime policy, network snapshot,
RoutePlan, and matcher corridor. It does not persist coordinates, matcher
posterior, partial entry-transition evidence, CarPlay connection, active
guidance frame, or an audio queue. Restoration revalidates the whole identity,
so a surface-access session cannot be reopened through the route-only runtime
initializer. It maps an interrupted entry transition back to
`APPROACH_TO_ENTRY`, disconnects CarPlay, clears speech authority, and exposes
active navigation as LOST/estimated with a pending reacquisition window. The
first otherwise-HIGH matcher estimate may seed that window but is returned as
LOW and cannot advance progress or emit guidance. Later fresh evidence must
satisfy the ordinary multi-observation reacquisition policy. The emitted-prompt
ledger remains in the checkpoint, so reconstruction cannot replay a prior
prompt.

`FileNavigationSessionCheckpointStore` atomically replaces one JSON file under
Application Support. The runtime panel observes `scenePhase`; inactive or
background stops current speech and saves immediately because background can
precede termination, while active resumes only future prompt delivery. A
completed journey removes the active checkpoint on the next inactive/background
lifecycle save. This is termination recovery, not background navigation: the
target declares no location background mode and starts no
`CLBackgroundActivitySession` or equivalent background service. Foreground
`CLLocationManager` ownership is implemented behind exact live-input authority,
but the bundled synthetic release cannot construct it. Real released assets,
active background navigation, and production process/device evidence remain
Apple boundaries.

`NavigationReleaseBundle` is the platform-light pre-runtime eligibility gate.
It keeps an active `NetworkSnapshot`, compiled `RoutePlan`, reviewed editor
catalog, `ReleasedNavigationRuntimePolicy`, `RouteMatcherCorridor`, DecisionZone
definitions, released guidance, an optional junction-view registry, and an
optional `ReleasedSurfaceAccessDefinition` in one value. The policy must bind
the same snapshot and RoutePlan, name the compiled
directional entrance and first route occurrence, provide a released in-domain
candidate targeting a later RoutePlan occurrence for `SAFE_REJOIN`, and provide
no rejoin candidates for any other recovery policy. It must also provide at
least one released egress whose exit is the compiled RoutePlan exit. The bundle reuses
`NavigationSession`'s route/corridor/zone/guidance validator rather than defining
a second runtime identity policy. It additionally requires the catalog to use
the same snapshot and contain the route's directional entrance, initial edge,
and exit. `ReleasedRouteAuthoringRecipe` then proves the stronger relationship:
the exact initial edge plus every ordered movement/outgoing-edge pair, toll
domain, directional destination, occurrence ID, and repeated traversal must be
replayable through the same catalog. The recipe exposes immutable IDs for
user-submitted parked choices; it does not auto-author a route. Only a completed
session whose whole identity matches can regain the release-owned RoutePlan and
its reviewed actual distance. The bundle also requires exactly one DecisionZone
and at least one released guidance definition for every planned
junction-movement occurrence; and requires every embedded junction view to match
one released registry value exactly. Duplicate
movement zones, missing repeated-occurrence assets, unregistered views, and
orphaned views fail closed. This is release-asset integrity, not evidence
promotion: KR-D18's synthetic `ACTIVE` and `RELEASED` values do not establish
real-road eligibility.

When surface access is present, the bundle additionally requires its
`SurfaceApproachPolicy` to match the exact snapshot, RoutePlan entrance, first
join occurrence, runtime entry-transition edges, and compatible compiled exit.
It also requires a complete reviewed release-candidate provider/build identity
covering provider, adapter, engine, snapshot, dataset, manifest, build,
validation profile, and intended use. The definition is inert until
`ReleasedSurfaceAccessPlanner` proves the runtime provider carries that exact
identity, runs it, inspects every candidate, and recomputes every surface hard
gate. The package-scoped `JourneyPlanCompiler` then requires a same-snapshot
inspection with an unambiguous resolved edge sequence. A single accepted
candidate becomes ready; multiple accepted alternatives require explicit
selection and cannot inherit provider response order. The resulting
`JourneyPlan` composes around the unchanged RoutePlan; provider guidance steps
never enter released guidance authority. `KaidoProductNavigationRuntime`
revalidates the whole plan against that release before admitting it, starts a
fresh access plan at `APPROACH_TO_ENTRY`, and retains the existing ordered
entry-evidence gate for `STRICT_ROUTE`. A route-only plan remains valid, while
`RETURN_NEAR_ORIGIN` fails closed until a separately evidenced
`ReleasedSurfaceEgressDefinition` binds at least one released egress option to
an exact exit facility and reviewed ordinary-road handoff anchor. The accepted
access candidate freezes the only permitted return target from its original
coordinate, first resolved edge, and initial bearing. `ReleasedSurfaceEgressPlanner`
derives requests from that target, runs every released exit policy through a
release-bound provider, `DirectedRoadGraphInspector`, the exit-side hard gates,
and `JourneyPlanCompiler`, then applies the release-owned
`FASTEST_THEN_SHORTEST` ranking. Complete selected-path identity must begin on
the policy handoff edge and end on the frozen return edge; any expressway
re-entry, forbidden toll domain, provider/dataset drift, caller-selected
destination, or ambiguous graph binding fails closed. OSRM, GraphHopper, and
Valhalla implement the same bounded role. Provider alternatives and prose
remain non-authoritative.

The iPhone C2 demonstration exercises this product composition without
promoting it to release authority. It resolves the origin and destination with
MapKit, requests ordinary-road candidates around the selected Tomigaya outer
entrance and Hatsudai-minami outer exit, and renders the fixed audited C2 + B
occurrence sequence between those legs. Its normal map is no longer a relabeled
topology: it renders the bounded ODbL
`c2-b-20260729-geographic-route.json` database on MapKit, with pinned C2-outer,
Kasai connector, B-west, Oi connector, and final C2-outer node/way lineage plus
visible OSM attribution. The alternate overview remains Kaido-generated
topology with directional IC/JCT/PA semantics. Planning and driving are separate:
successful provider resolution enters a parked review that exposes both
ordinary-road legs and the immutable expressway choices, and only a second
explicit action starts playback. The driving lifecycle includes separate entry
and exit transitions, Kasai and Oi junction insets, an estimated-position tunnel
state, an App-inactive pause that requires explicit resume, and confirmed
termination. It is intentionally labeled `SIMULATION`; without a released C2
graph, provider identity, `JourneyPlan`, matcher corridor, and field evidence,
it cannot create a `KaidoProductNavigationRuntime`.

The C2 demonstration has a separate schema-1.0 app-private simulation
checkpoint. It stores the resolved endpoints, accepted surface candidates,
phase, step index, and ordered expressway occurrence progress in Application
Support and binds them to the exact bundled geographic-route database ID.
Relaunch restoration always enters a paused state and requires an explicit
resume; completion and confirmed ending remove the file. Decode failure,
database drift, invalid route boundaries, and explicit highway/toll candidates
fail restoration and remain visible as a recoverable UI warning. This
checkpoint may contain the user's local endpoint coordinates, is never bundled,
tracked, exported, or treated as matcher evidence, and cannot create released
navigation authority.

The completed return `JourneyPlan` fixes one exact egress option, and runtime
configuration filters Finish behavior to that option instead of asking
`EgressPlanner` to choose another released exit. `FINISH_DRIVE` activates the
legal egress and enters `EXIT_TRANSITION`. `NavigationSession` enters
`SURFACE_EGRESS` only after the compiler-retained
`SurfaceEgressMatcherCorridor` and its separately scoped matcher resolve two
fresh HIGH, non-simulated observations to the exact first surface occurrence
with valid heading and increasing along-edge progress. The corridor retains
graph geometry per ordered occurrence; repeated directed edges share exact
geometry but keep different occurrence IDs. The first fix is pinned to
occurrence zero, and later fixes may move only forward, so geometry cannot skip
to a later repeated traversal. The Core Location adapter receives the complete
release/runtime context and mints evidence; it neither shares the expressway
matcher session nor infers identity from a fix. The actor independently checks
product, navigation, journey, runtime-policy, snapshot, RoutePlan, egress
option, exit, handoff anchor, corridor, occurrence, edge, time, confidence,
heading, simulation provenance, and progress before changing phase. Partial or
rejected evidence is not checkpointed and cannot be supplied by UI state.
KR-S20 executes this boundary with synthetic geometry. App enrollment remains
blocked on real graph/provider output, physical-device profiling, and held-out
field reliability evidence.

Surface-egress calibration is a separate evidence domain from expressway
matching. `SurfaceEgressMatcherCalibrationScope` binds the complete product,
navigation, JourneyPlan, runtime-policy, graph, selected provider candidate,
egress, handoff, corridor, occurrence, algorithm, configuration, device, and
explicit field-transport identity. `CoreLocationSurfaceEgressMatcherCalibrationSession`
owns a fresh `CoreLocationObservationAdapter`, `SurfaceEgressMatcherSession`,
and in-memory recorder; it measures that exact pipeline in callback order and
never consumes the live expressway matcher posterior. Raw coordinates remain
only in `SurfaceEgressPrivateTrace`. The public schema-1.1
`SurfaceEgressMatcherCalibrationReport` contains scalar counts, p95 timings,
the exact evaluator floor and budget, and reliability bins but no observation,
device, mount, or head-unit detail. The evaluator rejects mixed scopes and
collection methods, gives any incorrect HIGH edge or occurrence priority over
every other gate status, and prevents synthetic or software-simulated samples
from satisfying the held-out field floor.
`SurfaceEgressMatcherCalibrationArtifactAuthor` accepts exact private trace
bytes and one exact-scope, independently reviewed private annotation set. It
hashes those bytes into a coordinate-free schema-1.0 artifact, retains only an
opaque reviewer identity and scalar review summary, and hard-codes both
navigation authority and release approval to false. Independent validation
requires the same private bytes and re-runs the evaluator; standalone structure
validation never substitutes for that private replay. These types are
profiling infrastructure, not App enrollment, field evidence, confidence
qualification, or release approval.

`NavigationReleaseArtifact` schema 6.0 is the Codable distribution envelope for
those runtime inputs. It adds a stable release identity, release time,
editor-catalog identity, a complete locale-exact editor presentation catalog,
and a source registry with HTTPS locations, pinned SHA-256 values, checked
dates, licences, and explicit asset roles. Exactly one `RELEASED` evidence
record must cover the editor catalog, editor presentation, runtime policy,
matcher corridor, every DecisionZone, every guidance prompt, and every junction
view, plus the optional surface-access and surface-egress definitions when
present. Unresolved
or unused sources, missing or orphaned evidence, duplicate asset identities,
role mismatch, junction-view provenance drift, and evidence checked after the
release date fail closed.
`NavigationReleaseArtifactCodec` validates on encode and decode, and the
resulting `NavigationRelease` always contains a freshly validated
`NavigationReleaseBundle`; decoding never bypasses runtime identity checks.
`NavigationReleaseDraft` separately carries the immutable reviewed runtime
assets, while `NavigationReleaseAuthoringConfiguration` carries explicit release
identity and provenance. `NavigationReleaseAuthor` derives the current artifact
schema, retains both inputs unchanged, and must construct a valid
`NavigationRelease` before the CLI may create an output. It exposes no synthetic
or evidence-promotion switch. KR-D25 proves authoring, version, and provenance
boundaries with synthetic values only.

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
same release validator. `RouteAtlasReleaseDraft` carries the exact reviewed
snapshot, RoutePlan, topology, layout, and occurrence bindings without
evidence. `RouteAtlasReleaseAuthoringConfiguration` separately carries the
source registry plus topology and layout release evidence.
`RouteAtlasReleaseAuthor` derives the current artifact schema, retains those
inputs unchanged, and must construct a valid `RouteAtlasRelease` before the CLI
may create a new non-overwriting output. It exposes no synthetic or
evidence-promotion switch.
Every RoutePlan occurrence has its own binding in exact RoutePlan order, while
repeated occurrences may intentionally reference the same schematic segment.
Snapshot drift, missing or extra coverage, an invented connection, incomplete
occurrence binding, or anything short of released dated topology and layout
evidence fails closed. KR-D19 executes an invented-connection rejection with
synthetic data, while KR-D28 executes the authoring/schema boundary. This gate
proves internal
consistency only; the repository still has no released real Shuto topology slice
or reviewed production atlas layout.

`KaidoProductReleaseArtifact` schema 6.0 is the outer distribution envelope a
product build must consume. It embeds the complete navigation and Route Atlas
artifacts plus an explicit `runtime_use` declaration rather than referencing two
mutable release names. `KaidoProductRelease` first
revalidates both nested gates, then requires exact `NetworkSnapshot` and
`RoutePlan` equality and a finite positive actual route distance. Its release
time cannot precede the nested navigation release or any Route Atlas source,
topology, or layout evidence. Finally, every editor-catalog initial edge,
incoming approach, movement, and outgoing edge must resolve to one unique
`routeEntityID` in the released atlas topology slice.
Coverage is over the whole released editor catalog, not only the occurrences in
the active RoutePlan. `KaidoProductReleaseArtifactCodec` validates on encode and
decode, and `kaido-release validate-product` exposes the same boundary to build
automation. KR-D26 proves that independently valid synthetic artifacts remain
product-blocked when this cross-artifact coverage is incomplete. The same
scenario then attempts `PRODUCT_NAVIGATION_RUNTIME_CREATED` and proves that the
failed release yields no partial runtime release identity. A focused positive
unit test proves that a valid joint release supplies one exact runtime
composition and that its released policy supplies executable Finish egress
without an adapter-authored default. KR-D27 proves that structural validity is
not sensor authority: synthetic releases must disable live input, mixed
synthetic/released-road source scopes fail closed, and a released-road release
with live input disabled remains valid without minting authority. Only a fully
validated `RELEASED_ROAD + FOREGROUND_WHEN_IN_USE` release can construct
`KaidoForegroundLiveInputAuthority`. Its six-part runtime identity and token
initializers are package-only, so application adapters can compare and consume
the authority but cannot invent it.

`KaidoProductReleaseAuthor` is the production assembly path into that outer
envelope. It receives the two complete artifact values and explicit versioned
release metadata, validates each nested gate independently, retains both inputs
unchanged, fixes runtime use to `RELEASED_ROAD + FOREGROUND_WHEN_IN_USE`, and
then re-runs the complete joint validator. Configuration cannot opt into a
synthetic scope or disable live input, so an unchanged preview artifact fails
the production command. `kaido-release build-product` encodes only the validated
result, creates a new file atomically, and refuses overwrite. Passing assembly
does not establish that a licence or evidence label is true and does not replace
independent provenance review, the App-catalog digest/role gate, or
physical-device qualification.

The iPhone distribution boundary adds `BundledProductReleaseCatalog` in front of
the product codec. Its compile-time descriptors pin a safe bundle resource name,
extension, SHA-256, expected release ID, and an explicit demo or foreground
role. Hash verification precedes decode. The decoded runtime-use declaration
and codec-minted authority must then match the descriptor role; manifest text
cannot promote synthetic evidence. Duplicate resources, duplicate release IDs,
missing or corrupt assets, and identity or role drift block catalog
construction.

`AppBundleReleaseStagingAuthor` is the package-time bridge into this boundary.
It accepts only a production-decoded foreground product, optionally revalidates
multiple independently complete exact-product guidance-audio releases, retains
all artifact bytes,
optionally pins public Ed25519 pre-drive evidence update trust roots and one
exact credential-free HTTPS JSON endpoint, and derives the shared descriptor
values and per-resource audit hashes.
`kaido-release prepare-app-bundle` writes those resources plus a generated
compile-time descriptor into a new atomic staging directory. It refuses
synthetic products, partial audio input, unsafe names, duplicate selection IDs,
release IDs, or resources,
invalid or duplicate trust keys, an endpoint without trust, unsafe endpoint
syntax, and existing output. Private signing keys are never staging inputs. A
maintainer must still review and explicitly enroll the
generated static symbol in the App manifest; no runtime scanning or automatic
promotion is introduced.

The retained release-backed Debug/regression journey exposes only foreground
releases. When any exist,
`ReleasedProductRouteAuthoringModel` replaces the synthetic editor and lets the
user select one catalog entry and submit each release-owned recipe choice.
`ReleasedRouteEditorAdapter` retains occurrence identity, and compilation must
equal that release's whole `RoutePlan`. Review becomes available after that
exact compilation. The user may then select one canonical
`ShutoVehicleClass` and one independent `ShutoPaymentMethod` for current toll
information; the provider
receives a `PreDriveReviewSession` bound to that exact RoutePlan, snapshot,
class, and payment method. Its evidence envelope and every quote must match.
Only matching information may be presented as current, but missing or expired
information does not own route authority. A current known closure or planned
conflict still blocks the explicit user-start action.
The action constructs
`ProductNavigationRuntimeModel` from the selected entry, reuses the codec-minted
live-input authority, and enters the navigation stage without starting Core
Location. A second explicit action starts foreground location only after actor
activation and When In Use authorization. Runtime construction failure stays in
pre-drive review; route invalidation or a newly admitted current closure
terminates an active runtime. Ending navigation stops input and speech, removes
the active checkpoint, and returns to review. Its retained catalog carries one
foreground K7 release and one synthetic demo; neither is the default
whole-Shuto delivery route. The foreground entry carries one dated, hash-bound K7
pre-drive bundle with all ten canonical vehicle/payment profiles. It admits
current-information presentation only within that bundle's exact validity
window, becomes a stale-information warning after expiry, and never substitutes
the demo or its synthetic review for the released route.

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
the broader Kawamuki corridor as municipal Higashikatacho Route 342 and the
temporary passage then used inside the land-readjustment area. A 2023 City
Council resolution later recognizes Higashikatacho Routes 354 through 358
inside the completed replotting area, but the area-level reference map does not
uniquely map the target OSM way to one route. The online recognized-route map is
dated 2026-07-03. A 2026-07-25 browser inspection selected the exact three
source-adjacent features and displayed the southern feature corresponding to
way `776884422` as `東方町第356号線`, while the two east-west successors displayed
as `高速横浜環状北西線`. Yokohama states that online material is not proof and
directs latest legal-record review to its counter, so this narrows the exact
counter request without establishing the way's current legal-record identity,
physical status, legal direction, or permitted exit movement. The derivative
database preserves
257 route and alternative nodes, complete selected-way tags, parent PBF and
bounded-extract hashes, extraction bounds, OSM timestamp, and reconstruction
tooling. Its 13 route occurrences, 15 topology
edges, and 15 layout segments pass internal identity and successor validation.
A separate deterministic audit compares the complete source adjacency at 14
entry, route, divergence, and exit checkpoints. The pinned extract yields 19
outgoing successors and no applicable turn-restriction relation. This proves
source translation completeness, not road legality: the third surface way has
an official historic identity but no current road-level direction or
permitted-movement review. The coordinate-free field-review validator requires
four current, lawfully passenger-collected, hash-bound checkpoints, an
independent reviewer, an exact privacy allowlist, and no more than 31 days of
validity. It refuses completed in-repository manifests outside ignored
`research/`, exposes no raw media or location in its report, and still grants
no Route Atlas release authority.
The separate exact road-register validator accepts only a current map-66 record
obtained at the City of Yokohama Road Survey Division counter. It requires a
hash-bound private record, explicit comparison of all three exit-terminal OSM
successors, selection of exact way `776884422`, independent review, and a
coordinate-free report. Online map inspection, map 67, historic corridor
identity, raw copied geometry, and a nonexact mapping cannot satisfy it.
The dated readiness package binds exact topology and layout release-review
records. Schema 2.0 scopes the first candidate to the exact
Yokohama Kohoku exit handoff: the terminal expressway occurrence is retained,
all three ordinary-road successors are excluded, and no `SURFACE_EGRESS` is
released. The current road-register and field findings remain separate future-
scope gates for any later surface-egress expansion; they are neither required
nor treated as satisfied for this exit-only topology review. A layout approval
depends on the current topology approval and must use a different reviewer.
Each approval is valid for at most 31 days. Evidence state and review approval
are conjunctive: changing a candidate to `RELEASED` without the matching
current approval cannot satisfy the readiness gate. The generated candidate
continues to carry two `CANDIDATE` states so deterministic rebuilds and
KR-D22/KR-D23 remain negative controls. On 2026-07-27, different independent
reviewers approved the exact exit-only topology and layout. A deterministic
input builder projects immutable candidate content into a draft and derives a
separate authoring configuration whose two `RELEASED` evidence dates match
those approvals. The resulting schema-1.0 Route Atlas artifact passes
`kaido-atlas validate-release`. It still grants no navigation, realtime, or
surface-egress authority.

The first Kaido-owned K7 schematic candidate replaces raw source geometry only
in the layout definition. It covers the same 15 topology edges, preserves both
expressway divergences and all 13 occurrence bindings, and carries a separate
Apache-2.0 layout source record. The renderer visibly terminates at
`osm.node.7473451738`; none of the three adjacent surface ways is present in
the layout. KR-D24 proves that the candidate artifact has no structural release
issue beyond the two intentional candidate evidence states. The subsequent
independent layout approval and final authoring artifact release only this
renderer-neutral exit-handoff Atlas; they do not grant surface-movement or
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
  context establishes the recognizable full-network shape, while released Route
  Atlas data may become selectable or carry RoutePlan occurrence state only
  through a validated `KaidoProductRelease`; a standalone `RouteAtlasRelease`
  has no navigation or editor authority.
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
- `RouteAtlasJourneyProjector` now implements the release-to-renderer boundary.
  It accepts only one validated `RouteAtlasRelease` and an optional exact
  actor-owned `NavigationSnapshot`, validates the completed/current/pending/
  skipped occurrence partition, and emits immutable context segments, ordered
  occurrence tracks, repeat ordinals, and adjacent source attribution. Before
  actor activation all occurrences are `PLANNED`; afterward the renderer
  receives only `PASSED`, `CURRENT`, `FUTURE`, or `SKIPPED`. Identity or order
  drift blocks the overlay. The projection carries no coordinate and cannot
  authorize or imitate a measured-position marker.
- Phone and CarPlay receive the Route Atlas value from an already validated
  `KaidoProductRelease`; renderers never infer connectivity from line
  intersections or author an alternate successor graph. Before a real joint
  product release exists, concept compositions must be marked
  topology-unverified and not for navigation.
- The retained internal release-backed Debug scene sequences Route Atlas,
  parked authoring,
  pre-drive review, and a locked navigation stage through
  `KaidoProductJourneyModel`. This coordinator owns presentation stage only. It
  selects the synthetic preview editor only when the catalog has no foreground
  release. Otherwise it observes release-owned authoring and separately admitted
  pre-drive information. Route invalidation returns to authoring and terminates
  an active runtime; missing or expired dynamic information remains a warning,
  while a current known closure or planned conflict blocks start. The
  coordinator cannot convert a structurally valid synthetic or mismatched
  release into navigation authority. The former all-panel evidence workbench
  remains a launch-only internal surface.
- The App owns one persisted interface-locale environment with exact Japanese,
  Simplified Chinese, and English copy. The selection is visible in the default
  whole-Shuto journey and retained release-backed surfaces. It changes atlas,
  entrance explanation, parked editor, pre-drive review, voice setup, and
  released-navigation chrome immediately. It does not mutate
  the separately persisted guidance-voice locale, reinterpret RoutePlan values,
  translate evidence codes, or replace release-owned editor and guidance
  catalogs. Synthetic entrance and editor labels must be complete in all three
  locales before the preview model initializes; production labels remain a
  release gate.
- A precise vehicle bead requires fresh route-resolved evidence. Degraded,
  ambiguous, tunnel, or stacked-road positioning renders an honest segment or
  uncertainty halo rather than a falsely precise point.
- The bounded surface access and egress screens may use MapKit for geographic
  context and render accepted provider geometry as overlays.
- A junction inset is drawn from `JunctionViewDefinition` with a Kaido-owned
  vector renderer. SwiftUI must not retain or reproduce third-party junction
  artwork. The internal iPhone renderer now maps normalized path points and
  left-indexed lane values directly from one synthetic definition; it does not
  infer a path from labels or create a CarPlay scene.
- Complex authoring is disabled while moving.
- SwiftUI renders `ExpertRouteEditorSnapshot` and submits stable reviewed choice
  or lap-candidate IDs. `KaidoRouting`, not the view tree, owns the current
  incoming approach, legal movement set, reviewed closed-sequence matching,
  fresh occurrence creation, grouped parked undo, and explicit exit completion.
  A release may provide a validated `ReleasedRouteAuthoringRecipe`;
  `ReleasedProductRouteAuthoringModel` resolves its locale-complete option and
  current step, but the UI still submits each choice and cannot promote a
  partial or alternate authored route back into the exact released RoutePlan.
  KR-U01 and KR-U02 execute this pure boundary; the currently bundled SwiftUI
  editor still uses a synthetic catalog and does not release real Shuto
  authoring data.
- A freehand gesture is only adapter input. `ParkedCorridorResolutionSession`
  accepts a geometry match only when its snapshot, RoutePlan, current decision
  point, and candidate choice values still match `ExpertRouteEditorSnapshot`.
  Zero or one matches never author a route automatically; multiple matches
  require an explicit parked choice. Resolution returns one reviewed choice,
  which must still pass through `ExpertRouteEditorSession` with fresh occurrence
  IDs. KR-U03 and the internal synthetic Canvas execute this boundary without
  implementing production snapping or layout matching.
- The pre-drive adapter consumes only the compiled exact RoutePlan. A
  same-snapshot reviewed-distance catalog may populate actual distance by
  walking ordered occurrences. `PreDriveReviewEvaluator` then binds a separately
  dated evidence set to an independently constructed `PreDriveReviewSession`
  containing the exact snapshot, RoutePlan, canonical Shuto vehicle class, and
  independently selected ETC or cash path. The evidence envelope must match
  before every tariff record is validated, and exactly one `ACTIVE` version is
  selected. A provider cannot drift its envelope and every quote together to
  another profile; one proposed or retired quote for another class or payment
  path also rejects the whole evidence set.
  Tariff and passage evidence remain session inputs rather than versioned
  product assets. `PreDriveEvidenceBundle` now provides the first operational,
  non-network provider: a separately hash-pinned schema-1.0 manifest binds the
  exact product/navigation/snapshot/RoutePlan identities, reviewed tariff and
  passage sources, one vehicle/payment profile per record, and an exclusive
  runtime expiry. The App catalog decodes it only beside the matching foreground
  product, and the released authoring model resolves it at the current time by
  default. Missing, not-yet-valid, expired, or unlisted profiles fail closed as
  current information and cannot reuse another record, but do not revoke the
  independently validated RoutePlan.
  `PreDriveEvidenceBundleAuthor` now constructs that manifest from a
  release-authority-free reviewed draft plus separate release metadata. The
  exact product supplies product/navigation/snapshot/RoutePlan and
  entrance/exit identity, while each record supplies its vehicle/payment
  profile once; neither can be overridden per quote. The production CLI fixes
  scope to `RELEASED_ROAD`, requires codec-minted foreground authority, and
  writes no output before the whole bundle gate passes.
  `PreDriveEvidenceUpdateCodec` adds a signed refresh boundary without changing
  product or RoutePlan authority. It signs exact validated manifest bytes with
  Ed25519 and verifies a domain separator, key ID, SHA-256, compile-time public
  key, exact foreground product, and the whole evidence bundle. The parked App
  supports manual local import and an explicit refresh from one compile-time
  pinned, credential-free HTTPS JSON endpoint for the selected product. The
  bounded transport rejects redirects, final-URL drift, credentials, cookies,
  caches, non-200 or non-JSON responses, and oversized envelopes; it cannot
  bypass codec validation. The App rejects rollback and release-ID reuse,
  persists before publishing, and re-verifies on restoration. A future bundle
  cannot activate early, and once effective it cannot fall back to older
  profiles. Endpoint changes, trust rotation, or revocation still require an
  App release. Until a live authority contract exists, the evaluator rejects
  `REALTIME_CONFIRMED_PASSABLE`; realtime-unconfirmed stays neutral.
  SwiftUI renders the resulting KR-U04 projection and cannot derive one distance
  from the other. `ReleasedPreDriveReviewAdapter` exposes the same evaluator for
  one validated joint product release. Its evidence remains a separate
  current-session input; missing or identity-drifted evidence cannot fall back
  to the internal synthetic review. The journey shell exposes review after the
  exact release-owned RoutePlan compiles. It labels missing or expired dynamic
  information without treating it as current, and it may display the last
  bundled checked value as stale. Route invalidation demotes the shell back to
  authoring; a current known closure or planned conflict blocks start and
  terminates an active runtime. The checked foreground K7 descriptor contains
  one dated, hash-bound evidence bundle whose expiry no longer revokes route
  authority. A future operator-backed live refresh still requires independent
  authority, freshness, data-use, and failure-policy review.
- A synthetic language-preview adapter independently selects the interface and
  guidance-voice locales from one validated `GuidanceFrame`. It renders the
  Japanese sign target and route shield unchanged beside localized explanatory
  text. It supplies no prompt emission and therefore has no speech authority.
  KR-U05 and KR-U11 cover this adapter boundary; the App applies the independent
  interface preference to its app-owned chrome, while
  internal-workbench localization and pronunciation review remain pending. The
  separate product-runtime adapter
  exercises the implemented speech scheduler and Apple output lifecycle without
  allowing this text preview to speak.
- A synthetic driving-surface adapter executes stale LOW location evidence and
  Finish drive through `NavigationEngine`, then renders only the resulting
  `NavigationPresentationProjection`. SwiftUI maps `MEASURED`, `ESTIMATED`,
  realtime-unconfirmed, moving DecisionZone editing lockout, and the selected
  egress exit to explicit visual states without upgrading evidence or selecting
  an exit. KR-U06, KR-U07, KR-U08, and KR-U12 cover this local adapter boundary.
  A fourth state invokes `NavigationEngine.connectCarPlay()` and proves KR-U10
  surface ownership plus KR-U14 shared junction-view identity. Both projections
  retain one occurrence, prompt, distance, maneuver, lane preparation, sign,
  shield, and definition; only `isPrimarySurface` changes. The iPhone labels
  this as fixture-only and has no `CPMapTemplate` or CarPlay scene. The panel is
  not an active `NavigationSession` or released-route renderer. KR-U09 adds
  localized assistive semantics to that same projection, a 4.5:1 tested
  critical text contrast floor, non-color selected-path and preferred-lane
  cues, and a single-column accessibility Dynamic Type layout. Local XCUITest
  covers standard and AXXXL Simulator sizes; it is not full-app, device, or
  CarPlay accessibility qualification. The separate joint-product runtime panel
  now uses one actor-returned projection to render its iPhone driving surface and
  corresponding CarPlay/voice identities. Its fixed synthetic input control is
  an internal adapter proof, not a second navigation state or live input source.

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
simulator rendering, termination timing on a physical device, and wired/wireless
head-unit behavior remain platform integration and field-test gates.

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

The iPhone route-choice adapter executes that boundary as a complete-set
comparison. It evaluates access and egress concurrently for each already exact
`ShutoRouteRecommendation`, retains each `RoutePlan` byte-for-byte, and replaces
only the surface component of its ranking score. All candidates must resolve
before provider metrics can reorder the row or appear as full-journey
comparisons. Partial provider results may be cached for the selected journey,
but they cannot be compared against unresolved candidates. MapKit is the
default no-extra-credential implementation; other providers enter through the
same surface boundary after account, licence, and executable qualification.

`SurfaceApproachPolicy` is the provider-neutral release shape for those hard
filters. Private entrance fixtures can project into it for bake-off execution,
but a product release must carry and evidence the policy independently. The
compiler compares the full directed anchor, entrance, selected first
occurrence, provider identity, exact inspection snapshot, and optional
snapshot-bound selected-path evidence. It preserves repeated resolved edges and
cannot alter the Shuto RoutePlan.

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
and the live matcher handoff. A separate entry adapter uses the same preserved
provenance and the product-release admission context; it does not infer wired or
wireless transport and cannot grant navigation progress itself. Its typed output
is accepted only by the actor's ordered entry-evidence gate. These tests do not
replace iPhone/head-unit field tests.

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
→ phone / CarPlay / released offline audio or AVSpeech fallback
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

The speech adapter retains a second, output-local consumed set using the full
`prompt_id + anchor_id + anchor_occurrence_id` identity. This does not replace
the engine ledger; it prevents duplicate projection delivery or delayed speech
callbacks from replaying an already admitted command. A new command replaces
older in-flight speech, while stale completion callbacks cannot clear the newer
identity. Audio interruptions drop, rather than queue, prompts so resumption
does not deliver obsolete maneuver guidance.

An optional `GuidanceAudioRelease` is complete and occurrence-scoped rather than
a generic phrase cache. The manifest covers every released anchor and locale,
binds exact spoken content and local WAV hashes to the same product and route
identities, embeds the passed exact-WAV human review, and is hash-pinned by the
bundled release catalog. Exact matches use recorded playback; absent or
unstartable assets fall back to the installed Apple voice. A prompt that already
began recorded playback is never replayed after an interruption or decoder
failure. Multiple such releases may be attached to one product as selectable
voice packs, but each remains independently all-or-nothing. Runtime never mixes
assets across packs.

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

The live-session checkpoint is separate from graph storage and saved routes:

- encode only coordinate-free navigation reducer state in schema 2.0;
- bind every checkpoint to the exact validated product/navigation release,
  journey plan, runtime policy, network snapshot, RoutePlan, and matcher
  corridor;
- atomically replace one active-session file and delete it on the next lifecycle
  save after completion, or after an explicit discard;
- never restore matcher posterior, a measured marker, partial entry continuity,
  CarPlay ownership, active audio, or a one-shot prompt emission; and
- require a fresh multi-observation location window before measured progress
  resumes.

The C2 simulation checkpoint is deliberately separate from this released
live-session checkpoint. Its provider coordinates and playback index restore
only local demonstration continuity, never a measured marker or release-owned
state.

The whole-Shuto replay uses a separate schema-2.0 app checkpoint. It binds the
candidate network snapshot, the complete replanned `RoutePlan`, directional
entry and exit, selected preference, recommendation/custom/circuit selection
source, circuit identity and lap count when applicable, bounded surface legs,
phase, map mode, and consumed output prompt IDs. Entry-transition and
expressway checkpoints additionally carry the exact
`ShutoRuntimeAssetIdentity`; restoration recompiles the route-local assets from
the bundled graph and requires both the network-artifact and route-runtime hashes
to match before reconstructing replay state. The hash is an integrity check,
not release authority.

A custom or circuit checkpoint restores its selection only after the exact plan
is reconstructed; the source flag cannot substitute for `RoutePlan` equality.
A prior schema or `RoutePlan` drift is rejected before any journey state is
restored. Load, schema, snapshot, phase, route, runtime-identity, save, and
removal failures publish a distinct checkpoint issue instead of looking like
an empty first launch. A rejected or failed replacement also removes the old
checkpoint when storage remains writable, so stale progress or a stale spoken-
prompt ledger cannot reappear on the next launch. Runtime-asset drift returns
the reconstructed route to parked Review instead of restoring progress. An
entry-transition checkpoint must retain zero route progress and no runtime
occurrence or fraction. Restoration is paused, discards matcher posterior and
partial entry continuity, and resumes from the first generated entrance
observation. An expressway restore resumes at the saved occurrence but admits
no new progress until another HIGH replay observation. App inactive/background
cancels replay, stops current speech, and saves consumed prompt IDs so
reconstruction cannot repeat an admitted command. Any checkpoint marked as live
is also returned to parked review with
`WHOLE_SHUTO_NAVIGATION_RELEASE_REQUIRED`; the candidate product never
reconstructs `ShutoLiveDriveSession`. This is replay termination recovery, not
background navigation or released-session evidence, and it cannot mint
live-input authority.

For the first small graph:

- keep source fixtures human-reviewable and separate by licence;
- compile a read-only, versioned snapshot for the app;
- use SQLite with an R-tree or an equivalent compact index for geometry lookup and
  metadata, then build small in-memory adjacency arrays for search;
- store saved route plans as occurrence-based records tied to a snapshot ID;
- reject incompatible or partially migrated snapshots before navigation.

The first saved-route implementation follows that direction without adopting a
UI object graph. `FileSavedRouteLibraryStore` atomically replaces one validated
schema-1.0 library under Application Support. Every record contains a complete
`SharedRouteDocument`; storage origin remains separate from its evidence state.
The App's `SavedRouteLibraryModel` uses the pure
`SavedRouteLibraryEditor` to validate current-schema JSON imports, assign
`SHARED_IMPORT` provenance, rename local display metadata, export the exact
shared document, or delete one stable record. It persists each complete result
before publishing it to SwiftUI; failed I/O cannot expose an uncommitted
library. Unsupported schemas are rejected rather than implicitly migrated.

The retained release-editor path can reopen a record only after
`SavedRouteReleaseMatcher` finds exactly one whole-RoutePlan-equal current
foreground release. Reopening selects that release's parked
`ReleasedRouteEditorAdapter`; it does not replay choices, compile, admit
pre-drive evidence, or start navigation. Missing, corrupt, snapshot-drifted, or
ambiguous release state stays fail-closed.

The default whole-Shuto planner has a separate current-snapshot resolver.
`savedRouteAvailability` first requires the exact bundled snapshot ID, then
reconstructs and validates every ordered occurrence against the current graph,
including repeated edges, reviewed junction-movement occurrences, directional
entry/exit bindings, and circuit laps. Only that exact match is labeled
`CURRENT SNAPSHOT`. `openSavedRoute` is parked-only, preserves the complete
saved `RoutePlan`, resolves fresh bounded surface legs, and enters Review for a
labeled replay. Template source is validated separately: a circuit source must
name a bundled circuit and legal lap count whose newly planned complete
`RoutePlan` exactly equals the saved plan; custom and recommendation sources
cannot carry circuit fields. Valid template parameters survive reopen and
re-save instead of silently degrading a circuit to custom. None of this selects
a product release or promotes the saved document's evidence; live start remains
`WHOLE_SHUTO_NAVIGATION_RELEASE_REQUIRED` until an authority-bearing release is
enrolled.

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

## Sources checked through 2026-07-30

- [Apple MapKit for SwiftUI](https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui)
- [Apple `MKDirections.Request`](https://developer.apple.com/documentation/mapkit/mkdirections/request)
- [Apple `MKRoute` geometry](https://developer.apple.com/documentation/mapkit/mkroute/polyline)
- [Apple CarPlay navigation integration](https://developer.apple.com/documentation/carplay/integrating-carplay-with-your-navigation-app)
- [Apple `CPManeuver` junction images and maneuver metadata](https://developer.apple.com/documentation/carplay/cpmaneuver)
- [Apple `CPLaneGuidance`](https://developer.apple.com/documentation/carplay/cplaneguidance)
- [Apple background location guidance](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
- [Apple SwiftUI `ScenePhase`](https://developer.apple.com/documentation/swiftui/scenephase)
- [Apple `CLLocation` source information](https://developer.apple.com/documentation/corelocation/cllocation/sourceinformation)
- [Apple external-accessory location source](https://developer.apple.com/documentation/corelocation/cllocationsourceinformation/isproducedbyaccessory)
- [Apple software-simulation location source](https://developer.apple.com/documentation/corelocation/cllocationsourceinformation/issimulatedbysoftware)
- [Apple location timestamp](https://developer.apple.com/documentation/corelocation/cllocation/timestamp)
- [Apple horizontal location accuracy](https://developer.apple.com/documentation/corelocation/cllocation/horizontalaccuracy)
- [Apple course accuracy](https://developer.apple.com/documentation/corelocation/cllocation/courseaccuracy)
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
- [Valhalla Meili matching configuration](https://valhalla.github.io/valhalla/meili/configuration/)
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
- [Google road-snapped location updates](https://developers.google.com/maps/documentation/navigation/ios-sdk/reference/objc/Protocols/GMSRoadSnappedLocationProviderListener)
- [Google route location simulation](https://developers.google.com/maps/documentation/navigation/ios-sdk/reference/objc/Classes/GMSLocationSimulator)
- [Mapbox navigation pricing reference](https://www.mapbox.com/pricing)
