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
the tracked full-network and K7 Route Atlas assets. Its default launch is now one
ordered route-first journey instead of the former vertically stacked evidence
workbench: Route Atlas recognition leads to parked authoring, an exact compiled
RoutePlan unlocks pre-drive review, and navigation remains visibly locked until
a real joint product release grants authority. Returning to edit and
invalidating the compiled route automatically removes review readiness. The
original internal workbench remains available through a dedicated launch
argument. The journey presents a synthetic directional-entrance recommendation,
parked route authoring, RoutePlan-bound pre-drive review, and a parked
guidance-voice sound check without calling live location or surface routing.
Its visible, persisted interface selector switches the default journey among
Japanese, Simplified Chinese, and English immediately. App-owned copy for the
atlas, entrance explanation, parked editor, pre-drive review, voice setup, and
released navigation surfaces follows that one interface locale, while
release-owned guidance and editor labels still come from their exact validated
locale catalogs. Changing the interface locale does not change the independently
persisted guidance-voice locale. Japanese sign text, route shields, raw
occurrence identity, and evidence codes are never translated away.
The sound check independently selects Japanese, Simplified Chinese, or English,
enumerates only installed exact-synthesis-locale Apple voices, keeps one
device-local preference per language, and plays one fixed locale-specific sample
through a separate output with no route, position, occurrence, or prompt-ledger
input. Its bundled product-release catalog is a
compile-time manifest: every resource is pinned to an exact filename, SHA-256,
release ID, and `DEMO_ONLY` or `FOREGROUND_NAVIGATION` role before the production
codec runs. Navigation selection requires whole-`RoutePlan` equality and fails
closed on zero or multiple released-road matches. When a foreground entry is
present, the journey replaces synthetic authoring with that release's localized
editor recipe, requires every stable choice explicitly, retains its exact
occurrence sequence, and admits review only after separately supplied current
tariff and passage evidence evaluates against the same RoutePlan and network
snapshot. The user must first select one of the five canonical Shuto vehicle
classes and select the ETC or cash tariff path independently; the evidence
provider receives that exact session request, and its envelope plus every tariff
quote must match both selections. The first operational provider is now an
optional compile-time, hash-bound schema-1.0 pre-drive evidence bundle attached
to the exact foreground product. It retains separate reviewed tariff and
passage source roles, resolves only one exact vehicle/payment profile inside its
declared validity window, and fails closed when missing, not yet valid, or
expired. It does not fetch live services or claim realtime-open authority. The
release CLI now builds that manifest from a reviewed identity-free draft,
deriving product, RoutePlan, entrance/exit, and quote-profile identity instead
of accepting copied values. A schema-1.2 App staging descriptor may
additionally pin public Ed25519 trust roots and one exact credential-free HTTPS
JSON endpoint for signed evidence updates. The CLI generates an offline
private/public key pair, signs exact validated manifest bytes, and validates
the self-contained envelope. The parked App can import that envelope locally or
explicitly fetch it from the selected product's pinned endpoint. Both paths
require the same whole-product signature validation, persist before publishing,
reject rollback and release-ID reuse, revalidate on restoration, and never fall
back after a newer effective bundle loses or expires a profile. The current
manifest contains zero foreground releases and one synthetic demo, so that branch
remains dormant. A separate
synthetic guidance panel lets interface and voice locales vary independently
while retaining one Japanese sign target and route shield; it previews text only
and has no audio authority. A synthetic driving-surface panel contrasts measured
and estimated markers, keeps realtime-unconfirmed passage neutral, locks route
editing in a moving DecisionZone, executes a precomputed Finish-drive exit, and
renders one immutable occurrence-bound junction definition with shared
phone/CarPlay projection ownership.
Another internal panel decodes one complete `SYNTHETIC_TEST_ONLY` joint product
release, constructs `KaidoProductNavigationRuntime`, and publishes the actor's
atomic planning snapshot into SwiftUI. Its strict-entry gate stays locked and
its Core Location input stays disconnected by default. A renderer-neutral
journey projection now converts only that exact validated Route Atlas release
plus its optional actor snapshot into planned, passed, current, future, and
skipped occurrence tracks. The SwiftUI overlay keeps all released topology as
quiet context, preserves repeated traversals as separately numbered tracks,
shows adjacent source and licence attribution, and never derives a position
marker or occurrence progress itself. RoutePlan, release, binding, or actor
progress drift blocks the overlay instead of drawing a best-effort route.
The parked journey now also persists named routes as schema-1.0 saved-route
library records in Application Support. Each record embeds the complete
`SharedRouteDocument`, including snapshot, evidence state, template parameters,
and every ordered occurrence. The parked library can import or export that
validated JSON document, rename local display metadata, and delete one exact
record after confirmation. Import records `SHARED_IMPORT`, and unsupported
schemas are rejected rather than migrated. Storage and file operations never
grant navigation authority. A saved record may reopen only when its whole
`RoutePlan` equals exactly one current foreground product release; zero,
multiple, invalid, or snapshot-drifted matches remain visible but cannot leave
the Route Atlas stage. Reopening selects that release's parked editor and still
requires every release-owned choice, compilation, current pre-drive evidence,
and explicit navigation start.
The app also exposes an opt-in,
foreground-only internal Core Location calibration harness bound to the exact
review-only K7 ODbL candidate corridor. The harness keeps raw location in memory,
emits only a coordinate-free non-release report, and rejects simulated locations
by default. A machine-readable attribution catalog now drives a native evidence
strip adjacent to every Route Atlas; the K7 strip visibly links OpenStreetMap
credit and the ODbL 1.0 licence without making the SVG interactive. The app
remains explicitly review-only: it has no real-road released
route bundle, live measured-position display, real-road active-route highlight,
qualified device voice, active background location session, or CarPlay scene. The
repository still has no production road database or released provider
integration. It includes a
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
The internal iPhone shell now owns the explicit when-in-use permission and
delegate lifecycle for a foreground calibration run. It validates the tracked
13-occurrence/15-edge K7 candidate before constructing the session, requires
explicit device/mount metadata, keeps connected-unknown separate from declared
wired/wireless context, and discards the memory trace on command. No real
iPhone/head-unit trace has been collected yet, so device performance and
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
ownership boundary. KR-U09 adds localized assistive labels for the same
projection, non-color branch and lane cues, tested theme contrast, and an
accessibility-size single-column SwiftUI layout for the synthetic driving/JCT
panel. A RoutePlan-bound speech scheduler now admits only the same transient
prompt/anchor/occurrence projection, suppresses duplicate SwiftUI delivery,
preempts stale speech for a newer prompt, and drops interrupted prompts without
catch-up replay. The Apple adapter uses `AVSpeechSynthesizer` with the
turn-by-turn `voicePrompt` audio-session mode, temporary ducking, explicit
interruption handling, and typed unavailable-voice/audio-session failures. It
selects only an exact-locale installed voice, excludes novelty and personal
voices, prefers premium over enhanced over default quality, and applies a
neutral Apple rate and pitch so app-side tuning does not exaggerate compact
voice cadence. After the first admitted prompt, the runtime panel exposes the
actual selected voice and quality. A default-only result is visibly marked as a
basic fallback with the device installation path. The 2026-07-24 checked
Simulator exposes only default-quality `Kyoko / ja-JP`,
`Tingting / zh-CN`, and `Samantha / en-US`; enhanced or premium acoustic
quality still requires the corresponding voice asset on a physical device.
The pre-drive sound check exposes the same installed voice ranking, persists an
explicit identifier or automatic highest-quality preference independently for
each language, and plays a representative route-shield/destination sample only
while parked. When an explicitly selected basic voice has a higher-ranked
installed replacement, the sound check can audition that exact candidate
without changing navigation; only a completed exact-candidate audition followed
by explicit confirmation persists it. Resolution drift fails closed. Release
locales are translated to exact Apple synthesis locales (`ja-JP`, `zh-CN`, and
`en-US`) before voice resolution. The real one-shot output reads that preference
only after an actor-owned prompt has been admitted; the independent audition
output cannot create or consume a navigation prompt. Apple voice is now also an
explicit fallback behind an optional offline guidance audio release. That
release must cover every released guidance anchor occurrence in all three
locales and bind each exact spoken string to a flat local PCM16 WAV resource,
SHA-256 digest, byte count, audio metadata, model or recording provenance, and
the same product, navigation, snapshot, and RoutePlan identities. Schema 1.2
also embeds one exact-WAV human review per asset; pronunciation,
intelligibility, and audio quality must all pass before authoring. The entire
audio release is rejected for missing, extra, corrupt, silent, future-reviewed,
review-incomplete, or identity-drifted content. Runtime selection does not fuzz
text or reuse another occurrence: an exact asset plays through `AVAudioPlayer`,
while a lookup or playback-start failure uses the selected installed Apple
voice. Interruption after recorded playback begins consumes the prompt without
replaying it through fallback. The bundled product-release catalog can declare
and hash-pin one such manifest; the current preview catalog declares none, and
no audition output is presented as a reviewed release asset. The synthetic
runtime panel exercises this boundary with injected output, retains the
exact phone/CarPlay/voice projection constructed from one actor update, and
remains input-disconnected by default. Its explicit fixed synthetic trace proves
that visual refresh and one-shot voice authority stay separate without creating
a second UI progress state. The default journey now also has a dormant
released-road path: one exact catalog-selected `RoutePlan` can create only its
codec-admitted product runtime after an explicit user action, then exposes a
second explicit control for foreground location. Demo releases cannot enter
that path, ending navigation removes the active checkpoint, and missing or
ambiguous releases remain locked. No real release is bundled, so this
composition is structurally tested but not real-road or device evidence.
Production corridor construction, DecisionZone calibration, CarPlay entitlement,
internal-workbench localization, full device accessibility validation,
pronunciation, and physical location/audio/CarPlay hardware behavior remain
unimplemented or unproven.

