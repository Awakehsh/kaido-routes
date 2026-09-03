# E2E strategy

## Goal

Treat product behavior as a portable contract before choosing the app stack.
One scenario should be reusable across a pure domain engine, a deterministic
navigation simulator, iPhone UI tests, CarPlay tests, and selected field tests.

"E2E" therefore means end-to-end product intent, not only a fragile sequence of
screen taps.

## Test layers

| Layer | Purpose | Environment | Live network? |
|---|---|---|---|
| L0 Contract | Validate scenario shape, IDs, evidence, and occurrence order | Standard-library validator | No |
| L1 Domain | Compile routes, validate movement legality, preserve occurrences, compute state | Pure in-process tests | No |
| L2 Simulation | Replay location, restriction, tunnel, branch, and connection events | Deterministic clock and fixtures | No |
| L3 iPhone UI | Verify editor, pre-drive review, driving mode, accessibility, degraded states | iOS simulator/device | No |
| L4 CarPlay | Verify templates, glanceability, voice timing, lifecycle, and phone/CarPlay handoff | CarPlay simulator and approved hardware | No |
| L5 Field | Measure positioning and sign timing on a lawful, passenger-observed drive | Real phone, vehicle, and dated route | Operator pages may be checked before departure, never as a deterministic assertion |

L1 and L2 carry most logic coverage. L3 and L4 prove platform integration. L5
tests hardware and road reality that simulators cannot reproduce.

Real-source release-readiness packages are also L0 contracts, but they are not
portable runtime scenarios. They bind dated external reviews and distributable
candidate files by hash, then feed an authoritative release validator only when
all preflight gates are satisfied. The K7 readiness validator deliberately
reuses KR-D22 through KR-D24 for Swift graph/release semantics rather than
adding a route-specific field-evidence event to the pure runtime runner.
Its schema-2.0 release scope ends at the exact Yokohama Kohoku exit handoff:
the three ordinary-road successors remain excluded, and their road-register
and field gates are reported separately as future `SURFACE_EGRESS` work rather
than counted as blockers for the exit-only atlas. KR-S21 independently proves
the platform-light `EXIT_TRANSITION` to `COMPLETED` reducer boundary without
authorizing a surface movement.
Its ODbL distribution gate is cross-layer evidence: L0 hash-validates the full
derivative database, reconstruction README, machine-readable notices,
attribution catalog, SwiftUI implementation, and Xcode resource declaration.
That immutable catalog and implementation remain the exact retained K7 review
scope. The default whole-Shuto map has an independent L3 gate: it validates the
decoded network's OSM attribution and ODbL metadata before exposing compact
native source/licence links adjacent to the map. This separation adds no bytes to the
historical K7 review. Passing either technical gate is not road, topology,
layout, realtime, or navigation evidence.

The current `verify/deterministic` job runs `python3 -m unittest discover -s
scripts/tests` alongside the Swift and portable scenario suites, then exercises
the production joint-release CLI against the retained K7
`KaidoProductRelease`:

```sh
swift run kaido-release validate-product \
  --artifact \
  data/product/releases/k7-northwest-up-aoba-to-kohoku-product-release.json
```

These are regression gates for validator behavior and the retained K7 fixture.
They do not enroll the candidate whole-Shuto snapshot or grant it live-input,
surface, field, or navigation authority. The historical K7 atlas review records
remain bound to the exact catalog and implementation bytes that were reviewed;
whole-Shuto attribution is validated independently rather than rewriting those
human-review bindings.

The per-change `verify/app` job runs 11 critical App unit classes, six
whole-Shuto App-model journeys, and one route-selection-to-live-navigation UI
smoke in one xcodebuild session on the newest iPhone 17 Pro Simulator. Simulator
boot and location injection run alongside the test build. The complete 33-pair
foreground-product matrix stays in the deterministic compiler suite instead of
being repeated through the asynchronous App model.
Documentation-only changes stop after the lightweight `verify/changes` path
classification. Failed App runs retain raw xcodebuild logs and `.xcresult`
bundles.

After the same commit passes `verify`, manually trigger the
`iOS qualification` workflow for the intentionally slower gates: every default
silent App unit test, the focused five-journey primary suite, iPhone SE
accessibility audits at Large and AX5, and a validated unsigned Release archive. It uploads the exact
archive as a short-lived artifact, but it does not claim signing,
installation, road, acoustic, CarPlay, TestFlight, or App Store evidence.
Physical-device qualification remains a separate local workflow because it
requires the connected authorized phone and private output. Real audio tests
are excluded from every default scheme and run only through the explicit
`KaidoRoutesPhysicalAudioQualification` scheme.

## Portable scenario envelope

Each file under `e2e/scenarios/` contains:

- identity, layer, tags, and one primary purpose;
- evidence classification and dated source references;
- a network snapshot;
- an optional ordered route plan;
- other deterministic inputs and initial state;
- an ordered event timeline;
- assertions against observable state or output.

Route occurrences have both `occurrence_id` and `entity_id`. Reusing an entity
is valid; reusing an occurrence ID is not.

Assertions use stable semantic subjects such as
`navigation.occurrence_index` or `route_summary.toll.status`. A platform adapter
maps those subjects to engine values, accessibility identifiers, CarPlay
templates, or field observations. Scenario files must not contain Swift class
names or pixel coordinates.

## Determinism rules

- CI never calls live routing, traffic, toll, map, or operator services.
- Time, location, restrictions, and CarPlay lifecycle are injected as events.
- Official-query evidence is stored as dated scalar inputs and source links, not
  copied pages or screenshots.
- Synthetic IDs are obvious (`test.*`) and cannot be mistaken for production
  road data.
- Field observations record hardware and route configuration but do not become
  deterministic truth for every device.
