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

  /// "この先の分岐で、江戸橋ジャンクションは分岐せず" read as a fork followed by
  /// "don't fork": the lead-in named a fork the commit cue then denies. A
  /// prepare cue says "fork" exactly as often as its movement's commit cue
  /// (a compound movement names two); one without a commit cue, at most once.
  @Test("no released Japanese or Chinese prepare cue adds a fork")
  func japaneseAndChinesePrepareCuesAddNoFork() throws {
    let releases = try FileManager.default.contentsOfDirectory(
      at: Self.releasesDirectory,
      includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasSuffix("-product-release.json") }
    #expect(!releases.isEmpty)
    var checked = 0
    for url in releases {
      let release = try KaidoProductReleaseArtifactCodec.decode(Data(contentsOf: url))
      let guidance = release.navigation.bundle.releasedGuidance
      let commitByMovement = Dictionary(
        guidance.filter { $0.frameTemplate.stage == .commit }
          .map { ($0.frameTemplate.movementOccurrenceID, $0) },
        uniquingKeysWith: { first, _ in first }
      )
      for prepare in guidance where prepare.frameTemplate.stage == .prepare {
        let promptID = prepare.anchor.promptID
        let commit = commitByMovement[prepare.frameTemplate.movementOccurrenceID]
        for (locale, fork) in [
          (KaidoReleaseLocale.japanese, "分岐"), (.simplifiedChinese, "分岔"),
        ] {
          let prepared = try #require(
            prepare.frameTemplate.presentationSource.localizedContent[locale],
            "\(url.lastPathComponent) \(promptID) \(locale)"
          )
          let committed = commit?.frameTemplate.presentationSource
            .localizedContent[locale]
          for (text, commitText) in [
            (prepared.displayText, committed?.displayText),
            (prepared.spokenText, committed?.spokenText),
          ] {
            let allowed = commitText.map { Self.count(fork, in: $0) } ?? 1
            #expect(
              Self.count(fork, in: text) <= allowed,
              "\(url.lastPathComponent) \(promptID): \(text)"
            )
          }
        }
        checked += 1
      }
    }
    #expect(checked > 0)
  }

  static func count(_ word: String, in text: String) -> Int {
    text.components(separatedBy: word).count - 1
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
