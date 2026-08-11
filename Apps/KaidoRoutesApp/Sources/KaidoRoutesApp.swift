import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoRouting
import KaidoSurfaceRouting
import SwiftUI

@main
struct KaidoRoutesApp: App {
  init() {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains(
        "-RESET-NAVIGATION-CHECKPOINT"
      ) {
        do {
          try FileNavigationSessionCheckpointStore.applicationSupport()
            .remove()
          try FileC2NavigationSimulationCheckpointStore.applicationSupport()
            .remove()
          try WholeShutoUserDefaultsCheckpointStore().remove()
        } catch {
          preconditionFailure(
            "Failed to reset E2E navigation checkpoint: \(error)"
          )
        }
      }
    #endif
  }

  var body: some Scene {
    WindowGroup {
      #if DEBUG
        debugPreviewHost
      #else
        WholeShutoProductView()
      #endif
    }
  }

  #if DEBUG
    /// Launch-argument preview and qualification hosts for the automated
    /// suites and internal review. They compile only into Debug builds —
    /// the distributed app is the product surface alone, so no internal
    /// fixture or review screen can be reached from a shipped binary.
    @ViewBuilder
    private var debugPreviewHost: some View {
      if ProcessInfo.processInfo.arguments.contains(
        "-ROUTE-ATLAS-ATTRIBUTION-PREVIEW"
      ) {
        RouteAtlasAttributionPreviewHost()
      } else if ProcessInfo.processInfo.arguments.contains(
        "-KR-U03-CORRIDOR-PREVIEW"
      ) {
        KR_U03CorridorPreviewHost()
      } else if ProcessInfo.processInfo.arguments.contains(
        "-KR-U09-ACCESSIBILITY-PREVIEW"
      ) {
        KR_U09AccessibilityPreviewHost()
      } else if ProcessInfo.processInfo.arguments.contains(
        "-PRODUCT-RUNTIME-PREVIEW"
      ) {
        ProductRuntimePreviewHost()
      } else if ProcessInfo.processInfo.arguments.contains(
        "-PHYSICAL-AUDIO-QUALIFICATION"
      ) {
        PhysicalAudioQualificationHost()
      } else if ProcessInfo.processInfo.arguments.contains(
        "-INTERNAL-REVIEW-HOME"
      ) {
        RouteAtlasHomeView()
      } else if ProcessInfo.processInfo.arguments.contains(
        "-PRODUCT-JOURNEY-REVIEW-PREVIEW"
      ) {
        KaidoProductJourneyView(
          model: .reviewPreview()
        )
      } else if ProcessInfo.processInfo.arguments.contains(
        "-PRODUCT-JOURNEY-DEMO-PREVIEW"
      ) {
        KaidoProductJourneyView(
          model: .demoPreview()
        )
      } else if ProcessInfo.processInfo.arguments.contains(
        "-PRODUCT-JOURNEY-C2-RESTORE-PREVIEW"
      ) {
        KaidoProductJourneyView(
          model: .demoPreview(),
          c2NavigationModel: .restoredPreview()
        )
      } else if ProcessInfo.processInfo.arguments.contains(
        "-C2-NAVIGATION-REVIEW-PREVIEW"
      ) {
        C2NavigationDemoView(
          model: .preview(phase: .review)
        )
      } else if ProcessInfo.processInfo.arguments.contains(
        "-C2-NAVIGATION-KASAI-PREVIEW"
      ) {
        C2NavigationDemoView(
          model: .preview(
            phase: .expressway,
            expresswayOccurrenceIndex: 9
          )
        )
      } else if ProcessInfo.processInfo.arguments.contains(
        "-C2-NAVIGATION-OI-PREVIEW"
      ) {
        C2NavigationDemoView(
          model: .preview(
            phase: .expressway,
            expresswayOccurrenceIndex: 13
          )
        )
      } else if ProcessInfo.processInfo.arguments.contains(
        "-C2-NAVIGATION-EGRESS-PREVIEW"
      ) {
        C2NavigationDemoView(
          model: .preview(phase: .surfaceEgress)
        )
      } else if ProcessInfo.processInfo.arguments.contains(
        "-C2-FULL-NAVIGATION-DEMO"
      ) {
        C2NavigationDemoView(model: .preview())
      } else if ProcessInfo.processInfo.arguments.contains(
        "-C2-ROUTE-MAP-DEMO"
      ) {
        C2CompletedRouteDemoView()
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-SEARCH-PREVIEW"
      ) {
        WholeShutoSearchPreviewHost()
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-LOCATION-DENIED-PREVIEW"
      ) {
        WholeShutoLocationDeniedPreviewHost()
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-SURFACE-FAILURE-PREVIEW"
      ) {
        WholeShutoSurfaceFailurePreviewHost()
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-TRACK-MAP-PREVIEW"
      ) {
        WholeShutoTrackMapPreviewHost(startsNavigation: false)
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-TRACK-MAP-NAVIGATION-PREVIEW"
      ) {
        WholeShutoTrackMapPreviewHost(startsNavigation: true)
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-TRACK-MAP-LINEAR-PREVIEW"
      ) {
        WholeShutoLinearTrackMapPreviewHost()
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-NETWORK-BROWSE-PREVIEW"
      ) {
        WholeShutoNetworkBrowsePreviewHost()
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-ROUTE-PREVIEW"
      ) {
        WholeShutoProductPreviewHost(startsNavigation: false)
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-NAVIGATION-PREVIEW"
      ) {
        WholeShutoProductPreviewHost(startsNavigation: true)
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-ARRIVAL-PREVIEW"
      ) {
        WholeShutoArrivalPreviewHost()
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-JUNCTION-NAVIGATION-PREVIEW"
      ) {
        WholeShutoJunctionPreviewHost(
          movement: .oi,
          startsNavigation: true
        )
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-KASAI-JUNCTION-NAVIGATION-PREVIEW"
      ) {
        WholeShutoJunctionPreviewHost(
          movement: .kasai,
          startsNavigation: true
        )
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-SHINONOME-EASTBOUND-JUNCTION-NAVIGATION-PREVIEW"
      ) {
        WholeShutoJunctionPreviewHost(
          movement: .shinonomeEastbound,
          startsNavigation: true
        )
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-SHINONOME-WESTBOUND-JUNCTION-NAVIGATION-PREVIEW"
      ) {
        WholeShutoJunctionPreviewHost(
          movement: .shinonomeWestbound,
          startsNavigation: true
        )
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-TATSUMI-EASTBOUND-JUNCTION-NAVIGATION-PREVIEW"
      ) {
        WholeShutoJunctionPreviewHost(
          movement: .tatsumiEastbound,
          startsNavigation: true
        )
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-TATSUMI-WESTBOUND-JUNCTION-NAVIGATION-PREVIEW"
      ) {
        WholeShutoJunctionPreviewHost(
          movement: .tatsumiWestbound,
          startsNavigation: true
        )
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-JUNCTION-PREVIEW"
      ) {
        WholeShutoJunctionPreviewHost(
          movement: .oi,
          startsNavigation: false
        )
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-KASAI-JUNCTION-PREVIEW"
      ) {
        WholeShutoJunctionPreviewHost(
          movement: .kasai,
          startsNavigation: false
        )
      } else if ProcessInfo.processInfo.arguments.contains(
        "-LEGACY-PRODUCT-JOURNEY"
      ) {
        KaidoProductJourneyView()
      } else if ProcessInfo.processInfo.arguments.contains(
        "-SAVED-ROUTE-LIBRARY-PREVIEW"
      ) {
        SavedRouteLibraryPreviewHost()
      } else if ProcessInfo.processInfo.arguments.contains(
        "-K7-OPERATIONAL-E2E"
      ) {
        KaidoProductJourneyView(
          model: KaidoProductJourneyModel(
            composition: .k7OperationalE2E()
          )
        )
      } else if ProcessInfo.processInfo.arguments.contains(
        "-K7-EXPIRED-INFORMATION-E2E"
      ) {
        KaidoProductJourneyView(
          model: KaidoProductJourneyModel(
            composition: .k7ExpiredInformationE2E()
          )
        )
      } else {
        WholeShutoProductView()
      }
    }
  #endif
}

