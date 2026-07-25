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
  let exactWithRenderedSynthesis = GuidanceSpeechCommand(
    identity: exact.identity,
    routePlanID: exact.routePlanID,
    languageCode: exact.languageCode,
    spokenText: exact.spokenText,
    synthesisText: "reviewed device synthesis form"
  )
  #expect(
    release.asset(matching: exactWithRenderedSynthesis)?.record == record
  )

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

@Test("Bundle staging may map a reviewed logical WAV name to one physical file")
func guidanceAudioReleaseAcceptsExplicitLogicalFilenameMapping() throws {
  let productRelease = try guidanceAudioProductRelease()
  let fixture = guidanceAudioManifestFixture(productRelease)

  let release = try GuidanceAudioRelease(
    manifest: fixture.manifest,
    productRelease: productRelease,
    resourceProvider: { filename in
      guard let source = fixture.resources[filename] else {
        return nil
      }
      return GuidanceAudioResource(
        url: source.url.deletingLastPathComponent()
          .appendingPathComponent("calm--\(filename)"),
        data: source.data,
        logicalFilename: filename
      )
    }
  )

  #expect(release.assets.count == fixture.manifest.assets.count)
  #expect(
    release.assets.allSatisfy {
      $0.resourceURL.lastPathComponent.hasPrefix("calm--")
    }
  )
}

@Test("Unsafe guidance resource names never reach the resource provider")
func guidanceAudioReleaseRejectsUnsafeFilenameBeforeLookup() throws {
  let productRelease = try guidanceAudioProductRelease()
  let fixture = guidanceAudioManifestFixture(productRelease)
  let original = try #require(fixture.manifest.assets.first)
  let unsafe = GuidanceAudioAssetRecord(
    key: original.key,
    spokenText: original.spokenText,
    spokenTextSHA256: original.spokenTextSHA256,
    resourceFilename: "../escape.wav",
    audioSHA256: original.audioSHA256,
    byteCount: original.byteCount,
    sampleRateHz: original.sampleRateHz,
    channelCount: original.channelCount,
    durationMilliseconds: original.durationMilliseconds,
    provenance: original.provenance,
    review: original.review
  )
  var records = fixture.manifest.assets
  records[0] = unsafe
  let manifest = GuidanceAudioReleaseManifest(
    releaseID: fixture.manifest.releaseID,
    releasedAt: fixture.manifest.releasedAt,
    productReleaseID: fixture.manifest.productReleaseID,
    navigationReleaseID: fixture.manifest.navigationReleaseID,
    networkSnapshotID: fixture.manifest.networkSnapshotID,
    routePlanID: fixture.manifest.routePlanID,
    assets: records
  )
  var requestedUnsafeFilename = false

  do {
    _ = try GuidanceAudioRelease(
      manifest: manifest,
      productRelease: productRelease,
      resourceProvider: { filename in
        if filename == unsafe.resourceFilename {
          requestedUnsafeFilename = true
        }
        return fixture.resources[filename]
      }
    )
    Issue.record("Expected an unsafe audio filename to fail")
  } catch GuidanceAudioReleaseError.invalid(let issues) {
    #expect(issues == [.invalidAssetRecord(original.key)])
    #expect(!requestedUnsafeFilename)
  }
}

@Test("Audio provenance cannot postdate its reviewed release")
func guidanceAudioReleaseRejectsFutureProvenance() throws {
  let productRelease = try guidanceAudioProductRelease()
  let fixture = guidanceAudioManifestFixture(productRelease)
  let original = try #require(fixture.manifest.assets.first)
  let futureProvenance = GuidanceAudioSynthesisProvenance(
    evidenceScope: original.provenance.evidenceScope,
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
    provenance: futureProvenance,
    review: original.review
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
    #expect(issues.contains(.invalidReview(original.key)))
    #expect(issues.count == 2)
  }
}

