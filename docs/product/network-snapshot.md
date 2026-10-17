# Current network snapshot

The bundled network data and the operator facts it is joined to.

The bundled `2026-08-04` OSM geometry snapshot is joined to operator facts
checked on `2026-07-29`:

| Item | Bundled coverage |
|---|---:|
| Official route entries | 26 |
| Directed graph edges | 24,549 |
| IC entries | 152 |
| Usable IC geometry matches | 147 / 148 |
| Official JCT matches | 39 / 39 |
| PA entries | 19 |
| Source-reviewed PA interiors | 19 / 19 |
| PA stops with supported Shuto entrance/exit tests | 17 / 19 |

Four unavailable IC entries have no routable geometry: the three of the
long-term-closed Yaesu Route, and the abolished 新富町 exit. They remain
visible as unavailable facts and are never admitted to route search. The one
available IC without a ramp of its own is the 横浜港北 entry listed under
横浜北西線: the interchange's ramps belong to 横浜北線 and bind that route's twin,
which pairs with the whole network.

The [facility candidate patch](../../data/route-atlas/reviews/README.md) of
2026-09-14 re-points nine facilities the builder had bound to the wrong ramp
(豊洲, 五反田, 加賀, 東領家, 浅田, 浦和南 exits; 与野 entrance; 新都心's split
ramps; 八潮's outbound exit) and unbinds that twin. Before it, each of them
paired with nothing but itself; after it, each pairs with the network like its
neighbours, and a planner test keeps every bound facility paired with a
differently named counterpart.

The [facility closure review](../../data/route-atlas/reviews/README.md) of
2026-10-12 applies the operator's notice of 2026-07-17 for C1 from 2026-10-18
23:00: the 新富町 exit is abolished in both directions, and the 内回り 銀座
entrance closes for about three years (planned until 2029). 新富町 is
unavailable, its ramp is unbound from 宝町, 京橋 and 銀座, which had it as a
nearby exit candidate, and 銀座 is entered only toward 外回り. The snapshot has
no dated availability, so both closures hold for the bundled data as a whole.

The [topology review](../../data/route-atlas/reviews/README.md) of 2026-10-12
repairs graph defects the builder's rules introduced. Route 1 Haneda
southbound stopped for 1.8 km because its 2025-10-29 rebuilt section was
never added to the route relation, and K3 began from nothing at 本牧JCT;
both carriageways are restored from the OSM ways current at the extract. Three
construction structures the builder admitted as motorway are removed. At ten
interchanges (天現寺, 東池袋, 木場, 船堀橋, 錦糸町, 永田, 堤通, 新郷, 羽田, 大師) OSM
draws the exit and the entrance as one link chain across the surface road;
the review cuts the chain at the surface crossing, so a route or fare path
can no longer leave the expressway and come straight back on. The restored K3
start adds two 本牧JCT movements with no reviewed guidance yet; a route through
them builds no foreground product until they are reviewed.

The [facility candidate patch](../../data/route-atlas/reviews/README.md) of
2026-10-12 re-derives every facility's ramps. The builder had bound every edge
of the facility's route within 750 m, so 613 of 1,376 candidates sat more than
200 m away and interchanges started or ended on a neighbour's ramp, the
opposite direction's ramp, a PA return ramp, bare carriageway, or a connecting
expressway's link. Each ramp now binds at most one interchange name: 753
candidates, 30 of them beyond 400 m with a reviewed reason. The patch adds the
東銀座 exit (外回り), which the operator lists and the KK line closure kept
open, and drops two stray nodes that a name-substring match had added to
大橋JCT, which had moved its point 4.8 km. Two interchanges keep ramps the
first derivation missed, bound on 2026-10-17 from ja.wikipedia and NAVITIME's
per-direction interchange lists: 扇大橋's 外回り exit and 内回り entrance are
on S1, either side of 江北JCT (the exit had been dropped as another
interchange's ramp, so 鹿浜橋 to 扇大橋 priced 1,290 yen instead of 300), and
浦安's 東行き entrance and 西行き exit sit at its second ramp site 1.9 km from
the operator point (浦安 to 千鳥町 priced 1,270 yen instead of 340).
`scripts/audit_shuto_network.py`
fails CI if a carriageway ends or starts outside a listed terminus, a ramp is
bound to two interchanges, a candidate exceeds the limit without a reviewed
exception, or an exit ramp runs on to another interchange's exit.

Fare search and pairing treat the interchanges the operator bills together
as one toll point, as they do same-named ramps: 王子南 and 王子北; 箱崎, 浜町 and 清洲橋;
大井南 and 中環大井南. Each name has its own ramp, and 王子南's leads away from
most of the network, so pricing it alone sent fare paths round the C2 loop.

Against the operator's 2026-10 fare and distance table (not distributed here),
over the 16,798 pairings the app may quote, fares now come out more than
100 yen off for 10.5% (21.0% of 16,669 before this change) and more than
500 yen off for 0.6% (6.5%); none is falsely quoted at the minimum (16
before) and 52 at the cap (321). Known residuals: C1 内回り has no link to
Route 1 and Route 11 at 浜崎橋 (芝公園 to 平和島 measures about twice the
operator's distance); and the directions the operator lists without a ramp
in the snapshot stay unbound rather than borrowing a neighbour's: 新都心西 下り
entrance, and 横浜港北 (横浜北線) 下り entrance and 上り exit.

加賀 to 東領家 is a recorded restriction, not a gap: 東領家's exit (OSM way
563799388) leaves S1 上り at the junction node named 東領家, and 加賀's 上り
entrance (ways 1023900268, 633246083, 28188014) runs alongside and joins the
carriageway (way 438367463) about 100 m after that split. The snapshot and
the OSM ways current on 2026-10-17 agree, so the pair has no drivable path
and is not planned, although the operator's fare table still prices it at
the minimum.

All PA interiors are bound to exact ordered source segments as `PARKING`
edges with no route membership. Route planning traverses an explicitly requested
PA path in full; ordinary route searches cannot use it as a shortcut. Fare
searches keep the interiors, and only 大黒PA's ever carries a fare path. A
turn-back pairing, whose entrance heads away from its exit, has to turn round
somewhere; the operator's fare distances for such pairings around 横羽線 and
大黒線 match a turnaround inside 大黒PA (浅田 to 大師 is 21.1 km here through
the PA, 25.8 km without it, and the operator's distance agrees with the
former within 0.5 km). Removing the PA from fare search moved more pairings
away from the operator's fares than toward them. No other PA changes any
pairing's fare path.
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
Third-party direction names can differ: NAVITIME calls K6's 大師-bound
carriageway 上り, while the catalog follows the operator, whose K6 上り runs
toward the route's 起点, 川崎浮島JCT.
Operator maps, junction images, and logos are not copied into the repository.
