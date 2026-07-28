# Kaido Routes agent instructions

## Communication

- Use Chinese with the project owner. Use English for tracked documentation,
  code, commits, pull requests, issues, and public comments.
- Lead with verified outcomes. Never claim that a route, movement, toll,
  closure, test, device behavior, or field result was verified without dated
  evidence.
- Keep tracked English Markdown and executable scenarios authoritative. A
  Chinese owner-facing HTML report is a presentation snapshot and must not add
  decisions absent from the tracked contract.

## Current stage and autonomous authority

- This repository is in active product delivery. It has a real iPhone target,
  a released K7 route, a joint navigation/atlas product artifact, and a
  physical-device deployment path. Do not describe it as a feasibility-only
  repository.
- The project owner authorizes agents to modify repository rules, product
  code, tests, data contracts, adapters, dependencies, and documentation when
  needed to finish the product.
- Work directly on `main`. Within Kaido scope, normal implementation,
  dependency installation, deterministic data generation, simulator testing,
  physical-device build/install/launch, commits, and pushes do not require a
  separate approval checkpoint.
- Continue from one completed milestone to the next highest-value executable
  milestone. Do not stop merely because an old handoff called something a
  future gate, or because a synthetic reviewer/team label is absent.
- Automated review may be run by the implementing agent. Require a distinct
  human or field reviewer only when the evidence itself is a human observation
  or independent field measurement; never invent that evidence.
- Pause only for a genuinely unavailable secret/account, unavoidable
  third-party action, material spend, destructive target ambiguity, or a
  product decision with materially different user outcomes that cannot be
  inferred from the current contract.
- App Store preparation or submission may proceed when the configured account,
  listing, privacy answers, licences, and release evidence are available.
  Never fabricate legal, privacy, field, or marketing claims to pass a gate.

## Context loading

1. Read this file and the current Git state first.
2. Read `README.md` and only the product, architecture, or test document needed
   for the active milestone.
3. For behavior changes, load the exact scenario under `e2e/scenarios/` before
   broad background material.
4. Treat `research/` as an ignored private notebook. Recheck any discovery
   against current primary sources before promoting it into tracked assets.
5. Preserve intentional dirty changes and prefer exact IDs, paths, hashes, and
   runtime probes over inherited prose.

## Product invariants

- The route is the product, not a by-product of destination search.
- Model the road network as a time-versioned directed multigraph.
- A junction choice is an incoming approach to a legal outgoing movement.
- Preserve repeated edges and movements as distinct ordered occurrences.
- Entrances, exits, and PA access/return movements are directional facilities.
- Surface access and egress may surround the Shuto section, but providers
  cannot author, mutate, optimize, recover, or erase its `RoutePlan`.
- Wrong-route recovery searches only for a legal later occurrence in the
  active plan. Finish drive uses the released exit/egress contract and never
  invents a U-turn, reversal, or nearby exit.
- Keep driven distance, tariff distance, toll information, and passage status
  separate.
- `NO_KNOWN_CONFLICT` and `REALTIME_UNCONFIRMED` never mean confirmed open.
- Missing, expired, not-yet-valid, or profile-unavailable tariff/passage
  information is an explicit warning, not route authority. A fresh matching
  `KNOWN_CLOSED` or `PLANNED_CONFLICT` state blocks navigation.
- Support Japanese, Simplified Chinese, and English. UI and voice language are
  independent, while Japanese sign text and route shields remain visible.
- Position confidence and degraded mode must be explicit, especially in
  tunnels and stacked roads.
- Keep the product lawful and safe. Do not add racing, speed, lap-time,
  evasion, or unsafe interaction mechanics.

## Architecture boundaries

- `docs/architecture/ios-navigation-architecture.md` is the current detailed
  architecture contract. Update it when the accepted design changes; do not
  duplicate its implementation history in this file.
- Keep domain, routing, matcher, navigation, and guidance policy in
  platform-light Swift modules. MapKit, Core Location, Core Motion, CarPlay,
  speech, network providers, and commercial/open-source engines are adapters.
- `RoutePlan`, exact occurrence identity, `NavigationSession`, released
  guidance, and the joint `KaidoProductRelease` remain Kaido-owned authority.
  UI and provider output are projections or bounded candidates.
