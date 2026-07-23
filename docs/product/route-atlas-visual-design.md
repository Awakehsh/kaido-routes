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
unnamed OSM way `776884422`. Its corridor is officially identified as a 2020
land-readjustment temporary passage, while its 2026 physical status, legal
direction, and permitted movement remain unconfirmed. The UI must not simplify
this into two reviewed exits or display a production route through the
unresolved way.

## Current sources

- [Shuto Navi Map, current on 2026-07-01](https://www.shutoko.jp/use/network/navimap/)
- [Shuto route marks](https://www.shutoko.jp/use/convenience/infoboard/guidance/)
- [MLIT N06-2025 Highway Time Series](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N06-2025.html)
- [Route Atlas geographic context provenance](../../data/route-atlas/context/README.md)
- [OSM-derived K7 candidate provenance](../../data/route-atlas/osm-derived/README.md)