@Test("Audio provenance scope must match the product runtime scope")
func guidanceAudioReleaseRejectsEvidenceScopeDrift() throws {
  let productRelease = try guidanceAudioProductRelease()
  let fixture = guidanceAudioManifestFixture(productRelease)
  let original = try #require(fixture.manifest.assets.first)
  let driftedProvenance = GuidanceAudioSynthesisProvenance(
    evidenceScope: .releasedAsset,
    generationMode: original.provenance.generationMode,
    engineID: original.provenance.engineID,
    engineVersion: original.provenance.engineVersion,
    modelID: original.provenance.modelID,
    modelRevision: original.provenance.modelRevision,
    voiceID: original.provenance.voiceID,
    licenceIdentifier: original.provenance.licenceIdentifier,
    sourceURL: original.provenance.sourceURL,
    generatedAt: original.provenance.generatedAt,
    reviewedAt: original.provenance.reviewedAt
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
    provenance: driftedProvenance,
    review: original.review
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
    Issue.record("Expected provenance scope drift to fail")
  } catch GuidanceAudioReleaseError.invalid(let issues) {
    #expect(issues == [.provenanceScopeMismatch(original.key)])
  }
}

@Test("Every released WAV carries an exact passed human review")
func guidanceAudioReleaseRejectsReviewDrift() throws {
  let productRelease = try guidanceAudioProductRelease()
  let fixture = guidanceAudioManifestFixture(productRelease)
  let original = try #require(fixture.manifest.assets.first)
  let rejected = GuidanceAudioAssetRecord(
    key: original.key,
    spokenText: original.spokenText,
    spokenTextSHA256: original.spokenTextSHA256,
    resourceFilename: original.resourceFilename,
    audioSHA256: original.audioSHA256,
    byteCount: original.byteCount,
    sampleRateHz: original.sampleRateHz,
    channelCount: original.channelCount,
    durationMilliseconds: original.durationMilliseconds,
    provenance: original.provenance,
    review: GuidanceAudioAssetReview(
      reviewerID: original.review.reviewerID,
      reviewedAt: original.review.reviewedAt,
      pronunciation: .rejected,
      intelligibility: .passed,
      audioQuality: .passed
    )
  )
  var records = fixture.manifest.assets
  records[0] = rejected
  let manifest = GuidanceAudioReleaseManifest(
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
      manifest: manifest,
      productRelease: productRelease,
      resourceProvider: { fixture.resources[$0] }
    )
    Issue.record("Expected rejected pronunciation review to fail")
  } catch GuidanceAudioReleaseError.invalid(let issues) {
    #expect(issues == [.invalidReview(original.key)])
  }
}

@Test("Recording worklist derives every released identity deterministically")
func guidanceAudioRecordingWorklistIsComplete() throws {
  let productRelease = try guidanceAudioProductRelease()
  let encoded = try GuidanceAudioRecordingWorklistCodec.encode(
    productRelease: productRelease
  )
  let repeated = try GuidanceAudioRecordingWorklistCodec.encode(
    productRelease: productRelease
  )
  let worklist = try GuidanceAudioRecordingWorklistCodec.decode(
    encoded,
    productRelease: productRelease
  )

  #expect(encoded == repeated)
  #expect(
    worklist.items.count
      == productRelease.navigation.bundle.releasedGuidance.count
      * KaidoReleaseLocale.allCases.count
  )
  #expect(
    Set(worklist.items.map(\.key)).count == worklist.items.count
  )
  #expect(
    Set(worklist.items.map(\.suggestedResourceFilename)).count
      == worklist.items.count
  )
  #expect(
    worklist.items.allSatisfy {
      $0.suggestedResourceFilename.hasPrefix("guidance-")
        && $0.suggestedResourceFilename.hasSuffix(".wav")
    }
  )

  let drifted = GuidanceAudioRecordingWorklist(
    productReleaseID: worklist.productReleaseID,
    navigationReleaseID: worklist.navigationReleaseID,
    networkSnapshotID: worklist.networkSnapshotID,
    routePlanID: worklist.routePlanID,
    items: Array(worklist.items.dropLast())
  )
  let driftedData = try JSONEncoder().encode(drifted)
  var rejectedDrift = false
  do {
    _ = try GuidanceAudioRecordingWorklistCodec.decode(
      driftedData,
      productRelease: productRelease
    )
    Issue.record("Expected worklist drift to fail")
  } catch GuidanceAudioAuthoringError.worklistDrift {
    rejectedDrift = true
  }
  #expect(rejectedDrift)
}

