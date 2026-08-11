# Kaido Routes

Kaido Routes is a route-first iPhone navigation product for the Shuto
Expressway. A driver chooses a route experience first, derives a
direction-valid entrance and exit from the current origin, optionally adds a
final destination, reviews the exact Shuto route and junction sequence, then
replays the journey from surface access through surface egress. Live navigation
remains fail-closed until an exact authority-bearing product is enrolled.

The project is not affiliated with or endorsed by Metropolitan Expressway
Company Limited.

## Product

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
  alternatives one disclosure away, offers a 1–3 lap count on loops, plans
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
- The bundled whole-Shuto graph remains a candidate asset rather than a
  validated `KaidoProductRelease`. The complete journey is available as a
  clearly labeled replay. **Start navigation** fails closed with
  `WHOLE_SHUTO_NAVIGATION_RELEASE_REQUIRED` until one exact joint product
  release and its released surface provider/field evidence are enrolled.
- Every compiled whole-Shuto runtime exposes a deterministic asset identity.
  Its network-artifact hash covers the complete decoded network, including
  source, licence, limitation, and bounds metadata; its route-runtime hash
  additionally covers the exact `RoutePlan`, matcher corridor, decision zones,
  guidance, recovery candidates, and route-edge lengths. This is not a
  `KaidoProductRelease`: the hashes detect input drift but do not grant live-input
  authority or upgrade the graph's evidence status. Entry-transition and
  expressway replay checkpoints persist that identity and return to parked
  review instead of restoring runtime progress when either hash drifts.
- Graph search may derive candidate wrong-turn rejoin shapes for integrity and
  future review, but every such path remains unreleased. A replayed deviation is
  therefore unavailable/route-interrupted rather than executing an unreviewed
  movement.
- The driving simulation covers surface access, entry, expressway travel,
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
  travel-distance tolerance. The default candidate product currently uses
  foreground Core Location for planning origin only, not live navigation.
- Starting the simulation opens the geographic driving map with a
  direction-following camera. The map separates traveled and remaining Shuto
  geometry, makes the next reviewed decision and its distance the dominant
  guidance, and keeps full-journey reference time, distance, and route-thread
  progress together in the lower instrument strip. The next reviewed movement
  may be shown before its decision-zone threshold, while junction insets and
  one-shot speech remain actor-triggered. An explicit free-browse/follow
  control remains available. Degraded, interrupted, and tunnel-estimated states
  return to north-up instead of inventing a route heading.
- With a route selected, the second map presentation is the whole-route track
  map: the entire selected route in one readable frame with every on-route
  IC, JCT, and PA always labeled, component routes visually distinct (the
  Bayshore leg of a C2 circuit renders in its own color), travel-direction
  chevrons, and an explicit entrance mark. While driving, the current
  position renders above every other layer with a travel-direction indicator;
  nearby labels yield to it, and estimated positioning changes its appearance
  instead of hiding it. Without a selected route the whole-network line map
  remains the network presentation.
- During expressway travel the driver can switch between the normal geographic
  map and the whole-network line map. A junction inset appears only when an
  exact adjacent-edge movement matches a reviewed, snapshot-bound definition;
  route-label changes and nearest-JCT geometry cannot create one.
- The reviewed whole-network catalog contains 20 exact movements. It covers
  every divergent JCT on the C1 inner catalog loop and on the Bayshore corridor
  in both directions. Their Kaido vectors, branch or continuation instructions,
  Japanese sign targets, and route shields are operator-source-traceable. Each
  exact outgoing occurrence compiles into actor-owned screen and one-shot
  speech guidance. Lane indices remain explicitly unreleased, and transitions
  without sufficient approach-specific evidence remain silent.
- Map facility labels for IC, JCT, and PA, route shields, and physical sign
  targets stay in Japanese. The default whole-network journey provides
  persisted Japanese, Simplified Chinese, and English interface controls plus
  an independently persisted guidance-voice language.

The previous C2 and K7 artifacts remain useful deterministic fixtures. They are
not the default product, do not constrain where a journey may start, and are not
special routing modes.

## Current network snapshot

The bundled `2026-08-04` OSM geometry snapshot is joined to operator facts
checked on `2026-07-29`:

| Item | Bundled coverage |
|---|---:|
| Official route entries | 26 |
| Directed graph edges | 24,299 |
| IC names | 151 |
| Usable IC geometry matches | 148 / 148 |
| Official JCT matches | 39 / 39 |
| PA entries | 19 |

The three IC names without routable geometry belong to the officially
unavailable, long-term-closed Yaesu Route. They remain visible as unavailable
facts and are never admitted to route search.

Operator pages establish route names, IC direction availability, the current
JCT directory, and the PA directory. The pinned OpenStreetMap extract supplies
candidate geometry and topology. Operator maps, junction images, and logos are
not copied into the repository.

## Accuracy boundary

The product distinguishes what is known from what is still unconfirmed:

- Static operator facility facts and the exact source dates are bundled.
- OSM geometry and connectivity are candidate data under ODbL 1.0; they are not
  operator-authored lane or stacked-road authority.
- The line map and junction inset are Kaido-generated vectors. Every JCT keeps
  the current official detail-image URL and content hash for audit. Reviewed
  movement guidance must also match the exact network snapshot, adjacent edge
  IDs, shared JCT node, direction, and official content hash. The 20 admitted
  definitions cover the C1 inner catalog loop and both directions of the
  Bayshore corridor at divergent JCTs; they authorize only the reviewed branch
  or continuation and approach-specific Japanese sign target. They do not copy
  operator artwork or imply unreleased lane numbers.
- Current traffic, temporary closures, toll quotes, and PA operating status are
  `REALTIME_UNCONFIRMED` until a current provider response exists.