private enum WholeShutoJunctionPreviewMovement {
  case kasai
  case oi
  case shinonomeEastbound
  case shinonomeWestbound
  case tatsumiEastbound
  case tatsumiWestbound
}

private struct WholeShutoSearchPreviewHost: View {
  @StateObject private var model: WholeShutoProductModel
  @StateObject private var planningLocation:
    WholeShutoPlanningLocationController
  @StateObject private var placeSearch: WholeShutoPlaceSearchController

  init() {
    let coordinate = WholeShutoSearchPreviewLocationProvider.coordinate
    _model = StateObject(
      wrappedValue: WholeShutoProductModel(
        locationProvider: WholeShutoSearchPreviewLocationProvider(),
        surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
        checkpointStore: nil
      )
    )
    _planningLocation = StateObject(
      wrappedValue: WholeShutoPlanningLocationController(
        previewSnapshot: WholeShutoPlanningLocationSnapshot(
          coordinate: ShutoCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
          ),
          horizontalAccuracyMeters: 6,
          courseDegrees: nil,
          measuredAt: Date(timeIntervalSince1970: 0)
        )
      )
    )
    _placeSearch = StateObject(
      wrappedValue: WholeShutoPlaceSearchController(
        previewPlaces: [
          (
            WholeShutoPlaceSuggestion(
              id: "preview.tokyo-tower",
              title: "东京塔",
              subtitle: "东京都港区芝公园"
            ),
            WholeShutoPlace(
              title: "东京塔",
              coordinate: ShutoCoordinate(
                latitude: 35.658581,
                longitude: 139.745433
              )
            )
          ),
          (
            WholeShutoPlaceSuggestion(
              id: "preview.tokyo-station",
              title: "东京站",
              subtitle: "东京都千代田区丸之内"
            ),
            WholeShutoPlace(
              title: "东京站",
              coordinate: ShutoCoordinate(
                latitude: 35.681236,
                longitude: 139.767125
              )
            )
          ),
        ]
      )
    )
  }

  var body: some View {
    WholeShutoProductView(
      model: model,
      planningLocation: planningLocation,
      placeSearch: placeSearch
    )
  }
}

