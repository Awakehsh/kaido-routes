import AppIntents
import KaidoAppleAdapters

enum DriveControlAction: String, AppEnum {
  case repeatDirection, mute, unmute, addLap, removeLap, rest, resume, endNavigation

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Drive action"
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .repeatDirection: "Repeat current direction",
    .mute: "Mute guidance",
    .unmute: "Unmute guidance",
    .addLap: "Add one lap",
    .removeLap: "Remove one lap",
    .rest: "Take a break",
    .resume: "Resume navigation",
    .endNavigation: "End navigation",
  ]
}

@MainActor
enum ActiveDriveControl {
  static weak var model: WholeShutoProductModel?
}

struct DriveControlIntent: AppIntent {
  static let title: LocalizedStringResource = "Control drive"
  static let openAppWhenRun = true
  @available(iOS 26.0, *)
  static let supportedModes: IntentModes = .foreground

  @Parameter(title: "Action") var action: DriveControlAction
  static var parameterSummary: some ParameterSummary { Summary("\(\.$action)") }

  init() {}
  init(action: DriveControlAction) { self.action = action }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard let model = ActiveDriveControl.model else {
      return .result(dialog: "Open Kaido Routes to select or resume a route.")
    }
    if action == .resume {
      if model.isLiveDrive && model.isPlaying {
        return .result(dialog: "Navigation is already running.")
      }
      if await model.resumeLiveJourney() {
        return .result(dialog: "Navigation resumed. Waiting for a reliable position.")
      }
      return .result(dialog: "There is no navigation session ready to resume.")
    }
    guard model.isLiveDrive, model.phase != .completed else {
      return .result(dialog: "There is no active navigation session.")
    }
    switch action {
    case .repeatDirection:
      guard let text = model.currentInstructionForRepeat else {
        return .result(dialog: "No current direction is ready to repeat.")
      }
      // Siri reads the validated current text itself rather than competing
      // with the navigation audio session while Siri is speaking.
      return .result(dialog: "\(text)")
    case .mute:
      model.setSpeechMode(.muted)
      return .result(dialog: "Guidance is muted. Navigation continues.")
    case .unmute:
      model.setSpeechMode(.full)
      return .result(dialog: "Guidance is on.")
    case .addLap:
      if await model.addOneLap() { return .result(dialog: "One lap added.") }
      return .result(dialog: "A lap cannot be added at the current position.")
    case .removeLap:
      if await model.dropOneLap() { return .result(dialog: "One lap removed.") }
      return .result(dialog: "There is no complete remaining lap to remove.")
    case .rest:
      if model.liveLocationState == .resting {
        return .result(dialog: "Navigation is paused for your break.")
      }
      if await model.restLiveJourney() {
        return .result(dialog: "Navigation is paused for your break.")
      }
      return .result(dialog: "Navigation could not be paused.")
    case .endNavigation:
      let sessionIdentity = model.liveSessionIdentity
      let routePlan = model.selectedRoute?.routePlan
      try await requestConfirmation(dialog: "End navigation? Route guidance will stop.")
      guard ActiveDriveControl.model === model, model.isLiveDrive,
        model.liveSessionIdentity == sessionIdentity,
        model.selectedRoute?.routePlan == routePlan
      else {
        return .result(dialog: "The navigation session has already ended.")
      }
      model.reset()
      return .result(dialog: "Navigation ended.")
    case .resume:
      return .result(dialog: "Navigation is already running.")
    }
  }
}

struct KaidoDriveShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: DriveControlIntent(),
      phrases: ["\(\.$action) in \(.applicationName)"],
      shortTitle: "Drive controls",
      systemImageName: "steeringwheel"
    )
  }
}
