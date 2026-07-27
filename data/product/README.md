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
SHA-256. The generated staging configuration intentionally includes no
pre-drive evidence, signed-update trust, update endpoint, or reviewed offline
audio. Consequently the released route may be authored and inspected, but
navigation start fails closed until separately reviewed, current tariff and
passage evidence matches the exact session profile.

The exact App build was signed, built, and installed on the paired iPhone 13
Pro on 2026-07-27. Installation is packaging evidence only. It is not live
location, tunnel, junction-distance, pronunciation, physical-audio, background,
CarPlay, or field-navigation qualification.
