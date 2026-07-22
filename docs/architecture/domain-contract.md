# Route and road-network domain contract

This document defines implementation-independent invariants. Concrete field
names may evolve, but implementations and tests must preserve the semantics.

## Time-versioned directed multigraph

The routable network is a directed multigraph bound to an effective snapshot.
Named roads and named junctions are presentation concepts; routing operates on
directional carriageways, facilities, approaches, connectors, and movements.

```text
NetworkSnapshot
├── RoadRoute
│   └── Carriageway
│       └── DirectedRoadEdge
├── AccessComplex
│   ├── EntranceFacility
│   └── ExitFacility
├── JunctionComplex
│   ├── JunctionApproach
│   ├── JunctionMovement
│   └── DecisionZone
├── ParkingAreaSubgraph
├── ExternalBoundary
└── OperationalRestriction
```

Overlapping coordinates do not establish connectivity. Direction, level,
structure, and connector identity do.

## Canonical junction choice

A route choice is:

```text
incoming carriageway and approach
→ named junction complex and ordered connector sequence
→ outgoing carriageway and direction
```

Lane preparation, sign destinations, maneuver, prompt anchors, and risk flags
attach to this movement. They do not attach only to the JCT name.

## Directional facilities

An entrance and an exit are separate routable facilities. A UI may group them
under one `AccessComplex`, but the route compiler cannot infer missing directions
or treat a full IC as the default.

```text
AccessComplex
  access_complex_id
  display_name
  directional_facility_ids[]
  access_pattern: FULL | HALF | QUARTER | IRREGULAR | UNKNOWN

EntranceFacility
  facility_id
  approach_variant_ids[]
  target_carriageway_id
  target_direction
  connector_edge_ids[]

EntranceApproachVariant
  approach_variant_id
  surface_approach_anchor_id
  directed_surface_movement_edge_ids[]
  availability_rule_id

ExitFacility
  facility_id
  source_carriageway_id
  source_direction
  connector_edge_ids[]
  surface_handoff_anchor_id
```

`access_pattern` is derived metadata for education and filtering. It never
creates a missing entrance, exit, or direction. Exact facilities and connector
edges in the selected network snapshot are the routing truth.

Surface anchors are directed points on an ordinary-road edge. An approach anchor
must leave enough distance for guidance before the ramp and must not represent a
place where the driver should stop. An exit handoff anchor is beyond the ramp at
a point where ordinary-road routing can resume.

One directional entrance may have more than one legal surface approach. A turn
restriction can make one approach legal only at particular times while another,
longer approach remains legal. These are separate `EntranceApproachVariant`
records, not interchangeable coordinates under one IC name. The selected variant
must be evaluated at the predicted entry time in the road's local time zone.
Unknown or conflicting availability blocks that variant. A provider route
calculated "now" does not prove that the movement will be legal at another time.

The B1 v1 probe fixture carries one approach anchor. A facility that needs
multiple or conditional variants cannot be released from that format until the
temporal movement contract and evidence are implemented. A conservative,
reviewed, always-legal variant may still be tested independently.

## Route occurrence identity

A route plan is an ordered list of occurrences:

```text
RoutePlan
  network_snapshot_id
  entry_facility_id
  occurrences[]
  exit_facility_id
  recovery_policy

RouteOccurrence
  occurrence_id
  index
  kind: EDGE | JUNCTION_MOVEMENT | PA_VISIT
  entity_id
  parking_area_id: present on each PA access, visit, and return occurrence
  toll_domain_id: operator or charging domain classification for this occurrence
```

The same entity may appear any number of times. Runtime identity is the
occurrence, not the entity or coordinate. Progress, import/export, recovery,
analytics, and UI selection must all preserve occurrence order.

An additional lap is value expansion, not an object reference. A
`ReviewedLapTemplate` identifies one contiguous, evidence-reviewed source
subsequence. `LapDuplicationRequest` supplies the same number of fresh occurrence
IDs. Compilation rejects an absent source sequence, count mismatch, empty ID,
collision, or duplicate. The resulting route preserves entity, PA, optionality,
and toll-domain fields while assigning contiguous new indexes.

Export and import use a versioned `SharedRouteDocument`:

```text
SharedRouteDocument
  schema_version
  evidence_state
  template_parameters
  route_plan
```

The codec accepts only its current schema version and a non-empty RoutePlan with
one network snapshot, stable plan/facility IDs, unique occurrence IDs, and
contiguous indexes matching array order. JSON keys are sorted for deterministic
exports. Import never deduplicates repeated entities, removes optional PA
occurrences, drops toll-domain bindings, changes evidence state, or migrates the
plan to a newer snapshot. Snapshot migration remains a separate reviewed compile
operation.

