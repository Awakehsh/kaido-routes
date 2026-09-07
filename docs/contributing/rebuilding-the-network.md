# Rebuilding the network

How the bundled whole-Shuto database is regenerated from operator pages and
a pinned OpenStreetMap extract.

The builders use Beautiful Soup and pinned pyosmium:

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

The builder selects the 26 Shuto route relations, adds only connected motorway
links, respects directed access, excludes abandoned and unavailable roads,
applies hash-bound facility exclusions, forward entry-boundary corrections,
and exact direction-reviewed candidate replacements,
matches every usable official IC and JCT, and fails on source or coverage drift.
