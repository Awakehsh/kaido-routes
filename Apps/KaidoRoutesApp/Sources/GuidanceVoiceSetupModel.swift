import Combine
import Foundation
import KaidoAppleAdapters
import KaidoDomain

@MainActor
protocol GuidanceVoicePreferenceStoring: AnyObject {
  func identifier(for languageCode: String) -> String?
  func setIdentifier(_ identifier: String?, for languageCode: String)
}

@MainActor
final class UserDefaultsGuidanceVoicePreferenceStore:
  GuidanceVoicePreferenceStoring
{
  private let defaults: UserDefaults
  private let keyPrefix: String

  init(
    defaults: UserDefaults = .standard,
    keyPrefix: String = "app.kaidoroutes.guidance-voice"
  ) {
    self.defaults = defaults
    self.keyPrefix = keyPrefix
  }

  func identifier(for languageCode: String) -> String? {
    guard
      let identifier = defaults.string(
        forKey: key(for: languageCode)
      )?.trimmingCharacters(in: .whitespacesAndNewlines),
      !identifier.isEmpty
    else {
      return nil
    }
    return identifier
  }

  func setIdentifier(
    _ identifier: String?,
    for languageCode: String
  ) {
    let normalizedIdentifier = identifier?.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard
      let normalizedIdentifier,
      !normalizedIdentifier.isEmpty
    else {
      defaults.removeObject(forKey: key(for: languageCode))
      return
    }
    defaults.set(
      normalizedIdentifier,
      forKey: key(for: languageCode)
    )
  }

  private func key(for languageCode: String) -> String {
    let locale =
      languageCode
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "_", with: "-")
      .lowercased()
    return "\(keyPrefix).\(locale)"
  }
}

enum GuidanceVoiceSetupState: Equatable, Sendable {
  case ready
  case preparing
  case speaking(GuidanceSpeechVoiceProfile)
  case completed(GuidanceSpeechVoiceProfile)
  case blocked(String)
}

@MainActor
final class GuidanceVoiceSetupModel: ObservableObject {
  static let japaneseLanguageCode = "ja-JP"
  static let japaneseAuditionText = "この先、左側です。"

  @Published private(set) var profiles: [GuidanceSpeechVoiceProfile] = []
  @Published private(set) var selectedGuidanceLocale: KaidoReleaseLocale
  @Published private(set) var selectedVoiceIdentifier: String?
  @Published private(set) var lastAuditionedProfile: GuidanceSpeechVoiceProfile?
  @Published private(set) var state: GuidanceVoiceSetupState = .ready

  private let preferenceStore: any GuidanceVoicePreferenceStoring
  private let output: any GuidanceVoiceAuditionOutput
  private let profileProvider: (String) -> [GuidanceSpeechVoiceProfile]
  private let guidanceLocaleDidChange: (KaidoReleaseLocale) -> Void

  init(
    guidanceLocale: KaidoReleaseLocale = .japanese,
    preferenceStore: any GuidanceVoicePreferenceStoring =
      UserDefaultsGuidanceVoicePreferenceStore(),
    output: any GuidanceVoiceAuditionOutput =
      LazyAVSpeechVoiceAuditionOutput(),
    profileProvider: @escaping (String) -> [GuidanceSpeechVoiceProfile] = {
      AVSpeechGuidanceOutput.installedVoiceProfiles(for: $0)
    },
    guidanceLocaleDidChange: @escaping (KaidoReleaseLocale) -> Void = {
      _ in
    }
  ) {
    selectedGuidanceLocale = guidanceLocale
    self.preferenceStore = preferenceStore
    self.output = output
    self.profileProvider = profileProvider
    self.guidanceLocaleDidChange = guidanceLocaleDidChange
    selectedVoiceIdentifier = preferenceStore.identifier(
      for: guidanceLocale.speechLanguageCode
    )
    output.eventHandler = { [weak self] event in
      self?.handle(event)
    }
  }

  var selectedProfile: GuidanceSpeechVoiceProfile? {
    guard let selectedVoiceIdentifier else { return nil }
    return profiles.first {
      $0.identifier == selectedVoiceIdentifier
    }
  }

  var languageCode: String {
    selectedGuidanceLocale.speechLanguageCode
  }

  var auditionText: String {
    selectedGuidanceLocale.guidanceAuditionText
  }

  var effectiveProfile: GuidanceSpeechVoiceProfile? {
    selectedProfile ?? lastAuditionedProfile ?? profiles.first
  }

  var usesAutomaticSelection: Bool {
    selectedVoiceIdentifier == nil
  }

  var canAudition: Bool {
    switch state {
    case .preparing, .speaking:
      false
    case .ready, .completed, .blocked:
      true
    }
  }