@Test("Audio review preparation is deterministic, exact, and pending")
func guidanceAudioReviewPreparationIsPending() throws {
  let productRelease = try guidanceAudioProductRelease()
  let resources = try guidanceAudioAuthoringResources(productRelease)
  let worklist = try GuidanceAudioRecordingWorklistCodec.derive(
    productRelease: productRelease
  )
  let checklist = try GuidanceAudioReviewChecklistCodec.prepare(
    reviewID: "test.guidance-audio-review.v1",
    productRelease: productRelease,
    resourceProvider: { resources[$0] }
  )
  let encoded = try GuidanceAudioReviewChecklistCodec.encode(
    checklist
  )
  let repeated = try GuidanceAudioReviewChecklistCodec.encode(
    checklist
  )
  let decoded = try GuidanceAudioReviewChecklistCodec.decode(
    encoded
  )

  #expect(encoded == repeated)
  #expect(decoded == checklist)
  #expect(checklist.records.count == worklist.items.count)
  #expect(
    checklist.records.map(\.resourceFilename)
      == worklist.items.map(\.suggestedResourceFilename)
  )
  #expect(
    checklist.records.allSatisfy {
      $0.review == .pending
        && $0.audioSHA256
          == guidanceSHA256Hex(
            resources[$0.resourceFilename]!.data
          )
    }
  )
}

@Test("Authoring rejects pending or hash-drifted human review")
func guidanceAudioAuthoringRequiresExactPassedReview() throws {
  let productRelease = try guidanceAudioProductRelease()
  let fixture = guidanceAudioManifestFixture(productRelease)
  let configuration = try guidanceAudioAuthoringConfiguration(
    fixture
  )
  let resources = try guidanceAudioAuthoringResources(productRelease)
  let pending = try GuidanceAudioReviewChecklistCodec.prepare(
    reviewID: "test.guidance-audio-review.v1",
    productRelease: productRelease,
    resourceProvider: { resources[$0] }
  )
  let firstKey = try #require(pending.records.first?.key)

  do {
    _ = try GuidanceAudioReleaseAuthor.buildManifest(
      productRelease: productRelease,
      configuration: configuration,
      reviewChecklist: pending,
      resourceProvider: { resources[$0] }
    )
    Issue.record("Expected pending human review to fail")
  } catch GuidanceAudioAuthoringError.invalidReview(let issues) {
    #expect(issues.contains(.invalidReviewer(firstKey)))
    #expect(issues.contains(.reviewIncomplete(firstKey)))
    #expect(issues.contains(.reviewChronologyInvalid(firstKey)))
  }

  let passed = passingGuidanceAudioReviewChecklist(pending)
  let firstRecord = try #require(passed.records.first)
  var driftedRecords = passed.records
  driftedRecords[0] = GuidanceAudioReviewChecklistRecord(
    key: firstRecord.key,
    spokenTextSHA256: firstRecord.spokenTextSHA256,
    resourceFilename: firstRecord.resourceFilename,
    audioSHA256: String(repeating: "0", count: 64),
    review: firstRecord.review
  )
  let drifted = GuidanceAudioReviewChecklist(
    schemaVersion: passed.schemaVersion,
    reviewID: passed.reviewID,
    productReleaseID: passed.productReleaseID,
    navigationReleaseID: passed.navigationReleaseID,
    networkSnapshotID: passed.networkSnapshotID,
    routePlanID: passed.routePlanID,
    records: driftedRecords
  )

  do {
    _ = try GuidanceAudioReleaseAuthor.buildManifest(
      productRelease: productRelease,
      configuration: configuration,
      reviewChecklist: drifted,
      resourceProvider: { resources[$0] }
    )
    Issue.record("Expected review audio hash drift to fail")
  } catch GuidanceAudioAuthoringError.invalidReview(let issues) {
    #expect(issues == [.recordBindingMismatch(firstRecord.key)])
  }
}

