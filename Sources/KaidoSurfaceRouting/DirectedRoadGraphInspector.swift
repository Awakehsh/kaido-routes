import Foundation

public enum SurfaceRoadEdgeKind: String, Codable, Sendable {
  case ordinaryRoad = "ORDINARY_ROAD"
  case entryTransition = "ENTRY_TRANSITION"
  case expressway = "EXPRESSWAY"
}

public enum OSMWayDirection: String, Codable, Sendable {
  case forward
  case reverse
}

public struct SurfaceRoadEdge: Codable, Equatable, Sendable {
  public let id: String
  public let fromNodeID: String
  public let toNodeID: String
  public let kind: SurfaceRoadEdgeKind
  public let coordinates: [SurfaceCoordinate]
  public let tollDomainID: String?
  public let sourceOSMWayID: Int64?
  public let sourceOSMSegmentIndex: Int?
  public let sourceOSMDirection: OSMWayDirection?

  public init(
    id: String,
    fromNodeID: String,
    toNodeID: String,
    kind: SurfaceRoadEdgeKind,
    coordinates: [SurfaceCoordinate],
    tollDomainID: String? = nil,
    sourceOSMWayID: Int64? = nil,
    sourceOSMSegmentIndex: Int? = nil,
    sourceOSMDirection: OSMWayDirection? = nil
  ) {
    self.id = id
    self.fromNodeID = fromNodeID
    self.toNodeID = toNodeID
    self.kind = kind
    self.coordinates = coordinates
    self.tollDomainID = tollDomainID
    self.sourceOSMWayID = sourceOSMWayID
    self.sourceOSMSegmentIndex = sourceOSMSegmentIndex
    self.sourceOSMDirection = sourceOSMDirection
  }

  private enum CodingKeys: String, CodingKey {
    case id = "edge_id"
    case fromNodeID = "from_node_id"
    case toNodeID = "to_node_id"
    case kind
    case coordinates
    case tollDomainID = "toll_domain_id"
    case sourceOSMWayID = "source_osm_way_id"
    case sourceOSMSegmentIndex = "source_osm_segment_index"
    case sourceOSMDirection = "source_osm_direction"
  }
}

public struct SurfaceRoadGraphSnapshot: Codable, Equatable, Sendable {
  public let networkSnapshotID: String
  public let provenance: SurfaceRoadGraphProvenance?
  public let edges: [SurfaceRoadEdge]

  public init(
    networkSnapshotID: String,
    provenance: SurfaceRoadGraphProvenance? = nil,
    edges: [SurfaceRoadEdge]
  ) {
    self.networkSnapshotID = networkSnapshotID
    self.provenance = provenance
    self.edges = edges
  }

  fileprivate var isStructurallyValid: Bool {
    guard !networkSnapshotID.isEmpty, !edges.isEmpty else { return false }
    guard Set(edges.map(\.id)).count == edges.count else { return false }
    return edges.allSatisfy { edge in
      !edge.id.isEmpty && !edge.fromNodeID.isEmpty && !edge.toNodeID.isEmpty
        && edge.coordinates.count >= 2
        && edge.coordinates.allSatisfy(\.isValid)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case networkSnapshotID = "network_snapshot_id"
    case provenance
    case edges
  }
}

public struct SurfaceRoadGraphProvenance: Codable, Equatable, Sendable {
  public let source: String
  public let sourceSnapshotAt: String
  public let sourceDatasetID: String?
  public let sourceURI: String
  public let licence: String
  public let attribution: String

  public init(
    source: String,
    sourceSnapshotAt: String,
    sourceDatasetID: String? = nil,
    sourceURI: String,
    licence: String,
    attribution: String
  ) {
    self.source = source
    self.sourceSnapshotAt = sourceSnapshotAt
    self.sourceDatasetID = sourceDatasetID
    self.sourceURI = sourceURI
    self.licence = licence
    self.attribution = attribution
  }

  private enum CodingKeys: String, CodingKey {
    case source
    case sourceSnapshotAt = "source_snapshot_at"
    case sourceDatasetID = "source_dataset_id"
    case sourceURI = "source_uri"
    case licence
    case attribution
  }
}

public struct DirectedRoadGraphInspectorConfiguration: Codable, Equatable, Sendable {
  public let sampleIntervalMeters: Double
  public let maximumMatchDistanceMeters: Double
  public let maximumHeadingDifferenceDegrees: Double
  public let headingPenaltyMeters: Double
  public let ambiguityMarginMeters: Double
  public let maximumSkippedEdgeHops: Int
  public let maximumMatchesPerSample: Int
  public let maximumSequenceStates: Int
  public let skippedEdgePenaltyMeters: Double
  public let transitionDistancePenaltyFactor: Double

