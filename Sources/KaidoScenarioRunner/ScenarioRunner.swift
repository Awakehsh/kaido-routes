import Foundation
import KaidoDomain
import KaidoNavigation
import KaidoPresentation
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
  var matcherSession: RouteMatcherSession?
  var matcherCorridor: RouteMatcherCorridor?
  var routeEditorSession: ExpertRouteEditorSession?
  var lastGuidancePromptEmission: GuidancePromptEmission?
  var adapterObservations: [String: JSONValue] = [:]

  init(scenario: PortableScenario) throws {
    self.scenario = scenario
    let configuration = try Self.navigationConfiguration(from: scenario.given)
    let initialSnapshot = Self.initialNavigationSnapshot(from: scenario.given)
    engine = NavigationEngine(
      configuration: configuration,
      initialSnapshot: initialSnapshot
    )
    matcherSession = nil
    matcherCorridor = nil
    routeEditorSession = nil
    lastGuidancePromptEmission = nil
  }

  var observations: [String: JSONValue] {
    adapterObservations.merging(engine.snapshot.scenarioObservations) { _, engineValue in
      engineValue
    }
  }

  mutating func apply(_ event: ScenarioEvent) throws {
    lastGuidancePromptEmission = nil
    switch event.type {
    case "ROUTE_COMPILE_REQUESTED":
      try compileRoute(event.payload)
    case "ROUTE_EDITOR_STARTED":
      try startRouteEditor(event.payload)
    case "ROUTE_EDITOR_CHOICE_SELECTED":
      try selectRouteEditorChoice(event.payload)
    case "ROUTE_EDITOR_LAP_DUPLICATION_REQUESTED":
      try duplicateRouteEditorLap(event.payload)
    case "ROUTE_EDITOR_UNDO_REQUESTED":
      try undoRouteEditorChoice(event.payload)
    case "ROUTE_EDITOR_COMPILE_REQUESTED":
      try compileRouteEditor(event.payload)
    case "NAVIGATION_RELEASE_BUNDLE_VALIDATED":
      try validateNavigationReleaseBundle()
    case "ROUTE_ATLAS_RELEASE_VALIDATED":
      try validateRouteAtlasRelease()
    case "ROUTE_ATLAS_CONTEXT_VALIDATED":
      try validateRouteAtlasContext()
    case "NAVIGATION_STARTED":
      projectSignGuidance()
      projectLocalization()
      engine.start()
    case "LOCATION_UPDATED":
      engine.observeLocation(
        locationObservation(
          from: event.payload,
          observedAtMilliseconds: event.payload.int("observed_at_ms")
            ?? event.atMilliseconds
        ))
    case "MATCHER_SESSION_STARTED":
      try startMatcherSession(event.payload)
    case "MATCHER_OBSERVATION_RECEIVED":
      try receiveMatcherObservation(event.payload)
    case "MATCHER_SESSION_RESET":
      try resetMatcherSession(event.payload)
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
    case "TARIFF_SELECTION_REQUESTED":
      try selectTariff(event.payload)
    case "GUIDANCE_ANCHOR_REACHED":
      engine.reachGuidanceAnchor(
        occurrenceID: try event.payload.requiredString("occurrence_id"),
        anchorID: try event.payload.requiredString("anchor_id")
      )
    case "GUIDANCE_PROGRESS_UPDATED":
      lastGuidancePromptEmission = engine.observeGuidanceProgress(
        GuidanceProgressObservation(
          occurrenceID: try event.payload.requiredString("occurrence_id"),
          distanceToDecisionPointMeters: try requiredDouble(
            event.payload,
            key: "distance_to_decision_point_meters"
          ),
          observedAtMilliseconds: event.payload.int("observed_at_ms")
            ?? event.atMilliseconds
        )
      )
    case "CARPLAY_CONNECTED":
      engine.connectCarPlay()
    case "CARPLAY_DISCONNECTED":
      engine.disconnectCarPlay()
    default:
      throw ScenarioExecutionError.unsupportedEvent(event.type)
    }
    try refreshPresentation()
  }

  private mutating func compileRoute(_ payload: [String: JSONValue]) throws {
    let inputs = scenario.given.inputs

    if let roundTrip = inputs.object("shared_route_round_trip"),
      let routePlan = scenario.given.routePlan
    {
      let parameterValues = roundTrip.object("template_parameters") ?? [:]
      guard parameterValues.values.allSatisfy({ $0.stringValue != nil }) else {
        throw ScenarioExecutionError.invalidInput("template_parameters")
      }
      guard
        let evidenceState = SharedRouteEvidenceState(
          rawValue: try roundTrip.requiredString("evidence_state")
        )
      else {
        throw ScenarioExecutionError.invalidInput("evidence_state")
      }
      let document = SharedRouteDocument(
        schemaVersion: try roundTrip.requiredString("schema_version"),
        evidenceState: evidenceState,
        templateParameters: parameterValues.compactMapValues(\.stringValue),
        routePlan: routePlan
      )
      let exported = try SharedRouteCodec.encode(document)
      publish(try SharedRouteCodec.decode(exported))
      return
    }

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

    if let requests = inputs.object("template_variant_requests"),
      let variantValues = inputs.array("approved_template_variants"),
      let routePlan = scenario.given.routePlan
    {
      let requestID = try payload.requiredString("request_id")
      guard let request = requests.object(requestID) else {
        throw ScenarioExecutionError.invalidInput("request_id")
      }
      let parameters = request.object("parameters") ?? [:]
      guard parameters.values.allSatisfy({ $0.stringValue != nil }) else {
        throw ScenarioExecutionError.invalidInput("parameters")
      }
      let variants = try variantValues.map { value in
        guard let variant = value.objectValue else {
          throw ScenarioExecutionError.invalidInput("approved_template_variants")
        }
        let variantParameters = variant.object("parameters") ?? [:]
        guard variantParameters.values.allSatisfy({ $0.stringValue != nil }) else {
          throw ScenarioExecutionError.invalidInput("approved_template_variants.parameters")
        }
        return ApprovedRouteTemplateVariant(
          id: try variant.requiredString("variant_id"),
          templateID: try variant.requiredString("template_id"),
          networkSnapshotID: try variant.requiredString("network_snapshot_id"),
          parameters: variantParameters.compactMapValues(\.stringValue),
          requiredEntityIDsInOrder: try requiredStrings(
            variant,
            key: "required_entity_ids_in_order"
          )
        )
      }
      publish(
        StrictRouteCompiler.validate(
          routePlan: routePlan,
          templateSelection: RouteTemplateVariantSelection(
            templateID: try request.requiredString("template_id"),
            parameters: parameters.compactMapValues(\.stringValue)
          ),
          approvedVariants: variants
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
          targetCarriagewayID: try candidate.requiredString(
            "target_carriageway_id"
          ),
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

  private mutating func startRouteEditor(_ payload: [String: JSONValue]) throws {
    guard let catalogValue = scenario.given.inputs.object("expert_route_editor_catalog") else {
      throw ScenarioExecutionError.invalidInput("expert_route_editor_catalog")
    }
    let recoveryPolicyValue = try payload.requiredString("recovery_policy")
    guard let recoveryPolicy = RoutePlan.RecoveryPolicy(rawValue: recoveryPolicyValue) else {
      throw ScenarioExecutionError.invalidInput("recovery_policy")
    }
    let catalog = try reviewedRouteEditorCatalog(catalogValue)
    guard catalog.networkSnapshotID == scenario.given.networkSnapshot.id else {
      throw ScenarioExecutionError.invalidInput("expert_route_editor_catalog.network_snapshot_id")
    }
    do {
      let session = try ExpertRouteEditorSession(
        catalog: catalog,
        routePlanID: try payload.requiredString("route_plan_id"),
        entranceFacilityID: try payload.requiredString("entrance_facility_id"),
        initialOccurrenceID: try payload.requiredString("initial_occurrence_id"),
        recoveryPolicy: recoveryPolicy,
        interaction: try routeEditorInteraction(payload)
      )
      routeEditorSession = session
      publish(session.snapshot)
    } catch let error as ExpertRouteEditorError {
      routeEditorSession = nil
      publishRouteEditorError(error)
    }
  }

  private mutating func selectRouteEditorChoice(
    _ payload: [String: JSONValue]
  ) throws {
    guard var session = routeEditorSession else {
      throw ScenarioExecutionError.invalidInput("expert_route_editor_session")
    }
    do {
      try session.select(
        choiceID: try payload.requiredString("choice_id"),
        movementOccurrenceID: try payload.requiredString("movement_occurrence_id"),
        outgoingEdgeOccurrenceID: try payload.requiredString(
          "outgoing_edge_occurrence_id"
        ),
        interaction: try routeEditorInteraction(payload)
      )
      routeEditorSession = session
      publish(session.snapshot)
    } catch let error as ExpertRouteEditorError {
      routeEditorSession = session
      publish(session.snapshot)
      adapterObservations["editor.last_error"] = .string(error.code)
    }
  }

  private mutating func undoRouteEditorChoice(_ payload: [String: JSONValue]) throws {
    guard var session = routeEditorSession else {
      throw ScenarioExecutionError.invalidInput("expert_route_editor_session")
    }
    do {
      try session.undo(interaction: try routeEditorInteraction(payload))
      routeEditorSession = session
      publish(session.snapshot)
    } catch let error as ExpertRouteEditorError {
      routeEditorSession = session
      publish(session.snapshot)
      adapterObservations["editor.last_error"] = .string(error.code)
    }
  }

  private mutating func duplicateRouteEditorLap(
    _ payload: [String: JSONValue]
  ) throws {
    guard var session = routeEditorSession else {
      throw ScenarioExecutionError.invalidInput("expert_route_editor_session")
    }
    do {
      try session.duplicateLap(
        candidateID: try payload.requiredString("lap_candidate_id"),
        newOccurrenceIDs: try requiredStrings(payload, key: "new_occurrence_ids"),
        interaction: try routeEditorInteraction(payload)
      )
      routeEditorSession = session
      publish(session.snapshot)
    } catch let error as ExpertRouteEditorError {
      routeEditorSession = session
      publish(session.snapshot)
      adapterObservations["editor.last_error"] = .string(error.code)
    }
  }

  private mutating func compileRouteEditor(_ payload: [String: JSONValue]) throws {
    guard let session = routeEditorSession else {
      throw ScenarioExecutionError.invalidInput("expert_route_editor_session")
    }
    do {
      let routePlan = try session.makeRoutePlan(
        interaction: try routeEditorInteraction(payload)
      )
      publish(session.snapshot)
      publishCompiledRoutePlan(routePlan)
    } catch let error as ExpertRouteEditorError {
      publish(session.snapshot)
      adapterObservations["editor.last_error"] = .string(error.code)
    }
  }

  private mutating func validateNavigationReleaseBundle() throws {
    guard let routePlan = scenario.given.routePlan,
      let catalogValue = scenario.given.inputs.object("expert_route_editor_catalog"),
      let corridorValue = scenario.given.inputs.object("matcher_corridor"),
      let decisionZoneValues = scenario.given.inputs.array("decision_zones")
    else {
      throw ScenarioExecutionError.invalidInput("navigation_release_bundle")
    }
    let junctionViewValues = scenario.given.inputs.array("junction_views") ?? []
    let catalog = try reviewedRouteEditorCatalog(catalogValue)
    let corridor = try routeMatcherCorridor(corridorValue)
    let decisionZones = try decisionZoneValues.map { value in
      guard let definition = value.objectValue else {
        throw ScenarioExecutionError.invalidInput("decision_zones")
      }
      return try Self.decisionZoneProgressDefinition(definition)
    }
    let junctionViews = try junctionViewValues.map { value in
      guard let definition = value.objectValue,
        let junctionView = try Self.junctionViewDefinition(definition)
      else {
        throw ScenarioExecutionError.invalidInput("junction_views")
      }
      return junctionView
    }
    let releasedGuidance = try Self.releasedGuidance(from: scenario.given.inputs)

    clearReleaseBundleObservations()
    do {
      let bundle = try NavigationReleaseBundle(
        networkSnapshot: scenario.given.networkSnapshot,
        routePlan: routePlan,
        editorCatalog: catalog,
        matcherCorridor: corridor,
        decisionZones: decisionZones,
        releasedGuidance: releasedGuidance,
        junctionViews: junctionViews
      )
      publish(bundle)
    } catch NavigationReleaseBundleError.invalid(let issues) {
      adapterObservations["release_bundle.status"] = .string("BLOCKED")
      adapterObservations["release_bundle.error_codes"] = .strings(
        Array(Set(issues.map(\.code))).sorted()
      )
    }
  }

  private mutating func validateRouteAtlasRelease() throws {
    guard let routePlan = scenario.given.routePlan,
      let sourceValues = scenario.given.inputs.array("route_atlas_sources"),
      let topologyValue = scenario.given.inputs.object("route_atlas_topology"),
      let definitionValue = scenario.given.inputs.object("route_atlas")
    else {
      throw ScenarioExecutionError.invalidInput("route_atlas_release")
    }
    let sourceRegistry = try routeAtlasSourceRegistry(sourceValues)
    let topology = try routeAtlasTopologySlice(topologyValue)
    let definition = try routeAtlasDefinition(definitionValue)

    clearRouteAtlasObservations()
    do {
      let release = try RouteAtlasRelease(
        networkSnapshot: scenario.given.networkSnapshot,
        routePlan: routePlan,
        sourceRegistry: sourceRegistry,
        topologySlice: topology,
        definition: definition
      )
      publish(release)
    } catch RouteAtlasReleaseError.invalid(let issues) {
      adapterObservations["route_atlas.status"] = .string("BLOCKED")
      adapterObservations["route_atlas.error_codes"] = .strings(
        Array(Set(issues.map(\.code))).sorted()
      )
    }
  }

  private mutating func validateRouteAtlasContext() throws {
    guard
      let sourceValue = scenario.given.inputs.object(
        "route_atlas_context_source"
      ),
      let definitionValue = scenario.given.inputs.object("route_atlas_context")
    else {
      throw ScenarioExecutionError.invalidInput("route_atlas_context")
    }
    let source = try routeAtlasContextSource(sourceValue)
    let definition = try routeAtlasContextDefinition(definitionValue)

    clearRouteAtlasContextObservations()
    do {
      let bundle = try RouteAtlasContextBundle(
        source: source,
        definition: definition
      )
      adapterObservations["route_atlas_context.status"] = .string("PASS")
      adapterObservations["route_atlas_context.error_codes"] = .strings([])
      adapterObservations["route_atlas_context.context_id"] = .string(
        bundle.definition.id
      )
      adapterObservations["route_atlas_context.navigation_role"] = .string(
        bundle.definition.navigationRole.rawValue
      )
    } catch RouteAtlasContextError.invalid(let issues) {
      adapterObservations["route_atlas_context.status"] = .string("BLOCKED")
      adapterObservations["route_atlas_context.error_codes"] = .strings(
        Array(Set(issues.map(\.code))).sorted()
      )
    }
  }

  private mutating func clearRouteAtlasContextObservations() {
    for key in adapterObservations.keys.filter({
      $0.hasPrefix("route_atlas_context.")
    }) {
      adapterObservations.removeValue(forKey: key)
    }
  }

  private mutating func publish(_ release: RouteAtlasRelease) {
    adapterObservations["route_atlas.status"] = .string("PASS")
    adapterObservations["route_atlas.error_codes"] = .strings([])
    adapterObservations["route_atlas.network_snapshot_id"] = .string(
      release.networkSnapshot.id
    )
    adapterObservations["route_atlas.route_plan_id"] = .string(
      release.routePlan.id
    )
    adapterObservations["route_atlas.topology_edge_ids"] = .strings(
      release.topologySlice.edges.map(\.id)
    )
    adapterObservations["route_atlas.occurrence_ids"] = .strings(
      release.definition.occurrenceBindings.map(\.occurrenceID)
    )
  }

  private mutating func clearRouteAtlasObservations() {
    for key in adapterObservations.keys.filter({ $0.hasPrefix("route_atlas.") }) {
      adapterObservations.removeValue(forKey: key)
    }
  }

  private mutating func publish(_ bundle: NavigationReleaseBundle) {
    adapterObservations["release_bundle.status"] = .string("PASS")
    adapterObservations["release_bundle.error_codes"] = .strings([])
    adapterObservations["release_bundle.network_snapshot_id"] = .string(
      bundle.networkSnapshot.id
    )
    adapterObservations["release_bundle.route_plan_id"] = .string(bundle.routePlan.id)
    adapterObservations["release_bundle.decision_zone_movement_occurrence_ids"] =
      .strings(bundle.decisionZones.map(\.movementOccurrenceID))
    adapterObservations["release_bundle.guidance_movement_occurrence_ids"] =
      .strings(
        orderedUnique(bundle.releasedGuidance.map(\.frameTemplate.movementOccurrenceID))
      )
    adapterObservations["release_bundle.junction_view_ids"] = .strings(
      bundle.junctionViews.map(\.id)
    )
  }

  private mutating func clearReleaseBundleObservations() {
    for key in adapterObservations.keys.filter({ $0.hasPrefix("release_bundle.") }) {
      adapterObservations.removeValue(forKey: key)
    }
  }

  private func orderedUnique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.filter { seen.insert($0).inserted }
  }

  private mutating func publish(_ snapshot: ExpertRouteEditorSnapshot) {
    clearRouteEditorObservations()
    adapterObservations["editor.state"] = .string(snapshot.state.rawValue)
    adapterObservations["editor.network_snapshot_id"] = .string(
      snapshot.networkSnapshotID
    )
    adapterObservations["editor.route_plan_id"] = .string(snapshot.routePlanID)
    adapterObservations["editor.entrance_facility_id"] = .string(
      snapshot.entranceFacilityID
    )
    adapterObservations["editor.available_choice_ids"] = .strings(
      snapshot.availableChoices.map(\.id)
    )
    adapterObservations["editor.available_movement_ids"] = .strings(
      snapshot.availableChoices.map(\.movementID)
    )
    adapterObservations["editor.available_lap_candidate_ids"] = .strings(
      snapshot.availableLapCandidates.map(\.id)
    )
    adapterObservations["editor.available_lap_template_ids"] = .strings(
      snapshot.availableLapCandidates.map(\.reviewedTemplateID)
    )
    adapterObservations["editor.available_lap_source_occurrence_ids"] = .array(
      snapshot.availableLapCandidates.map {
        .strings($0.sourceOccurrenceIDs)
      }
    )
    adapterObservations["editor.occurrence_ids"] = .strings(
      snapshot.occurrences.map(\.id)
    )
    adapterObservations["editor.occurrence_entity_ids"] = .strings(
      snapshot.occurrences.map(\.entityID)
    )
    adapterObservations["editor.occurrence_kinds"] = .strings(
      snapshot.occurrences.map { $0.kind.rawValue }
    )
    adapterObservations["editor.occurrence_indexes"] = .array(
      snapshot.occurrences.map { .integer($0.index) }
    )
    if let currentDecisionPointID = snapshot.currentDecisionPointID {
      adapterObservations["editor.current_decision_point_id"] = .string(
        currentDecisionPointID
      )
    }
    if let incomingApproachID = snapshot.incomingApproachID {
      adapterObservations["editor.incoming_approach_id"] = .string(incomingApproachID)
    }
    if let junctionComplexID = snapshot.junctionComplexID {
      adapterObservations["editor.junction_complex_id"] = .string(junctionComplexID)
    }
    if let selectedExitFacilityID = snapshot.selectedExitFacilityID {
      adapterObservations["editor.selected_exit_facility_id"] = .string(
        selectedExitFacilityID
      )
    }
  }

  private mutating func publishCompiledRoutePlan(_ routePlan: RoutePlan) {
    adapterObservations["editor.compiled.status"] = .string("COMPILED")
    adapterObservations["editor.compiled.network_snapshot_id"] = .string(
      routePlan.networkSnapshotID
    )
    adapterObservations["editor.compiled.route_plan_id"] = .string(routePlan.id)
    adapterObservations["editor.compiled.entrance_facility_id"] = .string(
      routePlan.entryFacilityID
    )
    adapterObservations["editor.compiled.exit_facility_id"] = .string(
      routePlan.exitFacilityID
    )
    adapterObservations["editor.compiled.occurrence_ids"] = .strings(
      routePlan.occurrences.map(\.id)
    )
    adapterObservations["editor.compiled.entity_ids"] = .strings(
      routePlan.occurrences.map(\.entityID)
    )
  }

  private mutating func publishRouteEditorError(_ error: ExpertRouteEditorError) {
    clearRouteEditorObservations()
    adapterObservations["editor.last_error"] = .string(error.code)
  }

  private mutating func clearRouteEditorObservations() {
    for key in adapterObservations.keys.filter({ $0.hasPrefix("editor.") }) {
      adapterObservations.removeValue(forKey: key)
    }
  }

  private mutating func publish(_ result: CompileResult) {
    clearCompilerObservations()
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
    if let selectedTemplateVariantID = result.selectedTemplateVariantID {
      adapterObservations["compiler.selected_template_variant_id"] = .string(
        selectedTemplateVariantID
      )
    }
    adapterObservations["compiler.selected_template_parameters"] = .strings(
      result.selectedTemplateParameters
    )
  }

  private mutating func publish(_ result: RoutePlanExpansionResult) {
    clearCompilerObservations()
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

  private mutating func clearCompilerObservations() {
    for key in adapterObservations.keys.filter({ $0.hasPrefix("compiler.") }) {
      adapterObservations.removeValue(forKey: key)
    }
  }

  private mutating func publish(_ document: SharedRouteDocument) {
    let routePlan = document.routePlan
    adapterObservations["shared_route.round_trip_status"] = .string("PASS")
    adapterObservations["shared_route.schema_version"] = .string(document.schemaVersion)
    adapterObservations["shared_route.evidence_state"] = .string(document.evidenceState.rawValue)
    adapterObservations["shared_route.network_snapshot_id"] = .string(
      routePlan.networkSnapshotID
    )
    adapterObservations["shared_route.plan_id"] = .string(routePlan.id)
    adapterObservations["shared_route.occurrence_ids"] = .strings(
      routePlan.occurrences.map(\.id)
    )
    adapterObservations["shared_route.occurrence_indexes"] = .array(
      routePlan.occurrences.map { .integer($0.index) }
    )
    adapterObservations["shared_route.entity_ids"] = .strings(
      routePlan.occurrences.map(\.entityID)
    )
    adapterObservations["shared_route.parking_area_bindings"] = .strings(
      routePlan.occurrences.compactMap { occurrence in
        occurrence.parkingAreaID.map { "\(occurrence.id)=\($0)" }
      }
    )
    adapterObservations["shared_route.toll_domain_bindings"] = .strings(
      routePlan.occurrences.compactMap { occurrence in
        occurrence.tollDomainID.map { "\(occurrence.id)=\($0)" }
      }
    )
    adapterObservations["shared_route.optional_occurrence_ids"] = .strings(
      routePlan.occurrences.filter(\.isOptional).map(\.id)
    )
    adapterObservations["shared_route.template_parameters"] = .strings(
      document.templateParameters.map { "\($0.key)=\($0.value)" }.sorted()
    )
  }

  private mutating func publish(_ recommendation: EntranceRecommendation) {
    adapterObservations["entry_recommendation.status"] = .string(
      recommendation.status.rawValue
    )
    adapterObservations["entry_recommendation.error_codes"] = .strings(
      recommendation.errorCodes
    )
    if let selectedFacilityID = recommendation.selectedFacilityID {
      adapterObservations["entry_recommendation.selected_facility_id"] = .string(selectedFacilityID)
    }
    if let joinOccurrenceID = recommendation.joinOccurrenceID {
      adapterObservations["entry_recommendation.join_occurrence_id"] = .string(joinOccurrenceID)
    }
    for (facilityID, reasons) in recommendation.rejections {
      adapterObservations["entry_recommendation.rejections.\(facilityID)"] = .strings(reasons)
    }
    if let selection = recommendation.selection {
      adapterObservations["entry_recommendation.selection.target_carriageway_id"] =
        .string(selection.targetCarriagewayID)
      adapterObservations["entry_recommendation.selection.straight_line_distance_km"] =
        .number(selection.straightLineDistanceKM)
      adapterObservations["entry_recommendation.selection.straight_line_distance_rank"] =
        .integer(selection.straightLineDistanceRank)
      adapterObservations["entry_recommendation.selection.surface_eta_minutes"] =
        .number(selection.surfaceETAMinutes)
      adapterObservations["entry_recommendation.selection.reason_codes"] = .strings(
        selection.reasonCodes.map(\.rawValue)
      )
      adapterObservations["entry_recommendation.selection.proximity_only"] = .bool(
        !selection.reasonCodes.contains(.exactDirectionalCarriageway)
          || !selection.reasonCodes.contains(.legalRouteJoin)
      )
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

  private mutating func startMatcherSession(_ payload: [String: JSONValue]) throws {
    guard let corridorValue = scenario.given.inputs.object("matcher_corridor") else {
      throw ScenarioExecutionError.missingInput("matcher_corridor")
    }
    let corridor = try routeMatcherCorridor(corridorValue)
    guard corridor.networkSnapshotID == scenario.given.networkSnapshot.id,
      scenario.given.routePlan?.networkSnapshotID == corridor.networkSnapshotID,
      scenario.given.routePlan?.id == corridor.routePlanID
    else {
      throw ScenarioExecutionError.invalidInput("matcher_corridor.route_binding")
    }
    let configurationValue = scenario.given.inputs.object("matcher_session_configuration") ?? [:]
    let sessionConfiguration = RouteMatcherSessionConfiguration(
      ambiguityMarginMeters: configurationValue.double("ambiguity_margin_meters") ?? 3,
      staleObservationThresholdMilliseconds: configurationValue.int(
        "stale_observation_threshold_ms"
      ) ?? 10_000,
      observationGapThresholdMilliseconds: configurationValue.int(
        "observation_gap_threshold_ms"
      ) ?? 10_000,
      spatialCellSizeMeters: configurationValue.double("spatial_cell_size_meters") ?? 100,
      maximumActiveStates: configurationValue.int("maximum_active_states") ?? 64,
      scoreBeamWidth: configurationValue.double("score_beam_width") ?? 30
    )
    matcherSession = try RouteAwareSwiftMatcher().makeSession(
      corridor: corridor,
      sessionConfiguration: sessionConfiguration,
      initialOccurrenceID: payload.string("initial_occurrence_id")
    )
    matcherCorridor = corridor
    publishMatcherSessionStatus("ACTIVE")
  }

  private mutating func receiveMatcherObservation(
    _ payload: [String: JSONValue]
  ) throws {
    guard var session = matcherSession else {
      throw ScenarioExecutionError.invalidInput("matcher_session")
    }
    let observation = try routeMatcherObservation(payload)
    let estimate = try session.observe(observation)
    matcherSession = session
    publish(estimate, diagnostics: session.diagnostics)

    let candidateResolution: RouteCandidateResolution
    if estimate.directedEdgeID != nil, estimate.candidateEdgeIDs.count == 1 {
      candidateResolution = .resolved
    } else if estimate.candidateEdgeIDs.count > 1 {
      candidateResolution = .ambiguous
    } else {
      candidateResolution = .unknown
    }
    engine.observeLocation(
      LocationObservation(
        directedEdgeID: estimate.directedEdgeID,
        matchedEntityID: estimate.directedEdgeID,
        matchedOccurrenceID: estimate.occurrenceID,
        candidateOccurrenceIDs: Set([estimate.occurrenceID].compactMap { $0 }),
        candidateResolution: candidateResolution,
        observedAtMilliseconds: observation.observedAtMilliseconds,
        reportedConfidence: LocationConfidence(rawValue: estimate.confidence.rawValue),
        horizontalAccuracyMeters: observation.horizontalAccuracyMeters,
        ageMilliseconds: observation.receivedAtMilliseconds
          - observation.observedAtMilliseconds
      )
    )
    try updateGuidanceProgress(from: estimate)
  }

  private mutating func updateGuidanceProgress(from estimate: MatcherEstimate) throws {
    for key in adapterObservations.keys.filter({
      $0.hasPrefix("guidance.progress_bridge.")
    }) {
      adapterObservations.removeValue(forKey: key)
    }
    guard let value = scenario.given.inputs.object("guidance_progress_bridge") else {
      return
    }
    guard let routePlan = scenario.given.routePlan, let matcherCorridor else {
      throw ScenarioExecutionError.invalidInput("guidance_progress_bridge.route_binding")
    }
    let decisionZone = try Self.decisionZoneProgressDefinition(value)
    do {
      let progress = try GuidanceProgressBridge.resolve(
        estimate: estimate,
        routePlan: routePlan,
        corridor: matcherCorridor,
        decisionZone: decisionZone,
        skippedOccurrenceIDs: Set(engine.snapshot.skippedOccurrenceIDs)
      )
      adapterObservations["guidance.progress_bridge.status"] = .string("RESOLVED")
      adapterObservations["guidance.progress_bridge.distance_meters"] = .number(
        progress.distanceToDecisionPointMeters
      )
      lastGuidancePromptEmission = engine.observeGuidanceProgress(progress)
    } catch GuidanceProgressBridgeError.insufficientMatcherEvidence {
      adapterObservations["guidance.progress_bridge.status"] = .string(
        "INSUFFICIENT_MATCHER_EVIDENCE"
      )
    } catch {
      throw ScenarioExecutionError.invalidInput(
        "guidance_progress_bridge.\(String(describing: error))"
      )
    }
  }

  private mutating func resetMatcherSession(_ payload: [String: JSONValue]) throws {
    guard var session = matcherSession else {
      throw ScenarioExecutionError.invalidInput("matcher_session")
    }
    if payload["initial_occurrence_id"] != nil {
      try session.restart(at: payload.string("initial_occurrence_id"))
    } else {
      session.reset()
    }
    matcherSession = session
    clearMatcherEstimateObservations()
    publishMatcherSessionStatus("RESET")
  }

  private mutating func publish(
    _ estimate: MatcherEstimate,
    diagnostics: RouteMatcherSessionDiagnostics
  ) {
    clearMatcherEstimateObservations()
    adapterObservations["matcher.confidence"] = .string(estimate.confidence.rawValue)
    adapterObservations["matcher.candidate_edge_ids"] = .strings(estimate.candidateEdgeIDs)
    adapterObservations["matcher.indexed_edge_count"] = .integer(diagnostics.indexedEdgeCount)
    adapterObservations["matcher.last_queried_edge_count"] = .integer(
      diagnostics.lastQueriedEdgeCount
    )
    adapterObservations["matcher.active_state_count"] = .integer(diagnostics.activeStateCount)
    adapterObservations["matcher.accepted_observation_count"] = .integer(
      diagnostics.acceptedObservationCount
    )
    if let edgeID = estimate.directedEdgeID {
      adapterObservations["matcher.directed_edge_id"] = .string(edgeID)
    }
    if let occurrenceID = estimate.occurrenceID {
      adapterObservations["matcher.occurrence_id"] = .string(occurrenceID)
    }
    if let fractionAlongEdge = estimate.fractionAlongEdge {
      adapterObservations["matcher.fraction_along_edge"] = .number(fractionAlongEdge)
    }
    if let distanceMeters = estimate.distanceMeters {
      adapterObservations["matcher.lateral_distance_meters"] = .number(distanceMeters)
    }
    publishMatcherSessionStatus("ACTIVE")
  }

  private mutating func clearMatcherEstimateObservations() {
    for key in adapterObservations.keys.filter({
      $0.hasPrefix("matcher.") && $0 != "matcher.session_status"
    }) {
      adapterObservations.removeValue(forKey: key)
    }
  }

  private mutating func publishMatcherSessionStatus(_ status: String) {
    adapterObservations["matcher.session_status"] = .string(status)
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

    guard let actualDistance = routeSummary.double("actual_distance_km"),
      let tollEvidenceStatus = TollEvidenceStatus(rawValue: quote.status),
      let passageEvidence = RoutePassageEvidence(
        rawValue: routeSummary.string("passage_evidence")
          ?? RoutePassageEvidence.noKnownConflictRealtimeUnconfirmed.rawValue
      )
    else {
      throw ScenarioExecutionError.invalidInput("route_summary")
    }
    let review = try PreDriveReviewProjector.project(
      PreDriveReviewRequest(
        actualDistanceKM: actualDistance,
        tariffDistanceKM: quote.tariffDistanceKM,
        estimatedAmountYen: quote.estimatedAmountYen,
        tollEvidenceStatus: tollEvidenceStatus,
        passageEvidence: passageEvidence
      )
    )
    publish(review)
  }

  private mutating func refreshPresentation() throws {
    for key in adapterObservations.keys.filter({ $0.hasPrefix("presentation.kernel.") }) {
      adapterObservations.removeValue(forKey: key)
    }
    guard let value = scenario.given.inputs.object("presentation") else { return }
    if value.string("guidance_source") == "NAVIGATION_ACTIVE",
      engine.snapshot.activeGuidanceFrame == nil
    {
      return
    }
    let request = try presentationRequest(value)
    let projection = try NavigationPresentationProjector.project(request)
    publish(projection)
  }

  private func presentationRequest(
    _ value: [String: JSONValue]
  ) throws -> NavigationPresentationRequest {
    guard let languageSelection = value.object("language_selection"),
      let interfaceLocale = languageSelection.string("interface_locale")
        .flatMap(KaidoReleaseLocale.init(rawValue:)),
      let voiceLocale = languageSelection.string("guidance_voice_locale")
        .flatMap(KaidoReleaseLocale.init(rawValue:)),
      let passageEvidence = value.string("passage_evidence")
        .flatMap(RoutePassageEvidence.init(rawValue:)),
      let drivingContext = value.object("driving_context")
    else {
      throw ScenarioExecutionError.invalidInput("presentation")
    }
    let frame: GuidanceFrame
    if value.string("guidance_source") == "NAVIGATION_ACTIVE" {
      guard let activeFrame = engine.snapshot.activeGuidanceFrame else {
        throw ScenarioExecutionError.invalidInput("presentation.active_guidance_frame")
      }
      frame = activeFrame
    } else {
      guard let guidanceValue = value.object("guidance") else {
        throw ScenarioExecutionError.invalidInput("presentation.guidance")
      }
      frame = try Self.guidanceFrame(guidanceValue)
    }
    return NavigationPresentationRequest(
      snapshot: engine.snapshot,
      networkSnapshotID: scenario.given.networkSnapshot.id,
      guidanceFrame: frame,
      promptEmission: lastGuidancePromptEmission,
      languages: NavigationLanguageSelection(
        interfaceLocale: interfaceLocale,
        guidanceVoiceLocale: voiceLocale
      ),
      passageEvidence: passageEvidence,
      drivingContext: PresentationDrivingContext(
        isVehicleMoving: drivingContext.bool("vehicle_moving") ?? false,
        isInsideDecisionZone: drivingContext.bool("inside_decision_zone") ?? false
      ),
      facilityNames: try localizedFacilityNames(value.object("facility_names") ?? [:])
    )
  }

  private static func guidanceFrame(
    _ value: [String: JSONValue]
  ) throws -> GuidanceFrame {
    guard let distanceMeters = value.double("distance_meters") else {
      throw ScenarioExecutionError.invalidInput("presentation.guidance.distance_meters")
    }
    return try guidanceFrameTemplate(value).makeFrame(
      anchor: GuidanceAnchorDefinition(
        occurrenceID: try value.requiredString("anchor_occurrence_id"),
        anchorID: try value.requiredString("anchor_id"),
        promptID: try value.requiredString("prompt_id")
      ),
      distanceMeters: distanceMeters
    )
  }

  private static func guidanceFrameTemplate(
    _ value: [String: JSONValue]
  ) throws -> GuidanceFrameTemplate {
    guard let stage = value.string("stage").flatMap(GuidancePromptStage.init(rawValue:)),
      let maneuver = value.string("maneuver").flatMap(GuidanceManeuver.init(rawValue:)),
      let lanePreparation = value.string("lane_preparation")
        .flatMap(GuidanceLanePreparation.init(rawValue:)),
      let localizedNameValues = value.object("localized_decision_point_names")
    else {
      throw ScenarioExecutionError.invalidInput("presentation.guidance.frame")
    }
    var localizedNames: [KaidoReleaseLocale: String] = [:]
    for (localeValue, nameValue) in localizedNameValues {
      guard let locale = KaidoReleaseLocale(rawValue: localeValue),
        let name = nameValue.stringValue
      else {
        throw ScenarioExecutionError.invalidInput(
          "presentation.guidance.localized_decision_point_names"
        )
      }
      localizedNames[locale] = name
    }
    return GuidanceFrameTemplate(
      movementOccurrenceID: try value.requiredString("movement_occurrence_id"),
      decisionZoneID: try value.requiredString("decision_zone_id"),
      stage: stage,
      decisionPointNameJapanese: try value.requiredString("decision_point_name_ja"),
      localizedDecisionPointNames: localizedNames,
      maneuver: maneuver,
      lanePreparation: lanePreparation,
      presentationSource: try guidancePresentationSource(value)
    )
  }

  private static func guidancePresentationSource(
    _ value: [String: JSONValue]
  ) throws -> GuidancePresentationSource {
    guard let localizedValues = value.object("localized_content") else {
      throw ScenarioExecutionError.invalidInput("presentation.guidance.localized_content")
    }
    var localizedContent: [KaidoReleaseLocale: LocalizedGuidanceContent] = [:]
    for (localeValue, contentValue) in localizedValues {
      guard let locale = KaidoReleaseLocale(rawValue: localeValue),
        let content = contentValue.objectValue,
        let spokenFormValues = content.object("spoken_forms")
      else {
        throw ScenarioExecutionError.invalidInput("presentation.guidance.localized_content")
      }
      let spokenForms = spokenFormValues.compactMapValues(\.stringValue)
      guard spokenForms.count == spokenFormValues.count else {
        throw ScenarioExecutionError.invalidInput("presentation.guidance.spoken_forms")
      }
      localizedContent[locale] = LocalizedGuidanceContent(
        displayText: try content.requiredString("display_text"),
        spokenText: try content.requiredString("spoken_text"),
        spokenForms: spokenForms,
        preservedJapaneseSignText: try content.requiredString(
          "preserved_japanese_sign_text"
        )
      )
    }
    return GuidancePresentationSource(
      routeShields: (value.array("route_shields") ?? []).compactMap(\.stringValue),
      japaneseSignText: try value.requiredString("japanese_sign_text"),
      localizedContent: localizedContent,
      junctionView: try junctionViewDefinition(value.object("junction_view"))
    )
  }

  private static func junctionViewDefinition(
    _ value: [String: JSONValue]?
  ) throws -> JunctionViewDefinition? {
    guard let value else { return nil }
    guard let pathValues = value.array("paths"),
      let laneValue = value.object("lane_layout"),
      let evidenceValue = value.object("evidence"),
      let evidenceState = evidenceValue.string("state")
        .flatMap(JunctionViewEvidenceState.init(rawValue:)),
      let sourceValues = evidenceValue.array("source_reference_ids")
    else {
      throw ScenarioExecutionError.invalidInput("presentation.guidance.junction_view")
    }

    let paths = try pathValues.map { pathValue -> JunctionViewPath in
      guard let path = pathValue.objectValue,
        let role = path.string("role").flatMap(JunctionViewPathRole.init(rawValue:)),
        let pointValues = path.array("points")
      else {
        throw ScenarioExecutionError.invalidInput("presentation.guidance.junction_view.paths")
      }
      let points = try pointValues.map { pointValue -> JunctionViewPoint in
        guard let point = pointValue.objectValue,
          let x = point.double("x"),
          let y = point.double("y")
        else {
          throw ScenarioExecutionError.invalidInput(
            "presentation.guidance.junction_view.paths.points"
          )
        }
        return JunctionViewPoint(x: x, y: y)
      }
      return JunctionViewPath(
        id: try path.requiredString("path_id"),
        role: role,
        points: points
      )
    }
    let sourceReferenceIDs = sourceValues.compactMap(\.stringValue)
    guard sourceReferenceIDs.count == sourceValues.count else {
      throw ScenarioExecutionError.invalidInput(
        "presentation.guidance.junction_view.evidence.source_reference_ids"
      )
    }
    let allowedLaneValues = laneValue.array("allowed_lane_indices") ?? []
    let allowedLaneIndices = allowedLaneValues.compactMap(\.intValue)
    let preferredLaneValues = laneValue.array("preferred_lane_indices") ?? []
    let preferredLaneIndices = preferredLaneValues.compactMap(\.intValue)
    let routeShieldValues = value.array("route_shields") ?? []
    let routeShields = routeShieldValues.compactMap(\.stringValue)
    guard allowedLaneIndices.count == allowedLaneValues.count,
      preferredLaneIndices.count == preferredLaneValues.count,
      routeShields.count == routeShieldValues.count
    else {
      throw ScenarioExecutionError.invalidInput(
        "presentation.guidance.junction_view.lane_or_shield_values"
      )
    }

    return JunctionViewDefinition(
      id: try value.requiredString("view_id"),
      networkSnapshotID: try value.requiredString("network_snapshot_id"),
      movementOccurrenceID: try value.requiredString("movement_occurrence_id"),
      paths: paths,
      laneLayout: JunctionViewLaneLayout(
        laneCount: laneValue.int("lane_count") ?? 0,
        allowedLaneIndices: allowedLaneIndices,
        preferredLaneIndices: preferredLaneIndices
      ),
      japaneseSignText: try value.requiredString("japanese_sign_text"),
      routeShields: routeShields,
      evidence: JunctionViewEvidence(
        state: evidenceState,
        checkedAt: try evidenceValue.requiredString("checked_at"),
        sourceReferenceIDs: sourceReferenceIDs
      )
    )
  }

  private func localizedFacilityNames(
    _ values: [String: JSONValue]
  ) throws -> [String: LocalizedFacilityName] {
    var result: [String: LocalizedFacilityName] = [:]
    for (facilityID, namesValue) in values {
      guard let names = namesValue.objectValue else {
        throw ScenarioExecutionError.invalidInput("presentation.facility_names")
      }
      var localizedNames: [KaidoReleaseLocale: String] = [:]
      for (localeValue, nameValue) in names {
        guard let locale = KaidoReleaseLocale(rawValue: localeValue),
          let name = nameValue.stringValue
        else {
          throw ScenarioExecutionError.invalidInput("presentation.facility_names")
        }
        localizedNames[locale] = name
      }
      result[facilityID] = LocalizedFacilityName(values: localizedNames)
    }
    return result
  }

  private mutating func publish(_ review: PreDriveReviewPresentation) {
    adapterObservations["route_summary.actual_distance_km"] = .number(
      review.actualDistanceKM
    )
    adapterObservations["route_summary.toll.status"] = .string(
      review.tollEvidenceStatus.rawValue
    )
    adapterObservations["route_summary.passage.tone"] = .string(
      review.passage.tone.rawValue
    )
    adapterObservations["route_summary.passage.uses_positive_open_color"] = .bool(
      review.passage.usesPositiveOpenColor
    )
    if let tariffDistanceKM = review.tariffDistanceKM {
      adapterObservations["route_summary.tariff_distance_km"] = .number(
        tariffDistanceKM
      )
    }
    if let estimatedAmountYen = review.estimatedAmountYen {
      adapterObservations["route_summary.toll.estimated_amount_yen"] = .integer(
        estimatedAmountYen
      )
    }
  }

  private mutating func publish(_ projection: NavigationPresentationProjection) {
    adapterObservations["presentation.kernel.interface_locale"] = .string(
      projection.interfaceLocale.rawValue
    )
    adapterObservations["presentation.kernel.voice_locale"] = .string(
      projection.voice.locale.rawValue
    )
    adapterObservations["presentation.kernel.voice.spoken_text"] = .string(
      projection.voice.spokenText
    )
    adapterObservations["presentation.kernel.voice.prompt_id"] = .string(
      projection.voice.promptID
    )
    adapterObservations["presentation.kernel.voice.stage"] = .string(
      projection.voice.stage.rawValue
    )
    adapterObservations["presentation.kernel.voice.distance_meters"] = .number(
      projection.voice.distanceMeters
    )
    adapterObservations["presentation.kernel.voice.maneuver"] = .string(
      projection.voice.maneuver.rawValue
    )
    adapterObservations["presentation.kernel.voice.should_speak"] = .bool(
      projection.voice.shouldSpeak
    )
    publish(projection.iPhone, prefix: "presentation.kernel.phone")
    publish(projection.carPlay, prefix: "presentation.kernel.carplay")
    publish(
      NavigationAccessibilityProjector.project(
        projection.iPhone,
        locale: projection.interfaceLocale
      ),
      prefix: "presentation.accessibility.phone"
    )
    publish(
      NavigationAccessibilityProjector.project(
        projection.carPlay,
        locale: projection.interfaceLocale
      ),
      prefix: "presentation.accessibility.carplay"
    )
  }

  private mutating func publish(
    _ accessibility: NavigationAccessibilityPresentation,
    prefix: String
  ) {
    adapterObservations["\(prefix).route_shield_labels"] = .strings(
      accessibility.routeShieldLabels
    )
    adapterObservations["\(prefix).guidance_label"] = .string(
      accessibility.guidanceLabel
    )
    adapterObservations["\(prefix).marker_label"] = .string(
      accessibility.markerLabel
    )
    adapterObservations["\(prefix).passage_label"] = .string(
      accessibility.passageLabel
    )
    adapterObservations["\(prefix).route_editing_label"] = .string(
      accessibility.routeEditingLabel
    )
    adapterObservations["\(prefix).surface_ownership_label"] = .string(
      accessibility.surfaceOwnershipLabel
    )
    adapterObservations["\(prefix).selected_path_has_non_color_cue"] = .bool(
      accessibility.selectedPathHasNonColorCue
    )
    adapterObservations["\(prefix).preferred_lanes_have_non_color_cue"] = .bool(
      accessibility.preferredLanesHaveNonColorCue
    )
    if let junctionDiagramLabel = accessibility.junctionDiagramLabel {
      adapterObservations["\(prefix).junction_diagram_label"] = .string(
        junctionDiagramLabel
      )
    }
    if let junctionLaneLabel = accessibility.junctionLaneLabel {
      adapterObservations["\(prefix).junction_lane_label"] = .string(
        junctionLaneLabel
      )
    }
  }

  private mutating func publish(
    _ presentation: NavigationSurfacePresentation,
    prefix: String
  ) {
    adapterObservations["\(prefix).primary"] = .bool(presentation.isPrimarySurface)
    adapterObservations["\(prefix).marker"] = .string(presentation.marker.rawValue)
    adapterObservations["\(prefix).guidance.prompt_id"] = .string(
      presentation.guidancePromptID
    )
    adapterObservations["\(prefix).guidance.anchor_id"] = .string(
      presentation.guidanceAnchorID
    )
    adapterObservations["\(prefix).guidance.anchor_occurrence_id"] = .string(
      presentation.guidanceAnchorOccurrenceID
    )
    adapterObservations["\(prefix).guidance.decision_zone_id"] = .string(
      presentation.decisionZoneID
    )
    adapterObservations["\(prefix).guidance.stage"] = .string(
      presentation.guidanceStage.rawValue
    )
    adapterObservations["\(prefix).guidance.distance_meters"] = .number(
      presentation.distanceMeters
    )
    adapterObservations["\(prefix).guidance.decision_point_name_ja"] = .string(
      presentation.decisionPointNameJapanese
    )
    adapterObservations["\(prefix).guidance.localized_decision_point_name"] = .string(
      presentation.localizedDecisionPointName
    )
    adapterObservations["\(prefix).guidance.maneuver"] = .string(
      presentation.maneuver.rawValue
    )
    adapterObservations["\(prefix).guidance.lane_preparation"] = .string(
      presentation.lanePreparation.rawValue
    )
    adapterObservations["\(prefix).route_shields"] = .strings(
      presentation.routeShields
    )
    adapterObservations["\(prefix).japanese_sign_text"] = .string(
      presentation.japaneseSignText
    )
    adapterObservations["\(prefix).localized_display_text"] = .string(
      presentation.localizedDisplayText
    )
    adapterObservations["\(prefix).passage_tone"] = .string(
      presentation.passage.tone.rawValue
    )
    adapterObservations["\(prefix).uses_positive_open_color"] = .bool(
      presentation.passage.usesPositiveOpenColor
    )
    adapterObservations["\(prefix).route_editing_availability"] = .string(
      presentation.routeEditingAvailability.rawValue
    )
    adapterObservations["\(prefix).requires_phone_touch_while_moving"] = .bool(
      presentation.requiresPhoneTouchWhileMoving
    )
    if let routePlanID = presentation.routePlanID {
      adapterObservations["\(prefix).route_plan_id"] = .string(routePlanID)
    }
    if let currentOccurrenceID = presentation.currentOccurrenceID {
      adapterObservations["\(prefix).current_occurrence_id"] = .string(
        currentOccurrenceID
      )
    }
    if let nextMovementOccurrenceID = presentation.nextMovementOccurrenceID {
      adapterObservations["\(prefix).next_movement_occurrence_id"] = .string(
        nextMovementOccurrenceID
      )
    }
    if let finishDrive = presentation.finishDrive {
      adapterObservations["\(prefix).finish.exit_facility_id"] = .string(
        finishDrive.exitFacilityID
      )
      adapterObservations["\(prefix).finish.localized_exit_name"] = .string(
        finishDrive.localizedExitName
      )
      adapterObservations["\(prefix).finish.announcement_priority"] = .string(
        finishDrive.announcementPriority.rawValue
      )
    }
    if let junctionView = presentation.junctionView {
      adapterObservations["\(prefix).junction_view.id"] = .string(junctionView.id)
      adapterObservations["\(prefix).junction_view.network_snapshot_id"] = .string(
        junctionView.networkSnapshotID
      )
      adapterObservations["\(prefix).junction_view.movement_occurrence_id"] = .string(
        junctionView.movementOccurrenceID
      )
      adapterObservations["\(prefix).junction_view.path_count"] = .integer(
        junctionView.paths.count
      )
      adapterObservations["\(prefix).junction_view.lane_count"] = .integer(
        junctionView.laneLayout.laneCount
      )
      adapterObservations["\(prefix).junction_view.preferred_lane_indices"] = .array(
        junctionView.laneLayout.preferredLaneIndices.map(JSONValue.integer)
      )
      adapterObservations["\(prefix).junction_view.japanese_sign_text"] = .string(
        junctionView.japaneseSignText
      )
      adapterObservations["\(prefix).junction_view.evidence_state"] = .string(
        junctionView.evidence.state.rawValue
      )
      if let selectedPath = junctionView.paths.first(where: { $0.role == .selected }) {
        adapterObservations["\(prefix).junction_view.selected_path_id"] = .string(
          selectedPath.id
        )
      }
    }
  }

  private mutating func selectTariff(_ payload: [String: JSONValue]) throws {
    let quoteIDs = try requiredStrings(payload, key: "candidate_quote_ids")
    let quotes = try quoteIDs.map { quoteID in
      guard let quote = scenario.given.tariffQuotes.first(where: { $0.id == quoteID }) else {
        throw ScenarioExecutionError.invalidInput("candidate_quote_ids")
      }
      return quote
    }
    let selection = TariffSelector.selectCurrent(
      from: quotes.map { quote in
        TariffCandidate(
          quoteID: quote.id,
          tariffVersionID: quote.tariffVersionID,
          versionStatus: quote.tariffVersionStatus
        )
      }
    )

    adapterObservations["tariff_selection.status"] = .string(selection.status.rawValue)
    adapterObservations["tariff_selection.ignored_non_active_quote_ids"] = .strings(
      selection.ignoredNonActiveQuoteIDs
    )
    adapterObservations["tariff_selection.error_codes"] = .strings(selection.errorCodes)
    guard let selected = selection.selectedCandidate,
      let quote = quotes.first(where: { $0.id == selected.quoteID })
    else { return }
    adapterObservations["tariff_selection.selected_quote_id"] = .string(selected.quoteID)
    adapterObservations["tariff_selection.selected_tariff_version_id"] = .string(
      selected.tariffVersionID
    )
    adapterObservations["tariff_selection.selected_tariff_version_status"] = .string(
      selected.versionStatus.rawValue
    )
    if let amount = quote.estimatedAmountYen {
      adapterObservations["tariff_selection.selected_amount_yen"] = .integer(amount)
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
      nextSign: signGuidance(from: given.inputs),
      guidanceAnchors: try guidanceAnchors(from: given.inputs),
      releasedGuidance: try releasedGuidance(from: given.inputs)
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

  private static func guidanceAnchors(
    from inputs: [String: JSONValue]
  ) throws -> [GuidanceAnchorDefinition] {
    try (inputs.array("guidance_anchors") ?? []).map { value in
      guard let anchor = value.objectValue else {
        throw ScenarioExecutionError.invalidInput("guidance_anchors")
      }
      return GuidanceAnchorDefinition(
        occurrenceID: try anchor.requiredString("occurrence_id"),
        anchorID: try anchor.requiredString("anchor_id"),
        promptID: try anchor.requiredString("prompt_id")
      )
    }
  }

  private static func releasedGuidance(
    from inputs: [String: JSONValue]
  ) throws -> [ReleasedGuidanceDefinition] {
    try (inputs.array("released_guidance") ?? []).map { value in
      guard let definition = value.objectValue,
        let frameValue = definition.object("frame"),
        let triggerDistanceMeters = definition.double("trigger_distance_meters")
      else {
        throw ScenarioExecutionError.invalidInput("released_guidance")
      }
      return ReleasedGuidanceDefinition(
        anchor: GuidanceAnchorDefinition(
          occurrenceID: try definition.requiredString("occurrence_id"),
          anchorID: try definition.requiredString("anchor_id"),
          promptID: try definition.requiredString("prompt_id")
        ),
        triggerDistanceMeters: triggerDistanceMeters,
        frameTemplate: try guidanceFrameTemplate(frameValue)
      )
    }
  }

  private static func decisionZoneProgressDefinition(
    _ value: [String: JSONValue]
  ) throws -> DecisionZoneProgressDefinition {
    guard let entryOffsetMeters = value.double("entry_offset_meters") else {
      throw ScenarioExecutionError.invalidInput(
        "guidance_progress_bridge.entry_offset_meters"
      )
    }
    return DecisionZoneProgressDefinition(
      id: try value.requiredString("decision_zone_id"),
      networkSnapshotID: try value.requiredString("network_snapshot_id"),
      routePlanID: try value.requiredString("route_plan_id"),
      movementOccurrenceID: try value.requiredString("movement_occurrence_id"),
      entryOffsetMeters: entryOffsetMeters
    )
  }

  private static func languageCode(_ locale: String) -> String {
    locale.split(separator: "-").first.map(String.init) ?? locale
  }

  private func routeMatcherCorridor(
    _ value: [String: JSONValue]
  ) throws -> RouteMatcherCorridor {
    guard let edgeValues = value.array("edges"), let occurrenceValues = value.array("occurrences")
    else {
      throw ScenarioExecutionError.invalidInput("matcher_corridor")
    }
    let edges = try edgeValues.map { value in
      guard let edge = value.objectValue, let coordinateValues = edge.array("coordinates") else {
        throw ScenarioExecutionError.invalidInput("matcher_corridor.edges")
      }
      let coordinates = try coordinateValues.map { value in
        guard let coordinate = value.objectValue,
          let latitude = coordinate.double("latitude"),
          let longitude = coordinate.double("longitude")
        else {
          throw ScenarioExecutionError.invalidInput("matcher_corridor.coordinates")
        }
        return MatcherCoordinate(latitude: latitude, longitude: longitude)
      }
      return RouteMatcherDirectedEdge(
        id: try edge.requiredString("directed_edge_id"),
        coordinates: coordinates,
        successorEdgeIDs: Set(
          (edge.array("successor_edge_ids") ?? []).compactMap(\.stringValue)
        )
      )
    }
    let occurrences = try occurrenceValues.map { value in
      guard let occurrence = value.objectValue, let index = occurrence.int("index") else {
        throw ScenarioExecutionError.invalidInput("matcher_corridor.occurrences")
      }
      return RouteMatcherOccurrence(
        id: try occurrence.requiredString("occurrence_id"),
        index: index,
        directedEdgeID: try occurrence.requiredString("directed_edge_id")
      )
    }
    return RouteMatcherCorridor(
      id: try value.requiredString("corridor_id"),
      networkSnapshotID: try value.requiredString("network_snapshot_id"),
      routePlanID: try value.requiredString("route_plan_id"),
      edges: edges,
      occurrences: occurrences
    )
  }

  private func routeAtlasTopologySlice(
    _ value: [String: JSONValue]
  ) throws -> RouteAtlasTopologySlice {
    guard let nodeValues = value.array("nodes"),
      let edgeValues = value.array("edges"),
      let evidenceValue = value.object("evidence")
    else {
      throw ScenarioExecutionError.invalidInput("route_atlas_topology")
    }
    let nodes = try nodeValues.map { value in
      guard let node = value.objectValue else {
        throw ScenarioExecutionError.invalidInput("route_atlas_topology.nodes")
      }
      return RouteAtlasTopologyNode(id: try node.requiredString("node_id"))
    }
    let edges = try edgeValues.map { value in
      guard let edge = value.objectValue else {
        throw ScenarioExecutionError.invalidInput("route_atlas_topology.edges")
      }
      return RouteAtlasTopologyEdge(
        id: try edge.requiredString("edge_id"),
        routeEntityID: try edge.requiredString("route_entity_id"),
        fromNodeID: try edge.requiredString("from_node_id"),
        toNodeID: try edge.requiredString("to_node_id"),
        successorEdgeIDs: Set(
          (edge.array("successor_edge_ids") ?? []).compactMap(\.stringValue)
        )
      )
    }
    return RouteAtlasTopologySlice(
      id: try value.requiredString("topology_slice_id"),
      networkSnapshotID: try value.requiredString("network_snapshot_id"),
      nodes: nodes,
      edges: edges,
      evidence: try routeAtlasEvidence(evidenceValue)
    )
  }

  private func routeAtlasSourceRegistry(
    _ values: [JSONValue]
  ) throws -> RouteAtlasSourceRegistry {
    let references = try values.map { value in
      guard
        let source = value.objectValue,
        let roleValues = source.array("roles")
      else {
        throw ScenarioExecutionError.invalidInput("route_atlas_sources")
      }
      let roles = try roleValues.map { value in
        guard
          let rawValue = value.stringValue,
          let role = RouteAtlasSourceRole(rawValue: rawValue)
        else {
          throw ScenarioExecutionError.invalidInput(
            "route_atlas_sources.roles"
          )
        }
        return role
      }
      return RouteAtlasSourceReference(
        id: try source.requiredString("source_reference_id"),
        roles: Set(roles),
        authorityName: try source.requiredString("authority_name"),
        sourceURL: try source.requiredString("source_url"),
        contentSHA256: try source.requiredString("content_sha256"),
        checkedAt: try source.requiredString("checked_at"),
        licenceIdentifier: try source.requiredString("licence_identifier")
      )
    }
    return RouteAtlasSourceRegistry(references: references)
  }

  private func routeAtlasDefinition(
    _ value: [String: JSONValue]
  ) throws -> RouteAtlasDefinition {
    guard let nodeValues = value.array("nodes"),
      let segmentValues = value.array("segments"),
      let occurrenceValues = value.array("occurrence_bindings"),
      let evidenceValue = value.object("evidence")
    else {
      throw ScenarioExecutionError.invalidInput("route_atlas")
    }
    let nodes = try nodeValues.map { value in
      guard let node = value.objectValue,
        let point = node.object("point"),
        let x = point.double("x"),
        let y = point.double("y")
      else {
        throw ScenarioExecutionError.invalidInput("route_atlas.nodes")
      }
      return RouteAtlasLayoutNode(
        topologyNodeID: try node.requiredString("topology_node_id"),
        point: RouteAtlasPoint(x: x, y: y)
      )
    }
    let segments = try segmentValues.map { value in
      guard let segment = value.objectValue,
        let pointValues = segment.array("points")
      else {
        throw ScenarioExecutionError.invalidInput("route_atlas.segments")
      }
      let points = try pointValues.map { value in
        guard let point = value.objectValue,
          let x = point.double("x"),
          let y = point.double("y")
        else {
          throw ScenarioExecutionError.invalidInput("route_atlas.segments.points")
        }
        return RouteAtlasPoint(x: x, y: y)
      }
      return RouteAtlasSegment(
        id: try segment.requiredString("segment_id"),
        topologyEdgeID: try segment.requiredString("topology_edge_id"),
        fromNodeID: try segment.requiredString("from_node_id"),
        toNodeID: try segment.requiredString("to_node_id"),
        successorSegmentIDs: Set(
          (segment.array("successor_segment_ids") ?? []).compactMap(\.stringValue)
        ),
        points: points
      )
    }
    let occurrenceBindings = try occurrenceValues.map { value in
      guard let occurrence = value.objectValue,
        let index = occurrence.int("index")
      else {
        throw ScenarioExecutionError.invalidInput(
          "route_atlas.occurrence_bindings"
        )
      }
      return RouteAtlasOccurrenceBinding(
        occurrenceID: try occurrence.requiredString("occurrence_id"),
        occurrenceIndex: index,
        segmentID: try occurrence.requiredString("segment_id")
      )
    }
    return RouteAtlasDefinition(
      id: try value.requiredString("atlas_id"),
      networkSnapshotID: try value.requiredString("network_snapshot_id"),
      routePlanID: try value.requiredString("route_plan_id"),
      topologySliceID: try value.requiredString("topology_slice_id"),
      nodes: nodes,
      segments: segments,
      occurrenceBindings: occurrenceBindings,
      evidence: try routeAtlasEvidence(evidenceValue)
    )
  }

  private func routeAtlasEvidence(
    _ value: [String: JSONValue]
  ) throws -> RouteAtlasEvidence {
    guard
      let state = RouteAtlasEvidenceState(
        rawValue: try value.requiredString("state")
      )
    else {
      throw ScenarioExecutionError.invalidInput("route_atlas.evidence.state")
    }
    return RouteAtlasEvidence(
      state: state,
      checkedAt: try value.requiredString("checked_at"),
      sourceReferenceIDs: try (value.array("source_reference_ids") ?? []).map { value in
        guard let sourceID = value.stringValue else {
          throw ScenarioExecutionError.invalidInput(
            "route_atlas.evidence.source_reference_ids"
          )
        }
        return sourceID
      }
    )
  }

  private func routeAtlasContextSource(
    _ value: [String: JSONValue]
  ) throws -> RouteAtlasContextSource {
    guard
      let usageScope = RouteAtlasContextUsageScope(
        rawValue: try value.requiredString("usage_scope")
      ),
      let sourceCRS = RouteAtlasContextSourceCRS(
        rawValue: try value.requiredString("source_crs")
      )
    else {
      throw ScenarioExecutionError.invalidInput(
        "route_atlas_context_source.usage_scope"
      )
    }
    return RouteAtlasContextSource(
      sourceReferenceID: try value.requiredString("source_reference_id"),
      authorityName: try value.requiredString("authority_name"),
      sourcePageURL: try value.requiredString("source_page_url"),
      downloadURL: try value.requiredString("download_url"),
      archiveSHA256: try value.requiredString("archive_sha256"),
      sourceCRS: sourceCRS,
      datasetReferenceDate: try value.requiredString("dataset_reference_date"),
      retrievedAt: try value.requiredString("retrieved_at"),
      checkedAt: try value.requiredString("checked_at"),
      licenceIdentifier: try value.requiredString("licence_identifier"),
      usageScope: usageScope,
      attribution: try value.requiredString("attribution"),
      transformationDisclosure: try value.requiredString(
        "transformation_disclosure"
      )
    )
  }

  private func routeAtlasContextDefinition(
    _ value: [String: JSONValue]
  ) throws -> RouteAtlasContextDefinition {
    guard
      let navigationRole = RouteAtlasContextNavigationRole(
        rawValue: try value.requiredString("navigation_role")
      ),
      let projectionValue = value.object("projection"),
      let projectionKind = RouteAtlasContextProjectionKind(
        rawValue: try projectionValue.requiredString("kind")
      ),
      let northUp = projectionValue.bool("north_up"),
      let sourceCRS = RouteAtlasContextSourceCRS(
        rawValue: try projectionValue.requiredString("source_crs")
      ),
      let coordinateSpace = RouteAtlasContextCoordinateSpace(
        rawValue: try projectionValue.requiredString("coordinate_space")
      ),
      let minimumLongitude = projectionValue.double("minimum_longitude"),
      let maximumLongitude = projectionValue.double("maximum_longitude"),
      let minimumLatitude = projectionValue.double("minimum_latitude"),
      let maximumLatitude = projectionValue.double("maximum_latitude"),
      let coverageValue = value.object("coverage"),
      let sourceFeatureCount = coverageValue.int("source_feature_count"),
      let pathCount = coverageValue.int("path_count"),
      let vertexCount = coverageValue.int("vertex_count"),
      let routeNameCount = coverageValue.int("route_name_count"),
      let pathValues = value.array("paths")
    else {
      throw ScenarioExecutionError.invalidInput("route_atlas_context")
    }

    let paths = try pathValues.map { value in
      guard
        let path = value.objectValue,
        let sourcePartIndex = path.int("source_part_index"),
        let useStatus = RouteAtlasContextUseStatus(
          rawValue: try path.requiredString("use_status")
        ),
        let pointValues = path.array("points")
      else {
        throw ScenarioExecutionError.invalidInput("route_atlas_context.paths")
      }
      let points = try pointValues.map { value in
        guard
          let point = value.objectValue,
          let x = point.double("x"),
          let y = point.double("y")
        else {
          throw ScenarioExecutionError.invalidInput(
            "route_atlas_context.paths.points"
          )
        }
        return RouteAtlasContextPoint(x: x, y: y)
      }
      return RouteAtlasContextPath(
        id: try path.requiredString("path_id"),
        sourceFeatureID: try path.requiredString("source_feature_id"),
        sourceRecordID: try path.requiredString("source_record_id"),
        sourcePartIndex: sourcePartIndex,
        routeNameJA: try path.requiredString("route_name_ja"),
        useStatus: useStatus,
        points: points
      )
    }

    return RouteAtlasContextDefinition(
      schemaVersion: try value.requiredString("schema_version"),
      id: try value.requiredString("context_id"),
      navigationRole: navigationRole,
      sourceReferenceID: try value.requiredString("source_reference_id"),
      projection: RouteAtlasContextProjection(
        kind: projectionKind,
        northUp: northUp,
        sourceCRS: sourceCRS,
        coordinateSpace: coordinateSpace,
        minimumLongitude: minimumLongitude,
        maximumLongitude: maximumLongitude,
        minimumLatitude: minimumLatitude,
        maximumLatitude: maximumLatitude
      ),
      coverage: RouteAtlasContextCoverage(
        sourceFeatureCount: sourceFeatureCount,
        pathCount: pathCount,
        vertexCount: vertexCount,
        routeNameCount: routeNameCount
      ),
      paths: paths
    )
  }

  private func routeMatcherObservation(
    _ payload: [String: JSONValue]
  ) throws -> RouteMatcherObservation {
    guard let coordinate = payload.object("coordinate"),
      let latitude = coordinate.double("latitude"),
      let longitude = coordinate.double("longitude"),
      let observedAtMilliseconds = payload.int("observed_at_ms"),
      let receivedAtMilliseconds = payload.int("received_at_ms"),
      let horizontalAccuracyMeters = payload.double("horizontal_accuracy_meters")
    else {
      throw ScenarioExecutionError.invalidInput("matcher_observation")
    }
    let sourceValue = payload.string("source") ?? MatcherLocationSource.phone.rawValue
    guard let source = MatcherLocationSource(rawValue: sourceValue) else {
      throw ScenarioExecutionError.invalidInput("matcher_observation.source")
    }
    return RouteMatcherObservation(
      id: payload.string("observation_id"),
      observedAtMilliseconds: observedAtMilliseconds,
      receivedAtMilliseconds: receivedAtMilliseconds,
      coordinate: MatcherCoordinate(latitude: latitude, longitude: longitude),
      horizontalAccuracyMeters: horizontalAccuracyMeters,
      courseDegrees: payload.double("course_degrees"),
      speedMetersPerSecond: payload.double("speed_meters_per_second"),
      source: source
    )
  }

  private func facilityKind(_ value: String) throws -> FacilityKind {
    guard let kind = FacilityKind(rawValue: value) else {
      throw ScenarioExecutionError.invalidInput("facility.kind")
    }
    return kind
  }

  private func reviewedRouteEditorCatalog(
    _ value: [String: JSONValue]
  ) throws -> ReviewedRouteEditorCatalog {
    guard let entranceValues = value.array("entrances"),
      let decisionPointValues = value.array("decision_points")
    else {
      throw ScenarioExecutionError.invalidInput("expert_route_editor_catalog")
    }
    let entrances = try entranceValues.map { entranceValue in
      guard let entrance = entranceValue.objectValue else {
        throw ScenarioExecutionError.invalidInput("expert_route_editor_catalog.entrances")
      }
      return ReviewedRouteEditorEntrance(
        facilityID: try entrance.requiredString("facility_id"),
        initialEdgeID: try entrance.requiredString("initial_edge_id"),
        initialEdgeTollDomainID: try entrance.requiredString(
          "initial_edge_toll_domain_id"
        ),
        firstDecisionPointID: try entrance.requiredString("first_decision_point_id")
      )
    }
    let decisionPoints = try decisionPointValues.map { decisionPointValue in
      guard let decisionPoint = decisionPointValue.objectValue,
        let choiceValues = decisionPoint.array("choices")
      else {
        throw ScenarioExecutionError.invalidInput(
          "expert_route_editor_catalog.decision_points"
        )
      }
      let choices = try choiceValues.map { choiceValue in
        guard let choice = choiceValue.objectValue else {
          throw ScenarioExecutionError.invalidInput(
            "expert_route_editor_catalog.choices"
          )
        }
        let nextDecisionPointID = choice.string("next_decision_point_id")
        let exitFacilityID = choice.string("exit_facility_id")
        let destination: ReviewedRouteEditorDestination
        switch (nextDecisionPointID, exitFacilityID) {
        case (.some(let id), .none):
          destination = .decisionPoint(id)
        case (.none, .some(let id)):
          destination = .exitFacility(id)
        default:
          throw ScenarioExecutionError.invalidInput(
            "expert_route_editor_catalog.choice.destination"
          )
        }
        return ReviewedRouteEditorChoice(
          id: try choice.requiredString("choice_id"),
          movementID: try choice.requiredString("movement_id"),
          movementTollDomainID: try choice.requiredString("movement_toll_domain_id"),
          outgoingEdgeID: try choice.requiredString("outgoing_edge_id"),
          outgoingEdgeTollDomainID: try choice.requiredString(
            "outgoing_edge_toll_domain_id"
          ),
          destination: destination
        )
      }
      return ReviewedRouteEditorDecisionPoint(
        id: try decisionPoint.requiredString("decision_point_id"),
        incomingApproachID: try decisionPoint.requiredString("incoming_approach_id"),
        junctionComplexID: try decisionPoint.requiredString("junction_complex_id"),
        choices: choices
      )
    }
    let lapTemplateValues: [JSONValue]
    if value["lap_templates"] == nil {
      lapTemplateValues = []
    } else if let values = value.array("lap_templates") {
      lapTemplateValues = values
    } else {
      throw ScenarioExecutionError.invalidInput(
        "expert_route_editor_catalog.lap_templates"
      )
    }
    let lapTemplates = try lapTemplateValues.map { templateValue in
      guard let template = templateValue.objectValue else {
        throw ScenarioExecutionError.invalidInput(
          "expert_route_editor_catalog.lap_templates"
        )
      }
      return ReviewedRouteEditorLapTemplate(
        id: try template.requiredString("template_id"),
        startDecisionPointID: try template.requiredString(
          "start_decision_point_id"
        ),
        choiceIDs: try requiredStrings(template, key: "choice_ids")
      )
    }
    return ReviewedRouteEditorCatalog(
      networkSnapshotID: try value.requiredString("network_snapshot_id"),
      entrances: entrances,
      decisionPoints: decisionPoints,
      lapTemplates: lapTemplates
    )
  }

  private func routeEditorInteraction(
    _ payload: [String: JSONValue]
  ) throws -> RouteEditorInteractionContext {
    guard let vehicleMoving = payload.bool("vehicle_moving") else {
      throw ScenarioExecutionError.invalidInput("vehicle_moving")
    }
    return vehicleMoving ? .moving : .parked
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
      "guidance.anchor_status": .string(guidanceAnchorStatus.rawValue),
      "guidance.planning_status": .string(guidancePlanningStatus.rawValue),
      "guidance.emitted_prompt_ids": .strings(emittedGuidancePromptIDs),
      "guidance.emitted_prompt_count": .integer(emittedGuidancePromptIDs.count),
      "presentation.active_surface": .string(presentationSurface.rawValue),
      "presentation.carplay_connection_state": .string(carPlayConnectionState.rawValue),
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
    if let lastGuidancePromptID {
      values["guidance.last_prompt_id"] = .string(lastGuidancePromptID)
    }
    if let activeGuidanceFrame {
      values["guidance.active_frame.prompt_id"] = .string(activeGuidanceFrame.promptID)
      values["guidance.active_frame.anchor_id"] = .string(activeGuidanceFrame.anchorID)
      values["guidance.active_frame.anchor_occurrence_id"] = .string(
        activeGuidanceFrame.anchorOccurrenceID
      )
      values["guidance.active_frame.movement_occurrence_id"] = .string(
        activeGuidanceFrame.movementOccurrenceID
      )
      values["guidance.active_frame.decision_zone_id"] = .string(
        activeGuidanceFrame.decisionZoneID
      )
      values["guidance.active_frame.stage"] = .string(activeGuidanceFrame.stage.rawValue)
      values["guidance.active_frame.distance_meters"] = .number(
        activeGuidanceFrame.distanceMeters
      )
    }
    if let lastGuidanceProgressAtMilliseconds {
      values["guidance.last_progress_at_ms"] = .integer(
        lastGuidanceProgressAtMilliseconds
      )
    }
    if let lastPresentationTransitionTrigger {
      values["presentation.last_transition_trigger"] = .string(
        lastPresentationTransitionTrigger
      )
    }
    return values
  }
}
