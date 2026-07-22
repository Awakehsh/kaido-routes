# Portable E2E scenarios

This directory stores implementation-independent product scenarios.

```text
e2e/
├── schema/scenario.schema.json
└── scenarios/*.json
```

The JSON Schema documents the envelope. The dependency-free validator also
checks cross-field rules that are awkward to express in JSON Schema, including
contiguous occurrence indexes, unique event IDs, event ordering, and assertion
references. Route occurrences may also carry `parking_area_id` and
`toll_domain_id`; both are explicit domain data rather than labels inferred by
the runner.

Run:

```sh
python3 scripts/validate_e2e.py
swift run kaido-scenarios e2e/scenarios
swift test
```

The Python command validates the portable envelope and cross-field rules. The
Swift CLI executes the events against `KaidoDomain`, `KaidoRouting`, and
`KaidoNavigation`, then evaluates every semantic assertion. `swift test` runs
the same corpus through Swift Testing without a simulator or live service.

Matcher lifecycle scenarios use `MATCHER_SESSION_STARTED`,
`MATCHER_OBSERVATION_RECEIVED`, and `MATCHER_SESSION_RESET`. Their
`matcher_corridor` input is a synthetic, snapshot-bound set of directed edges,
legal successors, and RoutePlan occurrence bindings. The runner streams each
observation through the same public `RouteMatcherSession` used by the replay
CLI, then projects its confidence and occurrence into `NavigationEngine`. This
keeps matcher-to-navigation commit policy executable without importing Core
Location or a UI framework into the portable core.

Scenario IDs are stable. File names may add descriptive words, but changing a
scenario's behavior should retain its ID or create a new version intentionally.

Real operator data is allowed only as a small, dated evidence fixture with
direct source links. All other road IDs must be visibly synthetic.
