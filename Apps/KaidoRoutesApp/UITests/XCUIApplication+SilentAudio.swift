import XCTest

extension XCUIApplication {
  func launchSilently() {
    launchArguments.append("-KAIDO-SILENT-AUDIO")
    launch()
  }
}
