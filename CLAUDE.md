# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` is the authoritative agent instruction set for this repository. Read it first; this file only orients you and adds Claude-specific notes.

## What this repository is

Kaido Routes is a route-first navigation concept for the Shuto Expressway (iPhone, CarPlay later): the driver chooses the exact roads and junction movements to drive — including loops and repeated segments — and the app executes that ordered route. The repository is currently in the **product-contract and feasibility stage**: it contains contracts, scenarios, research, and a platform-light Swift core, but no iPhone/CarPlay app or production road database. Do not add app targets, provider integration, or dependencies unless the task explicitly asks.

Chat with the project owner in Chinese; write all tracked artifacts (docs, code, commits, PRs) in English.

## Commands

```sh
swift test                                      # build the package and run Swift Testing
swift run kaido-scenarios e2e/scenarios         # execute every portable assertion
python3 scripts/validate_e2e.py                  # validate the JSON contract envelope
```

Run all three after changing scenario semantics or the Swift core. The Python
validator has no third-party dependencies. Swift formatting is available through
`xcrun swift-format` in the Xcode toolchain.

## Architecture: a three-layer contract repo

1. **`docs/` — the contracts.** `docs/architecture/domain-contract.md` (route/network concepts), `docs/architecture/journey-lifecycle.md` (entry, recovery, egress), and `docs/architecture/ios-navigation-architecture.md` (Swift modules, provider boundaries, matching, and CarPlay) define the domain and architecture direction. `docs/product/` defines the promise and the route-builder model. `docs/testing/` defines the verification strategy, scenario catalog, and hard-gated engine bake-off. `docs/contributing/route-evidence.md` defines the evidence gates route data must pass before release.

2. **`e2e/` — the behavior spec, machine-readable.** Each `e2e/scenarios/kr-*.json` expresses one primary behavior in an implementation-independent envelope (`e2e/schema/scenario.schema.json`): a network snapshot + route plan (`given`), an ordered event stream (`when`), and categorized assertions (`then`). Scenario IDs (`KR-D01`, `KR-S04`, …) are stable — changing behavior keeps the ID or intentionally creates a new one. Layers: `DOMAIN`, `SIMULATION`, `IPHONE_UI`, `CARPLAY`, `FIELD`. CI scenarios must be deterministic and never call live operator/map/toll/traffic services. Road IDs must be visibly synthetic (`test.*`) unless a dated evidence fixture permits real data. Never weaken a scenario to make an implementation pass — surface the conflict instead.

3. **`research/` — private discovery notebook, gitignored.** Do not load or quote it by default, and never commit it or copy from it into tracked assets without rechecking the primary source. It contains provisional (Wikipedia/community-derived) notes alongside dated primary-source evidence records; `research/synthesis/verified-findings.md` supersedes stronger claims elsewhere in `research/sources/`.

4. **`Sources/` and `Tests/` — the feasibility core.** `KaidoDomain` owns value types, `KaidoRouting` owns strict validation and bounded selection, `KaidoNavigation` owns journey state transitions, and `KaidoScenarioRunner` maps portable JSON events and assertions onto those modules. The adapter must not switch on scenario IDs or silently skip unsupported subjects.

## Domain rules that are easy to get wrong

These come from verified road-operator behavior, not style preference (full list in AGENTS.md "Product invariants"):

- The road network is a **time-versioned directed multigraph**. Entrances/exits are one-way directional facilities; a shared place name implies nothing. JCTs are sets of legal directional movements (incoming approach → outgoing carriageway), never a single node — many movements that "should" exist don't.
- Route plans are **ordered occurrence sequences**: the same edge driven twice is two occurrences with identity `(plan, index)`. Never deduplicate by entity ID or coordinate.
- **Actual planned distance ≠ tariff distance.** Shuto tolls use the shortest all-Shuto path between entry and exit regardless of the driven route. Keep toll quotes as dated evidence, and keep `ACTIVE`/`PROPOSED`/`RETIRED` tariff and topology versions separate (an October 2026 toll revision is proposed, not confirmed).
- `NO_KNOWN_CONFLICT` ≠ `REALTIME_UNCONFIRMED` ≠ "open". Tunnel/stacked-road positioning must expose confidence and degraded mode.
- Never commit Shuto Expressway maps/images/logos, mew-ti or JARTIC payloads, raw third-party articles or screenshots, or OSM-derived databases without an ODbL plan.
- No speed, lap-time, racing, or enforcement-evasion mechanics anywhere, including copy and examples.
