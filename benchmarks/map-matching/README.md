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

The next evidence step is a private same-snapshot Meili replay window. Until
that window exists, this adapter proves request and identity semantics only; it
does not establish real-road matching accuracy or justify a live provider in
the production navigation authority.
