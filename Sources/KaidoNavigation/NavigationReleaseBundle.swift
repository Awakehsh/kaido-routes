import Foundation
import KaidoDomain
import KaidoRouting

public enum NavigationReleaseBundleIssue: Equatable, Sendable {
  case invalidNetworkSnapshot
  case routePlanSnapshotMismatch
  case invalidRoutePlan
  case editorCatalogSnapshotMismatch
  case invalidEditorCatalog([String])
  case unknownRouteEntrance
  case routeEntranceEdgeMismatch
  case unknownRouteExit
  case invalidRuntimeConfiguration(String)
  case duplicateDecisionZoneForMovement(String)
  case missingDecisionZoneForMovement(String)
  case missingGuidanceForMovement(String)
  case duplicateJunctionViewID(String)
  case invalidJunctionView(String)
  case junctionViewSnapshotMismatch(String)
  case junctionViewOccurrenceMismatch(String)
  case unregisteredJunctionView(String)
  case junctionViewDefinitionMismatch(String)
  case orphanedJunctionView(String)

  public var code: String {
    switch self {
    case .invalidNetworkSnapshot:
      "INVALID_NETWORK_SNAPSHOT"
    case .routePlanSnapshotMismatch:
      "ROUTE_PLAN_SNAPSHOT_MISMATCH"
    case .invalidRoutePlan:
      "INVALID_ROUTE_PLAN"
    case .editorCatalogSnapshotMismatch:
      "EDITOR_CATALOG_SNAPSHOT_MISMATCH"
    case .invalidEditorCatalog:
      "INVALID_EDITOR_CATALOG"
    case .unknownRouteEntrance:
      "UNKNOWN_ROUTE_ENTRANCE"
    case .routeEntranceEdgeMismatch:
      "ROUTE_ENTRANCE_EDGE_MISMATCH"
    case .unknownRouteExit:
      "UNKNOWN_ROUTE_EXIT"
    case .invalidRuntimeConfiguration:
      "INVALID_RUNTIME_CONFIGURATION"
    case .duplicateDecisionZoneForMovement:
      "DUPLICATE_DECISION_ZONE_FOR_MOVEMENT"
    case .missingDecisionZoneForMovement:
      "MISSING_DECISION_ZONE_FOR_MOVEMENT"
    case .missingGuidanceForMovement:
      "MISSING_GUIDANCE_FOR_MOVEMENT"
    case .duplicateJunctionViewID:
      "DUPLICATE_JUNCTION_VIEW_ID"
    case .invalidJunctionView:
      "INVALID_JUNCTION_VIEW"
    case .junctionViewSnapshotMismatch:
      "JUNCTION_VIEW_SNAPSHOT_MISMATCH"
    case .junctionViewOccurrenceMismatch:
      "JUNCTION_VIEW_OCCURRENCE_MISMATCH"
    case .unregisteredJunctionView:
      "UNREGISTERED_JUNCTION_VIEW"
    case .junctionViewDefinitionMismatch:
      "JUNCTION_VIEW_DEFINITION_MISMATCH"
    case .orphanedJunctionView:
      "ORPHANED_JUNCTION_VIEW"
    }
  }

  var sortKey: String {
    switch self {
    case .invalidEditorCatalog(let details):
      "\(code):\(details.joined(separator: ","))"
    case .invalidRuntimeConfiguration(let detail):
      "\(code):\(detail)"
    case .duplicateDecisionZoneForMovement(let id),
      .missingDecisionZoneForMovement(let id),
      .missingGuidanceForMovement(let id),
      .duplicateJunctionViewID(let id),
      .invalidJunctionView(let id),
      .junctionViewSnapshotMismatch(let id),
      .junctionViewOccurrenceMismatch(let id),
      .unregisteredJunctionView(let id),
      .junctionViewDefinitionMismatch(let id),
      .orphanedJunctionView(let id):
      "\(code):\(id)"
    default:
      code
    }
  }
}

public enum NavigationReleaseBundleError: Error, Equatable, Sendable {
  case invalid([NavigationReleaseBundleIssue])
}

/// One validated, platform-light runtime asset set for an exact RoutePlan.
///
/// This type proves identity coherence only. It does not promote synthetic,
/// proposed, stale, or locally valid evidence into released road data.
public struct NavigationReleaseBundle: Equatable, Sendable {
  public let networkSnapshot: NetworkSnapshot
  public let routePlan: RoutePlan
  public let editorCatalog: ReviewedRouteEditorCatalog
  public let matcherCorridor: RouteMatcherCorridor
  public let decisionZones: [DecisionZoneProgressDefinition]
  public let releasedGuidance: [ReleasedGuidanceDefinition]
  public let junctionViews: [JunctionViewDefinition]