  public init(
    sampleIntervalMeters: Double = 12,
    maximumMatchDistanceMeters: Double = 20,
    maximumHeadingDifferenceDegrees: Double = 55,
    headingPenaltyMeters: Double = 5,
    ambiguityMarginMeters: Double = 3,
    maximumSkippedEdgeHops: Int = 8,
    maximumMatchesPerSample: Int = 24,
    maximumSequenceStates: Int = 48,
    skippedEdgePenaltyMeters: Double = 0.5,
    transitionDistancePenaltyFactor: Double = 0.5
  ) {
    self.sampleIntervalMeters = sampleIntervalMeters
    self.maximumMatchDistanceMeters = maximumMatchDistanceMeters
    self.maximumHeadingDifferenceDegrees = maximumHeadingDifferenceDegrees
    self.headingPenaltyMeters = headingPenaltyMeters
    self.ambiguityMarginMeters = ambiguityMarginMeters
    self.maximumSkippedEdgeHops = maximumSkippedEdgeHops
    self.maximumMatchesPerSample = maximumMatchesPerSample
    self.maximumSequenceStates = maximumSequenceStates
    self.skippedEdgePenaltyMeters = skippedEdgePenaltyMeters
    self.transitionDistancePenaltyFactor = transitionDistancePenaltyFactor
  }

  fileprivate var isValid: Bool {
    sampleIntervalMeters > 0 && maximumMatchDistanceMeters > 0
      && (0...180).contains(maximumHeadingDifferenceDegrees)
      && headingPenaltyMeters >= 0 && ambiguityMarginMeters >= 0
      && maximumSkippedEdgeHops >= 0 && maximumMatchesPerSample > 0
      && maximumSequenceStates > 0 && skippedEdgePenaltyMeters >= 0
      && transitionDistancePenaltyFactor >= 0
  }

  private enum CodingKeys: String, CodingKey {
    case sampleIntervalMeters = "sample_interval_meters"
    case maximumMatchDistanceMeters = "maximum_match_distance_meters"
    case maximumHeadingDifferenceDegrees = "maximum_heading_difference_degrees"
    case headingPenaltyMeters = "heading_penalty_meters"
    case ambiguityMarginMeters = "ambiguity_margin_meters"
    case maximumSkippedEdgeHops = "maximum_skipped_edge_hops"
    case maximumMatchesPerSample = "maximum_matches_per_sample"
    case maximumSequenceStates = "maximum_sequence_states"
    case skippedEdgePenaltyMeters = "skipped_edge_penalty_meters"
    case transitionDistancePenaltyFactor = "transition_distance_penalty_factor"
  }
}

/// Binds provider geometry to a small, versioned, directed road graph.
///
/// This is an offline feasibility inspector, not the live Shuto map matcher. It
/// deliberately fails closed when graph coverage, direction, or topology is
/// unresolved.
public struct DirectedRoadGraphInspector: SurfaceCandidateInspector {
  public let graph: SurfaceRoadGraphSnapshot
  public let configuration: DirectedRoadGraphInspectorConfiguration
  private let measuredEdges: [MeasuredEdge]
  private let edgesByID: [String: SurfaceRoadEdge]
  private let edgeLengths: [String: Double]

  public init(
    graph: SurfaceRoadGraphSnapshot,
    configuration: DirectedRoadGraphInspectorConfiguration = .init()
  ) {
    self.graph = graph
    self.configuration = configuration
    let measuredEdges = graph.edges.compactMap(MeasuredEdge.init(edge:))
    self.measuredEdges = measuredEdges
    self.edgesByID = Dictionary(uniqueKeysWithValues: graph.edges.map { ($0.id, $0) })
    self.edgeLengths = Dictionary(
      uniqueKeysWithValues: measuredEdges.map { ($0.edge.id, $0.lengthMeters) }
    )
  }

