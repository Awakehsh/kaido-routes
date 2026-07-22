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

- `docs/architecture/ios-navigation-architecture.md` is the accepted direction for architecture spikes. Provider selection remains conditional on `docs/testing/navigation-engine-bakeoff.md`.
- Keep domain, routing, and navigation policy in platform-light Swift modules. MapKit, Core Location, Core Motion, CarPlay, speech, and third-party engines are adapters and must not become domain dependencies.
- Treat a MapKit or other provider result as a bounded surface-leg candidate. It cannot author, optimize, mutate, recover, or erase the active Shuto `RoutePlan`.
- The strict compiler, occurrence progress, deviation recovery, legal egress, confidence policy, and structured guidance remain Kaido-owned behavior.
- Do not add a commercial navigation SDK or production provider dependency before its bounded role, licence, data-use constraints, hard gates, and comparison fixtures are documented.
- Keep the portable scenarios executable against the pure Swift core before building an iPhone screen. UI work consumes navigation snapshots; it does not define navigation semantics.

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
