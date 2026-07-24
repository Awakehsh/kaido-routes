import Foundation
import KaidoDomain

public enum SavedRouteLibraryStoreError: Error, Equatable, Sendable {
  case invalidPathComponent
  case applicationSupportUnavailable
  case directoryCreationFailed
  case readFailed
  case writeFailed

  public var code: String {
    switch self {
    case .invalidPathComponent:
      "SAVED_ROUTE_STORE_PATH_INVALID"
    case .applicationSupportUnavailable:
      "SAVED_ROUTE_STORE_APPLICATION_SUPPORT_UNAVAILABLE"
    case .directoryCreationFailed:
      "SAVED_ROUTE_STORE_DIRECTORY_CREATION_FAILED"
    case .readFailed:
      "SAVED_ROUTE_STORE_READ_FAILED"
    case .writeFailed:
      "SAVED_ROUTE_STORE_WRITE_FAILED"
    }
  }
}

/// Storage has no route or navigation authority.
///
/// Implementations persist complete validated library values. Reopening a
/// record still requires an exact current product release match.
@MainActor
public protocol SavedRouteLibraryStoring: AnyObject {
  func load() throws -> SavedRouteLibraryDocument?
  func save(_ library: SavedRouteLibraryDocument) throws
}

/// One atomically replaced saved-route library in Application Support.
@MainActor
public final class FileSavedRouteLibraryStore:
  SavedRouteLibraryStoring
{
  public static let defaultDirectoryName = "KaidoRoutes"
  public static let defaultFileName = "saved-route-library.json"

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
      throw SavedRouteLibraryStoreError.invalidPathComponent
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
  ) throws -> FileSavedRouteLibraryStore {
    guard isPathComponent(directoryName) else {
      throw SavedRouteLibraryStoreError.invalidPathComponent
    }
    guard
      let baseURL = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw SavedRouteLibraryStoreError.applicationSupportUnavailable
    }
    return try FileSavedRouteLibraryStore(
      directoryURL: baseURL.appendingPathComponent(
        directoryName,
        isDirectory: true
      ),
      fileName: fileName,
      fileManager: fileManager
    )
  }

  public func load() throws -> SavedRouteLibraryDocument? {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return nil
    }
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      throw SavedRouteLibraryStoreError.readFailed
    }
    do {
      return try SavedRouteLibraryCodec.decode(data)
    } catch let error as SavedRouteLibraryCodecError {
      throw error
    } catch {
      throw SavedRouteLibraryStoreError.readFailed
    }
  }

  public func save(_ library: SavedRouteLibraryDocument) throws {
    let data = try SavedRouteLibraryCodec.encode(library)
    do {
      try fileManager.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true
      )
    } catch {
      throw SavedRouteLibraryStoreError.directoryCreationFailed
    }
    do {
      try data.write(to: fileURL, options: .atomic)
    } catch {
      throw SavedRouteLibraryStoreError.writeFailed
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
