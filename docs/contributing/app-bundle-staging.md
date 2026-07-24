# App bundle staging

`kaido-release prepare-app-bundle` is the package-time boundary between one
validated foreground product release and the explicit compile-time catalog in
the iPhone target. It removes manual release-ID and SHA-256 transcription
without turning the App into a runtime artifact scanner.

The command accepts only a product artifact that the production codec resolves
as `RELEASED_ROAD + FOREGROUND_WHEN_IN_USE` with foreground live-input
authority. The current synthetic preview therefore cannot be staged.

## Configuration

Start from
[`app-bundle-staging-config.example.json`](app-bundle-staging-config.example.json):

```json
{
  "descriptor_symbol": "releasedK7AobaKohoku",
  "guidance_audio_manifest_resource_name": null,
  "product_resource_name": "k7-aoba-kohoku-product-release",
  "schema_version": "1.0"
}
```

`descriptor_symbol` must be a non-keyword Swift identifier.
`product_resource_name` and the optional audio manifest resource name must be
safe extension-free bundle basenames. They cannot be equal.

## Product-only staging

```sh
swift run kaido-release prepare-app-bundle \
  --product-artifact <product-release.json> \
  --config <app-bundle-staging.json> \
  --output <new-staging-directory>
```

The output directory must not exist. A successful package contains:

- the exact product artifact under `Resources/`;
- a generated `BundledProductReleaseDescriptor` extension under `Sources/`;
- `app-bundle-staging-manifest.json`, which records each resource path, byte
  count, kind, and SHA-256.

The generated descriptor is always `FOREGROUND_NAVIGATION`. Review the staging
manifest and source, copy the `Sources/` and `Resources/` contents into
`Apps/KaidoRoutesApp/`, then deliberately add the generated static descriptor
symbol to `BundledProductReleaseCatalogLoader.previewManifest`. XcodeGen already
includes those two App directories. Re-run the App catalog tests and the full
App test scheme before committing.

This final explicit manifest edit is intentional. A staged directory cannot
silently enroll itself into the product.

## Staging reviewed offline guidance audio

Set `guidance_audio_manifest_resource_name` in the configuration, then supply
both audio inputs:

```sh
swift run kaido-release prepare-app-bundle \
  --product-artifact <product-release.json> \
  --config <app-bundle-staging-with-audio.json> \
  --guidance-audio-manifest <guidance-audio-release.json> \
  --guidance-audio-resources <reviewed-wav-directory> \
  --output <new-staging-directory>
```

The complete schema-1.1 audio release is revalidated against the exact product.
Every manifest WAV is copied by its reviewed safe filename, and the generated
descriptor pins the audio manifest release ID and SHA-256. A missing, corrupt,
identity-drifted, synthetic-scope, remote, or path-escaping audio resource
blocks the whole staging run.

Supplying only a manifest, only a resource directory, or an audio resource name
without both inputs is invalid.

## Safety properties

- Inputs are fully validated before any destination is created.
- The destination is assembled in a sibling temporary directory and moved into
  place only after every file is written.
- Existing output is never overwritten.
- Product and audio bytes are retained exactly; staging does not re-author
  either artifact.
- Duplicate output resource paths fail closed.
- The generated source retains the App's compile-time catalog boundary.
- Staging grants no release, route, location, prompt, audio, or navigation
  authority by itself.

The first real App entry still requires real Route Atlas and navigation
releases, reviewed localized editor/pre-drive data, an exact product release,
and physical-device qualification. This command only prepares already-released
content for deliberate bundle inclusion.
