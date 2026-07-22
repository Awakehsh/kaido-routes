# Composite journey and navigation lifecycle

## Decision

A Kaido drive is one composite journey with an ordinary-road access leg, an
exact Shuto entry transition, a route-first expressway plan, an exact exit
transition, and an optional ordinary-road egress leg. These parts use different
routing evidence, but they share one lifecycle and one navigation presentation.

```text
current location
→ surface access leg
→ directional entrance transition
→ strict Shuto route occurrences
→ optional route-recovery occurrences
→ directional exit transition
→ optional surface egress leg
```

The route experience remains the primary object. Surface routing helps the user
reach and leave it; it cannot rewrite the selected Shuto route.

## Journey model

```text
JourneyPlan
  journey_plan_id
  origin
  access_leg
  entry_transition
  shuto_route_plan_id
  finish_policy
  precomputed_egress_options[]
  exit_transition
  surface_egress_leg

JourneyPhase
  PLANNING
  APPROACH_TO_ENTRY
  ENTRY_TRANSITION
  STRICT_ROUTE
  ROUTE_RECOVERY
  EXIT_TRANSITION
  SURFACE_EGRESS
  COMPLETED
```

`access_leg` and `surface_egress_leg` may be absent. For example, a user already
parked near an entrance may begin at `ENTRY_TRANSITION`, and a user may choose to
end guidance at the exit's surface handoff anchor.

## Exact access facilities

IC naming is presentation, not connectivity. The routable model separates a
named access complex from its actual facilities:

```text
AccessComplex
  display_name
  directional_facility_ids[]
  access_pattern: FULL | HALF | QUARTER | IRREGULAR | UNKNOWN

EntranceFacility
  facility_id
  surface_approach_anchor_id
  target_carriageway_id
  target_direction
  connector_edge_ids[]
  payment_constraints

ExitFacility
  facility_id
  source_carriageway_id
  source_direction
  connector_edge_ids[]
  surface_handoff_anchor_id
```

`FULL`, `HALF`, and `QUARTER` are derived educational summaries. They describe
how many expected directional access movements exist for a conventional divided
road. Shuto access patterns can be asymmetric or irregular, so the compiler
never infers a facility from the summary or from a shared IC name. The source of
truth is the current snapshot's explicit entrance and exit movements.

## Current-location entrance recommendation

Recommendation is a constrained compilation problem, not a nearest-point query.
It has two passes.

Hard filters:

1. The exact entrance facility and requested direction exist in the active
   network snapshot.
2. Its entry transition reaches an approved join occurrence in the selected
   route or template.
3. The full path to the intended exit remains inside allowed toll domains.
4. Vehicle, payment, predicted entry time, recurring movement rules, and known
   operational restriction constraints pass for the exact approach variant.
5. The surface route reaches the approach anchor without entering the wrong
   expressway facility first.

Scoring after those filters may consider surface ETA, turn complexity near the
ramp, Shuto lead-in distance, decision-zone difficulty, egress convenience, and
evidence freshness. Straight-line distance alone is never sufficient.

If a closer approach has time-conditioned turns, recommendation may choose a
longer reviewed approach that is legal for the full supported time range. The UI
must explain that choice. It must not route to an approach whose availability is
unknown and ask the driver to improvise at the ramp.

A route does not have to begin on C1 or C2. A verified radial-road lead-in may
join a later ring occurrence. A closed loop can be rotated to a compatible join
occurrence while preserving its cyclic order and creating fresh occurrence IDs.
A non-cyclic route cannot be rotated implicitly.

## Surface-routing feasibility

The ordinary-road data is available through platform routing services or an
open road graph; the missing product asset is the verified binding between that
route and Kaido's exact directional facility.

The first spike should request an automobile route from the current location to
a directed `EntryApproachAnchor` using MapKit. `MKDirections` can calculate
routes and `MKRoute.steps` exposes the step sequence. Kaido should validate the
result, convert accepted steps into its own maneuver pipeline, and remain the
active navigation experience. MapKit routing is server-backed and opaque, so an
answer is only a candidate: reject it if it enters an expressway early, reaches
the wrong side of the facility, or cannot be bound to the verified transition.

Opening Apple Maps is a useful fallback, not the seamless target. The documented
`openInMaps` flow launches Maps and suspends interaction with the calling app.
Background location or a region notification may help detect proximity, but a
geofence alone neither proves the exact ramp nor guarantees that Kaido can force
itself into the foreground. The fallback therefore requires an explicit handoff
before the approach anchor.

If MapKit cannot reliably produce bounded surface legs for the supported
facilities, a later implementation may route over a deliberately licensed OSM
graph. OSM commonly models ramps as directional `motorway_link` ways and can
store signed destinations, but those tags still require snapshot validation and
facility binding before release.

## Entry transition and mode switching

Kaido owns the transition from the ordinary-road approach anchor through the
ramp to the first Shuto occurrence. The default change from
`ENTRY_TRANSITION` to `STRICT_ROUTE` is automatic only when evidence agrees:

- the matched directed edge is part of the selected entrance transition;
- heading and forward continuity agree with its direction;
- recent fixes form a plausible sequence rather than a single geofence hit;
- the first mainline occurrence is reachable without an unobserved branch.

A geofence is a wake-up or candidate signal, never the committing signal. If
confidence is insufficient, the app retains `ENTRY_TRANSITION`, shows the target
route shield and direction, and offers a simple voice or CarPlay confirmation at
a safe point. It must not demand a phone interaction while the vehicle is moving.