The entrance recommendation boundary now returns a structured selected facility,
exact target carriageway, legal join occurrence, surface ETA, straight-line
distance rank, hard-filter reason codes, and rejected-candidate reasons. Invalid
candidate identity or metrics reject the whole recommendation; an unavailable,
unknown, or route-incompatible approach cannot win. KR-D16 and KR-D17 retain the
routing rules, while KR-U13 proves that an iPhone adapter can explain why the
selected exact directional entrance is farther than rejected nearby candidates.
The internal iPhone shell binds one synthetic recommendation to the exact
entrance and initial occurrence used by its editor. It uses no live location or
provider result and releases no real entrance.

The parked expert-authoring boundary is executable independently of SwiftUI.
`ExpertRouteEditorSession` starts from one exact directional entrance and a
snapshot-bound reviewed catalog. Its cursor names the incoming approach and
junction complex, exposes only that decision point's legal choices, appends
fresh movement and outgoing-edge occurrences, supports reviewed cycles, and
compiles only after an explicit directional exit choice. A reviewed lap template
names one exact closed choice sequence. Only an authored match becomes an opaque
lap candidate; duplication copies semantic values into fresh occurrences and is
one grouped parked-undo action. UI code cannot infer closure, submit a future
decision's choice, reuse an occurrence ID, or edit while moving. KR-U01 and
KR-U02 execute this stateful boundary. KR-U03 adds a separate parked corridor
resolver between freehand geometry matching and the editor. It accepts only the
exact current snapshot, decision point, and reviewed choice IDs; ambiguity
requires an explicit choice and still cannot append occurrences by itself. The
release boundary additionally constructs a `ReleasedRouteAuthoringRecipe`.
It proves that every ordered movement/edge occurrence, toll domain, directional
destination, and repeated traversal in the exact released `RoutePlan` can be
replayed through that same catalog. It exposes stable choice and occurrence IDs
for user submission, never selects them automatically, and returns the exact
released plan—including reviewed actual distance—only after the parked session
matches every field and occurrence. The internal iPhone shell now composes the
same session through a synthetic parked-only catalog. A separate release-bound
iPhone adapter consumes the validated localized presentation catalog without
raw-ID fallback and can replay only the exact recipe-owned choice and occurrence
IDs before regaining the released RoutePlan. If the bundled catalog contains a
foreground release, `ReleasedProductRouteAuthoringModel` and its SwiftUI panel
list only those entries, submit each recipe choice explicitly, and reject any
compiled value that is not exactly the selected release's RoutePlan. The
currently bundled synthetic editor still renders its immutable choices and lap
candidates, preserves repeated occurrences, uses session-owned undo, and
unlocks compilation only after an explicit exit. Its synthetic Canvas sends no
geometry semantics to the editor; a fixed fixture returns two candidate choice
IDs, and XCUITest proves a drag requires parked resolution before the editor
advances. This is an adapter proof, not production snapping or released Shuto
authoring data; the actual released editor catalog and localized text, reviewed
layout geometry, matching tolerances, topology rendering, and physical-device
accessibility validation remain pending.

