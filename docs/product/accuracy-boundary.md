# Accuracy boundary

What this product knows, what it treats as candidate data, and what it
refuses to assert. Read this before trusting any guidance it gives.

The product distinguishes what is known from what is still unconfirmed:

- Static operator facility facts and the exact source dates are bundled.
- OSM geometry and connectivity are candidate data under ODbL 1.0; they are not
  operator-authored lane or stacked-road authority.
- The line map and junction inset are Kaido-generated vectors. Every JCT keeps
  the current official detail-image URL and content hash for audit. Reviewed
  movement guidance must also match the exact network snapshot, adjacent edge
  IDs, shared JCT node, direction, and official content hash. The admitted
  definitions cover all divergent JCTs in the bundled snapshot; the
  whole-network inventory resolves 163 of 165 exact movement bindings, all
  but the two 本牧JCT movements from the restored start of K3. They
  authorize only the
  reviewed branch or continuation and approach-specific Japanese sign target.
  They do not copy operator artwork or imply unreleased lane numbers.
- Current traffic, temporary closures, toll quotes, and PA operating status are
  `REALTIME_UNCONFIRMED` until a current provider response exists.
- The driving map draws the planned route in blue, never in the product's warm
  route accent: Apple's congestion layer owns amber and red on that basemap, so
  a warm route line would read as a jam along the whole route. Kaido's own
  surfaces — route cards, course thumbnails, the track map — draw no congestion
  and keep the warm accent.
- The driving map draws Apple's congestion layer and, on tap, Apple's place
  card for a basemap point of interest — the only surface carrying its
  operating hours, because MapKit exposes them to no API. Both are Apple's
  answer rendered on Apple's basemap: neither reaches a Kaido route, tariff,
  or passage decision, and the preview duration stays non-realtime. The drive
  narrows the basemap catalog to fuel, charge, parking, and restrooms so
  storefronts cannot bury the route; a parked map keeps the full catalog and
  omits congestion colouring, which is unreadable at journey framing.
- MapKit surface access and egress cannot author, optimize, replace, or recover
  the Shuto `RoutePlan`. During a live drive, accepted MapKit
  geometry and steps provide the current ordinary-road instruction and
  distance. Live navigation speaks the current provider step and preannounces
  the next step once within 250 meters; these route-bound provider commands
  share the interruption-safe audio output but never gain expressway guidance
  authority. Two consecutive accurate off-route observations trigger a bounded
  MapKit recalculation of only the active ordinary-road leg, with a cooldown;
  the exact Shuto plan and the opposite surface leg remain unchanged. Entry
  evidence takes over only near the exact directional ramp. A single fix that
  misses the ordinary-road leg changes nothing on screen: the step, the
  distance and the position stay as they were, and only the second consecutive
  miss labels the drive as waiting to join the route. That label is never weak
  positioning, and a coarse but on-route fix is still the position; genuinely
  stale positioning keeps the separate degraded warning and speaks it at most
  once per minute.
- The default App's Core Location lifecycle keeps planning location
  foreground-only, while an explicitly foreground-started live navigation
  session continues through screen lock or temporary app switching and stops
  when the journey ends, permission is revoked, or the pipeline fails. It
  supplies the planning origin, five prebuilt releases, the C1 outer on-demand release, and other
  on-device exact routes whose complete decision sequence is covered by the
  163 released movement bindings. Live admission and replay do not grant
  tunnel, field, acoustic, or CarPlay qualification. Tunnel coasting is an
  explicitly low-confidence presentation aid, not dead-reckoning authority;
  spoken expressway guidance still covers reviewed junction movements only.
- On the expressway, route progress and spoken guidance move only on a fix the
  navigation session admits. A fix is not admitted while a road the car could
  have turned onto — a branch leaving the route at or after the last point the
  car was matched clear of every branch — lies within twice the error its
  reported accuracy allows. The matcher corridor follows every such branch
  until it is 125 m from the route, so a branch running a few metres beside
  the plan is visible instead of being mistaken for it. Two consecutive fixes
  on such a branch, with no route road among the candidates, end strict-route
  navigation: the car follows a released detour if one exists, otherwise the
  route is interrupted and only an admitted fix on a later occurrence of the
  same plan resumes it. No U-turn, reversal or nearby exit is invented.
  Where two roads run within GPS error of each other — stacked carriageways,
  a ramp alongside the mainline before it separates — admitted progress pauses
  until they separate (up to about 60 seconds in replay); the position and
  heading hold, and the drive is called weak only after 10 seconds without a
  fix the matcher can place on any corridor road. One reviewed cue cannot be
  given in time for that reason: the Namamugi second split on the Daikoku
  loop, 252 m after the first, before which the first split's other branch
  never separates from the planned one. It is withheld rather than spoken for
  a road the car may not be on.
- A released detour is limited to one whose every junction decision after the
  wrong turn is a released movement binding and which never leaves the
  expressway by an exit ramp. The C1 inner release has none (its former
  Edobashi detour turned through the Hakozaki rotary), so a wrong turn there is
  the unavailable-recovery state.
- Entry is confirmed only after fixes have followed the route head away from
  the straight line the reviewed approach arrives along: each fix is weighed
  for lying on the route head or on that line, normalised by its accuracy,
  where the two are at least 20 m apart. A street running straight on beneath
  or beside a ramp therefore never confirms entry, and confirmation comes
  some way along the route head (about 300 m at a typical entrance, up to
  about 1.6 km). A street that curves exactly with the ramp, or a ramp whose
  route head never leaves its approach line, cannot be told apart by geometry:
  entry then stays unconfirmed and the driver's "already on the expressway"
  join remains the way to start (one direction of Toda-minami, along one
  route-head path within 1.5 km, of 138 directional entrances).
- The drive finishes at a released exit when fixes show the car past the end
  of the route's last edge, or on the exit ramp's own continuation, after
  progress reached the exit tail; a single exact match on a short terminal
  edge is no longer required. A route ending in a PA completes on an admitted
  fix inside the final PA visit.
- These behaviours are proven by a deterministic 1 Hz replay of every bundled
  foreground release through the Core Location adapters and the navigation
  session, with seeded 5–15 m GPS error, 30–60 m bursts and correlated error.
  That is synthetic evidence of deterministic behaviour, not field accuracy.

Inspect one exact planned route's expressway release gaps:

```sh
swift run kaido-release inspect-live-coverage \
  --network data/route-atlas/osm-derived/shuto-whole-network-20260804.json \
  --entry shuto.ic.3.shibuya \
  --exit shuto.ic.k1.minatomirai
```

Export the snapshot-wide candidate JCT movement review worklist:

```sh
swift run kaido-release inspect-network-live-coverage \
  --network data/route-atlas/osm-derived/shuto-whole-network-20260804.json
```

Inspect one bundled circuit without flattening its repeated occurrences:

```sh
swift run kaido-release inspect-circuit-live-coverage \
  --network data/route-atlas/osm-derived/shuto-whole-network-20260804.json \
  --circuit shuto.circuit.c1-inner \
  --entry shuto.ic.c1.shibakouen --exit shuto.ic.c1.shiodome --laps 1
```

The report includes each graph-derived recovery candidate's exact trigger,
ordered edge path, and later RoutePlan target; every candidate remains
unreleased until it is present in a validated product release.
