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
Swift CLI executes the events against `KaidoDomain`, `KaidoRouting`,
`KaidoNavigation`, and the platform-light `KaidoPresentation` projector, then
evaluates every semantic assertion. `swift test` runs the same corpus through
Swift Testing without a simulator or live service.

Matcher lifecycle scenarios use `MATCHER_SESSION_STARTED`,
`MATCHER_OBSERVATION_RECEIVED`, and `MATCHER_SESSION_RESET`. Their
`matcher_corridor` input is a synthetic, snapshot-bound set of directed edges,
legal successors, and exact RoutePlan occurrence bindings. The runner streams each
observation through the same public `RouteMatcherSession` used by the replay
CLI, then projects its confidence and occurrence into `NavigationEngine`. This
keeps matcher-to-navigation commit policy executable without importing Core
Location or a UI framework into the portable core.

Route-editor scenarios use `ROUTE_EDITOR_STARTED`,
`ROUTE_EDITOR_CHOICE_SELECTED`, `ROUTE_EDITOR_LAP_DUPLICATION_REQUESTED`,
`ROUTE_EDITOR_UNDO_REQUESTED`, and `ROUTE_EDITOR_COMPILE_REQUESTED`. Their
reviewed catalog is bound to the same network snapshot and names exact
directional entrances, incoming approaches, junction complexes, movements,
outgoing edges, exits, and optional closed lap templates. KR-U01 proves that a
future choice and moving-time edit cannot mutate the draft, while each accepted
choice creates fresh occurrences and an explicit exit produces one RoutePlan.
KR-U02 proves that only an already authored template-matched closed sequence
becomes a lap candidate, duplication creates fresh occurrence values, and one
undo removes the whole copied lap. The portable runner does not claim that a
SwiftUI editor has rendered.

Presentation scenarios project the same current occurrence and structured
occurrence-scoped guidance frame into semantic phone, CarPlay, and voice values.
The frame carries prompt and anchor identity, stage, distance, decision point,
maneuver, lane preparation, Japanese sign target, route shields, and localized
content. KR-S17 additionally streams fresh route-resolved distance observations
through the pure `GuidanceFramePlanner`, `NavigationEngine` prompt ledger, and
the projector. It proves most-actionable anchor selection, no stage regression,
stale-progress rejection, and one-shot `voice.should_speak`. KR-S18 supplies
Swift matcher observations and a reviewed DecisionZone entry, then proves that
HIGH occurrence plus along-edge progress becomes route-corridor distance while
the separate lateral residual is ignored. Neither scenario claims that
production geometry, zone calibration, SwiftUI, `CPMapTemplate`, accessibility,
audio, or hardware rendering has run; those later layers must consume the same
semantics without inferring them.

Release scenarios use `NAVIGATION_RELEASE_BUNDLE_VALIDATED` for in-memory
runtime coherence and `NAVIGATION_RELEASE_ARTIFACT_VALIDATED` for the versioned
distribution boundary. KR-D25 encodes and decodes the artifact, checks exact
role-matched evidence coverage—including the `RUNTIME_POLICY` asset that binds
entry transition, safe rejoin, and legal egress—and then reuses the bundle gate.
Its synthetic source and `RELEASED` values test fail-closed mechanics only.
`PRODUCT_RELEASE_ARTIFACT_VALIDATED` is the joint product boundary. KR-D26 first
proves that its navigation and Route Atlas artifacts pass independently, then
blocks their combination because one editor incoming approach is absent from
released atlas topology. It reports the exact missing entity ID; it does not
promote either synthetic fixture into real-road authority.
`PRODUCT_NAVIGATION_RUNTIME_CREATED` then proves the failed joint artifact
cannot expose a partial runtime release identity.

Scenario IDs are stable. File names may add descriptive words, but changing a
scenario's behavior should retain its ID or create a new version intentionally.

Real operator data is allowed only as a small, dated evidence fixture with
direct source links. All other road IDs must be visibly synthetic.
