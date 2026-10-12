import KaidoDomain
import XCTest

@testable import KaidoRoutesApp

@MainActor
final class DriveHistoryStoreTests: XCTestCase {
  func testHistorySurvivesReopeningAndDeletionTargetsOneRecord() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = try entry(start: 1_000)
    let second = try entry(start: 10_000)
    let store = FileDriveHistoryStore(directory: directory)
    try store.save(first)
    try store.save(second)
    let reopened = FileDriveHistoryStore(directory: directory)
    let reloaded = try await reopened.load()
    XCTAssertEqual(reloaded.map(\.id), [second.id, first.id])
    try reopened.remove(id: second.id)
    let afterRemoval = try await reopened.load()
    XCTAssertEqual(afterRemoval, [first])
  }

  func testABadHistoryFileHidesOnlyItself() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let kept = try entry(start: 10_000)
    let store = FileDriveHistoryStore(directory: directory)
    try store.save(kept)
    try JSONEncoder().encode(entry(start: 1_000))
      .write(to: directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
    try Data("not-a-drive".utf8)
      .write(to: directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
    let loaded = try await store.load()
    XCTAssertEqual(loaded, [kept])
  }

  private func entry(start: Int) throws -> DriveHistoryEntry {
    var record = WholeShutoDriveRecord(startedAtMilliseconds: start)
    record.observe(speedMetersPerSecond: 10, atMilliseconds: start)
    record.observe(speedMetersPerSecond: 10, atMilliseconds: start + 1_000)
    record.finish(atMilliseconds: start + 1_000)
    let plan = RoutePlan(
      id: "test.history.plan", networkSnapshotID: "test.history.network",
      entryFacilityID: "test.entry", exitFacilityID: "test.exit", recoveryPolicy: .strict,
      occurrences: [RouteOccurrence(id: "test.edge.0", index: 0, kind: .edge, entityID: "test.edge")]
    )
    return try XCTUnwrap(DriveHistoryEntry(record: record, routePlan: plan,
      routeName: "Test route", templateParameters: [:], arrived: false))
  }
}
