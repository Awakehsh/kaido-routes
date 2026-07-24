import Foundation

public enum KaidoProductRuntimeEvidenceScope: String, Codable, Equatable, Sendable {
  case syntheticTestOnly = "SYNTHETIC_TEST_ONLY"
  case releasedRoad = "RELEASED_ROAD"
}

public enum KaidoProductLiveInputPolicy: String, Codable, Equatable, Sendable {
  case disabled = "DISABLED"
  case foregroundWhenInUse = "FOREGROUND_WHEN_IN_USE"
}

/// Product-release intent for runtime inputs.
///
/// Structural release validation alone never grants a live sensor authority.
/// The joint product artifact must also declare whether its evidence is
/// synthetic or released-road evidence and whether foreground live input is
/// permitted.
public struct KaidoProductRuntimeUseDeclaration: Codable, Equatable, Sendable {
  public let evidenceScope: KaidoProductRuntimeEvidenceScope
  public let liveInputPolicy: KaidoProductLiveInputPolicy

  public init(
    evidenceScope: KaidoProductRuntimeEvidenceScope,
    liveInputPolicy: KaidoProductLiveInputPolicy
  ) {
    self.evidenceScope = evidenceScope
    self.liveInputPolicy = liveInputPolicy
  }

  public static let syntheticTestOnlyDisabled =
    KaidoProductRuntimeUseDeclaration(
      evidenceScope: .syntheticTestOnly,
      liveInputPolicy: .disabled
    )

  private enum CodingKeys: String, CodingKey {
    case evidenceScope = "evidence_scope"
    case liveInputPolicy = "live_input_policy"
  }
}

public enum KaidoProductRuntimeSourceDomain: String, Codable, Equatable, Sendable {
  case navigation = "NAVIGATION"
  case routeAtlas = "ROUTE_ATLAS"
}

public struct KaidoProductRuntimeSourceDescriptor: Equatable, Sendable {
  public let domain: KaidoProductRuntimeSourceDomain
  public let sourceID: String
  public let licenceIdentifier: String

  public init(
    domain: KaidoProductRuntimeSourceDomain,
    sourceID: String,
    licenceIdentifier: String
  ) {
    self.domain = domain
    self.sourceID = sourceID
    self.licenceIdentifier = licenceIdentifier
  }
}

public enum KaidoProductRuntimeUseIssue: Equatable, Sendable {
  case missingEvidenceSource(KaidoProductRuntimeSourceDomain)
  case syntheticLiveInputForbidden
  case sourceScopeMismatch(
    KaidoProductRuntimeSourceDomain,
    sourceID: String
  )

  public var code: String {
    switch self {
    case .missingEvidenceSource:
      "MISSING_PRODUCT_RUNTIME_EVIDENCE_SOURCE"
    case .syntheticLiveInputForbidden:
      "SYNTHETIC_PRODUCT_LIVE_INPUT_FORBIDDEN"
    case .sourceScopeMismatch:
      "PRODUCT_RUNTIME_SOURCE_SCOPE_MISMATCH"
    }
  }

  var sortKey: String {
    switch self {
    case .missingEvidenceSource(let domain):
      "\(code):\(domain.rawValue)"
    case .syntheticLiveInputForbidden:
      code
    case .sourceScopeMismatch(let domain, let sourceID):
      "\(code):\(domain.rawValue):\(sourceID)"
    }
  }
}

public struct KaidoProductRuntimeUseEvaluation: Equatable, Sendable {
  public let declaration: KaidoProductRuntimeUseDeclaration
  public let issues: [KaidoProductRuntimeUseIssue]

  public var isValid: Bool {
    issues.isEmpty
  }

  public var foregroundLiveInputAdmitted: Bool {
    issues.isEmpty
      && declaration.evidenceScope == .releasedRoad
      && declaration.liveInputPolicy == .foregroundWhenInUse
  }
}

public enum KaidoProductRuntimeUseEvaluator {
  public static func evaluate(
    declaration: KaidoProductRuntimeUseDeclaration,
    sources: [KaidoProductRuntimeSourceDescriptor]
  ) -> KaidoProductRuntimeUseEvaluation {
    var issues: [KaidoProductRuntimeUseIssue] = []

    if declaration.evidenceScope == .syntheticTestOnly,
      declaration.liveInputPolicy != .disabled
    {
      issues.append(.syntheticLiveInputForbidden)
    }

    for domain in [
      KaidoProductRuntimeSourceDomain.navigation,
      .routeAtlas,
    ] {
      let domainSources = sources.filter { $0.domain == domain }
      if domainSources.isEmpty {
        issues.append(.missingEvidenceSource(domain))
        continue
      }

      for source in domainSources {
        let sourceID = normalized(source.sourceID)
        let licenceIdentifier = normalized(source.licenceIdentifier)
        guard !sourceID.isEmpty, !licenceIdentifier.isEmpty else {
          issues.append(.missingEvidenceSource(domain))
          continue
        }

        let isSynthetic = licenceIdentifier == "SYNTHETIC_TEST_ONLY"
        switch declaration.evidenceScope {
        case .syntheticTestOnly where !isSynthetic:
          issues.append(
            .sourceScopeMismatch(domain, sourceID: sourceID)
          )
        case .releasedRoad where isSynthetic:
          issues.append(
            .sourceScopeMismatch(domain, sourceID: sourceID)
          )
        case .syntheticTestOnly, .releasedRoad:
          break
        }
      }
    }

    return KaidoProductRuntimeUseEvaluation(
      declaration: declaration,
      issues: sortedUnique(issues)
    )
  }

  private static func sortedUnique(
    _ issues: [KaidoProductRuntimeUseIssue]
  ) -> [KaidoProductRuntimeUseIssue] {
    var result: [KaidoProductRuntimeUseIssue] = []
    for issue in issues.sorted(by: { $0.sortKey < $1.sortKey })
    where !result.contains(issue) {
      result.append(issue)
    }
    return result
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// Complete identity shared by one validated product release and its runtime.
///
/// The package-only initializer prevents application adapters from inventing a
/// release identity. Public consumers receive this value from
/// `KaidoProductRelease` or `KaidoProductNavigationRuntime`.
public struct KaidoProductRuntimeIdentity: Equatable, Sendable {
  public let productReleaseID: String
  public let navigationReleaseID: String
  public let runtimePolicyID: String
  public let networkSnapshotID: String
  public let routePlanID: String
  public let matcherCorridorID: String

  package init(
    productReleaseID: String,
    navigationReleaseID: String,
    runtimePolicyID: String,
    networkSnapshotID: String,
    routePlanID: String,
    matcherCorridorID: String
  ) {
    self.productReleaseID = productReleaseID
    self.navigationReleaseID = navigationReleaseID
    self.runtimePolicyID = runtimePolicyID
    self.networkSnapshotID = networkSnapshotID
    self.routePlanID = routePlanID
    self.matcherCorridorID = matcherCorridorID
  }

  public var isComplete: Bool {
    [
      productReleaseID,
      navigationReleaseID,
      runtimePolicyID,
      networkSnapshotID,
      routePlanID,
      matcherCorridorID,
    ].allSatisfy {
      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }
}

/// Unforgeable authority for an exact released-road foreground runtime.
///
/// Only `KaidoProductRelease` can mint this package-internal token after the
/// complete joint release and runtime-use declaration pass validation.
public struct KaidoForegroundLiveInputAuthority: Equatable, Sendable {
  public let runtimeIdentity: KaidoProductRuntimeIdentity

  package init(runtimeIdentity: KaidoProductRuntimeIdentity) {
    self.runtimeIdentity = runtimeIdentity
  }
}
