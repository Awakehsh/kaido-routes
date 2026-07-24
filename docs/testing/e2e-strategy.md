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
Its ODbL distribution gate is cross-layer evidence: L0 hash-validates the full
derivative database, reconstruction README, machine-readable notices,
attribution catalog, SwiftUI implementation, and Xcode resource declaration;
focused L3 unit and UI tests then prove the K7 credit and source/licence links
are actually exposed adjacent to the non-interactive map. Passing that gate is
technical distribution evidence only, not road, topology, layout, realtime, or
navigation evidence.

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

The platform-light `KaidoPresentation` adapter now executes KR-U04 through U12
and KR-U14. These scenarios verify semantic view values
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
becomes the DecisionZone scalar. The portable scenarios remain L1/L2 contract
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
threshold.

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
occurrences, so repeated entities contribute once per traversal. The app model
then requires exact route, entry, and exit identity, selects one unique
`ACTIVE` tariff record, and binds the existing presentation projection to an
accessibility-visible review. App tests verify that actual distance changes with
a duplicated lap while tariff distance does not, unconfirmed passage is not
positive-open, invalid evidence fails closed, and undo removes the review.

The default iPhone product-journey shell has a separate app-state and XCUITest
floor. App tests require Route Atlas → parked authoring → pre-drive review
ordering, reject early review/navigation selection, demote stale review after
compiled-route invalidation, and keep the bundled synthetic release blocked
from navigation. XCUITest proves the default launch and primary authoring
transition, while a deterministic review launch verifies the exact visible
`ROUTE_RELEASE_AUTHORITY_UNAVAILABLE` blocker and disabled navigation action.
That review launch also verifies the parked sound-check panel, installed-voice
menu, quality status, and audition control without playing audio. Focused app
tests inject the preference store, voice catalog, and audition output to prove
exact identifier persistence, a fixed `ja-JP` sample, moving-context lockout,
stale-preference handling, and lifecycle projection. These stay at L3 because
Apple voice installation and audio output are environment facts, not portable
route events.
These are app-composition tests; existing portable domain scenarios remain the
authority for editor legality, repeated occurrences, release validation, and
navigation behavior.

The internal iPhone language preview adds local L3 adapter evidence for KR-U05
and KR-U11. It projects one synthetic `GuidanceFrame` through
`KaidoPresentation`, lets interface and guidance-voice locales vary
independently, and verifies that Japanese, Simplified Chinese, and English all
retain the same Japanese sign target and route shield. It deliberately supplies
no one-shot prompt emission, so `voice.should_speak` remains false and the panel
cannot play audio. This does not verify full-app localization, pronunciation,
or released road guidance.

The internal iPhone driving preview adds local L3 adapter evidence for KR-U06
through KR-U10, KR-U12, and KR-U14. It executes one stale LOW observation and one
released synthetic egress selection through `NavigationEngine`, then passes the
resulting snapshots to `KaidoPresentation`. Focused app tests compare measured
and estimated markers, require neutral realtime-unconfirmed passage and
DecisionZone editing lockout, and require Finish drive to name the engine's
selected exit before branch guidance while retaining the reversal prohibition.
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
for invalid entry binding, absent released recovery/egress, compiled-exit drift,
non-rejoin policy contamination, missing repeated-occurrence assets, duplicate
movement zones, and unregistered or orphaned junction views. Neither
the portable scenario nor those tests promote their synthetic `ACTIVE` or
`RELEASED` flags into real release evidence.

KR-D25 takes the next distribution step without weakening that distinction.
The runner constructs a `NavigationReleaseArtifact`, encodes and decodes it,
requires exact released evidence coverage for every runtime asset role and
identity—including `RUNTIME_POLICY`—and then re-runs
`NavigationReleaseBundle`. A second event proves that an unknown artifact schema
fails closed. Python independently checks the policy's snapshot, RoutePlan,
entry, safe-rejoin, and compiled-exit bindings as well as the source registry,
exact asset-evidence coverage, role compatibility, and embedded junction-view
provenance. The fixture remains synthetic and does not establish real-road
release eligibility.

