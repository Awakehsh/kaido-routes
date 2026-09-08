# Parking-area access review — 2026-09-08

Status: **candidate investigation complete; no additional PA is approved or released**.

This follows the local `handoffs/parking-area-modelling/2026-09-08-remaining-parking-areas.md`. Its table contains 12 unmodelled “ready” PAs and six investigation PAs, plus Daikoku; the headings miscount them. Its dead-end-only mechanism does not cover the actual graph.

## Evidence and reproduction

The read used snapshot `shuto-official-2026-07-29-osm-2026-08-04`, SHA-256 `831a162e7260447fc130dcf0dc4d3e4b39cd2f5d3c5ae19d6197f29e813d4c26`. These are the local inherited Daikoku-overlay bytes, not the clean ancestor `adc1086`. The original checkout and its uncommitted delivery work were preserved. No additional parking geometry was applied.

The coordinate-free [candidate inventory](../../data/route-atlas/osm-derived/shuto-parking-access-candidates-20260908.json) records source URLs and hashes, way versions/timestamps, ordered segments, nearby named OSM PA polygons, and whether a node-only stop can bypass the PA. It is deliberately not importer input. Current OSM readings do not establish that every way/node version existed in the historical extract.

```sh
python3 scripts/audit_parking_area_access.py \
  --network data/route-atlas/osm-derived/shuto-whole-network-20260804.json \
  --cache-dir /tmp/kaido-pa-review \
  --output /tmp/kaido-pa-review.json --read-at <actual-read-time>
```

The live read is bounded; its shortest paths are candidates, not an exhaustive lane inventory. Use `--offline` only with retained payloads from the stated read time. Raw OSM map payloads and geometry plots remain outside tracked files.

## Review each PA

A reviewer must confirm the exact access, parking path and return for the stated direction using the linked operator identity and OSM way evidence. The OSM polygon name is a useful cross-check, not legal or field verification.

