# K7 Yokohama Kohoku surface field verification

## Decision

Do not publish a navigable Yokohama Kohoku surface schematic yet.

The pinned OSM extract is source-complete at the exit terminal. Yokohama's
2020 opening notice identifies the corridor represented by OSM way `776884422`
as the temporary passage then used inside the land-readjustment area. The
current municipal project page reports that surrounding infrastructure work
completed in March 2022 and the project ended on 2023-07-25. The final
replotting map does not map this exact OSM way to a current road identity.
Neither source establishes the way's current physical status, legal direction,
or permitted movement from the K7 exit.

The unresolved release code is:

`CURRENT_ROAD_IDENTITY_AND_DIRECTION_UNCONFIRMED`

Field scenario: `KR-F08`.

## Exact target

| Field | Identity |
|---|---|
| Network snapshot | `shutoko.candidate.osm-geofabrik-kanto-260721.k7-northwest` |
| Exit facility | `shutoko.exit.yokohama-kohoku.k7-northwest.up` |
| Incoming OSM way | `734299106` |
| Surface signal node | `7473451738` |
| Surface OSM way | `776884422` |
| Source direction under review | `FORWARD` |

The source direction is the OSM digitization direction leaving the surface
signal. It is not a legal-direction claim.

## Reviewed official evidence

