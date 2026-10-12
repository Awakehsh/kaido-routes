import Foundation
import KaidoDomain
import KaidoNavigation
import Testing

@Suite("Released guidance copy")
struct ReleasedGuidanceCopyTests {
  /// "At the upcoming junction, At Edobashi JCT, stay…" stacked the
  /// preparation lead-in on the commit cue's own place phrase.
  @Test("no released English prepare cue doubles its place prefix")
  func englishPrepareCuesHaveOnePlacePrefix() throws {
    let releases = try FileManager.default.contentsOfDirectory(
      at: Self.releasesDirectory,
      includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasSuffix("-product-release.json") }
    #expect(!releases.isEmpty)
    var checked = 0
    for url in releases {
      let release = try KaidoProductReleaseArtifactCodec.decode(Data(contentsOf: url))
      for definition in release.navigation.bundle.releasedGuidance
      where definition.frameTemplate.stage == .prepare {
        let english = try #require(
          definition.frameTemplate.presentationSource.localizedContent[.english],
          "\(url.lastPathComponent) \(definition.anchor.promptID)"
        )
        for text in [english.displayText, english.spokenText] {
          #expect(
            !Self.hasDoubledPlacePrefix(text),
            "\(url.lastPathComponent) \(definition.anchor.promptID): \(text)"
          )
        }
        checked += 1
      }
    }
    #expect(checked > 0)
  }

  /// Two consecutive clauses that each open with "at": the lead-in and the
  /// commit cue both saying where.
  static func hasDoubledPlacePrefix(_ text: String) -> Bool {
    let clauses = text.lowercased().split(separator: ",").map {
      $0.trimmingCharacters(in: .whitespaces)
    }
    return zip(clauses, clauses.dropFirst()).contains {
      $0.hasPrefix("at ") && $1.hasPrefix("at ")
    }
  }

  static let releasesDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("data/product/releases")
}
