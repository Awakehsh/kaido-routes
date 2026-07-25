import Foundation

public struct SurfaceEgressCalibrationOccurrenceBinding:
  Codable, Equatable, Sendable
{
  public let occurrenceID: String
  public let occurrenceIndex: Int
  public let directedEdgeID: String

  public init(
    occurrenceID: String,
    occurrenceIndex: Int,
    directedEdgeID: String
  ) {
    self.occurrenceID = occurrenceID
    self.occurrenceIndex = occurrenceIndex
    self.directedEdgeID = directedEdgeID
  }

  private enum CodingKeys: String, CodingKey {
    case occurrenceID = "occurrence_id"
    case occurrenceIndex = "occurrence_index"
    case directedEdgeID = "directed_edge_id"
  }
}

/// Release, route, corridor, matcher, device, and transport identity for one
/// ordinary-road egress calibration window.
///
/// This scope is deliberately separate from `MatcherCalibrationScope`.
/// Expressway and surface-egress traces cannot be combined into one report.
public struct SurfaceEgressMatcherCalibrationScope:
  Codable, Equatable, Sendable
{
  public let productReleaseID: String
  public let navigationReleaseID: String
  public let journeyPlanID: String
  public let runtimePolicyID: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let providerDatasetID: String
  public let candidateID: String
  public let egressOptionID: String
  public let exitFacilityID: String
  public let handoffAnchorID: String
  public let directedSurfaceEdgeID: String
  public let matcherCorridorID: String
  public let handoffOccurrenceID: String
  public let occurrences: [SurfaceEgressCalibrationOccurrenceBinding]
  public let matcherAlgorithmID: String
  public let matcherConfigurationID: String
  public let matcherConfiguration: SurfaceEgressMatcherConfiguration
  public let deviceConfigurationID: String
  public let fieldTransportContext: MatcherFieldTransportContext

  public init(
    admissionContext: SurfaceEgressAdmissionContext,
    matcherAlgorithmID: String = SurfaceEgressMatcherSession.algorithmID,
    matcherConfigurationID: String,
    matcherConfiguration: SurfaceEgressMatcherConfiguration,
    deviceConfigurationID: String,
    fieldTransportContext: MatcherFieldTransportContext
  ) {
    productReleaseID = admissionContext.productReleaseID
    navigationReleaseID = admissionContext.navigationReleaseID
    journeyPlanID = admissionContext.journeyPlanID
    runtimePolicyID = admissionContext.runtimePolicyID
    networkSnapshotID = admissionContext.networkSnapshotID
    routePlanID = admissionContext.routePlanID
    providerDatasetID = admissionContext.matcherCorridor.providerDatasetID
    candidateID = admissionContext.matcherCorridor.candidateID
    egressOptionID = admissionContext.egressOptionID
    exitFacilityID = admissionContext.exitFacilityID
    handoffAnchorID = admissionContext.handoffAnchorID
    directedSurfaceEdgeID = admissionContext.directedSurfaceEdgeID
    matcherCorridorID = admissionContext.matcherCorridorID
    handoffOccurrenceID = admissionContext.handoffOccurrenceID
    occurrences = admissionContext.matcherCorridor.occurrences.map {
      SurfaceEgressCalibrationOccurrenceBinding(
        occurrenceID: $0.id,
        occurrenceIndex: $0.index,
        directedEdgeID: $0.directedEdgeID
      )
    }
    self.matcherAlgorithmID = matcherAlgorithmID
    self.matcherConfigurationID = matcherConfigurationID
    self.matcherConfiguration = matcherConfiguration
    self.deviceConfigurationID = deviceConfigurationID
    self.fieldTransportContext = fieldTransportContext
  }

  public var validationIssues: [String] {
    var issues: [String] = []
    let identities = [
      productReleaseID,
      navigationReleaseID,
      journeyPlanID,
      runtimePolicyID,
      networkSnapshotID,
      routePlanID,
      providerDatasetID,
      candidateID,
      egressOptionID,
      exitFacilityID,
      handoffAnchorID,
      directedSurfaceEdgeID,
      matcherCorridorID,
      handoffOccurrenceID,
      matcherAlgorithmID,
      matcherConfigurationID,
      deviceConfigurationID,
    ]
    if identities.contains(where: {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) {
      issues.append("surface egress calibration scope identity is invalid")
    }
    issues.append(contentsOf: occurrenceValidationIssues)
    if !matcherConfiguration.isValid {
      issues.append("surface egress calibration matcher configuration is invalid")
    }
    return Array(Set(issues)).sorted()
  }

  public func matches(_ admissionContext: SurfaceEgressAdmissionContext) -> Bool {
    self
      == SurfaceEgressMatcherCalibrationScope(
        admissionContext: admissionContext,
        matcherAlgorithmID: matcherAlgorithmID,
        matcherConfigurationID: matcherConfigurationID,
        matcherConfiguration: matcherConfiguration,
        deviceConfigurationID: deviceConfigurationID,
        fieldTransportContext: fieldTransportContext
      )
  }

  private enum CodingKeys: String, CodingKey {
    case productReleaseID = "product_release_id"
    case navigationReleaseID = "navigation_release_id"
    case journeyPlanID = "journey_plan_id"
    case runtimePolicyID = "runtime_policy_id"
    case networkSnapshotID = "network_snapshot_id"
    case routePlanID = "route_plan_id"
    case providerDatasetID = "provider_dataset_id"
    case candidateID = "candidate_id"
    case egressOptionID = "egress_option_id"
    case exitFacilityID = "exit_facility_id"
    case handoffAnchorID = "handoff_anchor_id"
    case directedSurfaceEdgeID = "directed_surface_edge_id"
    case matcherCorridorID = "matcher_corridor_id"
    case handoffOccurrenceID = "handoff_occurrence_id"
    case occurrences
    case matcherAlgorithmID = "matcher_algorithm_id"
    case matcherConfigurationID = "matcher_configuration_id"
    case matcherConfiguration = "matcher_configuration"
    case deviceConfigurationID = "device_configuration_id"
    case fieldTransportContext = "field_transport_context"
  }

  private var occurrenceValidationIssues: [String] {
    guard !occurrences.isEmpty else {
      return ["surface egress calibration occurrence bindings are empty"]
    }
    let occurrenceIDs = occurrences.map(\.occurrenceID)
    guard Set(occurrenceIDs).count == occurrenceIDs.count else {
      return ["surface egress calibration occurrence bindings are not unique"]
    }
    guard occurrences.map(\.occurrenceIndex) == Array(0..<occurrences.count)
    else {
      return ["surface egress calibration occurrence bindings are not ordered"]
    }
    guard
      occurrences.allSatisfy({
        !$0.occurrenceID.isEmpty && !$0.directedEdgeID.isEmpty
      })
    else {
      return ["surface egress calibration occurrence binding is invalid"]
    }
    guard occurrences.first?.occurrenceID == handoffOccurrenceID else {
      return ["surface egress calibration handoff occurrence is not first"]
    }
    guard occurrences.first?.directedEdgeID == directedSurfaceEdgeID else {
      return ["surface egress calibration handoff edge is not first"]
    }
    return []
  }
}

/// Sensitive collection metadata retained only beside private raw locations.
public struct SurfaceEgressPrivateTraceContext:
  Codable, Equatable, Sendable
{
  public let traceID: String
  public let scope: SurfaceEgressMatcherCalibrationScope
  public let deviceModel: String
  public let operatingSystemVersion: String
  public let appBuild: String
  public let mountDescription: String
  public let headUnitDescription: String?
  public let collectionMethod: MatcherTraceCollectionMethod
  public let startedAtMilliseconds: Int
  public let privacyClassification: MatcherTracePrivacyClassification

  public init(
    traceID: String,
    scope: SurfaceEgressMatcherCalibrationScope,
    deviceModel: String,
    operatingSystemVersion: String,
    appBuild: String,
    mountDescription: String,
    headUnitDescription: String? = nil,
    collectionMethod: MatcherTraceCollectionMethod,
    startedAtMilliseconds: Int,
    privacyClassification: MatcherTracePrivacyClassification = .privateRawLocation
  ) {
    self.traceID = traceID
    self.scope = scope
    self.deviceModel = deviceModel
    self.operatingSystemVersion = operatingSystemVersion
    self.appBuild = appBuild
    self.mountDescription = mountDescription
    self.headUnitDescription = headUnitDescription
    self.collectionMethod = collectionMethod
    self.startedAtMilliseconds = startedAtMilliseconds
    self.privacyClassification = privacyClassification
  }

  public var validationIssues: [String] {
    var issues = scope.validationIssues
    let identities = [
      traceID,
      deviceModel,
      operatingSystemVersion,
      appBuild,
      mountDescription,
    ]
    if identities.contains(where: {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) {
      issues.append("surface egress private trace context is invalid")
    }
    if startedAtMilliseconds < 0 {
      issues.append("surface egress private trace start time is negative")
    }
    return Array(Set(issues)).sorted()
  }

  private enum CodingKeys: String, CodingKey {
    case traceID = "trace_id"
    case scope
    case deviceModel = "device_model"
    case operatingSystemVersion = "operating_system_version"
    case appBuild = "app_build"
    case mountDescription = "mount_description"
    case headUnitDescription = "head_unit_description"
    case collectionMethod = "collection_method"
    case startedAtMilliseconds = "started_at_ms"
    case privacyClassification = "privacy_classification"
  }
}

/// One private surface-egress observation. Raw coordinates exist only here.
public struct SurfaceEgressPrivateTraceEntry:
  Codable, Equatable, Sendable
{
  public let observationID: String
  public let status: MatcherPrivateTraceEntryStatus
  public let observation: MatcherReplayObservation?
  public let provenance: MatcherTraceSourceProvenance?
  public let estimate: SurfaceEgressMatcherEstimate?
  public let adapterRejectionCode: String?
  public let matcherRejectionCode: String?
  public let adaptationDurationMicroseconds: Int
  public let matchingDurationMicroseconds: Int?

  public init(
    observationID: String,
    status: MatcherPrivateTraceEntryStatus,
    observation: MatcherReplayObservation? = nil,
    provenance: MatcherTraceSourceProvenance? = nil,
    estimate: SurfaceEgressMatcherEstimate? = nil,
    adapterRejectionCode: String? = nil,
    matcherRejectionCode: String? = nil,
    adaptationDurationMicroseconds: Int,
    matchingDurationMicroseconds: Int? = nil
  ) {
    self.observationID = observationID
    self.status = status
    self.observation = observation
    self.provenance = provenance
    self.estimate = estimate
    self.adapterRejectionCode = adapterRejectionCode
    self.matcherRejectionCode = matcherRejectionCode
    self.adaptationDurationMicroseconds = adaptationDurationMicroseconds
    self.matchingDurationMicroseconds = matchingDurationMicroseconds
  }

  public var validationIssues: [String] {
    var issues: [String] = []
    if observationID.isEmpty {
      issues.append("surface egress trace entry observation id is empty")
    }
    if adaptationDurationMicroseconds < 0
      || matchingDurationMicroseconds.map({ $0 < 0 }) == true
    {
      issues.append("surface egress trace entry duration is negative")
    }
    if let matchingDurationMicroseconds {
      let (_, overflow) = adaptationDurationMicroseconds.addingReportingOverflow(
        matchingDurationMicroseconds
      )
      if overflow {
        issues.append("surface egress trace entry pipeline duration overflows")
      }
    }
    if let observation {
      if observation.id != observationID
        || !observation.coordinate.isValid
        || !observation.horizontalAccuracyMeters.isFinite
        || observation.horizontalAccuracyMeters <= 0
        || observation.receivedAtMilliseconds < observation.observedAtMilliseconds
      {
        issues.append("surface egress trace entry observation is invalid")
      }
    }
    if let estimate {
      if estimate.observationID != observationID {
        issues.append("surface egress trace entry observation id does not match estimate")
      }
      if estimate.corridorID.isEmpty {
        issues.append("surface egress trace entry estimate corridor is empty")
      }
    }
    if let observation, let provenance,
      observation.source != provenance.calibrationCohort
    {
      issues.append("surface egress trace entry source does not match provenance cohort")
    }

    switch status {
    case .matched:
      if observation == nil || provenance == nil || estimate == nil
        || matchingDurationMicroseconds == nil
        || adapterRejectionCode != nil || matcherRejectionCode != nil
      {
        issues.append("matched surface egress trace entry has inconsistent fields")
      }
    case .adapterRejected:
      if observation != nil || provenance != nil || estimate != nil
        || adapterRejectionCode?.isEmpty != false || matcherRejectionCode != nil
        || matchingDurationMicroseconds != nil
      {
        issues.append("adapter-rejected surface egress trace entry has inconsistent fields")
      }
    case .matcherRejected:
      if observation == nil || provenance == nil || estimate != nil
        || adapterRejectionCode != nil || matcherRejectionCode?.isEmpty != false
        || matchingDurationMicroseconds == nil
      {
        issues.append("matcher-rejected surface egress trace entry has inconsistent fields")
      }
    }
    return issues
  }

  private enum CodingKeys: String, CodingKey {
    case observationID = "observation_id"
    case status
    case observation
    case provenance
    case estimate
    case adapterRejectionCode = "adapter_rejection_code"
    case matcherRejectionCode = "matcher_rejection_code"
    case adaptationDurationMicroseconds = "adaptation_duration_us"
    case matchingDurationMicroseconds = "matching_duration_us"
  }
}

public struct SurfaceEgressPrivateTrace: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let context: SurfaceEgressPrivateTraceContext
  public let entries: [SurfaceEgressPrivateTraceEntry]

  public init(
    schemaVersion: String = "1.0",
    context: SurfaceEgressPrivateTraceContext,
    entries: [SurfaceEgressPrivateTraceEntry]
  ) {
    self.schemaVersion = schemaVersion
    self.context = context
    self.entries = entries
  }

  public var validationIssues: [String] {
    var issues = context.validationIssues
    if schemaVersion != "1.0" {
      issues.append("unsupported surface egress private trace schema version")
    }
    if entries.isEmpty {
      issues.append("surface egress private trace has no entries")
    }
    let observationIDs = entries.map(\.observationID)
    if Set(observationIDs).count != observationIDs.count {
      issues.append("surface egress private trace observation ids are not unique")
    }
    for entry in entries {
      issues.append(contentsOf: entry.validationIssues)
      if entry.estimate.map({ $0.corridorID != context.scope.matcherCorridorID }) == true {
        issues.append("surface egress estimate corridor differs from calibration scope")
      }
      if let estimate = entry.estimate {
        issues.append(
          contentsOf: estimateValidationIssues(
            estimate,
            bindings: context.scope.occurrences
          )
        )
      }
      if entry.provenance.map({
        $0.fieldTransportContext != context.scope.fieldTransportContext
      }) == true {
        issues.append("surface egress trace transport differs from calibration scope")
      }
    }
    return Array(Set(issues)).sorted()
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case context
    case entries
  }

  private func estimateValidationIssues(
    _ estimate: SurfaceEgressMatcherEstimate,
    bindings: [SurfaceEgressCalibrationOccurrenceBinding]
  ) -> [String] {
    var issues: [String] = []
    var bindingsByOccurrence: [String: SurfaceEgressCalibrationOccurrenceBinding] = [:]
    for binding in bindings {
      bindingsByOccurrence[binding.occurrenceID] = binding
    }
    let knownEdges = Set(bindings.map(\.directedEdgeID))
    if let occurrenceID = estimate.occurrenceID {
      guard
        let binding = bindingsByOccurrence[occurrenceID],
        estimate.occurrenceIndex == binding.occurrenceIndex,
        estimate.directedEdgeID == binding.directedEdgeID
      else {
        return ["surface egress selected occurrence differs from calibration scope"]
      }
    } else if estimate.occurrenceIndex != nil || estimate.directedEdgeID != nil {
      issues.append("surface egress selected occurrence is incomplete")
    }
    if !estimate.candidateOccurrenceIDs.allSatisfy({
      bindingsByOccurrence[$0] != nil
    }) {
      issues.append("surface egress candidate occurrence differs from calibration scope")
    }
    if !estimate.candidateEdgeIDs.allSatisfy(knownEdges.contains) {
      issues.append("surface egress candidate edge differs from calibration scope")
    }
    if estimate.confidence == .high && estimate.occurrenceID == nil {
      issues.append("surface egress HIGH estimate has no occurrence")
    }
    return issues
  }
}

public struct SurfaceEgressGroundTruthAnnotation:
  Codable, Equatable, Sendable
{
  public let observationID: String
  public let partition: MatcherCalibrationPartition
  public let directedEdgeID: String
  public let occurrenceID: String

  public init(
    observationID: String,
    partition: MatcherCalibrationPartition,
    directedEdgeID: String,
    occurrenceID: String
  ) {
    self.observationID = observationID
    self.partition = partition
    self.directedEdgeID = directedEdgeID
    self.occurrenceID = occurrenceID
  }

  private enum CodingKeys: String, CodingKey {
    case observationID = "observation_id"
    case partition
    case directedEdgeID = "directed_edge_id"
    case occurrenceID = "occurrence_id"
  }
}

/// Coordinate-free output for one exact surface-egress calibration scope.
public struct SurfaceEgressMatcherCalibrationReport:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "1.1"

  public let schemaVersion: String
  public let reportID: String
  public let scope: SurfaceEgressMatcherCalibrationScope
  public let collectionMethod: MatcherTraceCollectionMethod
  public let traceCount: Int
  public let entryCount: Int
  public let matchedEntryCount: Int
  public let adapterRejectionCount: Int
  public let matcherRejectionCount: Int
  public let simulatedMatchedEntryCount: Int
  public let annotatedEntryCount: Int
  public let unannotatedMatchedEntryCount: Int
  public let unsafeHighConfidenceEdgeCount: Int
  public let unsafeHighConfidenceOccurrenceCount: Int
  public let adaptationP95Microseconds: Int?
  public let matcherP95Microseconds: Int?
  public let pipelineP95Microseconds: Int?
  public let minimumHeldOutSamplesPerCohort: Int
  public let matcherP95BudgetMicroseconds: Int
  public let matcherP95BudgetMet: Bool
  public let reliabilityBins: [MatcherReliabilityBin]
  public let gateStatus: MatcherCalibrationGateStatus
  public let probabilityCalibrationStatus: MatcherProbabilityCalibrationStatus

  public init(
    schemaVersion: String =
      SurfaceEgressMatcherCalibrationReport.currentSchemaVersion,
    reportID: String,
    scope: SurfaceEgressMatcherCalibrationScope,
    collectionMethod: MatcherTraceCollectionMethod,
    traceCount: Int,
    entryCount: Int,
    matchedEntryCount: Int,
    adapterRejectionCount: Int,
    matcherRejectionCount: Int,
    simulatedMatchedEntryCount: Int,
    annotatedEntryCount: Int,
    unannotatedMatchedEntryCount: Int,
    unsafeHighConfidenceEdgeCount: Int,
    unsafeHighConfidenceOccurrenceCount: Int,
    adaptationP95Microseconds: Int?,
    matcherP95Microseconds: Int?,
    pipelineP95Microseconds: Int?,
    minimumHeldOutSamplesPerCohort: Int,
    matcherP95BudgetMicroseconds: Int,
    matcherP95BudgetMet: Bool,
    reliabilityBins: [MatcherReliabilityBin],
    gateStatus: MatcherCalibrationGateStatus,
    probabilityCalibrationStatus: MatcherProbabilityCalibrationStatus
  ) {
    self.schemaVersion = schemaVersion
    self.reportID = reportID
    self.scope = scope
    self.collectionMethod = collectionMethod
    self.traceCount = traceCount
    self.entryCount = entryCount
    self.matchedEntryCount = matchedEntryCount
    self.adapterRejectionCount = adapterRejectionCount
    self.matcherRejectionCount = matcherRejectionCount
    self.simulatedMatchedEntryCount = simulatedMatchedEntryCount
    self.annotatedEntryCount = annotatedEntryCount
    self.unannotatedMatchedEntryCount = unannotatedMatchedEntryCount
    self.unsafeHighConfidenceEdgeCount = unsafeHighConfidenceEdgeCount
    self.unsafeHighConfidenceOccurrenceCount = unsafeHighConfidenceOccurrenceCount
    self.adaptationP95Microseconds = adaptationP95Microseconds
    self.matcherP95Microseconds = matcherP95Microseconds
    self.pipelineP95Microseconds = pipelineP95Microseconds
    self.minimumHeldOutSamplesPerCohort =
      minimumHeldOutSamplesPerCohort
    self.matcherP95BudgetMicroseconds = matcherP95BudgetMicroseconds
    self.matcherP95BudgetMet = matcherP95BudgetMet
    self.reliabilityBins = reliabilityBins
    self.gateStatus = gateStatus
    self.probabilityCalibrationStatus = probabilityCalibrationStatus
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case reportID = "report_id"
    case scope
    case collectionMethod = "collection_method"
    case traceCount = "trace_count"
    case entryCount = "entry_count"
    case matchedEntryCount = "matched_entry_count"
    case adapterRejectionCount = "adapter_rejection_count"
    case matcherRejectionCount = "matcher_rejection_count"
    case simulatedMatchedEntryCount = "simulated_matched_entry_count"
    case annotatedEntryCount = "annotated_entry_count"
    case unannotatedMatchedEntryCount = "unannotated_matched_entry_count"
    case unsafeHighConfidenceEdgeCount = "unsafe_high_confidence_edge_count"
    case unsafeHighConfidenceOccurrenceCount = "unsafe_high_confidence_occurrence_count"
    case adaptationP95Microseconds = "adaptation_p95_us"
    case matcherP95Microseconds = "matcher_p95_us"
    case pipelineP95Microseconds = "pipeline_p95_us"
    case minimumHeldOutSamplesPerCohort =
      "minimum_held_out_samples_per_cohort"
    case matcherP95BudgetMicroseconds = "matcher_p95_budget_us"
    case matcherP95BudgetMet = "matcher_p95_budget_met"
    case reliabilityBins = "reliability_bins"
    case gateStatus = "gate_status"
    case probabilityCalibrationStatus = "probability_calibration_status"
  }
}
