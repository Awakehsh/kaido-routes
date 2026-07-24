import CryptoKit
import Foundation
import KaidoNavigation
import KaidoPresentation

public enum PreDriveEvidenceUpdateSignatureAlgorithm:
  String, Codable, Equatable, Sendable
{
  case ed25519 = "ED25519"
}

/// One compile-time trust root for signed current-evidence updates.
///
/// Only the public key is shipped. The corresponding private key stays outside
/// the repository and App bundle.
public struct PreDriveEvidenceUpdateTrustKey:
  Codable, Equatable, Sendable
{
  public let keyID: String
  public let algorithm: PreDriveEvidenceUpdateSignatureAlgorithm
  public let publicKeyBase64: String

  public init(
    keyID: String,
    algorithm: PreDriveEvidenceUpdateSignatureAlgorithm = .ed25519,
    publicKeyBase64: String
  ) {
    self.keyID = keyID
    self.algorithm = algorithm
    self.publicKeyBase64 = publicKeyBase64
  }

  private enum CodingKeys: String, CodingKey {
    case keyID = "key_id"
    case algorithm
    case publicKeyBase64 = "public_key_base64"
  }
}

/// A self-contained signed update carrying the exact reviewed manifest bytes.
///
/// The signature covers a domain separator, key ID, and the unmodified
/// manifest bytes. Product, RoutePlan, profile, source, and chronology
/// validation still comes from `PreDriveEvidenceBundle`.
public struct PreDriveEvidenceUpdateEnvelope:
  Codable, Equatable, Sendable
{
  public static let currentSchemaVersion = "1.0"

  public let schemaVersion: String
  public let keyID: String
  public let algorithm: PreDriveEvidenceUpdateSignatureAlgorithm
  public let manifestSHA256: String
  public let manifestBase64: String
  public let signatureBase64: String

  public init(
    schemaVersion: String =
      PreDriveEvidenceUpdateEnvelope.currentSchemaVersion,
    keyID: String,
    algorithm: PreDriveEvidenceUpdateSignatureAlgorithm,
    manifestSHA256: String,
    manifestBase64: String,
    signatureBase64: String
  ) {
    self.schemaVersion = schemaVersion
    self.keyID = keyID
    self.algorithm = algorithm
    self.manifestSHA256 = manifestSHA256
    self.manifestBase64 = manifestBase64
    self.signatureBase64 = signatureBase64
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case keyID = "key_id"
    case algorithm
    case manifestSHA256 = "manifest_sha256"
    case manifestBase64 = "manifest_base64"
    case signatureBase64 = "signature_base64"
  }
}

public struct PreDriveEvidenceUpdateSigningKeyPair:
  Equatable, Sendable
{
  public let privateKeyData: Data
  public let trustKey: PreDriveEvidenceUpdateTrustKey

  public init(
    privateKeyData: Data,
    trustKey: PreDriveEvidenceUpdateTrustKey
  ) {
    self.privateKeyData = privateKeyData
    self.trustKey = trustKey
  }
}

public struct VerifiedPreDriveEvidenceUpdate:
  Equatable, Sendable
{
  public let envelope: PreDriveEvidenceUpdateEnvelope
  public let manifestData: Data
  public let bundle: PreDriveEvidenceBundle

  public init(
    envelope: PreDriveEvidenceUpdateEnvelope,
    manifestData: Data,
    bundle: PreDriveEvidenceBundle
  ) {
    self.envelope = envelope
    self.manifestData = manifestData
    self.bundle = bundle
  }
}

