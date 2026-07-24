# Kaido Routes iPhone preview shell

Status: internal SwiftUI preview app; not released navigation.

This target is the first real iPhone composition boundary for Kaido Routes. It
links the local `KaidoDomain`, `KaidoRouting`, `KaidoNavigation`, and
`KaidoPresentation`, and `KaidoAppleAdapters` products and renders the tracked
Route Atlas assets in one fixed north-up instrument.

The current app deliberately exposes only:

- the 26-route full-network recognition reference;
- the topology-bound K7 evidence candidate;
- a synthetic entrance recommendation whose exact direction and route join
  match the parked editor;
- a parked route-authoring adapter backed by `ExpertRouteEditorSession` and a
  clearly synthetic reviewed catalog;
- a RoutePlan-bound pre-drive review with separate route, tariff, toll, and
  passage evidence;
- an independent interface-language and guidance-voice text preview that keeps
  the Japanese sign target and route shield fixed;
- a four-state synthetic driving preview for conservative position, passage,
  moving-time editing, Finish drive, shared surface ownership, and one
  occurrence-bound junction inset;
- a complete `SYNTHETIC_TEST_ONLY` joint product-release fixture that is decoded
  through the production codec, constructs `KaidoProductNavigationRuntime`, and
  publishes its actor-owned atomic snapshot into SwiftUI while strict entry
  remains locked;
- an opt-in, foreground-only internal location-calibration harness bound to the
  exact ODbL K7 candidate corridor; and
- explicit review and release-blocked states.

It requests when-in-use location only after the operator explicitly starts an
internal calibration run with non-empty device and mount metadata. The product
runtime panel constructs a real `NavigationSession`, but only from a complete
joint release whose identities, sources, and licences are explicitly synthetic.
The panel does not attach a `CLLocationManager`, display a live measured
position, highlight an active route, speak guidance, run location in the
background, or expose a CarPlay scene. Those behaviors still require a coherent
real released route bundle and device evidence.

The app constructs `KaidoProductNavigationRuntime` from the joint product
release; the package-only raw session initializer is not an adapter escape
hatch. The navigation artifact includes one evidenced
`ReleasedNavigationRuntimePolicy`; the app cannot supply or replace its entry
transition, recovery candidates, or Finish egress. The validated runtime
supplies the only `EntryTransitionAdmissionContext`. The app-owned foreground
pipeline is wired as `CoreLocationObservationAdapter` →
`CoreLocationEntryTransitionAdapter` → `NavigationSession`, and after strict
entry as `CoreLocationObservationAdapter` → `NavigationSession.observe`. Only
the actor's returned atomic snapshot is published. The default preview keeps
this input disconnected, and tests prove ordered synthetic fixture callbacks
without granting those callbacks real-road authority. No real product release
artifact exists in the app today.

## Synthetic product runtime composition

`synthetic-product-runtime-preview.json` is a distributable composition fixture,
not a road-data release. Its product release, navigation release, RoutePlan,
runtime policy, matcher corridor, guidance, and renderer-neutral atlas pass the
same validators used by production code. The app then adds a separate safety
gate: every navigation and atlas source must use
`SYNTHETIC_TEST_ONLY`, identify a synthetic authority, and resolve under
`example.com`. Identity or source drift blocks model construction.

The foreground model starts the actor in `PLANNING` with strict-route
auto-commit locked. It retains neither `CLLocation` nor matcher input; it
publishes only the latest actor snapshot and a coordinate-free pipeline status.
Unit tests execute the real two-edge entry adapter and then one route matcher
update, while a launch-only UI test verifies that the default scene remains
input-disconnected and entry-locked.

## Entrance recommendation

The KR-U13 panel renders one immutable `EntranceRecommendation` produced by
`KaidoRouting`. Its selection names an exact facility, target carriageway, route
join occurrence, surface ETA, straight-line distance rank, and routing-owned
reason codes. Rejected nearby candidates retain their failure reasons, so the UI
can explain that the selected entrance is route-compatible rather than merely
closest.

The bundled candidate set is synthetic and makes no location or provider call.
`EntranceRecommendationModel` requires its network snapshot, selected facility,
and join occurrence to match the exact entrance and initial occurrence owned by
the parked editor. Duplicate identities, invalid metrics, missing labels, drift,
or no eligible candidate fail closed. This proves adapter ownership only; it
does not release an entrance or prove a surface approach.

## Parked route authoring

The authoring surface starts from one exact synthetic directional entrance and
renders only the immutable `ExpertRouteEditorSnapshot` values exposed for the
current incoming approach and junction complex. Choice buttons submit the
snapshot's stable choice IDs; the app composition layer supplies fresh
occurrence IDs, including after undo. Reviewed cycles remain repeated
occurrences in the route rail instead of being deduplicated.

