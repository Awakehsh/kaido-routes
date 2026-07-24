import CoreLocation
import KaidoAppleAdapters
import KaidoDomain
import KaidoNavigation
import KaidoPresentation
import XCTest

@testable import KaidoRoutesApp

final class ProductNavigationRuntimeModelTests: XCTestCase {
  @MainActor
  func testReleasedEntryCreatesOnlyReleaseBoundRuntimeAuthority()
    async throws
  {
    let entry = try makeReleasedProductTestEntry()
    let model = try ProductNavigationRuntimeModel(
      releasedEntry: entry,
      sourceEvidenceProvider: FixedRuntimeSourceEvidenceProvider(),
      speechOutput: SilentGuidanceSpeechOutput(),
      languageSelectionProvider: {
        NavigationLanguageSelection(
          interfaceLocale: .simplifiedChinese,
          guidanceVoiceLocale: .japanese
        )
      }
    )

    XCTAssertTrue(model.isRealRoadAuthority)
    XCTAssertEqual(model.productReleaseID, entry.release.releaseID)
    XCTAssertEqual(
      model.foregroundNavigationRuntimeIdentity,
      entry.release.runtimeIdentity
    )
    guard
      case .releasedProduct(let authority) =
        model.foregroundNavigationLocationAuthority
    else {
      return XCTFail("Expected codec-minted released-road authority")
    }
    XCTAssertEqual(authority.runtimeIdentity, entry.release.runtimeIdentity)
    XCTAssertFalse(model.canRunDeterministicPreviewTrace)

    await model.activate()

    XCTAssertEqual(model.activation, .ready)
    XCTAssertEqual(model.snapshot?.journeyPhase, .planning)
    XCTAssertEqual(
      model.snapshot?.activeRoutePlanID,
      entry.release.navigation.bundle.routePlan.id
    )
  }

  @MainActor
  func testDemoEntryCannotConstructReleasedProductRuntime() throws {
    let catalog = try BundledProductReleaseCatalogLoader.bundledPreview()
    let entry = try XCTUnwrap(catalog.demoEntries.first)

    XCTAssertThrowsError(
      try ProductNavigationRuntimeModel(
        releasedEntry: entry,
        languageSelectionProvider: {
          NavigationLanguageSelection(
            interfaceLocale: .simplifiedChinese,
            guidanceVoiceLocale: .japanese
          )
        }
      )
    ) {
      XCTAssertEqual(
        $0 as? ProductNavigationRuntimeModelError,
        .invalidReleasedEntryRole
      )
    }
  }

  @MainActor
  func testTerminationStopsRuntimeAndRemovesCheckpoint() async throws {
    let store = RuntimeCheckpointStore()
    let entry = try makeReleasedProductTestEntry()
    let model = try ProductNavigationRuntimeModel(
      releasedEntry: entry,
      sourceEvidenceProvider: FixedRuntimeSourceEvidenceProvider(),
      speechOutput: SilentGuidanceSpeechOutput(),
      languageSelectionProvider: {
        NavigationLanguageSelection(
          interfaceLocale: .simplifiedChinese,
          guidanceVoiceLocale: .japanese
        )
      },
      checkpointStore: store
    )
    await model.activate()
    await model.handleScenePhase(
      .inactive,
      atMilliseconds: 1_000_000
    )
    XCTAssertNotNil(store.checkpoint)

    let terminated = await model.terminate()

    XCTAssertTrue(terminated)
    XCTAssertEqual(model.activation, .ended)
    XCTAssertNil(model.snapshot)
    XCTAssertNil(store.checkpoint)
    XCTAssertEqual(store.removeCount, 1)
    XCTAssertFalse(model.canConsumeForegroundNavigationLocations)
  }
}

private struct FixedRuntimeSourceEvidenceProvider:
  CoreLocationSourceEvidenceProviding
{
  func evidence(for _: CLLocation) -> CoreLocationSourceEvidence {
    CoreLocationSourceEvidence(
      deliverySource: .deviceOrUndisclosed,
      sourceInformationAvailable: true,
      isSimulatedBySoftware: false
    )
  }
}

@MainActor
private final class SilentGuidanceSpeechOutput: GuidanceSpeechOutput {
  var eventHandler: ((GuidanceSpeechOutputEvent) -> Void)?
  var selectedVoiceProfile: GuidanceSpeechVoiceProfile?

  func speak(_ command: GuidanceSpeechCommand) throws {
    eventHandler?(.didStart(command.identity))
  }

  func stop() {}
}

@MainActor
private final class RuntimeCheckpointStore:
  NavigationSessionCheckpointStoring
{
  var checkpoint: NavigationSessionCheckpoint?
  private(set) var removeCount = 0

  func load() throws -> NavigationSessionCheckpoint? {
    checkpoint
  }

  func save(_ checkpoint: NavigationSessionCheckpoint) throws {
    self.checkpoint = checkpoint
  }

  func remove() throws {
    checkpoint = nil
    removeCount += 1
  }
}
