# Current capabilities

What the shipped product does today, and the exact guarantees behind each
capability. Summarized in [`README.md`](../../README.md).

The default app opens on the whole Shuto network, not a sample route or an
internal review workbench.

- The full-network line map shows all 26 current official route entries,
  directional IC facilities, JCTs, and PAs.
- The geographic map shows the selected route on MapKit and keeps the exact
  Kaido-owned Shuto path separate from bounded surface access and egress.
  Beneath the highlighted route it draws every mainline carriageway — both
  directions — as a muted context layer with no guidance authority.
- The home is route-first: a named route-experience catalog leads the
  planning surface — the C1 inner loop, the C2 inner loop closed by the
  Bayshore Route, the Bayshore westbound run ending at Daikoku PA, the
  Yokohama-side Daikoku loop, and a scenic grand tour past Haneda, Minato
  Mirai, and the Yokohama Bay Bridge finishing beside Daikoku PA. The driver
  chooses a route, never designs an entrance or exit: selecting an
  experience derives the pairing automatically (nearest reachable
  direction-valid entrance, and for loops the exit whose pairing lands in
  the lowest tariff band), shows it as one factual line with ranked
  alternatives one disclosure away, offers a 1–9 lap count on loops, plans
  the experience as one ordered occurrence sequence, and runs it as a round
  trip through the normal review gate. Tariff bands come from dated ACTIVE
  evidence (normal car, ETC): the minimum band is asserted only with a
  distance safety margin, mid-range amounts stay explicit estimates, and
  nothing is shown until a band is computed. Because the tariff uses the
  shortest all-Shuto path between entry and exit, lap count never changes
  the band. Destination search remains an optional continuation below the
  catalog.
- Routing ranks compatible entrances and exits for arbitrary origin and
  destination coordinates, then searches the directed whole-network graph.
- Route choice keeps recommendations and exact customization together. Every
  candidate identifies its directional entrance and exit. When the bounded
  surface provider resolves both ordinary-road legs for every exact candidate,
  the row uses those comparable ETAs for ordering and shows full-journey preview
  time and distance. A partial provider result preserves deterministic Kaido
  order and labels every card as Shuto-only rather than mixing incomparable
  estimates. Custom selection pins one direction-valid entrance, one
  direction-valid exit, and a route style, previews the resulting route thread,
  and applies its own Kaido-owned `RoutePlan` without turning the map into
  another home surface.
- Route choice leads to one parked route pass before the drive starts. It
  combines the bounded surface access and egress legs with the exact selected
  Shuto route, shows full-journey distance and a non-realtime preview duration,
  and keeps passage and toll information explicitly unconfirmed when no current
  source exists. Missing either surface leg blocks review and start rather than
  silently skipping that part of the journey.
- Saved-route import preserves the complete shared `RoutePlan` and never
  upgrades its evidence. A record labeled `CURRENT SNAPSHOT` has been
  reconstructed and revalidated against the exact bundled whole-Shuto snapshot,
  including repeated occurrences and circuit laps; it may reopen parked review
  and replay only. Live start still requires an authority-bearing
  `KaidoProductRelease`.
- Route occurrences remain ordered and distinct. Directed links represent
  candidate entrances, exits, and junction connectivity; official facility
  facts remain distinguishable from OSM topology.
- The bundled whole-Shuto graph remains a candidate asset rather than blanket
  navigation authority. Five representative foreground releases are prebuilt
  for startup regression. Every other plannable exact `RoutePlan` is rebuilt
  and content-addressed on device from the same validated snapshot and 161
  released movement bindings before **Start navigation** is enabled. The
  exhaustive admission audit covers all 51,582 direction-valid facility route
  combinations; malformed, mismatched, or incomplete plans still fail closed.
- Every compiled whole-Shuto runtime exposes a deterministic asset identity.
  Its network-artifact hash covers the complete decoded network, including
  source, licence, limitation, and bounds metadata; its route-runtime hash
  additionally covers the exact `RoutePlan`, matcher corridor, decision zones,
  guidance, recovery candidates, and route-edge lengths. This is not a
  `KaidoProductRelease`: the hashes detect input drift but do not grant live-input
  authority or upgrade the graph's evidence status. Entry-transition and
  expressway replay checkpoints persist that identity and return to parked
  review instead of restoring runtime progress when either hash drifts.
- Selecting an exact route prepares its compiled assets, release-bound runtime,
  and reviewed JCT prompt projection off the main actor. **Start navigation**
  stays in `PREPARING` until all three match the full `RoutePlan`; start then
  reuses those values and attaches Core Location last. Changing or abandoning
  the route cancels its preparation. Driving UI reads one route-scoped prompt
  cache instead of recompiling the junction catalog during every map refresh.
- Graph search derives candidate wrong-turn rejoin shapes separately for every
  divergent directed edge. Each candidate is bound to the exact RoutePlan
  divergence occurrence and the observed wrong-turn edge, so one branch cannot
  borrow another branch's recovery. Compiler output alone remains unreleased.
  An exact foreground product release may bind one in-domain candidate into
  its runtime policy; all other deviations remain unavailable rather than
  executing an unreviewed movement. While that released recovery is active,
  the App keeps consuming serialized location observations, renders the
  remaining rejoin path, and returns to the unchanged RoutePlan at its bound
  target occurrence. `kaido-release
  inspect-live-coverage` emits the exact route-local missing guidance,
  candidate-recovery, and released-recovery counts without granting authority.
