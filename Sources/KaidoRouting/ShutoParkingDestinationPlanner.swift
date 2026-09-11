import Foundation

extension ShutoRoutePlanner {
  /// The arrival point is on the reviewed parking interior, nearest the PA's
  /// own point. Return ramps are not part of a journey that ends in the PA.
  func parkingArrivalEdges(_ parking: ShutoNetworkDatabase.ParkingArea) throws -> [ShutoNetworkDatabase.Edge] {
    guard let ids = parking.interiorEdgeIDs, !ids.isEmpty else { throw ShutoNetworkError.facilityUnavailable }
    let edges = ids.compactMap { edgesByID[$0] }
    guard edges.count == ids.count, edges.allSatisfy({ $0.kind == "PARKING" }),
      edges.first?.fromNodeID == parking.accessNodeID else { throw ShutoNetworkError.facilityUnavailable }
    let arrival = edges.indices.min {
      Self.distance(nodesByID[edges[$0].toNodeID]!.coordinate, parking.coordinate)
        < Self.distance(nodesByID[edges[$1].toNodeID]!.coordinate, parking.coordinate)
    }!
    return Array(edges[...arrival])
  }

  public func plan(
    entryFacilityID: String,
    destinationParkingAreaID: String,
    preference: ShutoRoutePreference = .recommended
  ) throws -> ShutoPlannedRoute {
    guard let entry = facilitiesByID[entryFacilityID], entry.canEnter,
      let parking = database.parkingAreas.first(where: { $0.parkingAreaID == destinationParkingAreaID }),
      let access = parking.accessNodeID else { throw ShutoNetworkError.facilityUnavailable }
    let arrival = try parkingArrivalEdges(parking)
    let seeds = entry.entryEdgeCandidates.compactMap { candidate in
      edgesByID[candidate.edgeID].map { (edge: $0, cost: candidate.distanceMeters + edgeCost($0, preference: preference)) }
    }
    guard let approach = circuitDijkstra(seeds: seeds, cost: { edgeCost($0, preference: preference) }, isTarget: { $0 == access }) else {
      throw ShutoNetworkError.routeUnavailable
    }
    return assemblePlannedRoute(
      routeEdges: approach.edges + arrival,
      planID: "shuto.\(entryFacilityID).\(destinationParkingAreaID).\(preference.rawValue.lowercased())",
      entryFacility: entry, exitFacility: nil, destinationParkingArea: parking, preference: preference
    )
  }

  public func recommend(
    from origin: ShutoCoordinate,
    destinationParkingAreaID: String,
    preference: ShutoRoutePreference = .recommended
  ) -> [ShutoRouteRecommendation] {
    let entries = database.directionalFacilities.filter(\.canEnter).sorted {
      let a = Self.distance(origin, $0.coordinate), b = Self.distance(origin, $1.coordinate)
      return a == b ? $0.facilityID < $1.facilityID : a < b
    }
    var result: [ShutoRouteRecommendation] = []
    for entry in entries {
      guard let route = try? plan(entryFacilityID: entry.facilityID, destinationParkingAreaID: destinationParkingAreaID, preference: preference) else { continue }
      let access = Self.distance(origin, entry.coordinate)
      result.append(.init(route: route, surfaceAccessDistanceMeters: access, surfaceEgressDistanceMeters: 0, totalScoreMeters: route.distanceMeters + access * 1.25))
      if result.count == 3 { break }
    }
    return result
  }
}
