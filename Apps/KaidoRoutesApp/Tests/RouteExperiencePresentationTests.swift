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
    XCTAssertGreaterThan(c2.tunnelDistanceMeters, c1.tunnelDistanceMeters)
    for preview in model.circuitPreviewsByID.values {
      XCTAssertTrue((0...100).contains(preview.tunnelPercent))
      XCTAssertLessThanOrEqual(preview.tunnelDistanceMeters, preview.distanceMeters)
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
      ["shuto.circuit.wangan-daikoku-run": ["shuto.pa.daikoku"]]
    )
    // A course cannot anchor on a parking area the snapshot cannot enter.
    for stopIDs in advertised.values {
      for stopID in stopIDs {
        let parkingArea = try XCTUnwrap(drivable[stopID])
        XCTAssertTrue(parkingArea.isDrivable, "\(stopID) is not drivable")
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
