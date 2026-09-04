# iPhone product experience

Status: accepted product design contract, checked against the default App on
2026-09-04. The implementation now opens on the
route-first whole-Shuto home, derives entrance/exit pairings and dated tariff
bands for named experiences, supports loop lap count and exact custom routes,
and carries the selected route through review, labeled replay, finish, and
checkpoint reconstruction. Every direction-valid route with complete reviewed
junction coverage can build an authority-bearing foreground product release on
device; incomplete routes still fail closed. An interrupted live journey keeps
its exact release-bound actor checkpoint and returns through an explicit resume
action with matcher reacquisition. Parked review checkpoints are deliberately
discarded so a stale current-location origin is never reused on a later drive.
Saved routes that exactly match the bundled snapshot reopen through current
origin resolution and complete `RoutePlan` reconstruction. The
accompanying visual mockup is illustrative and grants no real-road route, lane,
realtime, or field authority.

## Product thesis

Kaido Routes helps a driver choose a legal Shuto road experience, reach its
exact directional entrance from the current origin, execute the selected
ordered route, and leave through a planned directional exit. The route remains
the primary object. A destination, current address, basemap, or
surface-routing provider cannot rewrite it. The home surface asks which route
to drive, not where to go; a destination is an optional continuation of a
journey.

The iPhone product has four primary surfaces:

1. **Home:** route-experience choice, entrance recommendation, saved routes,
   and an optional destination.
2. **Plan:** an interactive map with geographic and track-map presentations,
   guided or expert authoring.
3. **Review:** one concise journey summary and explicit start action.
4. **Drive:** next-decision guidance and a user-selected geographic or
   track-map presentation.

Evidence workbenches, calibration controls, release keys, codec state, snapshot
IDs, actor state, and raw evidence codes are development surfaces. They do not
appear in the default product journey.

## Home

The home surface asks one question: which route to drive. It shows the network
map as context, an explicit current-location origin chip, and the named
route-experience catalog — versioned candidate templates over the bundled
planning snapshot, covering the drives the audience actually runs (the C1
inner loop, the C2-plus-Bayshore grand loop,
the Bayshore run ending at Daikoku PA, the Yokohama-side Daikoku loop, and an
ordered multi-route scenic grand tour), plus saved routes and one advanced
custom-route entry at the end of the catalog. Parked chrome keeps one Settings
entry for interface language, guidance voice, ordinary-road routing preference,
known map limitations, privacy, and licences. **Major roads first** is the
default; **Faster route** remains available for drivers who prefer the quickest
provider candidate. OSM source and licence credit sits under the title as a compact
caption, adjacent to the map and off the road drawing. Each catalog card presents the
route as a finished experience: its shape thumbnail, distance and duration
class, landmark and PA facts, and — once an origin is known — the derived
entrance/exit pairing as one factual line. It does not lead with a destination
field, and it does not show an editorial, operator, creator, or community
recommendation feed.

Selecting an experience replaces the catalog with one compact draft that has
an explicit **All routes** return action. The draft labels the entrance and its
automatically recommended exit separately; changing the entrance always
recomputes the exit and tariff band as one pairing. Route sequences pair every
shield with its official Japanese route name, so a transition such as `4 → C1`
is shown as `4 · 高速4号新宿線 → C1 · 高速都心環状線`.

The driver chooses a route, never designs an entrance or exit. Entrances and
exits are derived outputs of the chosen route plus the origin and the dated
tariff rule, not inputs the driver must assemble. The manual pairing workflow
survives only inside the advanced custom entry.

The origin chip uses current location only after explicit permission. It also
supports a manually entered origin and previously selected origins. If
permission is denied, saved and manually selected routes remain available.
Manual origin and destination fields share one completion surface. Exact
directional ICs from the bundled snapshot appear before MapKit address and POI
suggestions, keep their selected coordinate through planning, and remain
available when MapKit completion is unavailable.
Entrance recommendation reuses the measured coordinate shown by the origin
chip. If a measurement is still pending, the recommendation action shows that
it is locating and continues automatically when the coordinate arrives; it
does not start a second hidden location request. A denied or unavailable
location exposes and focuses the manual origin before recommendation can
continue.

