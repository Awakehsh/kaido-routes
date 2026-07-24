import Foundation

public enum GuidanceSpeechVoiceQuality: Int, Equatable, Sendable {
  case defaultQuality = 1
  case enhanced = 2
  case premium = 3

  public var label: String {
    switch self {
    case .defaultQuality:
      "DEFAULT"
    case .enhanced:
      "ENHANCED"
    case .premium:
      "PREMIUM"
    }
  }

  public var isHigherQuality: Bool {
    switch self {
    case .enhanced, .premium:
      true
    case .defaultQuality:
      false
    }
  }
}

public struct GuidanceSpeechVoiceCandidate: Equatable, Sendable {
  public let identifier: String
  public let name: String
  public let languageCode: String
  public let quality: GuidanceSpeechVoiceQuality
  public let isNoveltyVoice: Bool
  public let isPersonalVoice: Bool

  public init(
    identifier: String,
    name: String,
    languageCode: String,
    quality: GuidanceSpeechVoiceQuality,
    isNoveltyVoice: Bool = false,
    isPersonalVoice: Bool = false
  ) {
    self.identifier = identifier
    self.name = name
    self.languageCode = languageCode
    self.quality = quality
    self.isNoveltyVoice = isNoveltyVoice
    self.isPersonalVoice = isPersonalVoice
  }
}

public struct GuidanceSpeechVoiceProfile: Equatable, Sendable {
  public let identifier: String
  public let name: String
  public let languageCode: String
  public let quality: GuidanceSpeechVoiceQuality

  public init(
    identifier: String,
    name: String,
    languageCode: String,
    quality: GuidanceSpeechVoiceQuality
  ) {
    self.identifier = identifier
    self.name = name
    self.languageCode = languageCode
    self.quality = quality
  }
}

/// Deterministic selection over voices already installed on the device.
///
/// The selector never downloads a voice or crosses a network boundary. It
/// requires an exact BCP-47 locale, excludes novelty and personal voices, then
/// prefers premium, enhanced, and default quality in that order. The system
/// locale default breaks ties so generic accessibility characters do not
/// displace the normal navigation voice.
public enum GuidanceSpeechVoiceSelector {
  public static func select(
    languageCode: String,
    candidates: [GuidanceSpeechVoiceCandidate],
    systemDefaultIdentifier: String?,
    preferredIdentifier: String? = nil
  ) -> GuidanceSpeechVoiceProfile? {
    let profiles = rankedProfiles(
      languageCode: languageCode,
      candidates: candidates,
      systemDefaultIdentifier: systemDefaultIdentifier
    )
    if let preferredIdentifier,
      let preferred = profiles.first(where: {
        $0.identifier == preferredIdentifier
      })
    {
      return preferred
    }
    return profiles.first
  }

  public static func rankedProfiles(
    languageCode: String,
    candidates: [GuidanceSpeechVoiceCandidate],
    systemDefaultIdentifier: String?
  ) -> [GuidanceSpeechVoiceProfile] {
    let requestedLanguage = normalizedLanguageCode(languageCode)
    guard !requestedLanguage.isEmpty else { return [] }

    let rankedCandidates =
      candidates
      .filter {
        normalizedLanguageCode($0.languageCode) == requestedLanguage
          && !$0.isNoveltyVoice
          && !$0.isPersonalVoice
          && !normalized($0.identifier).isEmpty
          && !normalized($0.name).isEmpty
      }
      .sorted { lhs, rhs in
        if lhs.quality != rhs.quality {
          return lhs.quality.rawValue > rhs.quality.rawValue
        }
        let lhsIsSystemDefault = lhs.identifier == systemDefaultIdentifier
        let rhsIsSystemDefault = rhs.identifier == systemDefaultIdentifier
        if lhsIsSystemDefault != rhsIsSystemDefault {
          return lhsIsSystemDefault
        }
        if lhs.name != rhs.name {
          return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return lhs.identifier < rhs.identifier
      }

    var seenIdentifiers: Set<String> = []
    return rankedCandidates.compactMap { candidate in
      guard seenIdentifiers.insert(candidate.identifier).inserted else {
        return nil
      }
      return GuidanceSpeechVoiceProfile(
        identifier: candidate.identifier,
        name: candidate.name,
        languageCode: candidate.languageCode,
        quality: candidate.quality
      )
    }
  }

  private static func normalizedLanguageCode(_ value: String) -> String {
    normalized(value).replacingOccurrences(of: "_", with: "-").lowercased()
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public struct GuidanceSpeechProsody: Equatable, Sendable {
  public let rate: Float
  public let pitchMultiplier: Float
  public let preUtteranceDelay: TimeInterval
  public let postUtteranceDelay: TimeInterval

  public static func navigation(languageCode _: String) -> GuidanceSpeechProsody {
    return GuidanceSpeechProsody(
      rate: 0.5,
      pitchMultiplier: 1,
      preUtteranceDelay: 0.03,
      postUtteranceDelay: 0.02
    )
  }
}
