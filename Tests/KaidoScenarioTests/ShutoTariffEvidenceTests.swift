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
      evidence: .etcNormalCarUntil2026September
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
      exitFacilityID: circuit.routePlan.exitFacilityID!,
      evidence: .etcNormalCarUntil2026September
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
      evidence: .etcNormalCarUntil2026September
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
      evidence: .etcNormalCarUntil2026September
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
    let evidence = ShutoTariffEvidence.etcNormalCarUntil2026September

    #expect(evidence.status == "ACTIVE")
    #expect(evidence.checkedAt == "2026-09-12")
    #expect(evidence.sourceURL.hasPrefix("https://www.shutoko.jp/"))
    #expect(evidence.minimumYen == 300)
    #expect(evidence.maximumYen == 1_950)
    #expect(evidence.effectiveUntil == "2026-09-30")
  }

  @Test("the 2026-10-01 revision is dated, sourced, and priced by the operator formula")
  func revisionIsDatedAndPricedByTheFormula() {
    let revision = ShutoTariffEvidence.etcNormalCarFrom2026October

    #expect(revision.status == "ACTIVE")
    #expect(revision.effectiveFrom == "2026-10-01")
    #expect(revision.checkedAt == "2026-09-12")
    #expect(revision.sourceURL == "https://www.shutoko.jp/ss/2026ryoukin-kaitei/")
    #expect(revision.yenPerKilometer == 32.472)
    #expect(revision.minimumYen == 300)
    // (55.0 km × 32.472 + 150) × 1.10 = 2,129.6 in 10 yen units.
    let capRaw = revision.rawYen(forTariffDistanceMeters: 55_000)
    #expect(abs(capRaw - 2_129.6) < 0.05)
    #expect(Int((capRaw / 10).rounded()) * 10 == revision.maximumYen)
    #expect(revision.maximumYen == 2_130)
    // The current cap follows the same rounding of the same formula.
    let current = ShutoTariffEvidence.etcNormalCarUntil2026September
    let currentCapRaw = current.rawYen(forTariffDistanceMeters: 55_000)
    #expect(Int((currentCapRaw / 10).rounded()) * 10 == current.maximumYen)
  }

  @Test("the payable rule follows the JST calendar day, never early")
  func payableRuleFollowsTheDay() {
    #expect(
      ShutoTariffEvidence.etcNormalCar(effectiveOn: "2026-09-12")
        == .etcNormalCarUntil2026September
    )
    #expect(
      ShutoTariffEvidence.etcNormalCar(effectiveOn: "2026-09-30")
        == .etcNormalCarUntil2026September
    )
    #expect(
      ShutoTariffEvidence.etcNormalCar(effectiveOn: "2026-10-01")
        == .etcNormalCarFrom2026October
    )
    #expect(
      ShutoTariffEvidence.etcNormalCar(effectiveOn: "2027-01-15")
        == .etcNormalCarFrom2026October
    )
  }

  @Test("a capped pairing is quoted at the revised cap once the revision is payable")
  func cappedPairingFollowsTheRevision() throws {
    let planner = try ShutoRoutePlanner(database: loadDatabase())
    let before = try planner.tariffBand(
      entryFacilityID: "shuto.ic.6-misato.kahei",
      exitFacilityID: "shuto.ic.b.sachiura",
      evidence: .etcNormalCarUntil2026September
    )
    let after = try planner.tariffBand(
      entryFacilityID: "shuto.ic.6-misato.kahei",
      exitFacilityID: "shuto.ic.b.sachiura",
      evidence: .etcNormalCarFrom2026October
    )
    #expect(before == .maximum(yen: 1_950))
    #expect(after == .maximum(yen: 2_130))
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
