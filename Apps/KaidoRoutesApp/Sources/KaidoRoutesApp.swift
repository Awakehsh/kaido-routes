import Foundation
import SwiftUI

@main
struct KaidoRoutesApp: App {
  var body: some Scene {
    WindowGroup {
      if ProcessInfo.processInfo.arguments.contains(
        "-KR-U09-ACCESSIBILITY-PREVIEW"
      ) {
        KR_U09AccessibilityPreviewHost()
      } else {
        RouteAtlasHomeView()
      }
    }
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
