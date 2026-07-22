# Custom route builder

## Design decision

Offer two authoring depths over one compiler and one route-plan format:

1. **Guided customization** starts from a verified route template and changes a
   small number of safe parameters.
2. **Expert authoring** walks through legal directional movements one decision at
   a time.

Both modes compile to the same ordered occurrence sequence. They differ only in
how much of the graph the user sees.

## Guided customization

A user selects a verified route and adjusts constraints such as:

- compatible entrance and exit pair;
- current-location entrance recommendation among verified directional
  facilities;
- direction variant;
- one or more additional loop occurrences;
- target duration or actual distance range;
- required roads or highlights;
- optional or required PA stop;
- maximum junction difficulty;
- tunnel tolerance;
- UI language, guidance voice language, and explanation depth;
- finish policy: fixed exit, return near origin, or finish on request.

The system then presents a concrete compiled route and validation report. A
template is not a loose list of attractions: each allowed parameter combination
must map to checked movements in the selected network snapshot.

The compiler performs an exact lookup over approved variants. A variant records
its ID, template ID, complete parameter map, network snapshot, and ordered
required entities. It rejects a partial parameter match, an unapproved
combination, more than one matching approval, a stale snapshot, or missing and
out-of-order components. Target duration remains a filter among approved
variants; it never authorizes dynamic shortcut or movement generation.

## Expert authoring

The user selects an entrance facility. At each decision point, the editor shows
only movements legal from the current incoming approach:

```text
entrance facility
→ carriageway occurrence
→ junction movement
→ next carriageway occurrence
→ optional PA access and return
→ repeated occurrence sequence
→ exit facility
```

The user may select a previous closed subsequence and choose **Add another lap**.
This copies the subsequence as new occurrences with new occurrence IDs. It must
not create references to the original occurrence objects. The selectable slice
must come from a reviewed lap template whose topology closes in the active
network snapshot. The pure compiler receives caller-generated deterministic IDs,
rejects any collision, copies all semantic fields, and reindexes the expanded
sequence. It does not infer a closed loop from matching labels or coordinates.

### Circuit composition is explicit

A marketing name does not define graph connectivity. The current official route
catalog lists the Central Circular Route and Bayshore Route separately, while
the current complex-JCT catalog identifies Kasai JCT and Oi JCT as decision
points. Therefore a product route described as a practical “C2 circuit” is a
reviewed multi-route template: its ordered component requirement must retain the
exact C2 edges, B edges, and directional boundary movements that were verified
for that variant. The compiler rejects a missing or out-of-order component; the
UI may still present one friendly route name.

Current primary references, checked 2026-07-22:

- [Central Circular Route](https://www.shutoko.jp/use/network/map/route-c2/)
- [Bayshore Route](https://www.shutoko.jp/use/network/map/route-b/)
- [JCT and complex route guide](https://www.shutoko.jp/use/network/jct/)

These references support the network-modeling rule, not a released directional
route. Exact real movements still require a versioned evidence record and field
review.

Freehand drawing may be used as a gesture for selecting a desired corridor, but
it cannot directly create a route. The compiler must snap the gesture to legal
movements and ask the user to resolve any ambiguity while parked.

## Starting away from the expressway

A user normally creates or selects a route before reaching the Shuto network.
The editor recommends an exact `EntranceFacility`, not a place name or the
geometrically nearest IC. A hard filter first requires:

- the entrance's actual ramp direction and carriageway;
- legal access from that facility to an allowed join occurrence in the route;
- ETC and vehicle compatibility where relevant;
- no known blocking restriction;
- no unintended external toll-domain boundary.

Only then may a score compare surface ETA, access complexity, Shuto lead-in,
route difficulty, and the selected exit or return policy. A closed route may be
rotated to a verified join occurrence. A linear route may offer only its fixed
entrance or explicitly approved alternatives.

The surface leg ends at a directed approach anchor on the ordinary road before
the entrance ramp. It must not target an IC label, the center of a junction, or
a place where the driver would have to stop. The entry transition from that
anchor through the ramp and merge belongs to the Kaido journey.

## Finishing the drive

Every compiled route has a fixed default exit. A route may additionally expose
**Return near origin** or **Finish drive** policies. `Finish drive` is not a
Back button and never requests a reversal. It activates a checked egress sequence
from the current occurrence to a compatible directional exit and tells the user
which exit will be used before any branch instruction changes.

For a repeated loop, the compiler stores safe egress choices at eligible
occurrences. Until an egress plan is activated, an exit ramp is not a valid
substitute for a missed mainline movement. If the chosen exit is missed, the
driver continues safely and the system searches for another checked egress; it
never asks for stopping, reversing, or a U-turn.

## Validation result

Compilation returns separate hard and soft findings.

Hard blockers include:

- illegal or missing junction movement;
- incompatible directional entrance or exit;
- an external boundary when the route is declared Shuto-only;
- a known closure in the requested time interval;
- required PA access that is unavailable;
- a route object built for an incompatible network snapshot.

Warnings include:

- real-time passage not confirmed;
- optional PA may be unavailable;
- long tunnel or degraded-positioning exposure;
- short weave, right-side exit, or successive high-load decisions;
- toll is estimated rather than reproduced from an official query;
- route or sign evidence is approaching its review deadline.

### Low-price circuit evidence

Current official pages checked 2026-07-22 state that standard-car ETC basic
charges range from JPY 300 to JPY 1,950, that tariff distance can differ from
actual distance, and that the shortest Shuto-only path is used when multiple
paths connect the same entrance and exit. The D10 fixture separately preserves
one reproduced official query: Iikura to Shibakoen via Takaracho returned JPY
300 for the recorded inputs and check time.

This supports a dated route-detail estimate, not a product promise that any lap
count, all-night drive, entry/exit pair, vehicle, or future tariff will cost JPY
300. A [2026 community article](https://www.4g15maimai.com/entry/2026/05/17/005449)
is useful demand and route-pattern research, but its broader “unlimited laps”
interpretation remains non-authoritative. The app should link the current
official query, retain `tariff_version_status`, and tell the user that the ETC
statement is final.

Primary references:

- [ETC basic charges](https://www.shutoko.jp/fee/fee-info/pay_etc/)
- [Tariff-distance and route-selection rule](https://www.shutoko.jp/fee/fee-info/pay_etc/distance/)
- [Official route and toll query](https://search.shutoko.jp/)

## Safe customization boundaries

- Never optimize away an explicit road, direction, movement, or lap.
- Never insert an unverified shortcut merely to meet a duration target.
- Never promise that a toll stays constant as laps or elapsed time increase.
- Never turn route difficulty into a competitive score.
- When a branch is missed, do not ask for an abrupt correction. Continue safely,
  first find a checked path to a later occurrence in the active route plan, and
  make skipped occurrences and the recovery path explicit. Use a safe exit only
  when no released rejoin is available; mark the original route interrupted.

## Sharing and community routes

A shared route contains occurrence intent, template parameters, network snapshot,
and evidence state. It is not only a polyline or GPX track.

The v1 shared document is deterministic JSON. Its RoutePlan carries the exact
`network_snapshot_id`, ordered occurrences, directional PA bindings, optionality,
and toll domains. Import rejects unsupported schema versions and malformed
occurrence identity or order; it does not silently repair or migrate them.

Community routes should initially import as `COMMUNITY_CANDIDATE`. They remain
non-navigable until the compiler validates current topology and a reviewer checks
the safety-critical movements and signs. Popularity never upgrades evidence.
