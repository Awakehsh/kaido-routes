import Foundation
import KaidoSurfaceRouting

public enum ReleasedSurfaceEgressPlanningDisposition:
  String, Equatable, Sendable
{
  case ready = "READY"
  case rejected = "REJECTED"
  case providerFailure = "PROVIDER_FAILURE"
  case invalidResponse = "INVALID_RESPONSE"
}

public struct ReleasedSurfaceEgressPlanningOption: Equatable, Sendable {
  public let policyID: String
  public let candidateID: String
  public let journeyPlan: JourneyPlan

  package init(
    policyID: String,
    candidateID: String,
    journeyPlan: JourneyPlan
  ) {
    self.policyID = policyID
    self.candidateID = candidateID
    self.journeyPlan = journeyPlan
  }
}

public struct ReleasedSurfaceEgressEvaluation: Equatable, Sendable {
  public let policyID: String
  public let evaluation: SurfaceEgressCandidateEvaluation

  package init(
    policyID: String,
    evaluation: SurfaceEgressCandidateEvaluation
  ) {
    self.policyID = policyID
    self.evaluation = evaluation
  }
}

public struct ReleasedSurfaceEgressProviderFailure: Equatable, Sendable {
  public let policyID: String
  public let failure: SurfaceProviderFailure

  package init(policyID: String, failure: SurfaceProviderFailure) {
    self.policyID = policyID
    self.failure = failure
  }
}

public struct ReleasedSurfaceEgressCompilationFailure: Equatable, Sendable {
  public let policyID: String
  public let candidateID: String
  public let error: JourneyPlanCompilerError

  package init(
    policyID: String,
    candidateID: String,
    error: JourneyPlanCompilerError
  ) {
    self.policyID = policyID
    self.candidateID = candidateID
    self.error = error
  }
}

/// Every released exit policy is queried independently and reduced through the
/// same graph inspection and compiler. Provider response order has no authority;
/// the release-owned selection policy ranks only compiler-admitted plans.
public struct ReleasedSurfaceEgressPlanningResult: Equatable, Sendable {
  public let disposition: ReleasedSurfaceEgressPlanningDisposition
  public let evaluations: [ReleasedSurfaceEgressEvaluation]
  public let options: [ReleasedSurfaceEgressPlanningOption]
  public let providerFailures: [ReleasedSurfaceEgressProviderFailure]
  public let compilationFailures: [ReleasedSurfaceEgressCompilationFailure]

  package init(
    disposition: ReleasedSurfaceEgressPlanningDisposition,
    evaluations: [ReleasedSurfaceEgressEvaluation],
    options: [ReleasedSurfaceEgressPlanningOption],
    providerFailures: [ReleasedSurfaceEgressProviderFailure],
    compilationFailures: [ReleasedSurfaceEgressCompilationFailure]
  ) {
    self.disposition = disposition
    self.evaluations = evaluations
    self.options = options
    self.providerFailures = providerFailures
    self.compilationFailures = compilationFailures
  }

  public var selectedPlan: JourneyPlan? {
    guard disposition == .ready else { return nil }
    return options.first?.journeyPlan
  }
}

