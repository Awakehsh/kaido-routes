import CryptoKit
import Foundation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation
import Testing

@Test("A complete guidance audio release resolves only exact released commands")
func guidanceAudioReleaseResolvesExactCommands() throws {
  let productRelease = try guidanceAudioProductRelease()
  let fixture = guidanceAudioManifestFixture(productRelease)

  let encoded = try GuidanceAudioReleaseManifestCodec.encode(
    fixture.manifest,
    productRelease: productRelease,
    resourceProvider: { fixture.resources[$0] }
  )
  let repeated = try GuidanceAudioReleaseManifestCodec.encode(
    fixture.manifest,
    productRelease: productRelease,
    resourceProvider: { fixture.resources[$0] }
  )
  let release = try GuidanceAudioReleaseManifestCodec.decode(
    encoded,
    productRelease: productRelease,
    resourceProvider: { fixture.resources[$0] }
  )

  #expect(encoded == repeated)
  #expect(release.assets.count == fixture.manifest.assets.count)
  #expect(
    release.assets.count
      == productRelease.navigation.bundle.releasedGuidance.count
      * KaidoReleaseLocale.allCases.count
  )

  let record = try #require(
    release.assets.first {
      $0.record.key.languageCode == "ja-JP"
    }?.record
  )
  let exact = guidanceAudioCommand(
    record: record,
    routePlanID: productRelease.navigation.bundle.routePlan.id
  )
  #expect(release.asset(matching: exact)?.record == record)

  let textDrift = GuidanceSpeechCommand(
    identity: exact.identity,
    routePlanID: exact.routePlanID,
    languageCode: exact.languageCode,
    spokenText: "\(exact.spokenText) drift"
  )
  #expect(release.asset(matching: textDrift) == nil)

  let routeDrift = GuidanceSpeechCommand(
    identity: exact.identity,
    routePlanID: "test.plan.other",
    languageCode: exact.languageCode,
    spokenText: exact.spokenText
  )
  #expect(release.asset(matching: routeDrift) == nil)
}

@Test("A guidance audio pack must cover every released occurrence and locale")
func guidanceAudioReleaseRequiresCompleteCoverage() throws {
  let productRelease = try guidanceAudioProductRelease()
  let fixture = guidanceAudioManifestFixture(productRelease)
  let missingRecord = try #require(fixture.manifest.assets.last)
  let incomplete = GuidanceAudioReleaseManifest(
    releaseID: fixture.manifest.releaseID,
    releasedAt: fixture.manifest.releasedAt,
    productReleaseID: fixture.manifest.productReleaseID,
    navigationReleaseID: fixture.manifest.navigationReleaseID,
    networkSnapshotID: fixture.manifest.networkSnapshotID,
    routePlanID: fixture.manifest.routePlanID,
    assets: Array(fixture.manifest.assets.dropLast())
  )

  do {
    _ = try GuidanceAudioRelease(
      manifest: incomplete,
      productRelease: productRelease,
      resourceProvider: { fixture.resources[$0] }
    )
    Issue.record("Expected incomplete guidance audio coverage to fail")
  } catch GuidanceAudioReleaseError.invalid(let issues) {
    #expect(issues.contains(.missingAsset(missingRecord.key)))
    #expect(issues.count == 1)
  }
}

@Test("Corrupt, silent, or hash-drifted WAV assets reject the whole audio pack")
func guidanceAudioReleaseRejectsInvalidWaveResources() throws {
  let productRelease = try guidanceAudioProductRelease()
  let fixture = guidanceAudioManifestFixture(productRelease)
  let record = try #require(fixture.manifest.assets.first)
  let original = try #require(fixture.resources[record.resourceFilename])
  let silentData = guidanceTestWaveData(
    sampleRateHz: record.sampleRateHz,
    frameCount: 2_400,
    sampleValue: 0
  )
  var resources = fixture.resources
  resources[record.resourceFilename] = GuidanceAudioResource(
    url: original.url,
    data: silentData
  )

  do {
    _ = try GuidanceAudioRelease(
      manifest: fixture.manifest,
      productRelease: productRelease,
      resourceProvider: { resources[$0] }
    )
    Issue.record("Expected invalid audio bytes to reject the pack")
  } catch GuidanceAudioReleaseError.invalid(let issues) {
    #expect(issues.contains(.resourceHashMismatch(record.resourceFilename)))
    #expect(issues.contains(.invalidWaveAudio(record.resourceFilename)))
  }
}