- The foreground Core Location UI regression keeps a five-second transition
  bound from the explicit live-start tap to `SURFACE_ACCESS`. It therefore
  catches main-actor runtime construction, synchronous voice enumeration, and
  repeated junction-guidance compilation instead of hiding them behind a
  longer test timeout.

## Scenario-first coding workflow

1. Select an existing scenario or add the smallest new one.
2. Run `python3 scripts/validate_e2e.py`.
3. Add the narrow adapter/test that consumes the scenario and prove it fails for
   the missing behavior.
4. Implement the smallest production change.
5. Run the target scenario, then the affected layer, then broader tests only if
   the risk justifies them.
6. Record the commands and actual results in the handoff.

Changing an assertion is a product-contract change. It requires a reason such
as a newly accepted product decision or stronger evidence, not merely a failing
implementation.

## Adapter responsibilities

Every implementation adapter should expose:

```text
load network snapshot and deterministic inputs
compile or load route plan
apply events in declared order
capture semantic observations after each event
evaluate scenario assertions
emit a compact failure report with scenario, event, subject, expected, actual
```

Adapters may support only the layers they implement, but unsupported events or
assertions must be reported explicitly rather than skipped silently.

## Journey-lifecycle adapter boundary

Keep external routing and device sensors outside deterministic scenarios. A
surface-routing adapter records a candidate leg with its directed endpoint and
whether it crosses an expressway boundary; a location adapter emits observations
with direction, continuity, timestamp, and confidence. The pure journey engine
then decides whether to accept the access leg or change phase.

The semantic observation surface should include at least:

```text
journey.phase
journey.ambiguity_reason
navigation.active_route_plan_id
navigation.current_occurrence_id
navigation.signal_reacquisition_status
navigation.route_candidate_resolution
editor.state
editor.current_decision_point_id
editor.incoming_approach_id
editor.junction_complex_id
editor.available_choice_ids
editor.occurrence_ids
editor.selected_exit_facility_id
editor.compiled.occurrence_ids
matcher.fraction_along_edge
matcher.lateral_distance_meters
guidance.progress_bridge.status
guidance.progress_bridge.distance_meters
presentation.active_surface
presentation.carplay_connection_state
presentation.kernel.phone.current_occurrence_id
presentation.kernel.phone.next_movement_occurrence_id
presentation.kernel.carplay.current_occurrence_id
presentation.kernel.carplay.next_movement_occurrence_id
presentation.kernel.voice.prompt_id
presentation.kernel.voice.stage
presentation.kernel.voice.distance_meters
presentation.kernel.voice.maneuver
presentation.kernel.voice.should_speak
presentation.kernel.phone.guidance.prompt_id
presentation.kernel.phone.guidance.anchor_id
presentation.kernel.phone.guidance.anchor_occurrence_id
presentation.kernel.phone.guidance.decision_zone_id
presentation.kernel.phone.guidance.stage
presentation.kernel.phone.guidance.distance_meters
presentation.kernel.phone.guidance.decision_point_name_ja
presentation.kernel.phone.guidance.localized_decision_point_name
presentation.kernel.phone.guidance.maneuver
presentation.kernel.phone.guidance.lane_preparation
presentation.kernel.carplay.guidance.prompt_id
presentation.kernel.carplay.guidance.anchor_id
presentation.kernel.carplay.guidance.anchor_occurrence_id
presentation.kernel.carplay.guidance.decision_zone_id
presentation.kernel.carplay.guidance.stage
presentation.kernel.carplay.guidance.distance_meters
presentation.kernel.carplay.guidance.decision_point_name_ja
presentation.kernel.carplay.guidance.localized_decision_point_name
presentation.kernel.carplay.guidance.maneuver
presentation.kernel.carplay.guidance.lane_preparation
presentation.kernel.phone.marker
presentation.kernel.phone.passage_tone
presentation.kernel.phone.route_editing_availability
shared_route.network_snapshot_id
shared_route.occurrence_ids
compiler.selected_template_variant_id
compiler.selected_template_parameters
route.executable
route.blocking_reasons
route.blocking_occurrence_ids
entry_recommendation.selected_facility_id
recovery.route_plan_id
recovery.chosen_rejoin_occurrence_id
egress_plan.exit_facility_id
localization.release_gate
guidance.active_voice_locale
guidance.visible_sign_text_ja
guidance.anchor_status
guidance.planning_status
guidance.active_frame.prompt_id
guidance.active_frame.anchor_occurrence_id
guidance.active_frame.movement_occurrence_id
guidance.active_frame.decision_zone_id
guidance.active_frame.stage
guidance.active_frame.distance_meters
guidance.emitted_prompt_ids
tariff_selection.selected_tariff_version_id
tariff_selection.selected_tariff_version_status
tariff_selection.ignored_non_active_quote_ids
release_bundle.status
release_bundle.network_snapshot_id
release_bundle.route_plan_id
release_bundle.decision_zone_movement_occurrence_ids
release_bundle.guidance_movement_occurrence_ids
release_bundle.junction_view_ids
release_bundle.error_codes
```

This split lets coding agents implement MapKit, Core Location, iPhone UI, and
CarPlay adapters independently without changing route semantics. CI injects
surface candidates and sensor observations; it never calls live MapKit or waits
for a real geofence.

