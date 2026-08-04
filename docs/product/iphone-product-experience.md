# iPhone product experience

Status: accepted product design contract, realigned on 2026-08-03 to the
route-first home, entrance recommendation with tariff bands, and the
whole-route track map. The current implementation still reflects the earlier
destination-first home and must migrate to this contract. The accompanying
visual mockup is illustrative and grants no real-road route or navigation
authority.

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
route-experience catalog — reviewed route templates covering the drives the
audience actually runs (the C1 inner loop, the C2-plus-Bayshore grand loop,
the Bayshore run ending at Daikoku PA, the Yokohama-side Daikoku loop, and an
ordered multi-route scenic grand tour), plus saved routes and one advanced
custom-route entry at the end of the catalog. Each catalog card presents the
route as a finished experience: its shape thumbnail, distance and duration
class, landmark and PA facts, and — once an origin is known — the derived
entrance/exit pairing as one factual line. It does not lead with a destination
field, and it does not show an editorial, operator, creator, or community
recommendation feed.

The driver chooses a route, never designs an entrance or exit. Entrances and
exits are derived outputs of the chosen route plus the origin and the dated
tariff rule, not inputs the driver must assemble. The manual pairing workflow
survives only inside the advanced custom entry.

The origin chip uses current location only after explicit permission. It also
supports a manually entered origin and previously selected origins. If
permission is denied, saved and manually selected routes remain available.
Entrance recommendation reuses the measured coordinate shown by the origin
chip. If a measurement is still pending, the recommendation action shows that
it is locating and continues automatically when the coordinate arrives; it
does not start a second hidden location request. A denied or unavailable
location exposes and focuses the manual origin before recommendation can
continue.

### Derived entrance/exit pairing and tariff bands

Selecting a route experience derives one recommended pairing automatically:
the nearest direction-valid entrance compatible with the route's first
occurrence, and — for loop experiences — the exit whose entrance/exit pairing
lands in the lowest available tariff band, tie-broken by shortest forward
travel after the loop closes. Ordered tours and PA-terminated runs carry their
own reviewed egress instead. The pairing appears as one factual line on the
card; expanding it reveals the ranked alternatives so a driver can correct a
poor location fix or prefer a different entrance, but the default path never
asks the driver to assemble a pairing.

Surface access to the entrance is tiered: within 8 km the pairing is
recommended normally, between 8 and 16 km it carries an explicit far label,
and beyond 16 km the experience fails closed with the factual distance to
the nearest entrance instead of recommending a long ordinary-road leg — a
distant origin belongs to a radial approach, not surface navigation. The
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

### Provider boundary

Bounded third-party navigation providers may contribute candidate geometry,
ranking, or comparison evidence to entrance recommendation and route choice.
They do not create content cards, promotional route stories, or route
authority. A candidate must translate onto the exact Kaido graph snapshot and
ordered occurrences before it can become selectable. Required provider
attribution and technical provenance remain in route details or the system map
attribution surface rather than the primary choice row. The default iPhone
adapter currently uses MapKit only for the ordinary-road comparison and cached
surface legs. Google Routes and other billable services require their own
configured account, credentials, licence review, and executable comparison
before they can occupy the same replaceable boundary.

## Plan

The map occupies most of the screen. A persistent control switches between the
geographic presentation and the Kaido track map. The choice is not tied to
journey phase and persists when navigation begins. A bottom sheet contains the
current ordered route and the next legal action.

The track map is the route overview: the entire selected route stays in one
readable frame, drawn as one stylized continuous line in the manner of a
circuit diagram. Orientation and proportion may be adjusted for legibility and
are not required to be north-up or geographically proportional; directed
connectivity, route occurrence order, and facility direction are never
distorted. Every on-route IC, JCT, and PA is always labeled — labels do not
appear or disappear with zoom — and a leader must return each spaced label to
its exact route point. Off-route network appears only as quiet context or not
at all. Repeated laps remain separate occurrences; the renderer offsets
repeated traversals and exposes their ordinal and count instead of
deduplicating them. A compact summary reports the entrance, JCT, PA, and exit
counts. Facility names follow the interface locale while Japanese sign text
and route shields remain available. The track map carries no speed, lap-time,
ranking, or racing elements.

Dense circuits keep the complete entrance and exit names in the header and
visually distinguish each required route section. A practical C2 circuit
therefore exposes its C2 and Bayshore components instead of drawing a falsely
self-contained C2 ring.

Guided planning starts from one reviewed recommended template. It may change
only approved parameters such as direction, lap count, duration band,
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
identity remain in a secondary detail sheet. A second explicit primary action
starts the exact reviewed journey. The current implementation labels that action
as a synthetic full-journey preview and discloses its 54 km/h reference trace
and 20x playback rate.

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
map mode. It appears only after a supported left or right DecisionZone frame
crosses its released prompt threshold, then disappears after that frame clears.
The normal guidance card may preview the reviewed instruction before that
threshold. The inset preserves the released Japanese sign target, route shield,
distance, and selected branch. It renders its own road scene; operator
photographs may be used for private comparison but are never copied into the
product. Low-confidence or tunnel positioning is shown as estimated without
fabricating a precise marker.

The geographic presentation is the initial default and renders the released
route over the system MapKit basemap. Beneath the highlighted route it also
draws the whole expressway network — both carriageways of every mainline — as
a muted context layer, so the driver always sees the opposite carriageway and
nearby lines the way an ordinary navigation basemap would; the muted layer
never competes visually with the active route and grants no guidance
authority. Stacked or parallel carriageways may coincide in plan view; that is
a display compromise and never affects position matching. A user-started automatic route simulation
may exercise the complete Drive presentation along the selected route geometry.
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

For a journey with a final destination, the drive continues from the exact exit
handoff onto the released surface egress leg. A route scoped only to the exit
ends there after explicit confirmation.

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