  public init(
    networkSnapshot: NetworkSnapshot,
    routePlan: RoutePlan,
    editorCatalog: ReviewedRouteEditorCatalog,
    matcherCorridor: RouteMatcherCorridor,
    decisionZones: [DecisionZoneProgressDefinition],
    releasedGuidance: [ReleasedGuidanceDefinition],
    junctionViews: [JunctionViewDefinition] = []
  ) throws {
    let issues = Self.validationIssues(
      networkSnapshot: networkSnapshot,
      routePlan: routePlan,
      editorCatalog: editorCatalog,
      matcherCorridor: matcherCorridor,
      decisionZones: decisionZones,
      releasedGuidance: releasedGuidance,
      junctionViews: junctionViews
    )
    guard issues.isEmpty else {
      throw NavigationReleaseBundleError.invalid(issues)
    }

    self.networkSnapshot = networkSnapshot
    self.routePlan = routePlan
    self.editorCatalog = editorCatalog
    self.matcherCorridor = matcherCorridor
    self.decisionZones = decisionZones
    self.releasedGuidance = releasedGuidance
    self.junctionViews = junctionViews
  }

  private static func validationIssues(
    networkSnapshot: NetworkSnapshot,
    routePlan: RoutePlan,
    editorCatalog: ReviewedRouteEditorCatalog,
    matcherCorridor: RouteMatcherCorridor,
    decisionZones: [DecisionZoneProgressDefinition],
    releasedGuidance: [ReleasedGuidanceDefinition],
    junctionViews: [JunctionViewDefinition]
  ) -> [NavigationReleaseBundleIssue] {
    var issues: [NavigationReleaseBundleIssue] = []

    if normalized(networkSnapshot.id).isEmpty
      || networkSnapshot.status != .active
      || !isISO8601DateTime(networkSnapshot.effectiveAt)
    {
      issues.append(.invalidNetworkSnapshot)
    }
    if routePlan.networkSnapshotID != networkSnapshot.id {
      issues.append(.routePlanSnapshotMismatch)
    }
    if !routePlanIsValid(routePlan) {
      issues.append(.invalidRoutePlan)
    }

    let catalogIssues = editorCatalog.validationIssues
    if !catalogIssues.isEmpty {
      issues.append(.invalidEditorCatalog(catalogIssues))
    }
    if editorCatalog.networkSnapshotID != networkSnapshot.id {
      issues.append(.editorCatalogSnapshotMismatch)
    }
    if let entrance = editorCatalog.entrances.first(where: {
      $0.facilityID == routePlan.entryFacilityID
    }) {
      if routePlan.occurrences.first?.kind != .edge
        || routePlan.occurrences.first?.entityID != entrance.initialEdgeID
      {
        issues.append(.routeEntranceEdgeMismatch)
      }
    } else {
      issues.append(.unknownRouteEntrance)
    }
    let catalogExitIDs = Set<String>(
      editorCatalog.decisionPoints.flatMap(\.choices).compactMap { choice -> String? in
        guard case .exitFacility(let id) = choice.destination else { return nil }
        return id
      }
    )
    if !catalogExitIDs.contains(routePlan.exitFacilityID) {
      issues.append(.unknownRouteExit)
    }

    issues.append(
      contentsOf: NavigationRuntimeConfigurationValidator.issues(
        routePlan: routePlan,
        matcherCorridor: matcherCorridor,
        decisionZones: decisionZones,
        releasedGuidance: releasedGuidance
      ).map(NavigationReleaseBundleIssue.invalidRuntimeConfiguration)
    )

    let movementOccurrenceIDs = routePlan.occurrences
      .filter { $0.kind == .junctionMovement }
      .map(\.id)
    let zonesByMovement = Dictionary(grouping: decisionZones, by: \.movementOccurrenceID)
    for movementOccurrenceID in movementOccurrenceIDs {
      let count = zonesByMovement[movementOccurrenceID]?.count ?? 0
      if count == 0 {
        issues.append(.missingDecisionZoneForMovement(movementOccurrenceID))
      } else if count > 1 {
        issues.append(.duplicateDecisionZoneForMovement(movementOccurrenceID))
      }
    }

    let guidedMovementOccurrenceIDs = Set(
      releasedGuidance.map(\.frameTemplate.movementOccurrenceID)
    )
    for movementOccurrenceID in movementOccurrenceIDs
    where !guidedMovementOccurrenceIDs.contains(movementOccurrenceID) {
      issues.append(.missingGuidanceForMovement(movementOccurrenceID))
    }

    var junctionViewsByID: [String: JunctionViewDefinition] = [:]
    for junctionView in junctionViews {
      if junctionViewsByID[junctionView.id] != nil {
        issues.append(.duplicateJunctionViewID(junctionView.id))
      } else {
        junctionViewsByID[junctionView.id] = junctionView
      }
      do {
        try JunctionViewValidator.validate(junctionView)
      } catch {
        issues.append(.invalidJunctionView(junctionView.id))
      }
      if junctionView.networkSnapshotID != networkSnapshot.id {
        issues.append(.junctionViewSnapshotMismatch(junctionView.id))
      }
      guard let occurrence = routePlan.occurrence(id: junctionView.movementOccurrenceID),
        occurrence.kind == .junctionMovement
      else {
        issues.append(.junctionViewOccurrenceMismatch(junctionView.id))
        continue
      }
    }

    var usedJunctionViewIDs: Set<String> = []
    for definition in releasedGuidance {
      guard let junctionView = definition.frameTemplate.presentationSource.junctionView else {
        continue
      }
      guard let registered = junctionViewsByID[junctionView.id] else {
        issues.append(.unregisteredJunctionView(junctionView.id))
        continue
      }
      if registered != junctionView {
        issues.append(.junctionViewDefinitionMismatch(junctionView.id))
      }
      usedJunctionViewIDs.insert(junctionView.id)
    }
    for junctionViewID in junctionViewsByID.keys
    where !usedJunctionViewIDs.contains(junctionViewID) {
      issues.append(.orphanedJunctionView(junctionViewID))
    }

    return sorted(issues)
  }

