import UIKit
import XCTest

@testable import KaidoRoutesApp

final class PlacePhotoBundleTests: XCTestCase {
  func testClassicPlacePhotographsAreBundled() {
    for name in [
      "place-tokyo-tower",
      "place-tokyo-skytree",
      "place-haneda-airport",
      "place-minato-mirai",
      "place-rainbow-bridge",
      "place-yokohama-bay-bridge",
      "place-tsurumi-tsubasa-bridge",
      "place-katsushika-harp-bridge",
      "place-goshikizakura-bridge",
    ] {
      XCTAssertNotNil(UIImage(named: name), name)
    }
  }
}
