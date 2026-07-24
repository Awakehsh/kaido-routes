import Foundation

public struct GuidanceSpeechIdentity: Equatable, Hashable, Sendable {
  public let promptID: String
  public let anchorID: String
  public let anchorOccurrenceID: String

  public init(
    promptID: String,
    anchorID: String,
    anchorOccurrenceID: String
  ) {
    self.promptID = promptID
    self.anchorID = anchorID
    self.anchorOccurrenceID = anchorOccurrenceID
  }
}

public struct GuidanceSpeechCommand: Equatable, Sendable {
  public let identity: GuidanceSpeechIdentity
  public let routePlanID: String
  public let languageCode: String
  public let spokenText: String

  public init(
    identity: GuidanceSpeechIdentity,
    routePlanID: String,
    languageCode: String,
    spokenText: String
  ) {
    self.identity = identity
    self.routePlanID = routePlanID
    self.languageCode = languageCode
    self.spokenText = spokenText
  }
}

public enum GuidanceSpeechSuppressionReason: String, Equatable, Sendable {
  case notAuthorized = "NOT_AUTHORIZED"
  case duplicate = "DUPLICATE"
  case interrupted = "INTERRUPTED"
  case stopped = "STOPPED"
}

public enum GuidanceSpeechScheduleResult: Equatable, Sendable {
  case speak(
    GuidanceSpeechCommand,
    replacing: GuidanceSpeechIdentity?
  )
  case suppressed(GuidanceSpeechSuppressionReason)
}

public enum GuidanceSpeechLifecycleState: Equatable, Sendable {
  case idle
  case speaking(GuidanceSpeechIdentity)
  case interrupted
  case stopped
}

public enum GuidanceSpeechSchedulerError: Error, Equatable, Sendable {
  case missingExpectedRoutePlanID
  case routePlanMismatch
  case inconsistentProjectionIdentity
  case emptySpokenText
  case emptyLanguageCode
}

/// Admits already projected, occurrence-scoped voice commands exactly once.
///
/// The navigation engine owns prompt emission. This scheduler cannot create
/// speech authority from a persistent frame or a SwiftUI redraw. Interruption
/// drops the active command and never replays it after the interruption ends.
public struct GuidanceSpeechScheduler: Sendable {
  public let expectedRoutePlanID: String
  public private(set) var state: GuidanceSpeechLifecycleState = .idle
  public private(set) var activeCommand: GuidanceSpeechCommand?
  public private(set) var consumedIdentities: Set<GuidanceSpeechIdentity> = []

  public init(expectedRoutePlanID: String) throws {
    guard !Self.normalized(expectedRoutePlanID).isEmpty else {
      throw GuidanceSpeechSchedulerError.missingExpectedRoutePlanID
    }
    self.expectedRoutePlanID = expectedRoutePlanID
  }

  public mutating func submit(
    _ projection: NavigationPresentationProjection
  ) throws -> GuidanceSpeechScheduleResult {
    guard projection.voice.shouldSpeak else {
      return .suppressed(.notAuthorized)
    }

    let identity = try validatedIdentity(projection)
    guard !consumedIdentities.contains(identity) else {
      return .suppressed(.duplicate)
    }

    let text = Self.normalized(projection.voice.spokenText)
    guard !text.isEmpty else {
      throw GuidanceSpeechSchedulerError.emptySpokenText
    }
    let languageCode = Self.normalized(projection.voice.locale.rawValue)
    guard !languageCode.isEmpty else {
      throw GuidanceSpeechSchedulerError.emptyLanguageCode
    }

    consumedIdentities.insert(identity)
    guard state != .interrupted else {
      return .suppressed(.interrupted)
    }
    guard state != .stopped else {
      return .suppressed(.stopped)
    }

    let replacedIdentity = activeCommand?.identity
    let command = GuidanceSpeechCommand(
      identity: identity,
      routePlanID: expectedRoutePlanID,
      languageCode: languageCode,
      spokenText: text
    )
    activeCommand = command
    state = .speaking(identity)
    return .speak(command, replacing: replacedIdentity)
  }

  @discardableResult
  public mutating func didFinish(_ identity: GuidanceSpeechIdentity) -> Bool {
    finishIfActive(identity)
  }

  @discardableResult
  public mutating func didCancel(_ identity: GuidanceSpeechIdentity) -> Bool {
    finishIfActive(identity)
  }

  @discardableResult
  public mutating func interruptionBegan() -> GuidanceSpeechIdentity? {
    let interruptedIdentity = activeCommand?.identity
    activeCommand = nil
    state = .interrupted
    return interruptedIdentity
  }

  public mutating func interruptionEnded() {
    guard state == .interrupted else { return }
    state = .idle
  }

  @discardableResult
  public mutating func stop() -> GuidanceSpeechIdentity? {
    let stoppedIdentity = activeCommand?.identity
    activeCommand = nil
    state = .stopped
    return stoppedIdentity
  }

  public mutating func resume() {
    guard state == .stopped else { return }
    state = .idle
  }

  private mutating func finishIfActive(
    _ identity: GuidanceSpeechIdentity
  ) -> Bool {
    guard activeCommand?.identity == identity else { return false }
    activeCommand = nil
    if case .speaking = state {
      state = .idle
    }
    return true
  }

  private func validatedIdentity(
    _ projection: NavigationPresentationProjection
  ) throws -> GuidanceSpeechIdentity {
    let phone = projection.iPhone
    let carPlay = projection.carPlay
    guard
      phone.routePlanID == expectedRoutePlanID,
      carPlay.routePlanID == expectedRoutePlanID
    else {
      throw GuidanceSpeechSchedulerError.routePlanMismatch
    }

    let promptID = Self.normalized(projection.voice.promptID)
    let anchorID = Self.normalized(phone.guidanceAnchorID)
    let anchorOccurrenceID = Self.normalized(
      phone.guidanceAnchorOccurrenceID
    )
    guard
      !promptID.isEmpty,
      !anchorID.isEmpty,
      !anchorOccurrenceID.isEmpty,
      phone.guidancePromptID == promptID,
      carPlay.guidancePromptID == promptID,
      carPlay.guidanceAnchorID == anchorID,
      carPlay.guidanceAnchorOccurrenceID == anchorOccurrenceID
    else {
      throw GuidanceSpeechSchedulerError.inconsistentProjectionIdentity
    }
    return GuidanceSpeechIdentity(
      promptID: promptID,
      anchorID: anchorID,
      anchorOccurrenceID: anchorOccurrenceID
    )
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
