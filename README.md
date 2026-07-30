# Kaido Routes

Kaido Routes is a route-first iPhone navigation product for the Shuto
Expressway. A driver can start from any MapKit-resolvable place, choose a final
destination, review the exact directional entrance, Shuto route, junction
sequence, and exit, then run the complete journey from surface access through
surface egress.

The project is not affiliated with or endorsed by Metropolitan Expressway
Company Limited.

## Product

The default app opens on the whole Shuto network, not a sample route or an
internal review workbench.

- The full-network line map shows all 26 current official route entries,
  directional IC facilities, JCTs, and PAs.
- The geographic map shows the selected route on MapKit and keeps the exact
  Kaido-owned Shuto path separate from bounded surface access and egress.
- Routing ranks compatible entrances and exits for arbitrary origin and
  destination coordinates, then searches the directed whole-network graph.
- Route occurrences remain ordered and distinct. Directed links represent
  candidate entrances, exits, and junction connectivity; official facility
  facts remain distinguishable from OSM topology.
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
- Live Core Location course and speed uncertainty now reach the matcher.
  Uncertain course expands the heading model instead of being trusted like a
  precise bearing, and speed uncertainty widens travel-distance tolerance.
- Starting the simulation opens the geographic driving map with a
  direction-following camera. The map separates traveled and remaining Shuto
  geometry, exposes total remaining route distance and the next reviewed JCT
  distance, and provides an explicit free-browse/follow control. Degraded,
  interrupted, and tunnel-estimated states return to north-up instead of
  inventing a route heading.
- During expressway travel the driver can switch between the normal geographic
  map and the whole-network line map. A junction inset appears only when an
  exact adjacent-edge movement matches a reviewed, snapshot-bound definition;
  route-label changes and nearest-JCT geometry cannot create one.
- The reviewed whole-network movements are both Bayshore Route approaches to
  Route 10 inbound at Shinonome JCT, both Bayshore Route approaches to Route 9
  inbound at Tatsumi JCT, Bayshore Route westbound to C2 inner at Kasai JCT,
  and Bayshore Route westbound to C2 outer at Oi JCT. Their Kaido vectors,
  branch instructions, Japanese sign targets, and route shields are
  operator-source-traceable. Each exact outgoing occurrence compiles into
  actor-owned screen and one-shot speech guidance. Lane indices remain
  explicitly unreleased, and unreviewed transitions remain silent.
- Map facility labels for IC, JCT, and PA, route shields, and physical sign
  targets stay in Japanese. The default whole-network journey provides
  persisted Japanese, Simplified Chinese, and English interface controls plus
  an independently persisted guidance-voice language.

The previous C2 and K7 artifacts remain useful deterministic fixtures. They are
not the default product, do not constrain where a journey may start, and are not
special routing modes.

## Current network snapshot

The bundled `2026-07-28` OSM geometry snapshot is joined to operator facts
checked on `2026-07-29`:

| Item | Bundled coverage |
|---|---:|
| Official route entries | 26 |
| Directed graph edges | 24,291 |
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
  IDs, shared JCT node, direction, and official content hash. The Shinonome,
  Tatsumi, Kasai, and Oi definitions authorize only their reviewed left or
  right branch plus approach-specific Japanese sign target; they do not copy
  operator artwork or imply unreleased lane numbers.
- Current traffic, temporary closures, toll quotes, and PA operating status are
  `REALTIME_UNCONFIRMED` until a current provider response exists.
- MapKit surface access and egress cannot author, optimize, replace, or recover
  the Shuto `RoutePlan`.
- The shipped driving flow is a clearly labeled simulation. Device launch and
  deterministic Core Location injection do not attach a live location manager
  or claim tunnel, field, acoustic, or CarPlay qualification.

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
```

The focused whole-network tests decode the distributed database, validate
coverage and identity, plan a cross-network IC-to-IC route, and rank entrances
and exits for arbitrary Tokyo-to-Yokohama coordinates.

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
  --input /path/to/kanto-260728.osm.pbf \
  --official-catalog data/network/shuto-official-catalog-20260729.json \
  --output data/route-atlas/osm-derived/shuto-whole-network-20260728.json \
  --expected-input-sha256 \
    4ebc009018467c3d9c4cdc5f1817a7d2bfeab243af0889700667f6be99fe4e52 \
  --source-uri \
    https://download.geofabrik.de/asia/japan/kanto-260728.osm.pbf
```

The builder selects the 26 Shuto route relations, adds only connected motorway
links, respects directed access, excludes abandoned and unavailable roads,
matches every usable official IC and JCT, and fails on source or coverage drift.

## Licence and privacy

Project code is Apache-2.0. The complete database under
`data/route-atlas/osm-derived/` is an OpenStreetMap derivative distributed under
ODbL 1.0 with `© OpenStreetMap contributors` attribution. The root licence does
not relicense that database.

Raw coordinates and personal field traces must not be committed. See
[PRIVACY.md](PRIVACY.md), [OSM-derived data notes](data/route-atlas/osm-derived/README.md),
and [the iOS architecture contract](docs/architecture/ios-navigation-architecture.md).