  public func inspect(
    candidate: SurfaceRouteCandidate,
    request: SurfaceRouteRequest,
    fixture: EntranceProbeFixture
  ) async -> SurfaceCandidateInspection {
    guard graph.networkSnapshotID == fixture.networkSnapshotID,
      graph.isStructurallyValid,
      measuredEdges.count == graph.edges.count,
      configuration.isValid,
      candidate.coordinates.count >= 2,
      candidate.coordinates.allSatisfy(\.isValid),
      let samples = routeSamples(for: candidate.coordinates),
      let terminalHeading = samples.last?.headingDegrees
    else {
      return failedInspection()
    }

    if let selectedPathEvidence = candidate.selectedPathEvidence {
      return inspectSelectedPath(
        selectedPathEvidence,
        candidate: candidate,
        request: request,
        fixture: fixture,
        samples: samples,
        terminalHeading: terminalHeading
      )
    }

    let terminalCoordinate = candidate.coordinates[candidate.coordinates.count - 1]
    var matchesBySample = samples.map {
      edgeMatches(
        at: $0.coordinate,
        headingDegrees: $0.headingDegrees,
        measuredEdges: measuredEdges
      )
    }
    let unmatchedSampleCount = matchesBySample.count { $0.isEmpty }
    let terminalMatches = matchesBySample.last ?? []
    let terminalMatch = preferredTerminalMatch(
      matches: terminalMatches,
      expectedEdgeID: request.destinationAnchor.directedSurfaceEdgeID
    )
    if let terminalMatch,
      terminalMatch.edge.id == request.destinationAnchor.directedSurfaceEdgeID
    {
      matchesBySample[matchesBySample.count - 1] = [terminalMatch]
    }

    let outgoingEdges = makeOutgoingEdges(from: graph.edges)
    let selection = selectContinuousSequence(
      samples: samples,
      matchesBySample: matchesBySample,
      outgoingEdges: outgoingEdges,
      edgeLengths: edgeLengths
    )
    let pointwiseEdges = matchesBySample.compactMap { $0.first?.edge }
    let matchedEdges = selection?.sampleEdges ?? pointwiseEdges
    let matchedSequence = collapseAdjacentDuplicates(in: matchedEdges)
    let fallbackResolvedEdges = resolveContinuousPath(
      matchedSequence,
      outgoingEdges: outgoingEdges
    )
    let inspectedEdges = selection?.resolvedEdges ?? fallbackResolvedEdges ?? matchedSequence
    let disconnectedEdgeIDs =
      selection == nil
      ? disconnectedEdgePairs(in: matchedSequence, outgoingEdges: outgoingEdges) : []
    let ambiguousEdgeIDs =
      selection?.ambiguousEdgeIDs
      ?? pointwiseAmbiguousEdgeIDs(matchesBySample)
    let geometryIsUnambiguous =
      unmatchedSampleCount == 0 && selection != nil
      && ambiguousEdgeIDs.isEmpty

    let selectedTerminalMatch = matchedEdges.last.flatMap { selectedEdge in
      terminalMatches.first { $0.edge.id == selectedEdge.id }
    }

    let anchorBinding = selectedTerminalMatch.map { match in
      AnchorBindingObservation(
        anchorID: request.destinationAnchor.id,
        directedSurfaceEdgeID: match.edge.id,
        terminalDistanceMeters: distanceMeters(
          from: terminalCoordinate,
          to: request.destinationAnchor.coordinate
        ),
        terminalBearingDegrees: terminalHeading
      )
    }

    return SurfaceCandidateInspection(
      anchorBinding: anchorBinding,
      geometryBindingIsUnambiguous: geometryIsUnambiguous && anchorBinding != nil,
      expresswayEdgeIDsBeforeEntry: geometryIsUnambiguous
        ? uniqueIDs(inspectedEdges.filter { $0.kind != .ordinaryRoad }.map(\.id))
        : nil,
      crossedTollDomainIDs: geometryIsUnambiguous
        ? uniqueIDs(inspectedEdges.compactMap(\.tollDomainID))
        : nil,
      unmatchedSampleCount: unmatchedSampleCount,
      ambiguousDirectedEdgeIDs: uniqueIDs(ambiguousEdgeIDs),
      disconnectedDirectedEdgeIDs: disconnectedEdgeIDs,
      resolvedPathEdgeIDs: inspectedEdges.map(\.id)
    )
  }

  private func failedInspection() -> SurfaceCandidateInspection {
    SurfaceCandidateInspection(
      anchorBinding: nil,
      geometryBindingIsUnambiguous: false,
      expresswayEdgeIDsBeforeEntry: nil,
      crossedTollDomainIDs: nil,
      unmatchedSampleCount: nil,
      ambiguousDirectedEdgeIDs: nil,
      disconnectedDirectedEdgeIDs: nil,
      resolvedPathEdgeIDs: nil
    )
  }

