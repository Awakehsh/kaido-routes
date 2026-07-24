import Foundation
import KaidoDomain

private struct RouteEditorLocaleCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init?(stringValue: String) {
    self.stringValue = stringValue
  }

  init?(intValue: Int) {
    return nil
  }

  init(_ locale: KaidoReleaseLocale) {
    stringValue = locale.rawValue
  }
}

/// Complete display text for the three release locales.
public struct RouteEditorLocalizedText: Codable, Equatable, Sendable {
  public let values: [KaidoReleaseLocale: String]

  public init(values: [KaidoReleaseLocale: String]) {
    self.values = values
  }

  public func value(for locale: KaidoReleaseLocale) -> String? {
    values[locale]
  }

  package var validationIssues: [String] {
    var issues: [String] = []
    let expectedLocales = Set(KaidoReleaseLocale.allCases)
    let actualLocales = Set(values.keys)
    if actualLocales != expectedLocales {
      issues.append("localized text must cover every release locale exactly")
    }
    for locale in KaidoReleaseLocale.allCases {
      guard let value = values[locale],
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        issues.append("localized text is empty for \(locale.rawValue)")
        continue
      }
    }
    return issues.sorted()
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: RouteEditorLocaleCodingKey.self)
    var decoded: [KaidoReleaseLocale: String] = [:]
    for key in container.allKeys {
      guard let locale = KaidoReleaseLocale(rawValue: key.stringValue) else {
        throw DecodingError.dataCorruptedError(
          forKey: key,
          in: container,
          debugDescription: "Unknown route-editor locale \(key.stringValue)"
        )
      }
      decoded[locale] = try container.decode(String.self, forKey: key)
    }
    values = decoded
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: RouteEditorLocaleCodingKey.self)
    for locale in KaidoReleaseLocale.allCases {
      guard let value = values[locale] else { continue }
      try container.encode(value, forKey: RouteEditorLocaleCodingKey(locale))
    }
  }
}

public struct ReviewedRouteEditorEntrancePresentation: Codable, Equatable, Sendable {
  public let facilityID: String
  public let title: RouteEditorLocalizedText

  public init(facilityID: String, title: RouteEditorLocalizedText) {
    self.facilityID = facilityID
    self.title = title
  }

  private enum CodingKeys: String, CodingKey {
    case facilityID = "facility_id"
    case title
  }
}

public struct ReviewedRouteEditorDecisionPresentation: Codable, Equatable, Sendable {
  public let decisionPointID: String
  public let title: RouteEditorLocalizedText

  public init(decisionPointID: String, title: RouteEditorLocalizedText) {
    self.decisionPointID = decisionPointID
    self.title = title
  }

  private enum CodingKeys: String, CodingKey {
    case decisionPointID = "decision_point_id"
    case title
  }
}

public struct ReviewedRouteEditorChoicePresentation: Codable, Equatable, Sendable {
  public let choiceID: String
  public let title: RouteEditorLocalizedText
  public let detail: RouteEditorLocalizedText

  public init(
    choiceID: String,
    title: RouteEditorLocalizedText,
    detail: RouteEditorLocalizedText
  ) {
    self.choiceID = choiceID
    self.title = title
    self.detail = detail
  }

  private enum CodingKeys: String, CodingKey {
    case choiceID = "choice_id"
    case title
    case detail
  }
}

/// Snapshot-bound display data for one exact reviewed editor catalog.
///
/// This value owns labels only. It cannot create choices, movements, or route
/// occurrences, and it is not released until the enclosing artifact evidence
/// gate succeeds.
public struct ReviewedRouteEditorPresentationCatalog: Codable, Equatable, Sendable {
  public let id: String
  public let networkSnapshotID: String
  public let entrances: [ReviewedRouteEditorEntrancePresentation]
  public let decisionPoints: [ReviewedRouteEditorDecisionPresentation]
  public let choices: [ReviewedRouteEditorChoicePresentation]

