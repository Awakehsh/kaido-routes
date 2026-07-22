# E2E strategy

## Goal

Treat product behavior as a portable contract before choosing the app stack.
One scenario should be reusable across a pure domain engine, a deterministic
navigation simulator, iPhone UI tests, CarPlay tests, and selected field tests.

"E2E" therefore means end-to-end product intent, not only a fragile sequence of
screen taps.

## Test layers

| Layer | Purpose | Environment | Live network? |
|---|---|---|---|
| L0 Contract | Validate scenario shape, IDs, evidence, and occurrence order | Standard-library validator | No |
| L1 Domain | Compile routes, validate movement legality, preserve occurrences, compute state | Pure in-process tests | No |
| L2 Simulation | Replay location, restriction, tunnel, branch, and connection events | Deterministic clock and fixtures | No |
| L3 iPhone UI | Verify editor, pre-drive review, driving mode, accessibility, degraded states | iOS simulator/device | No |
| L4 CarPlay | Verify templates, glanceability, voice timing, lifecycle, and phone/CarPlay handoff | CarPlay simulator and approved hardware | No |
| L5 Field | Measure positioning and sign timing on a lawful, passenger-observed drive | Real phone, vehicle, and dated route | Operator pages may be checked before departure, never as a deterministic assertion |

L1 and L2 carry most logic coverage. L3 and L4 prove platform integration. L5
tests hardware and road reality that simulators cannot reproduce.

## Portable scenario envelope

Each file under `e2e/scenarios/` contains:

- identity, layer, tags, and one primary purpose;
- evidence classification and dated source references;
- a network snapshot;
- an optional ordered route plan;
- other deterministic inputs and initial state;
- an ordered event timeline;
- assertions against observable state or output.

Route occurrences have both `occurrence_id` and `entity_id`. Reusing an entity
is valid; reusing an occurrence ID is not.

Assertions use stable semantic subjects such as
`navigation.occurrence_index` or `route_summary.toll.status`. A platform adapter
maps those subjects to engine values, accessibility identifiers, CarPlay
templates, or field observations. Scenario files must not contain Swift class
names or pixel coordinates.

## Determinism rules

- CI never calls live routing, traffic, toll, map, or operator services.
- Time, location, restrictions, and CarPlay lifecycle are injected as events.
- Official-query evidence is stored as dated scalar inputs and source links, not
  copied pages or screenshots.
- Synthetic IDs are obvious (`test.*`) and cannot be mistaken for production
  road data.
- Field observations record hardware and route configuration but do not become
  deterministic truth for every device.

## Scenario-first coding workflow

1. Select an existing scenario or add the smallest new one.
2. Run `python3 scripts/validate_e2e.py`.
3. Add the narrow adapter/test that consumes the scenario and prove it fails for
   the missing behavior.
4. Implement the smallest production change.
5. Run the target scenario, then the affected layer, then broader tests only if
   the risk justifies them.
6. Record the commands and actual results in the handoff.

Changing an assertion is a product-contract change. It requires a reason such
as a newly accepted product decision or stronger evidence, not merely a failing
implementation.

## Adapter responsibilities

Every implementation adapter should expose:

```text
load network snapshot and deterministic inputs
compile or load route plan
apply events in declared order
capture semantic observations after each event
evaluate scenario assertions
emit a compact failure report with scenario, event, subject, expected, actual
```

Adapters may support only the layers they implement, but unsupported events or
assertions must be reported explicitly rather than skipped silently.

## Journey-lifecycle adapter boundary

Keep external routing and device sensors outside deterministic scenarios. A
surface-routing adapter records a candidate leg with its directed endpoint and
whether it crosses an expressway boundary; a location adapter emits observations
with direction, continuity, timestamp, and confidence. The pure journey engine
then decides whether to accept the access leg or change phase.

The semantic observation surface should include at least:

```text
journey.phase
journey.ambiguity_reason
navigation.active_route_plan_id
navigation.current_occurrence_id
navigation.signal_reacquisition_status
navigation.route_candidate_resolution
presentation.active_surface
presentation.carplay_connection_state
shared_route.network_snapshot_id
shared_route.occurrence_ids
compiler.selected_template_variant_id
compiler.selected_template_parameters
route.executable
route.blocking_reasons
route.blocking_occurrence_ids
entry_recommendation.selected_facility_id
recovery.route_plan_id
recovery.chosen_rejoin_occurrence_id
egress_plan.exit_facility_id
localization.release_gate
guidance.active_voice_locale
guidance.visible_sign_text_ja
guidance.anchor_status
guidance.emitted_prompt_ids
tariff_selection.selected_tariff_version_id
tariff_selection.selected_tariff_version_status
tariff_selection.ignored_non_active_quote_ids
```

This split lets coding agents implement MapKit, Core Location, iPhone UI, and
CarPlay adapters independently without changing route semantics. CI injects
surface candidates and sensor observations; it never calls live MapKit or waits
for a real geofence.

For localization, domain tests prove that all required bundles and spoken forms
exist. Simulator or device tests separately prove voice discovery, pronunciation
fixtures, audio lifecycle, and the visible Japanese sign target. A device voice
being installed is an environment fact, not a portable domain assertion.

## Field-test protocol

Field tests require a separate, dated test plan and safe roles:

- the driver drives and does not collect data;
- a passenger or automated logger records observations;
- the route, direction, entrances, exits, planned restrictions, and safe abort
  points are reviewed before departure;
- device, iOS, vehicle/head-unit, wired/wireless state, timestamps, and location
  source metadata are recorded;
- road signs, police directions, closures, and safety always override the test;
- raw personal location traces remain private unless deliberately redacted and
  licensed.

Field success is configuration-scoped. For example, one successful wireless
CarPlay tunnel run does not prove that phone-only positioning works.

## Initial release gate

A product slice is ready for a closed road test only when:

- all L0 checks pass;
- its exact movements pass L1 legality and occurrence tests;
- L2 covers tunnel degradation, missed branch, closure, and recovery behavior;
- relevant L3/L4 critical paths pass without requiring complex driving-time
  interaction;
- evidence is current for the selected snapshot;
- the field plan has a safe fallback and no unresolved must-pass contradiction.
