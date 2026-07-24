# K7 Yokohama Kohoku exact road-register verification

## Decision

The current recognized-route identity of OSM way `776884422` remains
unconfirmed. Yokohama's online map 66 is the correct `認定路線図` layer, but
the City states that online road-register information is not proof and directs
the latest legal-record review to the Road Survey Division counter.

Historic corridor identity, an online map impression, or map 67 cannot clear
this gate. The exact official record must distinguish OSM way `776884422` from
the two named Kawamuki Line carriageways leaving the same exit-terminal node.

## Exact target

| Field | Identity |
|---|---|
| Network snapshot | `shutoko.candidate.osm-geofabrik-kanto-260721.k7-northwest` |
| Exit facility | `shutoko.exit.yokohama-kohoku.k7-northwest.up` |
| Incoming OSM way | `734299106` |
| Surface signal node | `7473451738` |
| Surface OSM way | `776884422` |
| Source direction under review | `FORWARD` |
| Compared successor ways | `734299108`, `734299111`, `776884422` |

The OSM node and way identifiers bind the review to the checked dataset. They
are not municipal route identifiers or legal-direction claims.

## Required official review

Use the City of Yokohama Road Survey Division counter and the current
recognized-route record for map 66. Obtain enough record identity to determine:

- the exact recognized-route identifier and Japanese route name;
- the record's current-through date and stable sheet or counter reference;
- which of the three compared OSM successors the official route feature
  matches; and
- why the other two successors cannot be substituted.

Map 67 is `平面図・補正図・別図・補正別図` and is not accepted as the recognized-
route record. The online map may help locate the target, but it cannot replace
the counter record for this release gate.

Relevant official sources:

- [Yokohama road-register access](https://www.city.yokohama.lg.jp/kurashi/machizukuri-kankyo/doro/tetsuzuki/daichosys.html)
- [Yokohama recognized-route map 66 terms](https://wwwm.city.yokohama.lg.jp/yokohama/PositionSelect?mid=66)
- [Yokohama road-name FAQ](https://www.city.yokohama.lg.jp/faq/kukyoku/doro/doro-chosa/20211014144003932.html)

## Private evidence package

Initialize a new non-overwriting manifest:

```sh
python3 scripts/prepare_k7_road_register_review.py \
  --output research/evidence/k7-kohoku-road-register-review.json
```

Keep the raw counter record, scan, photo, print, copied geometry, exact
locations, file paths, and reviewer working notes in ignored private storage.
The manifest contains only:

- the immutable target and three-way comparison identity;
- counter acquisition method and record currentness;
- a short official record locator;
- SHA-256 bindings to private raw record files;
- the resulting recognized-route identifier and Japanese name;
- a concise exact-way mapping basis;
- an independent reviewer and bounded validity; and
- explicit declarations that no raw record, coordinates, or copied map geometry
  are embedded.

Hash each private raw record without putting its path in the manifest:

```sh
shasum -a 256 \
  "research/evidence/k7-kohoku-road-register/private-record.pdf"
```

Every raw hash must be used by the exact mapping review. Unbound or unreferenced
hashes fail closed.

## Validation

```sh
python3 scripts/validate_k7_road_register_review.py \
  research/evidence/k7-kohoku-road-register-review.json \
  --as-of 2026-07-25 \
  --report /tmp/k7-kohoku-road-register-review-report.json
```

The tracked template returns `BLOCKED`. A completed review passes only when:

- it was obtained from the Road Survey Division counter;
- the exact map-66 record is current and hash-bound;
- the record explicitly distinguishes all three successor ways;
- the selected way is exactly `776884422`;
- the recognized-route identifier and Japanese name are non-empty;
- an independent road-identity reviewer accepts the mapping;
- the record is no more than 31 days old at review; and
- the review validity is no longer than 31 days from both the record and
  review dates.

The coordinate-free report excludes raw hashes, reviewer identity, official
record locator, and mapping narrative. It cannot grant Route Atlas or
navigation authority.

## Aggregate readiness

Supply the private road-register and field manifests independently:

```sh
python3 scripts/validate_k7_route_atlas_readiness.py \
  data/route-atlas/candidates/k7-northwest-up-aoba-to-kohoku-release-readiness.json \
  --as-of 2026-07-25 \
  --road-register-review \
    research/evidence/k7-kohoku-road-register-review.json \
  --field-review research/evidence/k7-kohoku-field-review.json \
  --report /tmp/k7-route-atlas-readiness-report.json
```

A passing private road-register review clears only
`CURRENT_ROAD_IDENTITY_UNCONFIRMED`. It cannot clear field legality, topology,
layout, realtime, or product-release gates. A later approved topology review
must bind the canonical SHA-256 of both exact private manifests; neither review
may inherit evidence from another file.
