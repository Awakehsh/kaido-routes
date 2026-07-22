import Foundation

public enum MatcherFieldTransportContext: String, Codable, Hashable, Sendable {
  case phoneOnly = "PHONE_ONLY"
  case carPlayConnectedTransportUnknown = "CARPLAY_CONNECTED_TRANSPORT_UNKNOWN"
  case fieldDeclaredWiredCarPlay = "FIELD_DECLARED_WIRED_CARPLAY"
  case fieldDeclaredWirelessCarPlay = "FIELD_DECLARED_WIRELESS_CARPLAY"
}

public enum MatcherTraceCollectionMethod: String, Codable, Sendable {
  case automatedLogger = "AUTOMATED_LOGGER"
  case passengerObserved = "PASSENGER_OBSERVED"
  case syntheticTest = "SYNTHETIC_TEST"
}

public enum MatcherTracePrivacyClassification: String, Codable, Sendable {
  case privateRawLocation = "PRIVATE_RAW_LOCATION"
}

public struct MatcherCalibrationScope: Codable, Equatable, Sendable {
  public let networkSnapshotID: String
  public let matcherAlgorithmID: String
  public let matcherConfigurationID: String
  public let deviceConfigurationID: String
  public let fieldTransportContext: MatcherFieldTransportContext

  public init(
    networkSnapshotID: String,
    matcherAlgorithmID: String,
    matcherConfigurationID: String,
    deviceConfigurationID: String,
    fieldTransportContext: MatcherFieldTransportContext
  ) {
    self.networkSnapshotID = networkSnapshotID
    self.matcherAlgorithmID = matcherAlgorithmID
    self.matcherConfigurationID = matcherConfigurationID
    self.deviceConfigurationID = deviceConfigurationID
    self.fieldTransportContext = fieldTransportContext
  }

  var validationIssues: [String] {
    var issues: [String] = []
    if networkSnapshotID.isEmpty { issues.append("network snapshot id is empty") }
    if matcherAlgorithmID.isEmpty { issues.append("matcher algorithm id is empty") }
    if matcherConfigurationID.isEmpty { issues.append("matcher configuration id is empty") }
    if deviceConfigurationID.isEmpty { issues.append("device configuration id is empty") }
    return issues
  }

  private enum CodingKeys: String, CodingKey {
    case networkSnapshotID = "network_snapshot_id"
    case matcherAlgorithmID = "matcher_algorithm_id"
    case matcherConfigurationID = "matcher_configuration_id"
    case deviceConfigurationID = "device_configuration_id"
    case fieldTransportContext = "field_transport_context"
  }
}

