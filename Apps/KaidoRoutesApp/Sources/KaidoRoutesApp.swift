import Foundation
import KaidoAppleAdapters
import KaidoDomain
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
        "-WHOLE-SHUTO-ROUTE-PREVIEW"
      ) {
        WholeShutoProductPreviewHost(startsNavigation: false)
      } else if ProcessInfo.processInfo.arguments.contains(
        "-WHOLE-SHUTO-NAVIGATION-PREVIEW"
      ) {
        WholeShutoProductPreviewHost(startsNavigation: true)
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
  }
}

private enum WholeShutoJunctionPreviewMovement {
  case kasai
  case oi
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
        for _ in 0..<1_000 where model.activeJunctionPrompt == nil {
          await model.advanceSimulationForTesting()
        }
      }
  }
}

private struct WholeShutoProductPreviewHost: View {
  @StateObject private var model: WholeShutoProductModel

  init(startsNavigation: Bool) {
    let model = WholeShutoProductModel(checkpointStore: nil)
    model.preparePreviewJourney(startsNavigation: startsNavigation)
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
