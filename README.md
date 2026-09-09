# Kaido Routes

Kaido Routes is a route-first iPhone navigation product for the Shuto
Expressway. A driver chooses a route experience first, derives a
direction-valid entrance and exit from the current origin, optionally adds a
final destination, reviews the exact Shuto route and junction sequence, then
replays the journey from surface access through surface egress. Live navigation
starts only in the foreground and only when the selected route matches an exact
enrolled product release; that explicitly started session continues through
screen lock and temporary app switching.

The project is not affiliated with or endorsed by Metropolitan Expressway
Company Limited.

## Status

Active product delivery. There is a real iPhone target, a bundled
whole-Shuto network snapshot, and a physical-device deployment path.

Live navigation is deliberately narrow: it is admitted only for a route whose
every junction decision is covered by the released movement bindings. Broader
road coverage, CarPlay, tunnel dead-reckoning, and field qualification are not
claimed. Read the [accuracy boundary](docs/product/accuracy-boundary.md)
before trusting any guidance this product gives.

## What it does

- Opens on the whole Shuto network — all 26 current official route entries,
  directional IC facilities, JCTs, and PAs — not a sample route or an internal
  workbench.
- Leads with a named route-experience catalog: the C1 inner loop, the C2 inner
  loop closed by the Bayshore Route, the Bayshore westbound run that leaves
  the Bayshore at Daikoku to drive into Daikoku PA itself,
  the Yokohama-side Daikoku loop, and a scenic grand tour past Haneda, Minato
  Mirai, and the Yokohama Bay Bridge that also enters Daikoku PA. The driver picks a route, never designs
  an entrance: selecting one derives the direction-valid pairing, offers a 1–9
  lap count on loops, and shows a tariff band from dated operator evidence.
- Lets the driver add reachable PA stops from journey review, with actual
  directional access and return, one visit on the first pass, and saved-route
  restoration.
- Presents three maps for one selected route — the whole-network line map, the
  geographic MapKit map, and a whole-route track map that fits the entire route
  in one readable frame with every on-route IC, JCT, and PA labeled.
- Gates every drive behind one parked review pass that combines bounded surface
  access, the exact Shuto route, and the selected ending: return to the fixed
  start, finish at the directional exit, or continue to another place. A missing
  required surface leg blocks the start; exit-only journeys have no onward leg.
- Drives with a direction-following camera, a dominant next-decision prompt,
  junction insets, and preparation followed by final maneuver guidance drawn
  from reviewed exact JCT movements. Each stage speaks once; short approaches
  retain the final cue. Movements without approach-specific operator evidence stay silent.
  Touch outranks the route: a pan or pinch releases the camera immediately.
- Keeps facility labels, route shields, and sign targets in Japanese, with
  Japanese, Simplified Chinese, and English interface controls and an
  independently chosen guidance-voice language.

Full behaviour and the guarantee behind each capability:
[current capabilities](docs/product/current-capabilities.md).
Bundled data coverage: [network snapshot](docs/product/network-snapshot.md).

## Build and run

Requirements: Xcode 26 or newer, XcodeGen, iOS 18 or newer.

```sh
xcodegen generate
xcodebuild \
  -project KaidoRoutesApp.xcodeproj \
  -scheme KaidoRoutesApp \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

Debug builds accept preview launch arguments that open one surface directly; a
Release build ignores every one of them and opens the product home. They are
listed in [`CONTRIBUTING.md`](CONTRIBUTING.md).

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

Every pull request runs the `verify` workflow, which classifies the changed
paths, then runs the deterministic suites, critical App unit classes,
whole-Shuto App-model journeys, and route-selection, journey-ending, and
live-navigation UI checks in a single stable `xcodebuild` session. Documentation-only changes
finish after the lightweight classification. The `Verification gate` job
reports the single required result. The production joint-release validator
checks the retained K7 product artifact as a deterministic regression anchor;
it does not enroll the candidate whole-Shuto graph or grant live-navigation
authority.

Before a road test or release qualification, manually run the
`iOS qualification` workflow once `verify` is green. It runs the complete App
unit suite, a broader journey and compact accessibility matrix, and publishes a
validated unsigned Release archive. That artifact is not signed, installable
device evidence, TestFlight delivery, or an App Store submission.

## Documentation

| Area | Start here |
|---|---|
| Product | [principles](docs/product/principles.md) · [iPhone experience](docs/product/iphone-product-experience.md) · [current capabilities](docs/product/current-capabilities.md) · [accuracy boundary](docs/product/accuracy-boundary.md) |
| Architecture | [domain contract](docs/architecture/domain-contract.md) · [iOS navigation](docs/architecture/ios-navigation-architecture.md) · [journey lifecycle](docs/architecture/journey-lifecycle.md) |
| Testing | [E2E strategy](docs/testing/e2e-strategy.md) · [scenario catalog](docs/testing/scenario-catalog.md) · [device qualification](docs/testing/ios-physical-device-qualification.md) |
| Data and releases | [rebuilding the network](docs/contributing/rebuilding-the-network.md) · [route evidence](docs/contributing/route-evidence.md) · [product release authoring](docs/contributing/product-release-authoring.md) · [licensing](docs/contributing/licensing.md) |
| Working in this repo | [`CONTRIBUTING.md`](CONTRIBUTING.md) · [`AGENTS.md`](AGENTS.md) · [`SECURITY.md`](SECURITY.md) |

## Contributing

This is a maintainer-led project. Issues — wrong road data, behaviour that
contradicts the documented contract, a build failure from a clean checkout —
are the most useful contribution. Please open an issue and wait for a reply
before writing a feature. [`CONTRIBUTING.md`](CONTRIBUTING.md) has the setup,
verification, and pull-request rules.

## Licence and privacy

Project code is Apache-2.0. The complete database under
`data/route-atlas/osm-derived/` is an OpenStreetMap derivative distributed under
ODbL 1.0 with `© OpenStreetMap contributors` attribution. The root licence does
not relicense that database. [`DATA-LICENSES.md`](DATA-LICENSES.md) accompanies
the bundled machine-readable database with its attribution, source and direct
ODbL URI. The immutable bundled Route Atlas attribution
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

The distributed iPhone app includes the Apache-2.0 project licence and the
whole-Shuto ODbL data notice. Its information sheet exposes both documents,
the public privacy policy and version. Before a
signed archive is uploaded, validate the exact built app (or `.xcarchive`):

```bash
python3 scripts/validate_ios_release_bundle.py /path/to/KaidoRoutes.app
```

The validator rejects Debug identifiers, internal K7/C2/synthetic fixtures,
unreviewed bundle files, privacy-manifest drift, missing or unreviewed
background navigation modes,
missing localizations or licence bytes, non-iPhoneOS/non-ARM64 application
bundles, and app icons with transparent pixels.
