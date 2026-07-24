# Route Atlas Release Authoring

`kaido-atlas build-release` is the production assembly boundary between
reviewed renderer-neutral topology/layout, their independently reviewed release
evidence, and the schema-1.0 artifact consumed by product-release authoring. It
does not derive topology, draw geometry, create legal successors, author a
RoutePlan, promote evidence, or select a synthetic mode.

Do not run this command for a real release until topology, layout, provenance,
licence, and current-road evidence have completed their independent reviews.
The command proves internal consistency; it does not replace those reviews.

## Draft

The schema-1.0 draft contains the exact immutable reviewed content:

```text
schema_version
network_snapshot
route_plan
topology_slice
  topology_slice_id
  network_snapshot_id
  nodes
  edges
definition
  atlas_id
  network_snapshot_id
  route_plan_id
  topology_slice_id
  nodes
  segments
  occurrence_bindings
```

The draft contains no source registry, topology evidence, or layout evidence.
It therefore cannot become a release on its own. In particular, topology
successors and occurrence bindings remain reviewed content; the author never
infers them from coordinates.

## Configuration

The separate schema-1.0 authoring configuration contains:

```text
schema_version
source_registry
topology_evidence
layout_evidence
```

The topology and layout evidence values must independently be `RELEASED`, carry
valid checked dates, and resolve non-empty source-reference lists. Every source
record must contain an explicit role, authority, HTTPS URL, pinned content
SHA-256, checked date, and licence identifier. Topology evidence may resolve
only through `TOPOLOGY_EVIDENCE` sources; layout evidence may resolve only
through `LAYOUT_EVIDENCE` sources. Unused, duplicate, unresolved, misclassified,
or newer-than-evidence sources fail the whole gate.

`RELEASED` remains a reviewed configuration input. This command cannot upgrade
`CANDIDATE`, `OFFICIAL_CHECKED`, or `FIELD_CHECKED`, and it exposes no promotion
flag.

## Build and validate

```sh
swift run kaido-atlas build-release \
  --draft <route-atlas-release-draft.json> \
  --config <route-atlas-release-authoring.json> \
  --output <route-atlas-release.json>

swift run kaido-atlas validate-release \
  --artifact <route-atlas-release.json>
```

The build:

1. rejects unknown draft and authoring schemas;
2. derives the current artifact schema rather than accepting it from the
   caller;
3. attaches the two evidence records without rewriting reviewed geometry,
   topology, RoutePlan, or provenance;
4. constructs `RouteAtlasRelease`, re-running exact topology/layout coverage,
   legal-successor translation, endpoint geometry, source-role, and ordered
   occurrence-binding gates;
5. encodes and decodes through `RouteAtlasReleaseArtifactCodec`;
6. writes only after every gate passes; and
7. atomically creates a new output while refusing overwrite.

Failure produces no artifact. A successful artifact is only an independently
valid Route Atlas input. It still needs an independently valid navigation
release, `kaido-release build-product`, explicit App-catalog enrollment, and
physical-device qualification.
