# K7 Yokohama Kohoku exact road-register verification

## Decision

The current legal-record identity of OSM way `776884422` remains unconfirmed.
Public official evidence now supports `東方町第356号線` as a high-confidence
online identity candidate. Yokohama's online map 66 is the correct
`認定路線図` layer, but the City states that online road-register information is
not proof and directs the latest legal-record review to the Road Survey
Division counter.

A dated 2026-07-25 browser inspection selected the three source-adjacent
features at the exact target. The online map displayed the southern feature
corresponding to OSM way `776884422` as `東方町第356号線`, with an announcement
date of 2023-03-15, and displayed the two east-west successor features as
`高速横浜環状北西線`. The map's official currentness page dates the online
`認定路線図` to 2026-07-03. This is a precise counter locator, not proof of the
current legal record or a release finding.

This review no longer blocks the first K7 exit-handoff-only scope. That scope
ends guidance on the terminal expressway occurrence and releases no ordinary-
road successor. The exact road-register identity remains mandatory for a later
`SURFACE_EGRESS` expansion and is reported as a separate future-scope gate; it
is not treated as satisfied.

Historic corridor identity, this online feature selection, or map 67 cannot
clear the gate. The exact counter record must independently confirm the
`東方町第356号線` candidate, distinguish OSM way `776884422` from the two
adjacent expressway successors, and provide a stable record reference.

The 2023 City Council road-resolution package adds an exact recognition
constraint. After the land-readjustment replotting, the City recognized
Higashikatacho Route 356 from `川向町272番の3地内` to
`川向町430番の5地内`, alongside Routes 354, 355, 357, and 358, and retired
multiple older route segments. Its reference map and exact endpoints align
with the distinct lower branch selected as `東方町第356号線` in the current
online map. Together these sources materially narrow the identity question,
but they remain an online cross-source mapping rather than a current
counter-record finding.

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

The counter work must explicitly test the historic Higashikatacho Route 342
description against the post-replotting Routes 354 through 358 and the exact
Route 356 endpoints rather than assuming that the 2020 corridor name survived
as the exact current route.

Map 67 is `平面図・補正図・別図・補正別図` and is not accepted as the recognized-
route record. The online map may help locate the target, but it cannot replace
the counter record for this release gate.

Relevant official sources:

- [Yokohama road-register access](https://www.city.yokohama.lg.jp/kurashi/machizukuri-kankyo/doro/tetsuzuki/daichosys.html)
- [Yokohama recognized-route map 66 terms](https://wwwm.city.yokohama.lg.jp/yokohama/PositionSelect?mid=66)
- [Yokohama recognized-route map currentness](https://wwwm.city.yokohama.lg.jp/yokohama-sp/yokohama-sp/Content/pages/up_date/5_michi/koushin.html)
- [Yokohama road-name FAQ](https://www.city.yokohama.lg.jp/faq/kukyoku/doro/doro-chosa/20211014144003932.html)
- [Yokohama City Council Bill 129 road-recognition resolution, submitted 2023-02-07](https://www.city.yokohama.lg.jp/shikai/kiroku/kekka/gianR05-1.files/r5_1_s129.pdf)

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

A passing private road-register review clears only the future-scope
`CURRENT_ROAD_IDENTITY_UNCONFIRMED` gate. It cannot clear field legality,
exit-only topology, layout, realtime, or product-release gates, and it cannot
authorize a surface route without a separately released surface-egress
definition.
