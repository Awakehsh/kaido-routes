# iPhone product experience

Status: accepted product design contract; the accompanying visual mockup is
illustrative and grants no real-road route or navigation authority.

## Product thesis

Kaido Routes helps a driver choose a legal Shuto road experience, reach its
exact directional entrance from the current origin, execute the selected
ordered route, and leave through a planned directional exit. The route remains
the primary object. A destination, current address, basemap, or surface-routing
provider cannot rewrite it.

The iPhone product has four primary surfaces:

1. **Routes:** current origin, destination search, and saved routes.
2. **Plan:** an interactive map with geographic and topology projections,
   guided or expert authoring.
3. **Review:** one concise journey summary and explicit start action.
4. **Drive:** next-decision guidance and a user-selected geographic or topology
   map projection.

Evidence workbenches, calibration controls, release keys, codec state, snapshot
IDs, actor state, and raw evidence codes are development surfaces. They do not
appear in the default product journey.

## Routes

The origin chip uses current location only after explicit permission. It also
supports a manually entered origin and previously selected origins. If
permission is denied, saved and manually selected routes remain available.

The surface begins with the map, an explicit current-location control, one
destination field, and one route-search action. It does not show an editorial,
operator, creator, or community recommendation feed below those controls.

Recommended, alternative, and custom choices appear only after a destination
has been resolved. The route-choice row shows the recommended exact route first,
the custom control second, and further alternatives after it. Each route option
contains only its selection label, route shields, and distance. Custom expands
route preferences in place; it does not replace the map with a separate home
mode.

Bounded third-party navigation providers may contribute candidate geometry,
ranking, or comparison evidence to this route-choice stage. They do not create
content cards, promotional route stories, or route authority. A candidate must
translate onto the exact Kaido graph snapshot and ordered occurrences before it
can become selectable. Required provider attribution and technical provenance
remain in route details or the system map attribution surface rather than the
primary route-choice row.

## Plan

The map occupies most of the screen. A persistent control switches between the
geographic projection and Kaido's rectilinear topology projection. The choice
is not tied to journey phase and persists when navigation begins. A bottom sheet
contains the current ordered route and the next legal action.

The topology projection is an overview of the selected route, not a claim of
full-network coverage. It shows route shields and release-bound directional
entrance, selected JCT movement, and exit landmarks in route order, together
with the released route's PA visit count. Facility labels may use an evenly
spaced two-column layout for legibility, but a leader must return each label to
its exact Route Atlas point. A compact summary reports the entrance, JCT, PA,
and exit counts. Facility names follow the interface locale while Japanese sign
text and route shields remain available.

Short routes may use larger sign-like facility cards. Dense circuits use
compact labels around the selected route, keep the complete entrance and exit
names in the header, and visually distinguish each required route section. A
practical C2 circuit therefore exposes its C2 and Bayshore components instead
of drawing a falsely self-contained C2 ring.

Guided planning starts from one reviewed recommended template. It may change
only approved parameters such as direction, lap count, duration band,
directional PA occurrence, finish behavior, and compatible entrance or exit.

Expert planning starts from one exact directional entrance. Each JCT presents
only legal outgoing movements from the current incoming approach. A selected
movement extends one continuous route thread on the atlas. Repeated laps remain
separate occurrences. Selecting a directional exit completes the route.

Map gestures never directly create route semantics. A drag or corridor sketch
may propose reviewed choices, but the parked user confirms one exact choice
before the editor changes.

## Review

Review is a short journey summary, not an evidence report. It shows:

- current origin to exact directional entrance;
- the ordered Shuto route, repeated laps, JCT decisions, and planned PA visits;
- directional exit and optional surface egress destination;
- actual planned distance, estimated duration, and separately sourced toll;
- current traffic or restriction availability with a timestamp; and
- guidance language and voice.

Only an actionable blocker expands automatically. Evidence sources and release
identity remain in a secondary detail sheet. One primary button starts the exact
reviewed journey.

## Drive

The driving surface prioritizes:

1. the next legal movement and distance;
2. route shield, Japanese sign target, and lane preparation;
3. the user's selected map projection and eligible current position;
4. whole-route progress; and
5. one safe finish action.

The driver may switch between the geographic and topology projections at any
time, but cannot edit the route while moving. Both show the active route and
eligible current position. In topology view, the marker communicates the exact
route occurrence and progress without implying geographic precision. A
route-bound junction inset temporarily becomes the strongest visual when it
helps the next decision. It overlays either projection and is never a third map
mode. It appears only after a supported left or right DecisionZone frame crosses
its released prompt threshold, then disappears after that frame clears. The
normal guidance card may preview the reviewed instruction before that threshold.
The inset preserves the released Japanese sign target, route shield, distance,
and selected branch. It renders its own road scene; operator photographs may be
used for private comparison but are never copied into the product.
Low-confidence or tunnel positioning is shown as estimated without fabricating
a precise marker.

The geographic projection is the initial default and renders the released
route over the system MapKit basemap. A user-started automatic route simulation
may exercise the complete Drive presentation along the selected route geometry.
The current whole-Shuto replay uses at most 30 meters between generated samples,
a 54 km/h reference trace, and an explicitly displayed 20x wall-clock rate,
including position, progress, and transient junction insets. It remains visibly
synthetic and grants no live-road or passage authority.

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

The Chinese HTML mockup dated 2026-07-27 demonstrates this contract with
illustrative route families, facilities, durations, and current-origin
scenarios. Those values are interaction examples only. They do not represent a
released road dataset, live traffic state, toll quote, or navigation-ready
route.