Saved routes remain below the route-experience catalog. Import preserves the
complete versioned shared document and its evidence state. When the exact
`network_snapshot_id` matches the bundled graph, the planner reconstructs and
revalidates the full ordered `RoutePlan`, including repeated occurrences and
circuit laps, before labeling the record `CURRENT SNAPSHOT`. Opening it requires
a parked origin, resolves fresh bounded surface legs, and enters Review; it does
not silently replan the Shuto sequence. Snapshot drift or invalid occurrence
content stays unavailable. Circuit template metadata must also reproduce the
same complete plan for the named circuit and lap count; valid source parameters
survive reopen and re-save rather than becoming a custom route. This path
enables parked review and replay only: save, import, and current-snapshot
matching cannot create a release or unblock **Start navigation**.

### Derived entrance/exit pairing and tariff bands

Selecting a route experience derives one recommended pairing automatically.
For a loop, almost any nearby entrance qualifies — including a radial
entrance whose legal movements join the loop — because the fare rule
prices the shortest path between the toll points regardless of the laps
driven in between. The fare distance is the shortest DRIVABLE directed
path: this was verified against the operator's own fare search on
2026-08-04 (Hatsudai-minami to Tomigaya quotes the minimum; Higashi-Ogijima
to Daikoku-Futo quotes ¥420 matching our estimate; Kahei to Sachiura hits
the ¥1,950 cap). The folklore radial pairings are dead under the current
rule — the operator prices Shinjuku to Yoyogi at ¥860 because the return
radial is only reachable through a full circuit — so recommendations never
repeat that folklore: the exit search covers the soonest forward exits and
every reachable exit near the entrance, picks the lowest honestly-priced
band, and never recommends an exit sharing the entrance's name (same-named
ramps bill as one toll point, as the operator's Daikoku-Futo page and fare
search confirm across its Bayshore and Daikoku Line ramps). An entrance on
a member route must still match the experience's carriageway direction
(the opposite loop is a different experience), and ordered tours keep
their selected direction-valid entrances and exits throughout. The pairing appears as one
factual line on the card; expanding it reveals the ranked alternatives so
a driver can correct a poor location fix or prefer a different entrance,
but the default path never asks the driver to assemble a pairing.

Surface access to the entrance is tiered: within 8 km the pairing is
recommended normally, between 8 and 16 km it carries an explicit far label,
and longer approaches carry a long-access label. Straight-line distance never
decides whether the ordinary-road leg is drivable: the bounded surface provider
must resolve the exact directional ramp, and a missing access route blocks
review and start. Automatic selection always starts with the nearest reachable,
direction-valid entrance from the current origin. Navigation authority is
evaluated only after that exact pairing is formed and cannot replace the
location recommendation with a distant released sample entrance. An explicit
driver override remains honored and retains its precise release blocker. The
surface legs themselves target the plan's own directional ramp mouths, not
the IC representative point: a full IC's opposite-direction ramps can sit
hundreds of meters apart, and the half/full direction facts decide which
ramp the journey actually uses.

When the bounded surface provider resolves the ordinary-road access leg for
every candidate entrance, the expanded list orders by that comparable surface
access plus Kaido's unchanged route score; otherwise the list retains
deterministic Kaido order and labels each line accordingly. It never mixes
provider routes with straight-line estimates.

Each entrance card shows the exact directional entrance, one factual
surface-access line, and the tariff band of the resulting entrance/exit
pairing when dated tariff evidence is current — otherwise an explicit
no-current-quote state without inventing a tariff distance or amount. Because
the Shuto tariff uses the shortest all-Shuto path between entry and exit, lap
count never changes the quoted band; the entrance/exit pairing does. A
minimum-band pairing may be labeled factually; promotional or competitive copy
is not allowed.

Lap count is an explicit route parameter. When the origin favors a radial
route, recommendations include radial entrances whose legal JCT movements join
the selected loop; the preview shows the join and return movements as ordered
occurrences, never as an implied U-turn or reversal.

### Custom selection

Custom is the advanced entry at the end of the catalog for drivers who want a
pairing the named experiences do not cover. It expands into a map-anchored
route editor rather than replacing the map
with a separate home mode. It lets the parked user pin one nearby
direction-valid entrance, one nearby direction-valid exit, and a route style.
The editor waits for its explicit current-location request before opening; a
denied or unavailable request returns to the manual origin field. Entry and
exit candidates are distance ordered from the route's origin (or destination
when editing an existing point-to-point journey), keep the current selection at
the leading edge, show direction and straight-line distance, and can be filtered
by IC name or route shield. Empty filters and unavailable origins explain the
next action instead of rendering an unlabeled blank row.
The editor previews the concrete route shields and distance before **Use this
route** applies a new exact `RoutePlan`. Opening or dismissing the editor
never marks a draft as selected. Selecting another option immediately clears
any stale access or egress preview unless the complete comparison has already
cached the exact option's two bounded legs. While replacement surface legs
resolve, the new option remains selected and the journey start action stays
unavailable; only the latest selection may publish resolved surface legs. A
selected custom route restores as custom only when its exact snapshot-bound
plan can be reconstructed.

