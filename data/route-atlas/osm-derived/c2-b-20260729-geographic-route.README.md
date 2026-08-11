# C2 + B geographic route database

`c2-b-20260729-geographic-route.json` is a bounded OpenStreetMap-derived
database distributed under ODbL 1.0, not under the repository's Apache-2.0
licence.

Attribution and licence:

- © OpenStreetMap contributors
- <https://www.openstreetmap.org/copyright>
- <https://opendatacommons.org/licenses/odbl/1-0/>

The database backs the retained C2 product-journey geographic map. It preserves
every selected OSM node and way occurrence for:

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

The retained iPhone map renders `© OpenStreetMap contributors · ODbL 1.0`
adjacent to the produced work. This geographic candidate is not a live matcher,
traffic assertion, or field qualification.

## Reconstruction

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