After exact compilation, the internal iPhone shell resolves actual distance from
a same-snapshot synthetic reviewed-distance catalog and opens a KR-U04 pre-drive
review. The review binds to the exact RoutePlan, entry, and exit, selects exactly
one `ACTIVE` tariff record, and keeps actual route distance, tariff distance,
toll evidence, and passage evidence visibly separate. A repeated lap increases
actual distance without changing the independent tariff record. The fixture is
synthetic, realtime passage remains unconfirmed, and navigation start stays
locked because no released navigation bundle exists. The foreground-release
branch uses the same evaluator through `ReleasedPreDriveReviewAdapter`; missing
or drifting per-session evidence, including a provider envelope and all quotes
that drift together from the user's independently selected vehicle class or
payment method, keeps the exact compiled released route in authoring and cannot
fall back to the synthetic review. ETC is not encoded as a vehicle class, and a
payment selection alone does not prove that the directional entrance accepts
that method. A current authorized evidence provider is not yet connected.

The internal iPhone shell now also binds KR-U05 and KR-U11 through a synthetic
guidance-language preview. Japanese, Simplified Chinese, and English interface
choices select only reviewed display content, while the voice locale selects its
own reviewed spoken text. The Japanese sign target and route shield remain
unchanged for every combination. A missing locale or translated replacement for
the Japanese sign fails projection. The preview deliberately supplies no
`GuidancePromptEmission`, labels audio as unconnected, and cannot speak; it is
not full-app localization, pronunciation evidence, or an audio-lifecycle
implementation.

The internal iPhone shell also executes KR-U06 through KR-U10, KR-U12, and
KR-U14 through a four-state synthetic driving preview. Its degraded DecisionZone state
feeds a stale LOW observation through `NavigationEngine`, so the shared
projection renders an estimated marker, neutral realtime-unconfirmed status,
unavailable route editing, and no phone-touch requirement. Its Finish state
invokes `NavigationEngine.finishDrive()` against one released synthetic egress
option before the projector names that exact exit ahead of branch guidance and
retains the no-reversal prohibition. A measured reference state makes the marker
difference explicit. Its junction-handoff state uses
`NavigationEngine.connectCarPlay()` only to change surface ownership, then draws
the same snapshot- and movement-occurrence-bound `JunctionViewDefinition` on the
iPhone with Kaido-owned vectors and exact left-indexed lane semantics. The
display labels the synthetic `RELEASED` value as a fixture-only release-gate
input. KR-U09 projects route shields, Japanese sign text, degraded status,
selected branch, preferred lanes, and surface ownership into explicit
Simplified Chinese accessibility labels. At accessibility Dynamic Type sizes,
the panel uses single-column controls and vertical ownership rows; selected
branches and preferred lanes add checkmark/text cues rather than relying on
color. App tests enforce a 4.5:1 contrast floor for the actual critical theme
tokens, and XCUITest exercises both standard and AXXXL Simulator content sizes.
This is a synthetic panel baseline, not whole-app VoiceOver focus-order,
Switch Control, localization, device, or CarPlay accessibility qualification.
The panel has no live location, active `NavigationSession`, released Shuto
assets, audio authority, `CPMapTemplate`, or CarPlay scene.

