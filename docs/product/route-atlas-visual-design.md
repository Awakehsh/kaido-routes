# Route Atlas visual design

Status: design contract; no real Shuto topology is released.

## Product role

The Route Atlas is the persistent driving instrument for the supported Shuto
network. It keeps the whole network in a stable north-up frame so the driver can
understand where the active route sits without replacing that context with a
rotating street basemap.

The atlas has one visual hierarchy:

1. the released network stays visible as quiet context;
2. route marks identify familiar corridors without copying operator artwork;
3. the active `RoutePlan` is the strongest line;
4. passed, current, future, and repeated occurrences remain distinct;
5. a current-position marker appears only with eligible route-bound evidence;
6. a local approach-aligned junction inset shows only the next reviewed
   decision and never replaces or rotates the atlas.

## Recognition reference

The pre-release design study may combine two non-navigable references:

- MLIT N06-2025 current-state geometry supplies the full-network geographic
  silhouette; and
- the current operator route-mark table supplies factual Japanese route names
  and route codes.

The references remain separate. A route mark may appear only when its operator
name has an explicit match to one MLIT context route and its anchor snaps to a
vertex of that matched route. The resulting layer is a recognition reference,
not selectable topology, direction, legal movement, or route authority.

The operator table reviewed on 2026-07-23 lists 26 route names. The MLIT source
contains 25 direct route-name matches plus feature 1414 / record
`EA02_373001`, whose 38-vertex Yokohama Kohoku-to-Aoba geometry is named
`高速横浜環状北西線`. A separate current operator page names that bounded
corridor `高速神奈川7号横浜北西線`. The catalog records this one explicit,
dated, checksummed reconciliation, allowing all 26 route names to appear
without inferring geometry from visual proximity.

The deterministic standalone output is
`data/route-atlas/design/shuto-route-atlas-recognition-reference.svg`. It is the
formal full-network recognition asset used by product concept and evidence
views: 86 retained source paths, 26 matched route identities, and 28 snapped
route-code marks in one fixed north-up frame. The file carries visible MLIT /
CC BY 4.0 attribution and explicit `REVIEW_ONLY` and
`navigation_authority=false` metadata. Tracking this artifact makes visual
drift reviewable; it does not promote context geometry into directed topology.

## Density

Phone and CarPlay overview states show route codes, not full road names. Japanese
road names remain available in pre-drive review and guidance sign targets.
Repeated marks may identify a long ring or bay corridor, but every repeated mark
must resolve to the same reviewed route entry.

Minor geographic detail, entrances, exits, lane diagrams, and evidence prose do
not compete with the full-network silhouette in the driving view.

## Visual language

- fixed north-up frame;
- one muted line family for inactive context;
- compact Kaido-owned route-code capsules, distinct from operator route-mark
  artwork;
- warm route color for the active plan only;
- cyan for an eligible measured position;
- coral for recovery or blocking states;
- no speed, lap-time, ranking, or racing language.

## Release gate

The recognition reference can be shown in a clearly labelled concept or
evidence view. It cannot unlock route selection, highlighting, positioning,
recovery, or guidance.

Those states still require one accepted `RouteAtlasRelease` bound to the exact
active network snapshot, directed topology, legal successors, reviewed layout,
and occurrence bindings. A coordinate crossing never establishes a connection.

The ODbL-isolated K7 directed candidate may appear only in an evidence view. Its
13 one-way route occurrences and two immediate divergence alternatives improve
auditability, but its `CANDIDATE` state cannot create active-route highlighting,
position, progress, recovery, or guidance. Raw source geometry is not the
released Kaido schematic.

The evidence view may report that all 14 source-adjacency checkpoints match, but
must separately show `LEGAL REVIEW INCOMPLETE`. At the Yokohama Kohoku surface
terminal it must disclose three source-adjacent motor-road ways, including the
unnamed OSM way `776884422`. Its corridor was officially identified as the
temporary passage at the 2020 opening. Yokohama now reports that surrounding
infrastructure work completed in March 2022 and the project ended in July 2023,
but the checked current page and final replotting map do not map the exact OSM
way to a current road identity, legal direction, or permitted movement. The UI
must not simplify this into two reviewed exits or display a production route
through the unresolved way.

## First schematic layout candidate

The first Kaido-owned normalized layout covers the complete bounded K7
expressway candidate from the Yokohama Aoba entrance through the Yokohama
Kohoku exit terminal. It expands both reviewed expressway divergences instead
of using the cramped raw source geometry. Every one of its 15 visible segments
binds one-to-one to one candidate topology edge; every successor set is copied
from that topology; and all 13 RoutePlan occurrences remain separately bound.

The layout stops at topology node `osm.node.7473451738`. It renders none of the
three adjacent surface ways `734299108`, `734299111`, or `776884422`. A terminal
bar communicates the evidence boundary without inventing a disconnected road
or implying that the drive must stop there. The generated SVG carries OpenStreetMap
attribution and remains `CANDIDATE`, non-selectable, and non-navigable.

KR-D24 proves that the schematic has no structural release issue beyond the
expected unreleased topology and layout evidence states. It advances production
layout review; it does not release the current surface movement, field evidence,
realtime state, or navigation authority.

## Current sources

- [Shuto Navi Map, current on 2026-07-01](https://www.shutoko.jp/use/network/navimap/)
- [Shuto route marks](https://www.shutoko.jp/use/convenience/infoboard/guidance/)
- [MLIT N06-2025 Highway Time Series](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N06-2025.html)
- [Yokohama Kawamuko Minamikochi current project status](https://www.city.yokohama.lg.jp/kurashi/machizukuri-kankyo/toshiseibi/jokyo/kukakuseiri/kawamukou/kawamukou.html)
- [Yokohama Kawamuko Minamikochi final replotting map](https://www.city.yokohama.lg.jp/kurashi/machizukuri-kankyo/toshiseibi/kukappi-/kubetsu/14-tsuzuki.files/0009_20230112.pdf)
- [Route Atlas geographic context provenance](../../data/route-atlas/context/README.md)
- [Full-network recognition reference](../../data/route-atlas/design/shuto-route-atlas-recognition-reference.svg)
- [OSM-derived K7 candidate provenance](../../data/route-atlas/osm-derived/README.md)
- [K7 schematic layout candidate](../../data/route-atlas/design/k7-northwest-up-schematic-layout-candidate.svg)