KR-D26 crosses the two independently valid distribution boundaries without
merging their authority. The runner builds and validates one navigation artifact
and one Route Atlas artifact, embeds both in `KaidoProductReleaseArtifact`, and
then requires exact snapshot, RoutePlan, chronology, and complete
editor-catalog-to-atlas entity coverage. Its negative fixture omits one incoming
approach from otherwise valid atlas topology, so both nested events pass while
the joint product event blocks with the exact missing entity ID. Python
independently derives the required editor entity set and verifies the declared
missing set. A final runtime-admission event proves that the blocked release
cannot expose a partial runtime identity. Every released value remains
synthetic.

KR-D27 separates structural product validity from sensor authority. A shared
platform-light evaluator consumes the schema-3.0 `runtime_use` declaration and
both nested source domains. Synthetic scope is valid only with live input
disabled; released-road scope rejects every `SYNTHETIC_TEST_ONLY` source; and a
valid released-road product with disabled input still mints no token. Only the
released-road foreground case is eligible for the package-only authority used
by the App controller. The fixture's non-synthetic labels are test values and
do not claim a real release.

The internal iPhone target adds a local L3 composition check above KR-D26. One
bundled `SYNTHETIC_TEST_ONLY` product artifact is decoded through the production
codec before `KaidoProductNavigationRuntime` may exist. Unit tests exercise the
real Apple observation adapter, ordered two-edge entry adapter, actor admission,
and one post-entry matcher update, asserting only actor-returned snapshots. The
same update's matching one-shot emission passes through the RoutePlan-bound
speech scheduler into an injected output exactly once. Focused tests execute
replacement-safe callback identity, interruption without catch-up replay, and a
typed missing-voice failure. The real iOS output is compile- and launch-checked
with Apple's `voicePrompt` audio-session configuration; acoustic output remains
a device test. A launch-only XCUITest verifies that the visible preview starts
in `PLANNING`, keeps strict entry locked, exposes `INPUT DISCONNECTED`, and keeps
guidance audio `IDLE`.

The same L3 target tests the Apple bundle distribution gate without adding a
portable scenario event. Catalog tests require the checked-in demo resource to
match its compile-time SHA-256, expected release ID, and demo-only runtime role.
They mutate bytes before codec admission; exercise missing, corrupt, invalid,
identity-drifted, role-drifted, and duplicate manifests; admit a test
released-road entry only through a production-codec-minted authority; and
require whole-`RoutePlan` equality. Two independently valid released entries for
the same exact plan produce an explicit ambiguity rather than an arbitrary
choice. XCUITest exposes the current `0 RELEASED ROAD · 1 DEMO` catalog in the
default journey. Product schema, release validity, and live-input authority
remain covered portably by KR-D26/KR-D27; only bundle lookup and content hashing
are L3-specific.

KR-U16 adds package and L3 process-lifecycle evidence without inventing a
portable Apple scene event. A schema-1.0 checkpoint round-trips deterministic
coordinate-free state, fails on release identity or schema drift, clears partial
entry evidence and transient presentation/audio values, and preserves the prompt
ledger. A restored actor exposes its first otherwise-HIGH matcher result as LOW,
does not advance or emit, and requires the ordinary reacquisition window.
KR-S03 now also asserts that the first post-gap fix remains LOW; KR-S10, KR-S16,
and KR-S19 retain prompt, matcher-reset, and entry-admission boundaries.
App tests drive `background → atomic store → new runtime → first fix` and prove
no position or prompt replay. XCUITest keeps the no-store launch preview
`FOREGROUND` and deterministic. The app target has no location background mode,
so these checks are termination recovery rather than background navigation.
Together with KR-U15, this selects the existing KR-S10/KR-S17/KR-S18 transient
emission contract rather than adding a portable Apple-audio event, and grants no
field evidence or real-road release authority.

For localization, domain tests prove that all required bundles and spoken forms
exist. Simulator or device tests separately prove voice discovery, pronunciation
fixtures, audio lifecycle, and the visible Japanese sign target. A device voice
being installed is an environment fact, not a portable domain assertion. Pure
package tests cover exact-locale filtering, novelty/personal exclusion,
premium-enhanced-default ordering, deterministic system-default tie-breaking,
explicit preferred-identifier selection, catalog deduplication, explicit
higher-quality readiness, and neutral Apple rate/pitch values. The iOS runtime
test reports the actual installed voice profile after its first admitted prompt;
the separate parked model tests use injected audio. A default-quality Simulator
result is observability evidence, not enhanced acoustic qualification.

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
