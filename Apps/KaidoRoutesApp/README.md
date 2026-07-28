# Kaido Routes iPhone app

Status: active iPhone product target with one released K7 route. Physical
position accuracy, field reliability, acoustic output, background navigation,
and CarPlay remain separately unqualified.

This target is the first real iPhone composition boundary for Kaido Routes. It
links the local `KaidoDomain`, `KaidoRouting`, `KaidoNavigation`, and
`KaidoPresentation`, and `KaidoAppleAdapters` products. The ordinary journey
renders one shared map control with user-selected geographic and topology
projections; tracked recognition and evidence assets remain in the internal
workbench.

The default scene is now an ordered product journey rather than the complete
internal evidence workbench:

1. Routes starts directly with origin, map, compatible directional entrance,
   available route cards, create route, and saved routes;
2. Plan submits only release-owned parked choices;
3. only an exact compiled RoutePlan unlocks Review; and
4. the released K7 route continues into Drive through its actor runtime and
   starts foreground Core Location only after a second explicit user action.

The `Map | Lines` choice persists across Routes, Plan, Review, and Drive.
The topology renderer consumes only a validated
`RouteAtlasJourneyProjection`, preserves repeated occurrences, and can draw a
precise progress marker only from one exact HIGH matcher estimate admitted
against the active RoutePlan and actor snapshot. LOW, LOST, ambiguous, stale,
or identity-drifted evidence cannot create that marker. The synthetic
geographic preview is presentation-only; a real-road geographic adapter that
is not connected fails closed instead of drawing illustrative roads.

The journey coordinator owns UI stage only. It does not author topology,
occurrence progress, a RoutePlan, passage status, or navigation authority.
Returning to the editor and invalidating the compiled route immediately removes
review readiness and returns the scene to authoring. A future stage cannot be
selected early. The bundled synthetic release can unlock only its own
fresh-session rehearsal: it never mints live-input authority, requests location,
or becomes a foreground navigation release.
The former all-panel review workbench remains available only through
development launch arguments such as `-INTERNAL-REVIEW-HOME`; focused previews
retain their existing deterministic test arguments.

## Bundled product release catalog

The app does not discover arbitrary JSON files at runtime. Its compile-time
`BundledProductReleaseCatalog` manifest names each bundled artifact, pins its
SHA-256 and expected product release ID, and assigns either `DEMO_ONLY` or
`FOREGROUND_NAVIGATION`. The loader validates the descriptor and content hash
before calling `KaidoProductReleaseArtifactCodec`, then requires the decoded
release to match both identity and role. A demo must remain
`SYNTHETIC_TEST_ONLY + DISABLED` with no live-input authority. A foreground
entry must be `RELEASED_ROAD + FOREGROUND_WHEN_IN_USE` and carry only the
authority minted by production decode.

`kaido-release prepare-app-bundle` can derive one exact foreground descriptor,
copy the unchanged validated product and zero or more complete guidance-audio
packs into an Xcode-ready staging directory, and emit an audit manifest.
Every guidance-audio manifest is schema 1.4 and already contains a passed,
hash-bound human review for every exact WAV. App-bundle staging schema 2.0 gives
each pack a stable selection ID, three-language display name, exact release ID,
and manifest hash; duplicate or partial choices fail closed.
The App and CLI share the descriptor value types, so release ID, role, resource
name, and SHA-256 cannot drift through hand transcription. The generated static
descriptor must still be reviewed and explicitly added to `previewManifest`;
staging never becomes runtime resource discovery or automatic enrollment.

