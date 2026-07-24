# Navigation Release Authoring

`kaido-release build-navigation` is the production assembly boundary between
reviewed navigation runtime assets, their reviewed provenance, and the
schema-5.0 artifact consumed by the product-release pipeline. It does not
derive topology, author a RoutePlan, create guidance, promote evidence, or
select a synthetic mode.

Do not run this command for a real release until every asset and source has
completed its independent review. The command proves internal consistency; it
does not replace road, field, licence, pronunciation, or device evidence.

## Draft

The schema-1.0 draft contains the exact immutable runtime assets:

- `editor_catalog_id`;
- active `network_snapshot`;
- occurrence-complete `route_plan`;
- reviewed editor catalog and locale-complete presentation catalog;
- released entry/recovery/egress runtime policy;
- complete matcher corridor;
- one DecisionZone and released guidance coverage for every planned junction
  movement;
- the optional exact junction-view registry; and
- the optional exact surface-access definition, including its reviewed
  release-candidate provider/build identity.

The root JSON keys are:

```text
schema_version
editor_catalog_id
network_snapshot
route_plan
editor_catalog
editor_presentation_catalog
runtime_policy
matcher_corridor
decision_zones
released_guidance
junction_views
surface_access_definition
```

The draft has no release ID, release time, source registry, or evidence state.
It therefore cannot become a release on its own.

When `surface_access_definition` is present, its provider identity must pin the
provider and adapter versions, network snapshot, provider dataset, build
manifest, engine build, `RELEASE_CANDIDATE` validation profile and intended
use, plus the provider's declared data-retention review status. The latter is
an exact configuration identity, not a claim that future live responses were
reviewed in advance. Runtime provider selection is not supplied by the App or
CLI after release.

## Configuration

The separate schema-1.0 authoring configuration contains:

```text
schema_version
release_id
released_at
source_registry
asset_evidence
```

`source_registry` uses the same dated HTTPS source references, pinned content
SHA-256 values, licences, and explicit asset roles as
`NavigationReleaseArtifact`. `asset_evidence` must contain exactly one
`RELEASED` record for:

- the editor catalog;
- editor presentation catalog;
- runtime policy;
- matcher corridor;
- every DecisionZone;
- every guidance prompt;
- every junction view; and
- the surface-access definition when present.

Every source must be used, every evidence record must resolve to a source whose
role permits it, and neither source nor evidence review may postdate
`released_at`. Evidence remains a reviewed input; this command never upgrades
`OFFICIAL_CHECKED`, `FIELD_CHECKED`, or synthetic values.

## Build and validate

```sh
swift run kaido-release build-navigation \
  --draft <navigation-release-draft.json> \
  --config <navigation-release-authoring.json> \
  --output <navigation-release.json>

swift run kaido-release validate-navigation \
  --artifact <navigation-release.json>
```

The build:

1. rejects unknown draft and authoring schemas;
2. derives the current artifact schema rather than accepting it from the
   caller;
3. copies every reviewed draft asset and provenance record unchanged;
4. constructs `NavigationRelease`, re-running exact evidence coverage and the
   complete `NavigationReleaseBundle` gate;
5. encodes through `NavigationReleaseArtifactCodec`;
6. writes only after every gate passes; and
7. atomically creates a new output while refusing overwrite.

Failure produces no artifact. A successful artifact is only an independently
valid navigation release input. It still needs an independently released Route
Atlas, `kaido-release build-product`, explicit App-catalog enrollment, and
physical-device qualification.
