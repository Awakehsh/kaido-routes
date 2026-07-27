# Route Atlas releases

This directory contains independently validated renderer-neutral Route Atlas
artifacts and their exact authoring inputs. A Route Atlas release proves
snapshot, topology, layout, occurrence, source-role, and attribution integrity.
It does not grant navigation, realtime-passage, surface-egress, or whole-product
authority.

## K7 Northwest up: Yokohama Aoba to Yokohama Kohoku exit handoff

The first release is limited to the exact 13-occurrence K7 expressway plan from
the directional Yokohama Aoba up entrance to the Yokohama Kohoku up exit
handoff. Its 15-edge topology includes two reviewed expressway alternatives,
stops at `osm.node.7473451738`, excludes all three ordinary-road successors,
and releases no `SURFACE_EGRESS`.

The generated source candidate remains `CANDIDATE`. Two different independent
reviewers approved the bound topology and layout, after which the deterministic
release-input builder created a separate configuration with `RELEASED`
evidence. Rebuild the inputs only when the non-overwriting outputs do not exist:

```sh
python3 scripts/build_k7_route_atlas_release_inputs.py \
  --as-of 2026-07-27
```

Build and validate the immutable artifact:

```sh
swift run kaido-atlas build-release \
  --draft data/route-atlas/releases/k7-northwest-up-aoba-to-kohoku-route-atlas-release-draft.json \
  --config data/route-atlas/releases/k7-northwest-up-aoba-to-kohoku-route-atlas-release-authoring.json \
  --output data/route-atlas/releases/k7-northwest-up-aoba-to-kohoku-route-atlas-release.json

swift run kaido-atlas validate-release \
  --artifact data/route-atlas/releases/k7-northwest-up-aoba-to-kohoku-route-atlas-release.json
```

The CLI refuses to overwrite an existing artifact. A product build still
requires an independently valid navigation release with the exact same
snapshot and RoutePlan, followed by joint product authoring and App enrollment.

## K7 navigation-semantic release

The navigation-semantic release preserves the same reviewed exit-handoff road
scope while replacing the source-way-only plan with the exact five-occurrence
`EDGE → JUNCTION_MOVEMENT → EDGE → JUNCTION_MOVEMENT → EDGE` RoutePlan consumed
by the navigation runtime. It includes seven topology edges: five planned
entities and the two explicit expressway alternatives at Yokohama Kohoku. It
does not add any ordinary-road successor or `SURFACE_EGRESS`.

The topology, layout, and navigation/guidance drafts were hash-bound in one
review packet and approved by three different reviewers. Rebuild the generated
inputs only from a clean checkout where their non-overwriting destinations do
not exist:

```sh
python3 scripts/build_k7_navigation_release_candidates.py
python3 scripts/build_k7_navigation_release_inputs.py --as-of 2026-07-27
```

Build and validate the Atlas artifact:

```sh
swift run kaido-atlas build-release \
  --draft data/route-atlas/releases/k7-northwest-up-aoba-to-kohoku-navigation-semantic-route-atlas-release-draft.json \
  --config data/route-atlas/releases/k7-northwest-up-aoba-to-kohoku-navigation-semantic-route-atlas-release-authoring.json \
  --output data/route-atlas/releases/k7-northwest-up-aoba-to-kohoku-navigation-semantic-route-atlas-release.json

swift run kaido-atlas validate-release \
  --artifact data/route-atlas/releases/k7-northwest-up-aoba-to-kohoku-navigation-semantic-route-atlas-release.json
```

The immutable artifact SHA-256 is
`6497ea69853e35f2feb49705f4fd1694c8189a03384b5a46eab5f06bb0facda0`.
