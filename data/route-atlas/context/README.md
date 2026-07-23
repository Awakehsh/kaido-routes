# Route Atlas geographic context data

This directory isolates non-authoritative geographic context used to help a
driver recognize the overall Shuto network shape. It is not a directed road
graph and cannot authorize route selection, occurrence progress, junction
movement, recovery, or navigation.

## N06-2025 current-state artifact

`mlit-n06-2025-current-shuto-context.json` is generated from the current-state
slice of Japan's National Land Numerical Information Highway Time Series
dataset. The generator:

1. verifies the downloaded ZIP against the separately reviewed SHA-256 in
   `mlit-n06-2025-current-source.json`;
2. selects records with `N06_003 == 9999`, `N06_008 == 5`, and a Japanese
   route name beginning with `首都高速`;
3. accepts use status `1` (complete) and `2` (provisional);
4. preserves every selected feature, multiline part, and source vertex;
5. verifies the declared JGD2011 `EPSG:6668` source CRS and applies one north-up
   local equirectangular transform with uniform scale; and
6. emits `navigation_role: CONTEXT_ONLY`.

No geometry simplification, hand redrawing, inferred connection, inferred
direction, inferred JCT movement, route shield, or localized road label is
introduced.

The 25 unique Japanese strings in the context artifact are source properties,
not current display-label authority. The operator's current route-mark table
lists 26 route names and separately identifies `高速神奈川7号横浜北西線`, while
N06-2025 does not expose that name as a separate selected value. This naming
mismatch blocks route shields and labels and does not, by itself, establish
whether the corresponding geometry is present or absent.

The source reference date is 2025-12-31. Operator material dated after that date
must be reviewed separately before a navigable Kaido topology release can claim
current coverage. The context artifact remains non-navigable even after such a
review. `operator-currentness-review-2026-07-01.json` records the later operator
map reference, the exact externally reviewed asset checksum, and the blockers
that remain. The operator image itself is not retained or redistributed.

## Licence and attribution

Source: [National Land Numerical Information Highway Time Series
N06-2025](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N06-2025.html),
Ministry of Land, Infrastructure, Transport and Tourism of Japan.

The selected current-state data is used under CC BY 4.0. Kaido Routes modified
the source as described above. The repository's Apache-2.0 licence does not
replace the source-data terms. The raw source archive is not redistributed in
this repository.

## Rebuild

```sh
python3 scripts/build_mlit_route_atlas_context.py \
  --archive /path/to/N06-25_GML.zip \
  --source data/route-atlas/context/mlit-n06-2025-current-source.json \
  --output data/route-atlas/context/mlit-n06-2025-current-shuto-context.json
```