public struct ReleasedSurfaceEgressPlanner<Provider, Inspector>: Sendable
where
  Provider: ReleaseBoundSurfaceEgressRouteProvider,
  Inspector: SurfaceEgressCandidateInspector
{
  public let provider: Provider
  public let inspector: Inspector

  public init(provider: Provider, inspector: Inspector) {
    self.provider = provider
    self.inspector = inspector
  }

  public func plan(
    release: KaidoProductRelease,
    basePlan: JourneyPlan
  ) async throws -> ReleasedSurfaceEgressPlanningResult {
    let bundle = release.navigation.bundle
    guard let definition = bundle.surfaceEgressDefinition else {
      throw JourneyPlanCompilerError.surfaceEgressNotReleased
    }
    let definitionIssues = definition.validationIssues(
      networkSnapshot: bundle.networkSnapshot,
      routePlan: bundle.routePlan,
      runtimePolicy: bundle.runtimePolicy
    )
    guard definitionIssues.isEmpty else {
      throw JourneyPlanCompilerError.invalidReleasedSurfaceEgress(
        definitionIssues
      )
    }
    guard provider.releaseIdentity == definition.providerIdentity else {
      throw JourneyPlanCompilerError.providerIdentityMismatch
    }
    guard let returnTarget = basePlan.returnTarget else {
      throw JourneyPlanCompilerError.invalidRequest([
        "INVALID_SURFACE_EGRESS_BASE_PLAN"
      ])
    }

    var evaluations: [ReleasedSurfaceEgressEvaluation] = []
    var options: [ReleasedSurfaceEgressPlanningOption] = []
    var providerFailures: [ReleasedSurfaceEgressProviderFailure] = []
    var compilationFailures: [ReleasedSurfaceEgressCompilationFailure] = []
    var sawInvalidResponse = false
    var sawCandidateResponse = false

    for policy in definition.policies.sorted(by: { $0.id < $1.id }) {
      let request = SurfaceEgressRouteRequest(
        id: "\(basePlan.id).egress.\(policy.id)",
        exitFacilityID: policy.exitFacilityID,
        egressOptionID: policy.egressOptionID,
        originAnchor: policy.originAnchor,
        destinationAnchor: DirectedApproachAnchor(
          id: returnTarget.id,
          coordinate: returnTarget.coordinate,
          directedSurfaceEdgeID: returnTarget.directedSurfaceEdgeID,
          expectedBearingDegrees: returnTarget.expectedBearingDegrees,
          bearingToleranceDegrees:
            policy.returnTargetBearingToleranceDegrees,
          maxTerminalDistanceMeters: policy.maxReturnTargetDistanceMeters
        )
      )
      _ = try JourneyPlanCompiler.surfaceEgressPreflight(
        release: release,
        basePlan: basePlan,
        request: request,
        providerIdentity: provider.releaseIdentity
      )

      let response = await provider.egressRoutes(for: request)
      switch response {
      case .failure(let failure):
        providerFailures.append(
          ReleasedSurfaceEgressProviderFailure(
            policyID: policy.id,
            failure: failure
          )
        )
        evaluations.append(
          ReleasedSurfaceEgressEvaluation(
            policyID: policy.id,
            evaluation:
              SurfaceEgressHardGateEvaluator.disclosedFailure(failure)
          )
        )

      case .success(let candidates):
        sawCandidateResponse = true
        guard validCandidateIDs(candidates) else {
          sawInvalidResponse = true
          evaluations.append(
            ReleasedSurfaceEgressEvaluation(
              policyID: policy.id,
              evaluation: SurfaceEgressHardGateEvaluator.invalidResponse(
                reasonCodes: ["INVALID_OR_DUPLICATE_CANDIDATE_ID"]
              )
            )
          )
          continue
        }
        if candidates.isEmpty {
          sawInvalidResponse = true
          evaluations.append(
            ReleasedSurfaceEgressEvaluation(
              policyID: policy.id,
              evaluation: SurfaceEgressHardGateEvaluator.invalidResponse(
                reasonCodes: ["EMPTY_SUCCESS_RESPONSE"]
              )
            )
          )
          continue
        }
        for candidate in candidates {
          let inspection = await inspector.inspect(
            candidate: candidate,
            request: request,
            policy: policy
          )
          let evaluation = SurfaceEgressHardGateEvaluator.evaluate(
            candidate: candidate,
            request: request,
            policy: policy,
            inspection: inspection,
            expectedProviderID: provider.releaseIdentity.providerID
          )
          evaluations.append(
            ReleasedSurfaceEgressEvaluation(
              policyID: policy.id,
              evaluation: evaluation
            )
          )
          guard evaluation.isAccepted else { continue }
          do {
            let plan = try JourneyPlanCompiler.surfaceEgress(
              release: release,
              basePlan: basePlan,
              request: request,
              candidate: candidate,
              inspection: inspection,
              providerIdentity: provider.releaseIdentity
            )
            options.append(
              ReleasedSurfaceEgressPlanningOption(
                policyID: policy.id,
                candidateID: candidate.id,
                journeyPlan: plan
              )
            )
          } catch let error as JourneyPlanCompilerError {
            compilationFailures.append(
              ReleasedSurfaceEgressCompilationFailure(
                policyID: policy.id,
                candidateID: candidate.id,
                error: error
              )
            )
          }
        }
      }
    }

    switch definition.selectionPolicy {
    case .fastestThenShortest:
      options.sort(by: Self.fastestThenShortest)
    }
    providerFailures.sort { $0.policyID < $1.policyID }
    compilationFailures.sort {
      if $0.policyID != $1.policyID {
        return $0.policyID < $1.policyID
      }
      return $0.candidateID < $1.candidateID
    }

    let disposition: ReleasedSurfaceEgressPlanningDisposition
    if !options.isEmpty {
      disposition = .ready
    } else if sawInvalidResponse {
      disposition = .invalidResponse
    } else if !sawCandidateResponse && !providerFailures.isEmpty {
      disposition = .providerFailure
    } else {
      disposition = .rejected
    }
    return ReleasedSurfaceEgressPlanningResult(
      disposition: disposition,
      evaluations: evaluations,
      options: options,
      providerFailures: providerFailures,
      compilationFailures: compilationFailures
    )
  }

  private func validCandidateIDs(
    _ candidates: [SurfaceRouteCandidate]
  ) -> Bool {
    let ids = candidates.map(\.id)
    let normalizedIDs = ids.map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return zip(ids, normalizedIDs).allSatisfy {
      !$0.1.isEmpty && $0.0 == $0.1
    } && Set(normalizedIDs).count == normalizedIDs.count
  }

  private static func fastestThenShortest(
    _ lhs: ReleasedSurfaceEgressPlanningOption,
    _ rhs: ReleasedSurfaceEgressPlanningOption
  ) -> Bool {
    let lhsLeg = lhs.journeyPlan.egressLeg
    let rhsLeg = rhs.journeyPlan.egressLeg
    if lhsLeg?.expectedTravelTimeSeconds
      != rhsLeg?.expectedTravelTimeSeconds
    {
      return (lhsLeg?.expectedTravelTimeSeconds ?? .infinity)
        < (rhsLeg?.expectedTravelTimeSeconds ?? .infinity)
    }
    if lhsLeg?.distanceMeters != rhsLeg?.distanceMeters {
      return (lhsLeg?.distanceMeters ?? .infinity)
        < (rhsLeg?.distanceMeters ?? .infinity)
    }
    if lhs.policyID != rhs.policyID {
      return lhs.policyID < rhs.policyID
    }
    return lhs.candidateID < rhs.candidateID
  }
}