@MainActor
private final class WholeShutoSearchPreviewLocationProvider:
  C2NavigationCurrentLocationProviding
{
  nonisolated static let coordinate = SurfaceCoordinate(
    latitude: 35.681236,
    longitude: 139.767125
  )

  func currentCoordinate() async throws -> SurfaceCoordinate {
    Self.coordinate
  }
}

private struct WholeShutoLocationDeniedPreviewHost: View {
  @StateObject private var model = WholeShutoProductModel(
    checkpointStore: nil
  )
  @StateObject private var planningLocation =
    WholeShutoPlanningLocationController(previewState: .denied)
  @StateObject private var placeSearch = WholeShutoPlaceSearchController(
    previewPlaces: []
  )

  var body: some View {
    WholeShutoProductView(
      model: model,
      planningLocation: planningLocation,
      placeSearch: placeSearch
    )
  }
}

private struct WholeShutoSurfaceFailurePreviewHost: View {
  @StateObject private var model: WholeShutoProductModel

  init() {
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoUnavailableSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.originQuery = "現在地"
    model.selectCurrentOrigin(
      WholeShutoProductModel.previewOrigin.coordinate
    )
    model.selectDestinationPreview(
      WholeShutoProductModel.previewDestination
    )
    _model = StateObject(wrappedValue: model)
  }

  var body: some View {
    WholeShutoProductView(model: model)
      .task {
        guard model.phase == .planning, !model.isPlanning else { return }
        model.planJourney()
      }
  }
}

private struct WholeShutoUnavailableSurfaceRouteResolver:
  WholeShutoSurfaceRouteResolving,
  Sendable
{
  func route(
    from origin: ShutoCoordinate,
    to destination: ShutoCoordinate
  ) async -> WholeShutoSurfaceRoute? {
    nil
  }
}

