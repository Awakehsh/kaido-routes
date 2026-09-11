import SwiftUI
import UIKit
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class RouteExperiencePresentationTests: XCTestCase {
  func testCatalogReferencesDescribeDifferentActualRoutes() async throws {
    let model = WholeShutoProductModel(checkpointStore: nil)
    for _ in 0..<200 where model.circuitPreviewsByID.count != model.bundledCircuits.count {
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertEqual(model.circuitPreviewsByID.count, model.bundledCircuits.count)
    let c1 = try XCTUnwrap(model.circuitPreviewsByID["shuto.circuit.c1-inner"])
    let c2 = try XCTUnwrap(model.circuitPreviewsByID["shuto.circuit.c2-inner-bayshore"])
    XCTAssertGreaterThan(c1.points.count, 2)
    XCTAssertGreaterThan(c1.junctionCount, 0)
    XCTAssertGreaterThan(c2.distanceMeters, c1.distanceMeters)
    XCTAssertGreaterThan(c2.referenceMinutes, c1.referenceMinutes)
    XCTAssertEqual(c1.routeIDsInOrder, ["C1"])
    XCTAssertEqual(c2.routeIDsInOrder, ["C2", "B", "C2"])
    for preview in model.circuitPreviewsByID.values {
      XCTAssertFalse(preview.routeIDsInOrder.isEmpty)
      XCTAssertFalse(
        preview.routeIDsInOrder.contains(where: \.isEmpty),
        "every card shield needs a route code to print"
      )
    }
  }

  /// The green parking line on a catalog card means the route drives in,
  /// so it has to come from the course itself. Three experiences used to
  /// advertise a PA they only pass; a card may only name a parking area the
  /// planner actually routes through.
  func testOnlyRoutesThatEnterAParkingAreaAdvertiseOne() throws {
    let model = WholeShutoProductModel(checkpointStore: nil)
    let drivable = Dictionary(
      uniqueKeysWithValues: model.database.parkingAreas.map {
        ($0.parkingAreaID, $0)
      }
    )
    var advertised: [String: [String]] = [:]
    for circuit in model.bundledCircuits where !circuit.parkingAreaStopIDs.isEmpty {
      advertised[circuit.circuitID] = circuit.parkingAreaStopIDs
    }
    XCTAssertEqual(
      advertised,
      [
        "shuto.circuit.wangan-daikoku-run": ["shuto.pa.daikoku"],
        "shuto.circuit.scenic-grand-tour": ["shuto.pa.daikoku"],
      ]
    )
    // A course cannot anchor on a parking area the snapshot cannot enter.
    for stopIDs in advertised.values {
      for stopID in stopIDs {
        let parkingArea = try XCTUnwrap(drivable[stopID])
        XCTAssertTrue(parkingArea.isDrivable, "\(stopID) is not drivable")
      }
    }
  }

  /// Route marks are printed small — 10pt on the catalog card — so every
  /// shield ground has to carry `routeWhite` at the 4.5:1 normal-text bar,
  /// not the 3:1 large-text one the audit falls back to.
  func testRouteShieldGroundsCarryRouteWhiteAtSmallSizes() {
    let routeIDs = [
      "C1", "1_HANEDA", "1_UENO", "5", "S1", "S2", "S5",
      "C2", "6_MUKOJIMA", "6_MISATO", "K6",
      "B", "9", "11", "K5",
      "3", "K1", "K2", "K3",
      "4", "K7_YOKOHAMA_KITA", "K7_YOKOHAMA_HOKUSEI",
      "7", "10", "2", "Y",
    ]
    for routeID in routeIDs {
      for style in [UIUserInterfaceStyle.light, .dark] {
        XCTAssertGreaterThanOrEqual(
          contrast(KaidoTheme.routeWhite, routeColor(routeID), style: style),
          4.5,
          "shield \(shieldLabel(routeID)) is unreadable in \(style.rawValue)"
        )
      }
    }
  }

  func testMapLabelsRemainReadableInDayAndNightPalettes() {
    for style in [UIUserInterfaceStyle.light, .dark] {
      for label in [KaidoMapPalette.label, KaidoMapPalette.junctionLabel, KaidoMapPalette.pa] {
        XCTAssertGreaterThanOrEqual(contrast(label, KaidoMapPalette.background, style: style), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(label, KaidoMapPalette.plate, style: style), 4.5)
      }
      XCTAssertGreaterThanOrEqual(contrast(KaidoMapPalette.baseRoute, KaidoMapPalette.background, style: style), 3)
    }
    XCTAssertNotEqual(
      UIColor(KaidoMapPalette.background).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)),
      UIColor(KaidoMapPalette.background).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    )
  }

  private func contrast(_ first: Color, _ second: Color, style: UIUserInterfaceStyle) -> Double {
    func luminance(_ color: Color) -> Double {
      let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
      var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
      resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
      func linear(_ value: CGFloat) -> Double {
        let v = Double(value)
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
      }
      return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
    let a = luminance(first), b = luminance(second)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
  }
}
