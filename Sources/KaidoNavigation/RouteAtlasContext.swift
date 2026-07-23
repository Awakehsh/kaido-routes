import Foundation

/// The only releasable authority role for full-network geographic context.
///
/// `navigationAuthority` is intentionally decodable so malformed or promoted
/// artifacts can be rejected with an explicit issue instead of failing before
/// the evidence boundary can report why.
public enum RouteAtlasContextNavigationRole: String, Codable, Sendable {
  case contextOnly = "CONTEXT_ONLY"
  case navigationAuthority = "NAVIGATION_AUTHORITY"
}

public enum RouteAtlasContextUsageScope: String, Codable, Sendable {
  case currentStateOnly = "CURRENT_STATE_ONLY"
}

public enum RouteAtlasContextProjectionKind: String, Codable, Sendable {
  case localEquirectangular = "LOCAL_EQUIRECTANGULAR"
}

public enum RouteAtlasContextCoordinateSpace: String, Codable, Sendable {
  case normalizedUnitSquare = "NORMALIZED_UNIT_SQUARE"
}

public enum RouteAtlasContextSourceCRS: String, Codable, Sendable {
  case wgs84 = "EPSG:4326"
  case jgd2011 = "EPSG:6668"
}

public enum RouteAtlasContextUseStatus: String, Codable, Sendable {
  case complete = "COMPLETE"
  case provisional = "PROVISIONAL"
}

/// Reviewable provenance for one independently distributed context source.
///
/// The source checksum binds a generated context artifact to the exact archive
/// used to construct it. The raw archive remains outside the repository.
public struct RouteAtlasContextSource: Codable, Equatable, Sendable {
  public let sourceReferenceID: String
  public let authorityName: String
  public let sourcePageURL: String
  public let downloadURL: String
  public let archiveSHA256: String
  public let sourceCRS: RouteAtlasContextSourceCRS
  public let datasetReferenceDate: String
  public let retrievedAt: String
  public let checkedAt: String
  public let licenceIdentifier: String
  public let usageScope: RouteAtlasContextUsageScope
  public let attribution: String
  public let transformationDisclosure: String

  public init(
    sourceReferenceID: String,
    authorityName: String,
    sourcePageURL: String,
    downloadURL: String,
    archiveSHA256: String,
    sourceCRS: RouteAtlasContextSourceCRS,
    datasetReferenceDate: String,
    retrievedAt: String,
    checkedAt: String,
    licenceIdentifier: String,
    usageScope: RouteAtlasContextUsageScope,
    attribution: String,
    transformationDisclosure: String
  ) {
    self.sourceReferenceID = sourceReferenceID
    self.authorityName = authorityName
    self.sourcePageURL = sourcePageURL
    self.downloadURL = downloadURL
    self.archiveSHA256 = archiveSHA256
    self.sourceCRS = sourceCRS
    self.datasetReferenceDate = datasetReferenceDate
    self.retrievedAt = retrievedAt
    self.checkedAt = checkedAt
    self.licenceIdentifier = licenceIdentifier
    self.usageScope = usageScope
    self.attribution = attribution
    self.transformationDisclosure = transformationDisclosure
  }

  enum CodingKeys: String, CodingKey {
    case sourceReferenceID = "source_reference_id"
    case authorityName = "authority_name"
    case sourcePageURL = "source_page_url"
    case downloadURL = "download_url"
    case archiveSHA256 = "archive_sha256"
    case sourceCRS = "source_crs"
    case datasetReferenceDate = "dataset_reference_date"
    case retrievedAt = "retrieved_at"
    case checkedAt = "checked_at"
    case licenceIdentifier = "licence_identifier"
    case usageScope = "usage_scope"
    case attribution
    case transformationDisclosure = "transformation_disclosure"
  }
}

/// Projection metadata preserves north-up orientation and aspect ratio while
/// keeping third-party geographic coordinates out of navigation semantics.
public struct RouteAtlasContextProjection: Codable, Equatable, Sendable {
  public let kind: RouteAtlasContextProjectionKind
  public let northUp: Bool
  public let sourceCRS: RouteAtlasContextSourceCRS
  public let coordinateSpace: RouteAtlasContextCoordinateSpace
  public let minimumLongitude: Double
  public let maximumLongitude: Double
  public let minimumLatitude: Double
  public let maximumLatitude: Double