@Test("Authoring configuration builds a complete validated audio manifest")
func guidanceAudioAuthoringBuildsManifest() throws {
  let productRelease = try guidanceAudioProductRelease()
  let fixture = guidanceAudioManifestFixture(productRelease)
  let configuration = try guidanceAudioAuthoringConfiguration(
    fixture
  )
  let worklist = try GuidanceAudioRecordingWorklistCodec.derive(
    productRelease: productRelease
  )
  let resources = try guidanceAudioAuthoringResources(
    productRelease
  )
  let pendingReview = try GuidanceAudioReviewChecklistCodec.prepare(
    reviewID: "test.guidance-audio-review.v1",
    productRelease: productRelease,
    resourceProvider: { resources[$0] }
  )
  let review = passingGuidanceAudioReviewChecklist(
    pendingReview
  )

  let manifest = try GuidanceAudioReleaseAuthor.buildManifest(
    productRelease: productRelease,
    configuration: configuration,
    reviewChecklist: review,
    resourceProvider: { resources[$0] }
  )
  let repeated = try GuidanceAudioReleaseAuthor.buildManifest(
    productRelease: productRelease,
    configuration: configuration,
    reviewChecklist: review,
    resourceProvider: { resources[$0] }
  )
  let encoded = try GuidanceAudioReleaseManifestCodec.encode(
    manifest,
    productRelease: productRelease,
    resourceProvider: { resources[$0] }
  )
  let release = try GuidanceAudioReleaseManifestCodec.decode(
    encoded,
    productRelease: productRelease,
    resourceProvider: { resources[$0] }
  )

  #expect(manifest == repeated)
  #expect(manifest.assets.count == worklist.items.count)
  #expect(
    manifest.assets.map(\.resourceFilename)
      == worklist.items.map(\.suggestedResourceFilename)
  )
  #expect(release.assets.count == worklist.items.count)
  #expect(
    Set(manifest.assets.map(\.provenance.voiceID))
      == Set(configuration.languageProfiles.map(\.provenance.voiceID))
  )
}