## Reviewed route-component requirements

A friendly route template may span multiple official route names. Its
`required_entity_ids_in_order` is an evidence-reviewed subsequence of exact
directed edges and junction movements. Strict compilation advances through the
candidate occurrence list in order and rejects any unresolved component. A UI
label such as “C2 circuit” is never permission to manufacture an edge between
two similarly named or nearby route sections.

Guided controls select an `ApprovedRouteTemplateVariant` by exact `template_id`
and the complete parameter map. Each variant is also bound to one
`network_snapshot_id` and declares its ordered required entities. Compilation
requires exactly one parameter match, the same snapshot as the RoutePlan, and a
successful component validation. Missing, duplicated, stale-snapshot, or
partially matching variants fail closed; parameters are never interpreted as
permission to generate an unreviewed movement.

## Composite journey

A `RoutePlan` is the Shuto route contract. A `JourneyPlan` composes it with
bounded ordinary-road access and egress:

```text
JourneyPlan
  journey_plan_id
  origin
  access_leg
  entry_transition
  shuto_route_plan_id
  finish_policy: FIXED_EXIT | RETURN_NEAR_ORIGIN | FINISH_ON_REQUEST
  precomputed_egress_options[]
  exit_transition
  surface_egress_leg

JourneyPhase
  PLANNING | APPROACH_TO_ENTRY | ENTRY_TRANSITION | STRICT_ROUTE
  | ROUTE_RECOVERY | EXIT_TRANSITION | SURFACE_EGRESS | COMPLETED
```

The access router may propose an ordinary-road leg, but the journey compiler
accepts it only if it reaches the selected facility's approach anchor without
entering another expressway facility. Entry and exit transitions come from the
versioned Kaido network, not from an IC name returned by a surface router.

Phase changes are evidence-based. A proximity region may create an entry
candidate, but only matching the directed transition, heading, and continuous
forward progress may automatically commit `STRICT_ROUTE`. Low confidence keeps
the journey in `ENTRY_TRANSITION` and cannot be hidden by a UI mode change.

## Route-first recovery and egress

Deviation recovery retains the original plan reference:

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
  status: SEARCHING | ACTIVE | REJOINED | NO_RELEASED_REJOIN
```

Every candidate target is a later occurrence in the active route plan. The
search may add legal recovery occurrences but cannot substitute a generic
destination route, silently cross an external boundary, or treat an exit as a
successful rejoin. If no released rejoin exists, an explicit safe egress marks
the route interrupted.

`FINISH_ON_REQUEST` similarly activates a versioned `EgressPlan` from the current
or a later eligible occurrence to an exact exit facility. It never reverses the
occurrence sequence. Before activation, an exit connector is an off-route branch
and cannot be used as a shortcut.

## PA semantics

A PA visit is an explicit access movement, stopping state, and return movement.
It may be optional or required. If an optional PA closes, the mainline route may
remain executable; if a required PA is unavailable, compilation fails.

```text
DirectionalParkingAreaPath
  path_id
  parking_area_id
  source_carriageway_id
  access_movement_id
  return_movement_id
  return_carriageway_id

Compiled occurrence group
  JUNCTION_MOVEMENT parking_area_id=...  # access
  PA_VISIT          parking_area_id=...  # stopping state
  JUNCTION_MOVEMENT parking_area_id=...  # return
```

The compiler matches all five directional path fields. A path released for the
opposite carriageway cannot be borrowed because the PA name is the same. Every
occurrence in one compiled PA group has the same optionality. An operational
closure skips the complete optional group or blocks the complete required group;
it never leaves an orphan access or return movement in the pending route.

## Navigation state

Navigation tracks at least:

```text
route_plan_id
occurrence_index
progress_within_occurrence
location_confidence: HIGH | MEDIUM | LOW | LOST
location_source
candidate_states
last_reliable_fix
ambiguity_reason
```

Candidate matching is constrained around the expected occurrence. Nearest-line
matching alone is insufficient for repeated, parallel, stacked, or tunnel roads.

## Operational status

Topology and operational status are separate. Status applies to an edge,
movement, facility, or PA over an interval:

```text
KNOWN_CLOSED
PLANNED_CONFLICT
NO_KNOWN_CONFLICT
REALTIME_UNCONFIRMED
```

`NO_KNOWN_CONFLICT` means only that checked planned information contains no
conflict. It cannot be rendered as a live-open confirmation.

Recurring legal movement restrictions are also separate from operational
closures. They require a versioned availability rule with source, local time
zone, day/holiday semantics, effective interval, and last review date. OSM
conditional syntax may identify a candidate rule, but it is not operator proof
and must not be silently discarded by graph conversion.

## Toll contract

Every strict route is compiled under a `TollDomainPolicy`:

```text
allowed_toll_domain_ids[]
requires_every_occurrence_classified: true
```

An occurrence in an external domain produces
`EXTERNAL_TOLL_DOMAIN_BOUNDARY`; a missing classification produces
`UNCLASSIFIED_TOLL_DOMAIN`. Both are hard blockers for a Shuto-only route. The
compiler returns the exact boundary occurrence IDs and external domain IDs so
pre-drive review can explain the failure. A broader journey may cross a boundary
only through a separately reviewed policy and tariff contract; geometry alone
cannot authorize it.

The planned route and toll quote are independent records:

```text
RoutePlan.actual_distance_km

