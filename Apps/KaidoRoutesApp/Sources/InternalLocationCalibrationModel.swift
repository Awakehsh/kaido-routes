import Combine
import CoreLocation
import Foundation
import KaidoAppleAdapters
import KaidoNavigation
import UIKit

enum InternalCalibrationTransportMode: String, CaseIterable, Identifiable, Sendable {
  case phoneOnly = "PHONE ONLY"
  case connectedUnknown = "CARPLAY · UNKNOWN"
  case fieldDeclaredWired = "FIELD · WIRED"
  case fieldDeclaredWireless = "FIELD · WIRELESS"

  var id: String { rawValue }

  var connectionContext: AppleCarPlayConnectionContext {
    switch self {
    case .phoneOnly:
      .disconnected
    case .connectedUnknown:
      .connectedTransportUnknown
    case .fieldDeclaredWired:
      .fieldDeclaredWired
    case .fieldDeclaredWireless:
      .fieldDeclaredWireless
    }
  }

  var fieldTransportContext: MatcherFieldTransportContext {
    switch self {
    case .phoneOnly:
      .phoneOnly
    case .connectedUnknown:
      .carPlayConnectedTransportUnknown
    case .fieldDeclaredWired:
      .fieldDeclaredWiredCarPlay
    case .fieldDeclaredWireless:
      .fieldDeclaredWirelessCarPlay
    }
  }
}

enum InternalLocationCalibrationState: Equatable, Sendable {
  case idle
  case awaitingAuthorization
  case collecting
  case stopped
  case permissionDenied
  case failed(String)

  var label: String {
    switch self {
    case .idle:
      "IDLE"
    case .awaitingAuthorization:
      "AWAITING PERMISSION"
    case .collecting:
      "COLLECTING"
    case .stopped:
      "STOPPED · MEMORY HELD"
    case .permissionDenied:
      "LOCATION DENIED"
    case .failed:
      "FAILED"
    }
  }
}

struct InternalLocationCalibrationSummary: Equatable, Sendable {
  var entryCount = 0
  var matchedCount = 0
  var adapterRejectionCount = 0
  var matcherRejectionCount = 0
  var lastConfidence: MatcherConfidence?
  var lastSource: MatcherLocationSource?
}

struct InternalLocationCalibrationRun {
  private(set) var session: CoreLocationMatcherCalibrationSession
  private(set) var summary = InternalLocationCalibrationSummary()

  init(session: CoreLocationMatcherCalibrationSession) {
    self.session = session
  }

  mutating func process(
    _ locations: [CLLocation],
    receivedAt: Date = Date()
  ) throws {
    let outcomes = try session.process(locations, receivedAt: receivedAt)
    for outcome in outcomes {
      summary.entryCount += 1
      switch outcome {
      case .adapterRejected:
        summary.adapterRejectionCount += 1
      case .matched(let envelope, let estimate):
        summary.matchedCount += 1
        summary.lastConfidence = estimate.confidence
        summary.lastSource = envelope.provenance.matcherCalibrationCohort
      case .matcherRejected(let envelope, _):
        summary.matcherRejectionCount += 1
        summary.lastSource = envelope.provenance.matcherCalibrationCohort
      }
    }
  }

  func makeCoordinateFreeReport(reportID: String) throws -> MatcherCalibrationReport? {
    guard summary.entryCount > 0 else { return nil }
    return try MatcherCalibrationEvaluator.evaluate(
      traces: [session.privateTrace],
      annotations: [],
      reportID: reportID
    )
  }
}

@MainActor
final class InternalLocationCalibrationModel: NSObject, ObservableObject {
  @Published private(set) var state: InternalLocationCalibrationState = .idle
  @Published private(set) var summary = InternalLocationCalibrationSummary()
  @Published private(set) var report: MatcherCalibrationReport?
  @Published private(set) var lastEvent = "尚未请求定位权限"
  @Published var transportMode: InternalCalibrationTransportMode = .phoneOnly
  @Published var deviceConfigurationID = ""
  @Published var mountDescription = ""

  let fixture: InternalLocationCalibrationFixture

  private let locationManager: CLLocationManager
  private var run: InternalLocationCalibrationRun?
  private var pendingStart = false

  init(
    fixture: InternalLocationCalibrationFixture,
    locationManager: CLLocationManager = CLLocationManager()
  ) {
    self.fixture = fixture
    self.locationManager = locationManager
    super.init()
    locationManager.delegate = self
    locationManager.activityType = .automotiveNavigation
    locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    locationManager.distanceFilter = kCLDistanceFilterNone
    locationManager.pausesLocationUpdatesAutomatically = false
    locationManager.allowsBackgroundLocationUpdates = false
  }

  var canStart: Bool {
    switch state {
    case .idle, .stopped, .permissionDenied, .failed:
      return validRunMetadata
    case .awaitingAuthorization, .collecting:
      return false
    }
  }

  var canStop: Bool {
    state == .collecting
  }

  var canDiscard: Bool {
    run != nil || report != nil
  }

  var authorizationLabel: String {
    switch locationManager.authorizationStatus {
    case .notDetermined:
      "NOT DETERMINED"
    case .restricted:
      "RESTRICTED"
    case .denied:
      "DENIED"
    case .authorizedAlways:
      "AUTHORIZED ALWAYS"
    case .authorizedWhenInUse:
      "AUTHORIZED IN USE"
    @unknown default:
      "UNKNOWN"
    }
  }

