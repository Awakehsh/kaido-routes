# Parking-area access — 2026-09-08

All 19 bundled PA interiors have reviewed directional paths. Seventeen have
executable Shuto entrance-to-PA-to-exit tests. Yoga and Ichikawa require
connecting-expressway entrances outside the supported graph.

The [source review](../../data/route-atlas/reviews/shuto-parking-access-review-20260908.json)
records exact way versions, node versions, ordered segments and operator page
references. The [candidate inventory](../../data/route-atlas/osm-derived/shuto-parking-access-candidates-20260908.json)
is historical discovery evidence, not an approved importer input. Nearby labels
alone do not establish direction: both Oi and Heiwajima searches can return
roads belonging to the other carriageway.

## Reproduction

Apply the 2026-09-07 Daikoku review and then the 2026-09-08 review to the
unaugmented 2026-08-04 database. The second review checks its exact input hash.
The [review instructions](../../data/route-atlas/reviews/README.md) describe the
source refresh and ODbL distribution. Raw operator images and map responses
remain outside tracked files.

## Selected paths

| PA / operator identity | Source ways in traversal order | Availability |
|---|---|---|
| [平和島PA（上り）](https://www.shutoko-sv.jp/pa/heiwajima-inbound) | [507859758](https://www.openstreetmap.org/way/507859758) → [853831007](https://www.openstreetmap.org/way/853831007) → [507859759](https://www.openstreetmap.org/way/507859759) → [507859762](https://www.openstreetmap.org/way/507859762) → [507859763](https://www.openstreetmap.org/way/507859763) → [507859760](https://www.openstreetmap.org/way/507859760) → [853831008](https://www.openstreetmap.org/way/853831008) | Complete Shuto entry / PA / exit path tested |
| [平和島PA（下り）](https://www.shutoko-sv.jp/pa/heiwajima-outbound) | [586347926](https://www.openstreetmap.org/way/586347926) | Complete Shuto entry / PA / exit path tested |
| [用賀PA](https://www.shutoko-sv.jp/pa/yoga) | [678426242](https://www.openstreetmap.org/way/678426242) → [678426243](https://www.openstreetmap.org/way/678426243) → [678426244](https://www.openstreetmap.org/way/678426244) | Interior modelled; connecting-expressway entrance unsupported |
| [永福PA](https://www.shutoko-sv.jp/pa/eifuku) | [1449651626](https://www.openstreetmap.org/way/1449651626) → [1449651625](https://www.openstreetmap.org/way/1449651625) → [27514034](https://www.openstreetmap.org/way/27514034) | Complete Shuto entry / PA / exit path tested |
| [代々木PA](https://www.shutoko-sv.jp/pa/yoyogi) | [107771259](https://www.openstreetmap.org/way/107771259) | Complete Shuto entry / PA / exit path tested |
| [志村PA](https://www.shutoko-sv.jp/pa/shimura) | [659036654](https://www.openstreetmap.org/way/659036654) → [1023392643](https://www.openstreetmap.org/way/1023392643) → [659036655](https://www.openstreetmap.org/way/659036655) | Complete Shuto entry / PA / exit path tested |
| [南池袋PA](https://www.shutoko-sv.jp/pa/minami-ikebukuro) | [292083252](https://www.openstreetmap.org/way/292083252) | Complete Shuto entry / PA / exit path tested |
| [箱崎PA](https://www.shutoko-sv.jp/pa/hakozaki) | [263330206](https://www.openstreetmap.org/way/263330206) → [633246923](https://www.openstreetmap.org/way/633246923) → [263330211](https://www.openstreetmap.org/way/263330211) | Complete Shuto entry / PA / exit path tested |
| [駒形PA](https://www.shutoko-sv.jp/pa/komagata) | [154971211](https://www.openstreetmap.org/way/154971211) | Complete Shuto entry / PA / exit path tested |
| [加平PA](https://www.shutoko-sv.jp/pa/kahei) | [250488079](https://www.openstreetmap.org/way/250488079) | Complete Shuto entry / PA / exit path tested |
| [八潮PA](https://www.shutoko-sv.jp/pa/yashio) | [288901861](https://www.openstreetmap.org/way/288901861) | Complete Shuto entry / PA / exit path tested |
| [辰巳第一PA](https://www.shutoko-sv.jp/pa/tatsumi-1) | [809137047](https://www.openstreetmap.org/way/809137047) → [376496465](https://www.openstreetmap.org/way/376496465) | Complete Shuto entry / PA / exit path tested |
| [辰巳第二PA](https://www.shutoko-sv.jp/pa/tatsumi-2) | [809140340](https://www.openstreetmap.org/way/809140340) → [376509517](https://www.openstreetmap.org/way/376509517) | Complete Shuto entry / PA / exit path tested |
| [芝浦PA](https://www.shutoko-sv.jp/pa/shibaura) | [4848741](https://www.openstreetmap.org/way/4848741) → [820360944](https://www.openstreetmap.org/way/820360944) → [45067778](https://www.openstreetmap.org/way/45067778) → [45067779](https://www.openstreetmap.org/way/45067779) → [820360945](https://www.openstreetmap.org/way/820360945) | Complete Shuto entry / PA / exit path tested |
| [市川PA](https://www.shutoko-sv.jp/pa/ichikawa) | [25823832](https://www.openstreetmap.org/way/25823832) | Interior modelled; connecting-expressway entrance unsupported |
| [大井PA（西行き）](https://www.shutoko-sv.jp/pa/oi-westbound) | [675182036](https://www.openstreetmap.org/way/675182036) | Complete Shuto entry / PA / exit path tested |
| [大井PA（東行き）](https://www.shutoko-sv.jp/pa/oi-eastbound) | [675182035](https://www.openstreetmap.org/way/675182035) → [675182038](https://www.openstreetmap.org/way/675182038) | Complete Shuto entry / PA / exit path tested |
| [川口ハイウェイオアシス](https://www.shutoko-sv.jp/pa/kawaguchi) | [1299417625](https://www.openstreetmap.org/way/1299417625) → [687045302](https://www.openstreetmap.org/way/687045302) → [44351819](https://www.openstreetmap.org/way/44351819) | Complete Shuto entry / PA / exit path tested |

## Delivered modelling

- All 19 PAs have exact ordered parking edges without route membership. The 18 newly reviewed paths add 250 edges net, for 24,573 total graph edges.
- A PA anchor explicitly appends its whole reviewed path and resumes from the return node. Ordinary route searches do not take parking interiors as shortcuts. Tatsumi first preserves a repeated source segment as separate route occurrences.
- Minami-Ikebukuro and Ichikawa reuse and classify existing interior links. Their shared approach and return roads retain their original role. Ichikawa's point is corrected from its named OSM PA polygon.
- Oi eastbound's missing mainline way 1059139534 is restored from dated OSM geometry and retains B membership. Both newly reachable Oi JCT choices are bound to the operator diagram whose SHA-256 is `4bfe3cb6117273ec547a62872b971a87fcc944fff70b3267022888612aacfc2b`, fetched and visually reviewed on 2026-09-08.
- Every selected way and node version predates the 2026-08-04 extract. This is an explicit hash-bound supplement to that snapshot; no current opening or field-reliability claim is added.

## Executable availability boundary

The real circuit planner traverses the complete reviewed paths for 17 PAs,
including approach from the Bayshore for Tatsumi first/second and continuation
onto C1 after Shibaura. Yoga and Ichikawa precede the first supported inbound
Shuto entrance: their interiors exist, but a stop from a supported Shuto entry
is unavailable. Their tests require explicit rejection instead of inventing
an entrance on the connecting expressway.

Default route recipes retain their existing stops. Modelling a PA does not
silently add a stop to every route that passes it, or enroll arbitrary routes
for live navigation. Route cards continue to advertise only actual stops. Journey review now offers
optional PA stops whose directed local access and return fit the selected route;
added stops are visited on the first pass and retained in saved routes.

The deferred recovery-candidate ordering and Ohashi JCT issue remain outside
this work. Product releases and bundle hashes are rebuilt from the updated
network; synthetic/runtime checks are distinct from field evidence.

## Verification on 2026-09-08

- Swift core: 556 tests passed, including all 19 PA cases and repeated-lap visits.
- Portable E2E: 73 scenarios and 517 assertions passed; schema validation passed.
- Python: 258 tests and facility-candidate review verification passed.
- Live source refresh reproduces the review bytes; replaying the two reviews
  reproduces the distributed database bytes. All five rebuilt foreground
  products and the retained joint-release fixture passed validation.
- iPhone 17 Pro / iOS 26.5 Simulator: the initial full run passed 368 of 371
  tests. Two existing UI assertions were repaired by the concurrent main-branch
  update; the saved-route test now submits through the keyboard action instead
  of an English button label. The final affected set passed all seven tests,
  with no skips or expected failures.
- Physical iPhone: Debug signing/build verification passed; after unlocking,
  installation and foreground launch succeeded. Device process inspection
  confirmed the launched executable belongs to the just-installed App. Its
  bundled database exactly matches the repository with 19 PA interiors and
  SHA-256 `c4602ba48c84dcf3305775d335d2be7438c4ba284cb8111b32ebeb764fd7a2b3`.
  This proves device deployment and startup, not road/field reliability.
