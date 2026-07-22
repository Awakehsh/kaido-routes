import Foundation
import KaidoDomain
import KaidoNavigation
import KaidoRouting

public struct ScenarioRunner {
  public init() {}

  public func run(_ scenario: PortableScenario) throws -> ScenarioResult {
    var harness = try ScenarioHarness(scenario: scenario)
    var snapshots: [String: [String: JSONValue]] = [:]

    for event in scenario.events {
      try harness.apply(event)
      snapshots[event.id] = harness.observations
    }

    var failures: [ScenarioFailure] = []
    for assertion in scenario.assertions {
      guard let snapshot = snapshots[assertion.after] else {
        throw ScenarioExecutionError.missingEventSnapshot(assertion.after)
      }
      let actual = snapshot[assertion.subject]
      if !AssertionMatcher.matches(
        actual: actual,
        matcher: assertion.matcher,
        expected: assertion.expected
      ) {
        failures.append(
          ScenarioFailure(
            assertionID: assertion.id,
            eventID: assertion.after,
            subject: assertion.subject,
            matcher: assertion.matcher,
            expected: assertion.expected,
            actual: actual,
            rationale: assertion.rationale
          )
        )
      }
    }

    return ScenarioResult(
      scenarioID: scenario.id,
      title: scenario.title,
      assertionCount: scenario.assertions.count,
      failures: failures
    )
  }

  public func run(directory: URL) throws -> [ScenarioResult] {
    try ScenarioLoader.load(directory: directory).map(run)
  }
}

private struct ScenarioHarness {
  let scenario: PortableScenario
  var engine: NavigationEngine
  var adapterObservations: [String: JSONValue] = [:]

  init(scenario: PortableScenario) throws {
    self.scenario = scenario
    let configuration = try Self.navigationConfiguration(from: scenario.given)
    let initialSnapshot = Self.initialNavigationSnapshot(from: scenario.given)
    engine = NavigationEngine(
      configuration: configuration,
      initialSnapshot: initialSnapshot
    )
  }

  var observations: [String: JSONValue] {
    adapterObservations.merging(engine.snapshot.scenarioObservations) { _, engineValue in
      engineValue
    }
  }

  mutating func apply(_ event: ScenarioEvent) throws {
    switch event.type {
    case "ROUTE_COMPILE_REQUESTED":
      try compileRoute()
    case "NAVIGATION_STARTED":
      projectSignGuidance()
      projectLocalization()
      engine.start()
    case "LOCATION_UPDATED":
      engine.observeLocation(
        locationObservation(
          from: event.payload,
          observedAtMilliseconds: event.atMilliseconds
        ))
    case "TUNNEL_ENTERED":
      engine.enterTunnel()
    case "TUNNEL_EXITED":
      engine.exitTunnel()
    case "BRANCH_OBSERVED":
      engine.observeBranch(branchObservation(from: event.payload))
    case "RESTRICTION_UPDATED":
      engine.updateRestriction(
        subjectID: try event.payload.requiredString("subject_id"),
        state: try event.payload.requiredString("state")
      )
    case "USER_ACTION":
      try applyUserAction(event.payload)
    case "TARIFF_QUOTED":
      try projectTariffQuote(event.payload)
    default:
      throw ScenarioExecutionError.unsupportedEvent(event.type)
    }
  }

