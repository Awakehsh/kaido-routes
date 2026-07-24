import Combine
import CryptoKit
import Foundation
import KaidoAppleAdapters
import KaidoPresentation

enum PreDriveEvidenceUpdateModelError:
  String, Error, Equatable, Sendable
{
  case trustUnavailable = "PRE_DRIVE_EVIDENCE_UPDATE_TRUST_UNAVAILABLE"
  case storeUnavailable = "PRE_DRIVE_EVIDENCE_UPDATE_STORE_UNAVAILABLE"
  case importTooLarge = "PRE_DRIVE_EVIDENCE_UPDATE_IMPORT_TOO_LARGE"
  case importUnreadable = "PRE_DRIVE_EVIDENCE_UPDATE_IMPORT_UNREADABLE"
  case noTrustedProductMatch =
    "PRE_DRIVE_EVIDENCE_UPDATE_NO_TRUSTED_PRODUCT_MATCH"
  case ambiguousProductMatch =
    "PRE_DRIVE_EVIDENCE_UPDATE_PRODUCT_MATCH_AMBIGUOUS"
  case rollbackRejected = "PRE_DRIVE_EVIDENCE_UPDATE_ROLLBACK_REJECTED"
  case releaseIdentityReused =
    "PRE_DRIVE_EVIDENCE_UPDATE_RELEASE_IDENTITY_REUSED"
  case persistenceFailed = "PRE_DRIVE_EVIDENCE_UPDATE_PERSISTENCE_FAILED"
}

protocol PreDriveEvidenceUpdateStoring: AnyObject {
  func load(productReleaseID: String) throws -> Data?
  func save(_ data: Data, productReleaseID: String) throws
}