The live pure-Swift composition boundary is also concrete. A `NavigationSession`
actor owns one RoutePlan-bound matcher session and `NavigationEngine`, converts
each accepted matcher estimate into the conservative location observation,
selects the released DecisionZone for the current anchor occurrence, runs the
distance bridge, and returns one atomic snapshot plus optional prompt emission.
Initialization rejects mismatched route, snapshot, corridor, zone, or guidance
identities. Matcher reset/restart clears temporal evidence without rewinding
navigation progress. Before strict-route entry, ordinary matcher output may
update confidence diagnostics but cannot advance a RoutePlan occurrence or
schedule guidance. Its raw initializer is package-only.
`KaidoProductNavigationRuntime` is the public admission path: it accepts one
validated `KaidoProductRelease` and constructs the session from that release's
exact RoutePlan, released entry/recovery/egress runtime policy, corridor,
DecisionZones, and guidance while retaining the same released Route Atlas. It
accepts no independent asset overrides. The runtime also exposes one immutable
`EntryTransitionAdmissionContext`. `CoreLocationEntryTransitionAdapter` matches
fixes against that exact corridor and can construct package-only typed evidence,
but only the actor can accept a non-simulated, fresh, HIGH, single-edge,
heading-compatible, release-identity-matched sequence. It computes continuity
from the exact ordered edge history instead of accepting a caller boolean, and
restarts route matching at the first occurrence only after strict-route entry.
KR-S19 covers skipped edges, simulation, identity drift, and the valid sequence.
The app now decodes one complete `SYNTHETIC_TEST_ONLY` product artifact through
the production codec, constructs `KaidoProductNavigationRuntime`, and publishes
only the actor's atomic snapshot. Its foreground pipeline binds
`CoreLocationObservationAdapter` and `CoreLocationEntryTransitionAdapter` to the
session, and app tests execute the ordered two-edge admission plus one
strict-route matcher update. Every strict-route actor update now constructs one
shared `NavigationPresentationProjection` for the SwiftUI phone surface,
CarPlay semantics, and optional voice event. A persistent frame can refresh the
visual projection without replaying speech; no active frame or a projection
failure leaves the driving surface unavailable. The internal panel can execute
one fixed synthetic adapter-to-actor trace. A separate foreground location
controller now owns When In Use authorization, automotive manager configuration,
callback-order serialization, and scene shutdown. It requires an exact
product/navigation/runtime-policy/snapshot/RoutePlan/matcher-corridor token
minted by the validated joint product release before constructing its
`CLLocationManager`. The bundled `SYNTHETIC_TEST_ONLY` release declares live
input `DISABLED`, cannot mint that token, and therefore remains blocked without
requesting permission. A versioned, coordinate-free navigation checkpoint now binds
progress, recovery/egress state, and the prompt ledger to the exact product
release, navigation release, runtime policy, snapshot, RoutePlan, and matcher
corridor. SwiftUI scene changes stop the location source and drain its current
callback before stopping speech and atomically saving that checkpoint.
Restoration clears partial entry evidence, CarPlay ownership, position, matcher
posterior, active presentation, and speech authority, then requires a fresh
multi-fix matcher window. This is process-lifecycle recovery, not background
navigation: no location background mode or active background location session
is enabled. A real released product artifact and device lifecycle evidence
remain Apple-integration gates.

The pre-runtime release boundary is now explicit as well.
`NavigationReleaseBundle` accepts only one active `NetworkSnapshot`, one valid
`RoutePlan`, one locally valid reviewed editor catalog, one
`ReleasedNavigationRuntimePolicy`, one complete matcher corridor,
occurrence-scoped DecisionZones and released guidance, and an optional registry
of released junction views. It may also carry one optional
`ReleasedSurfaceAccessDefinition` bound to the exact snapshot, RoutePlan,
directional entrance, first join occurrence, entry transition, compatible exit,
finish-policy set, and one reviewed release-candidate provider/build identity.
It may additionally carry one `ReleasedSurfaceEgressDefinition` whose policies
bind exact released egress-option and exit-facility pairs to reviewed
ordinary-road handoff anchors, return-target tolerances, and explicit
expressway/toll prohibitions. Surface egress cannot be released without a
surface-access definition that permits `RETURN_NEAR_ORIGIN`.
Each provider identity pins the provider and adapter versions, network snapshot,
provider dataset, build manifest, engine build, validation profile, intended
use, and declared data-retention review status. The runtime policy binds the directional entry
transition, released in-domain recovery candidates targeting later RoutePlan
occurrences only for `SAFE_REJOIN`, and released legal egress to the exact
RoutePlan. Other recovery policies cannot carry rejoin candidates, and egress
cannot replace the compiled exit. Every entry-transition edge must have geometry
in the same released matcher corridor, consecutive edges must be explicit legal
successors, and the final edge must lead to the first RoutePlan occurrence
binding. It reuses the same runtime-composition
validation as `NavigationSession`, then adds whole-bundle coverage: every planned
junction-movement occurrence needs exactly one DecisionZone and at least one
released guidance definition. Embedded junction views must match one registry
entry exactly, and registry orphans fail closed. Repeated graph entities remain
distinct because coverage is keyed by occurrence ID. The bundle also retains the
validated `ReleasedRouteAuthoringRecipe`; a catalog that merely contains the
entry and exit but cannot replay an intermediate route occurrence now blocks
release. KR-D18 executes this boundary with synthetic data; it does not release
a real route or dataset.