The product journey prefers foreground entries when at least one exists.
Otherwise it exposes the validated demo through the same release-owned authoring
model for rehearsal only. `ReleasedProductRouteAuthoringModel` lists each
release through its own locale-complete presentation and submits every stable
recipe choice explicitly through `ReleasedRouteEditorAdapter`. Compilation must
equal the selected release's whole `RoutePlan`, including snapshot and
occurrence order. An optional compile-time, hash-bound
`PreDriveEvidenceBundle` is the default foreground session-evidence provider;
tests may still inject one explicitly. The bundle must satisfy
`ReleasedPreDriveReviewAdapter` before its values may be labeled current. The
user may select one of the five canonical Shuto vehicle classes and ETC or cash
to request matching toll information. Missing, expired, not-yet-valid, or
drifting tariff and passage information remains explicit, but does not revoke
an exact compiled RoutePlan. Known closure or planned-conflict information
still blocks navigation start. The exact route and release selection enables
the primary user action to construct the selected entry's
`ProductNavigationRuntimeModel`. The App then enters a release-keyed navigation
surface while Core Location remains idle. A second explicit action starts
foreground input only after actor activation and When In Use authorization.
Runtime construction failure stays in review, and ending navigation stops input
and speech, removes the active checkpoint, and returns to review. There is no
ID-only or injected mismatched-release fallback. A demo review instead creates a
new checkpoint-free `ProductNavigationRuntimeModel` from that exact decoded
release and admits only the fixture-owned trace. The current manifest contains
`1 RELEASED ROAD · 1 DEMO`. The K7 entry carries one dated, hash-bound evidence
bundle with ten exact vehicle/payment profiles; it is labeled current only
inside that validity window and becomes an explicit stale-information warning
after expiry without blocking the released runtime. The
demo remains a separate rehearsal path and cannot satisfy the released entry.

A foreground descriptor may also pin public Ed25519 keys and one exact,
credential-free HTTPS JSON endpoint for signed pre-drive evidence updates. The
parked authoring and review stages expose manual JSON import when compile-time
trust and the Application Support store exist, plus an explicit refresh action
when the selected product also has a pinned endpoint. The bounded transport
rejects redirects, final-URL drift, credentials, cookies, caches, non-JSON
responses, and oversized envelopes. Both paths revalidate the complete evidence
bundle contract. The model rejects rollback and release-ID reuse, persists
before publishing, verifies again after restart, and refreshes an already
selected vehicle/payment review. A future release waits until its declared
time; after activation, a missing or expired profile does not fall back to older
bundled evidence. Neither path changes product, RoutePlan, location, prompt, or
navigation authority.

The current app deliberately composes only:

- the 26-route full-network recognition reference;
- the topology-bound K7 evidence candidate;
- a catalog-driven native attribution strip adjacent to each Route Atlas,
  including visible OpenStreetMap credit and ODbL source/licence links for K7;
- a synthetic entrance recommendation whose exact direction and route join
  match the parked editor;
- a parked route-authoring adapter backed by `ExpertRouteEditorSession` and a
  clearly synthetic reviewed catalog;
- a RoutePlan-bound pre-drive review with separate route, tariff, toll, and
  passage evidence;
- a foreground-release authoring and pre-drive branch that retains
  release-owned choices and occurrences, presents exact current session
  information when available, and warns without blocking after the dated K7
  bundle expires;
- a dormant signed pre-drive evidence importer and explicit pinned-endpoint
  refresher whose public trust roots are compile-time product descriptors and
  whose accepted envelope is atomically retained under Application Support;
- a parked three-language guidance-voice sound check that ranks installed Apple
  premium/enhanced/default voices, persists one exact preference per synthesis
  locale, can audition a higher-ranked installed candidate before explicit
  confirmation, and keeps audition authority separate from navigation speech;
- an independent interface-language and guidance-voice text preview that keeps
  the Japanese sign target and route shield fixed;
- a four-state synthetic driving preview for conservative position, passage,
  moving-time editing, Finish drive, shared surface ownership, and one
  occurrence-bound junction inset;
- a complete `SYNTHETIC_TEST_ONLY` joint product-release fixture that is decoded
  through the production codec, constructs `KaidoProductNavigationRuntime`, and
  now owns the default journey's authoring, pre-drive review, and fresh-session
  actor rehearsal while strict entry remains locked, with a RoutePlan-bound
  exactly-once speech adapter waiting for a transient prompt emission;