  var statusLabel: String {
    switch state {
    case .ready:
      "READY"
    case .preparing:
      "PREPARING"
    case .speaking:
      "PLAYING"
    case .completed:
      "HEARD"
    case .blocked:
      "BLOCKED"
    }
  }

  var statusDetail: String {
    switch state {
    case .ready:
      "停车后试听固定样句，不会消耗导航提示。"
    case .preparing:
      "正在解析设备已安装的\(selectedGuidanceLocale.nativeLanguageName)音色。"
    case .speaking(let profile):
      "\(profile.name) · \(profile.quality.label)"
    case .completed(let profile):
      "已试听 \(profile.name) · \(profile.quality.label)"
    case .blocked(let code):
      code
    }
  }

  func refreshProfiles() {
    let refreshed = profileProvider(languageCode)
    profiles = refreshed
    guard let selectedVoiceIdentifier else { return }
    guard !refreshed.isEmpty else { return }
    guard
      refreshed.contains(where: {
        $0.identifier == selectedVoiceIdentifier
      })
    else {
      preferenceStore.setIdentifier(nil, for: languageCode)
      self.selectedVoiceIdentifier = nil
      state = .blocked("VOICE_PREFERENCE_NO_LONGER_INSTALLED")
      return
    }
  }

  func selectVoice(identifier: String?) {
    if let identifier {
      guard
        profiles.contains(where: {
          $0.identifier == identifier
        })
      else {
        state = .blocked("VOICE_SELECTION_UNAVAILABLE")
        return
      }
    }
    output.stop()
    preferenceStore.setIdentifier(identifier, for: languageCode)
    selectedVoiceIdentifier = identifier
    lastAuditionedProfile = nil
    state = .ready
  }

  func selectGuidanceLocale(_ locale: KaidoReleaseLocale) {
    guard locale != selectedGuidanceLocale else { return }
    output.stop()
    selectedGuidanceLocale = locale
    guidanceLocaleDidChange(locale)
    profiles = []
    selectedVoiceIdentifier = preferenceStore.identifier(
      for: locale.speechLanguageCode
    )
    lastAuditionedProfile = nil
    state = .ready
    refreshProfiles()
  }

  func audition(isVehicleMoving: Bool = false) {
    guard !isVehicleMoving else {
      state = .blocked("VOICE_AUDITION_MOVING_CONTEXT")
      return
    }
    guard canAudition else { return }
    state = .preparing
    do {
      try output.audition(
        GuidanceVoiceAuditionRequest(
          languageCode: languageCode,
          preferredVoiceIdentifier: selectedVoiceIdentifier,
          spokenText: auditionText
        )
      )
    } catch let error as GuidanceVoiceAuditionOutputError {
      state = .blocked(error.code.rawValue)
    } catch {
      state = .blocked(
        GuidanceVoiceAuditionFailureCode
          .audioSessionActivationFailed.rawValue
      )
    }
  }

  func stop() {
    output.stop()
    switch state {
    case .preparing, .speaking:
      state = .ready
    case .ready, .completed, .blocked:
      break
    }
  }

  private func handle(_ event: GuidanceVoiceAuditionOutputEvent) {
    switch event {
    case .didStart(let profile):
      retainResolvedProfile(profile)
      lastAuditionedProfile = profile
      state = .speaking(profile)
    case .didFinish(let profile):
      retainResolvedProfile(profile)
      lastAuditionedProfile = profile
      state = .completed(profile)
    case .didCancel(let profile):
      retainResolvedProfile(profile)
      lastAuditionedProfile = profile
      state = .ready
    }
  }

  private func retainResolvedProfile(
    _ profile: GuidanceSpeechVoiceProfile
  ) {
    guard
      !profiles.contains(where: {
        $0.identifier == profile.identifier
      })
    else {
      return
    }
    profiles.append(profile)
    profiles.sort {
      if $0.quality != $1.quality {
        return $0.quality.rawValue > $1.quality.rawValue
      }
      return $0.name.localizedStandardCompare($1.name)
        == .orderedAscending
    }
  }
}

@MainActor
private final class LazyAVSpeechVoiceAuditionOutput:
  GuidanceVoiceAuditionOutput
{
  var eventHandler: ((GuidanceVoiceAuditionOutputEvent) -> Void)? {
    didSet {
      resolvedOutput?.eventHandler = eventHandler
    }
  }

  private var resolvedOutput: AVSpeechVoiceAuditionOutput?

  func audition(_ request: GuidanceVoiceAuditionRequest) throws {
    let output = resolveOutput()
    try output.audition(request)
  }

  func stop() {
    resolvedOutput?.stop()
  }

  private func resolveOutput() -> AVSpeechVoiceAuditionOutput {
    if let resolvedOutput {
      return resolvedOutput
    }
    let output = AVSpeechVoiceAuditionOutput()
    output.eventHandler = eventHandler
    resolvedOutput = output
    return output
  }
}