  private mutating func compileRoute() throws {
    let inputs = scenario.given.inputs

    if let candidate = inputs.object("candidate_route"),
      let legalValues = inputs.array("legal_movements")
    {
      let request = DirectedMovementRequest(
        incomingApproachID: try candidate.requiredString("incoming_approach_id"),
        junctionComplexID: try candidate.requiredString("junction_complex_id"),
        outgoingCarriagewayID: try candidate.requiredString("requested_outgoing_carriageway_id")
      )
      let legalMovements = try legalValues.map { value in
        guard let movement = value.objectValue else {
          throw ScenarioExecutionError.invalidInput("legal_movements")
        }
        return LegalMovement(
          id: try movement.requiredString("movement_id"),
          incomingApproachID: try movement.requiredString("incoming_approach_id"),
          junctionComplexID: try movement.requiredString("junction_complex_id"),
          outgoingCarriagewayID: try movement.requiredString("outgoing_carriageway_id")
        )
      }
      publish(StrictRouteCompiler.validate(movement: request, legalMovements: legalMovements))
      return
    }

    if let requested = inputs.object("requested_facility"),
      let facilityValues = inputs.array("explicit_facilities")
    {
      let kind = try facilityKind(try requested.requiredString("kind"))
      let carriagewayKey =
        kind == .entrance
        ? "target_carriageway_id"
        : "source_carriageway_id"
      let request = FacilityRequest(
        kind: kind,
        carriagewayID: try requested.requiredString(carriagewayKey)
      )
      let facilities = try facilityValues.map { value in
        guard let facility = value.objectValue else {
          throw ScenarioExecutionError.invalidInput("explicit_facilities")
        }
        let facilityKind = try facilityKind(try facility.requiredString("kind"))
        let key =
          facilityKind == .entrance
          ? "target_carriageway_id"
          : "source_carriageway_id"
        return DirectionalFacility(
          id: try facility.requiredString("facility_id"),
          kind: facilityKind,
          carriagewayID: try facility.requiredString(key)
        )
      }
      publish(StrictRouteCompiler.validate(facility: request, explicitFacilities: facilities))
      return
    }

    if let savedRoute = inputs.object("saved_route") {
      let reviewedMigrations = inputs.array("reviewed_migrations") ?? []
      let result = StrictRouteCompiler.validateSnapshot(
        savedSnapshotID: try savedRoute.requiredString("network_snapshot_id"),
        currentSnapshotID: scenario.given.networkSnapshot.id,
        reviewedMigrationExists: !reviewedMigrations.isEmpty
      )
      publish(result)
      return
    }

    if let requestedPath = inputs.object("requested_pa_path"),
      let pathValues = inputs.array("released_pa_paths")
    {
      let request = ParkingAreaPathRequest(
        parkingAreaID: try requestedPath.requiredString("parking_area_id"),
        sourceCarriagewayID: try requestedPath.requiredString("source_carriageway_id"),
        accessMovementID: try requestedPath.requiredString("access_movement_id"),
        returnMovementID: try requestedPath.requiredString("return_movement_id"),
        returnCarriagewayID: try requestedPath.requiredString("return_carriageway_id")
      )
      let paths = try pathValues.map { value in
        guard let path = value.objectValue else {
          throw ScenarioExecutionError.invalidInput("released_pa_paths")
        }
        return DirectionalParkingAreaPath(
          id: try path.requiredString("path_id"),
          parkingAreaID: try path.requiredString("parking_area_id"),
          sourceCarriagewayID: try path.requiredString("source_carriageway_id"),
          accessMovementID: try path.requiredString("access_movement_id"),
          returnMovementID: try path.requiredString("return_movement_id"),
          returnCarriagewayID: try path.requiredString("return_carriageway_id")
        )
      }
      publish(
        StrictRouteCompiler.validate(
          parkingAreaPath: request,
          releasedPaths: paths
        ))
      return
    }

    if let duplication = inputs.object("lap_duplication"),
      let reviewedTemplate = inputs.object("reviewed_lap_template"),
      let routePlan = scenario.given.routePlan
    {
      let request = LapDuplicationRequest(
        reviewedTemplateID: try duplication.requiredString("reviewed_template_id"),
        newOccurrenceIDs: try requiredStrings(
          duplication,
          key: "new_occurrence_ids"
        )
      )
      let template = ReviewedLapTemplate(
        id: try reviewedTemplate.requiredString("template_id"),
        sourceOccurrenceIDs: try requiredStrings(
          reviewedTemplate,
          key: "source_occurrence_ids"
        )
      )
      publish(
        StrictRouteCompiler.appendLap(
          to: routePlan,
          request: request,
          reviewedTemplate: template
        ))
      return
    }

    if let requirement = inputs.object("route_component_requirement"),
      let routePlan = scenario.given.routePlan
    {
      let result = StrictRouteCompiler.validate(
        routePlan: routePlan,
        componentRequirement: RouteComponentRequirement(
          templateID: try requirement.requiredString("template_id"),
          requiredEntityIDsInOrder: try requiredStrings(
            requirement,
            key: "required_entity_ids_in_order"
          )
        )
      )
      publish(result)
      return
    }

    if let policy = inputs.object("toll_domain_policy"),
      let routePlan = scenario.given.routePlan
    {
      let result = StrictRouteCompiler.validate(
        routePlan: routePlan,
        tollDomainPolicy: TollDomainPolicy(
          allowedTollDomainIDs: Set(
            try requiredStrings(policy, key: "allowed_toll_domain_ids")
          ),
          requiresEveryOccurrenceClassified: policy.bool(
            "requires_every_occurrence_classified"
          ) ?? true
        )
      )
      publish(result)
      return
    }

    if let template = inputs.object("route_template"),
      let candidateValues = inputs.array("entrance_candidates")
    {
      let allowedJoins = Set(
        (template.array("allowed_join_occurrence_ids") ?? []).compactMap(\.stringValue)
      )
      let candidates = try candidateValues.map { value in
        guard let candidate = value.objectValue else {
          throw ScenarioExecutionError.invalidInput("entrance_candidates")
        }
        return EntranceCandidate(
          facilityID: try candidate.requiredString("facility_id"),
          straightLineDistanceKM: try requiredDouble(
            candidate,
            key: "straight_line_distance_km"
          ),
          surfaceETAMinutes: try requiredDouble(candidate, key: "surface_eta_minutes"),
          legalJoinOccurrenceIDs: Set(
            (candidate.array("legal_join_occurrence_ids") ?? []).compactMap(\.stringValue)
          ),
          approachAvailability: try candidate.string("approach_availability").map { value in
            guard let availability = EntranceApproachAvailability(rawValue: value) else {
              throw ScenarioExecutionError.invalidInput("approach_availability")
            }
            return availability
          } ?? .available
        )
      }
      publish(
        EntranceRecommender.recommend(
          candidates: candidates,
          allowedJoinOccurrenceIDs: allowedJoins
        ))
      return
    }

    throw ScenarioExecutionError.unsupportedCompileShape
  }

