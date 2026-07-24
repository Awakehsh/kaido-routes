# Kaido Routes agent instructions

## Communication and repository stage

- Use Chinese for chat with the project owner. Use English for tracked documentation, code, commits, pull requests, issues, and public comments.
- For substantial product or design summaries intended for the project owner, prefer a self-contained Chinese HTML file on the Desktop. Quick status and clarification may remain in chat.
- Treat tracked English Markdown and machine-readable E2E scenarios as the authoritative agent and open-source project contract. A user-facing HTML file is a presentation snapshot: it must not introduce a product decision that is absent from the tracked contract, and it should link back to the relevant Markdown.
- This repository is in product-contract and feasibility work with a platform-light Swift core. Do not start iPhone/CarPlay app targets, provider integration, or new dependencies unless the task explicitly asks for it.
- Lead with verified outcomes. Never claim that a route, junction movement, toll, closure, test, or device behavior is verified without dated evidence.

## Context loading

Use hybrid, just-in-time context loading:

1. Read this file and `README.md` first.
2. Read only the product, domain, or testing document relevant to the current task.
3. For behavior changes, load the exact scenario under `e2e/scenarios/` before reading broad background material.
4. Treat `research/` as a private, ignored discovery notebook. Do not load or quote it by default. A research task may inspect it, but findings must be rechecked before entering tracked assets.
5. Prefer links and identifiers over copying large source documents into context.

For a long handoff, preserve: objective, accepted decisions and reasons, files changed, actual verification, blockers, and next step. Drop raw command output and abandoned exploration.

## Product invariants

- The route is the product, not a by-product of a destination search.
- Model the road network as a time-versioned directed multigraph.
- A junction choice is an incoming approach to a legal outgoing movement, not a pin named after a JCT.
- Preserve repeated edges and movements as distinct route occurrences. Never deduplicate a route plan by entity ID or coordinate.
- Entrances and exits are directional facilities. A shared place or IC name does not imply all movements exist.
- Treat full, half, quarter, irregular, and unknown IC patterns as derived summaries. Routing uses exact directional entrance and exit facilities only.
- Treat a PA as a directional subgraph with explicit access and return movements, not an unrestricted POI.
- A journey may include a surface access leg and a surface egress leg, but its Shuto section remains an ordered route-first plan with explicit entry and exit transitions.
- Wrong-route recovery searches for a legal later occurrence in the active route plan. It must not become a destination-first reroute or silently leave the expressway.
- Finishing a cruise activates a legal, precomputed egress plan. It never means reversing, making a U-turn, or taking an arbitrary nearby exit.
- Keep actual planned distance separate from tariff distance and toll evidence.
- Keep `NO_KNOWN_CONFLICT` separate from `REALTIME_UNCONFIRMED`; neither means confirmed open.
- Keep active, proposed, and retired topology and tariff versions separate.
- Support Japanese, Simplified Chinese, and English in both displayed guidance and voice. UI language and guidance voice may be selected independently.
- Preserve Japanese sign text and route shields in every locale. Localized text, romaji, and spoken forms are explanatory layers, not replacements.
- Tunnel and stacked-road positioning must expose confidence and degraded mode; never render an estimated position as a precise measured fix.
- Keep the product focused on lawful route planning, safe driving assistance, and road culture. Do not add speed, lap-time, racing, evasion, or unsafe interaction mechanics.

## Navigation architecture boundaries

