import KaidoDomain
import SwiftUI
import UniformTypeIdentifiers

/// A user-selected file boundary for one complete SharedRouteDocument.
///
/// This type validates bytes but owns no saved-library or navigation state.
struct SharedRouteFileDocument: FileDocument {
  static let readableContentTypes: [UTType] = [.json]

  let data: Data

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