@Test("Guidance audio resources must be local files")
func guidanceAudioReleaseRejectsRemoteResourceURL() throws {
  let productRelease = try guidanceAudioProductRelease()
  let fixture = guidanceAudioManifestFixture(productRelease)
  let record = try #require(fixture.manifest.assets.first)
  let original = try #require(fixture.resources[record.resourceFilename])
  var resources = fixture.resources
  resources[record.resourceFilename] = GuidanceAudioResource(
    url: URL(string: "https://example.com/\(record.resourceFilename)")!,
    data: original.data
  )

  do {
    _ = try GuidanceAudioRelease(
      manifest: fixture.manifest,
      productRelease: productRelease,
      resourceProvider: { resources[$0] }
    )
    Issue.record("Expected a remote audio resource URL to fail")
  } catch GuidanceAudioReleaseError.invalid(let issues) {
    #expect(
      issues == [.resourceURLInvalid(record.resourceFilename)]
    )
  }
}

@Test("Audio provenance cannot postdate its reviewed release")
func guidanceAudioReleaseRejectsFutureProvenance() throws {
  let productRelease = try guidanceAudioProductRelease()
  let fixture = guidanceAudioManifestFixture(productRelease)
  let original = try #require(fixture.manifest.assets.first)
  let futureProvenance = GuidanceAudioSynthesisProvenance(
    generationMode: original.provenance.generationMode,
    engineID: original.provenance.engineID,
    engineVersion: original.provenance.engineVersion,
    modelID: original.provenance.modelID,
    modelRevision: original.provenance.modelRevision,
    voiceID: original.provenance.voiceID,
    licenceIdentifier: original.provenance.licenceIdentifier,
    sourceURL: original.provenance.sourceURL,
    generatedAt: "2026-07-25T16:00:00+09:00",
    reviewedAt: "2026-07-25T17:00:00+09:00"
  )
  let driftedRecord = GuidanceAudioAssetRecord(
    key: original.key,
    spokenText: original.spokenText,
    spokenTextSHA256: original.spokenTextSHA256,
    resourceFilename: original.resourceFilename,
    audioSHA256: original.audioSHA256,
    byteCount: original.byteCount,
    sampleRateHz: original.sampleRateHz,
    channelCount: original.channelCount,
    durationMilliseconds: original.durationMilliseconds,
    provenance: futureProvenance
  )
  var records = fixture.manifest.assets
  records[0] = driftedRecord
  let drifted = GuidanceAudioReleaseManifest(
    releaseID: fixture.manifest.releaseID,
    releasedAt: fixture.manifest.releasedAt,
    productReleaseID: fixture.manifest.productReleaseID,
    navigationReleaseID: fixture.manifest.navigationReleaseID,
    networkSnapshotID: fixture.manifest.networkSnapshotID,
    routePlanID: fixture.manifest.routePlanID,
    assets: records
  )

  do {
    _ = try GuidanceAudioRelease(
      manifest: drifted,
      productRelease: productRelease,
      resourceProvider: { fixture.resources[$0] }
    )
    Issue.record("Expected future synthesis review to fail")
  } catch GuidanceAudioReleaseError.invalid(let issues) {
    #expect(issues.contains(.invalidProvenance(original.key)))
    #expect(issues.count == 1)
  }
}