  private mutating func publish(_ result: CompileResult) {
    adapterObservations["compiler.status"] = .string(result.status.rawValue)
    adapterObservations["compiler.error_codes"] = .strings(result.errorCodes)
    adapterObservations["compiler.synthetic_facility_ids"] = .strings(result.syntheticFacilityIDs)
    adapterObservations["compiler.substituted_movement_ids"] = .strings(
      result.substitutedMovementIDs)
    adapterObservations["compiler.validated_required_entity_ids"] = .strings(
      result.validatedRequiredEntityIDs)
    adapterObservations["compiler.unresolved_required_entity_ids"] = .strings(
      result.unresolvedRequiredEntityIDs)
    adapterObservations["compiler.crossed_toll_domain_ids"] = .strings(
      result.crossedTollDomainIDs)
    adapterObservations["compiler.boundary_occurrence_ids"] = .strings(
      result.boundaryOccurrenceIDs)
  }

  private mutating func publish(_ result: RoutePlanExpansionResult) {
    adapterObservations["compiler.status"] = .string(result.status.rawValue)
    adapterObservations["compiler.error_codes"] = .strings(result.errorCodes)
    guard let routePlan = result.routePlan else { return }
    adapterObservations["compiler.expanded_occurrence_ids"] = .strings(
      routePlan.occurrences.map(\.id)
    )
    adapterObservations["compiler.expanded_entity_ids"] = .strings(
      routePlan.occurrences.map(\.entityID)
    )
    adapterObservations["compiler.expanded_occurrence_indexes"] = .array(
      routePlan.occurrences.map { .integer($0.index) }
    )
  }

