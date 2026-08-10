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

The distributed whole-Shuto, K7, and C2 + B databases carry the exact ODbL URI
and OpenStreetMap attribution URI in machine-readable metadata. The root
Apache-2.0 licence does not relicense this directory.

## Whole-Shuto directed network

`shuto-whole-network-20260804.json` is the default iPhone product graph. It
contains 26 official route entries, 2,499 selected OSM ways, 24,299 directed
edges, 151 operator IC names, 39 JCTs, and 19 PAs.

The builder starts from the 26 pinned Shuto route relations, then adds only
connected `motorway_link` ways. It does not flood-fill into another
expressway's mainline. A bounded gap-connector pass then repairs directed
dead ends left by OSM way splits whose new pieces were never re-added to the
route relation: from each membership-carrying carriageway that ends with no
outgoing continuation, it absorbs at most four orphan `motorway` ways
(≤ 1 km total) that lead straight back onto the selected graph, and only
when their `ref` (or a Shuto name) matches the interrupted route — so a
different expressway sharing the junction node is still rejected. Absorbed
ways carry a `kaido:gap_connector` tag and are listed in
`sources.osm.gap_connector_way_ids`.

Facility ramp candidates pass the ramp-topology probe — only link chains
that genuinely leave (exits) or enter (entrances) the graph survive, each
anchored at its ramp mouth — and then a dated, reviewed exclusion list
(`data/network/shuto-facility-candidate-review-*.json`, hash-recorded in
`sources.facility_candidate_review`). At stacked or shared-collector
junctions no global heuristic can pin the right ramp: a rest-area access
also "leaves the network" through unselected service ways (Yoyogi PA's
up-side ramp faked a 1.1 km Shinjuku-to-Yoyogi fare path that the operator
search prices via the full 21 km circuit), while a genuine directional gate
can anchor hundreds of meters from the catalog point on a collector shared
with the next facility (Hatsudai's up entrance), so distance or
way-ownership cuts sever real entrances. Each reviewed exclusion therefore
names one facility, one candidate edge, and the operator evidence proving
it wrong; the build fails if an exclusion no longer matches or would
unmatch a facility. Operator pages establish current route
and directional facility facts; OSM supplies candidate geometry and topology.
Every usable IC and every official JCT must match or generation fails. Each
JCT also retains the URL and SHA-256 of its current operator detail image
without redistributing the image. The three unmatched IC facts are the
explicitly unavailable Yaesu Route facilities and have no routable
candidates. The operator fact catalog was re-scraped on 2026-08-04 with
zero factual differences against the committed 2026-07-29 catalog, which
therefore remains the pinned build input.

Reconstruct it from the current operator fact catalog and the pinned Kanto
PBF (Geofabrik rotates dated files: 260728 and 260803 are no longer served;
the snapshot now pins the dated 260804 file, whose selected graph is
identical to 260803's — only three ways gained a `lanes` tag upstream):

```sh
python3 -m venv /tmp/kaido-shuto-osmium
/tmp/kaido-shuto-osmium/bin/pip install \
  beautifulsoup4 \
  osmium==4.3.1
/tmp/kaido-shuto-osmium/bin/python scripts/build_shuto_official_catalog.py \
  --checked-at 2026-07-29 \
  --output data/network/shuto-official-catalog-20260729.json
/tmp/kaido-shuto-osmium/bin/python scripts/build_shuto_network.py \
  --input /path/to/kanto-260804.osm.pbf \
  --official-catalog data/network/shuto-official-catalog-20260729.json \
  --facility-candidate-review \
    data/network/shuto-facility-candidate-review-20260810.json \
  --output data/route-atlas/osm-derived/shuto-whole-network-20260804.json \
  --expected-input-sha256 \
    a6835449bd93144cf6724e9682d691494a1b6ead5aeb4f42f1b5bf2f26e6412c \
  --source-uri \
    https://download.geofabrik.de/asia/japan/kanto-260804.osm.pbf
```

The database is a complete ODbL derivative offered in the repository. The
operator catalog is a compact factual source record; it does not redistribute
operator map or JCT image assets.

## C2 + B geographic route database

`c2-b-20260729-geographic-route.json` is the bounded derivative database behind
the normal geographic map in the C2 product journey. It retains every selected
OSM node and way occurrence for:

- C2 outer from Tomigaya toward the Kasai movement;
- the directed Kasai C2-outer to B-west connector;
- B west from Kasai through Tatsumi and Ariake to Oi; and
- C2 outer from Oi through Ohashi to Hatsudai-minami.

The generator pins C2 relation `4256077` version 44, B relation `4256202`
version 55, exact directed checkpoint nodes, and the bounded Kasai movement
extract. It fails if those versions drift, a checkpoint is unreachable, node
coordinates disagree across inputs, or either OSM path boundary is more than
25 meters from the current operator facility point. OSM supplies geometry
only. Current operator pages establish the directional Tomigaya entrance and
Hatsudai-minami exit, while the reviewed junction contract establishes the
Kasai-right and Oi-left movements.

The iPhone map visibly renders `© OpenStreetMap contributors · ODbL 1.0`
adjacent to the produced work. This geographic candidate is not a live matcher,
traffic assertion, or field qualification.

Rebuild it from current API responses:

```sh
curl -o /tmp/kaido-c2-osm-full.json \
  https://api.openstreetmap.org/api/0.6/relation/4256077/full.json
curl -o /tmp/kaido-b-osm-full.json \
  https://api.openstreetmap.org/api/0.6/relation/4256202/full.json
curl -o /tmp/kaido-kasai-osm-map.json \
  'https://api.openstreetmap.org/api/0.6/map.json?bbox=139.8460,35.6410,139.8620,35.6560'
python3 scripts/build_c2_geographic_route.py \
  --c2-source /tmp/kaido-c2-osm-full.json \
  --b-source /tmp/kaido-b-osm-full.json \
  --kasai-source /tmp/kaido-kasai-osm-map.json \
  --output data/route-atlas/osm-derived/c2-b-20260729-geographic-route.json
```

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

The complete machine-readable derivative databases are committed in this
directory. The reconstruction instructions provide the current API or pinned
parent PBF inputs, checksums where applicable, bounded extraction parameters,
and deterministic builders. Recipients may therefore use the distributed
complete databases or reconstruct their bounded derivatives. No additional
restriction is imposed on the ODbL databases.

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