@MainActor
@Test("Exact released commands use recorded audio and preserve identity")
func releasedGuidanceAudioOutputUsesExactAsset() throws {
  let productRelease = try guidanceAudioProductRelease()
  let fixture = guidanceAudioManifestFixture(productRelease)
  let release = try GuidanceAudioRelease(
    manifest: fixture.manifest,
    productRelease: productRelease,
    resourceProvider: { fixture.resources[$0] }
  )
  let record = try #require(release.assets.first?.record)
  let command = guidanceAudioCommand(
    record: record,
    routePlanID: release.manifest.routePlanID
  )
  let player = RecordingGuidanceAudioPlayer()
  let fallback = RecordingGuidanceAudioFallback()
  let output = ReleasedGuidanceAudioOutput(
    release: release,
    player: player,
    fallback: fallback
  )
  var events: [GuidanceSpeechOutputEvent] = []
  output.eventHandler = { events.append($0) }

  try output.speak(command)
  let playback = try #require(player.requests.first)

  #expect(playback.asset.record == record)
  #expect(fallback.commands.isEmpty)
  #expect(events == [.didStart(command.identity)])

  player.finish(playback.playbackID)
  #expect(
    events
      == [
        .didStart(command.identity),
        .didFinish(command.identity),
      ]
  )
}

@MainActor
@Test("Lookup drift and recorded start failure use Apple speech fallback")
func releasedGuidanceAudioOutputFallsBackSafely() throws {
  let productRelease = try guidanceAudioProductRelease()
  let fixture = guidanceAudioManifestFixture(productRelease)
  let release = try GuidanceAudioRelease(
    manifest: fixture.manifest,
    productRelease: productRelease,
    resourceProvider: { fixture.resources[$0] }
  )
  let record = try #require(release.assets.first?.record)
  let exact = guidanceAudioCommand(
    record: record,
    routePlanID: release.manifest.routePlanID
  )
  let drifted = GuidanceSpeechCommand(
    identity: exact.identity,
    routePlanID: exact.routePlanID,
    languageCode: exact.languageCode,
    spokenText: "\(exact.spokenText) drift"
  )
  let player = RecordingGuidanceAudioPlayer()
  let fallback = RecordingGuidanceAudioFallback()
  let output = ReleasedGuidanceAudioOutput(
    release: release,
    player: player,
    fallback: fallback
  )
  var events: [GuidanceSpeechOutputEvent] = []
  output.eventHandler = { events.append($0) }

  try output.speak(drifted)
  #expect(player.requests.isEmpty)
  #expect(fallback.commands == [drifted])
  #expect(events == [.didStart(drifted.identity)])
  fallback.finish(drifted.identity)

  player.shouldFailToStart = true
  try output.speak(exact)
  #expect(player.requests.count == 1)
  #expect(fallback.commands == [drifted, exact])
  #expect(events.last == .didStart(exact.identity))
}

@MainActor
@Test("Recorded interruption is terminal and does not invoke fallback")
func releasedGuidanceAudioOutputDoesNotReplayAfterInterruption() throws {
  let productRelease = try guidanceAudioProductRelease()
  let fixture = guidanceAudioManifestFixture(productRelease)
  let release = try GuidanceAudioRelease(
    manifest: fixture.manifest,
    productRelease: productRelease,
    resourceProvider: { fixture.resources[$0] }
  )
  let record = try #require(release.assets.first?.record)
  let command = guidanceAudioCommand(
    record: record,
    routePlanID: release.manifest.routePlanID
  )
  let player = RecordingGuidanceAudioPlayer()
  let fallback = RecordingGuidanceAudioFallback()
  let output = ReleasedGuidanceAudioOutput(
    release: release,
    player: player,
    fallback: fallback
  )
  var events: [GuidanceSpeechOutputEvent] = []
  output.eventHandler = { events.append($0) }

  try output.speak(command)
  let playbackID = try #require(player.requests.first?.playbackID)
  player.interrupt(playbackID)

  #expect(fallback.commands.isEmpty)
  #expect(
    events
      == [
        .didStart(command.identity),
        .interruptionBegan,
        .interruptionEnded,
      ]
  )
}