  func start() {
    guard canStart else { return }
    report = nil
    summary = InternalLocationCalibrationSummary()
    switch locationManager.authorizationStatus {
    case .notDetermined:
      pendingStart = true
      state = .awaitingAuthorization
      lastEvent = "等待用户授予使用期间定位权限"
      locationManager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      beginCollection()
    case .denied, .restricted:
      pendingStart = false
      state = .permissionDenied
      lastEvent = "定位权限被拒绝；未创建私有 trace"
    @unknown default:
      pendingStart = false
      state = .failed("UNKNOWN_AUTHORIZATION_STATUS")
      lastEvent = "未知定位授权状态"
    }
  }

  func stop() {
    guard state == .collecting else { return }
    locationManager.stopUpdatingLocation()
    pendingStart = false
    do {
      report = try run?.makeCoordinateFreeReport(
        reportID: "internal-device-profile-\(Int(Date().timeIntervalSince1970))"
      )
      state = .stopped
      lastEvent =
        report == nil
        ? "采集已停止；没有可报告的 observation"
        : "采集已停止；仅保留内存 trace 与坐标无关报告"
    } catch {
      state = .failed(Self.errorCode(error))
      lastEvent = "生成坐标无关报告失败"
    }
  }

  func discard() {
    locationManager.stopUpdatingLocation()
    pendingStart = false
    run = nil
    report = nil
    summary = InternalLocationCalibrationSummary()
    state = .idle
    lastEvent = "内存 trace 已丢弃"
  }

  func coordinateFreeReportJSON() throws -> Data? {
    guard let report else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(report)
  }

  private var validRunMetadata: Bool {
    !deviceConfigurationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !mountDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func beginCollection() {
    do {
      run = try makeRun()
      summary = InternalLocationCalibrationSummary()
      state = .collecting
      pendingStart = false
      lastEvent = "前台采集中；原始坐标仅存在内存"
      locationManager.startUpdatingLocation()
    } catch {
      run = nil
      pendingStart = false
      state = .failed(Self.errorCode(error))
      lastEvent = "无法创建 snapshot-bound 校准 session"
    }
  }

  private func makeRun() throws -> InternalLocationCalibrationRun {
    let runID = UUID().uuidString.lowercased()
    let observationAdapter = try CoreLocationObservationAdapter(
      sessionID: "internal-calibration.\(runID)",
      simulatedLocationPolicy: .reject,
      carPlayConnectionContext: transportMode.connectionContext
    )
    let matcherSession = try RouteAwareSwiftMatcher().makeSession(
      corridor: fixture.corridor,
      initialOccurrenceID: fixture.initialOccurrenceID
    )
    let device = UIDevice.current
    let appVersion =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
      ?? "unversioned"
    let context = MatcherPrivateTraceContext(
      traceID: "private.\(runID)",
      scope: MatcherCalibrationScope(
        networkSnapshotID: fixture.corridor.networkSnapshotID,
        matcherAlgorithmID: RouteAwareSwiftMatcher.algorithmID,
        matcherConfigurationID: "route-aware-swift-hmm-defaults-v1",
        deviceConfigurationID: deviceConfigurationID.trimmingCharacters(
          in: .whitespacesAndNewlines
        ),
        fieldTransportContext: transportMode.fieldTransportContext
      ),
      routePlanID: fixture.corridor.routePlanID,
      deviceModel: device.model,
      operatingSystemVersion: "\(device.systemName) \(device.systemVersion)",
      appBuild: appVersion,
      mountDescription: mountDescription.trimmingCharacters(
        in: .whitespacesAndNewlines
      ),
      collectionMethod: .automatedLogger,
      startedAtMilliseconds: Int(Date().timeIntervalSince1970 * 1_000)
    )
    let session = try CoreLocationMatcherCalibrationSession(
      observationAdapter: observationAdapter,
      matcherSession: matcherSession,
      traceRecorder: CoreLocationPrivateTraceRecorder(context: context)
    )
    return InternalLocationCalibrationRun(session: session)
  }

  private func process(_ locations: [CLLocation]) {
    guard state == .collecting, var run else { return }
    do {
      try run.process(locations)
      self.run = run
      summary = run.summary
      lastEvent = "已处理 \(summary.entryCount) 个 observation"
    } catch {
      self.run = run
      locationManager.stopUpdatingLocation()
      state = .failed(Self.errorCode(error))
      lastEvent = "adapter-to-matcher pipeline 失败并停止"
    }
  }

  private static func errorCode(_ error: Error) -> String {
    String(describing: error).uppercased()
  }
}

extension InternalLocationCalibrationModel: @preconcurrency CLLocationManagerDelegate {
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard pendingStart else { return }
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      beginCollection()
    case .denied, .restricted:
      pendingStart = false
      state = .permissionDenied
      lastEvent = "定位权限被拒绝；未创建私有 trace"
    case .notDetermined:
      state = .awaitingAuthorization
    @unknown default:
      pendingStart = false
      state = .failed("UNKNOWN_AUTHORIZATION_STATUS")
    }
  }

  func locationManager(
    _: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    process(locations)
  }

  func locationManager(_: CLLocationManager, didFailWithError error: Error) {
    if let coreLocationError = error as? CLError,
      coreLocationError.code == .locationUnknown
    {
      lastEvent = "暂时没有定位 fix；继续等待"
      return
    }
    locationManager.stopUpdatingLocation()
    state = .failed(Self.errorCode(error))
    lastEvent = "Core Location 失败并停止"
  }
}
