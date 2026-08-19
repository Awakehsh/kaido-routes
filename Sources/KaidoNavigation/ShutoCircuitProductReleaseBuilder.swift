import CryptoKit
import Foundation
import KaidoDomain
import KaidoRouting

public enum ShutoCircuitProductReleaseBuilderError:
  Error, Equatable, Sendable
{
  case unsupportedCircuit
  case missingReviewedMovement(String)
  case invalidReviewedMovementOrder(String)
  case missingEntryPredecessor
  case missingRecoveryCandidate
  case incompleteJunctionGuidance([String])
  case missingGraphEdge(String)
  case missingGraphNode(Int64)
  case inconsistentRepeatedEntity(String)
}

public struct ShutoPlannedRouteProductBuild: Sendable {
  public let release: KaidoProductRelease
  public let runtimeAssets: ShutoPlannedRouteRuntimeAssets

  public init(
    release: KaidoProductRelease,
    runtimeAssets: ShutoPlannedRouteRuntimeAssets
  ) {
    self.release = release
    self.runtimeAssets = runtimeAssets
  }
}

/// Authors exact whole-Shuto foreground releases from the bundled, dated graph
/// and reviewed junction catalog.
public enum ShutoCircuitProductReleaseBuilder {
  public static let circuitID = "shuto.circuit.c1-inner"
  public static let entryFacilityID = "shuto.ic.c1.shibakouen"
  public static let exitFacilityID = "shuto.ic.c1.shiodome"
  public static let releaseDate = "2026-08-15"
  public static let releasedAt = "2026-08-15T00:00:00+09:00"
  public static let wanganCircuitID =
    "shuto.circuit.wangan-daikoku-run"
  public static let wanganEntryFacilityID =
    "shuto.ic.b.chidoricho"
  public static let wanganExitFacilityID =
    "shuto.ic.b.daikokufutou"
  public static let c2CircuitID =
    "shuto.circuit.c2-inner-bayshore"
  public static let c2EntryFacilityID =
    "shuto.ic.c2.oujiminami"
  public static let c2ExitFacilityID =
    "shuto.ic.s1.shikahamabashi"
  public static let daikokuCircuitID =
    "shuto.circuit.daikoku-yokohama-loop"
  public static let daikokuEntryFacilityID =
    "shuto.ic.b.wangankanpachi"
  public static let daikokuExitFacilityID =
    "shuto.ic.b.daikokufutou"
  public static let scenicCircuitID =
    "shuto.circuit.scenic-grand-tour"
  public static let scenicEntryFacilityID =
    "shuto.ic.10.harumi"
  public static let scenicExitFacilityID =
    "shuto.ic.b.daikokufutou"

  public static func plannedRoute(
    database: ShutoNetworkDatabase
  ) throws -> ShutoPlannedRoute {
    guard
      let circuit = ShutoCircuitDefinition.bundled.first(where: {
        $0.circuitID == circuitID
      })
    else {
      throw ShutoCircuitProductReleaseBuilderError.unsupportedCircuit
    }
    let planner = try ShutoRoutePlanner(database: database)
    return try planner.planCircuit(
      circuit: circuit,
      entryFacilityID: entryFacilityID,
      exitFacilityID: exitFacilityID,
      laps: 1
    )
  }

  public static func buildArtifact(
    database: ShutoNetworkDatabase
  ) throws -> KaidoProductReleaseArtifact {
    return try buildArtifact(
      database: database,
      route: plannedRoute(database: database),
      releaseKey: "c1-inner-shibakoen-shiodome",
      preferredRecoveryTriggerID: "osm.44804643.0.forward"
    )
  }

  public static func plannedWanganRoute(
    database: ShutoNetworkDatabase,
    entryFacilityID: String = wanganEntryFacilityID
  ) throws -> ShutoPlannedRoute {
    guard
      let circuit = ShutoCircuitDefinition.bundled.first(where: {
        $0.circuitID == wanganCircuitID
      })
    else {
      throw ShutoCircuitProductReleaseBuilderError.unsupportedCircuit
    }
    return try ShutoRoutePlanner(database: database).planCircuit(
      circuit: circuit,
      entryFacilityID: entryFacilityID,
      exitFacilityID: wanganExitFacilityID,
      laps: 1
    )
  }

  public static func buildWanganArtifact(
    database: ShutoNetworkDatabase,
    entryFacilityID: String = wanganEntryFacilityID
  ) throws -> KaidoProductReleaseArtifact {
    let entryKey =
      entryFacilityID.split(separator: ".").last
      .map(String.init) ?? entryFacilityID
    return try buildArtifact(
      database: database,
      route: plannedWanganRoute(
        database: database,
        entryFacilityID: entryFacilityID
      ),
      releaseKey: "wangan-westbound-\(entryKey)-daikokufutou",
      preferredRecoveryTriggerID: nil
    )
  }

