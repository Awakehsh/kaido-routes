import KaidoDomain
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  static let kaidoRoute = UTType(exportedAs: "app.kaidoroutes.route", conformingTo: .json)
}

/// A user-selected file boundary for one complete SharedRouteDocument.
///
/// This type validates bytes but owns no saved-library or navigation state.
struct SharedRouteFileDocument: FileDocument {
  static let readableContentTypes: [UTType] = [.kaidoRoute, .json]

  let data: Data

  static func exportFileName(_ displayName: String) -> String {
    let disallowed = CharacterSet.alphanumerics.union(.whitespaces)
      .union(CharacterSet(charactersIn: "-_")).inverted
    let cleaned = displayName.components(separatedBy: disallowed).joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "kaido-route" : String(cleaned.prefix(48))
  }

  init(data: Data) throws {
    _ = try SharedRouteCodec.decode(data)
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    guard
      let data = configuration.file.regularFileContents
    else {
      throw CocoaError(.fileReadCorruptFile)
    }
    _ = try SharedRouteCodec.decode(data)
    self.data = data
  }

  func fileWrapper(
    configuration _: WriteConfiguration
  ) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
