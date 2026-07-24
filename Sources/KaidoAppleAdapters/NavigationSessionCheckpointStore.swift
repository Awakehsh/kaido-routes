import Foundation
import KaidoNavigation

public enum NavigationSessionCheckpointStoreError:
  Error, Equatable, Sendable
{
  case invalidPathComponent
  case applicationSupportUnavailable
  case directoryCreationFailed
  case readFailed
  case writeFailed
  case removalFailed

  public var code: String {
    switch self {
    case .invalidPathComponent:
      "CHECKPOINT_STORE_PATH_INVALID"
    case .applicationSupportUnavailable:
      "CHECKPOINT_STORE_APPLICATION_SUPPORT_UNAVAILABLE"
    case .directoryCreationFailed:
      "CHECKPOINT_STORE_DIRECTORY_CREATION_FAILED"
    case .readFailed:
      "CHECKPOINT_STORE_READ_FAILED"
    case .writeFailed:
      "CHECKPOINT_STORE_WRITE_FAILED"
    case .removalFailed:
      "CHECKPOINT_STORE_REMOVAL_FAILED"
    }
  }
}

/// Storage stays outside navigation authority.
///
/// Implementations persist only the coordinate-free, release-bound checkpoint.
/// Decoding and runtime restoration still revalidate every identity.
@MainActor
public protocol NavigationSessionCheckpointStoring: AnyObject {
  func load() throws -> NavigationSessionCheckpoint?
  func save(_ checkpoint: NavigationSessionCheckpoint) throws
  func remove() throws
}

/// One atomically replaced active-session checkpoint in Application Support.
@MainActor
public final class FileNavigationSessionCheckpointStore:
  NavigationSessionCheckpointStoring
{
  public static let defaultDirectoryName = "KaidoRoutes"
  public static let defaultFileName = "active-navigation-checkpoint.json"

  public let directoryURL: URL
  public let fileURL: URL

  private let fileManager: FileManager

  public init(
    directoryURL: URL,
    fileName: String = defaultFileName,
    fileManager: FileManager = .default
  ) throws {
    guard
      Self.isPathComponent(fileName),
      directoryURL.isFileURL
    else {
      throw NavigationSessionCheckpointStoreError.invalidPathComponent
    }
    self.directoryURL = directoryURL
    fileURL = directoryURL.appendingPathComponent(
      fileName,
      isDirectory: false
    )
    self.fileManager = fileManager
  }

  public static func applicationSupport(
    directoryName: String = defaultDirectoryName,
    fileName: String = defaultFileName,
    fileManager: FileManager = .default
  ) throws -> FileNavigationSessionCheckpointStore {
    guard isPathComponent(directoryName) else {
      throw NavigationSessionCheckpointStoreError.invalidPathComponent
    }
    guard
      let baseURL = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw NavigationSessionCheckpointStoreError
        .applicationSupportUnavailable
    }
    return try FileNavigationSessionCheckpointStore(
      directoryURL: baseURL.appendingPathComponent(
        directoryName,
        isDirectory: true
      ),
      fileName: fileName,
      fileManager: fileManager
    )
  }

  public func load() throws -> NavigationSessionCheckpoint? {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return nil
    }
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      throw NavigationSessionCheckpointStoreError.readFailed
    }
    return try NavigationSessionCheckpointCodec.decode(data)
  }

  public func save(_ checkpoint: NavigationSessionCheckpoint) throws {
    do {
      try fileManager.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true
      )
    } catch {
      throw NavigationSessionCheckpointStoreError
        .directoryCreationFailed
    }
    let data = try NavigationSessionCheckpointCodec.encode(checkpoint)
    do {
      try data.write(to: fileURL, options: .atomic)
    } catch {
      throw NavigationSessionCheckpointStoreError.writeFailed
    }
  }

  public func remove() throws {
    guard fileManager.fileExists(atPath: fileURL.path) else { return }
    do {
      try fileManager.removeItem(at: fileURL)
    } catch {
      throw NavigationSessionCheckpointStoreError.removalFailed
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