public enum PreDriveEvidenceUpdateError:
  Error, Equatable, Sendable
{
  case foregroundProductRequired
  case invalidKeyIdentity
  case invalidPrivateKey
  case invalidTrustRegistry
  case invalidEnvelope
  case invalidEnvelopeSchema
  case trustedKeyUnavailable
  case manifestHashMismatch
  case signatureInvalid
  case invalidManifest
  case invalidBundle([PreDriveEvidenceBundleIssue])

  public var code: String {
    switch self {
    case .foregroundProductRequired:
      "PRE_DRIVE_EVIDENCE_UPDATE_FOREGROUND_PRODUCT_REQUIRED"
    case .invalidKeyIdentity:
      "PRE_DRIVE_EVIDENCE_UPDATE_KEY_IDENTITY_INVALID"
    case .invalidPrivateKey:
      "PRE_DRIVE_EVIDENCE_UPDATE_PRIVATE_KEY_INVALID"
    case .invalidTrustRegistry:
      "PRE_DRIVE_EVIDENCE_UPDATE_TRUST_REGISTRY_INVALID"
    case .invalidEnvelope:
      "PRE_DRIVE_EVIDENCE_UPDATE_ENVELOPE_INVALID"
    case .invalidEnvelopeSchema:
      "PRE_DRIVE_EVIDENCE_UPDATE_SCHEMA_VERSION_INVALID"
    case .trustedKeyUnavailable:
      "PRE_DRIVE_EVIDENCE_UPDATE_TRUSTED_KEY_UNAVAILABLE"
    case .manifestHashMismatch:
      "PRE_DRIVE_EVIDENCE_UPDATE_MANIFEST_HASH_MISMATCH"
    case .signatureInvalid:
      "PRE_DRIVE_EVIDENCE_UPDATE_SIGNATURE_INVALID"
    case .invalidManifest:
      "PRE_DRIVE_EVIDENCE_UPDATE_MANIFEST_INVALID"
    case .invalidBundle:
      "PRE_DRIVE_EVIDENCE_UPDATE_BUNDLE_INVALID"
    }
  }
}

public enum PreDriveEvidenceUpdateTrustKeyCodec {
  public static func encode(
    _ trustKey: PreDriveEvidenceUpdateTrustKey
  ) throws -> Data {
    try PreDriveEvidenceUpdateCodec.validateTrustedKeys([trustKey])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(trustKey)
  }

  public static func decode(
    _ data: Data
  ) throws -> PreDriveEvidenceUpdateTrustKey {
    let trustKey: PreDriveEvidenceUpdateTrustKey
    do {
      trustKey = try JSONDecoder().decode(
        PreDriveEvidenceUpdateTrustKey.self,
        from: data
      )
    } catch {
      throw PreDriveEvidenceUpdateError.invalidTrustRegistry
    }
    try PreDriveEvidenceUpdateCodec.validateTrustedKeys([trustKey])
    return trustKey
  }
}

public enum PreDriveEvidenceUpdateCodec {
  public static let maximumEnvelopeByteCount = 2 * 1_024 * 1_024
  public static let maximumManifestByteCount = 1 * 1_024 * 1_024

  private static let signatureDomain =
    "KAIDO_PRE_DRIVE_EVIDENCE_UPDATE_V1"

  public static func generateSigningKeyPair(
    keyID: String
  ) throws -> PreDriveEvidenceUpdateSigningKeyPair {
    guard isValidKeyID(keyID) else {
      throw PreDriveEvidenceUpdateError.invalidKeyIdentity
    }
    let privateKey = Curve25519.Signing.PrivateKey()
    return PreDriveEvidenceUpdateSigningKeyPair(
      privateKeyData: privateKey.rawRepresentation,
      trustKey: PreDriveEvidenceUpdateTrustKey(
        keyID: keyID,
        publicKeyBase64:
          privateKey.publicKey.rawRepresentation.base64EncodedString()
      )
    )
  }

  public static func trustKey(
    keyID: String,
    privateKeyData: Data
  ) throws -> PreDriveEvidenceUpdateTrustKey {
    guard isValidKeyID(keyID) else {
      throw PreDriveEvidenceUpdateError.invalidKeyIdentity
    }
    let privateKey: Curve25519.Signing.PrivateKey
    do {
      privateKey = try Curve25519.Signing.PrivateKey(
        rawRepresentation: privateKeyData
      )
    } catch {
      throw PreDriveEvidenceUpdateError.invalidPrivateKey
    }
    return PreDriveEvidenceUpdateTrustKey(
      keyID: keyID,
      publicKeyBase64:
        privateKey.publicKey.rawRepresentation.base64EncodedString()
    )
  }

