# Route evidence and release gates

## Purpose

Community route recommendations are valuable discovery inputs, but a navigable
route is a safety-relevant data product. This process separates popularity from
verification.

## Evidence classes

| Class | Meaning | May drive navigation? |
|---|---|---|
| `SYNTHETIC` | Invented fixture for deterministic behavior tests | Test only |
| `COMMUNITY_CANDIDATE` | Blog, forum, video, or user suggestion | No |
| `OFFICIAL_CHECKED` | Current primary page, diagram, or reproducible official query checked | Only for the exact checked claim |
| `FIELD_CHECKED` | Passenger-observed or instrumented lawful field trace, with configuration recorded | After source and privacy review |
| `RELEASED` | Required fields passed current product review | Yes, within its snapshot and validity interval |
| `STALE_REVIEW_REQUIRED` | Review deadline or network change passed | No new navigation starts |

Popularity, repeated reposting, or an operator-branded old blog post does not
replace current topology validation.

## Minimum route record

A release candidate records:

- route ID and semantic version;
- network snapshot and effective interval;
- exact directional entrance and exit facilities;
- ordered edge, movement, and PA occurrences;
- Japanese sign targets and prompt anchors for critical movements;
- independently rendered junction-view path roles and left-indexed lane semantics,
  when a critical movement ships with an inset;
- external-network boundaries;
- actual-distance provenance;
- toll quote status, parameters, source, and checked date;
- planned-restriction check and real-time-data status;
- every source URI, licence class, reviewer, and review date;
- unresolved conflicts and next review deadline.

## Review gates

1. **Topology:** every occurrence resolves in the stated snapshot.
2. **Movement legality:** each incoming-to-outgoing transition has current
   primary or independently reviewed evidence.
3. **Sign guidance:** critical route shield and Japanese destination text are
   checked without copying protected artwork.
4. **Junction view:** normalized approach, selected, and alternative paths bind
   to the exact movement occurrence and snapshot; lane indices, route shields,
   Japanese sign text, checked date, and source references pass validation.
5. **PA semantics:** access and return direction are explicit; optional and
   required behavior are tested.
6. **Boundary:** accidental NEXCO or other toll-domain exits are flagged.
7. **Operations:** planned conflicts and lack of live confirmation are separate.
8. **Toll:** the product labels estimates and dated official-query results
   accurately; actual route distance remains separate.
9. **Safety:** difficulty and degraded-positioning behavior are reviewed.
10. **Freshness:** no relevant topology or access change occurred after review.

## Source retention

Store links, short original observations, query parameters, returned scalar
facts, and review metadata. Do not commit copied maps, route screenshots,
operator images, videos, or third-party article bodies. OSM-derived databases
require their own attribution and ODbL analysis.

Raw device traces contain personal location and configuration data. Keep
`MatcherPrivateTrace` values in ignored private storage and never commit them as
route evidence. A coordinate-free `MatcherCalibrationReport` may enter review
only after checking its opaque configuration scope and collection method. Its
statistical-floor status is matcher evidence, not `FIELD_CHECKED` route approval;
the underlying lawful run and independent annotation still require privacy and
source review.

Surface-road field review follows the same private-raw/public-claim boundary.
The [K7 Yokohama Kohoku plan](../testing/k7-yokohama-kohoku-surface-field-verification.md)
is the reference implementation: raw media and coordinates stay ignored,
tracked manifests contain only exact target identity, safe collection context,
hash bindings, concise findings, conclusions, reviewer, and validity. Passing
its validator closes one field-review gap; it never grants Route Atlas release
authority by itself.

## Contradiction handling

When sources disagree:

1. keep both claims and dates;
2. identify whether they refer to different directions, times, or snapshots;
3. prefer a current primary source for topology and operations;
4. block release if the safety-relevant conflict remains unresolved;
5. add a scenario when the contradiction exposes a reusable failure mode.