final class FilePreDriveEvidenceUpdateStore:
  PreDriveEvidenceUpdateStoring
{
  private let directoryURL: URL

  init(directoryURL: URL) {
    self.directoryURL = directoryURL.standardizedFileURL
  }

  static func applicationSupport(
    fileManager: FileManager = .default
  ) throws -> FilePreDriveEvidenceUpdateStore {
    let root = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return FilePreDriveEvidenceUpdateStore(
      directoryURL:
        root
        .appendingPathComponent(
          "KaidoRoutes",
          isDirectory: true
        )
        .appendingPathComponent(
          "PreDriveEvidenceUpdates",
          isDirectory: true
        )
    )
  }

  func load(productReleaseID: String) throws -> Data? {
    let url = fileURL(productReleaseID: productReleaseID)
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    let values = try url.resourceValues(
      forKeys: [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
      ]
    )
    guard
      values.isRegularFile == true,
      values.isSymbolicLink != true,
      let fileSize = values.fileSize,
      fileSize > 0,
      fileSize <= PreDriveEvidenceUpdateCodec.maximumEnvelopeByteCount
    else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return try Data(
      contentsOf: url,
      options: [.mappedIfSafe]
    )
  }

  func save(_ data: Data, productReleaseID: String) throws {
    guard
      !data.isEmpty,
      data.count <= PreDriveEvidenceUpdateCodec.maximumEnvelopeByteCount
    else {
      throw CocoaError(.fileWriteInapplicableStringEncoding)
    }
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    let resolvedDirectory = directoryURL.resolvingSymlinksInPath()
    guard resolvedDirectory == directoryURL else {
      throw CocoaError(.fileWriteNoPermission)
    }
    try data.write(
      to: fileURL(productReleaseID: productReleaseID),
      options: .atomic
    )
  }

  private func fileURL(productReleaseID: String) -> URL {
    let digest = SHA256.hash(data: Data(productReleaseID.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    return directoryURL.appendingPathComponent(
      "\(digest).json",
      isDirectory: false
    )
  }
}

enum PreDriveEvidenceUpdateModelState: Equatable, Sendable {
  case unavailable
  case ready
  case installed(productReleaseID: String, evidenceReleaseID: String)
  case blocked(String)

  var label: String {
    switch self {
    case .unavailable:
      "SIGNED UPDATE UNAVAILABLE"
    case .ready:
      "SIGNED UPDATE READY"
    case .installed:
      "SIGNED UPDATE INSTALLED"
    case .blocked:
      "SIGNED UPDATE BLOCKED"
    }
  }
}

/// Owns imported current-evidence updates without changing release authority.
///
/// The model tries every compile-time trusted foreground product and accepts
/// exactly one signature plus whole-bundle match. Persistence occurs before an
/// update becomes visible. A signed release cannot replace an equal or newer
/// release, and once a newer release is effective the provider never falls
/// back to older evidence for a missing or expired profile.
@MainActor
final class PreDriveEvidenceUpdateModel: ObservableObject {
  @Published private(set) var state: PreDriveEvidenceUpdateModelState
  var evidenceDidChange: (() -> Void)?

  private let entriesByReleaseID: [String: BundledProductReleaseEntry]
  private let store: (any PreDriveEvidenceUpdateStoring)?
  private let currentDateProvider: () -> Date
  private var verifiedUpdatesByProductReleaseID: [String: VerifiedPreDriveEvidenceUpdate] = [:]

  init(
    entries: [BundledProductReleaseEntry],
    store: (any PreDriveEvidenceUpdateStoring)?,
    currentDateProvider: @escaping () -> Date = Date.init
  ) {
    entriesByReleaseID = Dictionary(
      uniqueKeysWithValues: entries.map {
        ($0.release.releaseID, $0)
      }
    )
    self.store = store
    self.currentDateProvider = currentDateProvider
    if entries.allSatisfy({
      $0.preDriveEvidenceUpdateTrustKeys.isEmpty
    }) {
      state = .unavailable
      return
    }
    guard let store else {
      state = .blocked(
        PreDriveEvidenceUpdateModelError.storeUnavailable.rawValue
      )
      return
    }
    state = .ready
    restore(from: store)
  }

  var canImport: Bool {
    guard store != nil else { return false }
    return entriesByReleaseID.values.contains {
      !$0.preDriveEvidenceUpdateTrustKeys.isEmpty
    }
  }

  var trustedProductCount: Int {
    entriesByReleaseID.values.filter {
      !$0.preDriveEvidenceUpdateTrustKeys.isEmpty
    }.count
  }

  func importEnvelope(_ data: Data) {
    guard canImport else {
      state = .blocked(
        PreDriveEvidenceUpdateModelError.trustUnavailable.rawValue
      )
      return
    }
    guard
      !data.isEmpty,
      data.count <= PreDriveEvidenceUpdateCodec.maximumEnvelopeByteCount
    else {
      state = .blocked(
        PreDriveEvidenceUpdateModelError.importTooLarge.rawValue
      )
      return
    }
    let matches = verifiedMatches(for: data)
    guard !matches.isEmpty else {
      state = .blocked(
        PreDriveEvidenceUpdateModelError.noTrustedProductMatch.rawValue
      )
      return
    }
    guard matches.count == 1, let match = matches.first else {
      state = .blocked(
        PreDriveEvidenceUpdateModelError.ambiguousProductMatch.rawValue
      )
      return
    }
    let entry = match.entry
    let verified = match.update
    guard isStrictlyNewer(verified, than: entry) else {
      return
    }
    guard let store else {
      state = .blocked(
        PreDriveEvidenceUpdateModelError.storeUnavailable.rawValue
      )
      return
    }
    do {
      try store.save(data, productReleaseID: entry.release.releaseID)
    } catch {
      state = .blocked(
        PreDriveEvidenceUpdateModelError.persistenceFailed.rawValue
      )
      return
    }
    verifiedUpdatesByProductReleaseID[
      entry.release.releaseID
    ] = verified
    state = .installed(
      productReleaseID: entry.release.releaseID,
      evidenceReleaseID: verified.bundle.manifest.releaseID
    )
    evidenceDidChange?()
  }

  func rejectImport(_ error: PreDriveEvidenceUpdateModelError) {
    state = .blocked(error.rawValue)
  }

  func evidence(
    for entry: BundledProductReleaseEntry,
    session: PreDriveReviewSession
  ) throws -> PreDriveReviewEvidence? {
    let now = currentDateProvider()
    if let update =
      verifiedUpdatesByProductReleaseID[entry.release.releaseID],
      let updateReleasedAt = parseISO8601(
        update.bundle.manifest.releasedAt
      ),
      updateReleasedAt <= now
    {
      return try update.bundle.evidence(
        for: session,
        at: now
      )
    }
    return try entry.preDriveEvidenceBundle?.evidence(
      for: session,
      at: now
    )
  }

  private func restore(
    from store: any PreDriveEvidenceUpdateStoring
  ) {
    var restored: [(String, VerifiedPreDriveEvidenceUpdate)] = []
    var loadFailed = false
    for entry in entriesByReleaseID.values
    where !entry.preDriveEvidenceUpdateTrustKeys.isEmpty {
      do {
        guard
          let data = try store.load(
            productReleaseID: entry.release.releaseID
          )
        else {
          continue
        }
        let update = try PreDriveEvidenceUpdateCodec.verify(
          data,
          productRelease: entry.release,
          trustedKeys: entry.preDriveEvidenceUpdateTrustKeys
        )
        guard isNewerThanBundled(update, entry: entry) else {
          loadFailed = true
          continue
        }
        restored.append((entry.release.releaseID, update))
      } catch {
        loadFailed = true
      }
    }
    verifiedUpdatesByProductReleaseID = Dictionary(
      uniqueKeysWithValues: restored
    )
    if loadFailed {
      state = .blocked(
        PreDriveEvidenceUpdateModelError.noTrustedProductMatch.rawValue
      )
    } else if let latest = restored.max(by: {
      ($0.1.bundle.manifest.releasedAt)
        < ($1.1.bundle.manifest.releasedAt)
    }) {
      state = .installed(
        productReleaseID: latest.0,
        evidenceReleaseID: latest.1.bundle.manifest.releaseID
      )
    }
  }

  private func verifiedMatches(
    for data: Data
  ) -> [(
    entry: BundledProductReleaseEntry,
    update: VerifiedPreDriveEvidenceUpdate
  )] {
    entriesByReleaseID.values.compactMap { entry in
      guard !entry.preDriveEvidenceUpdateTrustKeys.isEmpty else {
        return nil
      }
      guard
        let verified = try? PreDriveEvidenceUpdateCodec.verify(
          data,
          productRelease: entry.release,
          trustedKeys: entry.preDriveEvidenceUpdateTrustKeys
        )
      else {
        return nil
      }
      return (entry, verified)
    }
  }

  private func isStrictlyNewer(
    _ update: VerifiedPreDriveEvidenceUpdate,
    than entry: BundledProductReleaseEntry
  ) -> Bool {
    let updateManifest = update.bundle.manifest
    let existingManifests = [
      entry.preDriveEvidenceBundle?.manifest,
      verifiedUpdatesByProductReleaseID[
        entry.release.releaseID
      ]?.bundle.manifest,
    ].compactMap { $0 }
    if existingManifests.contains(where: {
      $0.releaseID == updateManifest.releaseID
    }) {
      state = .blocked(
        PreDriveEvidenceUpdateModelError.releaseIdentityReused.rawValue
      )
      return false
    }
    guard
      let updateReleasedAt = parseISO8601(updateManifest.releasedAt),
      existingManifests.allSatisfy({
        guard let existingReleasedAt = parseISO8601($0.releasedAt) else {
          return false
        }
        return updateReleasedAt > existingReleasedAt
      })
    else {
      state = .blocked(
        PreDriveEvidenceUpdateModelError.rollbackRejected.rawValue
      )
      return false
    }
    return true
  }

  private func isNewerThanBundled(
    _ update: VerifiedPreDriveEvidenceUpdate,
    entry: BundledProductReleaseEntry
  ) -> Bool {
    guard let bundled = entry.preDriveEvidenceBundle?.manifest else {
      return true
    }
    guard
      update.bundle.manifest.releaseID != bundled.releaseID,
      let updateReleasedAt = parseISO8601(
        update.bundle.manifest.releasedAt
      ),
      let bundledReleasedAt = parseISO8601(bundled.releasedAt)
    else {
      return false
    }
    return updateReleasedAt > bundledReleasedAt
  }

  private func parseISO8601(_ value: String) -> Date? {
    let standard = ISO8601DateFormatter()
    if let date = standard.date(from: value) {
      return date
    }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [
      .withInternetDateTime,
      .withFractionalSeconds,
    ]
    return fractional.date(from: value)
  }
}
