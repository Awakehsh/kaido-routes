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
  static let japaneseAuditionText =
    KaidoReleaseLocale.japanese.guidanceAuditionText

  @Published private(set) var profiles: [GuidanceSpeechVoiceProfile] = []
  @Published private(set) var selectedGuidanceLocale: KaidoReleaseLocale
  @Published private(set) var selectedVoiceIdentifier: String?
  @Published private(set) var lastAuditionedProfile: GuidanceSpeechVoiceProfile?
  @Published private(set) var upgradeAuditionProfile: GuidanceSpeechVoiceProfile?
  @Published private(set) var state: GuidanceVoiceSetupState = .ready

  private let preferenceStore: any GuidanceVoicePreferenceStoring
  private let output: any GuidanceVoiceAuditionOutput
  private let profileProvider: (String) -> [GuidanceSpeechVoiceProfile]
  private let guidanceLocaleDidChange: (KaidoReleaseLocale) -> Void
  private var rejectedAuditionProfileIdentifier: String?

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
    selectedProfile ?? profiles.first
  }

  var recommendedUpgradeProfile: GuidanceSpeechVoiceProfile? {
    guard
      let selectedProfile,
      let highestRankedProfile = profiles.first,
      highestRankedProfile.identifier != selectedProfile.identifier,
      highestRankedProfile.quality.rawValue
        > selectedProfile.quality.rawValue
    else {
      return nil
    }
    return highestRankedProfile
  }

  var canUseLastAuditionedUpgrade: Bool {
    guard
      case .completed(let completedProfile) = state,
      let upgradeAuditionProfile,
      let recommendedUpgradeProfile,
      completedProfile == upgradeAuditionProfile,
      upgradeAuditionProfile == recommendedUpgradeProfile,
      lastAuditionedProfile == completedProfile
    else {
      return false
    }
    return true
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

  func refreshProfiles() {
    let refreshed = profileProvider(languageCode)
    profiles = refreshed
    if let upgradeAuditionProfile,
      !refreshed.contains(upgradeAuditionProfile)
    {
      self.upgradeAuditionProfile = nil
      lastAuditionedProfile = nil
    }
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
    upgradeAuditionProfile = nil
    rejectedAuditionProfileIdentifier = nil
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
    upgradeAuditionProfile = nil
    rejectedAuditionProfileIdentifier = nil
    state = .ready
    refreshProfiles()
  }

  func audition(isVehicleMoving: Bool = false) {
    beginAudition(
      preferredVoiceIdentifier: selectedVoiceIdentifier,
      upgradeProfile: nil,
      isVehicleMoving: isVehicleMoving
    )
  }

  func auditionRecommendedUpgrade(isVehicleMoving: Bool = false) {
    guard let recommendedUpgradeProfile else {
      state = .blocked("VOICE_UPGRADE_NOT_AVAILABLE")
      return
    }
    beginAudition(
      preferredVoiceIdentifier: recommendedUpgradeProfile.identifier,
      upgradeProfile: recommendedUpgradeProfile,
      isVehicleMoving: isVehicleMoving
    )
  }

  func useLastAuditionedUpgrade() {
    guard
      canUseLastAuditionedUpgrade,
      let upgradeAuditionProfile
    else {
      state = .blocked("VOICE_UPGRADE_CONFIRMATION_UNAVAILABLE")
      return
    }
    selectVoice(identifier: upgradeAuditionProfile.identifier)
  }

  private func beginAudition(
    preferredVoiceIdentifier: String?,
    upgradeProfile: GuidanceSpeechVoiceProfile?,
    isVehicleMoving: Bool
  ) {
    guard !isVehicleMoving else {
      state = .blocked("VOICE_AUDITION_MOVING_CONTEXT")
      return
    }
    guard canAudition else { return }
    rejectedAuditionProfileIdentifier = nil
    upgradeAuditionProfile = upgradeProfile
    lastAuditionedProfile = nil
    state = .preparing
    do {
      try output.audition(
        GuidanceVoiceAuditionRequest(
          languageCode: languageCode,
          preferredVoiceIdentifier: preferredVoiceIdentifier,
          spokenText: auditionText
        )
      )
    } catch let error as GuidanceVoiceAuditionOutputError {
      upgradeAuditionProfile = nil
      state = .blocked(error.code.rawValue)
    } catch {
      upgradeAuditionProfile = nil
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
    let profile: GuidanceSpeechVoiceProfile
    switch event {
    case .didStart(let startedProfile):
      profile = startedProfile
    case .didFinish(let finishedProfile):
      profile = finishedProfile
    case .didCancel(let cancelledProfile):
      profile = cancelledProfile
    }
    guard rejectedAuditionProfileIdentifier != profile.identifier else {
      return
    }
    if let upgradeAuditionProfile,
      profile.identifier != upgradeAuditionProfile.identifier
    {
      rejectedAuditionProfileIdentifier = profile.identifier
      self.upgradeAuditionProfile = nil
      lastAuditionedProfile = nil
      state = .blocked("VOICE_UPGRADE_RESOLUTION_DRIFT")
      output.stop()
      return
    }
    retainResolvedProfile(profile)
    lastAuditionedProfile = profile
    switch event {
    case .didStart:
      state = .speaking(profile)
    case .didFinish:
      state = .completed(profile)
    case .didCancel:
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