  private func inspectSelectedPath(
    _ evidence: SurfaceSelectedPathEvidence,
    candidate: SurfaceRouteCandidate,
    request: SurfaceRouteRequest,
    fixture: EntranceProbeFixture,
    samples: [RouteSample],
    terminalHeading: Double
  ) -> SurfaceCandidateInspection {
    guard evidence.networkSnapshotID == graph.networkSnapshotID,
      evidence.networkSnapshotID == fixture.networkSnapshotID,
      !evidence.providerDatasetID.isEmpty,
      evidence.providerDatasetID == graph.provenance?.sourceDatasetID,
      !evidence.directedEdgeIDs.isEmpty,
      Set(evidence.directedEdgeIDs).count == evidence.directedEdgeIDs.count
    else {
      return failedInspection()
    }

    let missingEdgeIDs = evidence.directedEdgeIDs.filter { edgesByID[$0] == nil }
    guard missingEdgeIDs.isEmpty else {
      return invalidSelectedPathInspection(edgeIDs: missingEdgeIDs)
    }
    let selectedEdges = evidence.directedEdgeIDs.compactMap { edgesByID[$0] }
    let disconnectedEdgeIDs = exactDisconnectedEdgeIDs(in: selectedEdges)
    guard disconnectedEdgeIDs.isEmpty,
      selectedEdges.last?.id == request.destinationAnchor.directedSurfaceEdgeID
    else {
      return invalidSelectedPathInspection(
        edgeIDs: disconnectedEdgeIDs.isEmpty
          ? evidence.directedEdgeIDs : disconnectedEdgeIDs
      )
    }

    let selectedMeasuredEdges = selectedEdges.compactMap(MeasuredEdge.init(edge:))
    guard selectedMeasuredEdges.count == selectedEdges.count else {
      return invalidSelectedPathInspection(edgeIDs: evidence.directedEdgeIDs)
    }
    let selectedEdgeLengths = Dictionary(
      uniqueKeysWithValues: selectedMeasuredEdges.map { ($0.edge.id, $0.lengthMeters) }
    )
    var matchesBySample = samples.map {
      edgeMatches(
        at: $0.coordinate,
        headingDegrees: $0.headingDegrees,
        measuredEdges: selectedMeasuredEdges
      )
    }
    let unmatchedSampleCount = matchesBySample.count { $0.isEmpty }
    let terminalMatches = matchesBySample.last ?? []
    let terminalMatch = preferredTerminalMatch(
      matches: terminalMatches,
      expectedEdgeID: request.destinationAnchor.directedSurfaceEdgeID
    )
    if let terminalMatch,
      terminalMatch.edge.id == request.destinationAnchor.directedSurfaceEdgeID
    {
      matchesBySample[matchesBySample.count - 1] = [terminalMatch]
    }

    let selection = selectContinuousSequence(
      samples: samples,
      matchesBySample: matchesBySample,
      outgoingEdges: makeOutgoingEdges(from: selectedEdges),
      edgeLengths: selectedEdgeLengths
    )
    let selectionMatchesEvidence =
      selection?.resolvedEdges.map(\.id) == evidence.directedEdgeIDs
    let selectedTerminalMatch = terminalMatches.first {
      $0.edge.id == request.destinationAnchor.directedSurfaceEdgeID
    }
    let terminalCoordinate = candidate.coordinates[candidate.coordinates.count - 1]
    let anchorBinding = selectedTerminalMatch.map { match in
      AnchorBindingObservation(
        anchorID: request.destinationAnchor.id,
        directedSurfaceEdgeID: match.edge.id,
        terminalDistanceMeters: distanceMeters(
          from: terminalCoordinate,
          to: request.destinationAnchor.coordinate
        ),
        terminalBearingDegrees: terminalHeading
      )
    }
    let geometryIsBound =
      unmatchedSampleCount == 0 && selectionMatchesEvidence && anchorBinding != nil

    return SurfaceCandidateInspection(
      anchorBinding: anchorBinding,
      geometryBindingIsUnambiguous: geometryIsBound,
      expresswayEdgeIDsBeforeEntry: geometryIsBound
        ? uniqueIDs(selectedEdges.filter { $0.kind != .ordinaryRoad }.map(\.id))
        : nil,
      crossedTollDomainIDs: geometryIsBound
        ? uniqueIDs(selectedEdges.compactMap(\.tollDomainID))
        : nil,
      unmatchedSampleCount: unmatchedSampleCount,
      ambiguousDirectedEdgeIDs: [],
      disconnectedDirectedEdgeIDs: selectionMatchesEvidence
        ? [] : evidence.directedEdgeIDs,
      resolvedPathEdgeIDs: evidence.directedEdgeIDs
    )
  }

  private func invalidSelectedPathInspection(edgeIDs: [String]) -> SurfaceCandidateInspection {
    SurfaceCandidateInspection(
      anchorBinding: nil,
      geometryBindingIsUnambiguous: false,
      expresswayEdgeIDsBeforeEntry: nil,
      crossedTollDomainIDs: nil,
      unmatchedSampleCount: nil,
      ambiguousDirectedEdgeIDs: [],
      disconnectedDirectedEdgeIDs: uniqueIDs(edgeIDs),
      resolvedPathEdgeIDs: nil
    )
  }