  public init(
    id: String,
    networkSnapshotID: String,
    entrances: [ReviewedRouteEditorEntrancePresentation],
    decisionPoints: [ReviewedRouteEditorDecisionPresentation],
    choices: [ReviewedRouteEditorChoicePresentation]
  ) {
    self.id = id
    self.networkSnapshotID = networkSnapshotID
    self.entrances = entrances
    self.decisionPoints = decisionPoints
    self.choices = choices
  }

  public func title(
    forEntrance facilityID: String,
    locale: KaidoReleaseLocale
  ) -> String? {
    entrances.first { $0.facilityID == facilityID }?.title.value(for: locale)
  }

  public func title(
    forDecisionPoint decisionPointID: String,
    locale: KaidoReleaseLocale
  ) -> String? {
    decisionPoints.first { $0.decisionPointID == decisionPointID }?
      .title.value(for: locale)
  }

  public func presentation(
    forChoice choiceID: String
  ) -> ReviewedRouteEditorChoicePresentation? {
    choices.first { $0.choiceID == choiceID }
  }

  public func validationIssues(
    for editorCatalog: ReviewedRouteEditorCatalog
  ) -> [String] {
    var issues: [String] = []
    if normalized(id).isEmpty {
      issues.append("editor presentation catalog ID is empty")
    }
    if normalized(networkSnapshotID).isEmpty {
      issues.append("editor presentation network snapshot ID is empty")
    }
    if networkSnapshotID != editorCatalog.networkSnapshotID {
      issues.append("editor presentation network snapshot does not match editor catalog")
    }

    validateCoverage(
      actualIDs: entrances.map(\.facilityID),
      expectedIDs: editorCatalog.entrances.map(\.facilityID),
      subject: "entrance",
      issues: &issues
    )
    validateCoverage(
      actualIDs: decisionPoints.map(\.decisionPointID),
      expectedIDs: editorCatalog.decisionPoints.map(\.id),
      subject: "decision point",
      issues: &issues
    )
    validateCoverage(
      actualIDs: choices.map(\.choiceID),
      expectedIDs: editorCatalog.decisionPoints.flatMap(\.choices).map(\.id),
      subject: "choice",
      issues: &issues
    )

    for entrance in entrances {
      appendLocalizedIssues(
        entrance.title.validationIssues,
        subject: "entrance \(entrance.facilityID) title",
        issues: &issues
      )
    }
    for decisionPoint in decisionPoints {
      appendLocalizedIssues(
        decisionPoint.title.validationIssues,
        subject: "decision point \(decisionPoint.decisionPointID) title",
        issues: &issues
      )
    }
    for choice in choices {
      appendLocalizedIssues(
        choice.title.validationIssues,
        subject: "choice \(choice.choiceID) title",
        issues: &issues
      )
      appendLocalizedIssues(
        choice.detail.validationIssues,
        subject: "choice \(choice.choiceID) detail",
        issues: &issues
      )
    }

    return Array(Set(issues)).sorted()
  }

  private enum CodingKeys: String, CodingKey {
    case id = "presentation_catalog_id"
    case networkSnapshotID = "network_snapshot_id"
    case entrances
    case decisionPoints = "decision_points"
    case choices
  }

  private func validateCoverage(
    actualIDs: [String],
    expectedIDs: [String],
    subject: String,
    issues: inout [String]
  ) {
    if actualIDs.contains(where: { normalized($0).isEmpty }) {
      issues.append("editor presentation \(subject) ID is empty")
    }
    if Set(actualIDs).count != actualIDs.count {
      issues.append("editor presentation \(subject) IDs are not unique")
    }
    let actual = Set(actualIDs)
    let expected = Set(expectedIDs)
    for missing in expected.subtracting(actual).sorted() {
      issues.append("editor presentation is missing \(subject) \(missing)")
    }
    for orphan in actual.subtracting(expected).sorted() {
      issues.append("editor presentation contains orphan \(subject) \(orphan)")
    }
  }

  private func appendLocalizedIssues(
    _ localizedIssues: [String],
    subject: String,
    issues: inout [String]
  ) {
    issues.append(contentsOf: localizedIssues.map { "\(subject): \($0)" })
  }

  private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