- a release-bound Route Atlas journey overlay that keeps released topology as
  quiet context, renders planned or actor-owned passed/current/future/skipped
  occurrence tracks, preserves repeated traversals with separate ordinal
  markers, keeps source/licence attribution adjacent, and never invents a
  vehicle position;
- an Application Support saved-route library whose atomically replaced
  schema-1.0 file retains complete shared documents, storage origin, evidence
  state, snapshot, and ordered occurrences; only one whole-RoutePlan-equal
  foreground release can reopen a record in the parked release-owned editor,
  with no automatic choices, compilation, evidence admission, or navigation;
- parked local rename, confirmation-gated deletion, deterministic JSON export,
  and validated JSON import controls; import records `SHARED_IMPORT`, unknown
  schemas fail closed without migration, and every mutation persists before the
  published library changes;
- a dormant released-road navigation surface that can be constructed only from
  one exact foreground catalog selection, separates the bound release key from
  user-started live input, exposes the exact release-owned route-only
  `JourneyPlan`, renders only actor-owned projections, and preserves
  `REALTIME_UNCONFIRMED`;
- an opt-in, foreground-only internal location-calibration harness bound to the
  exact ODbL K7 candidate corridor; and
- explicit review and release-blocked states.

`KaidoProductJourneyModelTests` execute ordered advancement, no early review,
compiled-route invalidation, backwards navigation, the exact catalog-backed
release-authority blocker, release-owned authoring with current, missing, and
expired pre-drive information, known-closure blocking, user-started runtime
creation and clean termination, mismatched
injected-release rejection, the exact default demo rehearsal, and fail-closed
construction errors. Dedicated
released-authoring tests cover exact route reconstruction, missing and drifting
evidence, wrong-choice immutability, and locale changes without occurrence
loss. Product runtime tests require a foreground descriptor plus codec-minted
authority, reject demo entries, keep synthetic trace input unavailable, and
remove the checkpoint on termination. Catalog tests cover hash mutation before
codec admission, role promotion, released-road authority, missing/corrupt
assets, descriptor and identity drift, duplicate resources and release IDs,
exact RoutePlan selection, ambiguous matches, signed-update trust validation,
and trust-role isolation. Signed-update model tests cover persist-before-publish,
untrusted input, rollback, future activation, and restoration. Released-editor
adapter tests replay the bundled repeated occurrences through Simplified
Chinese labels and reject a non-recipe choice without mutating the session.
`KaidoProductJourneyUITests` prove the concise Routes launch omits rejected
filler and internal K7/release state, the same map selection survives Routes,
Plan, Review, and Drive, repeated occurrences remain visible, the exact demo
recipe reaches actor-backed Drive, and the fixed trace produces an eligible
topology marker. They also prove the release blocker stays fail closed without
showing raw codes, interface and guidance-voice choices remain independent,
and the evidence workbench requires its explicit launch argument. This is
visual adapter evidence only; it does not qualify a physical device, acoustic
quality, or real navigation.

The SVG remains non-interactive. Attribution is not delegated to SVG text:
`route-atlas-attribution-catalog.json` is a bundled fail-closed contract, and
SwiftUI exposes native source and licence links beside the visible map. The K7
entry must retain `© OpenStreetMap contributors`, the OpenStreetMap copyright
URL, the ODbL 1.0 identifier and URI, always-visible placement, and stable
accessibility identifiers.