- Deterministic route playback is a Debug-only review tool. It compiles into
  Debug builds alone: the distributed app offers **Start navigation** and no
  second way to drive a route, and no shipped binary carries a playback entry,
  a launch-argument preview host, or an internal fixture screen.
  The playback covers surface access, entry, expressway travel,
  junction prompts, exit, surface egress, and completion. Entry and expressway
  playback follow the selected network geometry with a maximum 30-meter sample
  spacing. Observation timestamps, course, and the visible position all derive
  from the same 54 km/h reference trace before the explicit 20x presentation
  speed is applied. Every observation still runs through the route-aware
  matcher and actor-owned navigation session. Entry requires ordered, unique
  HIGH continuity on the selected directional entrance, and only an exact HIGH
  occurrence match can advance expressway progress.
- A deterministic whole-route accuracy suite retains exact occurrence,
  directed-edge, fraction, and route-distance truth before adding noise. Three
  representative whole-Shuto routes must keep wrong HIGH edge/occurrence
  commits at zero. The clean profile must meet the default accuracy floor; an
  eight-meter radial-drift profile must retain 100% HIGH occurrence precision,
  at least 20% HIGH coverage, and at most 15 meters p95 route-progress error.
- The Core Location adaptation boundary preserves course and speed uncertainty
  for release-enrolled runtimes. Uncertain course expands the heading model
  instead of being trusted like a precise bearing, and speed uncertainty widens
  travel-distance tolerance. Five foreground releases are bundled for
  deterministic startup. Any other exact selected route is content-addressed
  and admitted on device only when every one of its junction decisions is in
  the released guidance inventory; unmatched routes use Core Location only for
  the planning origin.
- Starting a drive opens the geographic driving map with a
  direction-following camera. The map separates traveled and remaining Shuto
  geometry, makes the next reviewed decision and its distance the dominant
  guidance, and keeps full-journey reference time, distance, and route-thread
  progress together in the lower instrument strip. The next reviewed movement
  may be shown before its decision-zone threshold, while junction insets and
  one-shot speech remain actor-triggered. Touch outranks the route: a pan,
  pinch, or rotate releases the following camera immediately rather than
  fighting the next position fix, and following resumes ten seconds after the
  last touch while the drive is active. The driver's own eye altitude is kept
  across that resume and reset only when the journey changes phase. An
  explicit free-browse/follow control remains available, and releasing through
  it is sticky until the driver asks for following back. A parked planning or
  review map keeps whatever frame the driver moved it to.
  Degraded, interrupted, and tunnel-estimated states
  return to north-up instead of inventing a route heading. In a tagged tunnel
  or covered segment, a live drive may move an amber estimated marker for at
  most 45 seconds from the last HIGH route-resolved fix using bounded speed as
  weak evidence. Its uncertainty halo grows continuously and the marker stops
  before the next released junction movement; the estimate cannot advance the
  matcher, NavigationSession, spoken guidance, exit handoff, or completion.
- With a route selected, the second map presentation is the whole-route track
  map: the entire selected route in one readable frame with every on-route
  IC, JCT, and PA always labeled, component routes visually distinct (the
  Bayshore leg of a C2 circuit renders in its own color), travel-direction
  chevrons that ride on the route colour instead of punching through it, and
  an explicit entrance mark. Panning and pinching it carry inertia and yield
  at the bounds instead of stopping dead. While driving, the current
  position renders above every other layer with a travel-direction indicator;
  nearby labels yield to it, and estimated positioning changes its appearance
  instead of hiding it. Without a selected route the whole-network line map
  remains the network presentation.
- During expressway travel the driver can switch between the normal geographic
  map and the whole-network line map. A junction inset appears only when an
  exact adjacent-edge movement matches a reviewed, snapshot-bound definition;
  route-label changes and nearest-JCT geometry cannot create one.
- The reviewed whole-network catalog contains 144 exact movements. It covers
  every divergent JCT on both C1 catalog loops, the Bayshore corridor in both
  directions, and the currently released radial and Yokohama approaches.
  Their Kaido vectors, branch or continuation instructions,
  Japanese sign targets, and route shields are operator-source-traceable. Each
  exact outgoing occurrence compiles into actor-owned screen and one-shot
  speech guidance. Lane indices remain explicitly unreleased, and transitions
  without sufficient approach-specific evidence remain silent.
  The remaining 23 candidate JCT movements stay preview-only until their
  approach-specific signs and legal continuations are released.
- Map facility labels for IC, JCT, and PA, route shields, and physical sign
  targets stay in Japanese. The default whole-network journey provides
  persisted Japanese, Simplified Chinese, and English interface controls plus
  an independently persisted guidance-voice language.

The previous C2 and K7 artifacts remain useful deterministic fixtures. They are
not the default product, do not constrain where a journey may start, and are not
special routing modes.
