# Licensing and public-repository boundaries

Kaido Routes is an open-source project under the Apache License 2.0.

## Project-authored material

Unless a path says otherwise, project-authored code and documentation in this
repository are licensed under the root [Apache License 2.0](../../LICENSE). The
licence permits commercial and noncommercial use, modification, and distribution
subject to its conditions, and includes an express patent grant from
contributors for applicable patent claims.

Unless explicitly marked otherwise, a contribution intentionally submitted for
inclusion is offered under Apache-2.0 as described by section 5 of the licence. A
contributor must have the right to submit the work and must not copy incompatible
code, data, images, maps, or text into a contribution.

## Material the root licence does not relicense

The root licence cannot change the terms of third-party material. Any releasable
third-party dependency, data subset, or asset must have a clear source,
provenance record, and applicable licence notice. In particular:

- OSM-derived databases require a deliberate ODbL and attribution plan;
- operator maps, JCT images, videos, logos, and copied site design are not part
  of the public repository;
- mew-ti and JARTIC payloads require appropriate permission before retention or
  redistribution;
- raw articles, screenshots, provider responses, and personal field traces stay
  outside the repository unless a specific review permits a derived fixture.

The ignored `research/` directory is never covered merely because it exists next
to the repository. Verified conclusions must be rewritten into project-authored
contracts or evidence records without copying restricted source material.

## OSM road-data product boundary

OpenStreetMap data is available under ODbL 1.0, including commercial use, with
attribution and share-alike obligations for the database and derivative
databases. Apache-2.0 continues to cover Kaido's source code, schemas, and
project-authored documentation; it does not relicense an extracted or transformed
OSM road graph.

Before an OSM-derived graph is distributed, it needs a separately identified
data boundary with:

- an ODbL licence and OpenStreetMap contributor attribution;
- the source snapshot, extraction method, and retained OSM object lineage;
- a machine-readable copy or reconstruction offer required for public use;
- an in-app attribution surface appropriate for any interactive map;
- no assumption that operator-reviewed additions are outside share-alike merely
  because they are stored in another file.

Unless a documented licence review establishes that combined data types are
independent, publish a combined OSM-based routing graph conservatively as an
ODbL derivative database. A rendered schematic may be a Produced Work, but that
does not make its underlying OSM-derived database Apache-2.0.

Primary references:

- [OpenStreetMap copyright and licence](https://www.openstreetmap.org/copyright/en-US)
- [OSMF attribution guideline](https://osmfoundation.org/wiki/Licence/Attribution_Guidelines)
- [OSMF Produced Work guideline](https://osmfoundation.org/wiki/Licence/Community_Guidelines/Produced_Work_-_Guideline)
- [OSMF Collective Database guideline](https://osmfoundation.org/wiki/Licence/Community_Guidelines/Collective_Database_Guideline_Guideline)

The bounded K7 Northwest candidate database under
`data/route-atlas/osm-derived/` is the first implementation of this isolation
rule. That directory identifies ODbL-1.0 as its data licence, carries the
required OpenStreetMap contributor attribution, pins the parent PBF and bounded
extract hashes, retains exact OSM node/way lineage, and provides machine-readable
reconstruction commands. The directed database and successor-audit report are
both explicitly marked ODbL-1.0. The Apache-2.0 repository licence still applies
to the extractor and candidate builders, not to their OSM-derived data output.
Interactive-map attribution integration remains a release blocker.

## MLIT Route Atlas context boundary

The isolated artifact under `data/route-atlas/context/` is transformed from the
current-state slice of MLIT National Land Numerical Information N06-2025 and is
identified as CC BY 4.0 data. Its source record pins the authority, source and
download URLs, dataset reference date, retrieval and review dates, raw-archive
SHA-256, attribution, permitted current-state scope, and transformation
disclosure. The raw archive is not redistributed.

The generated artifact retains selected source geometry and Japanese route-name
properties, so the root Apache-2.0 licence does not replace its CC BY 4.0 terms.
Any distribution or rendered use must retain an appropriate MLIT attribution and
state that Kaido Routes filtered and projected the source. The tracked data is
geographic context only; its licence and provenance do not make it a directed
routing graph or operator-reviewed navigation product.

Primary references:

- [MLIT N06-2025 dataset page](https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N06-2025.html)
- [MLIT National Land Numerical Information terms](https://nlftp.mlit.go.jp/ksj/other/agreement_01.html)

## Names and marks

The software licence grants copyright and patent permissions only as stated in
its text. It does not imply affiliation with Metropolitan Expressway Company
Limited or permission to use third-party names, logos, or marks beyond what
applicable law allows.

## Terminology

Use these phrases in public project communication:

- “open-source software”;
- “Apache-2.0 licensed”;
- “licensed under the Apache License 2.0”.

Do not imply that the Apache licence also covers a separately licensed dependency,
road database, operator asset, or provider payload. Identify those terms at the
path or distribution boundary where they apply.
