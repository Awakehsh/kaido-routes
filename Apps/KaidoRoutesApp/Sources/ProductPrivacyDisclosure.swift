import Foundation

enum ProductPrivacyDisclosure {
  static let policyURL = URL(
    string: "https://github.com/Awakehsh/kaido-routes/blob/main/PRIVACY.md"
  )!

  static let sourceLicenseURL = URL(
    string: "https://github.com/Awakehsh/kaido-routes/blob/main/LICENSE"
  )!

  static func sourceLicenseText(
    bundle: Bundle = .main
  ) -> String? {
    guard let url = bundle.url(forResource: "LICENSE", withExtension: nil)
    else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
  }

  static func mapDataLicenseText(
    bundle: Bundle = .main
  ) -> String? {
    guard
      let url = bundle.url(
        forResource: "DATA-LICENSES",
        withExtension: "md"
      )
    else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
  }

  static func versionDescription(
    bundle: Bundle = .main
  ) -> String {
    let version =
      bundle.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String
    let build =
      bundle.object(
        forInfoDictionaryKey: "CFBundleVersion"
      ) as? String

    return switch (version, build) {
    case (.some(let version), .some(let build)):
      "\(version) (\(build))"
    case (.some(let version), .none):
      version
    case (.none, .some(let build)):
      build
    case (.none, .none):
      "—"
    }
  }
}
