# Product Release Authoring

`kaido-release build-product` is the production assembly boundary between two
independently released inputs and the one joint artifact consumed by the iPhone
catalog. It does not author topology, a RoutePlan, guidance, editor choices, or
road evidence.

Build and validate both inputs through their own authoring boundaries; do not
hand-edit either final artifact:

```sh
swift run kaido-release build-navigation \
  --draft <navigation-release-draft.json> \
  --config <navigation-release-authoring.json> \
  --output <navigation-release.json>

swift run kaido-release validate-navigation \
  --artifact <navigation-release.json>

swift run kaido-atlas build-release \
  --draft <route-atlas-release-draft.json> \
  --config <route-atlas-release-authoring.json> \
  --output <route-atlas-release.json>

swift run kaido-atlas validate-release \
  --artifact <route-atlas-release.json>
```

See
[`navigation-release-authoring.md`](navigation-release-authoring.md) for draft,
provenance, and fail-before-write requirements, and
[`route-atlas-release-authoring.md`](route-atlas-release-authoring.md) for the
independent topology/layout authoring boundary.

The Route Atlas input must contain released topology and layout evidence. The
navigation input must contain its exact released editor catalog, three-locale
presentation, runtime policy, matcher corridor, DecisionZones, guidance, and
optional junction views. A review-only K7 candidate is not a valid input.

## Configuration

Create a small authoring configuration:

```json
{
  "release_id": "shutoko.product.example-route.2026-08-01",
  "released_at": "2026-08-01T12:00:00+09:00",
  "schema_version": "1.0"
}
```

The release time must not predate either navigation release or any bound Route
Atlas evidence. The ID and timestamp are explicit so the build is reproducible;
the command does not silently use the local clock.

There is intentionally no runtime-use field. This command always authors:

```text
RELEASED_ROAD + FOREGROUND_WHEN_IN_USE
```

Synthetic evidence therefore fails closed instead of gaining an authoring flag
that could promote it.

## Build and validate

```sh
swift run kaido-release build-product \
  --navigation-artifact <navigation-release.json> \
  --atlas-artifact <route-atlas-release.json> \
  --config <product-release-authoring.json> \
  --output <product-release.json>

swift run kaido-release validate-product \
  --artifact <product-release.json>
```

The build:

1. decodes and validates the complete navigation artifact;
2. decodes and validates the complete Route Atlas artifact;
3. retains both inputs unchanged in a schema-6.0 product artifact;
4. requires exact snapshot and RoutePlan identity;
5. requires a finite positive actual planned distance;
6. checks product chronology and atlas coverage for every released editor
   entity;
7. rejects any synthetic source under the fixed released-road scope;
8. requires the resulting product to mint the exact foreground live-input
   authority; and
9. writes a new output atomically and refuses overwrite.

Failure produces no product artifact. A successful build proves internal
release consistency and runtime admission only. It does not replace source
licensing review, current road evidence, field review, pronunciation review,
physical-device qualification, or the App catalog's separate filename,
SHA-256, release-ID, and role binding.

After validation, use
[`app-bundle-staging.md`](app-bundle-staging.md) to derive the final artifact
SHA-256 and one `FOREGROUND_NAVIGATION` descriptor without manual
transcription. Review and explicitly enroll that generated descriptor, rebuild
the App, and qualify the exact release on a physical iPhone. Do not enable
background location or CarPlay merely because product assembly or staging
passed.