When location is lost soon after a confirmed ramp match, navigation advances
only along the expected transition with decaying confidence. It must not snap to
a nearby tunnel or stacked carriageway merely to complete the mode switch.

## Route-first deviation recovery

Wrong-route recovery targets the active route plan, not a destination:

```text
RecoveryPlan
  recovery_plan_id
  route_plan_id
  deviation_occurrence_id
  observed_state
  candidate_rejoin_occurrence_ids[]
  chosen_rejoin_occurrence_id
  recovery_occurrences[]
  skipped_occurrence_ids[]
  status
```

The search considers only legal paths to a later occurrence in the same route
plan. Repeated entities are disambiguated by occurrence ID. A recovery may use a
checked loop or connector, but it cannot optimize away the remaining chosen
roads, cross an unapproved external boundary, or take an exit merely because it
is closer.

If no released rejoin exists, the safe fallback is an explicit egress plan. The
UI marks the original route interrupted, identifies the exit, and warns that
distance or toll expectations may change. It never describes that result as a
successful completion of the original route.

## Ending a loop without an illegal reversal

Supported finish policies are:

- `FIXED_EXIT`: follow the route's compiled default exit;
- `RETURN_NEAR_ORIGIN`: use the compiled exit and surface leg whose result best
  satisfies the accepted return policy;
- `FINISH_ON_REQUEST`: wait for the user, then activate one of the egress options
  precomputed for the current or a later eligible occurrence.

The driving action is named **Finish drive**, not Back. It first confirms
`Will finish at {exit name}` and then follows an ordinary sequence of Shuto
movements to that exit. It never means reverse direction, make a U-turn, cross a
painted gore, or leave through an arbitrary nearest ramp. Before activation, the
loop continues and exit ramps remain non-route branches.

If the driver misses the selected exit, guidance continues forward and chooses
another released egress option. Shuto's own safety guidance likewise instructs a
driver who misses an exit to continue to the next exit rather than reverse.

## Three-language display and voice contract

The release locales are `ja-JP`, `zh-Hans`, and `en`. UI language and guidance
voice language are independent settings. Every released route and movement must
pass a locale-completeness gate for all three; a missing locale blocks that item
in the affected language rather than silently mixing languages.

Guidance is assembled from structured fields, not translated as free-form prose:

```text
distance
+ JCT or facility name
+ maneuver and lane preparation
+ route shield
+ signed Japanese destination
+ localized explanation
```

Example for one illustrative, non-evidentiary sign target:

```text
Japanese: 800メートル先、辰巳ジャンクション。左側を進み、B 湾岸線・横浜方面へ。
Chinese:  前方 800 米，Tatsumi JCT。保持左侧，跟随 B 湾岸线・横滨方向。
English:  In 800 meters, at Tatsumi JCT, keep left for Route B, Bayshore Route, toward Yokohama.
Sign line shown in every locale: B 湾岸線・横浜方面
```

```text
LocalizedGuidanceBundle
  locale
  display_text
  spoken_text
  spoken_forms_by_term
  preserved_sign_text_ja
  route_shields[]
  source_evidence[]
```

Proper names, route codes, and Japanese road terms need reviewed spoken forms per
language. The implementation must enumerate device voices and select a matching
BCP-47 language. It must not feed raw Japanese names to an unrelated voice and
silently accept a wrong pronunciation. If a requested voice is unavailable, the
app reports that before departure and preserves text guidance.

## First spike and acceptance boundary

Start with a small dated set of roughly ten directional entrances and their
paired transitions. The spike succeeds only if deterministic and parked-device
tests show that:

- a farther compatible facility beats a nearer incompatible IC;
- the surface route terminates at the intended approach anchor without entering
  Shuto early;
- high-confidence ramp continuity switches phases automatically;
- a geofence-only or tunnel-ambiguous observation does not switch phases;
- a missed branch rejoins a named later occurrence in the original plan;
- Finish drive selects a declared exit sequence and never reverses;
- all three display and voice bundles identify the same Japanese sign target.

This spike establishes feasibility, not nationwide door-to-door navigation.

## Sources checked 2026-07-22

- [Shuto entrance and exit directory](https://www.shutoko.jp/use/network/map/)
- [Shuto entrance and exit sign guidance](https://www.shutoko.jp/use/convenience/infoboard/guidance/)
- [Shuto safety guidance for entrances and exits](https://search.shutoko.jp/movie/point_inout.html)
- [NEXCO Central explanation of full, half, and quarter IC patterns](https://highwaypost.c-nexco.co.jp/faq/traffic/knowledge/19.html)
- [Apple MapKit `MKDirections`](https://developer.apple.com/documentation/mapkit/mkdirections)
- [Apple MapKit route steps](https://developer.apple.com/documentation/mapkit/mkroute/steps)
- [Apple Maps handoff through `openInMaps`](https://developer.apple.com/documentation/mapkit/mkmapitem/openinmaps(launchoptions:))
- [Apple background location guidance](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
- [Apple geographic condition monitoring](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions)
- [Apple CarPlay navigation session](https://developer.apple.com/documentation/carplay/cpnavigationsession)
- [Apple speech synthesis voices](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice)
- [OSM `motorway_link` modeling](https://wiki.openstreetmap.org/wiki/Tag%3Ahighway%3Dmotorway_link)
- [OSM signed destination tags](https://wiki.openstreetmap.org/wiki/Key%3Adestination)