It requests when-in-use location only after the operator explicitly starts an
internal calibration run with non-empty device and mount metadata. The product
runtime panel constructs a real `NavigationSession`, but only from a complete
joint release whose identities, sources, and licences are explicitly synthetic.
Its foreground-navigation controller does not construct a `CLLocationManager`
unless it receives the unforgeable live-input token minted by a validated joint
product release for the exact product release, navigation release, runtime
policy, snapshot, RoutePlan, and matcher corridor. The schema-6.0 bundled
synthetic release declares `SYNTHETIC_TEST_ONLY + DISABLED`, mints no token, and
always supplies a typed blocker, so the panel requests no permission and
displays no live measured position. An admitted
controller requires an explicit user start, When In Use authorization, an
active scene, and an actor ready to accept input; inactive or background stops
the source and drains the current callback before checkpointing. It never
enables background location or exposes a CarPlay scene. Its Apple speech output
remains idle without an actor-owned one-shot emission; synthetic test callbacks
use an injected recording output rather than device audio. Real-road guidance
still requires a coherent released product artifact, installed-voice and
pronunciation review, and physical location/audio-route evidence.

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
artifact exists in the app today. Focused controller tests prove release-identity
and release-token admission, explicit authorization, callback ordering,
permission downgrade, scene stop without automatic resume, and distinct
transient versus terminal Core Location failures. Test-only released-road
artifacts obtain their token through the production codec; app tests cannot
construct a token or runtime identity directly.

The main review scene also supplies one
`FileNavigationSessionCheckpointStore` under Application Support. On
`ScenePhase.inactive` or `.background`, the runtime stops speech and atomically
replaces a coordinate-free schema-1.0 checkpoint. That file includes no
coordinates, matcher posterior, Core Location source metadata, or audio queue.
It is bound to the exact product/navigation release, runtime policy, snapshot,
RoutePlan, and matcher corridor. Restoration clears CarPlay ownership, partial
entry evidence, active frame, measured position, and speech authority; an active
drive returns as estimated/LOST and must rebuild a multi-fix matcher window. The
prompt ledger remains, so a process restart cannot replay an old instruction.
The dedicated launch-only preview injects no store to stay deterministic.
Neither scene declares the location background mode or starts a background
location session.

## Synthetic product runtime composition

`synthetic-product-runtime-preview.json` is a distributable composition fixture,
not a road-data release. Its product release, navigation release, RoutePlan,
runtime policy, matcher corridor, guidance, and renderer-neutral atlas pass the
same validators used by production code. Its RoutePlan occurrences carry the
same explicit toll-domain values used by the reviewed editor choices, allowing
the release bundle to prove an exact `ReleasedRouteAuthoringRecipe` without
weakening whole-plan equality. The app then adds a separate safety
gate: every navigation and atlas source must use
`SYNTHETIC_TEST_ONLY`, identify a synthetic authority, and resolve under
`example.com`. Identity or source drift blocks model construction.

The foreground model starts the actor in `PLANNING` with strict-route
auto-commit locked. It retains neither `CLLocation` nor matcher input; it
publishes only the latest actor snapshot and a coordinate-free pipeline status.
Unit tests execute the real two-edge entry adapter and then one route matcher
update through the actor. When that update returns one matching
`GuidancePromptEmission`, the app reprojects the active frame and submits it to
`GuidanceSpeechCoordinator`. Tests require one Japanese command, duplicate
suppression, interruption without replay, a typed installed-voice failure, an
atomic background checkpoint, and restoration without position or prompt replay.
UI tests verify that the runtime remains input-disconnected and entry-locked at
launch, and that the default product journey can reach the same actor through an
explicit, fixed-trace rehearsal without enabling live location.

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

`PreDriveReviewModel` delegates to the platform-light
`PreDriveReviewEvaluator`. The evaluator binds a dated evidence set to an
independently constructed `PreDriveReviewSession` containing the exact RoutePlan,
network snapshot, canonical `ShutoVehicleClass`, and `ShutoPaymentMethod`. The
evidence envelope and every quote must match that session, and exactly one
tariff version must be `ACTIVE` before presentation. A provider cannot change
its envelope and all quotes together to self-authorize another class or payment
path; any mixed-profile non-active quote also rejects the whole evidence set.
It rejects a positive realtime passage state because no live authority and
freshness token exists yet. The view never derives toll from route distance and
never presents
`NO_KNOWN_CONFLICT_REALTIME_UNCONFIRMED` as confirmed open.

