import Foundation
import KaidoRouting
import Testing

@Suite("Shuto tariff evidence")
struct ShutoTariffEvidenceTests {
  @Test("a short entry-exit pairing lands in the minimum band")
  func shortPairingIsMinimumBand() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())

    // Hatsudai-minami to Tomigaya is ~1.2 km of tariff distance; even with
    // the geometry margin the formula stays at or below the lower limit.
    let band = try planner.tariffBand(
      entryFacilityID: "shuto.ic.c2.hatsudaiminami",
      exitFacilityID: "shuto.ic.c2.tomigaya",
      evidence: .etcNormalCarActive
    )

    #expect(band == .minimum(yen: 300))
  }

  @Test("laps never change the band because the pairing sets it")
  func lapsDoNotChangeTheBand() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())

    // The driven circuit is ~112 km over two laps, but the tariff pairing
    // is still the ~1.2 km shortest path between entry and exit.
    let circuit = try planner.planCircuit(
      circuit: .c2InnerWithBayshore,
      entryFacilityID: "shuto.ic.c2.hatsudaiminami",
      exitFacilityID: "shuto.ic.c2.tomigaya",
      laps: 2
    )
    let band = try planner.tariffBand(
      entryFacilityID: circuit.routePlan.entryFacilityID,
      exitFacilityID: circuit.routePlan.exitFacilityID,
      evidence: .etcNormalCarActive
    )

    #expect(circuit.distanceMeters > 100_000)
    #expect(band == .minimum(yen: 300))
  }

  @Test("a long pairing is estimated or capped, never invented precisely")
  func longPairingIsEstimatedOrCapped() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())

    // Shibuya to Minato Mirai crosses most of the network (~30 km).
    let band = try planner.tariffBand(
      entryFacilityID: "shuto.ic.3.shibuya",
      exitFacilityID: "shuto.ic.k1.minatomirai",
      evidence: .etcNormalCarActive
    )

    switch band {
    case .minimum:
      Issue.record("A ~30 km pairing cannot be the minimum band")
    case .estimated(let yen):
      #expect(yen > 300)
      #expect(yen <= 1_950)
    case .maximum(let yen):
      #expect(yen == 1_950)
    }
  }

  @Test("the folklore Shinjuku-to-Yoyogi pairing prices the full circuit")
  func shinjukuToYoyogiPricesTheFullCircuit() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())

    // The Yoyogi exit serves only the down carriageway, so the legal fare
    // path from the Shinjuku up entrance rides the full C1 circuit
    // (~21.4 km). The operator fare search priced this exact pairing at
    // 860 yen on 2026-08-04; the band's ±500 m geometry margin may quote
    // one 10-yen step high, never low. A cheap quote here means a
    // parking-area ramp or a neighbouring facility's ramp leaked back
    // into the Yoyogi exit candidates.
    let band = try planner.tariffBand(
      entryFacilityID: "shuto.ic.4.shinjuku",
      exitFacilityID: "shuto.ic.4.yoyogi",
      evidence: .etcNormalCarActive
    )

    switch band {
    case .estimated(let yen):
      #expect(yen >= 860)
      #expect(yen <= 880)
    default:
      Issue.record("Expected an estimated band, got \(band)")
    }
  }

  @Test("the active evidence stays dated and sourced")
  func evidenceIsDatedAndSourced() {
    let evidence = ShutoTariffEvidence.etcNormalCarActive

    #expect(evidence.status == "ACTIVE")
    #expect(evidence.checkedAt == "2026-08-03")
    #expect(evidence.sourceURL.hasPrefix("https://www.shutoko.jp/"))
    #expect(evidence.minimumYen == 300)
    #expect(evidence.maximumYen == 1_950)
  }

  private func loadDatabase() throws -> ShutoNetworkDatabase {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let url = repositoryRoot
      .appendingPathComponent("data")
      .appendingPathComponent("route-atlas")
      .appendingPathComponent("osm-derived")
      .appendingPathComponent("shuto-whole-network-20260804.json")
    return try JSONDecoder().decode(
      ShutoNetworkDatabase.self,
      from: Data(contentsOf: url)
    )
  }
}
