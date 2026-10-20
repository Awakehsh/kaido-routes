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
  IDs, shared JCT node, direction, and official content hash. The
  whole-network inventory has 165 exact movements at divergent JCTs, and
  reviewed definitions bind 163 of them. The other two are the Bayshore
  westbound split at 本牧JCT, where the restored start of K3 branches off:
  neither staying on the Bayshore nor taking K3 has reviewed guidance, so a
  route through that split builds no foreground release. The definitions
  authorize only the
  reviewed branch or continuation and approach-specific Japanese sign target.
  They do not copy operator artwork or imply unreleased lane numbers.
- Current traffic, temporary closures, toll quotes, and PA operating status are
  `REALTIME_UNCONFIRMED` until a current provider response exists. Because a
  closed PA and a missed entry ramp look the same, a drive that passes its
  destination PA ends near the destination instead of claiming arrival or
  rerouting. Ending it takes a fix the matcher places on the road past the
  ramp above LOW confidence, at a divergence the car can have reached since
  its last admitted progress. A mid-route PA stop passed on the road it
  replaced is skipped on the same kind of evidence, and the drive goes on.
- Where roads in the same direction run a few metres apart and lead to
  different places, GPS cannot say which one the car is on until they split,
  and the drive holds its position until it can. Out of Route 6 through
  江戸橋JCT and 箱崎JCT that takes up to about 50 s: the C1 link to Route 6
  runs beside other ways of the same junction, the outbound carriageway runs
  beside lanes into the 箱崎 rotary and towards Route 9 and the 箱崎 exit, and
  each could be where the car is. A way off the plan that only rejoins it
  after as long a drive as the plan between (the rotary link beside the
  outbound carriageway) is no such alternative and does not hold it.
- An unplanned exit is recognised from position alone: two consecutive fixes
  better than 30 m that the matcher places on no corridor road and that lie
  at least 100 m from every road of the bundled Shuto network. An ordinary
  road running within 100 m of any Shuto road, such as a frontage road or a
  street under a viaduct, keeps the drive where it was until it turns away.
  The network holds Shuto roads only: a car that drives on past a Shuto
  route's end onto another operator's expressway is handed over as if it had
  left the expressway.
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
  the exact Shuto plan and the opposite surface leg remain unchanged. Every
  fix also goes to the ramp admission, so a car that reaches the entrance
  before the ordinary-road leg ends there still enters, and no reroute is
  requested while the matcher places the car on a corridor road. A car that
  goes on past the entrance, off every corridor road, gets its ordinary-road
  leg back. A single fix that
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
  supplies the planning origin, the five prebuilt releases, and any other
  exact route, the C1 outer loop included, whose complete decision sequence
  is covered by the 163 released movement bindings and whose release is built
  on the device. Live admission and replay do not grant
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
  on such a branch — or on a traversal of the plan the car has already driven
  past, as when it misses the exit of a loop — each clear of every road of the
  plan it can still be on by three times the error its accuracy allows, end
  strict-route navigation: the car follows a released detour if one exists,
  otherwise the route is interrupted and only an admitted fix on a later
  occurrence of the same plan resumes it. No U-turn, reversal or nearby exit
  is invented. A match farther ahead of admitted progress than 40 m/s since
  that progress allows (a repeated traversal of a loop, or a misplaced fix)
  is never admitted.
  Where two roads run within GPS error of each other — stacked carriageways,
  a ramp alongside the mainline before it separates — admitted progress pauses
  until they separate (up to about 60 seconds in replay). The position and
  heading hold; after 5 seconds the marker takes its estimated appearance,
  with no text and no voice. The drive is called weak only after 10 seconds
  without a fix the matcher can place on any corridor road, or, once the
  route is interrupted and the car may be off the corridor, without any fresh
  fix. One reviewed cue cannot be
  given in time for that reason: the Namamugi second split on the Daikoku
  loop, 252 m after the first, before which the first split's other branch
  never separates from the planned one. It is withheld rather than spoken for
  a road the car may not be on.
