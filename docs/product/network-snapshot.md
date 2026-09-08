# Current network snapshot

The bundled network data and the operator facts it is joined to.

The bundled `2026-08-04` OSM geometry snapshot is joined to operator facts
checked on `2026-07-29`:

| Item | Bundled coverage |
|---|---:|
| Official route entries | 26 |
| Directed graph edges | 24,323 |
| IC names | 151 |
| Usable IC geometry matches | 148 / 148 |
| Official JCT matches | 39 / 39 |
| PA entries | 19 |
| PA entries a route can drive into | 1 / 19 |

The three IC names without routable geometry belong to the officially
unavailable, long-term-closed Yaesu Route. They remain visible as unavailable
facts and are never admitted to route search.

A PA entry is a labelled point unless a parking-access review has supplied
the interior the network build drops. The build excludes rest-area service
roads on purpose — one reaching the graph is indistinguishable from a
facility exit, and a PA ramp read as an exit invents fare paths — so the
interior comes back only for a parking area a route experience stops at,
as `PARKING` edges carrying no route membership. Daikoku PA is the one
reviewed so far; thirteen others have the same dead-ended access and return
ramps waiting for the same review.

Operator pages establish route names, IC direction availability, the current
JCT directory, and the PA directory. The pinned OpenStreetMap extract supplies
candidate geometry and topology. Each route's official direction vocabulary is
derived from those directional IC facts; exact reviewed movement definitions,
not incomplete OSM relation roles, bind that vocabulary to directed JCT edges.
Operator maps, junction images, and logos are not copied into the repository.
