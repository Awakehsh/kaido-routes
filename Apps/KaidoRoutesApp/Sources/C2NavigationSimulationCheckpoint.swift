import Foundation
import KaidoSurfaceRouting

struct C2NavigationSimulationCheckpoint: Codable, Equatable, Sendable {
  static let currentSchemaVersion = "1.0"
  static let routeDatabaseID =
    "kaido.c2-b-geographic-route.2026-07-29"

  let schemaVersion: String
  let routeDatabaseID: String
  let originQuery: String
  let destinationQuery: String
  let origin: C2NavigationResolvedPlace
  let destination: C2NavigationResolvedPlace
  let accessRoute: SurfaceRouteCandidate
  let egressRoute: SurfaceRouteCandidate
  let phase: C2NavigationDemoPhase
  let surfaceProgressFraction: Double
  let surfaceStepIndex: Int
  let expresswayOccurrenceIndex: Int
  let expresswayOccurrenceFraction: Double
  let transitionTick: Int

  init(
    schemaVersion: String = currentSchemaVersion,
    routeDatabaseID: String = C2NavigationSimulationCheckpoint.routeDatabaseID,
    originQuery: String,
    destinationQuery: String,
    origin: C2NavigationResolvedPlace,
    destination: C2NavigationResolvedPlace,
    accessRoute: SurfaceRouteCandidate,
    egressRoute: SurfaceRouteCandidate,
    phase: C2NavigationDemoPhase,
    surfaceProgressFraction: Double,
    surfaceStepIndex: Int,
    expresswayOccurrenceIndex: Int,
    expresswayOccurrenceFraction: Double,
    transitionTick: Int
  ) {
    self.schemaVersion = schemaVersion
    self.routeDatabaseID = routeDatabaseID
    self.originQuery = originQuery
    self.destinationQuery = destinationQuery
    self.origin = origin
    self.destination = destination
    self.accessRoute = accessRoute
    self.egressRoute = egressRoute
    self.phase = phase
    self.surfaceProgressFraction = surfaceProgressFraction
    self.surfaceStepIndex = surfaceStepIndex
    self.expresswayOccurrenceIndex = expresswayOccurrenceIndex
    self.expresswayOccurrenceFraction = expresswayOccurrenceFraction
    self.transitionTick = transitionTick
  }

  var isValid: Bool {
    guard
      schemaVersion == Self.currentSchemaVersion,
      routeDatabaseID == Self.routeDatabaseID,
      Self.activePhases.contains(phase),
      !origin.title.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty,
      !destination.title.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty,
      origin.coordinate.isValid,
      destination.coordinate.isValid,
      Self.validRoute(accessRoute),
      Self.validRoute(egressRoute),
      (0...1).contains(surfaceProgressFraction),
      surfaceStepIndex >= 0,
      (0..<C2CompletedRouteDemo.occurrenceCount)
        .contains(expresswayOccurrenceIndex),
      (0...1).contains(expresswayOccurrenceFraction),
      (0...1).contains(transitionTick),
      Self.distance(
        accessRoute.coordinates.last,
        C2NavigationDemoModel.tomigayaEntranceCoordinate
      ) <= 150,
      Self.distance(
        egressRoute.coordinates.first,
        C2NavigationDemoModel.hatsudaiMinamiExitCoordinate
      ) <= 150
    else {
      return false
    }

    let activeStepCount =
      switch phase {
      case .surfaceAccess, .entryTransition:
        accessRoute.steps.count
      case .exitTransition, .surfaceEgress:
        egressRoute.steps.count
      case .expressway:
        max(accessRoute.steps.count, egressRoute.steps.count)
      case .planning, .routing, .review, .completed, .failed:
        0
      }
    return surfaceStepIndex < max(1, activeStepCount)
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case routeDatabaseID = "route_database_id"
    case originQuery = "origin_query"
    case destinationQuery = "destination_query"
    case origin
    case destination
    case accessRoute = "access_route"
    case egressRoute = "egress_route"
    case phase
    case surfaceProgressFraction = "surface_progress_fraction"
    case surfaceStepIndex = "surface_step_index"
    case expresswayOccurrenceIndex = "expressway_occurrence_index"
    case expresswayOccurrenceFraction =
      "expressway_occurrence_fraction"
    case transitionTick = "transition_tick"
  }

  private static let activePhases: Set<C2NavigationDemoPhase> = [
    .surfaceAccess,
    .entryTransition,
    .expressway,
    .exitTransition,
    .surfaceEgress,
  ]

  private static func validRoute(
    _ route: SurfaceRouteCandidate
  ) -> Bool {
    !route.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !route.providerID.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
      && route.coordinates.count >= 2
      && route.coordinates.allSatisfy(\.isValid)
      && !route.steps.isEmpty
      && route.distanceMeters.isFinite
      && route.distanceMeters >= 0
      && route.expectedTravelTimeSeconds.isFinite
      && route.expectedTravelTimeSeconds >= 0
      && route.hasHighways != true
      && route.hasTolls != true
  }