  public static func sign(
    manifestData: Data,
    productRelease: KaidoProductRelease,
    keyID: String,
    privateKeyData: Data
  ) throws -> Data {
    try requireForegroundProduct(productRelease)
    guard
      isValidKeyID(keyID),
      !manifestData.isEmpty,
      manifestData.count <= maximumManifestByteCount
    else {
      throw PreDriveEvidenceUpdateError.invalidEnvelope
    }
    let privateKey: Curve25519.Signing.PrivateKey
    do {
      privateKey = try Curve25519.Signing.PrivateKey(
        rawRepresentation: privateKeyData
      )
    } catch {
      throw PreDriveEvidenceUpdateError.invalidPrivateKey
    }
    let bundle = try decodeBundle(
      manifestData,
      productRelease: productRelease
    )
    let signature: Data
    do {
      signature = try privateKey.signature(
        for: signatureMessage(
          keyID: keyID,
          manifestData: manifestData
        )
      )
    } catch {
      throw PreDriveEvidenceUpdateError.invalidPrivateKey
    }
    let envelope = PreDriveEvidenceUpdateEnvelope(
      keyID: keyID,
      algorithm: .ed25519,
      manifestSHA256: sha256Hex(manifestData),
      manifestBase64: manifestData.base64EncodedString(),
      signatureBase64: signature.base64EncodedString()
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let encoded = try encoder.encode(envelope)
    guard encoded.count <= maximumEnvelopeByteCount else {
      throw PreDriveEvidenceUpdateError.invalidEnvelope
    }
    let trustKey = PreDriveEvidenceUpdateTrustKey(
      keyID: keyID,
      publicKeyBase64:
        privateKey.publicKey.rawRepresentation.base64EncodedString()
    )
    let verified = try verify(
      encoded,
      productRelease: productRelease,
      trustedKeys: [trustKey]
    )
    guard verified.bundle == bundle else {
      throw PreDriveEvidenceUpdateError.invalidEnvelope
    }
    return encoded
  }

  public static func verify(
    _ envelopeData: Data,
    productRelease: KaidoProductRelease,
    trustedKeys: [PreDriveEvidenceUpdateTrustKey]
  ) throws -> VerifiedPreDriveEvidenceUpdate {
    try requireForegroundProduct(productRelease)
    try validateTrustedKeys(trustedKeys)
    guard
      !envelopeData.isEmpty,
      envelopeData.count <= maximumEnvelopeByteCount
    else {
      throw PreDriveEvidenceUpdateError.invalidEnvelope
    }
    let envelope: PreDriveEvidenceUpdateEnvelope
    do {
      envelope = try JSONDecoder().decode(
        PreDriveEvidenceUpdateEnvelope.self,
        from: envelopeData
      )
    } catch {
      throw PreDriveEvidenceUpdateError.invalidEnvelope
    }
    guard
      envelope.schemaVersion
        == PreDriveEvidenceUpdateEnvelope.currentSchemaVersion
    else {
      throw PreDriveEvidenceUpdateError.invalidEnvelopeSchema
    }
    guard
      isValidKeyID(envelope.keyID),
      envelope.algorithm == .ed25519,
      isSHA256(envelope.manifestSHA256),
      let manifestData = canonicalBase64Data(envelope.manifestBase64),
      !manifestData.isEmpty,
      manifestData.count <= maximumManifestByteCount,
      let signature = canonicalBase64Data(envelope.signatureBase64),
      signature.count == 64
    else {
      throw PreDriveEvidenceUpdateError.invalidEnvelope
    }
    guard sha256Hex(manifestData) == envelope.manifestSHA256 else {
      throw PreDriveEvidenceUpdateError.manifestHashMismatch
    }
    guard
      let trustKey = trustedKeys.first(where: {
        $0.keyID == envelope.keyID
          && $0.algorithm == envelope.algorithm
      }),
      let publicKeyData = canonicalBase64Data(trustKey.publicKeyBase64)
    else {
      throw PreDriveEvidenceUpdateError.trustedKeyUnavailable
    }
    let publicKey: Curve25519.Signing.PublicKey
    do {
      publicKey = try Curve25519.Signing.PublicKey(
        rawRepresentation: publicKeyData
      )
    } catch {
      throw PreDriveEvidenceUpdateError.invalidTrustRegistry
    }
    guard
      publicKey.isValidSignature(
        signature,
        for: signatureMessage(
          keyID: envelope.keyID,
          manifestData: manifestData
        )
      )
    else {
      throw PreDriveEvidenceUpdateError.signatureInvalid
    }
    return VerifiedPreDriveEvidenceUpdate(
      envelope: envelope,
      manifestData: manifestData,
      bundle: try decodeBundle(
        manifestData,
        productRelease: productRelease
      )
    )
  }

  public static func validateTrustedKeys(
    _ trustedKeys: [PreDriveEvidenceUpdateTrustKey]
  ) throws {
    var seenKeyIDs: Set<String> = []
    for trustedKey in trustedKeys {
      guard
        isValidKeyID(trustedKey.keyID),
        trustedKey.algorithm == .ed25519,
        seenKeyIDs.insert(trustedKey.keyID).inserted,
        let publicKeyData = canonicalBase64Data(
          trustedKey.publicKeyBase64
        ),
        publicKeyData.count == 32,
        (try? Curve25519.Signing.PublicKey(
          rawRepresentation: publicKeyData
        )) != nil
      else {
        throw PreDriveEvidenceUpdateError.invalidTrustRegistry
      }
    }
  }

  private static func decodeBundle(
    _ manifestData: Data,
    productRelease: KaidoProductRelease
  ) throws -> PreDriveEvidenceBundle {
    do {
      return try PreDriveEvidenceBundleCodec.decode(
        manifestData,
        context: PreDriveEvidenceBundleContext(
          productReleaseID: productRelease.releaseID,
          productReleasedAt: productRelease.releasedAt,
          navigationReleaseID: productRelease.navigation.releaseID,
          routePlan: productRelease.navigation.bundle.routePlan,
          evidenceScope: .releasedRoad
        )
      )
    } catch PreDriveEvidenceBundleError.invalid(let issues) {
      throw PreDriveEvidenceUpdateError.invalidBundle(issues)
    } catch {
      throw PreDriveEvidenceUpdateError.invalidManifest
    }
  }

  private static func requireForegroundProduct(
    _ productRelease: KaidoProductRelease
  ) throws {
    guard
      productRelease.runtimeUse.evidenceScope == .releasedRoad,
      productRelease.runtimeUse.liveInputPolicy == .foregroundWhenInUse,
      productRelease.foregroundLiveInputAuthority != nil
    else {
      throw PreDriveEvidenceUpdateError.foregroundProductRequired
    }
  }

  private static func signatureMessage(
    keyID: String,
    manifestData: Data
  ) -> Data {
    var result = Data(signatureDomain.utf8)
    result.append(0)
    result.append(Data(keyID.utf8))
    result.append(0)
    result.append(manifestData)
    return result
  }

  private static func isValidKeyID(_ value: String) -> Bool {
    !value.isEmpty
      && value.count <= 128
      && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
      && value.allSatisfy {
        $0.isLetter || $0.isNumber || $0 == "." || $0 == "-"
          || $0 == "_"
      }
  }

  private static func canonicalBase64Data(_ value: String) -> Data? {
    guard
      !value.isEmpty,
      let data = Data(base64Encoded: value),
      data.base64EncodedString() == value
    else {
      return nil
    }
    return data
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64
      && value == value.lowercased()
      && value.allSatisfy {
        ("0"..."9").contains($0) || ("a"..."f").contains($0)
      }
  }

  private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data)
      .map { String(format: "%02x", $0) }
      .joined()
  }
}