The platform-light `KaidoPresentation` adapter now executes KR-U04 through U12,
KR-U14, and KR-U20. These scenarios verify semantic view values
shared by phone, CarPlay, and voice, including a structured occurrence-scoped
guidance frame with prompt and anchor identity, stage, distance, decision point,
maneuver, lane preparation, and an optional snapshot-bound junction inset.
KR-U09 additionally projects route shields, Japanese sign text, degraded safety
status, junction branch selection, preferred lanes, and surface ownership into
localized assistive labels. It requires explicit non-color cues while retaining
the realtime-unconfirmed no-positive-open rule.
KR-U14 requires both visual surfaces to consume one released normalized
path/lane/sign definition and rejects UI-authored junction semantics. KR-S17
additionally injects a fresh route-resolved distance-to-DecisionZone observation
through the pure guidance planner, engine ledger, and the same projector. It
distinguishes a persistent active frame from the transient matching emission that
alone sets `voice.should_speak`. KR-S18
starts with actual Swift matcher observations and proves that occurrence-bound
along-edge progress, not lateral map-match residual or straight-line distance,
becomes the DecisionZone scalar. KR-U20 keeps exact released `spoken_text`
separate from a deterministic reviewed-form synthesis string and preserves the
Japanese sign target; it grants no acoustic evidence. The portable scenarios
remain L1/L2 contract
executions; their `layer` records the intended final verification surface, not
a claim that a simulator or head unit ran in CI. KR-U09 separately has local L3
evidence from the actual internal SwiftUI panel: unit tests calculate the
contrast of the theme tokens, and XCUITest inspects the accessibility tree at
standard and AXXXL Simulator content sizes. This narrow panel evidence does not
qualify full-app focus order, Switch Control, physical devices,
`CPMapTemplate`, or a head unit.

KR-S19 executes the release-bound entrance admission reducer separately from
ordinary matcher progress. A later transition edge cannot seed the sequence;
software-simulated evidence and a product-release identity mismatch remain
rejected; and only fresh HIGH single-edge evidence with compatible heading in
the exact reviewed order reaches `STRICT_ROUTE`. The fixture uses typed
synthetic evidence and proves no Core Location device accuracy or production
threshold. Focused runtime tests now enter the same scenario boundary from an
admitted compiler-minted surface-access `JourneyPlan`: the fresh actor begins
at `APPROACH_TO_ENTRY`, cross-release plans fail admission, and checkpoint
schema 2.0 cannot reopen that access journey as route-only. This reuses KR-S19
instead of adding a provider-shaped portable event that could bypass the real
provider, graph-inspection, and compiler gates.

KR-U01 and KR-U02 execute the parked `ExpertRouteEditorSession` at L1/L2 even
though their declared final surface is iPhone UI. The runner starts from an exact
directional entrance, observes the incoming-approach/JCT choice set, rejects a
future choice and moving-time edits, advances through reviewed choices, and
compares the final RoutePlan occurrence sequence. It additionally requires an
authored choice-history match before exposing one reviewed closed-lap candidate;
duplication copies fresh occurrence values, and one undo removes the whole copy.
The SwiftUI adapter must bind these semantic values to accessible controls
without recreating movement legality or closure in the view. The internal
iPhone preview now does so for a synthetic catalog, and focused app-model tests
cover current-choice binding, future-choice rejection, repeated fresh
occurrences, session-provided lap candidates, grouped undo, explicit-exit
compilation, and moving-time lockout. KR-U01 and KR-U02 remain the portable
L1/L2 contracts; Simulator interaction and accessibility-tree inspection are
local L3 evidence, not a CI field or release-data claim.

The App's dormant foreground branch adds an L3 composition gate above those
portable contracts. Model tests inject one valid foreground catalog entry,
submit its exact recipe choices, require whole-RoutePlan equality, preserve
occurrence progress across interface-locale changes, and reject a wrong choice
without mutation. This does not add a new portable route behavior or claim that
the currently bundled synthetic catalog is released road data.

KR-U03 inserts `ParkedCorridorResolutionSession` before editor mutation. The
portable runner submits a synthetic match containing only snapshot,
decision-point, and candidate choice IDs. Moving-time submission, a choice
outside the current candidate set, and moving-time resolution all fail without
adding occurrences. Ambiguous candidates remain pending until an explicit
parked choice; only then does the runner submit that reviewed choice to
`ExpertRouteEditorSession` with fresh occurrence IDs. A focused XCUITest adds
local L3 evidence by dragging on the actual SwiftUI Canvas, checking that two
reviewed candidates appear and compilation remains locked before and after the
first movement. This does not validate production gesture geometry, released
layout binding, candidate ranking, or snapping tolerances.

The internal iPhone adapter also composes KR-U04 after the exact explicit-exit
compilation. A same-snapshot reviewed-distance catalog walks RoutePlan
occurrences, so repeated entities contribute once per traversal. The shared
pre-drive evaluator receives an independently declared session plus a dated
evidence set. Both bind the exact snapshot and RoutePlan; the session owns one
canonical Shuto vehicle class plus one independent ETC or cash method, while the
evidence envelope and every tariff record must match both before one unique
`ACTIVE` version can be selected. The portable runner exposes session and
evidence profile fields separately. App tests verify that compilation or class
selection alone cannot request evidence, the exact selected class and payment
method reach the provider, changing either replaces the old review,
provider-wide drift and a single non-active mixed-profile quote fail closed,
actual distance changes with a duplicated lap while tariff distance does not,
unconfirmed passage is not positive-open, unauthorized positive live state and
invalid evidence fail closed, and undo removes the review.
Released-authoring model tests additionally require a separately supplied
session evidence set after exact release compilation plus explicit vehicle-class
and payment-method choices. Missing, RoutePlan-drifted, snapshot-drifted,
vehicle-class-drifted, or payment-method-drifted evidence leaves the released
route compiled but blocks review and navigation; no synthetic review or injected
mismatched release can authorize the journey. The default App composition
intentionally supplies no such current evidence provider.