The navigation bundle now also has a versioned distribution boundary.
`NavigationReleaseArtifact` schema 6.0 serializes the exact bundle inputs
together with a stable release identity, editor-catalog identity, complete
Japanese/Simplified-Chinese/English editor presentation, dated source registry,
and one released evidence record for every distributable asset, including the
editor presentation under `EDITOR_PRESENTATION` and runtime policy under
`RUNTIME_POLICY`, plus `SURFACE_ACCESS` whenever that optional definition is
present and `SURFACE_EGRESS` whenever a return definition is present.
`NavigationRelease`
rejects unknown schemas, missing or orphaned evidence, unused sources,
source-role drift, junction-view provenance drift, and evidence dated after the
release before re-running the whole `NavigationReleaseBundle` gate. The codec
validates on both encode and decode. `NavigationReleaseDraft` keeps the complete
reviewed runtime asset set separate from release provenance;
`NavigationReleaseAuthoringConfiguration` carries only explicit release
identity plus the source registry and exact asset-evidence records.
`kaido-release build-navigation` derives the current artifact schema, preserves
both inputs unchanged, runs the whole gate before writing, and refuses
overwrite. `validate-navigation` independently exposes the same boundary to a
release pipeline. KR-D25 proves authoring, serialization, and unknown-schema
rejection with synthetic data; no real navigation release artifact exists yet.

`ReleasedSurfaceAccessPlanner` is the public platform-light composition path
after release. It admits only a `ReleaseBoundSurfaceRouteProvider` whose exact
provider/build identity equals the released definition, runs the provider,
inspects every candidate against the release-owned graph policy, re-runs all
six hard gates, and invokes the package-scoped `JourneyPlanCompiler`. One
accepted result becomes ready; multiple accepted alternatives remain explicit
and sorted for parked selection rather than inheriting provider array order.
Provider failures, empty or duplicate candidate identities, graph ambiguity,
dataset drift, and compiler rejection remain typed fail-closed outcomes. The
result preserves repeated surface traversals and wraps the accepted leg around
the unchanged RoutePlan, entry transition, and released egress options. The
product runtime admits that compiler-minted plan only when every release,
RoutePlan, entry, finish-policy, provider, and access-leg identity still
matches. A fresh admitted access journey starts at `APPROACH_TO_ENTRY`; only
the existing ordered release-bound entry evidence may enter `STRICT_ROUTE`.
When no surface candidate has been accepted, the existing route-only runtime
remains unchanged. Checkpoint schema 2.0 binds restoration to the exact
`journey_plan_id`, so an access session cannot silently restore as route-only.
`RETURN_NEAR_ORIGIN` remains blocked unless that access result freezes an exact
return target and `ReleasedSurfaceEgressPlanner` obtains an accepted egress
candidate from a separately released policy. The planner queries every released
exit policy independently, re-runs exit-side graph inspection and six egress
hard gates, invokes the package-scoped compiler, then applies the
release-owned `FASTEST_THEN_SHORTEST` ranking. OSRM, GraphHopper, and Valhalla
must prove both the reviewed ordinary-road handoff edge and the frozen return
edge through complete same-snapshot path identity; provider prose and array
order have no authority. The completed `JourneyPlan` retains the unchanged
RoutePlan and exact selected egress option. `FINISH_DRIVE` enters
`EXIT_TRANSITION`. The compiler also retains one immutable, ordered
surface-egress geometry corridor whose repeated edge traversals remain distinct
occurrences. A separate matcher pins initial evidence to occurrence zero and
permits only forward occurrence progress. Only two fresh HIGH, unambiguous,
non-simulated Core Location observations with increasing progress on the exact
release-bound handoff occurrence may enter `SURFACE_EGRESS`; the actor rechecks
the complete release, journey, corridor, occurrence, and edge identity. No
provider or UI can replace the return target, choose a different exit, reuse the
expressway matcher, re-enter the expressway, or manufacture that phase
transition. KR-S20 is synthetic policy evidence only; App enrollment still
requires real graph/provider, device, and held-out field evidence.

The surface-egress matcher now has its own device-calibration boundary rather
than borrowing the expressway report scope. One calibration window binds the
exact product release, navigation release, JourneyPlan, runtime policy, network
snapshot, RoutePlan, provider dataset, selected candidate, egress option, exit,
handoff anchor, corridor, handoff occurrence, matcher/configuration, device
configuration, and explicitly known field transport. The Core Location session
executes the real observation-adapter-to-surface-matcher pipeline in callback
order and retains raw coordinates only in an in-memory
`PRIVATE_RAW_LOCATION` trace. Its public report is coordinate-free. Mixed
scopes fail closed, any false HIGH edge or occurrence blocks the gate, and
synthetic or software-simulated samples cannot satisfy the held-out statistical
floor. The matcher-replay CLI can turn exact private trace bytes plus one
independently reviewed private ground-truth set into a coordinate-free,
SHA-256-bound artifact, then re-run the evaluator against those same bytes.
The artifact always declares `navigation_authority=false` and
`release_approval=false`; its statistical floor does not enroll the App,
qualify a device, or approve a route. No surface-egress field trace has been
collected.

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
release artifact. `RouteAtlasReleaseDraft` contains the reviewed snapshot,
RoutePlan, topology, layout, and ordered occurrence bindings without evidence;
`RouteAtlasReleaseAuthoringConfiguration` separately carries the source
registry plus topology and layout evidence. `kaido-atlas build-release` derives
the current artifact schema, preserves both inputs, runs the whole gate before
writing, and refuses overwrite. KR-D19 proves that one visually invented
connection blocks release, while KR-D28 proves the separate authoring boundary.
This verifies
internal consistency only: the repository still has no released real Shuto
topology slice or production atlas layout.