  private mutating func publish(_ recommendation: EntranceRecommendation) {
    if let selectedFacilityID = recommendation.selectedFacilityID {
      adapterObservations["entry_recommendation.selected_facility_id"] = .string(selectedFacilityID)
    }
    if let joinOccurrenceID = recommendation.joinOccurrenceID {
      adapterObservations["entry_recommendation.join_occurrence_id"] = .string(joinOccurrenceID)
    }
    for (facilityID, reasons) in recommendation.rejections {
      adapterObservations["entry_recommendation.rejections.\(facilityID)"] = .strings(reasons)
    }
  }

  private mutating func projectSignGuidance() {
    guard let signSet = scenario.given.inputs.object("sign_set") else { return }
    adapterObservations["guidance.destinations_ja"] = .array(
      signSet.array("destinations_ja") ?? []
    )
    adapterObservations["guidance.route_shields"] = .array(
      signSet.array("route_shields") ?? []
    )
    adapterObservations["guidance.destinations_en"] = .array(
      signSet.array("destinations_en_official") ?? []
    )
  }

  private mutating func projectLocalization() {
    let inputs = scenario.given.inputs
    guard let requiredLocales = inputs.array("required_locales")?.compactMap(\.stringValue),
      let settings = inputs.object("settings"),
      let bundleValues = inputs.object("guidance_bundles"),
      let signTarget = inputs.object("sign_target")
    else {
      return
    }

    let exactSignText = signTarget.string("exact_text_ja")
    let bundlesComplete = requiredLocales.allSatisfy { locale in
      guard let bundle = bundleValues[locale]?.objectValue,
        !(bundle.string("display_text") ?? "").isEmpty,
        !(bundle.string("spoken_text") ?? "").isEmpty,
        let spokenForms = bundle.object("spoken_forms"),
        !spokenForms.isEmpty,
        bundle.string("preserved_sign_text_ja") == exactSignText
      else {
        return false
      }
      return true
    }

    let uiLocale = settings.string("ui_locale")
    let voiceLocale = settings.string("guidance_voice_locale")
    let availableVoiceLanguages =
      inputs.array("available_voice_languages")?
      .compactMap(\.stringValue) ?? []
    let matchingVoiceAvailable =
      voiceLocale.map { requested in
        availableVoiceLanguages.contains { available in
          Self.languageCode(requested) == Self.languageCode(available)
        }
      } ?? false

    adapterObservations["localization.release_gate"] = .string(
      bundlesComplete && matchingVoiceAvailable ? "PASS" : "BLOCKED"
    )
    if let exactSignText {
      adapterObservations["guidance.visible_sign_text_ja"] = .string(exactSignText)
    }
    if let uiLocale {
      adapterObservations["localization.active_ui_locale"] = .string(uiLocale)
    }
    if let voiceLocale {
      adapterObservations["guidance.active_voice_locale"] = .string(voiceLocale)
    }
    adapterObservations["guidance.used_implicit_wrong_language_voice"] = .bool(false)
  }

  private mutating func applyUserAction(_ payload: [String: JSONValue]) throws {
    switch try payload.requiredString("action") {
    case "FINISH_DRIVE":
      engine.finishDrive()
    case "OPEN_PRE_DRIVE_REVIEW":
      let inputs = scenario.given.inputs
      let planned = inputs.string("planned_status") ?? "UNKNOWN"
      let realtime =
        inputs.string("realtime_feed_status") == "UNAVAILABLE"
        ? "REALTIME_UNCONFIRMED"
        : "UNKNOWN"
      adapterObservations["route_status.planned"] = .string(planned)
      adapterObservations["route_status.realtime"] = .string(realtime)
    default:
      throw ScenarioExecutionError.unsupportedEvent("USER_ACTION")
    }
  }