The default iPhone product-journey shell has a separate app-state and XCUITest
floor. App tests require Route Atlas → parked authoring → pre-drive review
ordering, reject early review/navigation selection, demote stale review after
compiled-route invalidation, and keep the bundled synthetic release blocked
from navigation. XCUITest proves the default launch and primary authoring
transition, while a deterministic review launch verifies the exact visible
`ROUTE_RELEASE_AUTHORITY_UNAVAILABLE` blocker and disabled navigation action.
The same launch switches the persisted interface locale in place, verifies that
the route-first shell changes from Simplified Chinese to English, and requires
the separately selected Japanese guidance voice and fixed sample to remain
unchanged. Focused unit tests cover exact three-locale interface-copy selection
and complete synthetic entrance/editor presentation coverage without raw-ID
fallback.
That review launch also verifies the parked sound-check panel, three-language
selector, locale-specific fixed sample, installed-voice menu, quality status,
and audition control without playing audio. Focused app tests inject the
preference store, voice catalog, and audition output to prove exact
locale-scoped identifier persistence, `ja-JP` / `zh-CN` / `en-US` synthesis
mapping, representative sample selection, moving-context lockout,
stale-preference handling, lifecycle projection, higher-ranked candidate
audition without preference mutation, explicit post-audition confirmation, and
fail-closed resolved-voice drift. These stay at L3 because Apple voice
installation and audio output are environment facts, not portable route events.
These are app-composition tests; existing portable domain scenarios remain the
authority for editor legality, repeated occurrences, release validation, and
navigation behavior.

The internal iPhone language preview adds local L3 adapter evidence for KR-U05
and KR-U11. It projects one synthetic `GuidanceFrame` through
`KaidoPresentation`, lets interface and guidance-voice locales vary
independently, and verifies that Japanese, Simplified Chinese, and English all
retain the same Japanese sign target and route shield. It deliberately supplies
no one-shot prompt emission, so `voice.should_speak` remains false and the panel
cannot play audio. The default product journey now consumes the same independent
interface preference across its app-owned product surfaces. The internal
evidence workbench, system permission UI, pronunciation, and released road
guidance remain outside this localization evidence.

The internal iPhone driving preview adds local L3 adapter evidence for KR-U06
through KR-U10, KR-U12, and KR-U14. It executes one stale LOW observation and one
released synthetic egress selection through `NavigationEngine`, then passes the
resulting snapshots to `KaidoPresentation`. Focused app tests compare measured
and estimated markers, require neutral realtime-unconfirmed passage and
DecisionZone editing lockout, and require Finish drive to name the engine's
selected exit before branch guidance while retaining the reversal prohibition.
The portable Finish scenario does not claim an ordinary-road handoff. Focused
platform-light tests separately require a complete schema-6.0
`SURFACE_EGRESS` release definition, frozen access-derived return target,
provider endpoint identity, graph hard gates, deterministic ranking, exact
selected egress option, and two-observation `EXIT_TRANSITION` to
`SURFACE_EGRESS` admission. No live provider, field trace, or device claim is
made.
KR-S20 additionally executes the compiler-retained surface geometry boundary:
the portable runner builds an occurrence-ordered egress corridor, preserves a
repeated directed edge as two identities, runs the separately scoped matcher,
rejects simulated evidence, and requires two forward exact-handoff observations
before the actor enters `SURFACE_EGRESS`. Its coordinates and quality values are
synthetic and do not qualify the App, a Core Location source, or field
reliability.
KR-S22 adds a route-independent whole-drive simulation boundary. The
platform-light trace generator samples every ordered matcher-corridor
occurrence, including repeated traversals, and may inject an
occurrence-addressed coordinate offset, accuracy spike, receive delay, or
signal gap. The actor controller supports deterministic play, pause, step,
reset, and playback-speed selection; speed changes wall-clock delay only and
never event timestamps or matcher input. The trace generator also supports an
opt-in route-speed cadence that densifies long geometry without removing the
occurrence-scoped samples, then derives observation time from along-route
distance and one explicit reference speed. It dispatches the trace through the
real `RouteMatcherSession` and `NavigationSession`, activates Finish drive at
the release-owned first eligible egress occurrence, and may complete only at
the exact terminal exit handoff. The internal iPhone panel exposes these
controls plus clean, GPS-drift, signal-gap, and poor-accuracy presets. The
controller begins from an explicit synthetic strict-route seed instead of
manufacturing entry-admission evidence, and neither its output nor Simulator
interaction grants device, road, traffic, field, or release authority.

The generator retains coordinate-free truth for every matcher observation:
exact RoutePlan occurrence, directed edge, fraction, and cumulative route
distance. `NavigationDriveAccuracyEvaluator` joins estimates by observation ID
and keeps diagnostic top-1 results separate from navigation-authoritative HIGH
results. Its default clean floor requires at least 100 samples, at least 85%
edge and occurrence top-1 accuracy, 100% HIGH occurrence precision, at least
25% HIGH coverage, no wrong or backward HIGH commit, at most 15 meters p95
route-progress error, and at most five meters of HIGH progress regression.

The whole-Shuto accuracy regression executes three routes covering a
cross-network journey, Oi, and Kasai. Each runs a clean trace and a repeatable
eight-direction, eight-meter coordinate-drift trace with 12-meter reported
horizontal accuracy. Clean traces must meet the default floor. Drift traces
must retain zero wrong HIGH edge/occurrence commits, 100% HIGH occurrence
precision, at least 20% HIGH coverage, at least 56% diagnostic edge top-1 and
64% occurrence top-1 accuracy, and no more than 15 meters p95 progress error.
These are deterministic regression floors, not field accuracy claims.

A separate in-car readiness regression drives the C1 inner circuit and
Kyobashi-to-Minatomirai corridor at 1 Hz / 17 m/s with both 2-meter clean fixes
and 12-meter fixes plus deterministic 8-meter radial drift. It requires zero
unsafe HIGH edge or occurrence commits, at least 50% admitted HIGH-or-ordered-
MEDIUM progress coverage, and no admitted-progress gap longer than 30 seconds.
The C1 entry adapter is also exercised at 1 Hz with 8-meter accuracy through the
real release-bound route-head continuity path. These are synthetic regression
bounds, not road or field evidence.

