# Product principles

## Product promise

Kaido Routes lets a driver select a legal sequence of roads and junction
movements because the drive itself is the destination. It then helps the driver
execute that sequence using the route numbers, directions, destinations, and
lane preparation visible on real signs.

For reviewed critical movements, Kaido may show a compact junction inset generated
from its own structured geometry, lane, and sign semantics. It does not copy an
operator or navigation provider's junction artwork, and an adapter cannot invent
the diagram from prose.

This differs from adding many waypoints to a fastest-route navigator. A waypoint
describes a place to pass near; a Kaido route describes the exact directional
movement to take and preserves repeated traversals.

## Primary users

### Local enthusiast

Creates, repeats, saves, verifies, and shares exact routes. Values movement-level
control, route versions, optional PA visits, and strict execution.

### Foreign self-drive visitor

Starts from a verified route, chooses a suitable difficulty and duration, and
needs Japanese sign matching with concise Japanese, Simplified Chinese, or
English explanation and voice. Values confidence and safe recovery more than a
fully exposed graph editor.

### Guided self-drive participant

Uses the route as a backup when separated from a lead vehicle. This is a later
workflow and must not imply that following another driver overrides signs or
traffic control.

## Core principles

1. **Route before destination.** The ordered road experience is a first-class
   saved object.
2. **Legal movements only.** The editor offers outgoing choices that are legal
   from the current approach and network snapshot.
3. **Repetition is intentional.** A lap is another occurrence sequence, not a
   duplicate to optimize away.
4. **Signs are the shared language.** Route shields and Japanese destinations
   remain visible in every locale; translations and spoken forms help the user
   recognize them.
5. **Uncertainty is visible.** Location, road status, PA availability, toll, and
   evidence each expose their own confidence or verification state.
6. **The driver prepares before moving.** Complex editing and study happen while
   parked. Driving mode remains glanceable and low-interaction.
7. **Culture without racing.** Night scenery, engineering, JDM history, and PA
   etiquette are useful content. Speed and enforcement-evasion mechanics are not.
8. **Recovery preserves the route.** A missed movement finds a safe legal path to
   a later occurrence in the selected route; it does not replace the drive with
   destination-first navigation.
9. **Entry and exit are explicit — and priced.** After the user chooses a
   route, current-location recommendations target exact direction-valid
   entrances compatible with that route. Each entrance/exit pairing shows its
   tariff band from dated tariff evidence, or an explicit no-current-quote
   state; because the Shuto tariff uses the shortest all-Shuto path between
   entry and exit, lap count never changes the quoted band. A cruise ends only
   through a legal planned exit sequence, never by reversing or accidentally
   leaving the expressway.
10. **One map control offers two presentations.** The user may switch between
    a provider-backed geographic driving map and the Kaido-owned whole-route
    track map while planning or driving; the product does not force one
    presentation by journey phase. The geographic map preserves local spatial
    context during surface access, entry, and egress. The track map keeps the
    entire selected route readable in one frame — one stylized continuous
    route line in the manner of a circuit diagram, with every on-route
    directional IC, JCT, and PA labeled at all times, so the whole drive is
    legible at a glance without zooming. Track-map orientation and proportion
    may be adjusted for legibility and need not be north-up, but directed
    connectivity, facility direction, and route occurrence order are never
    distorted. Both presentations preserve the active `RoutePlan`, eligible
    current position, current occurrence, passed and future occurrences,
    repeated traversals, and positioning uncertainty. A track-map marker
    represents route-bound progress, not geographic precision. A reviewed
    junction inset may clarify the next decision. Neither presentation nor its
    UI may create route semantics, and Kaido-owned simplification must not
    copy operator artwork.
11. **Say only what helps now.** Interface copy is short, literal, and
    action-first. Driving surfaces state the current road, next legal movement,
    distance, and uncertainty without slogans, repeated reassurance, or internal
    implementation jargon. Provenance and technical detail remain available in
    pre-drive and evidence views instead of competing with the next driving
    decision.

## Product shape today and the route-first realignment

The whole-Shuto planning layer is released: a bundled dated network snapshot
covering all 26 official routes with directional IC facilities, JCTs, and PAs;
deterministic route search and exact custom selection; fail-closed surface
access and egress legs; and pre-drive review. The reviewed journey can then be
driven on real device positions, or replayed as an explicitly labeled preview;
both run the same reducer, and the live drive is foreground-scoped and refuses
invalid or spoofed fixes rather than turning them into progress.

Navigation-grade guidance remains movement-by-movement: only reviewed junction
movements produce insets and speech, and that coverage grows after evidence
review rather than shipping a visually complete but unevenly verified guidance
layer. A driver on a route without reviewed movements gets position, progress,
and the next facility with its distance, and no spoken turn instruction — the
product says less rather than guessing.

Coverage is extended by reviewing the operator's own junction detail diagrams.
They are published as images rather than machine-readable text, so each review
reads the diagram, records the sign target and arrow treatment it shows, and
binds the result to one exact directed movement in the snapshot — junction
node, incoming edge, outgoing edge, carriageway direction — with the diagram's
content hash recorded so a redrawn diagram invalidates the review. A movement
whose diagram shows the route continuing on a straight arrow is released as a
mainline continuation that asserts no lane; releasing a left or right branch
instruction additionally requires the diagram to show that branch treatment
unambiguously for that exact approach.

Coverage today: the C1 inner catalog loop and the Bayshore corridor in both
directions are reviewed at every junction where another route diverges from
them. The junctions that remain unreviewed each failed a specific evidence
test rather than merely awaiting work — a diagram whose signs are exit
previews rather than a fork (Hakozaki), a junction where the through route is
not the straight leg (Kohoku), pre-advisory signs that show every destination
on a straight arrow so no leg is distinguished (Kosuge-Horikiri, Itabashi-
Kumanocho, Kinko), and a junction where the operator publishes explicit
per-approach lane advice that a no-lane prompt would under-serve (Namamugi).
Movements that change route rather than continue on one need the diagram to
show that branch treatment for that exact approach, which none of the
remaining ones do yet.

The route-first realignment accepted on 2026-08-03 prioritizes, in order:

1. a route-first home: the user chooses the route experience before anything
   else, and destination search becomes an optional continuation;
2. entrance recommendation from the current origin with tariff bands,
   including legal radial-to-loop joins and adjustable lap count;
3. the whole-route track map replacing the semantic-zoom topology projection;
4. clear, always-visible facility labeling on the selected route.

## Non-goals for the first implementation

- generic door-to-door navigation for all Japanese roads beyond the bounded
  access and egress legs of a supported Kaido journey;
- live traffic redistribution without licensed data;
- guaranteed toll or PA availability;
- crowd rendezvous or event coordination at parking areas;
- lap timing, speed scoring, competitive leaderboards, or driving telemetry for
  public-road performance comparison;
- claiming continuous precise location in every tunnel or CarPlay setup.