- `docs/architecture/ios-navigation-architecture.md` is the accepted direction for architecture spikes. Valhalla is the leading shared open-source implementation candidate behind the provider boundary, not RoutePlan authority. Keep OSRM and GraphHopper as independent executable controls and revisit the choice when broader coverage, matcher replay, operations, or field evidence contradicts it.
- Keep domain, routing, and navigation policy in platform-light Swift modules. MapKit, Core Location, Core Motion, CarPlay, speech, and third-party engines are adapters and must not become domain dependencies.
- Treat a MapKit or other provider result as a bounded surface-leg candidate. It cannot author, optimize, mutate, recover, or erase the active Shuto `RoutePlan`.
- Geometry-only provider output cannot resolve vertically stacked roads. Accept `selected_path_evidence` only when the provider's complete OSM way/start-node/direction sequence has been translated onto the exact Kaido graph and its dataset ID matches graph provenance.
- The shared-snapshot Valhalla translator, checksummed build-manifest validator, response normalizer, bounded provider, URLSession transport, and explicit live-probe CLI are implemented. Five private graph-bound entrance fixtures x three origins x three repeats passed 45/45 final surface-routing requests through the public adapter. Route destinations must carry the reviewed heading and tolerance with `node_snap_tolerance=0`. Valhalla remains a bounded surface provider and HMM comparison oracle; long-running operations, data-distribution review, broader coverage, and field evidence are still pending.
- The independent OSRM surface baseline is also implemented. Its response must carry the manifest dataset ID, report left-side driving, and expose a complete `annotations=nodes` sequence whose every consecutive pair maps to exactly one Kaido directed edge. Parallel-pair ambiguity fails closed. The same private five-fixture window passed 45/45 final requests through the public URLSession adapter; its synthetic driving-side polygon is not release data.
- The GraphHopper 11.0 baseline is implemented behind the same bounded role. Every call verifies `/info`, requires a non-epoch manifest road timestamp, disables geometry simplification at import and request time, and aligns `edge_key + osm_way_id + country` path details to one unique whole-path Kaido directed-edge sequence. Short local point-pair ambiguity is acceptable only when full-path continuity leaves one sequence; true parallel ambiguity fails closed. The same private five-fixture window passed 45/45 final requests. GraphHopper navigation prose and its hard-coded right-driving field are diagnostic only; Kaido owns Japanese driving-side and multilingual guidance.
- The tracked matcher replay floor contains six synthetic fixtures and 23 observations with ground-truth occurrence intervals and branch decisions. `NearestEdgeNegativeControl` must reproduce each fixture's declared safety failures deterministically; passing that CLI means the negative control failed as expected, not that it is navigation-safe. Keep raw field traces and provider matcher responses ignored. Normalize Meili, Swift HMM, and later matcher results into `MatcherEstimate` before using the shared evaluator.
- The manifest-bound `ValhallaMatcherReplayOracle` request, response normalizer, provider-edge translator, shared-evaluator bridge, and opt-in live CLI are implemented. It requires retained OSM begin/end node identity, preserves repeated edge traversals, and refuses non-increasing observation time. Valhalla 3.8.2 requires a node-category field such as `node.type` before its JSON serializer materializes the requested end OSM node. Meili match type is not calibrated confidence and carries no RoutePlan occurrence, so the bridge emits at most `LOW` and cannot authorize progress. The private same-snapshot controlled window produced repeat-identical 192/195 edge top-1 across 15 fixtures and 45 requests; three LOW misses at the Tomigaya entrance mouth and 0/195 occurrences are the first Swift-HMM comparison gate, not device-accuracy evidence.
- `RouteAwareSwiftMatcher` is the first platform-light online Viterbi prototype. Its hidden state includes occurrence, geometry supplies candidates, forward occurrence order and along-edge progress constrain transitions, and stale, ambiguous, or first post-gap evidence cannot become `HIGH`. The tracked corpus is deterministic with 18/23 edge top-1, 21/21 occurrence, and zero named safety failures. On the same private window it produced 190/195 edge top-1 and 195/195 occurrence hypotheses; all five misses were LOW abstentions with no selected edge. `RouteMatcherSession` is fixture-independent, incremental, RoutePlan/snapshot/corridor-bound, spatially indexed, and state-bounded; KR-S16 executes its stale/post-gap/reset output through `NavigationEngine`. A HIGH Swift estimate exposes `fractionAlongEdge` separately from `distanceMeters`; the latter is lateral point-to-road residual and must never be used as remaining route or DecisionZone distance. `CoreLocationObservationAdapter` preserves timestamp, receive order, invalid-fix rejection, source-information evidence, and a separately declared CarPlay field context. Never infer wired or wireless transport from a connected CarPlay scene or from `isProducedByAccessory`; public Core Location only identifies software simulation and external-accessory production. `CoreLocationMatcherCalibrationSession` measures this boundary into an in-memory `PRIVATE_RAW_LOCATION` trace; only coordinate-free `MatcherCalibrationReport` output may be considered for tracking. Never merge different snapshot, matcher, device, or transport scopes, and never treat synthetic/software-simulated evidence as a field statistical-floor pass. Treat the matcher as the live direction, not a calibrated production engine. The next boundary is actual device profiling and held-out field reliability evidence before UI integration.
- `KaidoDomain` owns released guidance semantics and `GuidanceFrame`; `GuidanceFramePlanner` in `KaidoNavigation` consumes only a fresh, route-resolved occurrence plus distance-to-DecisionZone observation. `GuidanceProgressBridge` may derive that observation only from HIGH matcher evidence bound to the exact snapshot, RoutePlan, occurrence, directed edge, complete corridor geometry, and reviewed DecisionZone entry offset; skipped occurrences and missing along-edge progress fail closed. It chooses the most actionable released anchor, preserves an emitted later stage across distance jitter, and skips obsolete catch-up prompts. `NavigationEngine` alone updates the occurrence-scoped ledger and returns a one-shot `GuidancePromptEmission`; restoration cannot replay it. `KaidoPresentation` requires that emission to match the current frame and ledger before `voice.shouldSpeak` becomes true. Phone, CarPlay, and voice adapters never own occurrence progress or infer prompt, anchor occurrence, DecisionZone, stage, distance, decision point, maneuver, lane preparation, route shield, sign target, or localized content. KR-S17 executes planning from resolved progress; KR-S18 executes the Swift matcher distance bridge through planner, ledger, and projection. Production corridor construction, DecisionZone calibration, SwiftUI layout, accessibility, CarPlay entitlement, audio lifecycle, and real hardware remain unproven.
- The strict compiler, occurrence progress, deviation recovery, legal egress, confidence policy, and structured guidance remain Kaido-owned behavior.
- Do not add a commercial navigation SDK or production provider dependency before its bounded role, licence, data-use constraints, hard gates, and comparison fixtures are documented.
- Keep the portable scenarios executable against the pure Swift core before building an iPhone screen. UI work consumes navigation snapshots; it does not define navigation semantics.
- `ExpertRouteEditorSession` in `KaidoRouting` owns the parked expert-authoring cursor. It starts from an exact directional entrance, exposes only the current reviewed incoming-approach/JCT choices, appends fresh movement and edge occurrences, permits reviewed cycles, and compiles only after an explicit directional exit. A reviewed lap template names one exact closed choice sequence; only an authored match becomes a candidate, duplication creates fresh occurrence values, and one undo removes the whole copied lap. Moving-time edits, future-decision choices, unclosed templates, stale lap candidates, duplicate occurrence IDs, invalid catalogs, and exitless catalogs fail closed. SwiftUI may render `ExpertRouteEditorSnapshot` and submit stable choice or lap-candidate IDs; it must not infer graph legality, infer loop closure, or mutate RoutePlan directly. KR-U01 and KR-U02 execute this boundary. The internal iPhone scene uses synthetic data; released catalog construction, localized labels, topology rendering, and full accessibility validation remain pending.
- `NavigationSession` is the actor-owned live composition boundary after a RoutePlan is compiled. It serializes `RouteMatcherSession`, conservative matcher-to-`LocationObservation` projection, `NavigationEngine`, `GuidanceProgressBridge`, prompt emission, CarPlay ownership, tunnel state, restrictions, recovery, and Finish drive. Initialization must reject any RoutePlan, snapshot, corridor, DecisionZone, or released-guidance identity drift. Matcher reset or restart clears matcher evidence only and cannot rewind engine progress. The actor deliberately sets entry-transition forward continuity to false because a matcher estimate alone does not prove the full entrance-transition contract; a later Apple adapter must provide that reviewed evidence separately. Core Location, background lifecycle, persistence, audio, SwiftUI, and `CPMapTemplate` remain adapters.
- `NavigationReleaseBundle` is the pre-runtime whole-asset gate. It requires one active snapshot, exact RoutePlan, same-snapshot valid editor catalog, complete matcher corridor, exactly one DecisionZone and at least one released guidance definition for every planned junction-movement occurrence, and an exact optional junction-view registry with no unregistered or orphaned values. It reuses `NavigationSession` runtime identity validation. Repeated graph entities are covered by occurrence ID, not entity ID. KR-D18 executes this boundary with synthetic release flags only; it does not release real road data.
- `RouteAtlasRelease` is the renderer-neutral map-integrity gate. It requires one active snapshot, exact RoutePlan, one released dated topology slice, complete one-to-one topology-node and topology-edge layout coverage, unique route-entity identity, exact legal-successor translation, normalized endpoint-connected geometry, separate released dated layout evidence, and an ordered binding for every RoutePlan occurrence. Coordinate contact never creates a legal connection, arbitrary display labels are excluded, and repeated occurrences may bind the same segment without being deduplicated. KR-D19 proves that one visually invented connection blocks release. This is internal consistency only: no real Shuto atlas may be described as verified until a real released topology slice and reviewed layout evidence exist.

