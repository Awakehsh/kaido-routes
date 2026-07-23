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

## K7 Northwest directed candidate database

`k7-northwest-260721-directed-database.json` is a deliberately bounded
derivative database. It retains the exact OSM node, way, digitized direction,
tag, and coordinate lineage needed to review:

- Yokohama Aoba entrance to K7 Northwest up;
- the K7 Northwest up carriageway;
- the first divergence toward Daisan-Keihin / Yokohama Kohoku exit;
- the later Yokohama Kohoku exit versus Daisan-Keihin divergence; and
- one immediate alternative at each of those two decisions.

It also retains the Aoba incoming/non-route split and the two one-way
`川向線` ways connected to the Kohoku exit terminal as facility-boundary
evidence. Those surface ways are not silently appended to the Shuto RoutePlan.

It has no navigation authority and is not a complete interchange database.

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
  --scenario-output e2e/scenarios/kr-d22-osm-directed-k7-candidate-remains-blocked.json
```

The source extract and parent PBF are not part of the Apache-licensed source
tree. Any redistributed derivative database must retain ODbL terms,
OpenStreetMap contributor attribution, and an appropriate data access or
reconstruction offer.
