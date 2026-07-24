# Guidance audio authoring

Kaido may ship a reviewed pre-generated voice without granting a speech model,
audio file, or adapter any navigation authority. The active product release
still owns RoutePlan, occurrence, guidance, and exactly-once prompt identity.

This workflow creates one complete offline audio release from that authority.
It is not a generic phrase cache and it cannot be used to add, rewrite, or
deduplicate guidance.

## Boundaries

- Start from one validated `KaidoProductReleaseArtifact`.
- Generate one WAV for every worklist item. Repeated graph entities remain
  separate when their anchor occurrence IDs differ.
- Use the exact `spoken_text` and `suggested_resource_filename` from the
  generated worklist.
- Select exactly one reviewed voice/provenance profile for each of `ja-JP`,
  `zh-CN`, and `en-US`.
- Use local mono PCM16 WAV files. Network URLs, symlink escapes, silence,
  malformed RIFF data, metadata drift, and missing assets fail closed.
- `SYNTHETIC_TEST_ONLY` product releases require synthetic audio provenance.
  `RELEASED_ROAD` products require `RELEASED_ASSET`; the scopes cannot be
  mixed.
- Do not commit private source recordings, unreviewed model output, or material
  whose distribution terms are unresolved.

## 1. Export the recording worklist

```sh
swift run kaido-release export-guidance-audio-worklist \
  --product-artifact path/to/product-release.json \
  --output path/to/guidance-audio-worklist.json
```

The command refuses to overwrite an existing output. The worklist is a
deterministic projection of the product release and contains:

- exact product, navigation release, network snapshot, and RoutePlan identity;
- prompt, anchor, and anchor-occurrence identity;
- exact synthesis locale and reviewed spoken text;
- spoken-text SHA-256; and
- one deterministic flat WAV filename.

The worklist grants no release authority. Re-export it whenever the product
release changes. `GuidanceAudioRecordingWorklistCodec.decode` rejects a
worklist that no longer exactly matches its product release.

## 2. Generate and review WAV files

Generate or record the exact worklist text and place every file in one private
directory using its suggested filename. Do not add prompt text from a provider,
change punctuation after review, or reuse a file under another occurrence
identity.

Review at least:

- pronunciation of Japanese sign and junction text;
- clarity at navigation-prompt duration and cadence;
- Simplified Chinese, Japanese, and English voice identity;
- clipping, silence, leading/trailing delay, and background artifacts;
- model/engine/voice revision and licence; and
- whether output may be redistributed with the Apache-2.0 project.

Field audio-route, interruption, timing, and driver-comprehension qualification
remain separate device gates.

## 3. Create the authoring configuration

The configuration contains only release metadata and one provenance profile per
locale. It cannot alter worklist identities or text. See the executable
synthetic shape at
`docs/testing/fixtures/guidance-audio-authoring-config.synthetic.json`.

For a real release, replace every synthetic value with reviewed facts:

- `release_id` and `released_at`;
- `evidence_scope` (`RELEASED_ASSET` for a released-road product);
- generation mode (`LOCAL_OPEN_WEIGHT`, `CLOUD_PREGENERATED`, or
  `HUMAN_RECORDED`);
- engine, model, immutable model revision, and voice identity;
- exact licence identifier and HTTPS source URL; and
- generation and independent review timestamps no later than the audio release.

## 4. Build the manifest

```sh
swift run kaido-release build-guidance-audio \
  --product-artifact path/to/product-release.json \
  --config path/to/guidance-audio-authoring-config.json \
  --resources path/to/private-wav-directory \
  --output path/to/guidance-audio-release.json
```

The author derives every asset record from the product worklist, reads the local
WAV, calculates audio SHA-256 and byte count, parses PCM metadata, and runs the
whole `GuidanceAudioRelease` gate before writing a new manifest. It refuses to
overwrite an existing output.

## 5. Revalidate the distributable set

```sh
swift run kaido-release validate-guidance-audio \
  --product-artifact path/to/product-release.json \
  --manifest path/to/guidance-audio-release.json \
  --resources path/to/private-wav-directory
```

Validation requires complete one-to-one coverage and exact product, RoutePlan,
occurrence, locale, text, hash, WAV, chronology, and provenance-scope identity.
One invalid record blocks the whole pack.

Only after this command passes and the device gates are complete may the App
catalog declare the audio manifest filename, release ID, and manifest SHA-256
beside the exact foreground product descriptor. Apple installed voice remains
the safe playback-start fallback.
