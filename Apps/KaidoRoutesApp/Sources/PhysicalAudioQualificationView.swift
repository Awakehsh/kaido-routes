#if DEBUG
  import AVFAudio
import KaidoAppleAdapters
  import KaidoPresentation
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

    private let output: any GuidanceSpeechOutput
    private let samples = [
    PhysicalAudioQualificationSample(
      languageCode: "ja-JP",
        spokenText: "音声テスト。一、二、三。"
      ),
    PhysicalAudioQualificationSample(
      languageCode: "zh-CN",
        spokenText: "语音测试：一、二、三。"
      ),
    PhysicalAudioQualificationSample(
      languageCode: "en-US",
        spokenText: "Voice test. One, two, three."
      ),
  ]

  private var sampleIndex = 0
  private var activeRecord: PhysicalAudioQualificationRecord?
  private var completedRecords: [PhysicalAudioQualificationRecord] = []

  init(
      output: any GuidanceSpeechOutput = AVSpeechGuidanceOutput()
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
        let id = "physical-audio.\(sampleIndex)"
        try output.speak(
          GuidanceSpeechCommand(
            identity: GuidanceSpeechIdentity(
              promptID: id, anchorID: "TEST", anchorOccurrenceID: id),
            routePlanID: "physical-audio",
            languageCode: sample.languageCode,
          spokenText: sample.spokenText
        )
      )
      } catch let error as GuidanceSpeechOutputError {
        state = .blocked(error.code.rawValue)
    } catch {
      state = .blocked("PHYSICAL_AUDIO_OUTPUT_FAILED")
    }
  }

    private func handle(_ event: GuidanceSpeechOutputEvent) {
      guard samples.indices.contains(sampleIndex) else {
      state = .blocked("PHYSICAL_AUDIO_UNEXPECTED_CALLBACK")
      return
    }
    let expectedLanguageCode = samples[sampleIndex].languageCode
    switch event {
      case .didStart(let identity):
        let audioSession = AVAudioSession.sharedInstance()
      guard
          identity.promptID == "physical-audio.\(sampleIndex)",
          let profile = output.selectedVoiceProfile,
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
      case .didFinish(let identity):
        guard
          identity.promptID == "physical-audio.\(sampleIndex)",
          let profile = output.selectedVoiceProfile,
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
          try? await Task.sleep(nanoseconds: 1_000_000_000)
          self?.playCurrentSample()
      }
      case .didCancel, .interruptionBegan:
        if case .blocked = state {
        return
      }
      state = .blocked("PHYSICAL_AUDIO_CANCELLED")
      case .interruptionEnded:
        break
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
#endif