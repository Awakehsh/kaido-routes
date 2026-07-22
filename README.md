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

This repository defines product, domain, evidence, and test contracts plus a
pure Swift feasibility core. It does not yet contain an iPhone/CarPlay app,
production road database, or released provider integration. It includes a
bounded MapKit feasibility adapter, an offline directed-road graph inspector,
surface-routing hard gates, and an explicit local live-probe command; no live
MapKit call runs in deterministic tests.

The feasibility core currently executes portable scenarios for fourteen hard
properties that must remain proven as the product expands:

1. repeated road segments remain distinct ordered occurrences;
2. only legal directional junction movements can be authored and executed;
3. navigation stays honest when tunnel or stacked-road positioning is uncertain,
   keeps route-candidate resolution separate from raw fix quality, and requires a
   consistent post-gap window before resuming an exact occurrence;
4. a current-location recommendation selects a compatible directional entrance
   approach that is available at the predicted entry time, not merely the
   nearest IC name;
5. a deviation rejoins the active route plan instead of becoming a generic
   destination reroute;
6. Japanese, Simplified Chinese, and English guidance preserve the same physical
   sign target in both text and voice.
7. PA visits require an exact directional access-and-return path; operational
   closures skip a whole optional PA subgraph but block a required occurrence.
8. adding another reviewed lap copies values into fresh, contiguous occurrences
   instead of aliasing the first traversal;
9. a reviewed circuit template must contain every required route edge and
   boundary movement in order, including any separately named route used to
   close the circuit;
10. every strict route occurrence is classified against an allowed toll-domain
    policy, and external or unknown domains fail closed.
11. tariff selection requires exactly one `ACTIVE` version; proposed and retired
    versions remain visible evidence but cannot supply the payable amount.
12. deterministic guidance anchors emit once per occurrence, suppress duplicate
    location triggers, and remain independently eligible on a later lap.
13. a newly known blocking restriction during a drive activates a released
    rejoin to the existing RoutePlan without abrupt guidance or moving-time edits.
14. a CarPlay disconnect returns presentation to iPhone while the shared route
    occurrence and occurrence-scoped prompt ledger continue unchanged.

## Repository map

- [`docs/product/principles.md`](docs/product/principles.md): product promise and non-goals.
- [`docs/product/custom-route-builder.md`](docs/product/custom-route-builder.md): curated and expert route-authoring model.
- [`docs/architecture/domain-contract.md`](docs/architecture/domain-contract.md): stable route and road-network concepts.
- [`docs/architecture/journey-lifecycle.md`](docs/architecture/journey-lifecycle.md): surface access, entry recognition, recovery, and legal egress.
- [`docs/architecture/ios-navigation-architecture.md`](docs/architecture/ios-navigation-architecture.md): accepted Swift, CarPlay, routing, matching, and provider boundaries.
- [`docs/agents/context-architecture.md`](docs/agents/context-architecture.md): how coding agents should load and preserve context.
- [`docs/testing/e2e-strategy.md`](docs/testing/e2e-strategy.md): layered verification strategy.
- [`docs/testing/scenario-catalog.md`](docs/testing/scenario-catalog.md): behavior inventory and implementation order.
- [`docs/testing/navigation-engine-bakeoff.md`](docs/testing/navigation-engine-bakeoff.md): hard-gated comparison plan for surface routers and map matchers.
- [`docs/contributing/route-evidence.md`](docs/contributing/route-evidence.md): evidence gates for route data.
- [`docs/contributing/licensing.md`](docs/contributing/licensing.md): Apache-2.0 and third-party material boundaries.
- [`e2e/`](e2e/README.md): portable, machine-readable behavior scenarios.
- [`benchmarks/surface-routing/`](benchmarks/surface-routing/README.md): directional entrance fixtures and provider hard gates.
- [`Sources/`](Sources): platform-light Swift domain, routing, navigation, and scenario-adapter modules.
- [`Tests/`](Tests): Swift Testing suites that execute the portable scenarios.

`research/` is a local, ignored notebook for source discovery and raw analysis.
It is deliberately not part of the public repository. Verified conclusions must
be rewritten into a tracked contract or evidence record with direct source links.

## Documentation audiences

Tracked English Markdown, JSON scenarios, and code are the authoritative source
for coding agents and open-source contributors. Substantial project-owner
summaries may be rendered as self-contained Chinese HTML files on the Desktop.
Those HTML files are presentation snapshots rather than a second source of truth:
they should summarize and link to the tracked contracts, not define behavior that
the repository does not contain.

## Build and contract validation

The package uses only the Swift toolchain and Foundation. Run the executable
scenario suite and the independent schema validator:

```sh
swift test
swift run kaido-scenarios e2e/scenarios
python3 scripts/validate_e2e.py
```

`swift test` executes the domain and simulation semantics in process. The CLI
prints a result for every scenario and assertion. The Python validator remains
an independent L0 check for the portable envelope, route-occurrence identity,
event ordering, evidence references, and assertion references.

## Safety

Kaido Routes is for lawful route planning, driving assistance, and road-culture
discovery. On-road signs, police directions, and traffic controls always take
priority over the app. The product must not reward speed, lap time, unsafe phone
interaction, or attempts to evade enforcement.

## License

Kaido Routes is open-source software licensed under the
[Apache License 2.0](LICENSE). The licence permits commercial and noncommercial
use, modification, and distribution under its terms, including its notice and
patent provisions.

Separately identified third-party software, data, and assets remain under their
own terms. In particular, the project licence does not grant rights to operator
maps, traffic-service payloads, or an OSM-derived database.