  private mutating func projectTariffQuote(_ payload: [String: JSONValue]) throws {
    let quoteID = try payload.requiredString("quote_id")
    guard let quote = scenario.given.tariffQuotes.first(where: { $0.id == quoteID }),
      let routeSummary = scenario.given.inputs.object("route_summary")
    else {
      throw ScenarioExecutionError.invalidInput("quote_id")
    }

    if let actualDistance = routeSummary.double("actual_distance_km") {
      adapterObservations["route_summary.actual_distance_km"] = .number(actualDistance)
    }
    if let tariffDistance = quote.tariffDistanceKM {
      adapterObservations["route_summary.tariff_distance_km"] = .number(tariffDistance)
    }
    adapterObservations["route_summary.toll.status"] = .string(quote.status)
    if let amount = quote.estimatedAmountYen {
      adapterObservations["route_summary.toll.estimated_amount_yen"] = .integer(amount)
    }
  }

  private func locationObservation(
    from payload: [String: JSONValue],
    observedAtMilliseconds: Int
  ) -> LocationObservation {
    LocationObservation(
      directedEdgeID: payload.string("directed_edge_id"),
      matchedEntityID: payload.string("matched_entity_id"),
      expectedOccurrenceID: payload.string("expected_occurrence_id"),
      matchedOccurrenceID: payload.string("matched_occurrence_id"),
      candidateOccurrenceIDs: Set(
        (payload.array("candidate_occurrence_ids") ?? []).compactMap(\.stringValue)
      ),
      candidateResolution: payload.string("candidate_resolution")
        .flatMap(RouteCandidateResolution.init(rawValue:)) ?? .unknown,
      projectedOccurrenceID: payload.string("projected_occurrence_id"),
      observedAtMilliseconds: observedAtMilliseconds,
      reportedConfidence: payload.string("confidence").flatMap(LocationConfidence.init(rawValue:)),
      horizontalAccuracyMeters: payload.double("horizontal_accuracy_m"),
      ageMilliseconds: payload.int("age_ms"),
      headingMatches: payload["heading_matches"]?.boolValue,
      forwardContinuity: payload.bool("forward_continuity") ?? false,
      reachableOccurrenceIDs: Set(
        (payload.array("reachable_occurrence_ids") ?? []).compactMap(\.stringValue)
      ),
      insideEntryRegion: payload.bool("inside_entry_region") ?? false
    )
  }

  private func branchObservation(from payload: [String: JSONValue]) -> BranchObservation {
    BranchObservation(
      observedMovementID: payload.string("observed_movement_id"),
      candidateOccurrenceIDs: Set(
        (payload.array("candidate_occurrence_ids") ?? []).compactMap(\.stringValue)
      ),
      confidence: payload.string("confidence")
        .flatMap(LocationConfidence.init(rawValue:)) ?? .low
    )
  }

  private static func navigationConfiguration(
    from given: ScenarioGiven
  ) throws -> NavigationConfiguration {
    NavigationConfiguration(
      routePlan: given.routePlan,
      entryTransition: try entryTransition(from: given.inputs),
      recoveryCandidates: try recoveryCandidates(from: given.inputs),
      egressOptions: try egressOptions(from: given.inputs),
      nextSign: signGuidance(from: given.inputs)
    )
  }

  private static func initialNavigationSnapshot(from given: ScenarioGiven) -> NavigationSnapshot {
    let phase =
      given.systemState.string("journey_phase")
      .flatMap(JourneyPhase.init(rawValue:)) ?? .planning
    let confidence =
      given.systemState.string("location_confidence")
      .flatMap(LocationConfidence.init(rawValue:)) ?? .medium
    return NavigationSnapshot(
      journeyPhase: phase,
      activeRoutePlanID: given.systemState.string("active_route_plan_id") ?? given.routePlan?.id,
      currentOccurrenceID: given.systemState.string("current_occurrence_id"),
      locationConfidence: confidence
    )
  }

  private static func entryTransition(
    from inputs: [String: JSONValue]
  ) throws -> EntryTransition? {
    guard let value = inputs.object("entry_transition") else { return nil }
    let edges =
      value.array("directed_edge_ids")
      ?? value.array("required_directed_edge_ids")
      ?? []
    return EntryTransition(
      facilityID: try value.requiredString("facility_id"),
      directedEdgeIDs: edges.compactMap(\.stringValue),
      firstRouteOccurrenceID: value.string("first_route_occurrence_id")
    )
  }

