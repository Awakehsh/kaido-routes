# Route Atlas visual design

Status: design contract; no real Shuto topology is released.

## Product role

The Route Atlas is the rectilinear topology projection of the supported Shuto
network. It is not a static recognition image and it is not restricted to
parked planning. One map control lets the user switch between this projection
and a provider-backed geographic projection while planning or driving. The
selected projection persists until the user changes it.

The topology layout favors horizontal, vertical, and 45-degree segments with
consistent spacing. It may distort geographic distance and curvature to make
route relationships, junctions, and directional facilities legible. It does
not distort directed connectivity, facility direction, route occurrence order,
or the relative recognition structure of the released network.

The atlas has one visual hierarchy:

1. the released network stays visible as quiet context;
2. route marks identify familiar corridors without copying operator artwork;
3. the active `RoutePlan` is the strongest line;
4. directional IC, JCT, and PA values appear only at a useful scale;
5. passed, current, future, and repeated occurrences remain distinct;
6. a current-position marker appears only with eligible route-bound evidence;
7. a local approach-aligned junction inset shows only the next reviewed
   decision and never authors or changes the route.

The geographic map may show local roads, the reviewed surface leg, the current
position, and the active route geometry. The topology map may show the same
eligible current position projected onto the exact route occurrence. Its marker
communicates route position and confidence rather than precise coordinates.
Neither projection can infer or mutate an entrance, JCT movement, PA access,
exit, or RoutePlan occurrence.

## Interaction and semantic zoom

The topology projection supports pinch zoom, pan, explicit zoom controls, reset
to route, and accessible list alternatives in both parked and driving contexts.
Zoom changes the information layer, not only the pixel scale:

- **Network:** route codes, major JCTs, current origin area, and the selected
  route family.
- **Corridor:** all reviewed JCTs, compatible directional IC facilities,
  directional PAs, and the exact highlighted route.
- **Facility:** entrance or exit direction, facility number, ETC constraint,
  legal join or leave movement, JCT branch choices, and PA access/return
  direction.

Selecting a route segment explains it without changing the route. Selecting a
JCT or facility submits only a stable reviewed choice to the route editor. The
map cannot snap a gesture directly into an unreviewed movement. When the visual
surface becomes crowded, labels yield to the selected route and the next action;
the same values remain available in the accessible route list.

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

The network scale shows route codes, not every facility label. Japanese road
names remain available in route detail, pre-drive review, and guidance sign
targets. Repeated marks may identify a long ring or bay corridor, but every
repeated mark must resolve to the same reviewed route entry.

IC, JCT, and PA values appear progressively at corridor and facility scales.
Lane diagrams appear only for the next reviewed driving decision. Evidence
prose and implementation identifiers never compete with the map; concise
availability or uncertainty states link to a separate evidence detail.

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

## Released journey overlay

`RouteAtlasJourneyProjector` is the implemented renderer-neutral boundary
between one accepted `RouteAtlasRelease` and a phone presentation. Before a
navigation actor exists, it projects every exact RoutePlan occurrence as
`PLANNED`. After activation, it accepts only the exact actor-owned
`NavigationSnapshot` partition and projects `PASSED`, `CURRENT`, `FUTURE`, and
`SKIPPED`. Unknown, duplicated, reordered, or mismatched occurrence progress
blocks the projection.

The projection carries all released layout segments as quiet context and a
separate ordered occurrence value for every RoutePlan binding. Multiple
occurrences may therefore reference the same schematic segment; the renderer
offsets those traversals and exposes their ordinal and count instead of
deduplicating them. Context-only segments never receive an occurrence state.
Source and licence attribution remains adjacent to the rendered atlas.

This overlay is a route cursor, not a vehicle bead. It does not consume a
coordinate, infer along-route progress, or claim measured position. A position
marker remains subject to the independent fresh route-resolved evidence gate.
KR-U17 exercises the projection with synthetic released flags, including a
repeated segment and a context-only branch. The iPhone preview and its
XCUITest render that synthetic proof; no real Shuto atlas or road is released.

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
and a dated 2026-07-25 online map-66 inspection displays the exact southern
feature as `東方町第356号線`. Yokohama states that the online map is not proof,
so the result is a counter locator rather than a current legal-record, legal-
direction, or permitted-movement finding. The UI must not simplify this into
two reviewed exits or display a production route through the unresolved way.

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

The first K7 product scope may therefore end at this terminal as an
`EXIT_HANDOFF_ONLY_ROUTE_ATLAS_CANDIDATE`. In that scope, the terminal RoutePlan
occurrence and boundary bar are inside the candidate, while all three ordinary-
road successors and `SURFACE_EGRESS` are outside it. The unresolved identity and
field review for way `776884422` remain visible future-expansion gates; they are
not treated as satisfied and cannot be reused as evidence for a later surface
route. Topology and layout still require their own independent release reviews.

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