  public init(
    kind: RouteAtlasContextProjectionKind,
    northUp: Bool,
    sourceCRS: RouteAtlasContextSourceCRS,
    coordinateSpace: RouteAtlasContextCoordinateSpace,
    minimumLongitude: Double,
    maximumLongitude: Double,
    minimumLatitude: Double,
    maximumLatitude: Double
  ) {
    self.kind = kind
    self.northUp = northUp
    self.sourceCRS = sourceCRS
    self.coordinateSpace = coordinateSpace
    self.minimumLongitude = minimumLongitude
    self.maximumLongitude = maximumLongitude
    self.minimumLatitude = minimumLatitude
    self.maximumLatitude = maximumLatitude
  }

  enum CodingKeys: String, CodingKey {
    case kind
    case northUp = "north_up"
    case sourceCRS = "source_crs"
    case coordinateSpace = "coordinate_space"
    case minimumLongitude = "minimum_longitude"
    case maximumLongitude = "maximum_longitude"
    case minimumLatitude = "minimum_latitude"
    case maximumLatitude = "maximum_latitude"
  }
}

public struct RouteAtlasContextCoverage: Codable, Equatable, Sendable {
  public let sourceFeatureCount: Int
  public let pathCount: Int
  public let vertexCount: Int
  public let routeNameCount: Int

  public init(
    sourceFeatureCount: Int,
    pathCount: Int,
    vertexCount: Int,
    routeNameCount: Int
  ) {
    self.sourceFeatureCount = sourceFeatureCount
    self.pathCount = pathCount
    self.vertexCount = vertexCount
    self.routeNameCount = routeNameCount
  }

  enum CodingKeys: String, CodingKey {
    case sourceFeatureCount = "source_feature_count"
    case pathCount = "path_count"
    case vertexCount = "vertex_count"
    case routeNameCount = "route_name_count"
  }
}

public struct RouteAtlasContextPoint: Codable, Equatable, Sendable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// A source-derived visual path with no successor, direction, or occurrence
/// semantics. It must never be used as a selectable route edge.
public struct RouteAtlasContextPath: Codable, Equatable, Sendable {
  public let id: String
  public let sourceFeatureID: String
  public let sourceRecordID: String
  public let sourcePartIndex: Int
  public let routeNameJA: String
  public let useStatus: RouteAtlasContextUseStatus
  public let points: [RouteAtlasContextPoint]

  public init(
    id: String,
    sourceFeatureID: String,
    sourceRecordID: String,
    sourcePartIndex: Int,
    routeNameJA: String,
    useStatus: RouteAtlasContextUseStatus,
    points: [RouteAtlasContextPoint]
  ) {
    self.id = id
    self.sourceFeatureID = sourceFeatureID
    self.sourceRecordID = sourceRecordID
    self.sourcePartIndex = sourcePartIndex
    self.routeNameJA = routeNameJA
    self.useStatus = useStatus
    self.points = points
  }

  enum CodingKeys: String, CodingKey {
    case id = "path_id"
    case sourceFeatureID = "source_feature_id"
    case sourceRecordID = "source_record_id"
    case sourcePartIndex = "source_part_index"
    case routeNameJA = "route_name_ja"
    case useStatus = "use_status"
    case points
  }
}

/// A renderer-neutral, non-interactive full-network geographic context layer.
public struct RouteAtlasContextDefinition: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let id: String
  public let navigationRole: RouteAtlasContextNavigationRole
  public let sourceReferenceID: String
  public let projection: RouteAtlasContextProjection
  public let coverage: RouteAtlasContextCoverage
  public let paths: [RouteAtlasContextPath]

  public init(
    schemaVersion: String,
    id: String,
    navigationRole: RouteAtlasContextNavigationRole,
    sourceReferenceID: String,
    projection: RouteAtlasContextProjection,
    coverage: RouteAtlasContextCoverage,
    paths: [RouteAtlasContextPath]
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.navigationRole = navigationRole
    self.sourceReferenceID = sourceReferenceID
    self.projection = projection
    self.coverage = coverage
    self.paths = paths
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case id = "context_id"
    case navigationRole = "navigation_role"
    case sourceReferenceID = "source_reference_id"
    case projection
    case coverage
    case paths
  }
}

public enum RouteAtlasContextIssue: Equatable, Sendable {
  case invalidSchemaVersion
  case invalidContextIdentity
  case contextRoleMismatch
  case sourceReferenceMismatch
  case invalidSourceIdentity
  case invalidSourceURL
  case invalidSourceArchiveChecksum
  case sourceCRSMismatch
  case invalidSourceDate
  case unsupportedSourceLicence
  case unsupportedSourceUsageScope
  case missingSourceAttribution
  case missingTransformationDisclosure
  case invalidProjection
  case invalidCoverage
  case duplicatePathID(String)
  case duplicateSourcePart(String)
  case invalidContextPath(String)
  case invalidContextPoint(String)
  case sourceFeatureCountMismatch
  case pathCountMismatch
  case vertexCountMismatch
  case routeNameCountMismatch