- Geometry-only provider output cannot resolve vertically stacked roads.
  Provider identity must translate onto the exact graph snapshot before it can
  contribute selected-path evidence.
- Valhalla is the leading shared surface/matcher implementation candidate.
  OSRM and GraphHopper remain independent executable controls. Revisit this
  choice when current coverage, operations, replay, licence, or field evidence
  warrants it.
- A commercial dependency is allowed when its bounded role, licence/data-use
  terms, fallback, and executable comparison are documented and verified.
- Synthetic fixtures prove deterministic behavior only. Signed build,
  installation, and launch prove device deployment only. Neither substitutes
  for passenger-safe field reliability, acoustic, tunnel, or CarPlay evidence.

## Evidence, privacy, and licences

- For static road identity and legal movement claims, prefer: current operator
  or government sources; current licensed/open structured data; independently
  reviewed sign/video/passenger evidence; then community material for
  discovery only.
- Conflicting or stale topology/movement evidence blocks a new static road
  release. Stale dynamic toll/passage information is shown as non-current and
  does not revoke an already exact released route.
- Keep snapshot, source, checked date, and verification state with every
  releasable road or movement.
- Keep raw coordinates and personal field traces private and ignored. Track
  only coordinate-free, scope-bound reports when the contract permits them.
- The project is Apache-2.0. Preserve required copyright, patent, attribution,
  and change notices. Root licensing never overrides third-party data terms.
- Do not commit copied operator maps/JCT images/logos, unlicensed JARTIC or
  mew-ti payloads, raw third-party articles/screenshots, private field traces,
  or OSM-derived databases without the deliberate ODbL distribution plan.

## Autonomous delivery workflow

1. Observe current repository, runtime, device, and external dependency state.
2. Define the user-visible outcome and the narrowest executable success
   criteria.
3. Add or select a deterministic scenario for behavior changes.
4. Implement the complete vertical slice, including error and degraded states.
5. Run the narrowest useful checks, then the full affected regression.
6. Exercise the real App path on a simulator and connected device when
   applicable; distinguish runtime proof from field proof.
7. Update authoritative docs, commit with an English Conventional Commit
   message, and push `main`.
8. Continue to the next executable product gap without waiting for another
   prompt. Stop only at a genuine external boundary and leave one exact
   continuation command or artifact.

Do not weaken a scenario merely to pass it. If current primary evidence or an
intentional product decision changes the contract, update the scenario and
contract explicitly.

## Product-ready definition

- The default iPhone journey completes route selection/authoring, review,
  navigation startup, degraded-state handling, finish, and restoration without
  internal workbench knowledge.
- Released runtime inputs are hash-bound to one exact product and route.
- Critical interaction is accessible, localized, usable without network where
  promised, and does not require unsafe touch while driving.
- Deterministic core, App unit/UI, release-validation, and device smoke paths
  pass from a clean checkout.
- Known limitations are visible in-product and documented, but optional dynamic
  information and absent future integrations do not masquerade as blockers.
- “Product-ready” may be achieved before broader road coverage, CarPlay, or
  field qualification. Those capabilities must remain honestly labeled until
  their own evidence exists.

## E2E contract

- `docs/testing/e2e-strategy.md` defines layers and workflow.
- `e2e/schema/scenario.schema.json` defines the portable envelope.
- One scenario tests one primary behavior.
- CI scenarios are deterministic and never call live map, operator, toll, or
  traffic services.
- Field tests supplement deterministic tests and never replace them.
- Run `python3 scripts/validate_e2e.py` after scenario/schema changes.
- Run `swift test` and `swift run kaido-scenarios e2e/scenarios` after Swift
  core or scenario-semantic changes.

## Git

- Preserve unrelated user changes. Never rewrite, amend, or force-push unless
  the owner explicitly requests history rewriting.
- Inspect status before committing. Use a specific English Conventional Commit
  subject.
- `feat`, `fix`, `refactor`, `perf`, and `security` commits need a body that
  states why, user/system impact, and verification.
- Push completed milestones to `origin/main`; do not create process-only
  branches or PRs unless collaboration or repository protection requires one.