  private func routeSamples(for coordinates: [SurfaceCoordinate]) -> [RouteSample]? {
    var result: [RouteSample] = []

    for index in 0..<(coordinates.count - 1) {
      let start = coordinates[index]
      let end = coordinates[index + 1]
      let segmentLength = distanceMeters(from: start, to: end)
      guard segmentLength > 0 else { continue }

      let heading = bearingDegrees(from: start, to: end)
      let divisions = max(1, Int(ceil(segmentLength / configuration.sampleIntervalMeters)))
      if result.isEmpty {
        result.append(RouteSample(coordinate: start, headingDegrees: heading))
      }
      for division in 1...divisions {
        result.append(
          RouteSample(
            coordinate: interpolate(
              from: start,
              to: end,
              fraction: Double(division) / Double(divisions)
            ),
            headingDegrees: heading
          )
        )
      }
    }

    return result.isEmpty ? nil : result
  }

  private func edgeMatches(
    at coordinate: SurfaceCoordinate,
    headingDegrees: Double,
    measuredEdges: [MeasuredEdge]
  ) -> [EdgeMatch] {
    measuredEdges.compactMap { measuredEdge in
      let edge = measuredEdge.edge
      var bestProjection: EdgeProjection?
      for index in 0..<(edge.coordinates.count - 1) {
        let start = edge.coordinates[index]
        let end = edge.coordinates[index + 1]
        let segmentLength = measuredEdge.segmentLengths[index]
        guard segmentLength > 0 else { continue }
        let projection = project(coordinate, ontoSegmentFrom: start, to: end)
        let headingDifference = angularDifference(
          headingDegrees,
          bearingDegrees(from: start, to: end)
        )
        guard projection.distanceMeters <= configuration.maximumMatchDistanceMeters,
          headingDifference <= configuration.maximumHeadingDifferenceDegrees
        else { continue }

        let candidate = EdgeProjection(
          distanceMeters: projection.distanceMeters,
          headingDifferenceDegrees: headingDifference,
          alongEdgeDistanceMeters: measuredEdge.segmentStartDistances[index]
            + projection.fraction * segmentLength,
          edgeLengthMeters: measuredEdge.lengthMeters
        )
        if bestProjection == nil
          || candidate.score(configuration: configuration)
            < bestProjection!.score(configuration: configuration)
        {
          bestProjection = candidate
        }
      }

      guard let bestProjection else { return nil }
      return EdgeMatch(
        edge: edge,
        distanceMeters: bestProjection.distanceMeters,
        headingDifferenceDegrees: bestProjection.headingDifferenceDegrees,
        alongEdgeDistanceMeters: bestProjection.alongEdgeDistanceMeters,
        edgeLengthMeters: bestProjection.edgeLengthMeters,
        score: bestProjection.score(configuration: configuration)
      )
    }
    .sorted { lhs, rhs in
      if lhs.score != rhs.score { return lhs.score < rhs.score }
      if lhs.distanceMeters != rhs.distanceMeters {
        return lhs.distanceMeters < rhs.distanceMeters
      }
      if lhs.headingDifferenceDegrees != rhs.headingDifferenceDegrees {
        return lhs.headingDifferenceDegrees < rhs.headingDifferenceDegrees
      }
      return lhs.edge.id < rhs.edge.id
    }
  }

  private func preferredTerminalMatch(
    matches: [EdgeMatch],
    expectedEdgeID: String
  ) -> EdgeMatch? {
    guard let best = matches.first else { return nil }
    guard let expected = matches.first(where: { $0.edge.id == expectedEdgeID }) else {
      return best
    }
    return expected.score <= best.score + configuration.ambiguityMarginMeters
      ? expected : best
  }

  private func ambiguousAlternatives(best: EdgeMatch, matches: [EdgeMatch]) -> [EdgeMatch] {
    matches.filter { alternative in
      alternative.edge.id != best.edge.id
        && alternative.score <= best.score + configuration.ambiguityMarginMeters
        && !edgesFormOneDirectedPath(best.edge, alternative.edge)
    }
  }

  private func pointwiseAmbiguousEdgeIDs(_ matchesBySample: [[EdgeMatch]]) -> [String] {
    var result: [String] = []
    for matches in matchesBySample {
      guard let best = matches.first else { continue }
      let alternatives = ambiguousAlternatives(best: best, matches: matches)
      if !alternatives.isEmpty {
        result.append(best.edge.id)
        result.append(contentsOf: alternatives.map(\.edge.id))
      }
    }
    return uniqueIDs(result)
  }

  private func makeOutgoingEdges(
    from edges: [SurfaceRoadEdge]
  ) -> [String: [SurfaceRoadEdge]] {
    Dictionary(grouping: edges, by: \.fromNodeID).mapValues {
      $0.sorted { $0.id < $1.id }
    }
  }