@Test("Authoring fails before output when profiles or WAV files are missing")
func guidanceAudioAuthoringRequiresProfilesAndResources() throws {
  let productRelease = try guidanceAudioProductRelease()
  let fixture = guidanceAudioManifestFixture(productRelease)
  let complete = try guidanceAudioAuthoringConfiguration(fixture)
  let resources = try guidanceAudioAuthoringResources(productRelease)
  let pendingReview = try GuidanceAudioReviewChecklistCodec.prepare(
    reviewID: "test.guidance-audio-review.v1",
    productRelease: productRelease,
    resourceProvider: { resources[$0] }
  )
  let review = passingGuidanceAudioReviewChecklist(
    pendingReview
  )
  let missingProfile = GuidanceAudioAuthoringConfiguration(
    releaseID: complete.releaseID,
    releasedAt: complete.releasedAt,
    languageProfiles: Array(complete.languageProfiles.dropLast())
  )
  let missingLanguage = try #require(
    Set(KaidoReleaseLocale.allCases.map(\.speechLanguageCode))
      .subtracting(
        missingProfile.languageProfiles.map(\.languageCode)
      )
      .first
  )

  do {
    _ = try GuidanceAudioReleaseAuthor.buildManifest(
      productRelease: productRelease,
      configuration: missingProfile,
      reviewChecklist: review,
      resourceProvider: { _ in nil }
    )
    Issue.record("Expected a missing language profile to fail")
  } catch GuidanceAudioAuthoringError.invalidConfiguration(let issues) {
    #expect(issues == [.missingLanguageProfile(missingLanguage)])
  }

  let firstFilename = try #require(
    GuidanceAudioRecordingWorklistCodec.derive(
      productRelease: productRelease
    ).items.first?.suggestedResourceFilename
  )
  do {
    _ = try GuidanceAudioReleaseAuthor.buildManifest(
      productRelease: productRelease,
      configuration: complete,
      reviewChecklist: review,
      resourceProvider: { _ in nil }
    )
    Issue.record("Expected a missing WAV resource to fail")
  } catch GuidanceAudioAuthoringError.resourceMissing(let filename) {
    #expect(filename == firstFilename)
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

struct GuidanceAudioManifestFixture {
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

func guidanceAudioManifestFixture(
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
            evidenceScope: .syntheticTestOnly,
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
          ),
          review: GuidanceAudioAssetReview(
            reviewerID: "test.reviewer.\(locale.rawValue)",
            reviewedAt: "2026-07-24T13:30:00+09:00",
            pronunciation: .passed,
            intelligibility: .passed,
            audioQuality: .passed
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

private func guidanceAudioAuthoringConfiguration(
  _ fixture: GuidanceAudioManifestFixture
) throws -> GuidanceAudioAuthoringConfiguration {
  var profiles: [GuidanceAudioLanguageProfile] = []
  for locale in KaidoReleaseLocale.allCases {
    let record = try #require(
      fixture.manifest.assets.first {
        $0.key.languageCode == locale.speechLanguageCode
      }
    )
    profiles.append(
      GuidanceAudioLanguageProfile(
        languageCode: locale.speechLanguageCode,
        provenance: record.provenance
      )
    )
  }
  return GuidanceAudioAuthoringConfiguration(
    releaseID: "test.guidance-audio-authored.v1",
    releasedAt: "2026-07-24T15:00:00+09:00",
    languageProfiles: profiles
  )
}

private func guidanceAudioAuthoringResources(
  _ productRelease: KaidoProductRelease
) throws -> [String: GuidanceAudioResource] {
  let worklist = try GuidanceAudioRecordingWorklistCodec.derive(
    productRelease: productRelease
  )
  let waveData = guidanceTestWaveData(
    sampleRateHz: 24_000,
    frameCount: 4_800,
    sampleValue: 1_600
  )
  return Dictionary(
    uniqueKeysWithValues: worklist.items.map {
      (
        $0.suggestedResourceFilename,
        GuidanceAudioResource(
          url: URL(
            fileURLWithPath:
              "/tmp/\($0.suggestedResourceFilename)"
          ),
          data: waveData
        )
      )
    }
  )
}

private func passingGuidanceAudioReviewChecklist(
  _ checklist: GuidanceAudioReviewChecklist
) -> GuidanceAudioReviewChecklist {
  GuidanceAudioReviewChecklist(
    schemaVersion: checklist.schemaVersion,
    reviewID: checklist.reviewID,
    productReleaseID: checklist.productReleaseID,
    navigationReleaseID: checklist.navigationReleaseID,
    networkSnapshotID: checklist.networkSnapshotID,
    routePlanID: checklist.routePlanID,
    records: checklist.records.map {
      GuidanceAudioReviewChecklistRecord(
        key: $0.key,
        spokenTextSHA256: $0.spokenTextSHA256,
        resourceFilename: $0.resourceFilename,
        audioSHA256: $0.audioSHA256,
        review: GuidanceAudioAssetReview(
          reviewerID: "test.guidance-audio-reviewer",
          reviewedAt: "2026-07-24T13:30:00+09:00",
          pronunciation: .passed,
          intelligibility: .passed,
          audioQuality: .passed
        )
      )
    }
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

func guidanceTestWaveData(
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

func guidanceSHA256Hex(_ data: Data) -> String {
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