Neither independently valid artifact can authorize a product build by itself.
`KaidoProductReleaseArtifact` schema 6.0 contains one complete navigation
artifact, one complete Route Atlas artifact, and an explicit `runtime_use`
declaration. `KaidoProductRelease` revalidates both, requires
exact snapshot and RoutePlan identity, requires a finite positive
`RoutePlan.actualDistanceKM`, rejects navigation or atlas evidence newer than
the product release, and requires released atlas topology to contain every
initial edge, incoming approach, movement, and outgoing edge exposed by the
reviewed editor catalog. This keeps authoring choices from naming entities that
the product map cannot represent and prevents a product release that cannot
produce an honest pre-drive distance. The codec validates on encode and decode,
while `kaido-release validate-product` exposes the same joint gate to release
automation. KR-D26 proves that two separately valid synthetic artifacts still
fail the product gate when one editor approach is absent from the atlas, and
that the failure cannot produce a partial product runtime identity. No real
Kaido product release exists yet. KR-D27 adds the live-input gate:
`SYNTHETIC_TEST_ONLY` must remain `DISABLED`; a `RELEASED_ROAD` declaration
must contain no synthetic source in either nested release; and only a valid
`RELEASED_ROAD + FOREGROUND_WHEN_IN_USE` release mints the unforgeable
six-part foreground authority consumed by the app.

The release CLI also provides the production-only assembly path that will be
used after both nested releases exist. `kaido-release build-product` accepts one
independently valid navigation artifact, one independently valid Route Atlas
artifact, and explicit release metadata. It fixes runtime use to
`RELEASED_ROAD + FOREGROUND_WHEN_IN_USE`, rejects synthetic sources, re-runs the
complete joint gate, writes atomically without overwrite, and emits the same
schema-6.0 artifact consumed by the App catalog. It cannot convert the current
review-only K7 candidate or bundled synthetic preview into a product release.

The iPhone build adds a hash-bound catalog in front of that codec. A descriptor
cannot promote a synthetic artifact into foreground navigation, and a released
road descriptor is accepted only when production decode mints the exact
foreground authority. Missing, unreadable, mutated, invalid, role-drifted,
identity-drifted, duplicate, and ambiguous assets fail closed. The default
journey selects only an exact compiled `RoutePlan`; it does not fall back by
route ID or substitute the bundled demo. This app-distribution gate is covered
at L3 rather than by a new portable scenario because it depends on Apple bundle
resources, while schema-6.0 product semantics remain portable and
codec-authoritative.

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
and schema-1.1 coordinate-free manifest validator make that gap executable
without committing raw field media. The validator accepts only an exact
allowlist, refuses completed in-repository manifests outside ignored
`research/`, requires lawful passenger collection and an independent reviewer,
binds every raw hash to a checkpoint, and caps validity at 31 days. This closes
the structured directed-candidate gap, not release: topology and layout stay
`CANDIDATE` until independent lawful field/topology review and production layout
are complete. In-product attribution and derivative-database distribution are
separately complete under a dated, hash-bound technical review: the full
machine-readable derivative database and reconstruction instructions are
public, each ODbL artifact embeds source/licence URIs, and SwiftUI renders native
source and licence links adjacent to the K7 map. This is an implementation
review, not legal advice or road evidence. Realtime passage remains
separately `REALTIME_UNCONFIRMED`; it is not silently treated as open and is not
used as a substitute for static graph evidence. KR-D22 proves that
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

A dated K7 pre-release package now binds that schematic candidate, the directed
source review, the 14-checkpoint successor audit, the Kaido-authored layout
source, an official road-register access review, private coordinate-free
road-register and field templates, independent topology and layout review
templates, and the ODbL technical distribution review by SHA-256. The private
road-register validator requires a current map-66 record obtained at the Road
Survey Division counter, exact comparison of all three OSM successors,
hash-bound private raw records, independent review, and at most 31 days of
validity. It never embeds the record or copied map geometry. The topology
review must bind the canonical digests of both exact private manifests after
the road and field gates pass. The layout review depends on that current
topology review, uses a different reviewer, and both reviews expire after at
most 31 days. A manual evidence-state change cannot satisfy either release
gate. The distribution review in turn binds the derivative database, successor
audit, reconstruction README, attribution catalog, SwiftUI implementation, and
Xcode project source. Its independent validator derives four exact remaining
blockers: current road identity, current field legality, and topology and
layout release evidence. It reports the already proven structure, source
adjacency, and ODbL distribution separately from those unresolved gates.
Yokohama dates the online
recognized-route map to 2026-07-03 and identifies the broader Kawamuki corridor
as municipal Higashikatacho Route 342, while its official terms state that
online material is not proof and direct latest legal-record review to the Road
Survey Division counter. That corridor-level identity does not uniquely
distinguish OSM way `776884422` from the two named Kawamuki Line carriageways
leaving the same terminal node. The tracked decision therefore remains
`BLOCKED` and `navigation_authority=false`. A later completed private field or
road-register review can clear only its own gate, and even a readiness `PASS`
merely admits the candidate to the authoritative
`kaido-atlas validate-release` command.

