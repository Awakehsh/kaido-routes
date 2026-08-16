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
    XCTAssertEqual(
      Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes")
        as? [String],
      ["audio", "location"]
    )
    XCTAssertTrue(
      Set([
        "Kaido Routes uses your location after you choose Current Location or start route navigation, including while the screen is locked or another app is visible during active navigation.",
        "現在地の選択時とルート案内の開始後に位置情報を使用します。ナビ中は画面ロック中や他のApp表示中も継続します。",
        "在你选择「当前位置」或开始路线导航后，Kaido Routes 会使用你的位置信息。导航进行时，锁屏或显示其他 App 期间也会继续使用。",
      ]).contains(
        Bundle.main.object(
          forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription"
        ) as? String ?? ""
      )
    )
  }
}
