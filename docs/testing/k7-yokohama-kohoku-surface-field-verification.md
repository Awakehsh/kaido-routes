# K7 Yokohama Kohoku surface field verification

## Decision

Do not publish a navigable Yokohama Kohoku surface schematic yet.

The pinned OSM extract is source-complete at the exit terminal. Yokohama's
2020 opening notice also identifies the corridor represented by OSM way
`776884422` as the temporary passage inside the land-readjustment area. That
historic identity does not establish the passage's current physical status,
legal direction, or permitted movement from the K7 exit in 2026.

The unresolved release code is:

`CURRENT_TEMPORARY_PASSAGE_DIRECTION_UNCONFIRMED`

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
  publish the temporary passage's current legal direction.
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
2. `TEMPORARY_PASSAGE_EAST_MOUTH`: both sides of the passage mouth at the exit
   signal, including motor-access and closure signs.
3. `TEMPORARY_PASSAGE_WEST_MOUTH_EASTBOUND`: signs and lane markings controlling
   travel toward the exit signal.
4. `TEMPORARY_PASSAGE_WEST_MOUTH_WESTBOUND`: signs and lane markings controlling
   travel away from the exit signal.

An absent sign in one image is not evidence that no restriction exists. Retain
enough consecutive views to show the whole controlled approach.

## Private evidence package

Copy
[`k7-yokohama-kohoku-surface-field-review.template.json`](fixtures/k7-yokohama-kohoku-surface-field-review.template.json)
into ignored private storage. Keep raw photos, video, coordinates, device
metadata, and personal traces under `research/`; do not commit them.

The manifest records only:

- the exact snapshot, facility, OSM way, node, and source direction;
- capture time and safe observer role;
- SHA-256 hashes that bind each checkpoint to private raw evidence;
- concise sign findings without coordinates;
- current physical status, legal direction, and permitted exit movement;
- reviewer, review time, and a bounded validity date.

Validate a completed manifest with an explicit date:

```sh
python3 scripts/validate_k7_surface_field_review.py \
  research/evidence/k7-kohoku-field-review.json \
  --as-of 2026-07-24 \
  --report /tmp/k7-kohoku-field-review-report.json
```

The tracked template must return `BLOCKED`. A completed manifest returns
`PASS`, but its report still sets `route_release_authority` to `false`.
Field completion closes only this road-level evidence gap. Route Atlas release
still requires production schematic review, occurrence bindings, attribution,
and the other release gates.

## Acceptance

The current movement may enter topology review only when:

- all four observations are current and hash-bound;
- safe collection fields pass;
- physical status is explicit;
- legal direction is one of `FORWARD_ONLY`, `REVERSE_ONLY`, `BIDIRECTIONAL`, or
  `NO_MOTOR_ACCESS`;
- the exit movement is explicitly `ALLOWED` or `PROHIBITED`;
- an independent reviewer accepts the findings and validity interval; and
- no newer operator, government, police, construction, or field evidence
  conflicts with the conclusion.

Any ambiguity, stale review, changed construction state, or source conflict
keeps the production topology blocked.