TariffQuote
  entry_facility_id
  exit_facility_id
  tariff_version_id
  tariff_version_status: ACTIVE | PROPOSED | RETIRED
  tariff_distance_km
  vehicle_class
  estimated_amount_yen
  status: VERIFIED_QUERY | ESTIMATED | UNKNOWN
  checked_at
  official_query_reference
```

Never calculate a final toll from actual route distance. Proposed tariff
versions are non-active until primary evidence establishes an effective rule.
`TariffSelector` accepts a candidate set only when exactly one version is
`ACTIVE`; zero or multiple active versions return `NO_UNIQUE_ACTIVE_TARIFF`.
Input order, a newer check timestamp, or a proposed amount cannot make a
non-active version win.

## Signs and localization

Store displayed sign evidence separately from localized explanation:

```text
route_shields[]
destinations_ja[]
destinations_en_official[]
destinations_romaji[]
explanations_localized[]
spoken_forms_localized[]
lane_arrows[]
source_evidence[]
verified_at
```

Japanese text and displayed order are preserved so the driver can match the
physical sign. A translation cannot silently replace them.

The minimum release locales are `ja-JP`, `zh-Hans`, and `en`. Display guidance
and spoken guidance are complete, versioned bundles, and their languages can be
selected independently. Each bundle records reviewed spoken forms for route
codes, named facilities, and Japanese terms. Missing text, missing spoken forms,
or an unavailable matching device voice must be surfaced before departure; the
runtime cannot silently fall back to a wrong-language pronunciation.

`GuidanceAnchorDefinition` is versioned with the route snapshot:

```text
occurrence_id
anchor_id
prompt_id
```

The `(occurrence_id, anchor_id)` key and `prompt_id` are unique within a compiled
route. A prompt ledger records emissions for the whole active drive. Duplicate
sensor triggers for one key are suppressed, while the same anchor stage on a
later occurrence is a new key and may emit normally. A delayed anchor from an
older occurrence cannot become current guidance.

A release-ready anchor is wrapped by `ReleasedGuidanceDefinition`, which also
contains a non-negative trigger distance and immutable `GuidanceFrameTemplate`.
The template names the target movement occurrence and DecisionZone, prompt
stage, maneuver, lane preparation, Japanese decision-point and sign text, route
shields, and all three localized display/spoken bundles. The anchor occurrence
and target movement must both exist in the same RoutePlan; the target must be a
forward junction-movement occurrence. Definitions for one anchor occurrence may
not point at different movements or reuse the same trigger distance.

Runtime progress is a separate value: resolved anchor occurrence, remaining
distance to its reviewed DecisionZone, and observation time. It does not contain
localized prose. The planner may update a frame only with fresh HIGH-confidence,
route-resolved evidence outside post-gap reacquisition. A large position jump
selects only the most actionable eligible anchor rather than speaking every
missed prompt. An emitted later stage remains active through distance jitter.
Voice authorization is a transient `GuidancePromptEmission`, not a property of
the persisted frame; restoring the frame and prompt ledger therefore cannot
replay speech.

`DecisionZoneProgressDefinition` locates the entry of one reviewed DecisionZone
on a specific junction-movement occurrence. It carries the network snapshot ID,
RoutePlan ID, movement occurrence ID, and a non-negative offset along that
movement's corridor geometry. A distance bridge may consume it only when the
current matcher estimate, complete occurrence corridor, RoutePlan, and zone all
share the same identities. Matcher lateral residual, straight-line distance,
LOW confidence, missing along-edge progress, skipped occurrences, or geometry
from another snapshot cannot produce runtime guidance progress.

## Evidence lifecycle

Suggested movement lifecycle:

```text
DRAFT_OSM
→ OFFICIAL_DIAGRAM_CHECKED
→ SIGN_EVIDENCE_CHECKED
→ FIELD_TRACE_CHECKED
→ RELEASED
→ STALE_REVIEW_REQUIRED
```

Shipping a smaller released subgraph is preferable to presenting the whole
network as equally trustworthy.