  public var code: String {
    switch self {
    case .invalidSchemaVersion:
      "INVALID_CONTEXT_SCHEMA_VERSION"
    case .invalidContextIdentity:
      "INVALID_CONTEXT_IDENTITY"
    case .contextRoleMismatch:
      "CONTEXT_ROLE_MISMATCH"
    case .sourceReferenceMismatch:
      "CONTEXT_SOURCE_REFERENCE_MISMATCH"
    case .invalidSourceIdentity:
      "INVALID_CONTEXT_SOURCE_IDENTITY"
    case .invalidSourceURL:
      "INVALID_CONTEXT_SOURCE_URL"
    case .invalidSourceArchiveChecksum:
      "INVALID_CONTEXT_SOURCE_ARCHIVE_CHECKSUM"
    case .sourceCRSMismatch:
      "CONTEXT_SOURCE_CRS_MISMATCH"
    case .invalidSourceDate:
      "INVALID_CONTEXT_SOURCE_DATE"
    case .unsupportedSourceLicence:
      "UNSUPPORTED_CONTEXT_SOURCE_LICENCE"
    case .unsupportedSourceUsageScope:
      "UNSUPPORTED_CONTEXT_SOURCE_USAGE_SCOPE"
    case .missingSourceAttribution:
      "MISSING_CONTEXT_SOURCE_ATTRIBUTION"
    case .missingTransformationDisclosure:
      "MISSING_CONTEXT_TRANSFORMATION_DISCLOSURE"
    case .invalidProjection:
      "INVALID_CONTEXT_PROJECTION"
    case .invalidCoverage:
      "INVALID_CONTEXT_COVERAGE"
    case .duplicatePathID:
      "DUPLICATE_CONTEXT_PATH_ID"
    case .duplicateSourcePart:
      "DUPLICATE_CONTEXT_SOURCE_PART"
    case .invalidContextPath:
      "INVALID_CONTEXT_PATH"
    case .invalidContextPoint:
      "INVALID_CONTEXT_POINT"
    case .sourceFeatureCountMismatch:
      "CONTEXT_SOURCE_FEATURE_COUNT_MISMATCH"
    case .pathCountMismatch:
      "CONTEXT_PATH_COUNT_MISMATCH"
    case .vertexCountMismatch:
      "CONTEXT_VERTEX_COUNT_MISMATCH"
    case .routeNameCountMismatch:
      "CONTEXT_ROUTE_NAME_COUNT_MISMATCH"
    }
  }

  fileprivate var sortKey: String {
    switch self {
    case .duplicatePathID(let id),
      .duplicateSourcePart(let id),
      .invalidContextPath(let id),
      .invalidContextPoint(let id):
      "\(code):\(id)"
    default:
      code
    }
  }
}

public enum RouteAtlasContextError: Error, Equatable, Sendable {
  case invalid([RouteAtlasContextIssue])
}

/// A validated context bundle proves provenance and structural integrity only.
///
/// It does not prove direction, legal movement, current traffic state, or
/// eligibility for RoutePlan selection and highlighting.
public struct RouteAtlasContextBundle: Equatable, Sendable {
  public let source: RouteAtlasContextSource
  public let definition: RouteAtlasContextDefinition

  public init(
    source: RouteAtlasContextSource,
    definition: RouteAtlasContextDefinition
  ) throws {
    let issues = Self.validationIssues(source: source, definition: definition)
    guard issues.isEmpty else {
      throw RouteAtlasContextError.invalid(issues)
    }
    self.source = source
    self.definition = definition
  }

