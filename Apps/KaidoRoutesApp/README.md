# Kaido Routes iPhone app

Status: active iPhone product target with a default whole-Shuto route-first
planner, labeled replay, and foreground-started live navigation that continues
through screen lock and temporary app switching. The App authors one
exact, content-addressed `KaidoProductRelease` from the validated bundled
snapshot and released movement catalog before attaching Core Location. The
released K7 product remains a deterministic regression fixture. Physical
position accuracy, field reliability, background continuity, acoustic output,
and CarPlay remain separately unqualified.

This target is the first real iPhone composition boundary for Kaido Routes. It
links the local `KaidoDomain`, `KaidoRouting`, `KaidoNavigation`,
`KaidoPresentation`, and `KaidoAppleAdapters` products. The ordinary journey
renders one shared map control with user-selected geographic and whole-route
track-map presentations; tracked recognition and evidence assets remain in the
internal workbench.

The default Release scene and the no-argument Debug scene open the ordered
whole-Shuto product journey rather than the internal evidence workbench:

1. Routes starts with current/manual origin, the whole-network map, named route
   experiences, exact customization, and saved routes;
2. planning derives a direction-valid entrance/exit pairing and compiles one
   exact occurrence-preserving `RoutePlan` from the current bundled snapshot;
3. Review requires both bounded surface legs and keeps passage/toll uncertainty
   visible; and
4. **Replay route** runs the deterministic complete-journey trace, while
   **Start navigation** constructs the selected route's exact joint release and
   begins Core Location in the foreground only after validation succeeds, then
   keeps that active navigation session running through lock screen and app
   switching.

The planning panel can be collapsed and reopened by tap or drag without losing
the selected route. Place completion merges bundled direction-valid Shuto ICs
ahead of MapKit results for both manual origins and destinations. The custom
route editor waits for an origin, pins its current entry and exit at the leading
edge, and exposes searchable nearby candidates with direction and distance.

A saved record labeled `CURRENT SNAPSHOT` has had its complete ordered
`RoutePlan` reconstructed against the exact bundled graph, including repeats
and circuit laps. Circuit source, ID, and lap metadata must reproduce that same
plan and survive reopen/re-save. The record may open parked Review and resolve
fresh bounded surface legs for replay; saving/importing does not upgrade
evidence or unblock live navigation.

The `Diagram | Map` choice persists through the journey. `Diagram` shows the
Kaido-owned whole-network/whole-route track presentation; `Map` shows the exact
selected Shuto path plus bounded ordinary-road legs over MapKit. Replay exposes
pause, resume, finish, and termination reconstruction without claiming live-road
position or current passage status. A junction inset and one-shot speech appear
only for snapshot-bound reviewed movement definitions; lane indices and every
unreviewed movement stay silent. The App generates the road scene and does not
bundle operator photographs used for private visual comparison. Exact HIGH
matcher evidence may advance the replay marker; LOW, LOST, ambiguous, stale, or
identity-drifted evidence cannot.

During a live surface leg, two consecutive accurate off-route fixes trigger a
bounded MapKit recalculation from the current position. Only that ordinary-road
leg changes; the exact Shuto `RoutePlan` and the opposite surface leg remain
unchanged. A cooldown prevents repeated requests during noisy positioning, and
the guidance card exposes recalculation or provider-unavailable state.

Checkpoint load, compatibility, route/runtime validation, save, and removal
failures publish a localized resume-data warning. Rejected or failed
replacement data is invalidated when storage remains writable, so stale
progress and spoken-prompt state cannot silently return after relaunch.