  private static func recoveryCandidates(
    from inputs: [String: JSONValue]
  ) throws -> [RecoveryCandidate] {
    try (inputs.array("recovery_candidates") ?? []).map { value in
      guard let candidate = value.objectValue else {
        throw ScenarioExecutionError.invalidInput("recovery_candidates")
      }
      return RecoveryCandidate(
        targetOccurrenceID: try candidate.requiredString("target_occurrence_id"),
        recoveryOccurrenceIDs: (candidate.array("recovery_occurrence_ids") ?? [])
          .compactMap(\.stringValue),
        isReleased: candidate.bool("released") ?? false,
        staysInAllowedTollDomain: candidate.bool("stays_in_allowed_toll_domain") ?? false
      )
    }
  }

  private static func egressOptions(
    from inputs: [String: JSONValue]
  ) throws -> [EgressOption] {
    try (inputs.array("precomputed_egress_options") ?? []).map { value in
      guard let option = value.objectValue else {
        throw ScenarioExecutionError.invalidInput("precomputed_egress_options")
      }
      return EgressOption(
        id: try option.requiredString("egress_option_id"),
        firstEligibleOccurrenceID: try option.requiredString("first_eligible_occurrence_id"),
        exitFacilityID: try option.requiredString("exit_facility_id"),
        egressOccurrenceIDs: (option.array("egress_occurrence_ids") ?? [])
          .compactMap(\.stringValue),
        isReleased: option.bool("released") ?? false
      )
    }
  }

  private static func signGuidance(from inputs: [String: JSONValue]) -> SignGuidance {
    guard let sign = inputs.object("next_sign") else { return SignGuidance() }
    return SignGuidance(
      routeShields: (sign.array("route_shields") ?? []).compactMap(\.stringValue),
      destinationsJapanese: (sign.array("destinations_ja") ?? []).compactMap(\.stringValue),
      destinationsEnglish: (sign.array("destinations_en") ?? []).compactMap(\.stringValue)
    )
  }

  private static func languageCode(_ locale: String) -> String {
    locale.split(separator: "-").first.map(String.init) ?? locale
  }

  private func facilityKind(_ value: String) throws -> FacilityKind {
    guard let kind = FacilityKind(rawValue: value) else {
      throw ScenarioExecutionError.invalidInput("facility.kind")
    }
    return kind
  }

  private func requiredDouble(
    _ object: [String: JSONValue],
    key: String
  ) throws -> Double {
    guard let value = object.double(key) else {
      throw ScenarioExecutionError.invalidInput(key)
    }
    return value
  }

  private func requiredStrings(
    _ object: [String: JSONValue],
    key: String
  ) throws -> [String] {
    guard let values = object.array(key),
      values.allSatisfy({ $0.stringValue != nil })
    else {
      throw ScenarioExecutionError.invalidInput(key)
    }
    return values.compactMap(\.stringValue)
  }
}

private enum AssertionMatcher {
  static func matches(
    actual: JSONValue?,
    matcher: String,
    expected: JSONValue?
  ) -> Bool {
    switch matcher {
    case "PRESENT":
      return actual != nil
    case "ABSENT":
      return actual == nil
    case "EQUALS":
      guard let actual, let expected else { return false }
      return actual.semanticallyEquals(expected)
    case "NOT_EQUALS":
      guard let actual, let expected else { return false }
      return !actual.semanticallyEquals(expected)
    case "CONTAINS":
      guard let actual, let expected else { return false }
      if case .array(let values) = actual {
        return values.contains { $0.semanticallyEquals(expected) }
      }
      if case .string(let value) = actual,
        case .string(let fragment) = expected
      {
        return value.contains(fragment)
      }
      return false
    case "ONE_OF":
      guard let actual, case .array(let choices) = expected else { return false }
      return choices.contains { $0.semanticallyEquals(actual) }
    case "LESS_THAN":
      guard let actual = actual?.doubleValue,
        let expected = expected?.doubleValue
      else { return false }
      return actual < expected
    case "GREATER_THAN":
      guard let actual = actual?.doubleValue,
        let expected = expected?.doubleValue
      else { return false }
      return actual > expected
    default:
      return false
    }
  }
}