  public static func plannedC2Route(
    database: ShutoNetworkDatabase
  ) throws -> ShutoPlannedRoute {
    guard
      let circuit = ShutoCircuitDefinition.bundled.first(where: {
        $0.circuitID == c2CircuitID
      })
    else {
      throw ShutoCircuitProductReleaseBuilderError.unsupportedCircuit
    }
    return try ShutoRoutePlanner(database: database).planCircuit(
      circuit: circuit,
      entryFacilityID: c2EntryFacilityID,
      exitFacilityID: c2ExitFacilityID,
      laps: 1
    )
  }

  public static func buildC2Artifact(
    database: ShutoNetworkDatabase
  ) throws -> KaidoProductReleaseArtifact {
    try buildArtifact(
      database: database,
      route: plannedC2Route(database: database),
      releaseKey: "c2-inner-oujiminami-shikahamabashi",
      preferredRecoveryTriggerID: nil
    )
  }

  public static func plannedDaikokuRoute(
    database: ShutoNetworkDatabase
  ) throws -> ShutoPlannedRoute {
    guard
      let circuit = ShutoCircuitDefinition.bundled.first(where: {
        $0.circuitID == daikokuCircuitID
      })
    else {
      throw ShutoCircuitProductReleaseBuilderError.unsupportedCircuit
    }
    return try ShutoRoutePlanner(database: database).planCircuit(
      circuit: circuit,
      entryFacilityID: daikokuEntryFacilityID,
      exitFacilityID: daikokuExitFacilityID,
      laps: 1
    )
  }

  public static func buildDaikokuArtifact(
    database: ShutoNetworkDatabase
  ) throws -> KaidoProductReleaseArtifact {
    try buildArtifact(
      database: database,
      route: plannedDaikokuRoute(database: database),
      releaseKey: "daikoku-yokohama-wangankanpachi-daikokufutou",
      preferredRecoveryTriggerID: nil
    )
  }

  public static func plannedScenicRoute(
    database: ShutoNetworkDatabase
  ) throws -> ShutoPlannedRoute {
    guard
      let circuit = ShutoCircuitDefinition.bundled.first(where: {
        $0.circuitID == scenicCircuitID
      })
    else {
      throw ShutoCircuitProductReleaseBuilderError.unsupportedCircuit
    }
    return try ShutoRoutePlanner(database: database).planCircuit(
      circuit: circuit,
      entryFacilityID: scenicEntryFacilityID,
      exitFacilityID: scenicExitFacilityID,
      laps: 1
    )
  }

  public static func buildScenicArtifact(
    database: ShutoNetworkDatabase
  ) throws -> KaidoProductReleaseArtifact {
    try buildArtifact(
      database: database,
      route: plannedScenicRoute(database: database),
      releaseKey: "scenic-harumi-daikokufutou",
      preferredRecoveryTriggerID: nil
    )
  }

  /// Builds one exact foreground release for an arbitrary planned route when
  /// every junction decision already has released, source-bound guidance.
  /// The release identity is content-addressed from the complete RoutePlan so
  /// UI labels, saved-route IDs, or caller-controlled strings cannot mint a
  /// different authority for the same ordered route.
  public static func buildPlannedRouteArtifact(
    database: ShutoNetworkDatabase,
    route: ShutoPlannedRoute
  ) throws -> KaidoProductReleaseArtifact {
    try buildPlannedRouteArtifact(
      context: ShutoPlannedRouteRuntimeCompiler.NetworkContext(
        database: database
      ),
      route: route
    )
  }

  public static func buildPlannedRouteArtifact(
    context: ShutoPlannedRouteRuntimeCompiler.NetworkContext,
    route: ShutoPlannedRoute
  ) throws -> KaidoProductReleaseArtifact {
    try buildArtifact(
      database: context.database,
      route: route,
      releaseKey: plannedRouteReleaseKey(route.routePlan),
      preferredRecoveryTriggerID: nil,
      runtimeContext: context
    )
  }

  /// Builds and validates the on-demand foreground release exactly once.
  /// Live admission callers use this path so authoring and authority creation
  /// cannot redundantly traverse the full navigation and atlas artifact.
  public static func buildPlannedRouteRelease(
    context: ShutoPlannedRouteRuntimeCompiler.NetworkContext,
    route: ShutoPlannedRoute
  ) throws -> KaidoProductRelease {
    try buildPlannedRouteProduct(
      context: context,
      route: route
    ).release
  }

  public static func buildPlannedRouteProduct(
    context: ShutoPlannedRouteRuntimeCompiler.NetworkContext,
    route: ShutoPlannedRoute
  ) throws -> ShutoPlannedRouteProductBuild {
    let runtimeAssets = try context.compile(route: route)
    let artifact = try buildArtifact(
      database: context.database,
      route: route,
      releaseKey: plannedRouteReleaseKey(route.routePlan),
      preferredRecoveryTriggerID: nil,
      runtimeContext: context,
      runtimeAssets: runtimeAssets,
      validatesProduct: false
    )
    return try ShutoPlannedRouteProductBuild(
      release: KaidoProductRelease(artifact: artifact),
      runtimeAssets: runtimeAssets
    )
  }