The synthetic catalog also declares one exact reviewed lap template. The app
shows **Add another lap** only for opaque candidates returned by the session,
then supplies a fresh ID for every copied occurrence. It never reconstructs the
source slice or infers loop closure. Undo calls the session boundary and removes
one whole duplicated lap as one user action. The compile control stays disabled
until the session accepts an explicit directional exit, after which it creates
the exact `RoutePlan`. The app owns display labels for this synthetic fixture
only; it does not construct real Shuto topology, infer movement legality, or
promote the Route Atlas into selectable navigation data.

KR-U03 adds one synthetic freehand-corridor surface to the initial decision
point. The Canvas records only the parked gesture. Its fixture returns two
stable current choice IDs, and `ParkedCorridorResolutionSession` revalidates the
snapshot, RoutePlan, decision point, and complete candidate values before the
UI may show them. A gesture with zero candidates is unmatched, one candidate
still needs confirmation, and multiple candidates require explicit resolution.
Only the user's selected reviewed choice is then submitted to
`ExpertRouteEditorSession`, which creates the fresh movement and edge
occurrences. The compile control remains locked until the later explicit exit.
The launch-only `-KR-U03-CORRIDOR-PREVIEW` XCUITest performs a real drag and
checks this transition. The fixture does not implement production geometry
matching, snapping tolerances, or release any road layout.

## Pre-drive review

An accepted explicit-exit compilation is enriched by
`RouteDistanceResolver`, which walks the exact occurrence sequence against a
same-snapshot synthetic reviewed-distance catalog. Repeated traversals therefore
increase `RoutePlan.actualDistanceKM` again instead of being deduplicated.
Missing distance coverage, invalid values, or snapshot drift block compilation.

`PreDriveReviewModel` then requires the exact RoutePlan, entrance, and exit
identity. It uses `TariffSelector` to require one unique `ACTIVE` tariff quote
and sends the independent actual distance, tariff distance, amount evidence, and
passage evidence through `PreDriveReviewProjector`. The view never derives toll
from route distance and never presents
`NO_KNOWN_CONFLICT_REALTIME_UNCONFIRMED` as confirmed open. The tracked fixture
is synthetic, and the navigation control remains locked because the app has no
provenance-validated real `KaidoProductReleaseArtifact` binding one navigation
release to the exact released Route Atlas and editor topology.

## Guidance language preview

The KR-U05/KR-U11 panel projects one synthetic `GuidanceFrame` through
`NavigationPresentationProjector`. Japanese, Simplified Chinese, and English
buttons select the navigation explanation, while a separate set selects the
reviewed spoken text. Changing one does not mutate the other. Every combination
keeps the exact Japanese sign target and route shield visible.

This is a text-only adapter proof. The model passes no
`GuidancePromptEmission`, rejects any projection that would claim
`voice.shouldSpeak`, and labels the preview `AUDIO NOT CONNECTED`. A missing
locale or mismatched preserved Japanese sign fails initialization. It does not
localize the complete internal app, verify installed voices or pronunciation,
or implement audio focus and lifecycle.

## Synthetic driving preview

The KR-U06/KR-U07/KR-U08/KR-U09/KR-U10/KR-U12/KR-U14 panel consumes only
`NavigationPresentationProjection`. Its measured reference and degraded
DecisionZone states make the `MEASURED` versus `ESTIMATED` marker treatment
explicit. The degraded state comes from a stale LOW `LocationObservation`
executed through `NavigationEngine`; the resulting projection must remain
realtime-unconfirmed, avoid a positive open-road color, lock route editing, and
require no phone touch.

The Finish state invokes `NavigationEngine.finishDrive()` against one released
synthetic `EgressOption`. SwiftUI then renders the exact projected exit name and
before-branch announcement priority; it does not choose an exit. The engine
retains `U_TURN_OR_REVERSAL` as a prohibited action. Every state omits
`GuidancePromptEmission`, so the preview cannot speak.

The fourth junction-handoff state invokes `NavigationEngine.connectCarPlay()`
to change only presentation ownership. Phone and CarPlay projections retain the
same current occurrence, next movement, prompt, distance, maneuver, lane
preparation, Japanese sign, shields, and immutable `JunctionViewDefinition`.
The iPhone renderer maps the definition's normalized APPROACH, SELECTED, and
ALTERNATIVE paths and zero-based left-indexed lane values without deriving a
branch or lane from prose. Its green road-status color is deliberately not used:
ownership uses cyan, the selected branch uses amber, and the synthetic
`RELEASED` evidence value is labeled fixture-only. This is synthetic adapter
evidence, not a live `NavigationSession`, real position, released route,
`CPMapTemplate`, or CarPlay scene.