private struct WholeShutoJunctionPreviewHost: View {
  @StateObject private var model: WholeShutoProductModel
  private let startsNavigation: Bool

  init(
    movement: WholeShutoJunctionPreviewMovement,
    startsNavigation: Bool
  ) {
    let model = WholeShutoProductModel(checkpointStore: nil)
    switch movement {
    case .kasai:
      model.prepareKasaiJunctionPreview(
        startsNavigation: startsNavigation
      )
    case .oi:
      model.prepareJunctionPreview(startsNavigation: startsNavigation)
    case .shinonomeEastbound:
      model.prepareShinonomeEastboundJunctionPreview(
        startsNavigation: startsNavigation
      )
    case .shinonomeWestbound:
      model.prepareShinonomeWestboundJunctionPreview(
        startsNavigation: startsNavigation
      )
    case .tatsumiEastbound:
      model.prepareTatsumiEastboundJunctionPreview(
        startsNavigation: startsNavigation
      )
    case .tatsumiWestbound:
      model.prepareTatsumiWestboundJunctionPreview(
        startsNavigation: startsNavigation
      )
    }
    if startsNavigation {
      model.togglePlayback()
    }
    self.startsNavigation = startsNavigation
    _model = StateObject(wrappedValue: model)
  }

  var body: some View {
    WholeShutoProductView(model: model)
      .task {
        guard startsNavigation else { return }
        // Advance to the movement this preview is staged at, not merely
        // to the first reviewed prompt on the route — a denser corridor
        // puts earlier prompts ahead of it.
        for _ in 0..<2_000
        where model.activeJunctionPrompt?.movementID
          != model.junctionPreviewMovementID
        {
          await model.advanceSimulationForTesting()
        }
      }
  }
}

private struct WholeShutoNetworkBrowsePreviewHost: View {
  @StateObject private var model: WholeShutoProductModel

  init() {
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    // No selection: the whole-network browse diagram is the network mode.
    model.mapMode = .network
    _model = StateObject(wrappedValue: model)
  }

  var body: some View {
    WholeShutoProductView(model: model)
  }
}

private struct WholeShutoLinearTrackMapPreviewHost: View {
  @StateObject private var model: WholeShutoProductModel

  init() {
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    // Tokyo-to-Yokohama linear journey on the corridor-side track map.
    model.preparePreviewJourney()
    model.mapMode = .network
    _model = StateObject(wrappedValue: model)
  }

  var body: some View {
    WholeShutoProductView(model: model)
  }
}

private struct WholeShutoTrackMapPreviewHost: View {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var model: WholeShutoProductModel
  private let startsNavigation: Bool

  init(startsNavigation: Bool) {
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    // Circuit review near Hatsudai with the track map presentation active.
    model.selectCurrentOrigin(
      ShutoCoordinate(latitude: 35.6798, longitude: 139.6862)
    )
    model.selectCircuit(.c2InnerWithBayshore)
    model.selectCircuitLaps(2)
    // Pairing derivation is asynchronous; the journey starts on resolution.
    model.startCircuitJourneyWhenPaired()
    model.mapMode = .network
    self.startsNavigation = startsNavigation
    _model = StateObject(wrappedValue: model)
  }

  var body: some View {
    WholeShutoProductView(model: model)
      .task(id: scenePhase) {
        guard startsNavigation, scenePhase == .active else { return }
        // The derived pairing lands asynchronously before review opens.
        for _ in 0..<200 where model.phase != .review {
          try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard model.phase == .review else { return }
        model.startNavigationSimulation()
        model.mapMode = .network
      }
  }
}

private struct WholeShutoProductPreviewHost: View {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var model: WholeShutoProductModel
  private let startsNavigation: Bool

  init(startsNavigation: Bool) {
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.preparePreviewJourney()
    self.startsNavigation = startsNavigation
    _model = StateObject(wrappedValue: model)
  }

