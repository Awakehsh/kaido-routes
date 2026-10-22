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
        || NSClassFromString("XCTestCase") != nil
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
    return LazyAVSpeechGuidanceOutput {
      AVSpeechGuidanceOutput(
        preferredVoiceIdentifierProvider: preferredVoiceIdentifierProvider
      )
    }
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

/// Creates the speech output after launch instead of during it. Building it
/// touches `AVAudioSession`, whose first use waits on the audio server (about
/// 110 ms of the main thread on an iPhone 13 Pro launch). The home screen
/// prewarms it once its first frame is up, so starting a drive does not wait
/// either; a cue spoken before that creates it on the spot.
@MainActor
final class LazyAVSpeechGuidanceOutput: GuidanceSpeechOutput {
  var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)? {
    didSet { resolvedOutput?.eventHandler = eventHandler }
  }
  var selectedVoiceProfile: GuidanceSpeechVoiceProfile? {
    resolvedOutput?.selectedVoiceProfile
  }
  var isInterrupted: Bool { resolvedOutput?.isInterrupted ?? false }

  private let makeOutput: () -> AVSpeechGuidanceOutput
  private var resolvedOutput: AVSpeechGuidanceOutput?

  init(makeOutput: @escaping () -> AVSpeechGuidanceOutput) {
    self.makeOutput = makeOutput
  }

  func prewarm() {
    _ = resolveOutput()
  }

  func prewarmAudioSession() {
    resolveOutput().prepareAudioSession()
  }

  func prewarmVoice(languageCode: String) {
    resolveOutput().prepareVoice(languageCode: languageCode)
  }

  func speak(_ command: GuidanceSpeechCommand) throws {
    try resolveOutput().speak(command)
  }

  func stop() {
    resolvedOutput?.stop()
  }

  /// Nothing was interrupted before the output existed.
  func recoverAfterInterruption() throws -> Bool {
    try resolvedOutput?.recoverAfterInterruption() ?? false
  }

  private func resolveOutput() -> AVSpeechGuidanceOutput {
    if let resolvedOutput { return resolvedOutput }
    let output = makeOutput()
    output.eventHandler = eventHandler
    resolvedOutput = output
    return output
  }
}