`-C2-ROUTE-MAP-DEMO` opens a dense-route design preview. It shows one complete
Tomigaya-to-Hatsudai-minami circuit as green C2 sections plus the blue
westbound Bayshore section required between Kasai and Oi, with 13 named JCTs
and Oi PA (westbound). Directional entrance and exit names and the PA direction
were checked on 2026-07-29 against the current operator
[C2 facility table](https://www.shutoko.jp/use/network/map/route-c2/),
[JCT map](https://www.shutoko.jp/use/network/jct/), and
[Oi PA westbound page](https://www.shutoko-sv.jp/pa/oi-westbound). The layout
is Kaido-generated, bundles no operator artwork, is visibly marked `DEMO`, and
has no release or navigation authority.

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

## Retained product release catalog

The explicit released-product Debug/regression surfaces do not discover
arbitrary JSON files at runtime. Their compile-time
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

This retained release-backed journey prefers foreground entries when at least
one exists; it is not the default whole-Shuto scene. Otherwise it exposes the
validated demo through the same release-owned authoring model for rehearsal
only. `ReleasedProductRouteAuthoringModel` lists each release through its own
locale-complete presentation and submits every stable recipe choice explicitly
through `ReleasedRouteEditorAdapter`. Compilation must equal the selected
release's whole `RoutePlan`, including snapshot and occurrence order. An
optional compile-time, hash-bound
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

The released K7 descriptor now enrolls one public key and the exact
project-controlled GitHub Pages endpoint. Its published 2026-07-28 envelope is
accepted only inside the envelope's own validity window. The corresponding
private key remains ignored and outside the App; a future key rotation still
requires a reviewed descriptor update.

The retained Debug/regression surfaces additionally compose:

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
- an enrolled signed pre-drive evidence importer and explicit pinned-endpoint
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
  owns the retained release-backed journey's authoring, pre-drive review, and
  fresh-session actor rehearsal while strict entry remains locked, with a
  RoutePlan-bound exactly-once speech adapter waiting for a transient prompt
  emission;
- a release-bound Route Atlas journey overlay that keeps released topology as
  quiet context, renders planned or actor-owned passed/current/future/skipped
  occurrence tracks, preserves repeated traversals with separate ordinal
  markers, keeps source/licence attribution adjacent, and never invents a
  vehicle position;
- an Application Support saved-route library whose atomically replaced
  schema-1.0 file retains complete shared documents, storage origin, evidence
  state, snapshot, and ordered occurrences; the retained release editor still
  requires one whole-RoutePlan-equal foreground release, while the default
  planner may reopen an exact `CURRENT SNAPSHOT` match for parked review/replay
  only, with no evidence promotion or live-navigation authority;
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
accessibility identifiers. The default whole-Shuto map uses a separate
fail-closed attribution surface derived from the exact bundled
`ShutoNetworkDatabase.sources.osm` metadata. It exposes the same official OSM
copyright and ODbL HTTPS links without changing the legacy K7 catalog or its
hash-bound review.

The internal calibration surface requests when-in-use location only after the
operator explicitly starts a run with non-empty device and mount metadata. The
default whole-Shuto product separately authors a complete on-demand joint
release from the exact selected RoutePlan, bundled network snapshot, reviewed
guidance, runtime policy, matcher corridor, and Route Atlas. Its
foreground-navigation controller does not construct a `CLLocationManager`
unless that release mints the unforgeable live-input token for the same product,
navigation release, snapshot, RoutePlan, runtime policy, and matcher corridor.
The schema-6.0 bundled synthetic workbench release remains
`SYNTHETIC_TEST_ONLY + DISABLED`, mints no token, and cannot request permission
or display a live measured position. An admitted
controller requires an explicit user start in an active scene, When In Use
authorization, the declared `location` and `audio` background modes, and an
actor ready to accept input. Once started, it preserves ordered callback
delivery and Apple voice prompts through screen lock and temporary app
switching. Explicit end, completion, permission downgrade, pipeline failure,
or process termination stops the session. It exposes no CarPlay scene. Its Apple speech output
remains idle without an actor-owned one-shot emission; synthetic test callbacks
use an injected recording output rather than device audio. Real-road guidance
still requires a coherent released product artifact, installed-voice and
pronunciation review, and physical location/audio-route evidence.

The app constructs `KaidoProductNavigationRuntime` from the joint product
release; the package-only raw session initializer is not an adapter escape
hatch. The navigation artifact includes one evidenced
`ReleasedNavigationRuntimePolicy`; the app cannot supply or replace its entry
transition, recovery candidates, or Finish egress. The validated runtime
accepts a wrong-turn recovery only when its released divergence occurrence and
trigger directed edge match the observed branch; another branch's candidate is
not eligible. The validated runtime
supplies the only `EntryTransitionAdmissionContext`. The app-owned foreground
pipeline is wired as `CoreLocationObservationAdapter` →
`CoreLocationEntryTransitionAdapter` → `NavigationSession`, and after strict
entry as `CoreLocationObservationAdapter` → `NavigationSession.observe`. Only
the actor's returned atomic snapshot is published. The default product connects
this input only after exact on-demand release admission; tests also prove that
ordered synthetic fixture callbacks cannot grant themselves real-road
authority. Focused controller tests prove release-identity
and release-token admission, explicit authorization, callback ordering,
permission downgrade, background continuity without duplicate restart, and distinct
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
The default product declares `location` and `audio` background modes for an
active user-started navigation session. The retained synthetic scene cannot
mint live-input authority or start either service.

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
launch, and that the retained release-backed Debug journey can reach the same
actor through an explicit, fixed-trace rehearsal without enabling live
location.

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

The retained release-backed journey's pre-drive stage owns a separate
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
current audited declaration is no tracking, no data collected by the Kaido
Routes project, app-private `UserDefaults`
reason `CA92.1`, and elapsed-time reason `35F9.1`.
The whole-network information sheet exposes the on-device progress boundary,
Apple Maps network use, app version, public [`PRIVACY.md`](../../PRIVACY.md),
Apache-2.0 software licence, and the separate bundled
[`DATA-LICENSES.md`](../../DATA-LICENSES.md) notice for the machine-readable
whole-Shuto OpenStreetMap derivative under ODbL 1.0. Release contains only
those disclosures, localizations,
the whole-Shuto snapshot, compiled UI assets, and the app binary; retained K7,
C2, synthetic, and internal-calibration resources remain Debug-only.

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

python3 scripts/validate_ios_release_bundle.py \
  /tmp/KaidoRoutes.xcarchive
```

The dedicated `KaidoRoutesReleaseSmoke` scheme contains only UI tests, so it
exercises the optimized Release app without enabling `@testable` imports in the
distributed binary. The regular `KaidoRoutesApp` scheme remains the complete
Debug unit/UI suite.

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

The physical App suite includes one exact default whole-Shuto foreground
planning-location Core Location lifecycle,
`testWholeShutoForegroundLocationStartsAndStopsThroughCoreLocation()`: the user
action requests When In Use permission, survives the system-dialog scene
interruption, reaches `RUNNING`, and explicitly stops. The default suite is
silent and does not grant audio evidence. The separate physical-audio runner
plays parked Japanese, Simplified Chinese, and English samples only when
explicitly invoked. These are permission, callback, and route-lifecycle smokes
only; they do not
start or enroll live navigation and do not qualify location accuracy, matcher
reliability, voice naturalness, pronunciation, driver comprehension, current
road conditions, CarPlay, or lock-screen/background continuity. See
[`docs/testing/ios-physical-device-qualification.md`](../../docs/testing/ios-physical-device-qualification.md).

When the device's XCTest UI Automation service cannot start, use the narrower
App-hosted audio runner without changing the complete baseline:

```sh
python3 scripts/run_ios_physical_audio_qualification.py \
  --device-id <private-device-identifier> \
  --device-configuration-id iphone13pro-speaker-audio-v1 \
  --development-team <APPLE-TEAM-ID> \
  --allow-provisioning-updates \
  --output research/evidence/ios-physical-audio-2026-07-28-v1
```

It runs exactly one physical App-hosted test for the three installed locales,
voice callbacks, `.playback + .voicePrompt`, and a non-empty output route. Its
coordinate-free receipt grants those audio lifecycle smokes only. It does not
grant the full App baseline or foreground-location smoke, and separate receipts
must not be combined into a source-current complete-baseline claim.

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
`PhysicalAudioQualificationTests` and
`PhysicalAudioQualificationUITests` are excluded from the default scheme so a
build or ordinary test run never activates the speaker. The explicit
`KaidoRoutesPhysicalAudioQualification` scheme retains the parked-only
technical harness for deliberate physical-device checks.
They also save one background checkpoint, reconstruct a fresh runtime, retain
occurrence/prompt identity, clear position/CarPlay state, and require LOW
reacquisition evidence without replay. Package tests independently cover
deterministic checkpoint JSON, release-identity drift, partial-entry reset, the
first-fix matcher fence, and atomic file-store round trip. The platform-light
Swift package tests remain the authoritative domain and navigation verification.
