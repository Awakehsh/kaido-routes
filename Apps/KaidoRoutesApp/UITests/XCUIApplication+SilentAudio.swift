import XCTest

extension XCUIApplication {
  /// Launches without audible speech, from an empty app container unless the
  /// test is relaunching to prove that something the previous launch saved
  /// survives.
  func launchSilently(keepingAppState: Bool = false) {
    launchArguments.append("-KAIDO-SILENT-AUDIO")
    if !keepingAppState {
      launchArguments.append("-RESET-APP-STATE")
    }
    launch()
  }
}