Core Location adapter tests additionally require valid `courseAccuracy` and
`speedAccuracy` to reach the matcher observation. A focused opposing-direction
fixture proves that a highly uncertain course cannot overpower route continuity
as if it were a precise bearing.

Focused platform-light and Apple-adapter tests cover the separate
surface-egress calibration boundary. They require exact release, candidate,
corridor, occurrence, matcher, device, and field-transport scope; exercise
callback-order matching and receive-time reversal; verify false HIGH,
synthetic, and simulated failure precedence; and assert that only the private
trace contains coordinates and observation/device detail. The same focused
suite verifies that authoring hashes exact private trace and independently
reviewed annotation bytes into a coordinate-free, non-authoritative artifact,
and that validation rejects private-byte drift. This selects KR-S20 as the
underlying navigation behavior without adding a portable field-evidence claim
or committing private inputs.
It also executes ownership-only `connectCarPlay()`, requires phone and CarPlay
to retain one occurrence-scoped frame and junction definition, and rejects an
unreleased junction definition without replacing the prior valid state. The
SwiftUI renderer consumes exact normalized paths and lane indices. The model
supplies no prompt emission. KR-U09 binds the same projection to localized
assistive labels, a single-column accessibility-size layout, and non-color
branch/lane cues. Focused tests verify a 4.5:1 theme-token contrast floor and
the critical accessibility tree in both standard and AXXXL Simulator sizes.
This does not verify live location, production DecisionZones, full-app
accessibility, final pixels across the device matrix, `CPMapTemplate`, a
CarPlay scene, physical hardware, or released road data.

KR-U13 reuses `ROUTE_COMPILE_REQUESTED` to cross the direction-first entrance
recommendation into an iPhone-intended explanation contract. The runner exposes
the exact target carriageway, legal join occurrence, ETA, distance rank,
selection reasons, and rejected-candidate reasons. The app binds the same
selection to its editor entrance and initial occurrence. Focused tests prove
that duplicate identities, invalid metrics, snapshot drift, and editor identity
drift fail closed. The fixture is synthetic and no L1/L2 or Simulator execution
is evidence of a live location, provider route, or released entrance.

KR-D18 executes `NavigationReleaseBundle` at L1/L2 before any Apple adapter or
live service exists. Its synthetic asset set proves that one active snapshot,
RoutePlan, editor catalog, entry/recovery/egress runtime policy, matcher
corridor, DecisionZone set, released-guidance set, and optional junction-view
registry can pass as one coherent unit. Unit tests supply the fail-closed matrix
for invalid entry binding, absent released egress, malformed recovery,
non-rejoin policy contamination, compiled-exit drift, missing repeated-occurrence assets, duplicate
movement zones, and unregistered or orphaned junction views. Neither
the portable scenario nor those tests promote their synthetic `ACTIVE` or
`RELEASED` flags into real release evidence.

KR-D25 takes the next distribution step without weakening that distinction.
The runner first gives the immutable reviewed assets and separate provenance
configuration to `NavigationReleaseAuthor`; only a complete
`NavigationRelease` may produce the schema-6.0 artifact. It then encodes and
decodes that artifact, requires exact released evidence coverage for every
runtime asset role and identity—including `EDITOR_PRESENTATION` and
`RUNTIME_POLICY`—and re-runs `NavigationReleaseBundle`. A final event proves
that an unknown artifact schema fails closed. Python independently checks the
authoring-event payload, policy snapshot, RoutePlan, entry, safe-rejoin, and
compiled-exit bindings as well as source registry, exact asset-evidence
coverage, role compatibility, and embedded junction-view provenance. The
fixture remains synthetic and does not establish real-road release eligibility.

KR-D26 crosses the two independently valid distribution boundaries without
merging their authority. The runner builds and validates one navigation artifact
and one Route Atlas artifact, embeds both in `KaidoProductReleaseArtifact`, and
then requires exact snapshot, RoutePlan, positive actual distance, chronology, and complete
editor-catalog-to-atlas entity coverage. Its negative fixture omits one incoming
approach from otherwise valid atlas topology, so both nested events pass while
the joint product event blocks with the exact missing entity ID. Python
independently derives the required editor entity set and verifies the declared
missing set. A final runtime-admission event proves that the blocked release
cannot expose a partial runtime identity. Every released value remains
synthetic.

KR-D27 separates structural product validity from sensor authority. A shared
platform-light evaluator consumes the schema-6.0 `runtime_use` declaration and
both nested source domains. Synthetic scope is valid only with live input
disabled; released-road scope rejects every `SYNTHETIC_TEST_ONLY` source; and a
valid released-road product with disabled input still mints no token. Only the
released-road foreground case is eligible for the package-only authority used
by the App controller. The fixture's non-synthetic labels are test values and
do not claim a real release.

KR-D28 keeps reviewed atlas content separate from release authority. The runner
removes topology and layout evidence from one immutable draft, supplies the
source registry plus both evidence values through a separate authoring
configuration, derives schema 1.0, and re-runs the complete
`RouteAtlasRelease` gate before publishing the artifact. Two later events prove
that unknown draft and configuration schemas fail closed. Python independently
requires the exact authoring inputs, rejects unsupported payload keys, and
checks explicit non-empty schema overrides. The fixture remains synthetic and
does not establish real-road topology, layout, or evidence.

