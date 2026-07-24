import Foundation
import SwiftUI

@main
struct KaidoRoutesApp: App {
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
        "-INTERNAL-REVIEW-HOME"
      ) {
        RouteAtlasHomeView()
      } else if ProcessInfo.processInfo.arguments.contains(
        "-PRODUCT-JOURNEY-REVIEW-PREVIEW"
      ) {
        KaidoProductJourneyView(
          model: .reviewPreview()
        )
      } else {
        KaidoProductJourneyView()
      }
    }
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
  var productRuntimePhase: SyntheticProductRuntimeScenePhase {
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
