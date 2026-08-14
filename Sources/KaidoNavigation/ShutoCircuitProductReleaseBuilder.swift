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
  case missingGraphEdge(String)
  case missingGraphNode(Int64)
  case inconsistentRepeatedEntity(String)
}

/// Authors the first exact whole-Shuto foreground release from the bundled,
/// dated graph and reviewed junction catalog. The scope is deliberately one
/// C1 inner circuit; it does not promote other planner routes.
public enum ShutoCircuitProductReleaseBuilder {
  public static let circuitID = "shuto.circuit.c1-inner"
  public static let entryFacilityID = "shuto.ic.c1.shibakouen"
  public static let exitFacilityID = "shuto.ic.c1.shiodome"
  public static let releaseDate = "2026-08-15"
  public static let releasedAt = "2026-08-15T00:00:00+09:00"

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
    let route = try plannedRoute(database: database)
    let assets = try ShutoPlannedRouteRuntimeCompiler.compile(
      database: database,
      route: route
    )
    let reviewedMovements = try reviewedMovements(
      routePlan: route.routePlan
    )
    let editor = try editorCatalog(
      database: database,
      route: route,
      reviewedMovements: reviewedMovements
    )
    let releaseRecovery = try releasedRecovery(
      assets: assets,
      database: database
    )
    let entryPredecessor = try entryPredecessor(
      route: route,
      database: database
    )
    let corridor = try releaseCorridor(
      assets: assets,
      database: database,
      entryPredecessorID: entryPredecessor.edgeID,
      recovery: releaseRecovery
    )
    let runtimePolicy = ReleasedNavigationRuntimePolicy(
      id: "shutoko.runtime.c1-inner-shibakoen-shiodome.2026-08-15",
      networkSnapshotID: database.networkSnapshotID,
      routePlanID: route.routePlan.id,
      entryTransition: EntryTransition(
        facilityID: route.entryFacility.facilityID,
        directedEdgeIDs: [
          entryPredecessor.edgeID,
          route.edges[0].edgeID,
        ],
        firstRouteOccurrenceID: route.routePlan.occurrences[0].id
      ),
      recoveryCandidates: [releaseRecovery],
      egressOptions: [
        EgressOption(
          id: "shutoko.egress.c1-shiodome-handoff.2026-08-15",
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
      releaseID: "shutoko.navigation.c1-inner-shibakoen-shiodome.2026-08-15",
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
      networkSnapshot: networkSnapshot
    )
    let product = KaidoProductReleaseArtifact(
      releaseID: "shutoko.product.c1-inner-shibakoen-shiodome.2026-08-15",
      releasedAt: releasedAt,
      runtimeUse: KaidoProductRuntimeUseDeclaration(
        evidenceScope: .releasedRoad,
        liveInputPolicy: .foregroundWhenInUse
      ),
      navigationRelease: navigationArtifact,
      routeAtlasRelease: atlasArtifact
    )
    _ = try KaidoProductRelease(artifact: product)
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
        throw ShutoCircuitProductReleaseBuilderError
          .invalidReviewedMovementOrder(occurrence.id)
      }
      guard
        let definition = ShutoJunctionMovementCatalog.released.first(where: {
          $0.id == occurrence.entityID
        })
      else {
        throw ShutoCircuitProductReleaseBuilderError
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
    reviewedMovements: [ReviewedMovement]
  ) throws -> EditorAssets {
    guard let first = reviewedMovements.first else {
      throw ShutoCircuitProductReleaseBuilderError.unsupportedCircuit
    }
    func decisionID(_ movement: ReviewedMovement) -> String {
      "\(route.routePlan.id).editor.\(movement.occurrence.id)"
    }
    func localized(
      _ values: [KaidoReleaseLocale: String]
    ) -> RouteEditorLocalizedText {
      RouteEditorLocalizedText(values: values)
    }
    let catalog = ReviewedRouteEditorCatalog(
      networkSnapshotID: database.networkSnapshotID,
      entrances: [
        ReviewedRouteEditorEntrance(
          facilityID: route.entryFacility.facilityID,
          initialEdgeID: route.routePlan.occurrences[0].entityID,
          initialEdgeTollDomainID:
            route.routePlan.occurrences[0].tollDomainID!,
          firstDecisionPointID: decisionID(first)
        )
      ],
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
    let presentation = ReviewedRouteEditorPresentationCatalog(
      id: presentationID,
      networkSnapshotID: database.networkSnapshotID,
      entrances: [
        ReviewedRouteEditorEntrancePresentation(
          facilityID: route.entryFacility.facilityID,
          title: localized([
            .japanese: "\(route.entryFacility.nameJA)入口",
            .simplifiedChinese: "芝公园入口",
            .english: "Shibakoen entrance",
          ])
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

  private static func entryPredecessor(
    route: ShutoPlannedRoute,
    database: ShutoNetworkDatabase
  ) throws -> ShutoNetworkDatabase.Edge {
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
    guard let predecessor = predecessors.first else {
      throw ShutoCircuitProductReleaseBuilderError.missingEntryPredecessor
    }
    return predecessor
  }

  private static func releasedRecovery(
    assets: ShutoPlannedRouteRuntimeAssets,
    database: ShutoNetworkDatabase
  ) throws -> RecoveryCandidate {
    let expectedTrigger = "osm.44804643.0.forward"
    guard
      let candidate = assets.recoveryCandidates.first(where: {
        $0.triggerDirectedEdgeID == expectedTrigger
      }),
      candidate.recoveryOccurrenceIDs.allSatisfy({ id in
        database.edges.contains { $0.edgeID == id }
      })
    else {
      throw ShutoCircuitProductReleaseBuilderError.missingRecoveryCandidate
    }
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
    entryPredecessorID: String,
    recovery: RecoveryCandidate
  ) throws -> RouteMatcherCorridor {
    let requiredIDs =
      Set(assets.matcherCorridor.edges.map(\.id))
      .union([entryPredecessorID])
      .union(recovery.recoveryOccurrenceIDs)
    let edgesByID = Dictionary(
      uniqueKeysWithValues: database.edges.map { ($0.edgeID, $0) }
    )
    let nodesByID = Dictionary(
      uniqueKeysWithValues: database.nodes.map { ($0.nodeID, $0) }
    )
    let outgoing = Dictionary(grouping: database.edges, by: \.fromNodeID)
    let edges = try requiredIDs.sorted().map { id -> RouteMatcherDirectedEdge in
      guard let edge = edgesByID[id] else {
        throw ShutoCircuitProductReleaseBuilderError.missingGraphEdge(id)
      }
      guard let from = nodesByID[edge.fromNodeID] else {
        throw ShutoCircuitProductReleaseBuilderError
          .missingGraphNode(edge.fromNodeID)
      }
      guard let to = nodesByID[edge.toNodeID] else {
        throw ShutoCircuitProductReleaseBuilderError
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
    return RouteMatcherCorridor(
      id: "\(assets.matcherCorridor.id).release.2026-08-15",
      networkSnapshotID: assets.matcherCorridor.networkSnapshotID,
      routePlanID: assets.matcherCorridor.routePlanID,
      edges: edges,
      occurrences: assets.matcherCorridor.occurrences
    )
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
    let guidance = movements.map { movement in
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
    let guidanceSourceIDs = movements.map(\.sourceID)
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
    networkSnapshot: NetworkSnapshot
  ) throws -> RouteAtlasReleaseArtifact {
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
          throw ShutoCircuitProductReleaseBuilderError
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
        (binding.entityID, "c1.topology.edge.\(index)")
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
    let topologyID = "shutoko.atlas.c1-inner-shibakoen-shiodome.topology.2026-08-15"
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
      let width = database.bounds.maximumLongitude
        - database.bounds.minimumLongitude
      let height = database.bounds.maximumLatitude
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
        (binding.entityID, "c1.atlas.segment.\(index)")
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
      id: "shutoko.atlas.c1-inner-shibakoen-shiodome.2026-08-15",
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
