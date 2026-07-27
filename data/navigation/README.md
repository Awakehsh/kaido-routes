# K7 navigation release

This directory contains the first independently reviewed real-road navigation
release for the exact K7 Northwest up journey from the directional Yokohama
Aoba entrance to the Yokohama Kohoku exit handoff.

The release preserves five ordered occurrences:

```text
EDGE
→ JUNCTION_MOVEMENT: keep left for Daisan-Keihin / Yokohama Kohoku exit
→ EDGE
→ JUNCTION_MOVEMENT: take the Yokohama Kohoku exit left
→ EDGE: terminal exit handoff
```

The two junction movements each have an occurrence-bound DecisionZone and one
locale-complete released guidance definition. Japanese, Simplified Chinese,
and English projections retain the exact Japanese sign target and K7 shield.
The first preparation trigger is 400 metres and the second is 250 metres.
Those distances are graph-contained release values, not field-calibrated
device thresholds.

The review manifest binds the exact Atlas and navigation draft hashes to three
different reviewers:

- topology;
- renderer-neutral layout; and
- navigation and guidance.

The generated source registry contains five pinned official or ODbL sources,
and the release contains eight exact role-matched asset-evidence records.
Ordinary-road successors, `SURFACE_ACCESS`, `SURFACE_EGRESS`, realtime passage,
tariff quotes, and offline audio are not part of this artifact.

## Reproduce and validate

The generators and release CLIs refuse to overwrite existing outputs. Run these
commands in a clean checkout or direct them to new temporary outputs:

```sh
python3 scripts/build_k7_navigation_release_candidates.py
python3 scripts/build_k7_navigation_release_inputs.py --as-of 2026-07-27

swift run kaido-release build-navigation \
  --draft data/navigation/releases/k7-northwest-up-aoba-to-kohoku-navigation-release-draft.json \
  --config data/navigation/releases/k7-northwest-up-aoba-to-kohoku-navigation-release-authoring.json \
  --output data/navigation/releases/k7-northwest-up-aoba-to-kohoku-navigation-release.json

swift run kaido-release validate-navigation \
  --artifact data/navigation/releases/k7-northwest-up-aoba-to-kohoku-navigation-release.json
```

Release ID:
`shutoko.navigation.k7-aoba-to-kohoku.2026-07-27`

Artifact SHA-256:
`2f3c9e8014f08e8e717c63ef21e2d53e308150bdbc8889a5f09b4dd57fbd36aa`

The artifact is navigation authority only for its exact snapshot, RoutePlan,
entry transition, recovery/egress policy, matcher corridor, DecisionZones, and
guidance. A joint product artifact and current session evidence remain separate
gates.
