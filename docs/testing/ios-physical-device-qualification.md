# iOS physical-device App baseline

`scripts/run_ios_device_qualification.py` runs the complete
`KaidoRoutesApp` test scheme on one exact online physical iPhone and retains a
private evidence bundle. It exists so a Simulator result, an offline device
listing, a dirty checkout, or an incomplete test run cannot be reported as
physical-device qualification.

This is an App baseline only. Even a passing receipt grants no road-release,
acoustic-quality, pronunciation, CarPlay, background-navigation, location
accuracy, or driver-comprehension authority.

## Preflight

Keep the device unlocked, connect it by cable or the previously paired local
network, and enable Developer Mode. Resolve the private device identifier with
Xcode or `xcrun xcdevice list`, then run:

```sh
python3 scripts/run_ios_device_qualification.py \
  --device-id <private-device-identifier> \
  --preflight-only
```

The command passes only when that exact inventory entry is:

- `com.apple.platform.iphoneos`;
- explicitly not a Simulator;
- available without a device-preparation error; and
- complete enough to name the iPhone model and iOS version.

No output is created by preflight. Device identifiers and names must not be
copied into tracked issues or documentation.

## Full App test run

Start from a clean checkout at the exact commit under qualification. Choose an
opaque configuration ID that describes the reviewed model/OS/mount combination
without using the device name or identifier:

```sh
python3 scripts/run_ios_device_qualification.py \
  --device-id <private-device-identifier> \
  --device-configuration-id iphone13pro-dashboard-v1 \
  --output research/evidence/ios-app-baseline-2026-07-25
```

If automatic signing needs an explicit team and provisioning update, opt into
both:

```sh
python3 scripts/run_ios_device_qualification.py \
  --device-id <private-device-identifier> \
  --device-configuration-id iphone13pro-dashboard-v1 \
  --development-team <APPLE-TEAM-ID> \
  --allow-provisioning-updates \
  --output research/evidence/ios-app-baseline-2026-07-25
```

The output directory must not exist. In-repository output is accepted only
under ignored `research/`. Raw result bundles and logs may contain the device
identifier, name, local paths, or other private build context and must remain
there.

The runner:

1. repeats exact physical-device discovery;
2. refuses a dirty worktree and records the 40-character source commit;
3. runs the full tracked App unit and UI test scheme against
   `platform=iOS,id=<private-device-identifier>`;
4. requires exactly one physical-iOS result configuration;
5. requires every reported test to pass with zero failures, skips, or expected
   failures;
6. hashes the complete `.xcresult` tree, canonical summary, and build log; and
7. writes `qualification-run.json` only after the complete gate passes.

A failed build retains its private log/result bundle for diagnosis but creates
no passing receipt. Existing output is never overwritten.

## Coordinate-free receipt

`qualification-run.json` retains:

- source commit, scheme, bundle identifier, and clean-worktree fact;
- opaque configuration ID, iPhone model, iOS version, and physical-device fact;
- exact total/pass/fail/skip counts and UTC interval;
- SHA-256 values for the private result tree, summary, and log; and
- an explicit authority matrix.

It excludes the device identifier, device name, coordinates, raw location
traces, raw audio, and filesystem paths. Its authority matrix deliberately
keeps road release, acoustic quality, pronunciation, CarPlay, and background
navigation false.

## Remaining device gates

After this baseline passes, the exact released product still needs separate,
dated evidence for:

- installed enhanced/premium voice comparison and the owner-selected offline
  voice candidate;
- Japanese, Simplified Chinese, and English pronunciation;
- VoiceOver focus order, Switch Control, and the supported Dynamic Type/device
  matrix;
- foreground location start/stop, permission downgrade, interruption, output
  route, and no-replay behavior;
- the held-out matcher/location field plan; and
- any later approved CarPlay configuration.

Those reviews must remain bound to the exact product release and device
configuration. This baseline cannot inherit or synthesize them.
