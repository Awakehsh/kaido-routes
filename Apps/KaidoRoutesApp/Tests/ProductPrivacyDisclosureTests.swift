import Foundation
import XCTest

@testable import KaidoRoutesApp

final class ProductPrivacyDisclosureTests: XCTestCase {
  func testBundledPrivacyManifestMatchesAuditedCurrentBehavior() throws {
    let url = try XCTUnwrap(
      Bundle.main.url(
        forResource: "PrivacyInfo",
        withExtension: "xcprivacy"
      )
    )
    let object = try PropertyListSerialization.propertyList(
      from: Data(contentsOf: url),
      options: [],
      format: nil
    )
    let manifest = try XCTUnwrap(object as? [String: Any])

    XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
    XCTAssertEqual(
      manifest["NSPrivacyTrackingDomains"] as? [String],
      []
    )
    XCTAssertTrue(
      try XCTUnwrap(
        manifest["NSPrivacyCollectedDataTypes"] as? [Any]
      ).isEmpty
    )

    let entries = try XCTUnwrap(
      manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
    )
    let reasons = Dictionary(
      uniqueKeysWithValues: try entries.map { entry in
        (
          try XCTUnwrap(
            entry["NSPrivacyAccessedAPIType"] as? String
          ),
          try XCTUnwrap(
            entry["NSPrivacyAccessedAPITypeReasons"] as? [String]
          )
        )
      }
    )

    XCTAssertEqual(
      reasons,
      [
        "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
        "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
      ]
    )
  }

  func testAppCarriesReleaseVersionAndPublicPrivacyPolicy() {
    let version = ProductPrivacyDisclosure.versionDescription()
    XCTAssertNotNil(
      version.range(
        of: #"^[0-9]+\.[0-9]+\.[0-9]+ \([1-9][0-9]*\)$"#,
        options: .regularExpression
      )
    )
    XCTAssertEqual(
      ProductPrivacyDisclosure.policyURL.absoluteString,
      "https://github.com/Awakehsh/kaido-routes/blob/main/PRIVACY.md"
    )
    XCTAssertEqual(
      ProductPrivacyDisclosure.sourceLicenseURL.absoluteString,
      "https://github.com/Awakehsh/kaido-routes/blob/main/LICENSE"
    )
    XCTAssertNotNil(
      Bundle.main.url(forResource: "LICENSE", withExtension: nil)
    )
    XCTAssertNotNil(
      Bundle.main.url(forResource: "DATA-LICENSES", withExtension: "md")
    )
    XCTAssertTrue(
      ProductPrivacyDisclosure.sourceLicenseText()?
        .contains("Apache License") == true
    )
    let mapDataLicense = ProductPrivacyDisclosure.mapDataLicenseText()
    XCTAssertTrue(
      mapDataLicense?.contains("© OpenStreetMap contributors") == true
    )
    XCTAssertTrue(mapDataLicense?.contains("ODbL-1.0") == true)
    XCTAssertTrue(
      mapDataLicense?.contains(
        "https://opendatacommons.org/licenses/odbl/1-0/"
      ) == true
    )
  }
}