| PA / operator identity | Candidate way IDs (ordered) | Finding / required decision |
|---|---|---|
| [平和島PA（上り）](https://www.shutoko-sv.jp/pa/heiwajima-inbound) | [507859758](https://www.openstreetmap.org/way/507859758) → [853831007](https://www.openstreetmap.org/way/853831007) → [507859759](https://www.openstreetmap.org/way/507859759) → [507859762](https://www.openstreetmap.org/way/507859762) → [507859763](https://www.openstreetmap.org/way/507859763) → [507859760](https://www.openstreetmap.org/way/507859760) → [853831008](https://www.openstreetmap.org/way/853831008)<br>[586347926](https://www.openstreetmap.org/way/586347926) | Seven-way candidate intersects the inbound OSM PA polygon; the other candidate intersects the outbound polygon. The access node has an onward bypass. |
| [平和島PA（下り）](https://www.shutoko-sv.jp/pa/heiwajima-outbound) | [507859758](https://www.openstreetmap.org/way/507859758) → [853831007](https://www.openstreetmap.org/way/853831007) → [507859759](https://www.openstreetmap.org/way/507859759) → [507859762](https://www.openstreetmap.org/way/507859762) → [507859763](https://www.openstreetmap.org/way/507859763) → [507859760](https://www.openstreetmap.org/way/507859760) → [853831008](https://www.openstreetmap.org/way/853831008)<br>[586347926](https://www.openstreetmap.org/way/586347926) | Way 586347926 intersects the outbound OSM PA polygon. Do not select the seven-way inbound candidate by proximity. The access node has an onward bypass. |
| [用賀PA（上り）](https://www.shutoko-sv.jp/pa/yoga) | [678426242](https://www.openstreetmap.org/way/678426242) → [678426243](https://www.openstreetmap.org/way/678426243) → [678426244](https://www.openstreetmap.org/way/678426244) | Three service ways connect existing through nodes, not dead ends. A node anchor alone can skip the PA. |
| [永福PA（上り）](https://www.shutoko-sv.jp/pa/eifuku) | [1449651626](https://www.openstreetmap.org/way/1449651626) → [1449651625](https://www.openstreetmap.org/way/1449651625) → [27514034](https://www.openstreetmap.org/way/27514034) | Three service ways connect a through ramp. A node anchor alone can skip the PA. |
| [代々木PA（上り）](https://www.shutoko-sv.jp/pa/yoyogi) | [107771259](https://www.openstreetmap.org/way/107771259) | Single service-way candidate; exact identity, direction, and historical geometry still require review. |
| [志村PA（上り）](https://www.shutoko-sv.jp/pa/shimura) | [659036654](https://www.openstreetmap.org/way/659036654) → [1023392643](https://www.openstreetmap.org/way/1023392643) → [659036655](https://www.openstreetmap.org/way/659036655) | Three service ways connect mainline nodes. A node anchor alone can skip the PA. |
| [南池袋PA（上り）](https://www.shutoko-sv.jp/pa/minami-ikebukuro) | No new connected path in the original bounded read | Named motorway_link 292083252 is already present with Route 5 membership. This needs PA binding/classification review, not a fabricated interior. |
| [箱崎PA](https://www.shutoko-sv.jp/pa/hakozaki) | [263330206](https://www.openstreetmap.org/way/263330206) → [633246923](https://www.openstreetmap.org/way/633246923) → [263330211](https://www.openstreetmap.org/way/263330211) | Candidate traverses the named OSM PA polygon. A separate nearby service chain contains private access and is excluded. The rotary access node is not a dead end. |
| [駒形PA（上り）](https://www.shutoko-sv.jp/pa/komagata) | [154971211](https://www.openstreetmap.org/way/154971211) | Service way 154971211 begins on a mainline through node and rejoins an existing link. No missing half needs to be synthesized. |
| [加平PA（下り）](https://www.shutoko-sv.jp/pa/kahei) | [250488079](https://www.openstreetmap.org/way/250488079) | Single service-way candidate intersects the outbound PA polygon. Neighboring facility dead ends are not evidence for this PA. |
| [八潮PA（上り）](https://www.shutoko-sv.jp/pa/yashio) | [288901861](https://www.openstreetmap.org/way/288901861) → [288901862](https://www.openstreetmap.org/way/288901862) | The shortest candidate uses segments of two parking aisles; the old reader chooses one whole way. Select an explicit reviewed path, not every aisle. |
| [辰巳第一PA（上り）](https://www.shutoko-sv.jp/pa/tatsumi-1) | [809137047](https://www.openstreetmap.org/way/809137047) | Way 809137047 is a connected candidate, but the bounded read supplies no matching named rest-area polygon along it. Identity remains unresolved. |
| [辰巳第二PA（上り）](https://www.shutoko-sv.jp/pa/tatsumi-2) | [809137047](https://www.openstreetmap.org/way/809137047)<br>[809140340](https://www.openstreetmap.org/way/809140340) → [376509517](https://www.openstreetmap.org/way/376509517) | The two-way-ID chain intersects the second PA polygon. The neighboring first-PA candidate must not be selected for the second PA. |
| [芝浦PA（上り）](https://www.shutoko-sv.jp/pa/shibaura) | [4848741](https://www.openstreetmap.org/way/4848741) → [820360944](https://www.openstreetmap.org/way/820360944) → [45067778](https://www.openstreetmap.org/way/45067778) → [45067779](https://www.openstreetmap.org/way/45067779) → [820360945](https://www.openstreetmap.org/way/820360945) | Five service ways connect through nodes and intersect the PA polygon. A node anchor alone can skip the PA. |
| [市川PA（西行き）](https://www.shutoko-sv.jp/pa/ichikawa) | No new connected path in the original bounded read | The snapshot label is about 720 m west of the OSM PA polygon (way 585560634), outside the original search box. An expanded read finds existing motorway links 46897953, 25823832, 25823833 and 1133924269. Review the coordinate and exact PA segment binding; the empty original search does not establish missing roads. |
| [大井PA（西行き）](https://www.shutoko-sv.jp/pa/oi-westbound) | [675182036](https://www.openstreetmap.org/way/675182036) | Way 675182036 intersects the westbound PA polygon. Its proximity to the eastbound label does not make it eastbound. |
| [大井PA（東行き）](https://www.shutoko-sv.jp/pa/oi-eastbound) | [675182036](https://www.openstreetmap.org/way/675182036) | The only complete bounded candidate is WESTBOUND and must be rejected for this PA. Actual eastbound service way 675182035 continues through missing link 675182038 to node 4157120422 on motorway way 1059139534, which is absent from the snapshot. This is a mainline coverage issue, not an interior-only overlay. |
| [川口PA（上り）（川口ハイウェイオアシス）](https://www.shutoko-sv.jp/pa/kawaguchi) | [1299417625](https://www.openstreetmap.org/way/1299417625) → [687045302](https://www.openstreetmap.org/way/687045302) → [44351819](https://www.openstreetmap.org/way/44351819) | Three service ways connect the dead ends and intersect the PA polygon; the single-way reader cannot represent them. |

## Implementation required after identity review

- Extend the interior review/importer to ordered multi-way segments, retaining original segment indices and evidence; do not flatten them into an invented OSM way.
- Make a requested stop traverse the complete reviewed PA path explicitly. Several valid access nodes also lead onward without entering the PA, so the inherited access-node anchor is insufficient.
- Bind existing PA links only after auditing their route/fare use. Do not remove route membership from shared approach or return roads just because they touch a PA polygon.
- Resolve Oi eastbound mainline coverage and Ichikawa position/binding from source evidence before claiming those stops. Do not invent missing mainline geometry.
- After applying approved changes, rebuild affected releases, refresh bundled hashes, and run the handoff core/scenario/App/device checks. None of those runtime checks was performed for this candidate-only audit.

The deferred recovery-candidate ordering and Ohashi JCT issue remain outside this work.

## Required human checkpoint

The handoff explicitly says each candidate “still needs a human to confirm the service way is the parking area and not an adjacent depot road or a surface interchange.” No human sign-off is recorded here. The review must identify approved paths and direction for each PA; a general code-test pass cannot supply it.

## Verification

The audit CLI read all 18 remaining PAs from the captured live OSM responses and emitted 19 unapproved path candidates. Six deterministic tests cover multi-way through-node paths, restricted/reverse/missing returns, existing PA links, ambiguous alternatives and polygon evidence without approval. This audit changes no App or navigation runtime behavior.
