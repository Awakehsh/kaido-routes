# Security policy

## Reporting a vulnerability

Report suspected vulnerabilities privately through GitHub's
[private vulnerability reporting](https://github.com/Awakehsh/kaido-routes/security/advisories/new).
Do not open a public issue, and do not include a working exploit in the first
report — a description of the class of problem and the affected path is enough
to start.

Expect an acknowledgement within seven days. This is a maintainer-led project
without a paid security team, so please allow reasonable time for a fix before
any public disclosure.

## Scope

In scope: the iPhone app, the Swift packages under `Sources/`, the build and
release tooling under `scripts/`, and the integrity of the route database
under `data/`.

Of particular interest: anything that could make the app present a fabricated
or altered route as an enrolled product release, since a driver acts on that
guidance while moving.

Out of scope: the accuracy of upstream OpenStreetMap or operator data, which
belongs in a normal issue, and vulnerabilities in Apple platform components.

## Supported versions

Only the current `main` branch receives fixes. There is no maintained release
branch.