- [Yokohama City, Kawamuki Line opening notice, published 2020-02-06](https://www.city.yokohama.lg.jp/city-info/koho-kocho/press/doro/2019/0206-kawamukousen.files/0005_20200206.pdf)
  identifies Kawamuki Line as municipal road Higashikatacho Route 342 and labels
  the adjoining connection to the Shuto entrance/exit signal as a temporary
  passage inside the land-readjustment area. The checked archived PDF has
  SHA-256
  `bca0774b5e80dd4bb1ed3ce3960d053e953b8cd376f2864c10f7df47eb9a7c35`.
- [Shuto Yokohama Kohoku access guide](https://www.shutoko.jp/-/media/pdf/responsive/customer/use/safety/branch_k7/info_kohoku_200421.pdf)
  shows the planned 2020 surface connection and exit movements. Its publication
  era cannot establish the 2026 traffic regulation.
- [Current Shuto Yokohama Kohoku facility page](https://www.shutoko.jp/use/network/map/route-k7ho/yokohamakohoku/)
  confirms that the facility still serves both K7 directions. It does not
  publish the unresolved corridor's current legal direction.
- [Yokohama City, current Kawamuko Minamikochi project page](https://www.city.yokohama.lg.jp/kurashi/machizukuri-kankyo/toshiseibi/jokyo/kukakuseiri/kawamukou/kawamukou.html),
  last updated 2026-06-02, reports March 2022 infrastructure completion,
  January 2023 replotting disposition, and project closure on 2023-07-25. The
  checked HTML has SHA-256
  `fe60100d8a73165eaa928d104fc42f9616b9318188a4b127cf968ac6daf960d1`.
- [Yokohama City, final replotting map, published 2023-01-12](https://www.city.yokohama.lg.jp/kurashi/machizukuri-kankyo/toshiseibi/kukappi-/kubetsu/14-tsuzuki.files/0009_20230112.pdf)
  records the completed land parcels. It does not identify OSM way
  `776884422`, publish a current municipal road route number, or state the
  traffic direction. The checked PDF has SHA-256
  `58b5204c76d2667d08c2865a91530def93768c70781e9639f436d671d3479ba9`.
- [Yokohama City road-register access page](https://www.city.yokohama.lg.jp/kurashi/machizukuri-kankyo/doro/tetsuzuki/daichosys.html)
  directs road-identity review to the official road-register system and warns
  that online data can lag.
- [Yokohama City road-name FAQ, updated 2026-03-19](https://www.city.yokohama.lg.jp/faq/kukyoku/doro/doro-chosa/20211014144003932.html)
  directs municipal-road identity and name checks to the recognized-route map.
  The checked HTML has SHA-256
  `9c5e2027622f51e1682e52c4e370f3ca02d22ccfff9c839fb79c1c5d0266b06f`.
- [Yokohama City road-register currentness page](https://wwwm.city.yokohama.lg.jp/yokohama-sp/yokohama-sp/Content/pages/up_date/5_michi/koushin.html)
  dates the online recognized-route map to 2026-07-03. The checked HTML has
  SHA-256
  `33d94d39759fa1d5d7438c9c7b41ee412b6aa9dacd828019d25e935e415a07f9`.
- [Yokohama City road-register terms for map 67](https://wwwm.city.yokohama.lg.jp/yokohama/Agreement?IsPost=False&MapId=67&RequestPage=%2Fyokohama%2FPositionSelect%3Fmid%3D67)
  state that online material is not proof and direct the latest legal-record
  review to the Road Survey Division counter. The checked HTML has SHA-256
  `e98aa1e272f7aca3bb8c52dd2855fae6038bb29902aa00ff63a58ca27295d102`.
  No exact recognized-route record has been obtained that uniquely maps OSM way
  `776884422` rather than either named Kawamuki Line carriageway leaving the
  same exit-terminal node.
- [Kanagawa Prefectural Police traffic-regulation index](https://www.police.pref.kanagawa.jp/kotsu/kotsu_kisei/list/)
  does not expose a complete point-level public regulation register for this
  movement. The 2026 bicycle one-way exemption candidate list is not a complete
  one-way inventory and cannot close the claim.

No operator map, municipal diagram, police map, or field image is copied into
the repository.

## Safe collection rule

The complete four-checkpoint package requires a passenger during lawful travel;
supporting surface views may also be collected from a lawful parked position.
The driver must not operate a device. The run must not require stopping on an
expressway, shoulder, ramp, or intersection. Abort the collection if any
requested view would require unsafe positioning or conflict with current signs.

## Required observations

Collect current, readable evidence for all four checkpoint IDs:

1. `EXIT_RAMP_SIGNAL_APPROACH`: lane arrows and every no-entry, one-way,
   mandatory-direction, turn-restriction, closure, or construction sign
   controlling the exit movement.
2. `UNRESOLVED_CORRIDOR_EAST_MOUTH`: both sides of the corridor mouth at the
   exit signal, including motor-access and closure signs.
3. `UNRESOLVED_CORRIDOR_WEST_MOUTH_EASTBOUND`: signs and lane markings
   controlling travel toward the exit signal.
4. `UNRESOLVED_CORRIDOR_WEST_MOUTH_WESTBOUND`: signs and lane markings
   controlling travel away from the exit signal.

An absent sign in one image is not evidence that no restriction exists. Retain
enough consecutive views to show the whole controlled approach.

## Private evidence package

Copy
[`k7-yokohama-kohoku-surface-field-review.template.json`](fixtures/k7-yokohama-kohoku-surface-field-review.template.json)
into ignored private storage. Keep raw photos, video, coordinates, device
metadata, and personal traces under `research/`; do not commit them.
The validator accepts the tracked empty template for deterministic negative
testing, but refuses any other in-repository manifest outside ignored
`research/`. Private storage outside the repository is also allowed.
Initialize a fresh manifest without overwriting an existing private review:

```sh
python3 scripts/prepare_k7_surface_field_review.py \
  --output research/evidence/k7-kohoku-field-review.json
```

Schema 1.1 is an exact allowlist. A completed manifest cannot add raw media,
file paths, coordinates, device metadata, or arbitrary observation fields.
It declares `PRIVATE_COORDINATE_FREE_REVIEW`, retains raw evidence only by
SHA-256, and requires every listed raw hash to be referenced by at least one
checkpoint.

The manifest records only:

- the exact snapshot, facility, OSM way, node, and source direction;
- capture time, passenger observer role, lawful-travel status, and explicit
  absence of driver interaction, expressway stopping, or unsafe positioning;
- SHA-256 hashes that bind each checkpoint to private raw evidence;
- concise sign findings without coordinates;
- current physical status, legal direction, and permitted exit movement;
- independent reviewer, review time, and a validity date no more than 31 days
  after review.

Hash each private raw evidence file without copying it into the manifest:

```sh
shasum -a 256 "research/evidence/k7-kohoku/evidence-file.mov"
```

Validate a completed manifest with an explicit date:

```sh
python3 scripts/validate_k7_surface_field_review.py \
  research/evidence/k7-kohoku-field-review.json \
  --as-of 2026-07-24 \
  --report /tmp/k7-kohoku-field-review-report.json
```

The tracked template must return `BLOCKED`. A completed manifest returns
`PASS`, but its report still sets `route_release_authority` to `false`.
The report contains only the fixed target identity, scalar conclusions, file
count, privacy classification, and blocker codes; it cannot reproduce media,
coordinates, paths, reviewer identity, or device metadata.
Field completion closes only the physical-status, legal-direction, and
permitted-movement part of this road-level evidence gap. It does not name an
official municipal road route. The exact road identity remains a separate
official road-register review, and Route Atlas release still requires production
schematic review, occurrence bindings, attribution, and the other release gates.
The later topology review must bind the canonical SHA-256 of this exact private
manifest; a different field manifest cannot inherit its approval. The subsequent
layout approval depends on the current topology approval and must use a different
reviewer. Merely changing topology or layout evidence state to `RELEASED` cannot
replace either review.

The tracked aggregate decision binds this template to the candidate and the
separate road-register review:

```sh
python3 scripts/validate_k7_route_atlas_readiness.py \
  data/route-atlas/candidates/k7-northwest-up-aoba-to-kohoku-release-readiness.json \
  --as-of 2026-07-24 \
  --field-review research/evidence/k7-kohoku-field-review.json \
  --report /tmp/k7-route-atlas-readiness-report.json
```

Passing the field validator can clear only
`CURRENT_SURFACE_FIELD_REVIEW_INCOMPLETE`. It cannot clear
`CURRENT_ROAD_IDENTITY_UNCONFIRMED`, ODbL distribution work, or unreleased
topology/layout evidence, and it never grants navigation authority.

## Acceptance

The current movement may enter topology review only when:

- all four observations are current and hash-bound;
- safe collection fields pass;
- physical status is explicit;
- legal direction is one of `FORWARD_ONLY`, `REVERSE_ONLY`, `BIDIRECTIONAL`, or
  `NO_MOTOR_ACCESS`;
- the exit movement is explicitly `ALLOWED` or `PROHIBITED`;
- an independent reviewer accepts the findings and validity interval; and
- the validity interval is no longer than 31 days from review;
- no newer operator, government, police, construction, or field evidence
  conflicts with the conclusion.

Any ambiguity, stale review, changed construction state, or source conflict
keeps the production topology blocked.