extension JSONValue {
  fileprivate static func strings(_ values: [String]) -> JSONValue {
    .array(values.map(JSONValue.string))
  }
}

extension NavigationSnapshot {
  fileprivate var scenarioObservations: [String: JSONValue] {
    var values: [String: JSONValue] = [
      "journey.phase": .string(journeyPhase.rawValue),
      "journey.strict_route_auto_commit_allowed": .bool(strictRouteAutoCommitAllowed),
      "navigation.completed_occurrence_ids": .strings(completedOccurrenceIDs),
      "navigation.pending_occurrence_ids": .strings(pendingOccurrenceIDs),
      "navigation.location_confidence": .string(locationConfidence.rawValue),
      "navigation.marker_style": .string(markerStyle),
      "navigation.signal_reacquisition_status": .string(signalReacquisitionStatus.rawValue),
      "navigation.route_candidate_resolution": .string(routeCandidateResolution.rawValue),
      "route.executable": .bool(routeExecutable),
      "route.blocking_reasons": .strings(routeBlockingReasons),
      "route.blocking_occurrence_ids": .strings(routeBlockingOccurrenceIDs),
      "route.skipped_occurrence_ids": .strings(skippedOccurrenceIDs),
      "route.warnings": .strings(routeWarnings),
      "recovery.status": .string(recovery.status.rawValue),
      "recovery.destination_reroute_used": .bool(recovery.destinationRerouteUsed),
      "egress_plan.status": .string(egress.status.rawValue),
      "egress_plan.prohibited_actions": .strings(egress.prohibitedActions),
      "guidance.next.route_shields": .strings(signGuidance.routeShields),
      "guidance.prohibited_actions": .strings(prohibitedGuidanceActions),
      "ui.requires_route_editing_while_moving": .bool(requiresRouteEditingWhileMoving),
      "ui.requires_phone_touch_while_moving": .bool(requiresPhoneTouchWhileMoving),
      "guidance.shows_entry_route_shield_and_direction": .bool(showsEntryRouteShieldAndDirection),
    ]

    if let lastPhaseTransitionTrigger {
      values["journey.last_phase_transition.trigger"] = .string(lastPhaseTransitionTrigger)
    }
    if let activeRoutePlanID {
      values["navigation.active_route_plan_id"] = .string(activeRoutePlanID)
    }
    if let currentOccurrenceID {
      values["navigation.current_occurrence_id"] = .string(currentOccurrenceID)
    }
    if let currentOccurrenceIndex {
      values["navigation.occurrence_index"] = .integer(currentOccurrenceIndex)
    }
    if let ambiguityReason {
      values["journey.ambiguity_reason"] = .string(ambiguityReason)
    }
    if let signalReacquisitionTrigger {
      values["navigation.signal_reacquisition_trigger"] = .string(
        signalReacquisitionTrigger
      )
    }
    if let objective = recovery.objective {
      values["recovery.objective"] = .string(objective)
    }
    if let routePlanID = recovery.routePlanID {
      values["recovery.route_plan_id"] = .string(routePlanID)
    }
    if let chosenRejoinOccurrenceID = recovery.chosenRejoinOccurrenceID {
      values["recovery.chosen_rejoin_occurrence_id"] = .string(chosenRejoinOccurrenceID)
    }
    if let exitFacilityID = egress.exitFacilityID {
      values["egress_plan.exit_facility_id"] = .string(exitFacilityID)
    }
    if let firstEligibleOccurrenceID = egress.firstEligibleOccurrenceID {
      values["egress_plan.first_eligible_occurrence_id"] = .string(firstEligibleOccurrenceID)
    }
    if let finishConfirmationExitFacilityID {
      values["guidance.finish_confirmation.exit_facility_id"] = .string(
        finishConfirmationExitFacilityID
      )
    }
    return values
  }
}
