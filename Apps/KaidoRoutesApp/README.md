# Kaido Routes iPhone preview shell

Status: internal SwiftUI preview app; not released navigation.

This target is the first real iPhone composition boundary for Kaido Routes. It
links the local `KaidoDomain`, `KaidoRouting`, `KaidoNavigation`, and
`KaidoPresentation` products and renders the tracked Route Atlas assets in one
fixed north-up instrument.

The current app deliberately exposes only:

- the 26-route full-network recognition reference;
- the topology-bound K7 evidence candidate;
- a parked route-authoring adapter backed by `ExpertRouteEditorSession` and a
  clearly synthetic reviewed catalog; and
- explicit review and release-blocked states.

It does not request location, construct a real `NavigationSession`, display a
measured position, highlight an active route, speak guidance, or expose a
CarPlay scene. Those behaviors require a coherent released route bundle and
device evidence.

## Parked route authoring

The authoring surface starts from one exact synthetic directional entrance and
renders only the immutable `ExpertRouteEditorSnapshot` values exposed for the
current incoming approach and junction complex. Choice buttons submit the
snapshot's stable choice IDs; the app composition layer supplies fresh
occurrence IDs, including after undo. Reviewed cycles remain repeated
occurrences in the route rail instead of being deduplicated.

Undo calls the session boundary. The compile control stays disabled until the
session accepts an explicit directional exit, after which it creates the exact
`RoutePlan`. The app owns display labels for this synthetic fixture only; it
does not construct real Shuto topology, infer movement legality, or promote the
Route Atlas into selectable navigation data.

## Open in Xcode

The generated project is tracked, so XcodeGen is not required merely to open it:

```sh
open KaidoRoutesApp.xcodeproj
```

Select the `KaidoRoutesApp` scheme and an installed iPhone Simulator, then press
Command-R.

Open `RouteAtlasHomeView.swift` and choose **Editor > Canvas** to use the
`#Preview` definition.

## One-command Simulator run

```sh
./scripts/run_ios_preview.sh
```

The script creates a dedicated `Kaido Routes Preview` iPhone 17 Pro simulator
when needed, builds without device signing, installs the app, and launches it.
If no iOS Simulator runtime is installed, install the matching Xcode runtime
first:

```sh
xcodebuild -downloadPlatform iOS
```

## Regenerate the Xcode project

`project.yml` is the source for the generated project. XcodeGen 2.45.3 generated
the current project:

```sh
xcodegen generate
git diff -- KaidoRoutesApp.xcodeproj
```

Regeneration must be deterministic. Review and commit both `project.yml` and the
generated project when either changes. The application target's explicit
`productName` keeps the generated product reference, shared scheme, test host,
and actual `KaidoRoutes.app` bundle aligned when Xcode opens the project.

## Tests

```sh
xcodebuild \
  -project KaidoRoutesApp.xcodeproj \
  -scheme KaidoRoutesApp \
  -destination 'platform=iOS Simulator,name=Kaido Routes Preview' \
  test
```

`AppSafetyStateTests` proves that the internal preview cannot claim route-release
authority or a measured position. `ParkedRouteEditorModelTests` proves exact
entrance/current-choice binding, future-choice rejection, fresh identities
across repeated loops and undo, explicit-exit compilation, and moving-time
lockout. The platform-light Swift package tests remain the authoritative domain
and navigation verification.
