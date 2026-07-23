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
2. selects records with `N06_003 == 9999`, `N06_008 == 5`, and either a
   Japanese route name beginning with `首都高速` or the separately reconciled
   `高速横浜環状北西線`;
3. accepts use status `1` (complete) and `2` (provisional);
4. preserves every selected feature, multiline part, and source vertex;
5. verifies the declared JGD2011 `EPSG:6668` source CRS and applies one north-up
   local equirectangular transform with uniform scale; and
6. emits `navigation_role: CONTEXT_ONLY`.

No geometry simplification, hand redrawing, inferred connection, inferred
direction, inferred JCT movement, route shield, or localized road label is
introduced.

The 26 unique Japanese strings in the context artifact are source properties,
not current display-label authority. N06-2025 feature 1414 / record
`EA02_373001` names its 38-vertex Yokohama Kohoku-to-Aoba geometry
`高速横浜環状北西線`. The operator's current route page names that same bounded
corridor `高速神奈川7号横浜北西線`. The recognition catalog records this one
dated, checksummed naming reconciliation explicitly; no prefix filter or visual
proximity may silently create the mapping.

The source reference date is 2025-12-31. Operator material dated after that date
must be reviewed separately before a navigable Kaido topology release can claim
current coverage. The context artifact remains non-navigable even after such a
review. `operator-currentness-review-2026-07-01.json` records the later operator
map reference, the exact externally reviewed asset checksum, and the blockers
that remain. The operator image itself is not retained or redistributed.

## Route-mark recognition reference

`operator-route-mark-catalog-2026-07-23.json` records the 26 factual Japanese
route names and route codes reviewed on the operator's route-mark page. It does
not contain or reproduce operator route-mark artwork.

The separate
`../design/route-mark-layout-prototype.json` places a Kaido-owned code capsule
only after:

1. one operator route entry explicitly matches one N06 context route name;
2. the mark anchor snaps to a retained vertex of that matched source route; and
3. every matched context route is represented; and
4. the one K7 Northwest naming reconciliation resolves the exact MLIT feature
   and record plus a dated, checksummed current operator page.

The current result represents all 26 operator route names. It remains a
`REVIEW_ONLY` recognition reference and cannot authorize selection, direction,
connectivity, position, or navigation.

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

Render the non-navigable recognition design:

```sh
python3 scripts/render_route_atlas_design_svg.py \
  --context data/route-atlas/context/mlit-n06-2025-current-shuto-context.json \
  --source data/route-atlas/context/mlit-n06-2025-current-source.json \
  --route-catalog data/route-atlas/context/operator-route-mark-catalog-2026-07-23.json \
  --route-mark-layout data/route-atlas/design/route-mark-layout-prototype.json \
  --output /tmp/kaido-route-atlas-design.svg
```