The feasibility core currently executes portable scenarios for the following
hard properties that must remain proven as the product expands:

1. repeated road segments remain distinct ordered occurrences;
2. only legal directional junction movements can be authored and executed;
3. navigation stays honest when tunnel or stacked-road positioning is uncertain,
   keeps route-candidate resolution separate from raw fix quality, and requires a
   consistent post-gap window before resuming an exact occurrence;
4. a current-location recommendation selects a compatible directional entrance
   approach that is available at the predicted entry time, not merely the
   nearest IC name, and explains its exact carriageway, route join, distance
   rank, and rejected alternatives;
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
    fresh occurrences, exposes only authored reviewed closed sequences for lap
    duplication, groups a copied lap into one undo action, rejects moving-time
    edits, and finishes only through an explicit directional exit.
25. phone and CarPlay consume one released, normalized junction-view definition;
    snapshot, movement occurrence, lane, route-shield, Japanese-sign, and evidence
    drift fail closed before any adapter renders an inset.
26. a navigation release bundle binds the active snapshot, RoutePlan, reviewed
    editor catalog, entry/recovery/egress runtime policy, matcher corridor,
    every movement occurrence's DecisionZone and guidance, and any junction-view
    registry before runtime composition.
27. a Route Atlas exactly covers one reviewed topology slice, preserves every
    route occurrence, and rejects any visual connection absent from the graph.
28. full-network geographic context remains permanently non-navigable and fails
    closed on source, licence, projection, coverage, geometry, or authority
    drift.
29. a real official-checked directed atlas candidate remains blocked until both
    its topology evidence and production layout are explicitly released.
30. a versioned navigation artifact must resolve released, role-matched evidence
    for every runtime asset and survive the whole bundle gate after decoding;
    unknown schemas or provenance drift fail closed.
31. a product release must bind one independently valid navigation artifact and
    Route Atlas artifact to the exact same snapshot and RoutePlan, reject future
    evidence, and cover every released editor entity in atlas topology.
32. external adapters cannot construct a navigation session from loose runtime
    assets; one validated product release owns the session and atlas identity,
    and its released runtime policy is the only source of entry transition,
    recovery candidates, and legal egress.
33. structural release validity alone cannot enable live sensors; only one
    schema-6.0 joint product release with consistent released-road sources and
    explicit foreground policy can mint the exact runtime-bound foreground
    input token, while synthetic or mixed evidence fails closed.
34. production product authoring retains both independently validated nested
    artifacts unchanged, fixes released-road foreground runtime use, re-runs the
    joint gate, and emits no file when validation fails or the output already
    exists.

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
- [`docs/contributing/product-release-authoring.md`](docs/contributing/product-release-authoring.md): fail-closed assembly of validated navigation and Route Atlas releases.
- [`docs/contributing/route-atlas-release-authoring.md`](docs/contributing/route-atlas-release-authoring.md): fail-closed assembly of reviewed atlas content and separate release evidence.
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

Private surface-egress calibration inputs may be converted into one
coordinate-free review artifact without printing their contents:

```sh
swift run kaido-matcher-replay \
  build-surface-egress-calibration-artifact \
  --trace <private-trace.json> \
  --annotations <private-ground-truth.json> \
  --config <authoring-config.json> \
  --output <coordinate-free-artifact.json>

swift run kaido-matcher-replay \
  validate-surface-egress-calibration-artifact \
  --artifact <coordinate-free-artifact.json> \
  --trace <private-trace.json> \
  --annotations <private-ground-truth.json>
```

Multiple `--trace` arguments are allowed. Validation requires the exact same
private bytes used for authoring; see
[`docs/contributing/route-evidence.md`](docs/contributing/route-evidence.md)
for the privacy and independent-review gates.

`swift test` executes the domain and simulation semantics in process. The CLI
prints a result for every scenario and assertion. The Python validator remains
an independent L0 check for the portable envelope, route-occurrence identity,
event ordering, release-bound runtime policy, evidence references, and assertion
references.
`kaido-atlas build-release --draft <file> --config <file> --output <file>`
assembles reviewed content and separate release evidence only through the whole
source-registry and graph-integrity gate. `validate-release --artifact <file>`
independently decodes and validates that artifact; no real Shuto release
artifact exists yet.
The K7 readiness command is a stricter real-evidence preflight around the
current hash-bound candidate inputs. Its expected exit is `BLOCKED`; it never
grants release or navigation authority.

```sh
python3 scripts/validate_k7_route_atlas_readiness.py \
  data/route-atlas/candidates/k7-northwest-up-aoba-to-kohoku-release-readiness.json \
  --as-of 2026-07-25
```

`kaido-release validate-navigation --artifact <file>` equivalently validates a
future navigation runtime artifact through its provenance registry,
entry/recovery/egress policy, and the whole-bundle gate; no real navigation
release artifact exists yet.
`kaido-release validate-product --artifact <file>` revalidates both nested
artifacts and their cross-artifact identity, chronology, and editor-atlas
coverage; no real product release artifact exists yet.

Build—not hand-edit—the navigation artifact from its independently reviewed
draft and provenance configuration:

```sh
swift run kaido-release build-navigation \
  --draft <navigation-release-draft.json> \
  --config <navigation-release-authoring.json> \
  --output <navigation-release.json>

swift run kaido-release validate-navigation \
  --artifact <navigation-release.json>
```

