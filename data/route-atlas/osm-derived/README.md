# OSM-derived Route Atlas data

The JSON database in this directory is derived from OpenStreetMap. It is
distributed under the Open Data Commons Open Database License 1.0
(`ODbL-1.0`), not under the repository's Apache License 2.0.

Attribution:

> © OpenStreetMap contributors

Licence and attribution references:

- <https://www.openstreetmap.org/copyright>
- <https://opendatacommons.org/licenses/odbl/1-0/>
- <https://osmfoundation.org/wiki/Licence/Attribution_Guidelines>

Both distributed K7 JSON artifacts also carry the exact ODbL URI and
OpenStreetMap attribution URI in machine-readable metadata. The root
Apache-2.0 licence does not relicense this directory.

## K7 Northwest directed candidate database

`k7-northwest-260721-directed-database.json` is a deliberately bounded
derivative database. It retains the exact OSM node, way, digitized direction,
tag, and coordinate lineage needed to review:

- Yokohama Aoba entrance to K7 Northwest up;
- the K7 Northwest up carriageway;
- the first divergence toward Daisan-Keihin / Yokohama Kohoku exit;
- the later Yokohama Kohoku exit versus Daisan-Keihin divergence; and
- one immediate alternative at each of those two decisions.

It also retains the Aoba incoming/non-route split and all three motor-road ways
leaving the Kohoku exit terminal as facility-boundary evidence. Two are named
one-way `川向線` carriageways. OSM way `776884422` is an unnamed `tertiary`
way without an explicit `oneway` tag. Yokohama's dated 2020 opening notice
identifies its corridor as the temporary passage then used inside the
land-readjustment area. A current municipal page reports that surrounding
infrastructure completed in March 2022 and the project ended in July 2023; the
final replotting map does not map the exact OSM way to a current road identity.
Its present physical status, legal direction, and permitted exit movement
remain unconfirmed. None of those surface ways is silently appended to the
Shuto RoutePlan.

It has no navigation authority and is not a complete interchange database.

## Public distribution and produced-work attribution

The complete machine-readable derivative database is committed at
`k7-northwest-260721-directed-database.json` in the public repository. The
reconstruction instructions below provide the pinned parent PBF, checksums,
bounded extraction parameters, tool version, and deterministic candidate
builders. Recipients may therefore use either the distributed complete
database or reconstruct the bounded derivative from the pinned source. No
additional restriction is imposed on the ODbL database.

The iPhone target bundles
`../attribution/route-atlas-attribution-catalog.json`. When the K7 produced
work is visible, SwiftUI renders `© OpenStreetMap contributors` and a separate
`ODbL 1.0` link in a native strip adjacent to the map. The credit is visible
without interacting with the non-interactive SVG. Unit and UI tests verify the
exact URLs and accessibility identities.

`k7-northwest-260721-distribution-review.json` is the dated, hash-bound
technical implementation review for this distribution and attribution
contract. It is not legal advice and grants no navigation or road-evidence
authority.

## Reconstruction

The source record pins:

- the dated Geofabrik Kanto PBF URL;
- its published MD5 and locally verified SHA-256;
- the OSM replication timestamp;
- the exact geographic bounds;
- pyosmium 4.3.1; and
- the bounded extract SHA-256.

Reconstruct the ignored intermediate:

```sh
python3 -m venv /tmp/kaido-osmium
/tmp/kaido-osmium/bin/pip install osmium==4.3.1
/tmp/kaido-osmium/bin/python scripts/extract_osm_motorway_slice.py \
  --input /path/to/kanto-260721.osm.pbf \
  --output /tmp/k7-bounded-motorways-260721.json \
  --expected-input-sha256 b13cc6eabacbd5a0362265cc5fd1eaf512d87c241ce3ab9daba4f8263b8d35ac \
  --source-uri https://download.geofabrik.de/asia/japan/kanto-260721.osm.pbf \
  --minimum-latitude 35.500 \
  --maximum-latitude 35.560 \
  --minimum-longitude 139.520 \
  --maximum-longitude 139.610
```

Rebuild the distributed database and blocked candidate:

```sh
python3 scripts/build_k7_osm_route_atlas_candidate.py \
  --source-extract /tmp/k7-bounded-motorways-260721.json \
  --review data/route-atlas/candidates/k7-northwest-up-aoba-to-kohoku-osm-directed-review.json \
  --database-output data/route-atlas/osm-derived/k7-northwest-260721-directed-database.json \
  --candidate-output data/route-atlas/candidates/k7-northwest-up-aoba-to-kohoku-osm-directed-candidate.json \
  --scenario-output e2e/scenarios/kr-d22-osm-directed-k7-candidate-remains-blocked.json \
  --successor-audit-output data/route-atlas/osm-derived/k7-northwest-260721-successor-audit.json \
  --successor-scenario-output e2e/scenarios/kr-d23-k7-source-successors-legal-review-blocked.json
```

The successor audit must find exactly 14 checkpoints and 19 outgoing
motor-road successors. It fails on an omitted or unexpected way, direction
drift, or an unreviewed applicable turn restriction. A passing source audit
does not release legal movement evidence: the current report intentionally
keeps OSM way `776884422` unresolved under
`CURRENT_ROAD_IDENTITY_AND_DIRECTION_UNCONFIRMED`. Yokohama's current project
page confirms completion of the surrounding infrastructure, not the exact way's
current road identity or direction. See the
[coordinate-free field-verification plan](../../../docs/testing/k7-yokohama-kohoku-surface-field-verification.md).

The source extract and parent PBF are not part of the Apache-licensed source
tree. Any redistributed derivative database must retain ODbL terms,
OpenStreetMap contributor attribution, and an appropriate data access or
reconstruction offer.