`ReleasedPreDriveReviewAdapter` applies the same evaluation to the RoutePlan
owned by one validated `KaidoProductRelease`; tariff and passage evidence remain
per-session inputs rather than frozen release assets.
`ReleasedProductRouteAuthoringModel` requests that evidence only after the
release-owned recipe compiles to the exact selected RoutePlan and the user
optionally selects one of the five official categories plus ETC or cash.
Changing either selection invalidates the old review and issues a new exact
session request. Missing, snapshot-drifted, route-drifted,
vehicle-class-drifted, payment-method-drifted, or rejected evidence keeps review
from being presented as current; it does not invalidate the released route.
Changing the interface locale rebuilds released labels without changing
occurrence progress and reevaluates the same selected tariff profile. The
bundled fixture is synthetic and the default provider supplies no live evidence.

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
localize the complete internal app or verify installed voices or pronunciation.
The separate product-runtime composition owns the implemented speech lifecycle;
this language-selection panel intentionally remains unable to create speech
authority.

## Parked guidance-voice sound check

The product journey's pre-drive stage owns a separate
`GuidanceVoiceSetupModel`. Japanese, Simplified Chinese, and English are
translated to exact Apple synthesis locales `ja-JP`, `zh-CN`, and `en-US`
before voice discovery. The model enumerates only exact-locale voices already
installed on the device, excludes novelty and personal voices through the shared
selector, and orders premium, enhanced, then default quality. Automatic mode
follows that order; an explicit installed identifier may be selected and is
persisted independently for each language in `UserDefaults`. A resolved
non-empty catalog clears a stale identifier rather than silently naming a
removed voice. A temporarily empty catalog does not erase the preference before
Apple voice enumeration has resolved.

For an admitted foreground product, `GuidanceAudioSourceSetupModel` also exposes
a parked-only navigation voice-style menu. Device voice is the safe default.
Any additional row is one independently complete, reviewed, hash-bound offline
pack from that exact product descriptor. The choice persists per product release
and is read once when the navigation runtime is created; a removed selection is
cleared to device voice rather than remapped. The installed-voice menu remains
available as the primary device selection and as playback-start fallback for a
selected offline pack. The fixed sound check auditions the device voice only;
it does not invent a sample outside an offline pack's reviewed manifest.

The audition button is parked-only and requests one fixed representative
route-shield/destination sample for the selected language. If an explicitly
selected voice has a higher-ranked installed candidate, the model may audition
that exact candidate without changing the current navigation preference. It
persists the candidate only after the exact voice completes and the user
explicitly confirms it; a resolved-voice mismatch blocks confirmation and
suppresses subsequent callbacks from the rejected audition.
`AVSpeechVoiceAuditionOutput` owns its own synthesizer and audio lifecycle and
receives no RoutePlan, occurrence, guidance frame, prompt, or ledger value. It
therefore cannot authorize or consume navigation speech.
Audition and admitted navigation speech use one shared utterance configurator
for rate, pitch, pre-delay, and post-delay. A parked comparison therefore does
not silently omit timing that the same installed voice receives during
navigation.
The real `AVSpeechGuidanceOutput` reads the same locale-scoped stored identifier
only when the actor-owned one-shot command is admitted, and falls back to the
best eligible installed voice if that preference is unavailable. Its command
keeps the exact released text for offline-audio matching while passing a
separately rendered, reviewed-form synthesis string to Apple. Term replacement
is longest-first and non-cascading, and does not duplicate a form already
expanded in the spoken text. The app cannot
download Apple voice assets. A default-only device is explicitly described as
basic synthesis and is told to install an enhanced or premium voice through
iPhone Spoken Content settings, then return for a physical-device audition.
On 2026-07-24, the checked preview Simulator exposed only
`Kyoko / ja-JP / DEFAULT`, `Tingting / zh-CN / DEFAULT`, and
`Samantha / en-US / DEFAULT`; it is not acoustic-quality evidence.

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

## Distribution archive