See
[`docs/contributing/navigation-release-authoring.md`](docs/contributing/navigation-release-authoring.md)
for exact input ownership and evidence requirements.

After the navigation and Route Atlas artifacts have independently passed their
release gates, assemble—not hand-edit—the joint product artifact:

```sh
swift run kaido-release build-product \
  --navigation-artifact <navigation-release.json> \
  --atlas-artifact <route-atlas-release.json> \
  --config <product-release-authoring.json> \
  --output <product-release.json>

swift run kaido-release validate-product \
  --artifact <product-release.json>
```

The authoring configuration contains only schema version, product release ID,
and release timestamp. Runtime scope is intentionally not configurable. See
[`docs/contributing/product-release-authoring.md`](docs/contributing/product-release-authoring.md).

Validate separately reviewed current tariff and passage evidence against that
exact product before App staging:

```sh
swift run kaido-release build-pre-drive-evidence \
  --product-artifact <product-release.json> \
  --draft <pre-drive-evidence-draft.json> \
  --config <pre-drive-evidence-authoring.json> \
  --output <pre-drive-evidence.json>

swift run kaido-release validate-pre-drive-evidence \
  --product-artifact <product-release.json> \
  --manifest <pre-drive-evidence.json>

swift run kaido-release generate-pre-drive-evidence-signing-key \
  --key-id <stable-key-id> \
  --output <new-private-key-directory>

swift run kaido-release sign-pre-drive-evidence-update \
  --product-artifact <product-release.json> \
  --manifest <pre-drive-evidence.json> \
  --key-id <stable-key-id> \
  --private-key <private-key.bin> \
  --output <pre-drive-evidence-update.json>

swift run kaido-release validate-pre-drive-evidence-update \
  --product-artifact <product-release.json> \
  --envelope <pre-drive-evidence-update.json> \
  --trust-key <trust-key.json>
```

The author derives product, route, facility, and tariff-profile identity rather
than accepting copied values. The bundle remains separate from versioned route
authority and expires at runtime. The signing private key remains offline and
outside the repository; only its public trust descriptor is staged into the
App. See
[`docs/contributing/pre-drive-evidence.md`](docs/contributing/pre-drive-evidence.md).

After independent validation, prepare the exact Xcode-ready resources and
compile-time foreground descriptor without transcribing release IDs or hashes:

```sh
swift run kaido-release prepare-app-bundle \
  --product-artifact <product-release.json> \
  --config <app-bundle-staging.json> \
  --output <new-staging-directory>
```

An optional complete guidance-audio release and optional current pre-drive
evidence bundle may be supplied in the same run. Synthetic products fail before
output, existing destinations are never overwritten, and the generated
descriptor still requires an explicit reviewed addition to the App catalog. See
[`docs/contributing/app-bundle-staging.md`](docs/contributing/app-bundle-staging.md).

Offline guidance-audio authoring is executable without copying prompt records by
hand:

```sh
swift run kaido-release export-guidance-audio-worklist \
  --product-artifact <product-release.json> \
  --output <worklist.json>

swift run kaido-release prepare-guidance-audio-review \
  --product-artifact <product-release.json> \
  --resources <wav-directory> \
  --review-id <stable-review-id> \
  --output <guidance-audio-review.json>

swift run kaido-release build-guidance-audio \
  --product-artifact <product-release.json> \
  --config <authoring-config.json> \
  --resources <wav-directory> \
  --review <guidance-audio-review.json> \
  --output <guidance-audio-release.json>

swift run kaido-release validate-guidance-audio \
  --product-artifact <product-release.json> \
  --manifest <guidance-audio-release.json> \
  --resources <wav-directory>
```

The worklist derives every exact anchor occurrence, locale, spoken string, hash,
and deterministic filename from the validated product release. Review
preparation binds every local WAV hash to that exact worklist and writes only
`PENDING` decisions; a human reviewer must mark pronunciation,
intelligibility, and audio quality `PASSED`. The authoring command accepts only
three locale profiles plus that complete review, derives WAV metadata and
hashes, and runs the whole audio-release gate before writing a new file.
Existing outputs are never overwritten. See
[`docs/contributing/guidance-audio-authoring.md`](docs/contributing/guidance-audio-authoring.md)
for the provenance, evidence-scope, licensing, and device-review contract.

Generate or open the tracked iPhone project and run the internal preview:

```sh
xcodegen generate
open KaidoRoutesApp.xcodeproj
./scripts/run_ios_preview.sh
```

The Simulator app requires no device signing. It renders review-only assets and
one explicitly synthetic joint-release runtime fixture; neither can claim
real-road navigation authority. See
[`Apps/KaidoRoutesApp/README.md`](Apps/KaidoRoutesApp/README.md) for Xcode,
Preview Canvas, regeneration, and test instructions.

When an exact physical iPhone is online, run the complete App scheme through the
fail-closed private-evidence runner:

```sh
python3 scripts/run_ios_device_qualification.py \
  --device-id <private-device-identifier> \
  --preflight-only
```

The full run requires a clean commit and a new ignored output directory, rejects
Simulator and incomplete test results, and produces a coordinate-free receipt
that explicitly grants no road, acoustic, CarPlay, or background-navigation
authority. See
[`docs/testing/ios-physical-device-qualification.md`](docs/testing/ios-physical-device-qualification.md).

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