private struct GuidanceAudioManifestFixture {
  let manifest: GuidanceAudioReleaseManifest
  let resources: [String: GuidanceAudioResource]
}

private func guidanceAudioProductRelease() throws -> KaidoProductRelease {
  let fixture = navigationReleaseBundleFixture()
  return try KaidoProductRelease(
    artifact: KaidoProductReleaseArtifact(
      releaseID: "test.product-release.guidance-audio",
      releasedAt: "2026-07-24T12:00:00+09:00",
      navigationRelease: navigationReleaseArtifact(fixture),
      routeAtlasRelease: productRouteAtlasArtifact(
        fixture,
        includeIncomingApproach: true
      )
    )
  )
}

private func guidanceAudioManifestFixture(
  _ productRelease: KaidoProductRelease
) -> GuidanceAudioManifestFixture {
  let waveData = guidanceTestWaveData(
    sampleRateHz: 24_000,
    frameCount: 2_400,
    sampleValue: 1_200
  )
  let audioHash = guidanceSHA256Hex(waveData)
  var records: [GuidanceAudioAssetRecord] = []
  var resources: [String: GuidanceAudioResource] = [:]
  var index = 0

  for definition in productRelease.navigation.bundle.releasedGuidance {
    for locale in KaidoReleaseLocale.allCases {
      let content =
        definition.frameTemplate.presentationSource.localizedContent[
          locale
        ]!
      let filename =
        "guidance-\(index)-\(locale.speechLanguageCode.lowercased()).wav"
      let key = GuidanceAudioAssetKey(
        promptID: definition.anchor.promptID,
        anchorID: definition.anchor.anchorID,
        anchorOccurrenceID: definition.anchor.occurrenceID,
        languageCode: locale.speechLanguageCode
      )
      records.append(
        GuidanceAudioAssetRecord(
          key: key,
          spokenText: content.spokenText,
          spokenTextSHA256: guidanceSHA256Hex(
            Data(content.spokenText.utf8)
          ),
          resourceFilename: filename,
          audioSHA256: audioHash,
          byteCount: waveData.count,
          sampleRateHz: 24_000,
          channelCount: 1,
          durationMilliseconds: 100,
          provenance: GuidanceAudioSynthesisProvenance(
            generationMode: .localOpenWeight,
            engineID: "test.engine",
            engineVersion: "1.0.0",
            modelID: "test/model",
            modelRevision: String(repeating: "a", count: 40),
            voiceID: "test.voice.\(locale.rawValue)",
            licenceIdentifier: "SYNTHETIC_TEST_ONLY",
            sourceURL: "https://example.com/test-guidance-audio",
            generatedAt: "2026-07-24T13:00:00+09:00",
            reviewedAt: "2026-07-24T14:00:00+09:00"
          )
        )
      )
      resources[filename] = GuidanceAudioResource(
        url: URL(fileURLWithPath: "/tmp/\(filename)"),
        data: waveData
      )
      index += 1
    }
  }

  return GuidanceAudioManifestFixture(
    manifest: GuidanceAudioReleaseManifest(
      releaseID: "test.guidance-audio-release.v1",
      releasedAt: "2026-07-24T15:00:00+09:00",
      productReleaseID: productRelease.releaseID,
      navigationReleaseID: productRelease.navigation.releaseID,
      networkSnapshotID:
        productRelease.navigation.bundle.networkSnapshot.id,
      routePlanID: productRelease.navigation.bundle.routePlan.id,
      assets: records
    ),
    resources: resources
  )
}

private func guidanceAudioCommand(
  record: GuidanceAudioAssetRecord,
  routePlanID: String
) -> GuidanceSpeechCommand {
  GuidanceSpeechCommand(
    identity: GuidanceSpeechIdentity(
      promptID: record.key.promptID,
      anchorID: record.key.anchorID,
      anchorOccurrenceID: record.key.anchorOccurrenceID
    ),
    routePlanID: routePlanID,
    languageCode: record.key.languageCode,
    spokenText: record.spokenText
  )
}

