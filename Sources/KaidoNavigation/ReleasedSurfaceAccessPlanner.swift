import Foundation
import KaidoSurfaceRouting

public enum ReleasedSurfaceAccessPlanningDisposition: String, Equatable, Sendable {
  case ready = "READY"
  case selectionRequired = "SELECTION_REQUIRED"
  case rejected = "REJECTED"
  case providerFailure = "PROVIDER_FAILURE"
  case invalidResponse = "INVALID_RESPONSE"
}

public struct ReleasedSurfaceAccessPlanningOption: Equatable, Sendable {
  public let candidateID: String
  public let journeyPlan: JourneyPlan

  package init(candidateID: String, journeyPlan: JourneyPlan) {
    self.candidateID = candidateID
    self.journeyPlan = journeyPlan
  }
}

public struct ReleasedSurfaceAccessCompilationFailure: Equatable, Sendable {
  public let candidateID: String
  public let error: JourneyPlanCompilerError

  package init(candidateID: String, error: JourneyPlanCompilerError) {
    self.candidateID = candidateID
    self.error = error
  }
}

/// One complete provider response reduced through release-owned hard gates.
///
/// A single accepted candidate becomes `ready`. Multiple accepted candidates
/// remain `selectionRequired`; provider array order never chooses a journey.
public struct ReleasedSurfaceAccessPlanningResult: Equatable, Sendable {
  public let disposition: ReleasedSurfaceAccessPlanningDisposition
  public let providerFailure: SurfaceProviderFailure?
  public let evaluations: [SurfaceCandidateEvaluation]
  public let options: [ReleasedSurfaceAccessPlanningOption]
  public let compilationFailures: [ReleasedSurfaceAccessCompilationFailure]

  package init(
    disposition: ReleasedSurfaceAccessPlanningDisposition,
    providerFailure: SurfaceProviderFailure? = nil,
    evaluations: [SurfaceCandidateEvaluation],
    options: [ReleasedSurfaceAccessPlanningOption] = [],
    compilationFailures: [ReleasedSurfaceAccessCompilationFailure] = []
  ) {
    self.disposition = disposition
    self.providerFailure = providerFailure
    self.evaluations = evaluations
    self.options = options
    self.compilationFailures = compilationFailures
  }

  public var selectedPlan: JourneyPlan? {
    guard disposition == .ready, options.count == 1 else { return nil }
    return options[0].journeyPlan
  }
}

/// Runs one released surface request through the exact provider, graph
/// inspection, hard gates, and immutable JourneyPlan compiler.
public struct ReleasedSurfaceAccessPlanner<Provider, Inspector>: Sendable
where
  Provider: ReleaseBoundSurfaceRouteProvider,
  Inspector: SurfaceApproachCandidateInspector
{
  public let provider: Provider
  public let inspector: Inspector

  public init(provider: Provider, inspector: Inspector) {
    self.provider = provider
    self.inspector = inspector
  }

  public func plan(
    release: KaidoProductRelease,
    request: SurfaceRouteRequest,
    finishPolicy: JourneyFinishPolicy
  ) async throws -> ReleasedSurfaceAccessPlanningResult {
    let definition = try JourneyPlanCompiler.surfaceAccessPreflight(
      release: release,
      request: request,
      providerIdentity: provider.releaseIdentity,
      finishPolicy: finishPolicy
    )
    let response = await provider.routes(for: request)
    switch response {
    case .failure(let failure):
      return ReleasedSurfaceAccessPlanningResult(
        disposition: .providerFailure,
        providerFailure: failure,
        evaluations: [SurfaceHardGateEvaluator.disclosedFailure(failure)]
      )

    case .success(let candidates) where candidates.isEmpty:
      return ReleasedSurfaceAccessPlanningResult(
        disposition: .invalidResponse,
        evaluations: [SurfaceHardGateEvaluator.invalidEmptySuccess()]
      )

    case .success(let candidates):
      let candidateIDs = candidates.map(\.id)
      let normalizedCandidateIDs = candidateIDs.map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      let candidateIDsAreCanonical = zip(
        candidateIDs,
        normalizedCandidateIDs
      ).allSatisfy { pair in
        !pair.1.isEmpty && pair.0 == pair.1
      }
      guard
        candidateIDsAreCanonical,
        Set(normalizedCandidateIDs).count == normalizedCandidateIDs.count
      else {
        return ReleasedSurfaceAccessPlanningResult(
          disposition: .invalidResponse,
          evaluations: [
            SurfaceHardGateEvaluator.invalidResponse(
              reasonCodes: ["INVALID_OR_DUPLICATE_CANDIDATE_ID"]
            )
          ]
        )
      }

      var evaluations: [SurfaceCandidateEvaluation] = []
      var options: [ReleasedSurfaceAccessPlanningOption] = []
      var compilationFailures: [ReleasedSurfaceAccessCompilationFailure] = []
      for candidate in candidates {
        let inspection = await inspector.inspect(
          candidate: candidate,
          request: request,
          policy: definition.approachPolicy
        )
        let evaluation = SurfaceHardGateEvaluator.evaluate(
          candidate: candidate,
          request: request,
          policy: definition.approachPolicy,
          inspection: inspection,
          expectedProviderID: provider.releaseIdentity.providerID
        )
        evaluations.append(evaluation)
        guard evaluation.isAccepted else { continue }
        do {
          let journeyPlan = try JourneyPlanCompiler.surfaceAccess(
            release: release,
            request: request,
            candidate: candidate,
            inspection: inspection,
            providerIdentity: provider.releaseIdentity,
            finishPolicy: finishPolicy
          )
          options.append(
            ReleasedSurfaceAccessPlanningOption(
              candidateID: candidate.id,
              journeyPlan: journeyPlan
            )
          )
        } catch let error as JourneyPlanCompilerError {
          compilationFailures.append(
            ReleasedSurfaceAccessCompilationFailure(
              candidateID: candidate.id,
              error: error
            )
          )
        }
      }

      options.sort { $0.candidateID < $1.candidateID }
      compilationFailures.sort { $0.candidateID < $1.candidateID }
      let disposition: ReleasedSurfaceAccessPlanningDisposition =
        switch options.count {
        case 0:
          .rejected
        case 1:
          .ready
        default:
          .selectionRequired
        }
      return ReleasedSurfaceAccessPlanningResult(
        disposition: disposition,
        evaluations: evaluations,
        options: options,
        compilationFailures: compilationFailures
      )
    }
  }
}
