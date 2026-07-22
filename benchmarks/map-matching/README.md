# Map-matching replay benchmark

This benchmark compares location matchers without giving any matcher authority
over the active `RoutePlan`. It begins with synthetic traces and a deliberately
weak nearest-directed-edge negative control. The negative control is expected to
fail named safety gates; a successful CLI run means those known weaknesses were
reproduced deterministically, not that nearest-edge matching is acceptable.

## Tracked and private material

```text
benchmarks/map-matching/
├── schema/matcher-replay-fixture.schema.json
├── fixtures/synthetic/
├── raw/                              # local and gitignored
└── runs/                             # local and gitignored
```

Every fixture contains directed geometry, ordered route-occurrence bindings,
observations in receive order, ground-truth occurrence intervals, branch
decisions, and the exact failures expected from the negative control. Synthetic
IDs and coordinates make no real-road claim.

Raw field traces, accessory logs, provider responses, and unreviewed derivatives
must remain ignored. A future tracked derivative requires deliberate redaction,
licence review, provenance, and an explicit evidence classification rather than
being copied from `raw/`.

## Initial corpus

| Fixture | Contract exercised |
|---|---|
| `stacked-carriageway` | identical geometry on two road levels must not become a high-confidence tie-break |
| `parallel-surface-expressway` | normal noise at 5/10/20-meter accuracy bands must not silently move a fix to a nearby surface road |
| `repeated-edge-gaps` | one edge entity appears in four occurrences with 15, 30, and 60 second observation gaps |
| `wrong-branch-noisy-fix` | one noisy post-branch fix must not create a false high-confidence branch commit |
| `tunnel-branch-reacquisition` | a branch occurs inside a 31 second gap and can be confirmed only after observations return |
| `stale-reordered-sources` | a late out-of-order fix stays stale across phone, wired, wireless, and accessory source labels |

Source labels are benchmark dimensions, not claims that any CarPlay or accessory
source is more accurate. Device evidence must calibrate each source separately.

## Run

```sh
swift run kaido-matcher-replay benchmarks/map-matching/fixtures/synthetic
```

The command validates every fixture, runs the negative control twice, checks
value-identical deterministic reports, and compares actual failures with each
fixture's declared expectation. It exits nonzero for invalid fixtures,
nondeterminism, missing expected weaknesses, or new unexpected weaknesses.

An ignored same-snapshot fixture can exercise a self-hosted Valhalla explicitly:

```sh
swift run kaido-matcher-replay \
  --fixture research/private-matcher-fixture.json \
  --graph research/private-directed-graph.json \
  --manifest research/private-valhalla-manifest.json \
  --base-url http://127.0.0.1:18002 \
  --allow-live-valhalla --repeat 3 --pretty
```

Live mode emits a scalar-only local summary by default. `--raw-local` includes
normalized estimates for diagnosis; its output, provider responses, fixture,
and private graph must remain outside Git pending provenance and licence review.

Run the pure-Swift route-aware prototype against the same corpus:

```sh
swift run kaido-matcher-replay \
  --swift-hmm benchmarks/map-matching/fixtures/synthetic
```

The tracked result is deterministic 18/23 edge top-1 and 21/21 occurrence with
no named safety failure. The five non-top-1 observations are safe outcomes:
three indistinguishable stacked points have no directed top-1, one parallel-road
point stays ambiguous, and the first noisy wrong-branch point is not promoted.
`--raw-local` can expose normalized estimates for an ignored diagnostic run.

Replay is now a thin adapter over the fixture-independent incremental
`RouteMatcherSession`, so batch and streamed output share one algorithm. The
session binds a network snapshot and RoutePlan corridor, validates receive
ordering, uses a fixed-grid edge index, caps active Viterbi states, and supports
explicit reset/restart. Unit tests cover stream/batch parity and lifecycle
safety; KR-S16 covers the matcher-to-`NavigationEngine` commit boundary.

`NearestEdgeNegativeControl` intentionally ignores course, graph transition,
route occurrence, observation age, and location source. It is not production
navigation code. Its result establishes the minimum comparison floor for
Valhalla Meili and the route-aware Swift HMM.

`ValhallaMatcherReplayOracle` now defines that normalization boundary for an
offline batch oracle. It accepts only a manifest-pinned, same-snapshot response,
translates OSM way plus begin/end node and digitized direction into Kaido edge
chains, preserves repeated traversal, and leaves an internal segment boundary
ambiguous. A Valhalla `matched` result becomes LOW confidence because Meili does
not provide Kaido's calibrated live confidence or `RoutePlan` occurrence.
Non-increasing observation times are rejected rather than silently reordered.

The first ignored same-snapshot window now exercises that adapter through the
opt-in live CLI. Five reviewed entrance chains at three controlled graph-derived
accuracy bands produced 15 fixtures, 195 observations per repeat, and 45
provider requests. Reports were repeat-identical and edge top-1 was 192/195:
65/65 exact, 65/65 at 5-meter displacement with 10-meter declared accuracy, and
62/65 at 10-meter displacement with 20-meter declared accuracy. The three LOW
misses were all at the Tomigaya entrance mouth; occurrence stayed 0/195 because
Meili does not know the active `RoutePlan`.

The window validates the real protocol and same-snapshot translation boundary.
Its observations were synthesized from private OSM graph geometry, so it does
not establish phone or CarPlay accuracy, tunnel performance, calibration, or a
live production-provider decision. Raw fixtures, responses, and reports remain
ignored.

The Swift prototype scored 190/195 edge top-1 and 195/195 occurrence hypotheses
on the same private fixtures. Every non-top-1 result was a LOW abstention with no
selected directed edge. Meili scored 192/195 edge top-1 and 0/195 occurrence;
its three Tomigaya misses contained two LOW wrong-edge selections and one
ambiguity. This comparison selects the Swift matcher as the live RoutePlan
authority direction and keeps Meili as an offline oracle. It does not calibrate
either confidence scale.
