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
      _ in nil
    }
  ) -> any GuidanceSpeechOutput {
    if isSilent {
      return SilentAppGuidanceSpeechOutput()
    }
    return AVSpeechGuidanceOutput(
      preferredVoiceIdentifierProvider: preferredVoiceIdentifierProvider
    )
  }
}

@MainActor
private final class SilentAppGuidanceSpeechOutput: GuidanceSpeechOutput {
  var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?

  func speak(_ command: GuidanceSpeechCommand) {
    eventHandler?(.didStart(command.identity))
    eventHandler?(.didFinish(command.identity))
  }

  func stop() {}
}