KR-D29 keeps current pre-drive evidence separate from the versioned product
release without leaving the App dependent on a test-injected closure. One
schema-1.0 bundle binds the exact product/navigation/snapshot/RoutePlan
identities, separate tariff and passage source roles, reviewed content hashes,
one exact vehicle/payment profile, and an exclusive expiry. The runner resolves
the fresh ETC record, then proves that expiry and a CASH selection fail as
current information with stable distinct codes. It then starts the independently
executable RoutePlan while retaining the explicit expired-information state.
KR-S05 separately keeps a known required closure as a hard start blocker. Swift
tests cover deterministic codec round-trip,
identity/scope/profile drift, source-role completeness, and the same runtime
validity boundary. The fixture is synthetic and cannot establish a current
tariff, passage state, or released-road authority.

Pre-drive evidence authoring is covered at the same platform-light package
layer without adding a second portable behavior event. Focused tests require a
codec-admitted foreground product, prove that draft JSON contains no product,
route, facility, evidence-scope, or release identity, and verify that the
author derives every quote profile and route-owned field before running the
same KR-D29 bundle gate. Synthetic products, unknown input schemas, and invalid
reviewed source coverage return no manifest.

Signed pre-drive evidence updates are also covered at the platform-light and App
adapter layers without adding a portable route-behavior event. Package tests
bind Ed25519 verification to exact manifest bytes, one compile-time key ID, and
one whole foreground product; payload, hash, signature, trust, product, and
synthetic-scope drift fail closed. Staging tests require a valid non-duplicate
public-key registry. App tests then require exactly one trusted product match,
persist-before-publish, monotonic evidence release time, unique release ID,
release-time activation, and re-verification on restoration. These tests prove
local update mechanics only and do not qualify source claims, transport, device
storage, or realtime passage.

Product release authoring is covered at the same platform-light layer without a
new route-behavior event. Focused Swift tests pass independently valid
released-road navigation and Route Atlas fixtures to
`KaidoProductReleaseAuthor`, require exact unchanged nesting and foreground
authority, and reject invalid metadata, synthetic input promotion, and
cross-artifact editor coverage drift. The CLI then uses the same author, encodes
through the production schema-6.0 codec, writes only a new output, and refuses
overwrite. These tests prove deterministic assembly mechanics only; their
test-labelled non-synthetic licences are not real release evidence.

The internal iPhone target adds a local L3 composition check above KR-D26. One
bundled `SYNTHETIC_TEST_ONLY` product artifact is decoded through the production
codec before `KaidoProductNavigationRuntime` may exist. Unit tests exercise the
real Apple observation adapter, ordered two-edge entry adapter, actor admission,
and one post-entry matcher update, asserting only actor-returned snapshots. The
same update's matching one-shot emission passes through the RoutePlan-bound
speech scheduler into an injected output exactly once. Focused tests execute
replacement-safe callback identity, interruption without catch-up replay,
provider surface-step exactly-once delivery and released-prompt priority,
reviewed-form rendering without cascade or duplicate expansion, exact
offline-audio lookup against unchanged release text, and a typed missing-voice
failure. The real iOS output is compile- and launch-checked
with Apple's `voicePrompt` audio-session configuration; acoustic output remains
a device test. A launch-only XCUITest verifies that the visible preview starts
in `PLANNING`, keeps strict entry locked, exposes `INPUT DISCONNECTED`, and keeps
guidance audio `IDLE`.

The same L3 target tests the Apple bundle distribution gate above the portable
release contracts. Catalog tests require the checked-in demo resource to
match its compile-time SHA-256, expected release ID, and demo-only runtime role.
They mutate bytes before codec admission; exercise missing, corrupt, invalid,
identity-drifted, role-drifted, and duplicate manifests; admit a test
released-road entry only through a production-codec-minted authority; and
require whole-`RoutePlan` equality. A declared pre-drive evidence manifest is
also hash-pinned, production-decoded against that exact release, and used by the
retained authoring model only inside its validity window. Missing, mutated, or
expired information cannot fall back to injected values or be labeled current,
but it does not revoke the exact released route. Two independently valid
released entries for the same exact plan produce an explicit ambiguity rather
than an arbitrary choice. XCUITest exposes the current
`1 RELEASED ROAD · 1 DEMO` catalog only through the explicit
`-LEGACY-PRODUCT-JOURNEY` regression host. Product schema, release validity, and
live-input authority remain covered portably by KR-D26/KR-D27; only bundle
lookup and content hashing are L3-specific.

The focused C2 App suite uses deterministic place, location, and surface-route
providers to execute the complete visual lifecycle without a live network:
arbitrary endpoints, parked pre-drive review, explicit navigation start,
surface access, entry transition, all ordered C2 + B occurrences, automatic
Kasai-right and Oi-left junction insets, tunnel degradation, App-inactive
suspension with explicit resume, exit transition, and surface egress. Checkpoint
tests require exact file round-trip, route-database drift rejection, and paused
restoration at the same occurrence progress. The launch-only retained-journey UI
tests additionally require the C2 map to be primary while K7 remains an ordinary
catalog entry, and require `Continue previous route` to open the restored drive
without advancing until the user resumes. Model tests retain the exact checked
operator facility coordinates. These checks prove composition and UI behavior
only; they do not validate live MapKit output, release C2 route authority, or
replace field qualification.

The whole-Shuto live model suite also drives a released Rinkai-fukutoshin to
Hatsudai-minami route through the real entry adapter and route-aware matcher to
a tagged tunnel edge. After a deterministic fix gap it requires a moving,
growing-uncertainty presentation estimate while authoritative progress,
occurrence identity, and speech count remain unchanged. A later unrelated weak
raw coordinate must not displace that route projection. Platform tests bind the
45-second horizon, speed bound, and next-decision safety limit independently.
These are deterministic safety semantics, not tunnel accuracy evidence.