KR-U09 adds a bounded accessibility baseline to this same actual panel.
`NavigationAccessibilityProjector` supplies localized route-shield, guidance,
marker, passage, editing, junction, lane, and surface-ownership labels without
giving SwiftUI navigation authority. The selected path has a drawn checkmark,
and every lane has a symbol plus a spoken state. Accessibility Dynamic Type
switches the selector and surface ownership to one column. Unit tests calculate
at least 4.5:1 contrast from the actual critical theme tokens; XCUITest launches
the panel through `-KR-U09-ACCESSIBILITY-PREVIEW` and inspects its accessibility
tree at standard and AXXXL Simulator sizes. This does not qualify the complete
app, VoiceOver focus order, Switch Control, physical devices, or a CarPlay
scene.

## Internal location calibration

The calibration panel is an internal evidence instrument, not product
navigation. Its bundled fixture decodes the tracked K7 ODbL directed database
and candidate RoutePlan into one exact `RouteMatcherCorridor`: 13 ordered route
occurrences plus two reviewed divergence alternatives. The loader requires
`CANDIDATE`, `ODbL-1.0`, explicit one-way geometry, matching snapshot, RoutePlan,
facility, timestamp, and occurrence identities, and
`navigation_authority=false`.

A run must declare an opaque device-configuration ID, a private mount
description, and one transport context. A connected CarPlay scene remains
`CARPLAY_CONNECTED_TRANSPORT_UNKNOWN`; wired or wireless is available only as
an explicit field declaration. Starting requests when-in-use location and feeds
Core Location delegate batches through the real
`CoreLocationObservationAdapter` → `RouteMatcherSession` path. Software-simulated
locations are rejected by the production-default policy.

Raw coordinates, observation IDs, route-plan identity, device details, and
mount details stay inside the in-memory `PRIVATE_RAW_LOCATION` trace. The app
offers no raw-trace persistence or export. Stopping may create only a
coordinate-free `MatcherCalibrationReport`; without independent held-out
annotations it remains `INSUFFICIENT_HELD_OUT_EVIDENCE`. Discard destroys both
the in-memory trace and report.

## Open in Xcode

The generated project is tracked, so XcodeGen is not required merely to open it:

```sh
open KaidoRoutesApp.xcodeproj
```

Select the `KaidoRoutesApp` scheme and an installed iPhone Simulator, then press
Command-R.

Open `RouteAtlasHomeView.swift` and choose **Editor > Canvas** to use the
`#Preview` definition.

## One-command Simulator run

```sh
./scripts/run_ios_preview.sh
```

The script creates a dedicated `Kaido Routes Preview` iPhone 17 Pro simulator
when needed, builds without device signing, installs the app, and launches it.
If no iOS Simulator runtime is installed, install the matching Xcode runtime
first:

```sh
xcodebuild -downloadPlatform iOS
```

## Regenerate the Xcode project

`project.yml` is the source for the generated project. XcodeGen 2.45.3 generated
the current project:

```sh
xcodegen generate
git diff -- KaidoRoutesApp.xcodeproj
```

Regeneration must be deterministic. Review and commit both `project.yml` and the
generated project when either changes. The application target's explicit
`productName` keeps the generated product reference, shared scheme, test host,
and actual `KaidoRoutes.app` bundle aligned when Xcode opens the project.

## Tests

```sh
xcodebuild \
  -project KaidoRoutesApp.xcodeproj \
  -scheme KaidoRoutesApp \
  -destination 'platform=iOS Simulator,name=Kaido Routes Preview' \
  test
```

`AppSafetyStateTests` proves that the internal preview cannot claim route-release
authority or a measured position. `EntranceRecommendationModelTests` prove
direction-first selection evidence, rejected nearer candidates, editor identity
binding, and invalid candidate failure. `ParkedRouteEditorModelTests` prove exact
entrance/current-choice binding, future-choice rejection, session-provided lap
candidates, fresh identities across duplication and undo, grouped lap undo,
explicit-exit compilation with reviewed actual-distance resolution, and
moving-time lockout. `PreDriveReviewModelTests` proves exact RoutePlan identity,
unique active-tariff selection, repeated-occurrence distance, independent
tariff distance, conservative passage presentation, undo invalidation, and
fail-closed quote evidence. `GuidanceLanguagePreviewModelTests` proves
independent interface/voice changes, three-locale Japanese-sign and route-shield
preservation, no speech authority, and fail-closed localized-content drift.
`SyntheticDrivingPreviewModelTests` proves conservative low-confidence
presentation, measured/estimated distinction, no positive-open inference,
DecisionZone editing lockout, engine-owned Finish exit selection, surface
agreement, shared junction geometry/lane identity, CarPlay ownership-only
handoff, and fail-closed facility-name or unreleased-junction drift.
`InternalLocationCalibrationTests` proves exact candidate-corridor construction,
fail-closed navigation-authority handling, transport-context separation, and
coordinate-free non-release reporting. The platform-light Swift package tests
remain the authoritative domain and navigation verification.
