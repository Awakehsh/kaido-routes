import AVFAudio
import KaidoAppleAdapters
import SwiftUI

private struct PhysicalAudioQualificationSample: Equatable {
  let languageCode: String
  let spokenText: String
}

private struct PhysicalAudioQualificationRecord: Equatable {
  let profile: GuidanceSpeechVoiceProfile
  let outputPortTypes: [String]
}

private enum PhysicalAudioQualificationState: Equatable {
  case ready
  case playing(String)
  case passed([PhysicalAudioQualificationRecord])
  case blocked(String)
}

@MainActor
private final class PhysicalAudioQualificationModel: ObservableObject {
  @Published private(set) var state: PhysicalAudioQualificationState = .ready

  private let output: any GuidanceVoiceAuditionOutput
  private let samples = [
    PhysicalAudioQualificationSample(
      languageCode: "ja-JP",
      spokenText: "K7、第三京浜・出口へ"
    ),
    PhysicalAudioQualificationSample(
      languageCode: "zh-CN",
      spokenText: "K7，前往第三京浜・出口へ"
    ),
    PhysicalAudioQualificationSample(
      languageCode: "en-US",
      spokenText: "K7, toward 第三京浜・出口へ"
    ),
  ]

  private var sampleIndex = 0
  private var activeRecord: PhysicalAudioQualificationRecord?
  private var completedRecords: [PhysicalAudioQualificationRecord] = []

  init(
    output: any GuidanceVoiceAuditionOutput =
      LazyAVSpeechVoiceAuditionOutput()
  ) {
    self.output = output
    output.eventHandler = { [weak self] event in
      self?.handle(event)
    }
  }

  var statusValue: String {
    switch state {
    case .ready:
      return "READY"
    case .playing(let languageCode):
      return "PLAYING · \(languageCode)"
    case .passed(let records):
      let summary = records.map { record in
        let ports = record.outputPortTypes.joined(separator: "+")
        return
          "\(record.profile.languageCode):"
          + "\(record.profile.quality.label):\(ports)"
      }.joined(separator: " · ")
      return "PASSED · \(summary)"
    case .blocked(let code):
      return "BLOCKED · \(code)"
    }
  }

  var canStart: Bool {
    switch state {
    case .ready, .passed, .blocked:
      true
    case .playing:
      false
    }
  }

  func start() {
    guard canStart else { return }
    output.stop()
    sampleIndex = 0
    activeRecord = nil
    completedRecords = []
    playCurrentSample()
  }

  private func playCurrentSample() {
    guard samples.indices.contains(sampleIndex) else {
      state = .passed(completedRecords)
      return
    }
    let sample = samples[sampleIndex]
    state = .playing(sample.languageCode)
    do {
      try output.audition(
        GuidanceVoiceAuditionRequest(
          languageCode: sample.languageCode,
          preferredVoiceIdentifier: nil,
          spokenText: sample.spokenText
        )
      )
    } catch let error as GuidanceVoiceAuditionOutputError {
      state = .blocked(error.code.rawValue)
    } catch {
      state = .blocked("PHYSICAL_AUDIO_OUTPUT_FAILED")
    }
  }

  private func handle(_ event: GuidanceVoiceAuditionOutputEvent) {
    guard samples.indices.contains(sampleIndex) else {
      state = .blocked("PHYSICAL_AUDIO_UNEXPECTED_CALLBACK")
      return
    }
    let expectedLanguageCode = samples[sampleIndex].languageCode
    switch event {
    case .didStart(let profile):
      let audioSession = AVAudioSession.sharedInstance()
      guard
        profile.languageCode == expectedLanguageCode,
        audioSession.category == .playback,
        audioSession.mode == .voicePrompt
      else {
        output.stop()
        state = .blocked("PHYSICAL_AUDIO_SESSION_DRIFT")
        return
      }
      let portTypes = audioSession.currentRoute.outputs
        .map(\.portType.rawValue)
        .filter { !$0.isEmpty }
        .sorted()
      guard !portTypes.isEmpty else {
        output.stop()
        state = .blocked("PHYSICAL_AUDIO_ROUTE_UNAVAILABLE")
        return
      }
      activeRecord = PhysicalAudioQualificationRecord(
        profile: profile,
        outputPortTypes: portTypes
      )
    case .didFinish(let profile):
      guard
        let activeRecord,
        activeRecord.profile == profile,
        profile.languageCode == expectedLanguageCode
      else {
        state = .blocked("PHYSICAL_AUDIO_COMPLETION_DRIFT")
        return
      }
      completedRecords.append(activeRecord)
      self.activeRecord = nil
      sampleIndex += 1
      Task { @MainActor [weak self] in
        self?.playCurrentSample()
      }
    case .didCancel:
      if case .blocked = state {
        return
      }
      state = .blocked("PHYSICAL_AUDIO_CANCELLED")
    }
  }
}

struct PhysicalAudioQualificationHost: View {
  @StateObject private var model = PhysicalAudioQualificationModel()

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Physical audio technical qualification")
        .font(.system(size: 24, weight: .black, design: .rounded))
      Text(
        "Parked test only. It verifies installed voice callbacks and the "
          + "voice-prompt output route; it does not qualify pronunciation "
          + "or acoustic quality."
      )
      .font(.system(size: 13, weight: .medium))

      Text(model.statusValue)
        .font(.system(size: 12, weight: .bold, design: .monospaced))
        .accessibilityIdentifier("physical-audio-qualification-status")
        .accessibilityValue(model.statusValue)

      Button("Run Japanese, Chinese, and English audio") {
        model.start()
      }
      .buttonStyle(.borderedProminent)
      .disabled(!model.canStart)
      .accessibilityIdentifier("physical-audio-qualification-start")
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(KaidoTheme.asphalt.ignoresSafeArea())
    .foregroundStyle(KaidoTheme.routeWhite)
  }
}