The focused whole-Shuto suite compiles the exact reviewed Shinonome, Tatsumi,
Kasai, and Oi adjacent-edge transitions into occurrence-owned
`JUNCTION_MOVEMENT`, DecisionZone, and commit-stage guidance values. Package
tests require one actor emission per tested route: `BRANCH_LEFT` for Shinonome
eastbound, both Tatsumi approaches, Kasai, and Oi; and `BRANCH_RIGHT` for
Shinonome westbound. Every case retains no lane preparation and unchanged
Japanese sign targets. The two Shinonome cases must preserve their distinct
`豊洲` and `晴海` targets, while the two Tatsumi cases retain `箱崎` and
`箱崎・銀座`. App model tests require phone and Japanese speech to consume
those actor projections, reject schema or complete-`RoutePlan` checkpoint
drift, and suppress the Oi output prompt after background save and
reconstruction. Fault-injecting stores distinguish an absent checkpoint from
load, schema, route, save, and removal failures, require a visible issue code,
and prove that a failed replacement cannot revive older progress or a stale
prompt ledger. Saved-route model tests also round-trip circuit source,
identity, lap count, and exact repeated occurrences while rejecting template
metadata that cannot reproduce the saved plan. A real file-store regression
also round-trips the default Ginza-to-Yokohama recommendation through encoded
JSON before reopening all 789 occurrences. A separate UI launch writes a
corrupt whole-Shuto checkpoint, requires the localized parked-state issue, and
then relaunches without the fault to prove the invalid resume data was cleared.
A separate model case projects English phone copy and Chinese speech from the
Oi prompt while requiring its Japanese sign target to remain byte-identical.
XCUITest launches the static Oi review and deterministic
actor-driven Oi, Kasai, Shinonome, and Tatsumi navigation previews, then uses
the default whole-Shuto language sheet to switch Simplified Chinese, English,
and Japanese interface copy without changing the independently selected
voice. Each actor preview must reach its inset through session observations
and expose a scheduled, speaking, or consumed voice state. The Oi actor preview
also requires the geographic driving map, total remaining distance, next
reviewed-JCT distance, and the accessible follow/free/follow camera control,
and retains a screenshot of that complete driving surface. These tests retain
the default-product language screenshots plus Kasai and Tatsumi left-branch
screenshots and a Shinonome right-branch screenshot. This is simulator
composition and lifecycle evidence only. It does not attach continuous Core
Location, qualify acoustics, authorize a live road, or prove background
navigation.

The K7 operational E2E composes these boundaries without copying the real
release into a portable synthetic scenario:

```sh
python3 scripts/run_k7_operational_e2e.py
```

The command reconstructs the identity-free pre-drive draft from one dated,
reviewed scalar source snapshot; authors and validates the exact navigation,
navigation-semantic Route Atlas, joint product, and ten-profile pre-drive
artifacts; and re-runs App staging in a temporary directory. It requires the
generated draft, authoring configuration, evidence manifest, product resource,
pre-drive resource, and compile-time Swift descriptor to match the tracked
bytes exactly. Its focused L3 run then selects the real K7 foreground release,
submits both release-owned junction choices, compiles the five-occurrence
RoutePlan, selects `STANDARD + ETC`, verifies `¥400`, `7.1 km`, and
`REALTIME_UNCONFIRMED`, starts the released navigation runtime, and requires the
explicit foreground-location control to be available. A second model and UI
path freezes time at the exclusive expiry, keeps the old amount visibly stale,
and still starts the same released runtime; a current known closure remains
blocked. The fresh App launch injects
`2026-07-27T22:30:00+09:00`, which is inside the reviewed bundle window; a
companion launch injects `2026-07-28T00:00:00+09:00`.

This E2E makes no live request and cannot refresh the source review. Passing it
does not claim that K7 is currently open, calibrate Core Location or DecisionZone
timing, qualify pronunciation or physical audio routing, create a CarPlay scene,
or replace passenger-observed field evidence. A new operational window still
requires a separately reviewed official tariff query and neutral passage check
before it may be displayed as current information; it is no longer a daily
licence for route execution.

The physical-iPhone App layer separately executes the default whole-Shuto
planning-to-live handoff through the real `CLLocationManager`. Its
named UI test,
`testWholeShutoForegroundLocationStartsAndStopsThroughCoreLocation()`, accepts
the system When In Use dialog, proves that the explicit start survives the
temporary permission scene interruption, builds an exact released journey,
starts live navigation, verifies the planning manager stopped, presses Home,
returns to the App, and requires the same live journey to remain active without
`RESUME_REQUIRED`. The coordinate-free device runner requires that exact test
to pass and hashes the test tree. This is App-switch lifecycle wiring evidence
only, not proof that fixes or speech were delivered while locked/backgrounded,
nor coordinate accuracy, matcher reliability, road authority, or passenger-safe
field evidence. The retained K7 operational
E2E remains a fixture-specific release contract and is no longer the current
physical-device lifecycle gate.

A deterministic App integration test separately drives an exact foreground
release from surface handoff through strict-route observations, a released
wrong-route path, and its bound later RoutePlan occurrence. It requires the
model to continue accepting serialized location observations during active
recovery, move the displayed position along the release-owned recovery
geometry, keep navigation active, and return to strict-route state at rejoin.
A package test also covers the case where the trigger segment is ambiguous and
the first unique HIGH evidence arrives on a later edge: activation is allowed
only when that edge belongs to exactly one eligible released recovery. These
tests prove deterministic runtime and App projection behavior, not field
matcher accuracy or prompt timing.

Portable guidance-audio tests also prepare a complete exact-WAV review
checklist, require every generated decision to begin `PENDING`, and reject
pending conclusions, changed audio hashes, rejected pronunciation, and invalid
review chronology before a schema-1.4 manifest can be authored or admitted.
These deterministic checks prove review binding and fail-closed mechanics, not
acoustic quality or human listening.