## Project licence language

- The repository is open-source software under the Apache License 2.0.
- Apache-2.0 permits commercial and noncommercial use. Do not add a conflicting noncommercial restriction to project-authored material.
- Keep required copyright, patent, attribution, and change notices when incorporating or redistributing Apache-licensed material.
- The root licence does not override third-party data or asset terms. Keep separately licensed material identified and isolated.

## Evidence and data boundaries

Use this evidence order for routing and safety claims:

1. Current operator or government source.
2. Current licensed/open structured data with clear provenance.
3. Independently reviewed sign, video, or passenger-observed field evidence.
4. Community material for discovery only.

Every releasable route or movement must record its network snapshot, source references, checked date, and verification state. Conflicting or stale evidence blocks release.

Do not commit:

- Shuto Expressway maps, JCT images, videos, logos, or copied site design;
- mew-ti or JARTIC payloads without an appropriate licence;
- raw third-party articles, screenshots, or personal field traces;
- OSM-derived databases without a deliberate ODbL and attribution plan;
- anything under `research/`.

## Development workflow

For multi-step changes:

1. Observe current repository and runtime state.
2. State success criteria and the smallest relevant plan.
3. Add or select a scenario that expresses the behavior.
4. Make the smallest implementation change.
5. Run the narrowest useful verification, then expand only when risk warrants it.
6. Report exact commands and outcomes, including unrelated failures that affect the handoff.

Do not weaken a scenario merely to make an implementation pass. If the scenario conflicts with a product decision or new primary evidence, surface the conflict and update the contract intentionally.

## E2E contract

- `docs/testing/e2e-strategy.md` defines the test layers and workflow.
- `e2e/schema/scenario.schema.json` defines the portable scenario envelope.
- One scenario file should test one primary behavior.
- CI scenarios must be deterministic and must not call live operator, map, toll, or traffic services.
- Real routes may appear in tracked fixtures only when their evidence classification permits it. Otherwise use clearly synthetic IDs.
- Field tests supplement deterministic tests; they never replace them.

Run `python3 scripts/validate_e2e.py` after changing a scenario or schema.
Run `swift test` and `swift run kaido-scenarios e2e/scenarios` after changing
the Swift core or scenario semantics.

## Git

- Preserve user changes and keep edits scoped to the request.
- Never rewrite, amend, force-push, or alter existing commits unless explicitly asked.
- Before committing, inspect repository status and use an English, specific Conventional Commit subject.
- For `feat`, `fix`, `refactor`, `perf`, and `security` commits, include a body explaining why, impact, and verification. Documentation and chore-only commits may use a subject only.
