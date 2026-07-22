# Coding-agent context architecture

## Operating profile

- **System type:** single coding agent by default, with optional isolated helpers
  only when a task is genuinely separable.
- **Domain:** long-horizon product, road-data, navigation, iPhone, and CarPlay
  development.
- **Complexity:** high; evidence and implementation evolve independently.
- **Session horizon:** medium to long, often crossing milestones and agents.
- **Retrieval strategy:** hybrid. Stable invariants are preloaded; code,
  scenarios, and evidence are retrieved just in time.

## Context budget

The percentages scale to the model's available window. The 128k column is an
example, not a provider requirement.

| Context component | Budget | Example at 128k | Policy |
|---|---:|---:|---|
| Core instructions and task objective | 10% | 12.8k | `AGENTS.md`, request, current success criteria |
| Tool definitions | 12% | 15.4k | Host-managed; avoid redundant tool prose in repo docs |
| Canonical examples | 4% | 5.1k | Load only the scenario closest to the behavior |
| Current history and working state | 34% | 43.5k | Keep decisions and recent evidence, compact raw output |
| Just-in-time code, docs, and evidence | 30% | 38.4k | Read exact files; do not preload the whole repository |
| Output and safety buffer | 10% | 12.8k | Preserve room for patches, diagnostics, and handoff |

The repository-controlled startup context should normally stay below roughly
6,000 tokens. Large road data, raw research, and source pages are never startup
context.

## Information source plan

### Always loaded

- root `AGENTS.md`;
- root `README.md`;
- the current user objective and explicit constraints.

### Loaded by task signal

| Task signal | Load |
|---|---|
| route compiler, progress, loops | `docs/architecture/domain-contract.md` plus the target domain scenario |
| iOS modules, navigation engine, provider choice | `docs/architecture/ios-navigation-architecture.md` and `docs/testing/navigation-engine-bakeoff.md` |
| route editor or library | `docs/product/custom-route-builder.md` plus relevant UI scenarios |
| test change | `docs/testing/e2e-strategy.md`, target scenario, test runner code |
| route-data contribution | `docs/contributing/route-evidence.md`, exact source records, relevant snapshot |
| surface access or MapKit probe | `docs/testing/navigation-engine-bakeoff.md`, `docs/architecture/journey-lifecycle.md`, exact entrance fixtures |
| matcher, tunnel, or CarPlay behavior | `docs/architecture/ios-navigation-architecture.md`, exact positioning scenarios, runtime logs, platform docs |
| product decision | `docs/product/principles.md` and only the affected contracts |

### Discovery-only context

`research/` may be read for an explicit research task. Its contents are not
authority and should be summarized with direct sources before they influence a
tracked contract.

## Behavioral examples

Use a small dynamic example set rather than a large permanent prompt:

1. **Happy path:** a legal movement sequence compiles and advances occurrence by
   occurrence.
2. **Key decision:** a repeated entity advances to its later occurrence instead
   of jumping backward.
3. **Error handling:** an illegal directional movement is rejected with an
   actionable reason.
4. **Safety boundary:** tunnel uncertainty changes confidence and presentation;
   it never fabricates a branch confirmation.

The corresponding JSON scenarios are the canonical examples. Do not duplicate
their full contents in prompts.

## Long-session lifecycle

Compact context when it approaches roughly 80% utilization.

Preserve:

- accepted product and architecture decisions with reasons;
- current objective and success criteria;
- modified files and repository state;
- actual test commands and outcomes;
- unresolved contradictions, blockers, and next step.

Discard or externalize:

- raw web pages and terminal output already synthesized;
- unsuccessful search variations;
- repeated descriptions of stable contracts;
- implementation speculation that was not accepted.

A cross-session handoff should use this compact shape:

```text
Objective
Accepted decisions and rationale
Current repository state
Files changed
Verification actually run
Evidence classification and sources
Open risks or blockers
Exact next step
```

## Quality gates for agent output

The must-pass dimensions are:

| Dimension | Question | Pass condition |
|---|---|---|
| Contract accuracy | Does behavior preserve the domain invariants? | No invariant violation |
| Evidence honesty | Are current facts dated and sourced at the right level? | No community claim promoted as authority |
| Scenario coverage | Is changed behavior expressed by a focused scenario? | Required for behavior changes |
| Verification truth | Are only actually run checks reported as passing? | Exact commands and outcomes recorded |
| Scope control | Is the change limited to the requested outcome? | No unrelated refactor or dependency |

Completeness and elegance are secondary to these gates. A visually polished but
unverified route is a failure.