  private static func routePlanIsValid(_ routePlan: RoutePlan) -> Bool {
    guard !normalized(routePlan.id).isEmpty,
      !normalized(routePlan.networkSnapshotID).isEmpty,
      !normalized(routePlan.entryFacilityID).isEmpty,
      !normalized(routePlan.exitFacilityID).isEmpty,
      !routePlan.occurrences.isEmpty,
      routePlan.actualDistanceKM.map({ $0.isFinite && $0 > 0 }) != false
    else {
      return false
    }
    let occurrenceIDs = routePlan.occurrences.map(\.id)
    guard Set(occurrenceIDs).count == occurrenceIDs.count,
      routePlan.occurrences.map(\.index) == Array(0..<routePlan.occurrences.count)
    else {
      return false
    }
    return routePlan.occurrences.allSatisfy {
      !normalized($0.id).isEmpty && !normalized($0.entityID).isEmpty
    }
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isISO8601DateTime(_ value: String) -> Bool {
    let standard = ISO8601DateFormatter()
    if standard.date(from: value) != nil {
      return true
    }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) != nil
  }

  private static func sorted(
    _ issues: [NavigationReleaseBundleIssue]
  ) -> [NavigationReleaseBundleIssue] {
    issues.sorted { $0.sortKey < $1.sortKey }
  }
}

enum NavigationRuntimeConfigurationValidator {
  private struct GuidanceTargetKey: Hashable {
    let movementOccurrenceID: String
    let decisionZoneID: String
  }

  private struct AnchorKey: Hashable {
    let occurrenceID: String
    let anchorID: String
  }