### Optional destination

A journey may end as a circuit — a directional exit and surface egress near
the origin — or continue to a searched destination. The destination field
appears after route choice as an optional step. Typing presents a compact list
of address and point-of-interest candidates. Selecting one resolves a single
coordinate and places its destination marker on the map; if suggestions are
unavailable, the entered name remains usable by the normal search action. The
bounded provider resolves the egress leg to that destination under the same
fail-closed rules as every journey: missing either surface leg blocks review
and start rather than silently skipping part of the journey.

Ordinary-road access, egress, and live rerouting use the same persisted
preference. **Major roads first** requests provider alternatives and may accept
a route up to 15 percent slower, capped at eight additional minutes, when it
has fewer maneuvers or a higher implied average speed. The limit keeps the
preference bounded; it is not a promise that every road is wide. A local street
may remain necessary near an origin, destination, or directional ramp. The
provider's highway and toll avoidance remains separate and no surface
preference may alter the selected Shuto `RoutePlan`.

### Provider boundary

Bounded third-party navigation providers may contribute candidate geometry,
ranking, or comparison evidence to entrance recommendation and route choice.
They do not create content cards, promotional route stories, or route
authority. A candidate must translate onto the exact Kaido graph snapshot and
ordered occurrences before it can become selectable. Required provider
attribution and technical provenance remain in route details or the system map
attribution surface rather than the primary choice row. The default iPhone
adapter currently uses MapKit only for the ordinary-road comparison and cached
surface legs. It asks for alternate automobile routes, removes candidates that
MapKit identifies as highway or toll routes, and applies the persisted bounded
ordinary-road preference to the survivors. MapKit exposes no road-width or
road-class contract, so this remains a best available provider preference,
not verified road-width evidence. Google Routes and other billable services require their own
configured account, credentials, licence review, and executable comparison
before they can occupy the same replaceable boundary.

## Plan

The map occupies most of the screen. The self-drawn Kaido presentation — the
whole-network line diagram before a route exists, the track map after — is the
primary canvas, and a persistent control keeps the geographic presentation one
switch away. The whole product renders in a single midnight visual identity:
blue-black asphalt, an ink Tokyo Bay, receded unlit network, and neon-lit
route lines, with plated labels that never sit on the carriageways. Until
the driver chooses a route the network stays receded; selecting a catalog
experience lights only its member routes in their route colors. Junction
names stay on the diagram. The unzoomed network marks classic places with
licensed circular photographs (Tokyo Tower, Tokyo Skytree, Haneda, Minato
Mirai, and the named bridges) and names a short PA set — Daikoku, Tatsumi
First, Shibaura, Heiwajima, Oi, and Hakozaki. Pinching past the detail
threshold names those places and every bundled PA. A
checkered start-grid glyph may mark the derived entrance direction; it is
purely presentational and no copy anywhere adopts competitive or performance
framing. Each journey phase re-establishes its natural default (planning,
review, and the expressway body open on the Kaido presentation; ordinary-road
legs open on the geographic map), and the driver may override it at any time.
While planning, the diagram carries the driver's current position, the selected
circuit's member routes at full color over a receded rest-of-network, and the
derived entrance and exit marks; these marks are presentation only and carry no
guidance authority. A bottom panel contains the current ordered route and the
next legal action. Its visible handle is functional: pulling down or tapping it
collapses the panel to a route summary and pulling up reopens it, preserving map
access without discarding the draft. Modal Settings, saved-route, custom-route,
and journey-review sheets retain explicit Close or Done actions and visible
system drag indicators.

The track map is the route overview: the entire selected route stays in one
readable frame, drawn as one stylized continuous line in the manner of a
circuit diagram. Orientation and proportion may be adjusted for legibility and
are not required to be north-up or geographically proportional; directed
connectivity, route occurrence order, and facility direction are never
distorted. Every on-route IC, JCT, and PA is always marked on the route
thread; names ride on plates beside their points with a short leader, and
plate density is collision-managed so it fills in as the driver pinches
closer — the same anchored pinch, double-tap, and clamped pan as the network
diagram. While driving, the frame follows the current position at a closer
zoom by default; any gesture hands the viewport to the driver and a recenter
control returns it, with the whole-route frame one double-tap away. The next
facility ahead of the position always keeps its plate and carries its
remaining route distance. In landscape the instrument column (title, guidance
banner, and dock) sits on the leading edge and the map owns the remaining
width at full height; portrait keeps the floating top bar and bottom dock. Off-route network appears
only as quiet context or not at all. Repeated laps remain separate occurrences; the renderer offsets
repeated traversals and exposes their ordinal and count instead of
deduplicating them. A compact summary reports the entrance, JCT, PA, and exit
counts. Facility names follow the interface locale while Japanese sign text
and route shields remain available. The track map carries no speed, lap-time,
ranking, or racing elements.

