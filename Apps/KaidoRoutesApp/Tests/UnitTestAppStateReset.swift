import XCTest

/// The App's unit tests run in the app's own container, which UI tests share.
/// A UI test that changes a setting leaves it stored after its last launch:
/// only a UI launch clears the app's defaults (`-RESET-APP-STATE`), so the
/// voice language one UI test chose decided what a unit test heard on the
/// next run on that simulator. Clearing them once, before the first unit test,
/// is the same reset for this side. The test bundle's principal class.
final class UnitTestAppStateReset: NSObject, XCTestObservation {
  override init() {
    super.init()
    XCTestObservationCenter.shared.addTestObserver(self)
  }

  func testBundleWillStart(_ testBundle: Bundle) {
    guard let identifier = Bundle.main.bundleIdentifier else { return }
    UserDefaults.standard.removePersistentDomain(forName: identifier)
  }
}