  private func exactDisconnectedEdgeIDs(in edges: [SurfaceRoadEdge]) -> [String] {
    guard edges.count > 1 else { return [] }
    return uniqueIDs(
      zip(edges, edges.dropFirst()).flatMap { source, target in
        source.toNodeID == target.fromNodeID ? [] : [source.id, target.id]
      }
    )
  }

  private func selectContinuousSequence(
    samples: [RouteSample],
    matchesBySample: [[EdgeMatch]],
    outgoingEdges: [String: [SurfaceRoadEdge]],
    edgeLengths: [String: Double]
  ) -> SequenceSelection? {
    guard samples.count == matchesBySample.count,
      let firstMatches = matchesBySample.first, !firstMatches.isEmpty,
      matchesBySample.allSatisfy({ !$0.isEmpty })
    else { return nil }

    var states = firstMatches.prefix(configuration.maximumMatchesPerSample).map { match in
      SequenceState(
        cost: match.score,
        lastMatch: match,
        sampleEdges: [match.edge],
        resolvedEdges: [match.edge]
      )
    }
    var connectorCache: [EdgePair: ConnectorLookup] = [:]

    for sampleIndex in 1..<matchesBySample.count {
      let matches = matchesBySample[sampleIndex]
      let observedDistance = distanceMeters(
        from: samples[sampleIndex - 1].coordinate,
        to: samples[sampleIndex].coordinate
      )
      var nextStates: [SequenceState] = []
      for state in states {
        let source = state.lastMatch
        for match in matches.prefix(configuration.maximumMatchesPerSample) {
          let pair = EdgePair(sourceID: source.edge.id, targetID: match.edge.id)
          let lookup: ConnectorLookup
          if let cached = connectorCache[pair] {
            lookup = cached
          } else if let connectors = connectorEdges(
            from: source.edge,
            to: match.edge,
            outgoingEdges: outgoingEdges
          ) {
            lookup = .found(connectors)
            connectorCache[pair] = lookup
          } else {
            lookup = .missing
            connectorCache[pair] = lookup
          }

          guard case .found(let connectors) = lookup else { continue }
          guard
            let graphDistance = graphTravelDistance(
              from: source,
              through: connectors,
              to: match,
              edgeLengths: edgeLengths
            )
          else { continue }
          let transitionPenalty =
            abs(graphDistance - observedDistance)
            * configuration.transitionDistancePenaltyFactor
          var resolvedEdges = state.resolvedEdges
          for edge in connectors + [match.edge] where resolvedEdges.last?.id != edge.id {
            resolvedEdges.append(edge)
          }
          nextStates.append(
            SequenceState(
              cost: state.cost + match.score
                + Double(connectors.count) * configuration.skippedEdgePenaltyMeters
                + transitionPenalty,
              lastMatch: match,
              sampleEdges: state.sampleEdges + [match.edge],
              resolvedEdges: resolvedEdges
            )
          )
        }
      }

      var signatures: Set<String> = []
      states = nextStates.sorted(by: sequenceStateOrder).filter { state in
        signatures.insert(state.pathSignature).inserted
      }
      if states.count > configuration.maximumSequenceStates {
        states.removeLast(states.count - configuration.maximumSequenceStates)
      }
      guard !states.isEmpty else { return nil }
    }

    let ordered = states.sorted(by: sequenceStateOrder)
    guard let best = ordered.first else { return nil }
    let alternative = ordered.dropFirst().first {
      $0.cost <= best.cost + configuration.ambiguityMarginMeters
        && $0.pathSignature != best.pathSignature
    }
    return SequenceSelection(
      sampleEdges: best.sampleEdges,
      resolvedEdges: best.resolvedEdges,
      ambiguousEdgeIDs: alternative.map {
        differingEdgeIDs(best.resolvedEdges, $0.resolvedEdges)
      } ?? []
    )
  }

  private func graphTravelDistance(
    from source: EdgeMatch,
    through connectors: [SurfaceRoadEdge],
    to target: EdgeMatch,
    edgeLengths: [String: Double]
  ) -> Double? {
    if source.edge.id == target.edge.id {
      let progress = target.alongEdgeDistanceMeters - source.alongEdgeDistanceMeters
      guard progress >= -projectionProgressToleranceMeters else { return nil }
      return max(0, progress)
    }

    let connectorLengths = connectors.compactMap { edgeLengths[$0.id] }
    guard connectorLengths.count == connectors.count else { return nil }
    let connectorDistance = connectorLengths.reduce(0, +)
    return max(0, source.edgeLengthMeters - source.alongEdgeDistanceMeters)
      + connectorDistance
      + target.alongEdgeDistanceMeters
  }