Dense circuits keep the complete entrance and exit names in the header and
visually distinguish each required route section. A practical C2 circuit
therefore exposes its C2 and Bayshore components instead of drawing a falsely
self-contained C2 ring.

Guided planning starts from one versioned candidate template. It may change
only declared parameters such as direction, lap count, duration band,
directional PA occurrence, finish behavior, and compatible entrance or exit.

Expert planning starts from one exact directional entrance. Each JCT presents
only legal outgoing movements from the current incoming approach. A selected
movement extends one continuous route thread on the track map. Repeated laps
remain separate occurrences. Selecting a directional exit completes the route.

Map gestures never directly create route semantics. A drag or corridor sketch
may propose reviewed choices, but the parked user confirms one exact choice
before the editor changes.

## Review

Route choice and pre-drive review are two separate parked actions. Selecting a
recommended, alternative, or custom route does not start navigation. Once both
bounded surface legs have resolved for the latest exact route, one **Review
journey** action opens a map-anchored route pass. Missing either leg keeps that
action unavailable, exposes one retry action, and cannot be interpreted as a
shorter journey.

Review is a short journey summary, not an evidence report. It shows:

- current origin, resolved surface access, and exact directional entrance;
- the ordered Shuto route, repeated laps, JCT decisions, and planned PA visits;
- directional exit, resolved surface egress, and the destination when one was
  chosen;
- full-journey planned distance and a preview duration that explicitly excludes
  realtime traffic;
- a separately sourced toll quote when current, or an explicit no-current-quote
  state without inventing a tariff distance or amount;
- current traffic or restriction availability with a timestamp; and
- guidance language and voice.

Only an actionable blocker expands automatically. Evidence sources and release
identity remain in a secondary detail sheet. Review preserves the exact selected
journey for both start intents; replay remains synthetic, while navigation stays
disabled unless an authority-bearing release admits it.

The compiled whole-Shuto runtime carries a deterministic asset identity: one
hash binds the complete decoded graph plus its bounds, limitations, source, and
licence metadata, and a second binds the selected `RoutePlan`, matcher corridor,
guidance, recovery candidates, and route-edge lengths to that network-artifact
hash. Once replay reaches entry transition or the expressway, its checkpoint
persists that identity and must match both hashes before runtime progress is
reconstructed; drift returns to parked Review. This is not a
`KaidoProductRelease` and cannot mint its live-input authority. The hashes make
input drift detectable; they do not promote
OSM/provider surface geometry, unreviewed movements, or the network's candidate
evidence status, and they create no lane, realtime, or field authority.
Graph search may retain candidate rejoin shapes for integrity and future review,
but marks them unreleased. A replay deviation therefore becomes unavailable and
interrupts the route; it cannot execute a recovery movement until that movement
is separately reviewed and enrolled by an exact product release.

Checkpoint storage failures are not treated as an empty first launch. The App
labels unreadable, incompatible, invalid, unsaved, or uncleared resume data and
stays parked when restoration cannot be proven. Rejected or failed replacement
data is cleared when storage remains writable, so an older progress position or
spoken-prompt ledger cannot silently return on the next launch.

Review presents two start intents. The secondary action replays the complete
journey without driving and states its 54 km/h reference trace and 20x playback
rate wherever it appears, so a preview cannot be mistaken for a drive. **Start
navigation** may run only when one exact authority-bearing
`KaidoProductRelease`, released surface-provider artifacts, and required field
evidence are enrolled. With the current candidate whole-Shuto graph it fails
closed as `WHOLE_SHUTO_NAVIGATION_RELEASE_REQUIRED`; an asset hash, location
permission, or MapKit route response cannot satisfy that gate.

The default candidate product requests when-in-use location only for the
foreground planning origin. The physical lifecycle smoke proves that permission
and start/stop wiring; it does not enroll live navigation or grant road
authority. A future release-enrolled live drive must pass device fixes through
the shared adaptation boundary, reject invalid, stale, future-dated, and
distributed-build simulated fixes, and admit no entry, expressway, or egress
progress from proximity alone. Its termination restore must retain neither a
measured marker, matcher posterior, partial entry continuity, active audio, nor
background location ownership, and must require fresh observations before new
progress.

