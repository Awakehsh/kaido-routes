# Scenario catalog

This catalog is the behavior inventory. Rows marked **Seeded** have an initial
portable JSON scenario. Other rows define the intended implementation order and
should become scenarios when their layer is built.

## Domain and compilation

| ID | Behavior | Priority | State |
|---|---|---:|---|
| KR-D01 | Repeated entity IDs remain distinct ordered occurrences | P0 | Seeded |
| KR-D02 | Adding another C1 lap creates new occurrence IDs | P0 | Seeded |
| KR-D03 | Illegal incoming-to-outgoing junction movement is rejected | P0 | Seeded |
| KR-D04 | Full, half, or quarter IC metadata cannot synthesize a missing directional facility | P0 | Seeded |
| KR-D05 | A practical C2 circuit is modeled as C2 plus the required B movements | P0 | Seeded |
| KR-D06 | PA access and return are directional subgraph movements | P0 | Seeded |
| KR-D07 | Crossing an external toll-domain boundary is explicit | P0 | Seeded |
| KR-D08 | A route cannot silently migrate to an incompatible network snapshot | P0 | Seeded |
| KR-D09 | Japanese sign text survives localization and serialization | P0 | Seeded |
| KR-D10 | Actual route distance and tariff distance remain separate | P0 | Seeded |
| KR-D11 | An active tariff is never replaced by a proposed version | P0 | Seeded |
| KR-D12 | No known planned conflict never becomes live-open confirmation | P0 | Seeded |
| KR-D13 | Import/export preserves every repeated occurrence and index | P1 | Seeded |
| KR-D14 | Route-template parameters compile only to approved movement variants | P1 | Seeded |
| KR-D15 | Text, voice, and reviewed spoken forms are complete in Japanese, Simplified Chinese, and English | P0 | Seeded |
| KR-D16 | Current-location access chooses a compatible directional entrance rather than the nearest IC | P0 | Seeded |
| KR-D17 | Entrance recommendation rejects unavailable or unknown timed approaches | P0 | Seeded |

## Navigation simulation

| ID | Behavior | Priority | State |
|---|---|---:|---|
| KR-S01 | Tunnel uncertainty decays confidence and removes false precision | P0 | Seeded |
| KR-S02 | A planned tunnel branch is not confirmed without sufficient evidence | P0 | Covered by KR-S01 |
| KR-S03 | Signal recovery resumes the correct later route occurrence | P0 | Seeded |
| KR-S04 | A missed branch rejoins a later occurrence in the active RoutePlan, not a destination route | P0 | Seeded |
| KR-S05 | A planned movement closure blocks route start | P0 | Seeded |
| KR-S06 | A restriction arriving during a drive changes state without unsafe interaction | P1 | Seeded |
| KR-S07 | Optional PA closure skips the visit while preserving the mainline route | P0 | Seeded |
| KR-S08 | Required PA closure blocks route execution | P0 | Seeded |
| KR-S09 | Stacked-road candidates remain ambiguous until evidence separates them | P0 | Seeded |
| KR-S10 | Voice prompts fire once per occurrence at deterministic anchors | P0 | Seeded |
| KR-S11 | CarPlay disconnect falls back without losing route occurrence | P1 | Seeded |
| KR-S12 | A stale location timestamp cannot confirm a committed movement | P0 | Seeded |
| KR-S13 | Exact ramp, heading, and continuity evidence automatically enter strict-route mode | P0 | Seeded |
| KR-S14 | Finish drive activates a legal precomputed egress without reversing or taking an arbitrary exit | P0 | Seeded |
| KR-S15 | A geofence-only or low-confidence entrance observation cannot enter strict-route mode | P0 | Seeded |
| KR-S16 | Incremental matcher evidence requires fresh confirmation and reset cannot move navigation backward | P0 | Seeded |
| KR-S17 | Fresh resolved progress produces a non-regressing shared frame and one-shot voice emission | P0 | Seeded |
| KR-S18 | HIGH Swift along-edge progress becomes occurrence-bound distance to a reviewed DecisionZone | P0 | Seeded |

## iPhone and CarPlay experience

| ID | Behavior | Priority | State |
|---|---|---:|---|
| KR-U01 | Parked editor exposes only legal next choices and compiles an explicit directional exit | P0 | Seeded |
| KR-U02 | Expert editor can duplicate a closed subsequence as another lap | P0 | Planned |
| KR-U03 | An ambiguous freehand corridor asks for resolution while parked | P1 | Planned |
| KR-U04 | Pre-drive review separates actual distance, tariff distance, and toll status | P0 | Seeded |
| KR-U05 | Japanese sign target remains primary in Japanese, Chinese, and English UI | P0 | Seeded |
| KR-U06 | Estimated topology position is visually distinct from measured position | P0 | Seeded |
| KR-U07 | `REALTIME_UNCONFIRMED` cannot render as a green open-road state | P0 | Seeded |
| KR-U08 | Driving mode requires no route editing in a decision zone | P0 | Seeded |
| KR-U09 | Dynamic Type, VoiceOver, contrast, and route-shield recognition remain usable | P1 | Planned |
| KR-U10 | Phone and CarPlay surfaces agree on current occurrence and next movement | P0 | Seeded |
| KR-U11 | UI and guidance-voice languages can be selected independently | P0 | Seeded |
| KR-U12 | Finish drive names the planned exit before changing branch guidance | P0 | Seeded |
| KR-U13 | Entrance recommendations explain directional compatibility, not only proximity | P0 | Planned |

## Evidence and field verification

| ID | Behavior | Priority |
|---|---|---:|
| KR-F01 | Official toll query inputs and scalar result are reproducible and dated | P0 |
| KR-F02 | Phone-only Yamate Tunnel run records confidence degradation honestly | P0 |
| KR-F03 | Declared wired CarPlay run separately records source evidence and recovery | P0 |
| KR-F04 | Declared wireless CarPlay run separately records source evidence and recovery | P0 |
| KR-F05 | Critical movement prompt matches current route shield and Japanese sign | P0 |
| KR-F06 | Optional PA restriction leaves a safe mainline experience | P1 |
| KR-F07 | A route review detects a facility removed after an old recommendation | P0 |

## Safety regressions

The following are permanent rejection tests once UI or analytics exist:

- no speed, lap-time, or public-road performance leaderboard;
- no instruction to stop, reverse, or make an abrupt lane change after a miss;
- no destination-first reroute presented as recovery of the selected route;
- no exit ramp selected during a loop unless an egress plan is explicitly active;
- no photography prompt directed at the driver while moving;
- no implication that a PA is guaranteed open;
- no claim that an estimated toll or position is confirmed;
- no route start when a required safety-relevant movement is stale or conflicted.
