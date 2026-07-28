# K7 product release

This directory contains the joint product release that independently
revalidates and binds the exact K7 navigation-semantic Route Atlas and K7
navigation release.

The product has:

- evidence scope `RELEASED_ROAD`;
- live-input policy `FOREGROUND_WHEN_IN_USE`;
- five ordered RoutePlan occurrences;
- reviewed actual planned distance `7.031167671 km`; and
- no synthetic source or caller-supplied runtime override.

Build and validate it from the two immutable nested artifacts:

```sh
swift run kaido-release build-product \
  --navigation-artifact data/navigation/releases/k7-northwest-up-aoba-to-kohoku-navigation-release.json \
  --atlas-artifact data/route-atlas/releases/k7-northwest-up-aoba-to-kohoku-navigation-semantic-route-atlas-release.json \
  --config data/product/releases/k7-northwest-up-aoba-to-kohoku-product-release-authoring.json \
  --output data/product/releases/k7-northwest-up-aoba-to-kohoku-product-release.json

swift run kaido-release validate-product \
  --artifact data/product/releases/k7-northwest-up-aoba-to-kohoku-product-release.json
```

Release ID:
`shutoko.product.k7-aoba-to-kohoku.2026-07-27`

Artifact SHA-256:
`5fe54b002b7f70e4c4086eeee6328440115e6c512f3693d68ae275250831d060`

The App bundle contains those exact bytes and a compile-time
`FOREGROUND_NAVIGATION` descriptor pinned to the filename, release ID, and
SHA-256. The generated staging configuration additionally pins one dated,
hash-bound pre-drive evidence manifest with all five vehicle classes and
separate ETC and cash profiles. That evidence window ended at
`2026-07-28T00:00:00+09:00`. The App now labels its values stale and does not
use them as current toll or passage information, while the independently
validated K7 route remains available. A current known closure or planned
conflict still blocks start. The descriptor intentionally includes no
signed-update trust key, update endpoint, or reviewed offline audio.

The exact App build was signed, built, and installed on the paired iPhone 13
Pro, then launched successfully after the device was unlocked on 2026-07-28.
Installation and process launch are packaging and lifecycle evidence only. They
are not live location, tunnel, junction-distance, pronunciation,
physical-audio, background, CarPlay, or field-navigation qualification.
