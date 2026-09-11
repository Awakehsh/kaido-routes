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
  whole-network inventory resolves all 163 exact movement bindings. They
  authorize only the
  reviewed branch or continuation and approach-specific Japanese sign target.
  They do not copy operator artwork or imply unreleased lane numbers.
- Current traffic, temporary closures, toll quotes, and PA operating status are
  `REALTIME_UNCONFIRMED` until a current provider response exists.
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
  evidence takes over only near the exact directional ramp. A valid device fix
  that has not joined the surface route is labeled as waiting to join the route,
  not as weak positioning, and a coarse but on-route fix is still the position;
  genuinely stale positioning keeps the separate degraded warning and speaks it
  at most once per minute.
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