## Drive

The driving surface prioritizes:

1. the next legal movement and distance;
2. route shield, Japanese sign target, and lane preparation;
3. the user's selected map presentation and eligible current position;
4. whole-route progress; and
5. one safe finish action.

The next reviewed decision is the primary visual even before its actor-owned
voice or junction-inset threshold is reached. Its distance is the largest
number on the driving surface, while the selected movement text and outgoing
route shield remain directly adjacent. The lower instrument strip carries the
non-realtime reference time remaining, full-journey distance remaining, and one
continuous route-thread progress rail. It must not promote the route's total
remaining distance above the next decision distance.

The driver may switch between the geographic map and the track map at any
time, but cannot edit the route while moving. Both show the active route and
eligible current position. On the track map, the marker communicates the exact
route occurrence and progress without implying geographic precision. A
route-bound junction inset temporarily becomes the strongest visual when it
helps the next decision. It overlays either presentation and is never a third
map mode. In labeled replay it appears only after a supported left or right
DecisionZone frame crosses its bound prompt threshold, then disappears after
that frame clears. The normal guidance card may preview the stored instruction
before that threshold. The inset preserves the bound Japanese sign target,
route shield, distance, and selected branch. It renders its own road scene; operator
photographs may be used for private comparison but are never copied into the
product. Low-confidence or tunnel positioning is shown as estimated without
fabricating a precise marker.

The geographic presentation is the default for the ordinary-road access and
egress legs and renders the selected candidate route over the system MapKit
basemap.
Outside active navigation its camera frames the selected journey (or the
driver's surroundings before a route exists) rather than the whole network
extent. Beneath the highlighted route it also
draws the whole expressway network — both carriageways of every mainline — as
a muted context layer, so the driver always sees the opposite carriageway and
nearby lines the way an ordinary navigation basemap would; the muted layer
never competes visually with the active route and grants no guidance
authority. Stacked or parallel carriageways may coincide in plan view; that is
a display compromise and never affects position matching. A user-started
automatic route simulation may exercise the complete Drive presentation along
the selected route geometry.
The current whole-Shuto replay uses at most 30 meters between generated samples,
a 54 km/h reference trace, and an explicitly displayed 20x wall-clock rate,
including position, progress, and transient junction insets. It remains visibly
synthetic and grants no live-road or passage authority.

Leaving an active preview is a deliberate stop action. It pauses playback and
requires confirmation before clearing progress and returning to route
planning. Completion replaces playback controls with one arrival surface: the
destination or exit summary, full planned journey distance, directional
entrance-to-exit summary, and one **Done** action. Done clears the completed
journey and restores the route-first home; inactive playback controls never
remain on the arrival screen.

## Entry, exit, and external maps

The default journey stays inside Kaido. A bounded provider supplies the ordinary
road access or egress leg and geographic presentation; Kaido owns the exact
entry transition, Shuto RoutePlan, recovery, and exit transition.

An explicit **Open in Apple Maps** action may be offered as a boundary fallback
before the reviewed entrance approach or after the reviewed exit handoff. It is
not the default journey and cannot be used to claim that the external app will
preserve the selected Shuto route.

In labeled replay, a journey with a final destination continues from the
selected exit onto the bounded provider surface-egress candidate. A
release-backed drive may call that transition an exact exit handoff only when
the joint product release also contains the released surface-egress context. A
route scoped only to the exit ends there after explicit confirmation.

## Copy and visual hierarchy

- Use the driver's vocabulary: route, entrance, direction, JCT, PA, exit,
  distance, toll, and next action.
- Do not expose release, codec, actor, matcher, snapshot, manifest, or raw
  authority vocabulary in the default journey.
- Use one title, at most one helper sentence, and one primary action per state.
- Keep warnings short and neutral. Expand only the reason and next safe action.
- Preserve Japanese sign text and route shields in every interface locale.
- Use the route thread as the only strong planning accent. Everything else
  yields to the selected route and next decision.

## Mockup boundary

The Chinese HTML mockup dated 2026-07-27 demonstrates an earlier
destination-first draft of this contract with illustrative route families,
facilities, durations, and current-origin scenarios. Those values are
interaction examples only. They do not represent a released road dataset, live
traffic state, toll quote, navigation-ready route, or the accepted route-first
home.