- Under a tunnel or covered road the App's tunnel hooks follow the occurrence
  the matcher names. With no fixes there, or only cell-grade ones, progress
  resumes after the cover without a wrong commit, but a cue whose whole
  window lies under cover cannot be timed and is not spoken: Nishi-Shinjuku
  and Ohashi JCT inside the Yamate tunnel on the C2 loop, and
  Kawasaki-Ukishima JCT on the Bayshore run and the Daikoku loop.
- A receiver that reports half its true error is outside these guarantees.
  In replay it still commits no occurrence the car is not on and never
  finishes early, but it can interrupt the route on the correct road and can
  fail to confirm entry.
- A released detour is limited to one whose every junction decision after the
  wrong turn is a released movement binding and which never leaves the
  expressway by an exit ramp. The C1 inner release has none (its former
  Edobashi detour turned through the Hakozaki rotary), so a wrong turn there is
  the unavailable-recovery state.
- Entry is confirmed only after fixes have followed the route head away from
  the straight line the reviewed approach arrives along: each fix is weighed
  for lying on the route head or on that line, normalised by its accuracy,
  where the two are at least 20 m apart. A street running straight on from
  the approach therefore never confirms entry, and confirmation comes some
  way along the route head (about 300 m at a typical entrance, up to about
  1.6 km). A street that follows the ramp and route head within GPS error —
  directly beneath them, or alongside within about 15 m — cannot be told
  from the expressway by geometry, course or speed, and can confirm entry
  (14 of 15 such streets did in replay). Once it turns away, the plan does
  not advance, no cue is spoken and the journey does not finish; with the car
  off every expressway road, the position is reported lost after 10 seconds.
  A ramp whose route head never leaves its approach line stays unconfirmed,
  and the driver's "already on the expressway" join remains the way to start
  (one direction of Toda-minami, along one route-head path within 1.5 km, of
  138 directional entrances).
- The drive finishes at a released exit once the car is past the plan's
  last choice of road, on three consecutive fixes that are on no corridor
  road near the exit, where the corridor still holds every alternative (it
  follows them for 300 m past the exit decision), and at least four times
  their accuracy from every alternative, earlier passes of the plan
  included. An exit ramp that runs beside the road it leaves cannot be told
  from it before the ramp ends, so such a drive finishes after the ramp.
  Driving on past the exit is a deviation like any other and never
  finishes the journey. In replay over seeds 1–40 the bundled exit-ended
  releases (C1 at Shiodome, C2 at Itabashi-honcho) finish 7 seconds after
  the exit on average and within 21 seconds. A route ending in a
  PA completes on an admitted fix inside the final PA visit.
- These behaviours are proven by a deterministic 1 Hz replay of every bundled
  foreground release through the Core Location adapters, the App's tunnel
  hooks and the navigation session: ten seeds of 5–15 m GPS error with
  30–60 m bursts, multipath that holds its offset for about 30 seconds,
  fixes whose true error is twice the reported accuracy, tunnel outages,
  wrong branches, missed final exits and PAs, and streets beside the route
  head. That is synthetic evidence of deterministic behaviour, not field
  accuracy: no route has yet been driven for field evidence.
- Known gaps in the bundled data and planning:
  - The snapshot has no link from C1 内回り onto Route 1 or Route 11 at
    浜崎橋JCT, so no route takes that turn and fare paths that need it go the
    long way round (see [network snapshot](network-snapshot.md)).
  - 加賀 to 東領家 cannot be planned: 加賀's entrance joins S1 上り about
    100 m after 東領家's exit has left it, so the pair has no drivable path,
    although the operator's fare table prices it.
  - Four directions the operator lists have no ramp in the snapshot and stay
    unbound: 新都心西 下り entrance, 横浜港北 (横浜北線) 下り entrance and 上り
    exit, and 八潮 下り exit, whose only OSM link rejoins the carriageway.
  - Entrance recommendation does not read the snapshot's ETC-only flag, so a
    ramp only an ETC car can use, such as 殿町, can be the recommended
    entrance. Tariff bands are quoted for ETC.

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