  public static func validationIssues(
    source: RouteAtlasContextSource,
    definition: RouteAtlasContextDefinition
  ) -> [RouteAtlasContextIssue] {
    var issues: [RouteAtlasContextIssue] = []

    if definition.schemaVersion != "1.0" {
      issues.append(.invalidSchemaVersion)
    }
    if normalized(definition.id).isEmpty {
      issues.append(.invalidContextIdentity)
    }
    if definition.navigationRole != .contextOnly {
      issues.append(.contextRoleMismatch)
    }

    if normalized(source.sourceReferenceID).isEmpty
      || normalized(source.authorityName).isEmpty
    {
      issues.append(.invalidSourceIdentity)
    }
    if definition.sourceReferenceID != source.sourceReferenceID {
      issues.append(.sourceReferenceMismatch)
    }
    if !isHTTPSURL(source.sourcePageURL) || !isHTTPSURL(source.downloadURL) {
      issues.append(.invalidSourceURL)
    }
    if !isSHA256(source.archiveSHA256) {
      issues.append(.invalidSourceArchiveChecksum)
    }
    if !isISODate(source.datasetReferenceDate)
      || !isISODate(source.retrievedAt)
      || !isISODate(source.checkedAt)
      || source.datasetReferenceDate > source.retrievedAt
      || source.retrievedAt > source.checkedAt
    {
      issues.append(.invalidSourceDate)
    }
    if source.licenceIdentifier != "CC-BY-4.0" {
      issues.append(.unsupportedSourceLicence)
    }
    if source.usageScope != .currentStateOnly {
      issues.append(.unsupportedSourceUsageScope)
    }
    if normalized(source.attribution).isEmpty {
      issues.append(.missingSourceAttribution)
    }
    if normalized(source.transformationDisclosure).isEmpty {
      issues.append(.missingTransformationDisclosure)
    }

    let projection = definition.projection
    if projection.sourceCRS != source.sourceCRS {
      issues.append(.sourceCRSMismatch)
    }
    if projection.kind != .localEquirectangular
      || !projection.northUp
      || projection.coordinateSpace != .normalizedUnitSquare
      || !projection.minimumLongitude.isFinite
      || !projection.maximumLongitude.isFinite
      || !projection.minimumLatitude.isFinite
      || !projection.maximumLatitude.isFinite
      || projection.minimumLongitude >= projection.maximumLongitude
      || projection.minimumLatitude >= projection.maximumLatitude
      || projection.minimumLongitude < -180
      || projection.maximumLongitude > 180
      || projection.minimumLatitude < -90
      || projection.maximumLatitude > 90
    {
      issues.append(.invalidProjection)
    }

    let coverage = definition.coverage
    if coverage.sourceFeatureCount <= 0
      || coverage.pathCount <= 0
      || coverage.vertexCount <= 0
      || coverage.routeNameCount <= 0
    {
      issues.append(.invalidCoverage)
    }

    var pathIDs: Set<String> = []
    var sourceParts: Set<String> = []
    var sourceFeatureIDs: Set<String> = []
    var routeNames: Set<String> = []
    var vertexCount = 0

    for path in definition.paths {
      if !pathIDs.insert(path.id).inserted {
        issues.append(.duplicatePathID(path.id))
      }
      let sourcePartID = "\(path.sourceFeatureID)#\(path.sourcePartIndex)"
      if !sourceParts.insert(sourcePartID).inserted {
        issues.append(.duplicateSourcePart(sourcePartID))
      }
      if normalized(path.id).isEmpty
        || normalized(path.sourceFeatureID).isEmpty
        || normalized(path.sourceRecordID).isEmpty
        || path.sourcePartIndex < 0
        || normalized(path.routeNameJA).isEmpty
        || path.points.count < 2
      {
        issues.append(.invalidContextPath(path.id))
      }
      if path.points.contains(where: { !pointIsValid($0) }) {
        issues.append(.invalidContextPoint(path.id))
      }
      sourceFeatureIDs.insert(path.sourceFeatureID)
      routeNames.insert(path.routeNameJA)
      vertexCount += path.points.count
    }

    if coverage.sourceFeatureCount != sourceFeatureIDs.count {
      issues.append(.sourceFeatureCountMismatch)
    }
    if coverage.pathCount != definition.paths.count {
      issues.append(.pathCountMismatch)
    }
    if coverage.vertexCount != vertexCount {
      issues.append(.vertexCountMismatch)
    }
    if coverage.routeNameCount != routeNames.count {
      issues.append(.routeNameCountMismatch)
    }

    return issues.sorted { $0.sortKey < $1.sortKey }
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func pointIsValid(_ point: RouteAtlasContextPoint) -> Bool {
    point.x.isFinite && point.y.isFinite
      && (0...1).contains(point.x)
      && (0...1).contains(point.y)
  }

  private static func isHTTPSURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value) else {
      return false
    }
    return components.scheme == "https" && !(components.host ?? "").isEmpty
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64
      && value.utf8.allSatisfy { byte in
        (48...57).contains(byte)
          || (65...70).contains(byte)
          || (97...102).contains(byte)
      }
  }

  private static func isISODate(_ value: String) -> Bool {
    guard value.count == 10 else { return false }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    return formatter.date(from: value) != nil
  }
}
