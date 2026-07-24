# Pre-drive evidence bundles

`PreDriveEvidenceBundle` is the dated, replaceable boundary between one exact
foreground product route and the tariff/passage evidence evaluated immediately
before a drive. It is not part of `KaidoProductRelease`: changing a toll quote
or static passage review must not rewrite RoutePlan authority.

The schema-1.0 manifest binds:

- one evidence release ID and release time;
- `RELEASED_ROAD` or explicit synthetic-test scope;
- the exact product release, navigation release, network snapshot, and
  RoutePlan;
- a reviewed source registry with content SHA-256, check time, reviewer, and
  review time;
- at least one `TARIFF_QUERY` and one `PASSAGE_REVIEW` source for every record;
- one exact vehicle-class and ETC/cash profile per record;
- a validity start and exclusive expiry time; and
- the complete `PreDriveReviewEvidence`, including every active, proposed, and
  retired tariff quote.

Duplicate profile records, missing or orphaned sources, chronology drift,
identity drift, a mixed tariff profile, and
`REALTIME_CONFIRMED_PASSABLE` without a separate live authority all fail the
whole bundle. The runtime then resolves only the selected exact profile and
checks the current time again. Neither a record validity start nor a future
bundle release can authorize use early. It never reuses another vehicle class
or payment path, and an expired record returns
`PRE_DRIVE_EVIDENCE_EXPIRED`.

## Author without copying product identity

`kaido-release build-pre-drive-evidence` separates reviewed current evidence
from release metadata and derives every product-owned identity.

The schema-1.0 draft contains only:

```text
schema_version
source_registry
records
```

Each record retains its ID, validity window, source references, evaluation
time, one vehicle/payment profile, passage evidence, and reviewed tariff
values. A draft tariff quote deliberately has no entry facility, exit facility,
vehicle class, or payment method. The draft root also has no product,
navigation, snapshot, RoutePlan, evidence-scope, release-ID, or release-time
field.

The separate schema-1.0 authoring configuration contains only:

```text
schema_version
release_id
released_at
```

Build against the independently validated foreground product:

```sh
swift run kaido-release build-pre-drive-evidence \
  --product-artifact <product-release.json> \
  --draft <pre-drive-evidence-draft.json> \
  --config <pre-drive-evidence-authoring.json> \
  --output <pre-drive-evidence.json>
```

The author requires a codec-admitted
`RELEASED_ROAD + FOREGROUND_WHEN_IN_USE` product. It fixes the evidence scope
to `RELEASED_ROAD`, derives the product/navigation/snapshot/RoutePlan and
entry/exit identities, copies the record profile onto every quote, and runs the
complete `PreDriveEvidenceBundle` gate before returning a manifest. There is no
synthetic-mode or identity override. The CLI writes only after validation and
refuses to overwrite an existing output.

## Validate before staging

```sh
swift run kaido-release validate-pre-drive-evidence \
  --product-artifact <product-release.json> \
  --manifest <pre-drive-evidence.json>
```

The command decodes the product through the production codec, requires
released-road foreground authority, validates every source and record, and
re-runs `PreDriveReviewEvaluator`. A passing command proves artifact integrity,
not that the underlying road, tariff, or passage claim is true; those claims
still require the recorded current primary evidence and review.

## Enroll with the App release

Set `pre_drive_evidence_manifest_resource_name` in the App-bundle staging
configuration and pass the same manifest:

```sh
swift run kaido-release prepare-app-bundle \
  --product-artifact <product-release.json> \
  --config <app-bundle-staging.json> \
  --pre-drive-evidence-manifest <pre-drive-evidence.json> \
  --output <new-staging-directory>
```

Staging retains the exact bytes and generates an
`AppBundlePreDriveEvidenceDescriptor` containing the manifest resource name,
SHA-256, and evidence release ID. The App catalog verifies that hash before
decoding the bundle against the selected product release. A declared resource
cannot disappear, drift identity, or silently fall back to injected synthetic
evidence.

The compile-time descriptor must still be reviewed and explicitly enrolled.
Bundled evidence is intentionally fail-closed and may expire before a later App
release.

## Sign an update without republishing the App

The App can accept a manually imported, self-contained Ed25519 envelope when
the foreground product descriptor already contains the matching public trust
key. Generate a signing key once in a new offline directory:

```sh
swift run kaido-release generate-pre-drive-evidence-signing-key \
  --key-id <stable-key-id> \
  --output <new-private-key-directory>
```

The directory contains `private-key.bin` with mode `0600` and a public
`trust-key.json`. Keep the private key outside the repository, App bundle,
staging output, logs, backups shared with reviewers, and user-facing update
files. Only the public trust descriptor belongs in the schema-1.1 App-bundle
staging configuration:

```json
{
  "pre_drive_evidence_update_trust_keys": [
    {
      "algorithm": "ED25519",
      "key_id": "<stable-key-id>",
      "public_key_base64": "<public-key-base64>"
    }
  ]
}
```

After authoring and validating a newer evidence manifest, sign its exact bytes:

```sh
swift run kaido-release sign-pre-drive-evidence-update \
  --product-artifact <product-release.json> \
  --manifest <pre-drive-evidence.json> \
  --key-id <stable-key-id> \
  --private-key <private-key.bin> \
  --output <pre-drive-evidence-update.json>

swift run kaido-release validate-pre-drive-evidence-update \
  --product-artifact <product-release.json> \
  --envelope <pre-drive-evidence-update.json> \
  --trust-key <trust-key.json>
```

Both commands revalidate the whole manifest against the exact foreground
product. The envelope signs a domain separator, key ID, and unmodified manifest
bytes; its SHA-256 is checked before signature verification. Existing outputs
are never overwritten.

The parked App import tries every compile-time trusted foreground product and
requires exactly one signature plus whole-bundle match. It rejects an equal or
older release timestamp and any reused evidence release ID, persists the
envelope before publishing it, and verifies it again on restoration. A future
signed release waits until its own release time. Once a newer release is
effective, an expired or missing profile fails closed instead of falling back
to bundled evidence. Updating or revoking trust roots still requires a reviewed
App release.

This boundary is deliberately manual and local. It does not fetch operator or
traffic services, grant route or navigation authority, claim realtime passage,
or establish that signed source claims are true.
