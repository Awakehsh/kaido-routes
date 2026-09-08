# Current network snapshot

The bundled network data and the operator facts it is joined to.

The bundled `2026-08-04` OSM geometry snapshot is joined to operator facts
checked on `2026-07-29`:

| Item | Bundled coverage |
|---|---:|
| Official route entries | 26 |
| Directed graph edges | 24,573 |
| IC names | 151 |
| Usable IC geometry matches | 148 / 148 |
| Official JCT matches | 39 / 39 |
| PA entries | 19 |
| Source-reviewed PA interiors | 19 / 19 |
| PA stops with supported Shuto entrance/exit tests | 17 / 19 |

The three IC names without routable geometry belong to the officially
unavailable, long-term-closed Yaesu Route. They remain visible as unavailable
facts and are never admitted to route search.

All PA interiors are bound to exact ordered source segments as `PARKING`
edges with no route membership. Route planning traverses an explicitly requested
PA path in full; ordinary route and fare searches cannot use it as a shortcut.
The [parking-area source review](parking-area-access-review.md) records the
multi-way paths, reused interior links, and dated Oi eastbound mainline repair.
Yoga and Ichikawa require arrival from connecting expressways before the first
supported inbound Shuto entrance, so those entrance-to-PA pairings remain
explicitly unavailable. Default route recipes keep their existing stops.

Operator pages establish route names, IC direction availability, the current
JCT directory, and the PA directory. The pinned OpenStreetMap extract supplies
candidate geometry and topology. Each route's official direction vocabulary is
derived from those directional IC facts; exact reviewed movement definitions,
not incomplete OSM relation roles, bind that vocabulary to directed JCT edges.
Operator maps, junction images, and logos are not copied into the repository.