- MapKit surface access and egress cannot author, optimize, replace, or recover
  the Shuto `RoutePlan`.
- The default App's foreground Core Location lifecycle supplies the planning
  origin; it refuses to start candidate whole-Shuto navigation. The clearly
  labeled replay exercises the route-aware matcher and actor-owned reducer but
  grants no road, tunnel, field, acoustic, or CarPlay qualification. Spoken turn
  guidance still covers reviewed junction movements only.

## Build and run

Requirements:

- Xcode 26 or newer
- XcodeGen
- iOS 18 or newer

```sh
xcodegen generate
xcodebuild \
  -project KaidoRoutesApp.xcodeproj \
  -scheme KaidoRoutesApp \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

Useful visual launch arguments:

- `-WHOLE-SHUTO-TRACK-MAP-PREVIEW`
- `-WHOLE-SHUTO-TRACK-MAP-NAVIGATION-PREVIEW`
- `-WHOLE-SHUTO-TRACK-MAP-LINEAR-PREVIEW`
- `-WHOLE-SHUTO-NETWORK-BROWSE-PREVIEW`
- `-WHOLE-SHUTO-SEARCH-PREVIEW`
- `-WHOLE-SHUTO-SURFACE-FAILURE-PREVIEW`
- `-WHOLE-SHUTO-ROUTE-PREVIEW`
- `-WHOLE-SHUTO-NAVIGATION-PREVIEW`
- `-WHOLE-SHUTO-ARRIVAL-PREVIEW`
- `-WHOLE-SHUTO-JUNCTION-PREVIEW`
- `-WHOLE-SHUTO-JUNCTION-NAVIGATION-PREVIEW`
- `-WHOLE-SHUTO-KASAI-JUNCTION-PREVIEW`
- `-WHOLE-SHUTO-KASAI-JUNCTION-NAVIGATION-PREVIEW`
- `-WHOLE-SHUTO-SHINONOME-EASTBOUND-JUNCTION-NAVIGATION-PREVIEW`
- `-WHOLE-SHUTO-SHINONOME-WESTBOUND-JUNCTION-NAVIGATION-PREVIEW`
- `-WHOLE-SHUTO-TATSUMI-EASTBOUND-JUNCTION-NAVIGATION-PREVIEW`
- `-WHOLE-SHUTO-TATSUMI-WESTBOUND-JUNCTION-NAVIGATION-PREVIEW`
- `-C2-FULL-NAVIGATION-DEMO` for the retained C2 deterministic fixture
- `-K7-OPERATIONAL-E2E` for the retained K7 release fixture

## Verify

```sh
swift test
swift run kaido-scenarios e2e/scenarios
python3 scripts/validate_e2e.py
python3 -m unittest discover -s scripts/tests
swift run kaido-release validate-product \
  --artifact \
  data/product/releases/k7-northwest-up-aoba-to-kohoku-product-release.json
```

The focused whole-network tests decode the distributed database, validate
coverage and identity, plan a cross-network IC-to-IC route, and rank entrances
and exits for arbitrary Tokyo-to-Yokohama coordinates.

The verification workflow also runs the complete Python validator regression
suite and the production joint-release validator against the retained K7
product artifact. K7 remains a deterministic regression anchor. Neither gate
enrolls the candidate whole-Shuto graph, refreshes its evidence, or grants it
live-navigation authority.

## Rebuild the network

The builders use Beautiful Soup and pinned pyosmium:

```sh
python3 -m venv /tmp/kaido-shuto-osmium
/tmp/kaido-shuto-osmium/bin/pip install \
  beautifulsoup4 \
  osmium==4.3.1
/tmp/kaido-shuto-osmium/bin/python scripts/build_shuto_official_catalog.py \
  --checked-at 2026-07-29 \
  --output data/network/shuto-official-catalog-20260729.json
/tmp/kaido-shuto-osmium/bin/python scripts/build_shuto_network.py \
  --input /path/to/kanto-260804.osm.pbf \
  --official-catalog data/network/shuto-official-catalog-20260729.json \
  --facility-candidate-review \
    data/network/shuto-facility-candidate-review-20260810.json \
  --output data/route-atlas/osm-derived/shuto-whole-network-20260804.json \
  --expected-input-sha256 \
    a6835449bd93144cf6724e9682d691494a1b6ead5aeb4f42f1b5bf2f26e6412c \
  --source-uri \
    https://download.geofabrik.de/asia/japan/kanto-260804.osm.pbf
```

The builder selects the 26 Shuto route relations, adds only connected motorway
links, respects directed access, excludes abandoned and unavailable roads,
matches every usable official IC and JCT, and fails on source or coverage drift.

## Licence and privacy

Project code is Apache-2.0. The complete database under
`data/route-atlas/osm-derived/` is an OpenStreetMap derivative distributed under
ODbL 1.0 with `© OpenStreetMap contributors` attribution. The root licence does
not relicense that database. The immutable bundled Route Atlas attribution
catalog remains bound to the retained K7 review bytes. The default
`shuto-whole-network-20260804` surface independently validates the decoded
snapshot's OSM attribution and ODbL metadata, then exposes fixed HTTPS source
and licence links adjacent to the map; it does not rewrite or inherit the K7
review.

Raw coordinates and personal field traces must not be committed. See
[PRIVACY.md](PRIVACY.md), the
[whole-Shuto OSM distribution notes](data/route-atlas/osm-derived/shuto-whole-network-20260804.README.md),
the retained [K7 OSM review notes](data/route-atlas/osm-derived/README.md), and
[the iOS architecture contract](docs/architecture/ios-navigation-architecture.md).
