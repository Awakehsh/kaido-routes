import AVFAudio
import Foundation
import KaidoAppleAdapters
import KaidoPresentation

@MainActor
enum AppGuidanceSpeechOutputFactory {
  static let silentLaunchArgument = "-KAIDO-SILENT-AUDIO"

  static var isSilent: Bool {
    #if DEBUG
      ProcessInfo.processInfo.arguments.contains(silentLaunchArgument)
    #else
      false
    #endif
  }

  static func make(
    preferredVoiceIdentifierProvider: @escaping (String) -> String? = {
      UserDefaultsGuidanceVoicePreferenceStore().identifier(for: $0)
    }
  ) -> any GuidanceSpeechOutput {
    if isSilent {
      return SilentAppGuidanceSpeechOutput()
    }
    return AVSpeechGuidanceOutput(
      preferredVoiceIdentifierProvider: preferredVoiceIdentifierProvider
    )
  }

  static func makeAudition() -> any GuidanceVoiceAuditionOutput {
    isSilent ? SilentAppVoiceAuditionOutput() : LazyAVSpeechVoiceAuditionOutput()
  }
}

@MainActor
private final class SilentAppVoiceAuditionOutput: GuidanceVoiceAuditionOutput {
  var eventHandler: ((GuidanceVoiceAuditionOutputEvent) -> Void)?

  func audition(_ request: GuidanceVoiceAuditionRequest) throws {
    guard let profile = AVSpeechGuidanceOutput.preferredInstalledVoiceProfile(
      for: request.languageCode,
      preferredIdentifier: request.preferredVoiceIdentifier
        ?? AVSpeechSynthesisVoice(language: request.languageCode)?.identifier
    ) else { throw GuidanceVoiceAuditionOutputError.voiceUnavailable(request.languageCode) }
    eventHandler?(.didStart(profile))
    eventHandler?(.didFinish(profile))
  }

  func stop() {}
}

@MainActor
private final class SilentAppGuidanceSpeechOutput: GuidanceSpeechOutput {
  var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?
  private(set) var selectedVoiceProfile: GuidanceSpeechVoiceProfile?

  func speak(_ command: GuidanceSpeechCommand) {
    selectedVoiceProfile = GuidanceSpeechVoiceProfile(
      identifier: "app.kaidoroutes.silent-test-output",
      name: "Silent test output",
      languageCode: command.languageCode,
      quality: .defaultQuality
    )
    eventHandler?(.didStart(command.identity))
    eventHandler?(.didFinish(command.identity))
  }

  func stop() {}
}
