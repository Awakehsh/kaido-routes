# Contributing to Kaido Routes

Kaido Routes is a maintainer-led project. The repository is public so the
route data, accuracy boundary, and navigation behaviour can be inspected, not
because the roadmap is open for delegation. Please read this before opening a
pull request.

## What is welcome

- **Issues.** Wrong or stale road data, a navigation behaviour that does not
  match the documented contract, a build failure from a clean checkout, or an
  accuracy claim the evidence does not support. These are the most valuable
  contributions to this project.
- **Small, self-contained pull requests** that fix a defect an issue already
  describes.

## What to discuss first

Open an issue and wait for a reply before writing code for a new feature,
a change to a product invariant in `AGENTS.md`, a new dependency, or any
change to the route database under `data/`. Product direction is decided by
the maintainer, and an unsolicited feature pull request will usually be
declined regardless of its quality.

## Development setup

Requirements: Xcode 26 or newer, XcodeGen, iOS 18 or newer, Python 3.

```sh
xcodegen generate
xcodebuild \
  -project KaidoRoutesApp.xcodeproj \
  -scheme KaidoRoutesApp \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

### Debug preview launch arguments

These hosts compile into Debug builds only. A Release build ignores every
one of them and opens the product home.

- `-WHOLE-SHUTO-TRACK-MAP-PREVIEW`
- `-WHOLE-SHUTO-TRACK-MAP-NAVIGATION-PREVIEW`
- `-WHOLE-SHUTO-TRACK-MAP-LINEAR-PREVIEW`
- `-WHOLE-SHUTO-NETWORK-BROWSE-PREVIEW`
- `-WHOLE-SHUTO-SEARCH-PREVIEW`
- `-WHOLE-SHUTO-SURFACE-FAILURE-PREVIEW`
- `-WHOLE-SHUTO-ROUTE-PREVIEW`
- `-WHOLE-SHUTO-NAVIGATION-PREVIEW`
- `-WHOLE-SHUTO-ARRIVAL-PREVIEW`
- `-WHOLE-SHUTO-JUNCTION-PREVIEW`
- `-WHOLE-SHUTO-JUNCTION-NAVIGATION-PREVIEW`
- `-WHOLE-SHUTO-KASAI-JUNCTION-PREVIEW`
- `-WHOLE-SHUTO-KASAI-JUNCTION-NAVIGATION-PREVIEW`
- `-WHOLE-SHUTO-SHINONOME-EASTBOUND-JUNCTION-NAVIGATION-PREVIEW`
- `-WHOLE-SHUTO-SHINONOME-WESTBOUND-JUNCTION-NAVIGATION-PREVIEW`
- `-WHOLE-SHUTO-TATSUMI-EASTBOUND-JUNCTION-NAVIGATION-PREVIEW`
- `-WHOLE-SHUTO-TATSUMI-WESTBOUND-JUNCTION-NAVIGATION-PREVIEW`
- `-C2-FULL-NAVIGATION-DEMO` for the retained C2 deterministic fixture
- `-K7-OPERATIONAL-E2E` for the retained K7 release fixture

## Verification

Run these before opening a pull request, and paste the real output into the
description:

```sh
swift test
swift run kaido-scenarios e2e/scenarios
python3 scripts/validate_e2e.py
python3 -m unittest discover -s scripts/tests
```

`docs/testing/e2e-strategy.md` defines the scenario layers. One scenario tests
one primary behaviour, CI scenarios never call live map, operator, toll, or
traffic services, and a field test supplements a deterministic test rather
than replacing it. Do not weaken a scenario to make it pass; if the contract
genuinely changed, change the scenario and say so.

## Branches, commits, and pull requests

- Branch from `main`, named `feat/`, `fix/`, `perf/`, `refactor/`, `chore/`,
  or `docs/` plus a short description of the actual change.
- `feat`, `fix`, `refactor`, `perf`, and `security` commits need a body
  covering why, impact, and verification.
- `main` is protected: pull requests only, `Verification gate` must pass, no
  direct pushes, no force pushes. Merges are squashed. Only the maintainer can
  merge, so an outside pull request is reviewed before it lands whether or not
  a GitHub rule demands an approval.
- Arm `gh pr merge --auto --squash --delete-branch` and move on rather than
  watching the run. The iPhone job takes roughly eight minutes, most of it
  compiling and exercising the simulator.

## Evidence, data, and licensing

Route, facility, legal, privacy, and field claims must trace to a primary
source. Never invent a field observation, a measurement, or a licence.
Derived data records its source and licence — see `DATA-LICENSES.md`, and
`docs/contributing/` for how each kind of release artifact is authored.

## Security

Do not open a public issue for a vulnerability. Follow `SECURITY.md`.