  var body: some View {
    WholeShutoProductView(model: model)
      .task(id: scenePhase) {
        guard
          startsNavigation,
          scenePhase == .active,
          model.phase == .review
        else {
          return
        }
        await Task.yield()
        model.startNavigationSimulation()
      }
  }
}

private struct WholeShutoArrivalPreviewHost: View {
  @StateObject private var model: WholeShutoProductModel

  init() {
    let model = WholeShutoProductModel(
      surfaceRouteResolver: WholeShutoPreviewSurfaceRouteResolver(),
      checkpointStore: nil
    )
    model.prepareCompletedJourneyPreview()
    _model = StateObject(wrappedValue: model)
  }

  var body: some View {
    WholeShutoProductView(model: model)
  }
}

private struct SavedRouteLibraryPreviewHost: View {
  @StateObject private var model: KaidoProductJourneyModel

  init() {
    let store = PreviewSavedRouteLibraryStore()
    let composition = KaidoRoutesAppModel(
      savedRouteStore: store
    )
    let model = KaidoProductJourneyModel(
      composition: composition
    )
    composition.routeEditor.select(
      choiceID: "preview.synthetic.choice.early-exit"
    )
    composition.routeEditor.compile()
    model.go(to: .review)
    _model = StateObject(wrappedValue: model)
  }

  var body: some View {
    KaidoProductJourneyView(model: model)
  }
}

@MainActor
private final class PreviewSavedRouteLibraryStore:
  SavedRouteLibraryStoring
{
  private var library: SavedRouteLibraryDocument?

  func load() throws -> SavedRouteLibraryDocument? {
    library
  }

  func save(_ library: SavedRouteLibraryDocument) throws {
    self.library = library
  }
}

private struct ProductRuntimePreviewHost: View {
  @StateObject private var model: SyntheticProductRuntimeModel

  init() {
    let initialModel: SyntheticProductRuntimeModel
    do {
      initialModel = try SyntheticProductRuntimeModel()
    } catch {
      preconditionFailure("Invalid synthetic product runtime fixture: \(error)")
    }
    _model = StateObject(wrappedValue: initialModel)
  }

  var body: some View {
    ScrollView {
      SyntheticProductRuntimePanel(model: model)
        .padding(18)
    }
    .background(KaidoTheme.asphalt.ignoresSafeArea())
    .accessibilityIdentifier("product-runtime-preview")
  }
}

private struct KR_U03CorridorPreviewHost: View {
  @StateObject private var model: ParkedRouteEditorModel

  init() {
    let initialModel: ParkedRouteEditorModel
    do {
      initialModel = try ParkedRouteEditorModel()
    } catch {
      preconditionFailure("Invalid KR-U03 corridor fixture: \(error)")
    }
    _model = StateObject(wrappedValue: initialModel)
  }

  var body: some View {
    ScrollView {
      ParkedRouteEditorPanel(model: model)
        .padding(18)
    }
    .background(KaidoTheme.asphalt.ignoresSafeArea())
    .accessibilityIdentifier("kr-u03-corridor-preview")
  }
}

private struct KR_U09AccessibilityPreviewHost: View {
  @StateObject private var model: SyntheticDrivingPreviewModel

  init() {
    let initialModel: SyntheticDrivingPreviewModel
    do {
      initialModel = try SyntheticDrivingPreviewModel(
        initialCase: .reviewedJunctionHandoff
      )
    } catch {
      preconditionFailure("Invalid KR-U09 accessibility fixture: \(error)")
    }
    _model = StateObject(wrappedValue: initialModel)
  }

  var body: some View {
    ScrollView {
      SyntheticDrivingPreviewPanel(model: model)
        .padding(18)
    }
    .background(KaidoTheme.asphalt.ignoresSafeArea())
    .accessibilityIdentifier("kr-u09-accessibility-preview")
  }
}

extension ScenePhase {
  var productRuntimePhase: ProductNavigationRuntimeScenePhase {
    switch self {
    case .active:
      .active
    case .inactive:
      .inactive
    case .background:
      .background
    @unknown default:
      .inactive
    }
  }
}
