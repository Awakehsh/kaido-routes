# Whole-Shuto directed network

`shuto-whole-network-20260804.json` is a complete OpenStreetMap-derived
database distributed under ODbL 1.0, not under the repository's Apache-2.0
licence.

Attribution and licence:

- © OpenStreetMap contributors
- <https://www.openstreetmap.org/copyright>
- <https://opendatacommons.org/licenses/odbl/1-0/>

The database is the default iPhone product graph. It contains 26 official route
entries, 2,499 selected OSM ways, 24,299 directed edges, 151 operator IC names,
39 JCTs, and 19 PAs. Its metadata retains the exact parent input, SHA-256,
snapshot timestamp, builder/version, ODbL identifier, attribution, official
catalog binding, facility-candidate review binding, graph limitations, and
bounded gap-connector way IDs.

The builder starts from the 26 pinned Shuto route relations, then adds only
connected `motorway_link` ways. It does not flood-fill into another
expressway's mainline. A bounded gap-connector pass repairs directed dead ends
left by OSM way splits whose new pieces were never re-added to the route
relation: from each membership-carrying carriageway that ends with no outgoing
continuation, it absorbs at most four orphan `motorway` ways (no more than 1 km
total) that lead straight back onto the selected graph, and only when their
`ref` or a Shuto name matches the interrupted route. Absorbed ways carry a
`kaido:gap_connector` tag and are listed in
`sources.osm.gap_connector_way_ids`.

Facility ramp candidates pass the ramp-topology probe — only link chains that
genuinely leave (exits) or enter (entrances) the graph survive, each anchored at
its ramp mouth — and then a dated, reviewed candidate correction list
(`data/network/shuto-facility-candidate-review-*.json`, hash-recorded in
`sources.facility_candidate_review`). At stacked or shared-collector junctions
no global heuristic can pin the right ramp: a rest-area access also "leaves the
network" through unselected service ways (Yoyogi PA's up-side ramp faked a
1.1 km Shinjuku-to-Yoyogi fare path that the operator search prices via the full
21 km circuit), while a genuine directional gate can anchor hundreds of meters
from the catalog point on a collector shared with the next facility (Hatsudai's
up entrance), so distance or way-ownership cuts sever real entrances. Meguro's
official point lies beside the first downstream ramp edge after the generated
mouth anchor; its reviewed entry-boundary rebinding preserves the real forward
`anchor → boundary` transition instead of synthesizing backwards geometry.
Kiba's entrance and exit share a loop, so the generic dead-end probe ranks only
the wrong southbound mouth; its reviewed replacement binds the official
up-side entrance to the exact post-ETC-toll edge toward Hakozaki. Each reviewed
exclusion, rebinding, or replacement therefore names one facility and exact
candidate edges plus its evidence; the build fails if it no longer matches the
graph, reverses continuity, or would unmatch a facility. Operator pages
establish current route and directional facility facts; OSM supplies candidate
geometry and topology. Every usable IC and every official JCT must match or
generation fails. Each JCT also
retains the URL and SHA-256 of its current operator detail image without
redistributing the image. The three unmatched IC facts are the explicitly
unavailable Yaesu Route facilities and have no routable candidates. The operator
fact catalog was re-scraped on 2026-08-04 with zero factual differences against
the committed 2026-07-29 catalog, which therefore remains the pinned build
input.

## Reconstruction

Reconstruct the complete distributed database from the current operator fact
catalog and pinned Kanto PBF. Geofabrik rotates dated files: 260728 and 260803
are no longer served; the snapshot now pins the dated 260804 file, whose
selected graph is identical to 260803's — only three ways gained a `lanes` tag
upstream:

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
    data/network/shuto-facility-candidate-review-20260815.json \
  --output data/route-atlas/osm-derived/shuto-whole-network-20260804.json \
  --expected-input-sha256 \
    a6835449bd93144cf6724e9682d691494a1b6ead5aeb4f42f1b5bf2f26e6412c \
  --source-uri \
    https://download.geofabrik.de/asia/japan/kanto-260804.osm.pbf
```

The database is a complete ODbL derivative offered in the repository. The
operator catalog is a compact factual source record; it does not redistribute
operator map or JCT image assets.

## Product boundary

The Swift decoder preserves the complete source/licence metadata. The default
map validates the exact bundled database identity, snapshot identity, candidate
verification state, OSM attribution, and ODbL identifier before exposing the
network with official OSM copyright and ODbL HTTPS links adjacent to the map.
Route-level `official_directions_ja` values come from the official
directional IC catalog; they are vocabulary constraints only. A direction is
bound to a JCT edge only by an exact reviewed movement definition and its
operator-source hash, never by an empty or inferred OSM relation member role.

The compiled runtime's deterministic asset identity covers this decoded
metadata and exact route-local inputs. It is not a `KaidoProductRelease`, does
not grant live-input or navigation authority, and does not promote OSM geometry,
unreviewed movements, lanes, realtime information, or field observations.
