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
9. **Entry and exit are explicit.** Current-location recommendations target an
   exact directional entrance. A cruise ends only through a legal planned exit
   sequence, never by reversing or accidentally leaving the expressway.
10. **The route network stays visible.** On the supported Shuto network, the
    primary driving surface keeps a stable schematic route atlas visible instead
    of replacing route context with a rotating street basemap. The active
    `RoutePlan`, current occurrence, passed and future occurrences, repeated
    traversals, and positioning uncertainty remain distinguishable. A local
    approach-aligned junction inset may clarify the next reviewed decision
    without rotating or erasing the atlas.

## First product slice

The smallest useful product is not the whole Shuto network. It is:

- a small dated network snapshot;
- a few fully checked entrance, movement, PA, and exit combinations;
- one short central route and one tunnel-heavy outer route;
- a persistent schematic atlas of the released network slice, without implying
  that unsupported Shuto corridors are navigable or verified;
- pre-drive route review;
- deterministic route execution with repeated occurrences;
- current-location access to a small set of verified directional entrances;
- automatic entry-phase recognition with a low-confidence fallback;
- safe route rejoin and a precomputed finish-drive egress plan;
- explicit degraded positioning;
- Japanese, Simplified Chinese, and English text and voice guidance;
- planned-conflict warnings and honest real-time uncertainty.

Coverage should grow movement by movement after evidence review rather than
shipping a visually complete but unevenly verified map.

## Non-goals for the first implementation

- generic door-to-door navigation for all Japanese roads beyond the bounded
  access and egress legs of a supported Kaido journey;
- live traffic redistribution without licensed data;
- guaranteed toll or PA availability;
- crowd rendezvous or event coordination at parking areas;
- lap timing, speed scoring, competitive leaderboards, or driving telemetry for
  public-road performance comparison;
- claiming continuous precise location in every tunnel or CarPlay setup.