  private func sequenceStateOrder(_ lhs: SequenceState, _ rhs: SequenceState) -> Bool {
    if lhs.cost != rhs.cost { return lhs.cost < rhs.cost }
    return lhs.pathSignature < rhs.pathSignature
  }

  private func differingEdgeIDs(
    _ lhs: [SurfaceRoadEdge],
    _ rhs: [SurfaceRoadEdge]
  ) -> [String] {
    let lhsIDs = lhs.map(\.id)
    let rhsIDs = rhs.map(\.id)
    let lhsSet = Set(lhsIDs)
    let rhsSet = Set(rhsIDs)
    let difference =
      lhsIDs.filter { !rhsSet.contains($0) }
      + rhsIDs.filter { !lhsSet.contains($0) }
    if !difference.isEmpty { return uniqueIDs(difference) }
    return uniqueIDs([lhs.last?.id, rhs.last?.id].compactMap { $0 })
  }

  private func edgesFormOneDirectedPath(_ lhs: SurfaceRoadEdge, _ rhs: SurfaceRoadEdge) -> Bool {
    lhs.toNodeID == rhs.fromNodeID || rhs.toNodeID == lhs.fromNodeID
  }

  private func resolveContinuousPath(
    _ edges: [SurfaceRoadEdge],
    outgoingEdges: [String: [SurfaceRoadEdge]]
  ) -> [SurfaceRoadEdge]? {
    guard let first = edges.first else { return nil }
    var result = [first]

    for target in edges.dropFirst() {
      guard let source = result.last,
        let connectors = connectorEdges(
          from: source,
          to: target,
          outgoingEdges: outgoingEdges
        )
      else { return nil }

      for connector in connectors where result.last?.id != connector.id {
        result.append(connector)
      }
      if result.last?.id != target.id {
        result.append(target)
      }
    }
    return result
  }

  private func disconnectedEdgePairs(
    in edges: [SurfaceRoadEdge],
    outgoingEdges: [String: [SurfaceRoadEdge]]
  ) -> [String] {
    guard edges.count > 1 else { return [] }
    var result: [String] = []
    for (source, target) in zip(edges, edges.dropFirst())
    where connectorEdges(
      from: source,
      to: target,
      outgoingEdges: outgoingEdges
    ) == nil {
      result.append(source.id)
      result.append(target.id)
    }
    return uniqueIDs(result)
  }

  private func connectorEdges(
    from source: SurfaceRoadEdge,
    to target: SurfaceRoadEdge,
    outgoingEdges: [String: [SurfaceRoadEdge]]
  ) -> [SurfaceRoadEdge]? {
    if source.id == target.id || source.toNodeID == target.fromNodeID { return [] }

    var queue: [(nodeID: String, path: [SurfaceRoadEdge])] = [(source.toNodeID, [])]
    var visited: Set<String> = [source.toNodeID]
    var cursor = 0

    while cursor < queue.count {
      let state = queue[cursor]
      cursor += 1
      if state.nodeID == target.fromNodeID { return state.path }
      guard state.path.count < configuration.maximumSkippedEdgeHops else { continue }

      for edge in outgoingEdges[state.nodeID, default: []] {
        if edge.id == target.id { return state.path }
        let path = state.path + [edge]
        if edge.toNodeID == target.fromNodeID { return path }
        if visited.insert(edge.toNodeID).inserted {
          queue.append((edge.toNodeID, path))
        }
      }
    }
    return nil
  }

  private func collapseAdjacentDuplicates(in edges: [SurfaceRoadEdge]) -> [SurfaceRoadEdge] {
    edges.reduce(into: []) { result, edge in
      if result.last?.id != edge.id { result.append(edge) }
    }
  }

  private func uniqueIDs(_ ids: [String]) -> [String] {
    var seen: Set<String> = []
    return ids.filter { seen.insert($0).inserted }
  }
}

private struct RouteSample {
  let coordinate: SurfaceCoordinate
  let headingDegrees: Double
}

private struct MeasuredEdge {
  let edge: SurfaceRoadEdge
  let segmentLengths: [Double]
  let segmentStartDistances: [Double]
  let lengthMeters: Double