private func guidanceTestWaveData(
  sampleRateHz: Int,
  frameCount: Int,
  sampleValue: Int16
) -> Data {
  let channelCount = 1
  let bitsPerSample = 16
  let blockAlign = channelCount * bitsPerSample / 8
  let byteRate = sampleRateHz * blockAlign
  let audioByteCount = frameCount * blockAlign
  var result = Data()
  result.append(contentsOf: Array("RIFF".utf8))
  guidanceAppendUInt32(UInt32(36 + audioByteCount), to: &result)
  result.append(contentsOf: Array("WAVE".utf8))
  result.append(contentsOf: Array("fmt ".utf8))
  guidanceAppendUInt32(16, to: &result)
  guidanceAppendUInt16(1, to: &result)
  guidanceAppendUInt16(UInt16(channelCount), to: &result)
  guidanceAppendUInt32(UInt32(sampleRateHz), to: &result)
  guidanceAppendUInt32(UInt32(byteRate), to: &result)
  guidanceAppendUInt16(UInt16(blockAlign), to: &result)
  guidanceAppendUInt16(UInt16(bitsPerSample), to: &result)
  result.append(contentsOf: Array("data".utf8))
  guidanceAppendUInt32(UInt32(audioByteCount), to: &result)
  let sampleBits = UInt16(bitPattern: sampleValue)
  for _ in 0..<frameCount {
    guidanceAppendUInt16(sampleBits, to: &result)
  }
  return result
}

private func guidanceAppendUInt16(_ value: UInt16, to data: inout Data) {
  data.append(UInt8(value & 0xff))
  data.append(UInt8((value >> 8) & 0xff))
}

private func guidanceAppendUInt32(_ value: UInt32, to data: inout Data) {
  data.append(UInt8(value & 0xff))
  data.append(UInt8((value >> 8) & 0xff))
  data.append(UInt8((value >> 16) & 0xff))
  data.append(UInt8((value >> 24) & 0xff))
}

private func guidanceSHA256Hex(_ data: Data) -> String {
  SHA256.hash(data: data).map {
    String(format: "%02x", $0)
  }.joined()
}

@MainActor
private final class RecordingGuidanceAudioPlayer:
  GuidanceRecordedAudioPlaying
{
  struct Request {
    let asset: ReleasedGuidanceAudioAsset
    let playbackID: UUID
  }

  var eventHandler: ((GuidanceRecordedAudioPlaybackEvent) -> Void)?
  var shouldFailToStart = false
  private(set) var requests: [Request] = []

  func play(
    _ asset: ReleasedGuidanceAudioAsset,
    playbackID: UUID
  ) throws {
    requests.append(Request(asset: asset, playbackID: playbackID))
    if shouldFailToStart {
      throw GuidanceSpeechOutputError.recordedAudioPlaybackFailed
    }
    eventHandler?(.didStart(playbackID))
  }

  func stop() {}

  func finish(_ playbackID: UUID) {
    eventHandler?(.didFinish(playbackID))
  }

  func interrupt(_ playbackID: UUID) {
    eventHandler?(.interruptionBegan(playbackID))
    eventHandler?(.didCancel(playbackID))
    eventHandler?(.interruptionEnded(playbackID))
  }
}

@MainActor
private final class RecordingGuidanceAudioFallback: GuidanceSpeechOutput {
  var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?
  private(set) var commands: [GuidanceSpeechCommand] = []
  private var activeIdentity: GuidanceSpeechIdentity?

  func speak(_ command: GuidanceSpeechCommand) {
    commands.append(command)
    activeIdentity = command.identity
    eventHandler?(.didStart(command.identity))
  }

  func stop() {
    guard let activeIdentity else { return }
    self.activeIdentity = nil
    eventHandler?(.didCancel(activeIdentity))
  }

  func finish(_ identity: GuidanceSpeechIdentity) {
    activeIdentity = nil
    eventHandler?(.didFinish(identity))
  }
}
