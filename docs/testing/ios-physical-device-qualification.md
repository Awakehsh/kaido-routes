# iOS physical-device Debug baseline and Release smoke

`scripts/run_ios_device_qualification.py` first runs the default silent Debug
`KaidoRoutesApp` test scheme, then runs one information/privacy UI smoke through
the Release-only `KaidoRoutesReleaseSmoke` scheme on the same exact online
physical iPhone. It retains separate private result bundles for both parts. It
exists so a Simulator result, an offline device listing, a dirty checkout, an
incomplete Debug baseline, or a Debug-only result cannot be reported as the
physical-device App qualification.

Real audio tests are excluded from this default scheme. This is an App baseline
only. Even a passing receipt grants no road-release,
acoustic-quality, pronunciation, CarPlay, lock-screen location-delivery,
background-speech, location-accuracy, or driver-comprehension authority.

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

## Full Debug baseline and Release smoke

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
3. runs the full tracked Debug App unit and UI test scheme against
   `platform=iOS,id=<private-device-identifier>`;
4. requires exactly one physical-iOS result configuration;
5. requires every reported test to pass with zero failures, skips, or expected
   failures;
6. requires the default whole-Shuto planning-to-live permission, handoff, and
   App-switch lifecycle UI test
   `testWholeShutoForegroundLocationStartsAndStopsThroughCoreLocation()` to
   appear exactly once and pass; the test starts the exact released live
   journey, presses Home, returns to the App, and rejects a stopped or
   resume-required session;
7. resolves the formal App build settings from `KaidoRoutesReleaseSmoke` and
   fails unless they report `Release`, bundle identifier `app.kaidoroutes`, and
   `ENABLE_TESTABILITY=NO`;
8. rebuilds with separate derived data and runs only
   `testWholeShutoInformationExposesPrivacyPolicyAndBuildVersion()` through the
   Release scheme on the same device; that test first finishes or ends any
   persisted unfinished preview through the public UI, so prior App-container
   state cannot hide the information surface;
9. requires that Release result to contain exactly that one passing test with
    zero failures, skips, or expected failures;
10. runs `validate_ios_release_bundle.py` against the exact
    `Release-iphoneos/KaidoRoutes.app` produced for that device and binds its
    version, build, whole-Shuto snapshot, privacy manifest, software licence,
    map-data licence notice, and full App-tree hashes into the receipt;
11. independently hashes each `.xcresult` tree, canonical summary, canonical
    test tree, and build log, and also hashes the private Release build-settings
    and bundle-validation payloads; and
12. writes `qualification-run.json` only after both parts and the exact Release
    bundle validation pass.

The Release smoke uses development-device signing so XCTest can install it. It
does not change the Release compilation configuration or enable App
testability, and it does not claim an App Store distribution signature. If
either part fails, the runner retains the available private logs/result bundles
for diagnosis but creates no passing receipt. Existing output is never
overwritten.

## Independent App-hosted audio run

The default App baseline never activates the speaker. Run
`scripts/run_ios_physical_audio_qualification.py` only when physical audio
evidence is intentionally needed:

```sh
python3 scripts/run_ios_physical_audio_qualification.py \
  --device-id <private-device-identifier> \
  --device-configuration-id iphone13pro-speaker-audio-v1 \
  --development-team <APPLE-TEAM-ID> \
  --allow-provisioning-updates \
  --output research/evidence/ios-physical-audio-2026-07-28-v1
```

This runner has the same physical-device, clean-commit, private-output,
zero-failure, non-overwrite, and hash requirements as the complete runner. It
runs exactly one App-hosted unit test. That test sequentially exercises
installed Japanese, Simplified Chinese, and English voices, requires matching
start/finish callbacks, verifies `.playback + .voicePrompt`, and records that
the active physical output route is non-empty.

Its schema 1.0
`PRIVATE_COORDINATE_FREE_IOS_PHYSICAL_AUDIO_TEST` receipt grants only the
installed-voice and physical audio-route lifecycle smokes. It explicitly keeps
the complete App baseline and foreground-location smoke false. A previous
foreground-location receipt and a later audio-only receipt remain two
separately scoped facts; they must not be merged into a source-current complete
App-baseline claim.

## Coordinate-free receipt

The combined receipt uses schema 1.11. `qualification-run.json` retains:

- source commit and clean-worktree fact;
- opaque configuration ID, iPhone model, iOS version, and physical-device fact;
- a `debug_baseline` section with the Debug scheme, preview bundle identifier,
  exact total/pass/fail/skip counts, UTC interval, required lifecycle tests, and
  SHA-256 values for its private result tree, summary, test tree, and log;
- a separate `release_smoke` section with the Release scheme, formal
  `app.kaidoroutes` bundle identifier, `ENABLE_TESTABILITY=false`, its exact
  version/build, one-test counts and UTC interval, and independent result,
  summary, test-tree, log, build-settings, validated App-tree, whole-Shuto,
  exact C1, Bayshore-westbound, and C2 Inner/Bayshore foreground product
  releases,
  privacy-manifest, software-licence, map-data-licence, and bundle-validation
  hashes; and
- an explicit authority matrix.

It excludes the device identifier, device name, coordinates, raw location
traces, raw audio, and filesystem paths. The combined-run authority matrix
records the complete physical App baseline, Release-configuration device smoke,
and exact planning-to-live/App-switch lifecycle as true while keeping audio
lifecycle false. The independent audio-run matrix records only installed-voice
and physical audio-route lifecycle as true. Both deliberately keep location
accuracy, road release, acoustic quality, pronunciation, CarPlay, lock-screen fix/audio
delivery, and App Store distribution-signature qualification false. A callback and output
port prove that the technical route was active; they do not prove that a person
heard, understood, or approved the sound.

## Remaining device gates

After this baseline passes, the exact default product build still needs
separate, dated evidence for:

- installed enhanced/premium voice comparison and the owner-selected offline
  voice candidate;
- Japanese, Simplified Chinese, and English pronunciation;
- VoiceOver focus order, Switch Control, and the supported Dynamic Type/device
  matrix;
- foreground permission downgrade, interruption, matcher behavior under real
  movement, Bluetooth/CarPlay route changes, and no-replay behavior;
- the held-out matcher/location field plan; and
- any later approved CarPlay configuration.

Those reviews must remain bound to the exact product release and device
configuration. This baseline cannot inherit or synthesize them.