  private static func plannedRouteReleaseKey(
    _ routePlan: RoutePlan
  ) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let encodedRoutePlan = try encoder.encode(routePlan)
    let routeDigest = SHA256.hash(data: encodedRoutePlan).map {
      String(format: "%02x", $0)
    }.joined()
    return "route-\(routeDigest)"
  }

  private static func buildArtifact(
    database: ShutoNetworkDatabase,
    route: ShutoPlannedRoute,
    releaseKey: String,
    preferredRecoveryTriggerID: String?,
    runtimeContext: ShutoPlannedRouteRuntimeCompiler.NetworkContext? = nil,
    runtimeAssets: ShutoPlannedRouteRuntimeAssets? = nil,
    validatesProduct: Bool = true
  ) throws -> KaidoProductReleaseArtifact {
    let assets =
      try runtimeAssets
      ?? runtimeContext?.compile(route: route)
      ?? ShutoPlannedRouteRuntimeCompiler.compile(
        database: database,
        route: route
      )
    let missingGuidance = assets.liveReleaseCoverage.decisions.compactMap {
      decision -> String? in
      guard decision.kind == .junction,
        decision.releasedGuidanceDefinitionID == nil
      else { return nil }
      return "\(decision.incomingDirectedEdgeID)->"
        + decision.plannedOutgoingDirectedEdgeID
    }
    guard missingGuidance.isEmpty else {
      throw
        ShutoCircuitProductReleaseBuilderError
        .incompleteJunctionGuidance(missingGuidance.sorted())
    }
    let reviewedMovements = try reviewedMovements(
      routePlan: route.routePlan
    )
    let editor = try editorCatalog(
      database: database,
      route: route,
      reviewedMovements: reviewedMovements,
      releaseKey: releaseKey
    )
    let releaseRecovery = releasedRecovery(
      assets: assets,
      availableDirectedEdgeIDs:
        runtimeContext?.directedEdgeIDs
        ?? Set(database.edges.map(\.edgeID)),
      preferredTriggerID: preferredRecoveryTriggerID
    )
    let entryApproach = try entryApproach(
      route: route,
      database: database
    )
    let corridor = try releaseCorridor(
      assets: assets,
      database: database,
      runtimeContext: runtimeContext,
      entryApproach: entryApproach,
      recovery: releaseRecovery
    )
    let egressOptionID =
      releaseKey == "c1-inner-shibakoen-shiodome"
      ? "shutoko.egress.c1-shiodome-handoff.2026-08-15"
      : "shutoko.egress.\(releaseKey)-handoff.2026-08-15"
    let runtimePolicy = ReleasedNavigationRuntimePolicy(
      id: "shutoko.runtime.\(releaseKey).2026-08-15",
      networkSnapshotID: database.networkSnapshotID,
      routePlanID: route.routePlan.id,
      entryTransition: EntryTransition(
        facilityID: route.entryFacility.facilityID,
        directedEdgeIDs: entryApproach.transitionEdgeIDs,
        firstRouteOccurrenceID: route.routePlan.occurrences[0].id
      ),
      recoveryCandidates: releaseRecovery.map { [$0] } ?? [],
      egressOptions: [
        EgressOption(
          id: egressOptionID,
          firstEligibleOccurrenceID: route.routePlan.occurrences.last!.id,
          exitFacilityID: route.exitFacility.facilityID,
          egressOccurrenceIDs: [route.edges.last!.edgeID],
          isReleased: true
        )
      ]
    )
    let networkSnapshot = NetworkSnapshot(
      id: database.networkSnapshotID,
      status: .active,
      effectiveAt: database.sources.osm.sourceSnapshotAt
    )
    let navigationSources = navigationSourceRegistry(
      database: database,
      movements: reviewedMovements
    )
    let navigationArtifact = NavigationReleaseArtifact(
      releaseID: "shutoko.navigation.\(releaseKey).2026-08-15",
      releasedAt: releasedAt,
      editorCatalogID: editor.catalogID,
      networkSnapshot: networkSnapshot,
      routePlan: route.routePlan,
      sourceRegistry: navigationSources,
      assetEvidence: navigationEvidence(
        editorCatalogID: editor.catalogID,
        presentationCatalogID: editor.presentation.id,
        runtimePolicy: runtimePolicy,
        corridor: corridor,
        decisionZones: assets.decisionZones,
        guidance: assets.releasedGuidance,
        movements: reviewedMovements
      ),
      editorCatalog: editor.catalog,
      editorPresentationCatalog: editor.presentation,
      runtimePolicy: runtimePolicy,
      matcherCorridor: corridor,
      decisionZones: assets.decisionZones,
      releasedGuidance: assets.releasedGuidance
    )
    let atlasArtifact = try routeAtlasArtifact(
      database: database,
      route: route,
      networkSnapshot: networkSnapshot,
      releaseKey: releaseKey
    )
    let product = KaidoProductReleaseArtifact(
      releaseID: "shutoko.product.\(releaseKey).2026-08-15",
      releasedAt: releasedAt,
      runtimeUse: KaidoProductRuntimeUseDeclaration(
        evidenceScope: .releasedRoad,
        liveInputPolicy: .foregroundWhenInUse
      ),
      navigationRelease: navigationArtifact,
      routeAtlasRelease: atlasArtifact
    )
    if validatesProduct {
      _ = try KaidoProductRelease(artifact: product)
    }
    return product
  }

  private struct ReviewedMovement {
    let occurrence: RouteOccurrence
    let occurrenceIndex: Int
    let incomingOccurrence: RouteOccurrence
    let outgoingOccurrence: RouteOccurrence
    let definition: ShutoJunctionMovementDefinition

    var sourceID: String {
      "shutoko-guidance-\(definition.id)"
    }
  }

  private struct EditorAssets {
    let catalogID: String
    let catalog: ReviewedRouteEditorCatalog
    let presentation: ReviewedRouteEditorPresentationCatalog
  }

  private static func reviewedMovements(
    routePlan: RoutePlan
  ) throws -> [ReviewedMovement] {
    try routePlan.occurrences.enumerated().compactMap { index, occurrence in
      guard occurrence.kind == .junctionMovement else { return nil }
      guard index > 0, index + 1 < routePlan.occurrences.count else {
        throw
          ShutoCircuitProductReleaseBuilderError
          .invalidReviewedMovementOrder(occurrence.id)
      }
      guard
        let definition = ShutoJunctionMovementCatalog.released.first(where: {
          $0.id == occurrence.entityID
        })
      else {
        throw
          ShutoCircuitProductReleaseBuilderError
          .missingReviewedMovement(occurrence.entityID)
      }
      return ReviewedMovement(
        occurrence: occurrence,
        occurrenceIndex: index,
        incomingOccurrence: routePlan.occurrences[index - 1],
        outgoingOccurrence: routePlan.occurrences[index + 1],
        definition: definition
      )
    }
  }

  private static func editorCatalog(
    database: ShutoNetworkDatabase,
    route: ShutoPlannedRoute,
    reviewedMovements: [ReviewedMovement],
    releaseKey: String
  ) throws -> EditorAssets {
    func decisionID(_ movement: ReviewedMovement) -> String {
      "\(route.routePlan.id).editor.\(movement.occurrence.id)"
    }
    func localized(
      _ values: [KaidoReleaseLocale: String]
    ) -> RouteEditorLocalizedText {
      RouteEditorLocalizedText(values: values)
    }
    let entrance: ReviewedRouteEditorEntrance
    if let first = reviewedMovements.first {
      entrance = ReviewedRouteEditorEntrance(
        facilityID: route.entryFacility.facilityID,
        initialEdgeID: route.routePlan.occurrences[0].entityID,
        initialEdgeTollDomainID:
          route.routePlan.occurrences[0].tollDomainID!,
        firstDecisionPointID: decisionID(first)
      )
    } else {
      entrance = ReviewedRouteEditorEntrance(
        facilityID: route.entryFacility.facilityID,
        initialEdgeID: route.routePlan.occurrences[0].entityID,
        initialEdgeTollDomainID:
          route.routePlan.occurrences[0].tollDomainID!,
        directExitFacilityID: route.exitFacility.facilityID,
        directRouteOccurrences: route.routePlan.occurrences
      )
    }
    let catalog = ReviewedRouteEditorCatalog(
      networkSnapshotID: database.networkSnapshotID,
      entrances: [entrance],
      decisionPoints: reviewedMovements.enumerated().map { offset, movement in
        ReviewedRouteEditorDecisionPoint(
          id: decisionID(movement),
          incomingApproachID: movement.incomingOccurrence.entityID,
          junctionComplexID: movement.definition.junctionID,
          choices: [
            ReviewedRouteEditorChoice(
              id: "\(decisionID(movement)).selected",
              movementID: movement.occurrence.entityID,
              movementTollDomainID: movement.occurrence.tollDomainID!,
              outgoingEdgeID: movement.outgoingOccurrence.entityID,
              outgoingEdgeTollDomainID:
                movement.outgoingOccurrence.tollDomainID!,
              destination:
                offset + 1 < reviewedMovements.count
                ? .decisionPoint(decisionID(reviewedMovements[offset + 1]))
                : .exitFacility(route.exitFacility.facilityID)
            )
          ]
        )
      }
    )
    let presentationID = "\(route.routePlan.id).editor-presentation.2026-08-15"
    let entranceTitle: [KaidoReleaseLocale: String]
    switch releaseKey {
    case "c1-inner-shibakoen-shiodome":
      entranceTitle = [
        .japanese: "\(route.entryFacility.nameJA)入口",
        .simplifiedChinese: "芝公园入口",
        .english: "Shibakoen entrance",
      ]
    case let key where key.hasPrefix("wangan-westbound-"):
      entranceTitle = [
        .japanese: "\(route.entryFacility.nameJA)入口",
        .simplifiedChinese: "\(route.entryFacility.nameJA)入口",
        .english: "\(route.entryFacility.nameJA) entrance",
      ]
    case "c2-inner-oujiminami-shikahamabashi":
      entranceTitle = [
        .japanese: "\(route.entryFacility.nameJA)入口",
        .simplifiedChinese: "王子南入口",
        .english: "Oji-minami entrance",
      ]
    case "daikoku-yokohama-wangankanpachi-daikokufutou":
      entranceTitle = [
        .japanese: "\(route.entryFacility.nameJA)入口",
        .simplifiedChinese: "湾岸环八入口",
        .english: "Wangan-Kanpachi entrance",
      ]
    case "scenic-harumi-daikokufutou":
      entranceTitle = [
        .japanese: "\(route.entryFacility.nameJA)入口",
        .simplifiedChinese: "晴海入口",
        .english: "Harumi entrance",
      ]
    default:
      entranceTitle = [
        .japanese: "\(route.entryFacility.nameJA)入口",
        .simplifiedChinese: "\(route.entryFacility.nameJA)入口",
        .english: "\(route.entryFacility.nameJA) entrance",
      ]
    }
    let presentation = ReviewedRouteEditorPresentationCatalog(
      id: presentationID,
      networkSnapshotID: database.networkSnapshotID,
      entrances: [
        ReviewedRouteEditorEntrancePresentation(
          facilityID: route.entryFacility.facilityID,
          title: localized(entranceTitle)
        )
      ],
      decisionPoints: reviewedMovements.map { movement in
        ReviewedRouteEditorDecisionPresentation(
          decisionPointID: decisionID(movement),
          title: localized(movement.definition.localizedJunctionNames)
        )
      },
      choices: reviewedMovements.map { movement in
        ReviewedRouteEditorChoicePresentation(
          choiceID: "\(decisionID(movement)).selected",
          title: localized(
            movement.definition.localizedContent.mapValues(\.displayText)
          ),
          detail: localized(
            Dictionary(
              uniqueKeysWithValues: KaidoReleaseLocale.allCases.map {
                ($0, movement.definition.japaneseSignText)
              }
            )
          )
        )
      }
    )
    return EditorAssets(
      catalogID: "\(route.routePlan.id).editor-catalog.2026-08-15",
      catalog: catalog,
      presentation: presentation
    )
  }

  private struct ReleasedEntryApproach {
    let transitionEdgeIDs: [String]
    let virtualMatcherEdge: RouteMatcherDirectedEdge?
  }

  private static func entryApproach(
    route: ShutoPlannedRoute,
    database: ShutoNetworkDatabase
  ) throws -> ReleasedEntryApproach {
    let first = route.edges[0]
    let routeEdgeIDs = Set(route.edges.map(\.edgeID))
    let predecessors = database.edges
      .filter {
        $0.toNodeID == first.fromNodeID
          && !routeEdgeIDs.contains($0.edgeID)
      }
      .sorted { lhs, rhs in
        let lhsRank = lhs.kind == "LINK" ? 0 : 1
        let rhsRank = rhs.kind == "LINK" ? 0 : 1
        return lhsRank == rhsRank
          ? lhs.edgeID < rhs.edgeID : lhsRank < rhsRank
      }
    if let predecessor = predecessors.first {
      return ReleasedEntryApproach(
        transitionEdgeIDs: [predecessor.edgeID, first.edgeID],
        virtualMatcherEdge: nil
      )
    }
    guard
      let firstNode = database.nodes.first(where: {
        $0.nodeID == first.fromNodeID
      })
    else {
      throw ShutoCircuitProductReleaseBuilderError.missingEntryPredecessor
    }
    let facilityCoordinate = route.entryFacility.coordinate
    let nodeCoordinate = firstNode.coordinate
    let distance = distanceMeters(facilityCoordinate, nodeCoordinate)
    let matchedRampDistance = route.entryFacility.entryEdgeCandidates.first {
      $0.edgeID == first.edgeID
    }?.distanceMeters
    let isBoundedMatchedRamp =
      first.kind == "LINK"
      && matchedRampDistance.map {
        $0.isFinite && $0 <= 250 && distance <= $0 + 25
      } == true
    if distance > 1, distance <= 75 || isBoundedMatchedRamp {
      let virtualID =
        "shutoko.entry.\(route.entryFacility.facilityID).approach.2026-08-15"
      return ReleasedEntryApproach(
        transitionEdgeIDs: [virtualID, first.edgeID],
        virtualMatcherEdge: RouteMatcherDirectedEdge(
          id: virtualID,
          coordinates: [
            MatcherCoordinate(
              latitude: facilityCoordinate.latitude,
              longitude: facilityCoordinate.longitude
            ),
            MatcherCoordinate(
              latitude: nodeCoordinate.latitude,
              longitude: nodeCoordinate.longitude
            ),
          ],
          successorEdgeIDs: [first.edgeID]
        )
      )
    }

    // Some official facility coordinates identify the interchange rather
    // than the start of the retained OSM ramp. A long straight virtual edge
    // would create matcher authority across unrelated surface roads. When no
    // graph predecessor exists, prove entry with the first two exact ordered
    // RoutePlan edges instead; strict-route authority still targets the first
    // occurrence and opens only after both directed matches are observed.
    guard route.edges.count >= 2 else {
      throw ShutoCircuitProductReleaseBuilderError.missingEntryPredecessor
    }
    return ReleasedEntryApproach(
      transitionEdgeIDs: [first.edgeID, route.edges[1].edgeID],
      virtualMatcherEdge: nil
    )
  }

  private static func releasedRecovery(
    assets: ShutoPlannedRouteRuntimeAssets,
    availableDirectedEdgeIDs: Set<String>,
    preferredTriggerID: String?
  ) -> RecoveryCandidate? {
    let available = assets.recoveryCandidates
      .filter { candidate in
        candidate.recoveryOccurrenceIDs.allSatisfy(
          availableDirectedEdgeIDs.contains
        )
      }
      .sorted {
        if $0.divergenceOccurrenceID != $1.divergenceOccurrenceID {
          return $0.divergenceOccurrenceID < $1.divergenceOccurrenceID
        }
        return $0.triggerDirectedEdgeID < $1.triggerDirectedEdgeID
      }
    let selected =
      preferredTriggerID.flatMap { expected in
        available.first { $0.triggerDirectedEdgeID == expected }
      } ?? (preferredTriggerID == nil ? available.first : nil)
    guard let candidate = selected else { return nil }
    return RecoveryCandidate(
      divergenceOccurrenceID: candidate.divergenceOccurrenceID,
      triggerDirectedEdgeID: candidate.triggerDirectedEdgeID,
      targetOccurrenceID: candidate.targetOccurrenceID,
      recoveryOccurrenceIDs: candidate.recoveryOccurrenceIDs,
      isReleased: true,
      staysInAllowedTollDomain: true
    )
  }

  private static func releaseCorridor(
    assets: ShutoPlannedRouteRuntimeAssets,
    database: ShutoNetworkDatabase,
    runtimeContext: ShutoPlannedRouteRuntimeCompiler.NetworkContext?,
    entryApproach: ReleasedEntryApproach,
    recovery: RecoveryCandidate?
  ) throws -> RouteMatcherCorridor {
    var requiredIDs =
      Set(assets.matcherCorridor.edges.map(\.id))
      .union(recovery?.recoveryOccurrenceIDs ?? [])
    if entryApproach.virtualMatcherEdge == nil {
      requiredIDs.formUnion(entryApproach.transitionEdgeIDs)
    }
    let edgesByID =
      runtimeContext?.edgesByID
      ?? Dictionary(
        uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
      )
    let nodesByID =
      runtimeContext?.nodesByID
      ?? Dictionary(
        uniqueKeysWithValues: database.nodes.map { ($0.nodeID, $0) }
      )
    let outgoing =
      runtimeContext?.outgoingEdges
      ?? Dictionary(grouping: database.edges, by: \.fromNodeID)
    var edges = try requiredIDs.sorted().map { id -> RouteMatcherDirectedEdge in
      guard let edge = edgesByID[id] else {
        throw ShutoCircuitProductReleaseBuilderError.missingGraphEdge(id)
      }
      guard let from = nodesByID[edge.fromNodeID] else {
        throw
          ShutoCircuitProductReleaseBuilderError
          .missingGraphNode(edge.fromNodeID)
      }
      guard let to = nodesByID[edge.toNodeID] else {
        throw
          ShutoCircuitProductReleaseBuilderError
          .missingGraphNode(edge.toNodeID)
      }
      return RouteMatcherDirectedEdge(
        id: id,
        coordinates: [
          MatcherCoordinate(
            latitude: from.latitude,
            longitude: from.longitude
          ),
          MatcherCoordinate(
            latitude: to.latitude,
            longitude: to.longitude
          ),
        ],
        successorEdgeIDs: Set(
          (outgoing[edge.toNodeID] ?? []).map(\.edgeID)
            .filter(requiredIDs.contains)
        )
      )
    }
    if let virtualEdge = entryApproach.virtualMatcherEdge {
      edges.append(virtualEdge)
      edges.sort { $0.id < $1.id }
    }
    return RouteMatcherCorridor(
      id: "\(assets.matcherCorridor.id).release.2026-08-15",
      networkSnapshotID: assets.matcherCorridor.networkSnapshotID,
      routePlanID: assets.matcherCorridor.routePlanID,
      edges: edges,
      occurrences: assets.matcherCorridor.occurrences
    )
  }

  private static func distanceMeters(
    _ first: ShutoCoordinate,
    _ second: ShutoCoordinate
  ) -> Double {
    let latitude1 = first.latitude * .pi / 180
    let longitude1 = first.longitude * .pi / 180
    let latitude2 = second.latitude * .pi / 180
    let longitude2 = second.longitude * .pi / 180
    let latitudeDelta = latitude2 - latitude1
    let longitudeDelta = longitude2 - longitude1
    let value =
      pow(sin(latitudeDelta / 2), 2)
      + cos(latitude1) * cos(latitude2)
      * pow(sin(longitudeDelta / 2), 2)
    return 2 * 6_371_000 * asin(min(1, sqrt(value)))
  }

  private static func navigationSourceRegistry(
    database: ShutoNetworkDatabase,
    movements: [ReviewedMovement]
  ) -> NavigationReleaseSourceRegistry {
    let osm = database.sources.osm
    let osmDate = String(osm.sourceSnapshotAt.prefix(10))
    let base: [NavigationReleaseSourceReference] = [
      NavigationReleaseSourceReference(
        id: "osm-kanto-2026-08-04",
        roles: [.editorCatalog, .runtimePolicy, .matcherCorridor],
        authorityName: "OpenStreetMap contributors via Geofabrik",
        sourceURL: osm.sourceURI,
        contentSHA256: osm.inputSHA256,
        checkedAt: osmDate,
        licenceIdentifier: osm.licence
      ),
      NavigationReleaseSourceReference(
        id: "shutoko-official-catalog-2026-07-29",
        roles: [.editorCatalog, .editorPresentation, .runtimePolicy],
        authorityName: "Kaido Routes reviewed Shutoko catalog",
        sourceURL:
          "https://raw.githubusercontent.com/Awakehsh/kaido-routes/main/"
          + "data/network/shuto-official-catalog-20260729.json",
        contentSHA256: database.sources.officialCatalog.sha256,
        checkedAt: database.checkedAt,
        licenceIdentifier: "Apache-2.0"
      ),
    ]
    var seenGuidanceSourceIDs = Set<String>()
    let guidance = movements.compactMap {
      movement -> NavigationReleaseSourceReference? in
      guard seenGuidanceSourceIDs.insert(movement.sourceID).inserted else {
        return nil
      }
      let source = movement.definition.sources.first(where: {
        $0.contentSHA256 != nil
      })!
      return NavigationReleaseSourceReference(
        id: movement.sourceID,
        roles: [
          .editorCatalog,
          .editorPresentation,
          .decisionZone,
          .guidance,
        ],
        authorityName: "Metropolitan Expressway Company Limited",
        sourceURL: source.url,
        contentSHA256: source.contentSHA256!,
        checkedAt: movement.definition.checkedAt,
        licenceIdentifier: "OFFICIAL_REFERENCE"
      )
    }
    return NavigationReleaseSourceRegistry(references: base + guidance)
  }

  private static func navigationEvidence(
    editorCatalogID: String,
    presentationCatalogID: String,
    runtimePolicy: ReleasedNavigationRuntimePolicy,
    corridor: RouteMatcherCorridor,
    decisionZones: [DecisionZoneProgressDefinition],
    guidance: [ReleasedGuidanceDefinition],
    movements: [ReviewedMovement]
  ) -> [NavigationReleaseAssetEvidence] {
    let officialCatalogID = "shutoko-official-catalog-2026-07-29"
    let osmID = "osm-kanto-2026-08-04"
    let guidanceSourceIDs = Array(Set(movements.map(\.sourceID))).sorted()
    func evidence(
      _ role: NavigationReleaseAssetRole,
      _ id: String,
      _ sources: [String]
    ) -> NavigationReleaseAssetEvidence {
      NavigationReleaseAssetEvidence(
        role: role,
        assetID: id,
        state: .released,
        checkedAt: releaseDate,
        sourceReferenceIDs: sources
      )
    }
    var result = [
      evidence(
        .editorCatalog,
        editorCatalogID,
        [osmID, officialCatalogID] + guidanceSourceIDs
      ),
      evidence(
        .editorPresentation,
        presentationCatalogID,
        [officialCatalogID] + guidanceSourceIDs
      ),
      evidence(
        .runtimePolicy,
        runtimePolicy.id,
        [osmID, officialCatalogID]
      ),
      evidence(.matcherCorridor, corridor.id, [osmID]),
    ]
    let movementByOccurrenceID = Dictionary(
      uniqueKeysWithValues: movements.map { ($0.occurrence.id, $0) }
    )
    for zone in decisionZones {
      if let movement = movementByOccurrenceID[zone.movementOccurrenceID] {
        result.append(evidence(.decisionZone, zone.id, [movement.sourceID]))
      }
    }
    for definition in guidance {
      if let movement = movementByOccurrenceID[
        definition.frameTemplate.movementOccurrenceID
      ] {
        result.append(
          evidence(.guidance, definition.anchor.promptID, [movement.sourceID])
        )
      }
    }
    return result
  }

  private static func routeAtlasArtifact(
    database: ShutoNetworkDatabase,
    route: ShutoPlannedRoute,
    networkSnapshot: NetworkSnapshot,
    releaseKey: String
  ) throws -> RouteAtlasReleaseArtifact {
    let atlasElementPrefix =
      releaseKey == "c1-inner-shibakoen-shiodome"
      ? "c1" : releaseKey
    struct EntityBinding {
      let entityID: String
      let edge: ShutoNetworkDatabase.Edge
    }
    var orderedBindings: [EntityBinding] = []
    var bindingByEntity: [String: ShutoNetworkDatabase.Edge] = [:]
    for (occurrence, edge) in zip(route.routePlan.occurrences, route.edges) {
      if let existing = bindingByEntity[occurrence.entityID] {
        guard existing.fromNodeID == edge.fromNodeID,
          existing.toNodeID == edge.toNodeID
        else {
          throw
            ShutoCircuitProductReleaseBuilderError
            .inconsistentRepeatedEntity(occurrence.entityID)
        }
      } else {
        bindingByEntity[occurrence.entityID] = edge
        orderedBindings.append(
          EntityBinding(entityID: occurrence.entityID, edge: edge)
        )
      }
    }
    let topologyEdgeIDByEntity = Dictionary(
      uniqueKeysWithValues: orderedBindings.enumerated().map { index, binding in
        (binding.entityID, "\(atlasElementPrefix).topology.edge.\(index)")
      }
    )
    var successorEntities: [String: Set<String>] = [:]
    for pair in zip(
      route.routePlan.occurrences,
      route.routePlan.occurrences.dropFirst()
    ) {
      successorEntities[pair.0.entityID, default: []].insert(pair.1.entityID)
    }
    let topologyEdges = orderedBindings.map { binding in
      RouteAtlasTopologyEdge(
        id: topologyEdgeIDByEntity[binding.entityID]!,
        routeEntityID: binding.entityID,
        fromNodeID: "osm.node.\(binding.edge.fromNodeID)",
        toNodeID: "osm.node.\(binding.edge.toNodeID)",
        successorEdgeIDs: Set(
          successorEntities[binding.entityID, default: []].compactMap {
            topologyEdgeIDByEntity[$0]
          }
        )
      )
    }
    let nodeIDs = Set(
      orderedBindings.flatMap {
        [$0.edge.fromNodeID, $0.edge.toNodeID]
      }
    )
    let nodesByID = Dictionary(
      uniqueKeysWithValues: database.nodes.map { ($0.nodeID, $0) }
    )
    let topologyNodes = nodeIDs.sorted().map {
      RouteAtlasTopologyNode(id: "osm.node.\($0)")
    }
    let sourceID = "osm-kanto-2026-08-04"
    let evidence = RouteAtlasEvidence(
      state: .released,
      checkedAt: releaseDate,
      sourceReferenceIDs: [sourceID]
    )
    let topologyID =
      "shutoko.atlas.\(releaseKey).topology.2026-08-15"
    let topology = RouteAtlasTopologySlice(
      id: topologyID,
      networkSnapshotID: database.networkSnapshotID,
      nodes: topologyNodes,
      edges: topologyEdges,
      evidence: evidence
    )
    func point(_ nodeID: Int64) throws -> RouteAtlasPoint {
      guard let node = nodesByID[nodeID] else {
        throw ShutoCircuitProductReleaseBuilderError.missingGraphNode(nodeID)
      }
      let width =
        database.bounds.maximumLongitude
        - database.bounds.minimumLongitude
      let height =
        database.bounds.maximumLatitude
        - database.bounds.minimumLatitude
      return RouteAtlasPoint(
        x: (node.longitude - database.bounds.minimumLongitude) / width,
        y: (database.bounds.maximumLatitude - node.latitude) / height
      )
    }
    let layoutNodes = try nodeIDs.sorted().map { nodeID in
      RouteAtlasLayoutNode(
        topologyNodeID: "osm.node.\(nodeID)",
        point: try point(nodeID)
      )
    }
    let segmentIDByEntity = Dictionary(
      uniqueKeysWithValues: orderedBindings.enumerated().map { index, binding in
        (binding.entityID, "\(atlasElementPrefix).atlas.segment.\(index)")
      }
    )
    let segments = try orderedBindings.map { binding in
      RouteAtlasSegment(
        id: segmentIDByEntity[binding.entityID]!,
        topologyEdgeID: topologyEdgeIDByEntity[binding.entityID]!,
        fromNodeID: "osm.node.\(binding.edge.fromNodeID)",
        toNodeID: "osm.node.\(binding.edge.toNodeID)",
        successorSegmentIDs: Set(
          successorEntities[binding.entityID, default: []].compactMap {
            segmentIDByEntity[$0]
          }
        ),
        points: [
          try point(binding.edge.fromNodeID),
          try point(binding.edge.toNodeID),
        ]
      )
    }
    let definition = RouteAtlasDefinition(
      id: "shutoko.atlas.\(releaseKey).2026-08-15",
      networkSnapshotID: database.networkSnapshotID,
      routePlanID: route.routePlan.id,
      topologySliceID: topologyID,
      nodes: layoutNodes,
      segments: segments,
      occurrenceBindings: route.routePlan.occurrences.map { occurrence in
        RouteAtlasOccurrenceBinding(
          occurrenceID: occurrence.id,
          occurrenceIndex: occurrence.index,
          segmentID: segmentIDByEntity[occurrence.entityID]!
        )
      },
      evidence: evidence
    )
    let osm = database.sources.osm
    return RouteAtlasReleaseArtifact(
      networkSnapshot: networkSnapshot,
      routePlan: route.routePlan,
      sourceRegistry: RouteAtlasSourceRegistry(references: [
        RouteAtlasSourceReference(
          id: sourceID,
          roles: [.topologyEvidence, .layoutEvidence],
          authorityName: "OpenStreetMap contributors via Geofabrik",
          sourceURL: osm.sourceURI,
          contentSHA256: osm.inputSHA256,
          checkedAt: String(osm.sourceSnapshotAt.prefix(10)),
          licenceIdentifier: osm.licence
        )
      ]),
      topologySlice: topology,
      definition: definition
    )
  }
}
