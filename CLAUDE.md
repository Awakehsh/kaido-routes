# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` is the authoritative agent instruction set for this repository. Read it first; this file only orients you and adds Claude-specific notes.

## What this repository is

Kaido Routes is a route-first navigation product for the Shuto Expressway (iPhone now, CarPlay later): the driver chooses the exact route experience to drive — including loops, repeated segments, and radial-to-loop joins — and the app helps reach its directional entrance, execute the ordered route, and leave through a planned exit. The primary audience and the route-first home model are defined in AGENTS.md "Product direction and audience"; the audience motivation never appears in user-facing copy.

The repository is in **active product delivery**: contracts (`docs/`), machine-readable scenarios (`e2e/`), platform-light Swift modules (`Sources/`), a real iPhone app target (`KaidoRoutesApp`, generated with XcodeGen), and a bundled whole-Shuto network snapshot joined to dated operator facts. The shipped driving flow runs on real device positions, with an explicitly labeled replay preview beside it; no live-traffic, toll, or field-qualified navigation authority is claimed, and spoken turn guidance still covers reviewed junction movements only. Do not describe the repository as feasibility-only, and do not treat the retained C2/K7 fixtures as delivery tracks.

Chat with the project owner in Chinese; write all tracked artifacts (docs, code, commits, PRs) in English.

## Commands

```sh
swift test                                      # build the package and run Swift Testing
swift run kaido-scenarios e2e/scenarios         # execute every portable assertion
python3 scripts/validate_e2e.py                 # validate the JSON contract envelope
xcodegen generate                               # regenerate the app project
xcodebuild -project KaidoRoutesApp.xcodeproj \
  -scheme KaidoRoutesApp -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Run the first three after changing scenario semantics or the Swift core; build the app after app-facing changes. The Python validator has no third-party dependencies. Swift formatting is available through `xcrun swift-format` in the Xcode toolchain.

## Architecture: contracts, scenarios, core, app

1. **`docs/` — the contracts.** `docs/architecture/domain-contract.md` (route/network concepts), `docs/architecture/journey-lifecycle.md` (entry, recovery, egress), and `docs/architecture/ios-navigation-architecture.md` (Swift modules, provider boundaries, matching, and CarPlay) define the domain and architecture direction. `docs/product/principles.md` and `docs/product/iphone-product-experience.md` define the promise, the route-first home, entrance recommendation, and the two map presentations. `docs/testing/` defines the verification strategy, scenario catalog, and hard-gated engine bake-off. `docs/contributing/route-evidence.md` defines the evidence gates for navigation-grade guidance claims.

2. **`e2e/` — the behavior spec, machine-readable.** Each `e2e/scenarios/kr-*.json` expresses one primary behavior in an implementation-independent envelope (`e2e/schema/scenario.schema.json`): a network snapshot + route plan (`given`), an ordered event stream (`when`), and categorized assertions (`then`). Scenario IDs (`KR-D01`, `KR-S04`, …) are stable — changing behavior keeps the ID or intentionally creates a new one. Layers: `DOMAIN`, `SIMULATION`, `IPHONE_UI`, `CARPLAY`, `FIELD`. CI scenarios must be deterministic and never call live operator/map/toll/traffic services. Road IDs must be visibly synthetic (`test.*`) unless a dated evidence fixture permits real data. Never weaken a scenario to make an implementation pass — surface the conflict instead.

3. **`research/` — private discovery notebook, gitignored.** Do not load or quote it by default, and never commit it or copy from it into tracked assets without rechecking the primary source. It contains provisional (Wikipedia/community-derived) notes alongside dated primary-source evidence records; `research/synthesis/verified-findings.md` supersedes stronger claims elsewhere in `research/sources/`.

4. **`Sources/`, `Tests/`, and the app.** `KaidoDomain` owns value types, `KaidoRouting` owns strict validation and bounded selection, `KaidoNavigation` owns journey state transitions, `KaidoSurfaceRouting` owns the bounded surface access/egress boundary, `KaidoPresentation` owns projection models, `KaidoAppleAdapters` wraps platform services, and `KaidoScenarioRunner` maps portable JSON events and assertions onto those modules. The adapter must not switch on scenario IDs or silently skip unsupported subjects. CLI tools (`KaidoScenariosCLI`, `KaidoAtlasCLI`, `KaidoReleaseCLI`, …) drive validation and data workflows.

## Domain rules that are easy to get wrong

These come from verified road-operator behavior, not style preference (full list in AGENTS.md "Product invariants"):

- The road network is a **time-versioned directed multigraph**. Entrances/exits are one-way directional facilities; a shared place name implies nothing. JCTs are sets of legal directional movements (incoming approach → outgoing carriageway), never a single node — many movements that "should" exist don't.
- Route plans are **ordered occurrence sequences**: the same edge driven twice is two occurrences with identity `(plan, index)`. Never deduplicate by entity ID or coordinate.
- **Actual planned distance ≠ tariff distance.** Shuto tolls use the shortest all-Shuto path between entry and exit regardless of the driven route — laps never raise the quoted band; the entrance/exit pairing sets it. Keep toll quotes as dated evidence, and keep `ACTIVE`/`PROPOSED`/`RETIRED` tariff and topology versions separate (an October 2026 toll revision is proposed, not confirmed).
- `NO_KNOWN_CONFLICT` ≠ `REALTIME_UNCONFIRMED` ≠ "open". Tunnel/stacked-road positioning must expose confidence and degraded mode.
- Planning and selection over the bundled whole-network snapshot rely on the snapshot's coverage and identity gates. Per-route evidence gates apply to navigation-grade guidance claims (reviewed movements, junction insets, speech), not to drawing or selecting routes.
- Never commit Shuto Expressway maps/images/logos, mew-ti or JARTIC payloads, raw third-party articles or screenshots, or OSM-derived databases without an ODbL plan.
- No speed, lap-time, racing, or enforcement-evasion mechanics anywhere, including copy and examples. Stylized track-map presentation of a route is fine; competitive or performance framing is not.