  init?(edge: SurfaceRoadEdge) {
    let segmentLengths = zip(edge.coordinates, edge.coordinates.dropFirst()).map {
      distanceMeters(from: $0, to: $1)
    }
    var length = 0.0
    let segmentStartDistances = segmentLengths.map { segmentLength in
      defer { length += segmentLength }
      return length
    }
    guard length > 0 else { return nil }
    self.edge = edge
    self.segmentLengths = segmentLengths
    self.segmentStartDistances = segmentStartDistances
    self.lengthMeters = length
  }
}

private struct EdgeMatch {
  let edge: SurfaceRoadEdge
  let distanceMeters: Double
  let headingDifferenceDegrees: Double
  let alongEdgeDistanceMeters: Double
  let edgeLengthMeters: Double
  let score: Double
}

private struct SequenceSelection {
  let sampleEdges: [SurfaceRoadEdge]
  let resolvedEdges: [SurfaceRoadEdge]
  let ambiguousEdgeIDs: [String]
}

private struct SequenceState {
  let cost: Double
  let lastMatch: EdgeMatch
  let sampleEdges: [SurfaceRoadEdge]
  let resolvedEdges: [SurfaceRoadEdge]

  var pathSignature: String {
    resolvedEdges.map(\.id).joined(separator: "|")
  }
}

private struct EdgePair: Hashable {
  let sourceID: String
  let targetID: String
}

private enum ConnectorLookup {
  case found([SurfaceRoadEdge])
  case missing
}

private struct EdgeProjection {
  let distanceMeters: Double
  let headingDifferenceDegrees: Double
  let alongEdgeDistanceMeters: Double
  let edgeLengthMeters: Double

  func score(configuration: DirectedRoadGraphInspectorConfiguration) -> Double {
    distanceMeters
      + headingDifferenceDegrees / max(1, configuration.maximumHeadingDifferenceDegrees)
      * configuration.headingPenaltyMeters
  }
}

private let earthRadiusMeters = 6_371_000.0
private let projectionProgressToleranceMeters = 0.5

private func distanceMeters(from start: SurfaceCoordinate, to end: SurfaceCoordinate) -> Double {
  let startLatitude = radians(start.latitude)
  let endLatitude = radians(end.latitude)
  let latitudeDelta = endLatitude - startLatitude
  let longitudeDelta = radians(end.longitude - start.longitude)
  let haversine =
    sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
    + cos(startLatitude) * cos(endLatitude)
    * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
  return earthRadiusMeters * 2 * atan2(sqrt(haversine), sqrt(max(0, 1 - haversine)))
}

private func bearingDegrees(from start: SurfaceCoordinate, to end: SurfaceCoordinate) -> Double {
  let startLatitude = radians(start.latitude)
  let endLatitude = radians(end.latitude)
  let longitudeDelta = radians(end.longitude - start.longitude)
  let y = sin(longitudeDelta) * cos(endLatitude)
  let x =
    cos(startLatitude) * sin(endLatitude)
    - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
  return normalizedDegrees(degrees(atan2(y, x)))
}

private func angularDifference(_ lhs: Double, _ rhs: Double) -> Double {
  let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
  return min(difference, 360 - difference)
}

private func interpolate(
  from start: SurfaceCoordinate,
  to end: SurfaceCoordinate,
  fraction: Double
) -> SurfaceCoordinate {
  SurfaceCoordinate(
    latitude: start.latitude + (end.latitude - start.latitude) * fraction,
    longitude: start.longitude + (end.longitude - start.longitude) * fraction
  )
}

private func project(
  _ point: SurfaceCoordinate,
  ontoSegmentFrom start: SurfaceCoordinate,
  to end: SurfaceCoordinate
) -> (distanceMeters: Double, fraction: Double) {
  let referenceLatitude = radians((point.latitude + start.latitude + end.latitude) / 3)
  let startX =
    radians(start.longitude - point.longitude) * cos(referenceLatitude)
    * earthRadiusMeters
  let startY = radians(start.latitude - point.latitude) * earthRadiusMeters
  let endX =
    radians(end.longitude - point.longitude) * cos(referenceLatitude)
    * earthRadiusMeters
  let endY = radians(end.latitude - point.latitude) * earthRadiusMeters
  let deltaX = endX - startX
  let deltaY = endY - startY
  let lengthSquared = deltaX * deltaX + deltaY * deltaY
  let fraction: Double
  if lengthSquared == 0 {
    fraction = 0
  } else {
    fraction = min(1, max(0, -(startX * deltaX + startY * deltaY) / lengthSquared))
  }
  let projectedX = startX + deltaX * fraction
  let projectedY = startY + deltaY * fraction
  return (sqrt(projectedX * projectedX + projectedY * projectedY), fraction)
}

private func radians(_ degrees: Double) -> Double {
  degrees * .pi / 180
}

private func degrees(_ radians: Double) -> Double {
  radians * 180 / .pi
}

private func normalizedDegrees(_ degrees: Double) -> Double {
  let value = degrees.truncatingRemainder(dividingBy: 360)
  return value >= 0 ? value : value + 360
}