KR-U17 adds the Route Atlas journey-overlay contract without granting map or
position authority. Its synthetic released atlas carries one context-only
branch and a RoutePlan that traverses one schematic segment twice. The portable
runner requires the exact actor snapshot to produce ordered
`PASSED/CURRENT/FUTURE` occurrence state, preserve both bindings, and expose a
repeat ordinal instead of deduplicating the segment. Package tests cover
pre-activation `PLANNED` state, skipped occurrences, completed/pending order
drift, RoutePlan drift, and adjacent attribution. App model tests prove both
pre-drive and actor-owned projections, while a launch-only XCUITest inspects
the three separately numbered tracks and retains a screenshot. This is
synthetic renderer evidence only: it does not release Shuto topology, calibrate
a position marker, or prove physical-device layout.

KR-U18 adds saved-route persistence and reopening without treating storage as
authority. Its schema-1.0 library record contains one complete
`SharedRouteDocument` with a repeated road entity, local-authoring origin, and
unchanged community-candidate evidence. The portable runner round-trips that
value and selects the one whole-RoutePlan-equal release candidate while
rejecting a snapshot-drifted candidate. Package tests cover corrupt metadata,
duplicate identities, zero/one/multiple current matches, unsafe candidate
identity, and atomic file storage. Retained-path App tests prove that a saved
released route only selects the release-owned parked editor with no automatic
choice or compilation. Separate default-product tests require a same-snapshot
record to reconstruct the complete RoutePlan for parked Review without granting
release authority. The persistence UI test saves that exact route, terminates
the App, reopens the real file-backed library, requires `CURRENT SNAPSHOT`, and
returns to Review with the same directional entrance and exit.

KR-U19 adds the parked shared-route lifecycle without broadening authority. The
portable runner exports one complete document, imports it under a fresh record
with `SHARED_IMPORT`, renames only local metadata, re-exports byte-identical
route intent, and deletes only the imported record while release selection
remains unavailable. Package tests reject unknown schemas and missing
identities; App model tests prove persist-before-publish behavior on every
mutation. XCUITest exercises rename and confirmation-gated delete and exposes
system JSON import/export controls. Physical Files-provider interaction and
schema migration remain unproven and intentionally absent.

KR-U16 adds package and L3 process-lifecycle evidence without inventing a
portable Apple scene event. A schema-1.0 checkpoint round-trips deterministic
coordinate-free state, fails on release identity or schema drift, clears partial
entry evidence and transient presentation/audio values, and preserves the prompt
ledger. A restored actor exposes its first otherwise-HIGH matcher result as LOW,
does not advance or emit, and requires the ordinary reacquisition window.
KR-S03 now also asserts that the first post-gap fix remains LOW; KR-S10, KR-S16,
and KR-S19 retain prompt, matcher-reset, and entry-admission boundaries.
App tests drive `background → atomic store → new runtime → explicit resume →
first fix` and prove no position or prompt replay. Review-phase checkpoints are
rejected so an old current-location origin cannot silently return. XCUITest keeps the no-store launch preview
`FOREGROUND` and deterministic. The app target's active live-navigation path
declares `location` and `audio` background modes, while deterministic replay
still stops and checkpoints; these checks remain termination recovery rather
than proof of physical background continuity.
Together with KR-U15, this selects the existing KR-S10/KR-S17/KR-S18 transient
emission contract rather than adding a portable Apple-audio event, and grants no
field evidence or real-road release authority.

For localization, domain tests prove that all required bundles and spoken forms
exist and that reviewed forms reach a separate Apple synthesis string without
changing release text. Simulator or device tests separately prove voice
discovery, pronunciation
fixtures, audio lifecycle, and the visible Japanese sign target. A device voice
being installed is an environment fact, not a portable domain assertion. Pure
package tests cover exact-locale filtering, novelty/personal exclusion,
premium-enhanced-default ordering, deterministic system-default tie-breaking,
explicit preferred-identifier selection, catalog deduplication, explicit
higher-quality readiness, and neutral Apple rate/pitch values. The iOS runtime
test reports the actual installed voice profile after its first admitted prompt;
the separate parked model tests use injected audio. A default-quality Simulator
result is observability evidence, not enhanced acoustic qualification. The
candidate-audition tests prove selection authority and state transitions, not
pronunciation, naturalness, or acoustic quality.

The complete App scheme now has a separate physical-iPhone runner. It resolves
one exact `xcdevice` entry, rejects Simulator/offline destinations and dirty
source, requires zero failed/skipped/expected-failure tests in the physical
`.xcresult`, and hashes the private evidence into a coordinate-free receipt.
The receipt explicitly remains only an App physical-test baseline; its required
location test covers a foreground-started live session across temporary App
switching, but it cannot assert road release, acoustic quality, pronunciation,
location accuracy, CarPlay, lock-screen fix delivery, or background speech.

## Field-test protocol

Field tests require a separate, dated test plan and safe roles:

- the driver drives and does not collect data;
- a passenger or automated logger records observations;
- the route, direction, entrances, exits, planned restrictions, and safe abort
  points are reviewed before departure;
- device, iOS, vehicle/head-unit, passenger-declared wired/wireless state,
  timestamps, and Core Location source metadata are recorded as separate fields;
- road signs, police directions, closures, and safety always override the test;
- raw personal location traces remain private unless deliberately redacted and
  licensed.

Field success is configuration-scoped. For example, one passenger-declared
wireless CarPlay tunnel run does not prove that phone-only positioning works,
and an external-accessory source flag does not by itself prove the transport.

## Initial release gate

A product slice is ready for a closed road test only when:

- all L0 checks pass;
- its exact movements pass L1 legality and occurrence tests;
- L2 covers tunnel degradation, missed branch, closure, and recovery behavior;
- relevant L3/L4 critical paths pass without requiring complex driving-time
  interaction;
- evidence is current for the selected snapshot;
- the field plan has a safe fallback and no unresolved must-pass contradiction.