  static func issues(
    routePlan: RoutePlan,
    matcherCorridor: RouteMatcherCorridor,
    decisionZones: [DecisionZoneProgressDefinition],
    releasedGuidance: [ReleasedGuidanceDefinition]
  ) -> [String] {
    var issues = matcherCorridor.validationIssues
    if routePlan.id != matcherCorridor.routePlanID {
      issues.append("matcher corridor RoutePlan ID does not match")
    }
    if routePlan.networkSnapshotID != matcherCorridor.networkSnapshotID {
      issues.append("matcher corridor network snapshot does not match")
    }

    let routeOccurrenceIDs = routePlan.occurrences.map(\.id)
    let routeOccurrenceIndexes = routePlan.occurrences.map(\.index)
    if Set(routeOccurrenceIDs).count != routeOccurrenceIDs.count
      || routeOccurrenceIndexes != Array(0..<routePlan.occurrences.count)
    {
      issues.append("RoutePlan occurrence sequence is invalid")
    }
    var corridorOccurrencesByIndex: [Int: RouteMatcherOccurrence] = [:]
    for occurrence in matcherCorridor.occurrences
    where corridorOccurrencesByIndex[occurrence.index] == nil {
      corridorOccurrencesByIndex[occurrence.index] = occurrence
    }
    if matcherCorridor.occurrences.count != routePlan.occurrences.count {
      issues.append("matcher corridor does not cover every RoutePlan occurrence")
    }
    for occurrence in routePlan.occurrences {
      guard let binding = corridorOccurrencesByIndex[occurrence.index],
        binding.id == occurrence.id
      else {
        issues.append("matcher corridor occurrence binding does not match RoutePlan")
        continue
      }
      if occurrence.kind == .edge, occurrence.entityID != binding.directedEdgeID {
        issues.append("matcher corridor edge binding does not match RoutePlan entity")
      }
    }

    var decisionZonesByID: [String: DecisionZoneProgressDefinition] = [:]
    var corridorOccurrencesByID: [String: RouteMatcherOccurrence] = [:]
    for occurrence in matcherCorridor.occurrences
    where corridorOccurrencesByID[occurrence.id] == nil {
      corridorOccurrencesByID[occurrence.id] = occurrence
    }
    var edgesByID: [String: RouteMatcherDirectedEdge] = [:]
    for edge in matcherCorridor.edges where edgesByID[edge.id] == nil {
      edgesByID[edge.id] = edge
    }
    for zone in decisionZones {
      if decisionZonesByID[zone.id] != nil {
        issues.append("DecisionZone progress IDs are not unique")
      } else {
        decisionZonesByID[zone.id] = zone
      }
      guard !zone.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        zone.routePlanID == routePlan.id,
        zone.networkSnapshotID == routePlan.networkSnapshotID,
        zone.entryOffsetMeters.isFinite,
        zone.entryOffsetMeters >= 0,
        let movement = routePlan.occurrence(id: zone.movementOccurrenceID),
        movement.kind == .junctionMovement,
        let binding = corridorOccurrencesByID[movement.id],
        let edge = edgesByID[binding.directedEdgeID],
        edge.lengthMeters.isFinite,
        edge.lengthMeters > 0,
        zone.entryOffsetMeters <= edge.lengthMeters
      else {
        issues.append("DecisionZone progress binding is invalid")
        continue
      }
    }

    var anchorKeys: Set<AnchorKey> = []
    var promptIDs: Set<String> = []
    var targetByAnchorOccurrence: [String: GuidanceTargetKey] = [:]
    var triggerDistancesByAnchorOccurrence: [String: Set<Double>] = [:]
    for definition in releasedGuidance {
      let anchor = definition.anchor
      let template = definition.frameTemplate
      let target = GuidanceTargetKey(
        movementOccurrenceID: template.movementOccurrenceID,
        decisionZoneID: template.decisionZoneID
      )
      let anchorKey = AnchorKey(
        occurrenceID: anchor.occurrenceID,
        anchorID: anchor.anchorID
      )
      guard !anchor.occurrenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        !anchor.anchorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        !anchor.promptID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        definition.triggerDistanceMeters.isFinite,
        definition.triggerDistanceMeters >= 0,
        let anchorOccurrence = routePlan.occurrence(id: anchor.occurrenceID),
        let movement = routePlan.occurrence(id: template.movementOccurrenceID),
        movement.kind == .junctionMovement,
        movement.index >= anchorOccurrence.index,
        let zone = decisionZonesByID[template.decisionZoneID],
        zone.movementOccurrenceID == movement.id
      else {
        issues.append("released guidance route or DecisionZone binding is invalid")
        continue
      }
      if !anchorKeys.insert(anchorKey).inserted {
        issues.append("released guidance anchor keys are not unique")
      }
      if !promptIDs.insert(anchor.promptID).inserted {
        issues.append("released guidance prompt IDs are not unique")
      }
      if !triggerDistancesByAnchorOccurrence[anchor.occurrenceID, default: []]
        .insert(definition.triggerDistanceMeters).inserted
      {
        issues.append("released guidance trigger distances are not unique")
      }
      if let existing = targetByAnchorOccurrence[anchor.occurrenceID],
        existing != target
      {
        issues.append("one anchor occurrence targets multiple DecisionZones")
      } else {
        targetByAnchorOccurrence[anchor.occurrenceID] = target
      }
      do {
        try GuidanceFrameValidator.validate(
          template.makeFrame(anchor: anchor, distanceMeters: 0)
        )
      } catch {
        issues.append("released guidance frame is invalid")
      }
    }
    return Array(Set(issues)).sorted()
  }
}