  private static func distance(
    _ first: SurfaceCoordinate?,
    _ second: SurfaceCoordinate
  ) -> Double {
    guard let first else { return .infinity }
    let radius = 6_371_000.0
    let latitude1 = first.latitude * .pi / 180
    let longitude1 = first.longitude * .pi / 180
    let latitude2 = second.latitude * .pi / 180
    let longitude2 = second.longitude * .pi / 180
    let deltaLatitude = latitude2 - latitude1
    let deltaLongitude = longitude2 - longitude1
    let value =
      pow(sin(deltaLatitude / 2), 2)
      + cos(latitude1) * cos(latitude2)
      * pow(sin(deltaLongitude / 2), 2)
    return 2 * radius * asin(sqrt(value))
  }
}

enum C2NavigationSimulationCheckpointStoreError:
  Error, Equatable, Sendable
{
  case invalidPath
  case applicationSupportUnavailable
  case directoryCreationFailed
  case readFailed
  case decodeFailed
  case invalidCheckpoint
  case writeFailed
  case removalFailed

  var code: String {
    switch self {
    case .invalidPath:
      "C2_CHECKPOINT_PATH_INVALID"
    case .applicationSupportUnavailable:
      "C2_CHECKPOINT_APPLICATION_SUPPORT_UNAVAILABLE"
    case .directoryCreationFailed:
      "C2_CHECKPOINT_DIRECTORY_CREATION_FAILED"
    case .readFailed:
      "C2_CHECKPOINT_READ_FAILED"
    case .decodeFailed:
      "C2_CHECKPOINT_DECODE_FAILED"
    case .invalidCheckpoint:
      "C2_CHECKPOINT_INVALID"
    case .writeFailed:
      "C2_CHECKPOINT_WRITE_FAILED"
    case .removalFailed:
      "C2_CHECKPOINT_REMOVAL_FAILED"
    }
  }
}

@MainActor
protocol C2NavigationSimulationCheckpointStoring: AnyObject {
  func load() throws -> C2NavigationSimulationCheckpoint?
  func save(_ checkpoint: C2NavigationSimulationCheckpoint) throws
  func remove() throws
}

@MainActor
final class FileC2NavigationSimulationCheckpointStore:
  C2NavigationSimulationCheckpointStoring
{
  static let defaultDirectoryName = "KaidoRoutes"
  static let defaultFileName =
    "c2-navigation-simulation-checkpoint.json"

  let directoryURL: URL
  let fileURL: URL

  private let fileManager: FileManager

  init(
    directoryURL: URL,
    fileName: String = defaultFileName,
    fileManager: FileManager = .default
  ) throws {
    guard
      directoryURL.isFileURL,
      Self.isPathComponent(fileName)
    else {
      throw C2NavigationSimulationCheckpointStoreError.invalidPath
    }
    self.directoryURL = directoryURL
    fileURL = directoryURL.appendingPathComponent(
      fileName,
      isDirectory: false
    )
    self.fileManager = fileManager
  }

  static func applicationSupport(
    directoryName: String = defaultDirectoryName,
    fileName: String = defaultFileName,
    fileManager: FileManager = .default
  ) throws -> FileC2NavigationSimulationCheckpointStore {
    guard Self.isPathComponent(directoryName) else {
      throw C2NavigationSimulationCheckpointStoreError.invalidPath
    }
    guard
      let baseURL = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw
        C2NavigationSimulationCheckpointStoreError
        .applicationSupportUnavailable
    }
    return try FileC2NavigationSimulationCheckpointStore(
      directoryURL: baseURL.appendingPathComponent(
        directoryName,
        isDirectory: true
      ),
      fileName: fileName,
      fileManager: fileManager
    )
  }

  func load() throws -> C2NavigationSimulationCheckpoint? {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return nil
    }
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      throw C2NavigationSimulationCheckpointStoreError.readFailed
    }
    let checkpoint: C2NavigationSimulationCheckpoint
    do {
      checkpoint = try JSONDecoder().decode(
        C2NavigationSimulationCheckpoint.self,
        from: data
      )
    } catch {
      throw C2NavigationSimulationCheckpointStoreError.decodeFailed
    }
    guard checkpoint.isValid else {
      throw C2NavigationSimulationCheckpointStoreError.invalidCheckpoint
    }
    return checkpoint
  }

  func save(
    _ checkpoint: C2NavigationSimulationCheckpoint
  ) throws {
    guard checkpoint.isValid else {
      throw C2NavigationSimulationCheckpointStoreError.invalidCheckpoint
    }
    do {
      try fileManager.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true
      )
    } catch {
      throw
        C2NavigationSimulationCheckpointStoreError
        .directoryCreationFailed
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data: Data
    do {
      data = try encoder.encode(checkpoint)
    } catch {
      throw C2NavigationSimulationCheckpointStoreError.writeFailed
    }
    do {
      try data.write(to: fileURL, options: .atomic)
    } catch {
      throw C2NavigationSimulationCheckpointStoreError.writeFailed
    }
  }

  func remove() throws {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return
    }
    do {
      try fileManager.removeItem(at: fileURL)
    } catch {
      throw C2NavigationSimulationCheckpointStoreError.removalFailed
    }
  }

  private static func isPathComponent(_ value: String) -> Bool {
    let normalized = value.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    return !normalized.isEmpty
      && normalized != "."
      && normalized != ".."
      && !normalized.contains("/")
      && !normalized.contains("\\")
  }
}
