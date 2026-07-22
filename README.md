# Kaido Routes

Kaido Routes is a route-first driving navigation concept. Instead of asking only
where a driver wants to arrive, it lets the driver choose which legal roads and
junction movements they want to experience, then executes that exact ordered
route safely.

The initial scope is the Shuto Expressway on iPhone, with Apple CarPlay as a
future product surface. The broader product may later cover other distinctive
Japanese driving roads. The project is not affiliated with or endorsed by
Metropolitan Expressway Company Limited.

## Current status

This repository currently defines product, domain, evidence, and test contracts.
It does not yet contain an app implementation or production road database.

The first implementation should prove six hard properties before expanding:

1. repeated road segments remain distinct ordered occurrences;
2. only legal directional junction movements can be authored and executed;
3. navigation stays honest when tunnel or stacked-road positioning is uncertain;
4. a current-location recommendation selects a compatible directional entrance,
   not merely the nearest IC name;
5. a deviation rejoins the active route plan instead of becoming a generic
   destination reroute;
6. Japanese, Simplified Chinese, and English guidance preserve the same physical
   sign target in both text and voice.

## Repository map

- [`docs/product/principles.md`](docs/product/principles.md): product promise and non-goals.
- [`docs/product/custom-route-builder.md`](docs/product/custom-route-builder.md): curated and expert route-authoring model.
- [`docs/architecture/domain-contract.md`](docs/architecture/domain-contract.md): stable route and road-network concepts.
- [`docs/architecture/journey-lifecycle.md`](docs/architecture/journey-lifecycle.md): surface access, entry recognition, recovery, and legal egress.
- [`docs/agents/context-architecture.md`](docs/agents/context-architecture.md): how coding agents should load and preserve context.
- [`docs/testing/e2e-strategy.md`](docs/testing/e2e-strategy.md): layered verification strategy.
- [`docs/testing/scenario-catalog.md`](docs/testing/scenario-catalog.md): behavior inventory and implementation order.
- [`docs/contributing/route-evidence.md`](docs/contributing/route-evidence.md): evidence gates for route data.
- [`e2e/`](e2e/README.md): portable, machine-readable behavior scenarios.

`research/` is a local, ignored notebook for source discovery and raw analysis.
It is deliberately not part of the public repository. Verified conclusions must
be rewritten into a tracked contract or evidence record with direct source links.

## Documentation audiences

Tracked English Markdown, JSON scenarios, and code are the authoritative source
for coding agents and open-source collaborators. Substantial project-owner
summaries may be rendered as self-contained Chinese HTML files on the Desktop.
Those HTML files are presentation snapshots rather than a second source of truth:
they should summarize and link to the tracked contracts, not define behavior that
the repository does not contain.

## Contract validation

The scenario validator has no third-party dependencies:

```sh
python3 scripts/validate_e2e.py
```

It checks the portable scenario envelope, route-occurrence identity, event
ordering, evidence references, and assertion references. Product code will add
its own language-specific test runner later.

## Safety

Kaido Routes is for lawful route planning, driving assistance, and road-culture
discovery. On-road signs, police directions, and traffic controls always take
priority over the app. The product must not reward speed, lap time, unsafe phone
interaction, or attempts to evade enforcement.