/// Sensitive context retained only with the private raw trace.
public struct MatcherPrivateTraceContext: Codable, Equatable, Sendable {
  public let traceID: String
  public let scope: MatcherCalibrationScope
  public let routePlanID: String
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
    scope: MatcherCalibrationScope,
    routePlanID: String,
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
    self.routePlanID = routePlanID
    self.deviceModel = deviceModel
    self.operatingSystemVersion = operatingSystemVersion
    self.appBuild = appBuild
    self.mountDescription = mountDescription
    self.headUnitDescription = headUnitDescription
    self.collectionMethod = collectionMethod
    self.startedAtMilliseconds = startedAtMilliseconds
    self.privacyClassification = privacyClassification
  }

  var validationIssues: [String] {
    var issues = scope.validationIssues
    if traceID.isEmpty { issues.append("trace id is empty") }
    if routePlanID.isEmpty { issues.append("route plan id is empty") }
    if deviceModel.isEmpty { issues.append("device model is empty") }
    if operatingSystemVersion.isEmpty { issues.append("operating system version is empty") }
    if appBuild.isEmpty { issues.append("app build is empty") }
    if mountDescription.isEmpty { issues.append("mount description is empty") }
    if startedAtMilliseconds < 0 { issues.append("trace start time is negative") }
    return issues
  }

  private enum CodingKeys: String, CodingKey {
    case traceID = "trace_id"
    case scope
    case routePlanID = "route_plan_id"
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

public struct MatcherTraceSourceProvenance: Codable, Equatable, Sendable {
  public let calibrationCohort: MatcherLocationSource
  public let sourceInformationAvailable: Bool
  public let producedByExternalAccessory: Bool
  public let simulatedBySoftware: Bool
  public let fieldTransportContext: MatcherFieldTransportContext
  public let courseAccuracyDegrees: Double?
  public let speedAccuracyMetersPerSecond: Double?

  public init(
    calibrationCohort: MatcherLocationSource,
    sourceInformationAvailable: Bool,
    producedByExternalAccessory: Bool,
    simulatedBySoftware: Bool,
    fieldTransportContext: MatcherFieldTransportContext,
    courseAccuracyDegrees: Double? = nil,
    speedAccuracyMetersPerSecond: Double? = nil
  ) {
    self.calibrationCohort = calibrationCohort
    self.sourceInformationAvailable = sourceInformationAvailable
    self.producedByExternalAccessory = producedByExternalAccessory
    self.simulatedBySoftware = simulatedBySoftware
    self.fieldTransportContext = fieldTransportContext
    self.courseAccuracyDegrees = courseAccuracyDegrees
    self.speedAccuracyMetersPerSecond = speedAccuracyMetersPerSecond
  }

  private enum CodingKeys: String, CodingKey {
    case calibrationCohort = "calibration_cohort"
    case sourceInformationAvailable = "source_information_available"
    case producedByExternalAccessory = "produced_by_external_accessory"
    case simulatedBySoftware = "simulated_by_software"
    case fieldTransportContext = "field_transport_context"
    case courseAccuracyDegrees = "course_accuracy_degrees"
    case speedAccuracyMetersPerSecond = "speed_accuracy_meters_per_second"
  }
}

public enum MatcherPrivateTraceEntryStatus: String, Codable, Sendable {
  case matched = "MATCHED"
  case adapterRejected = "ADAPTER_REJECTED"
  case matcherRejected = "MATCHER_REJECTED"
}

/// One private field entry. Coordinates are intentionally present only here,
/// never in `MatcherCalibrationReport`.
public struct MatcherPrivateTraceEntry: Codable, Equatable, Sendable {
  public let observationID: String
  public let status: MatcherPrivateTraceEntryStatus
  public let observation: MatcherReplayObservation?
  public let provenance: MatcherTraceSourceProvenance?
  public let estimate: MatcherEstimate?
  public let adapterRejectionCode: String?
  public let matcherRejectionCode: String?
  public let adaptationDurationMicroseconds: Int
  public let matchingDurationMicroseconds: Int?

  public init(
    observationID: String,
    status: MatcherPrivateTraceEntryStatus,
    observation: MatcherReplayObservation? = nil,
    provenance: MatcherTraceSourceProvenance? = nil,
    estimate: MatcherEstimate? = nil,
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

  var validationIssues: [String] {
    var issues: [String] = []
    if observationID.isEmpty { issues.append("trace entry observation id is empty") }
    if adaptationDurationMicroseconds < 0 {
      issues.append("trace entry adaptation duration is negative")
    }
    if matchingDurationMicroseconds.map({ $0 < 0 }) == true {
      issues.append("trace entry matching duration is negative")
    }
    if let matchingDurationMicroseconds {
      let (_, overflow) = adaptationDurationMicroseconds.addingReportingOverflow(
        matchingDurationMicroseconds
      )
      if overflow { issues.append("trace entry pipeline duration overflows") }
    }
    if let observation {
      if observation.id != observationID {
        issues.append("trace entry observation id does not match observation")
      }
      if !observation.coordinate.isValid || !observation.horizontalAccuracyMeters.isFinite
        || observation.horizontalAccuracyMeters <= 0
        || observation.receivedAtMilliseconds < observation.observedAtMilliseconds
      {
        issues.append("trace entry observation is invalid")
      }
    }
    if let estimate, estimate.observationID != observationID {
      issues.append("trace entry observation id does not match estimate")
    }
    if let observation, let provenance,
      observation.source != provenance.calibrationCohort
    {
      issues.append("trace entry source does not match provenance cohort")
    }

    switch status {
    case .matched:
      if observation == nil || provenance == nil || estimate == nil
        || matchingDurationMicroseconds == nil
        || adapterRejectionCode != nil || matcherRejectionCode != nil
      {
        issues.append("matched trace entry has inconsistent fields")
      }
    case .adapterRejected:
      if observation != nil || provenance != nil || estimate != nil
        || adapterRejectionCode?.isEmpty != false || matcherRejectionCode != nil
        || matchingDurationMicroseconds != nil
      {
        issues.append("adapter-rejected trace entry has inconsistent fields")
      }
    case .matcherRejected:
      if observation == nil || provenance == nil || estimate != nil
        || adapterRejectionCode != nil || matcherRejectionCode?.isEmpty != false
        || matchingDurationMicroseconds == nil
      {
        issues.append("matcher-rejected trace entry has inconsistent fields")
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

public struct MatcherPrivateTrace: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let context: MatcherPrivateTraceContext
  public let entries: [MatcherPrivateTraceEntry]

  public init(
    schemaVersion: String = "1.0",
    context: MatcherPrivateTraceContext,
    entries: [MatcherPrivateTraceEntry]
  ) {
    self.schemaVersion = schemaVersion
    self.context = context
    self.entries = entries
  }

  public var validationIssues: [String] {
    var issues = context.validationIssues
    if schemaVersion != "1.0" { issues.append("unsupported private trace schema version") }
    if entries.isEmpty { issues.append("private trace has no entries") }
    let observationIDs = entries.map(\.observationID)
    if Set(observationIDs).count != observationIDs.count {
      issues.append("private trace observation ids are not unique")
    }
    for entry in entries {
      issues.append(contentsOf: entry.validationIssues)
      if let provenance = entry.provenance,
        provenance.fieldTransportContext != context.scope.fieldTransportContext
      {
        issues.append("trace entry field transport differs from calibration scope")
      }
    }
    return Array(Set(issues)).sorted()
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case context
    case entries
  }
}

public enum MatcherCalibrationPartition: String, Codable, Hashable, Sendable {
  case tuning = "TUNING"
  case heldOut = "HELD_OUT"
}

public struct MatcherGroundTruthAnnotation: Codable, Equatable, Sendable {
  public let observationID: String
  public let partition: MatcherCalibrationPartition
  public let directedEdgeID: String
  public let occurrenceID: String?

  public init(
    observationID: String,
    partition: MatcherCalibrationPartition,
    directedEdgeID: String,
    occurrenceID: String? = nil
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

public struct MatcherCalibrationEvaluatorConfiguration: Equatable, Sendable {
  public let minimumHeldOutSamplesPerCohort: Int
  public let matcherP95BudgetMicroseconds: Int

  public init(
    minimumHeldOutSamplesPerCohort: Int = 30,
    matcherP95BudgetMicroseconds: Int = 50_000
  ) {
    self.minimumHeldOutSamplesPerCohort = minimumHeldOutSamplesPerCohort
    self.matcherP95BudgetMicroseconds = matcherP95BudgetMicroseconds
  }

  var isValid: Bool {
    minimumHeldOutSamplesPerCohort > 0 && matcherP95BudgetMicroseconds > 0
  }
}

public enum MatcherCalibrationGateStatus: String, Codable, Sendable {
  case unsafeHighConfidenceObserved = "UNSAFE_HIGH_CONFIDENCE_OBSERVED"
  case syntheticEvidenceOnly = "SYNTHETIC_EVIDENCE_ONLY"
  case simulatedEvidencePresent = "SIMULATED_EVIDENCE_PRESENT"
  case insufficientHeldOutEvidence = "INSUFFICIENT_HELD_OUT_EVIDENCE"
  case statisticalFloorMet = "STATISTICAL_FLOOR_MET_NOT_RELEASE_APPROVAL"
}

public enum MatcherProbabilityCalibrationStatus: String, Codable, Sendable {
  case unavailableCategoricalConfidenceOnly = "UNAVAILABLE_CATEGORICAL_CONFIDENCE_ONLY"
}

public struct MatcherReliabilityBin: Codable, Equatable, Sendable {
  public let partition: MatcherCalibrationPartition
  public let calibrationCohort: MatcherLocationSource
  public let producedByExternalAccessory: Bool
  public let simulatedBySoftware: Bool
  public let confidence: MatcherConfidence
  public let annotatedEdgeCount: Int
  public let correctEdgeCount: Int
  public let wrongEdgeCount: Int
  public let abstainedEdgeCount: Int
  public let observedEdgeAccuracy: Double?
  public let occurrenceTruthCount: Int
  public let correctOccurrenceCount: Int

  public init(
    partition: MatcherCalibrationPartition,
    calibrationCohort: MatcherLocationSource,
    producedByExternalAccessory: Bool,
    simulatedBySoftware: Bool,
    confidence: MatcherConfidence,
    annotatedEdgeCount: Int,
    correctEdgeCount: Int,
    wrongEdgeCount: Int,
    abstainedEdgeCount: Int,
    observedEdgeAccuracy: Double?,
    occurrenceTruthCount: Int,
    correctOccurrenceCount: Int
  ) {
    self.partition = partition
    self.calibrationCohort = calibrationCohort
    self.producedByExternalAccessory = producedByExternalAccessory
    self.simulatedBySoftware = simulatedBySoftware
    self.confidence = confidence
    self.annotatedEdgeCount = annotatedEdgeCount
    self.correctEdgeCount = correctEdgeCount
    self.wrongEdgeCount = wrongEdgeCount
    self.abstainedEdgeCount = abstainedEdgeCount
    self.observedEdgeAccuracy = observedEdgeAccuracy
    self.occurrenceTruthCount = occurrenceTruthCount
    self.correctOccurrenceCount = correctOccurrenceCount
  }

  private enum CodingKeys: String, CodingKey {
    case partition
    case calibrationCohort = "calibration_cohort"
    case producedByExternalAccessory = "produced_by_external_accessory"
    case simulatedBySoftware = "simulated_by_software"
    case confidence
    case annotatedEdgeCount = "annotated_edge_count"
    case correctEdgeCount = "correct_edge_count"
    case wrongEdgeCount = "wrong_edge_count"
    case abstainedEdgeCount = "abstained_edge_count"
    case observedEdgeAccuracy = "observed_edge_accuracy"
    case occurrenceTruthCount = "occurrence_truth_count"
    case correctOccurrenceCount = "correct_occurrence_count"
  }
}

public struct MatcherCalibrationReport: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let reportID: String
  public let scope: MatcherCalibrationScope
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
  public let matcherP95BudgetMicroseconds: Int
  public let matcherP95BudgetMet: Bool
  public let reliabilityBins: [MatcherReliabilityBin]
  public let gateStatus: MatcherCalibrationGateStatus
  public let probabilityCalibrationStatus: MatcherProbabilityCalibrationStatus

  public init(
    schemaVersion: String = "1.0",
    reportID: String,
    scope: MatcherCalibrationScope,
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
    case matcherP95BudgetMicroseconds = "matcher_p95_budget_us"
    case matcherP95BudgetMet = "matcher_p95_budget_met"
    case reliabilityBins = "reliability_bins"
    case gateStatus = "gate_status"
    case probabilityCalibrationStatus = "probability_calibration_status"
  }
}
