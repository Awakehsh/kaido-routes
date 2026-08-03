# CarPlay direction

Status: accepted exploration, 2026-08-03. This records the direction and the
gates for a CarPlay scene; no CarPlay target ships yet, and nothing here
claims head-unit qualification.

## What CarPlay navigation requires

- A navigation-category CarPlay app uses `CPTemplateApplicationScene` with a
  `CPMapTemplate`: the app draws its own map content in the CarPlay window
  and drives maneuvers through `CPNavigationSession` (maneuvers, travel
  estimates, trip pause/end), with voice played through the existing audio
  session.
- The `com.apple.developer.carplay-maps` entitlement requires Apple's
  approval for the navigation category. That application is an external
  boundary: it needs the configured developer account and an owner decision,
  and no build can exercise a real head unit before it is granted. The
  CarPlay Simulator exercises layout and template flow only.

## How Kaido maps onto it

- **The phone stays the authority.** The CarPlay scene is a projection
  adapter in the same sense as the SwiftUI phone UI: it renders actor-owned
  navigation snapshots and released guidance, and it can never author,
  mutate, or recover a `RoutePlan`. This is the existing module contract —
  `KaidoPresentation` is already CarPlay-facing and renderer-neutral.
- **The track map is the CarPlay map surface.** `RouteTrackMapLayout` is
  deliberately platform-light: the same fixed-design-space layout that the
  phone renders with SwiftUI Canvas renders in the CarPlay window through a
  UIKit drawing layer. The whole-route one-frame presentation suits the
  glanceable CarPlay context better than a pannable basemap; the geographic
  presentation can follow later behind the same map control contract.
- **Guidance reuses the actor.** Reviewed junction movements compile to
  `CPManeuver` symbols, Japanese sign text, and the released localized
  strings; the one-shot speech coordinator remains the single speech
  authority so phone and head unit never speak twice. Unreviewed transitions
  stay silent on CarPlay exactly as on the phone.
- **Drive-focused scope.** CarPlay offers drive execution and safe finish
  only: continue the phone-prepared journey, show the next reviewed decision,
  and expose one finish action. Route authoring, circuit selection, tariff
  detail, and evidence views remain parked phone workflows.
- **Degraded states carry over.** Tunnel-estimated and degraded positioning
  render the same explicit estimated marker states; the simulation-only
  disclosure remains visible while no live-drive qualification exists.

## Existing contract coverage

- `KR-S11` (CarPlay disconnect handoff) already pins the session-continuity
  behavior between head unit and phone.
- The scenario envelope reserves the `CARPLAY` layer; template-flow scenarios
  join it once a scene exists.

## Gates before implementation

1. Owner-approved entitlement application for the navigation category
   (external boundary; material account action).
2. A CarPlay scene target behind the existing adapter boundary, exercised in
   the CarPlay Simulator with deterministic injected journeys.
3. Audio-session evidence: speech ducking against head-unit audio is field
   evidence, not simulator evidence, and stays honestly labeled until
   measured.
4. Physical head-unit qualification joins the existing device-qualification
   track before any CarPlay capability is described as supported.