`project.yml` assigns `app.kaidoroutes.preview` to Debug and
`app.kaidoroutes` to Release. Both configurations carry marketing version
`1.0.0` and build `1`. The Release app bundles `PrivacyInfo.xcprivacy`, whose
current audited declaration is no tracking, no off-device data collection,
app-private `UserDefaults` reason `CA92.1`, and elapsed-time reason `35F9.1`.
Settings exposes the same on-device location boundary and links to the public
[`PRIVACY.md`](../../PRIVACY.md).

The structural Release archive can be reproduced without signing:

```sh
xcodegen generate
xcodebuild archive \
  -project KaidoRoutesApp.xcodeproj \
  -scheme KaidoRoutesApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/KaidoRoutes.xcarchive \
  CODE_SIGNING_ALLOWED=NO
```

A local archive is not an App Store submission. Distribution still requires an
App Store Connect record and authorized signing account, truthful App Privacy
answers and privacy-policy URL, content-rights and age-rating answers,
localized listing assets and support URL, export-compliance handling, upload,
and App Review. Apple uses the bundle ID, version, and build from the uploaded
bundle to associate it with the App Store record. See Apple's
[upload guidance](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/),
[app privacy guidance](https://developer.apple.com/app-store/app-privacy-details/),
and [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## Physical-iPhone App baseline

Use `scripts/run_ios_device_qualification.py` instead of changing the Simulator
command when collecting physical-device App evidence. It rejects Simulator,
offline or ambiguous destinations, dirty source, failed/skipped tests, unsafe
tracked output, and existing evidence directories before a passing receipt can
exist. Raw `.xcresult`, summary, and build logs remain in ignored private
storage; the coordinate-free receipt excludes device identifier and name.

The physical suite includes one exact released-K7 Core Location lifecycle:
the user action requests When In Use permission, survives the system-dialog
scene interruption, reaches foreground `RUNNING`, and explicitly stops. The
runner requires that named test to pass and hashes the complete test tree. This
proves physical permission/start/stop wiring only; it does not qualify location
accuracy, matcher reliability, voice naturalness, pronunciation, current road
conditions, CarPlay, or background navigation. See
[`docs/testing/ios-physical-device-qualification.md`](../../docs/testing/ios-physical-device-qualification.md).

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
coordinate-free non-release reporting. `SyntheticProductRuntimeTests`
additionally prove that actor output schedules one occurrence-scoped Japanese
prompt, a duplicate callback does not schedule it again, an interruption never
replays it, and a missing installed voice remains a typed blocked state. They
also exercise a deterministic installed-voice selector that excludes novelty
and personal voices, requires the exact locale, ranks premium above enhanced
above default quality, honors an eligible explicit identifier, rejects stale
preferences, deduplicates the exposed catalog, and uses the system default only
as an equal-quality tie-break. `GuidanceVoiceSetupModelTests` cover persistence,
fixed-sample requests, moving-context lockout, lifecycle events, cold empty
voice enumeration, independent three-language preferences, locale switches,
exact higher-ranked candidate audition, explicit confirmation, and fail-closed
resolved-voice drift. They also cover product-scoped offline style selection,
explicit device-voice reset, and stale-choice rejection.
`GuidanceSpeechProsodyTests` proves that the shared Apple
utterance configurator applies rate, pitch, pre-delay, and post-delay together.
Neutral Apple rate and pitch are tested independently so a compact voice is not
made more mechanical by slow, lowered-pitch app tuning. The product-runtime UI
test executes real Simulator voice discovery on its first admitted prompt and
exposes the selected name, locale, and quality. A default-only result is marked
as a basic fallback and names the iPhone Spoken Content voice installation path;
the current preview Simulator reports only default-quality voices, not an
enhanced-voice qualification.
They also save one background checkpoint, reconstruct a fresh runtime, retain
occurrence/prompt identity, clear position/CarPlay state, and require LOW
reacquisition evidence without replay. Package tests independently cover
deterministic checkpoint JSON, release-identity drift, partial-entry reset, the
first-fix matcher fence, and atomic file-store round trip. The platform-light
Swift package tests remain the authoritative domain and navigation verification.
