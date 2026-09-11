import CoreLocation
import KaidoAppleAdapters
import KaidoDomain
import KaidoPresentation
import KaidoRouting
import MapKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum WholeShutoPlanningField: Hashable {
  case origin
  case destination
}

enum WholeShutoIdleTimerPolicy {
  static func disablesIdleTimer(
    isLiveDrive: Bool,
    phase: WholeShutoJourneyPhase
  ) -> Bool {
    isLiveDrive && phase != .completed
  }
}

struct WholeShutoProductView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @AppStorage(KaidoMapAppearance.preferenceKey) private var mapAppearance: KaidoMapAppearance = .automatic
  @ScaledMetric(relativeTo: .body) private var routeSelectionCardHeight: CGFloat = 160
  @StateObject private var model: WholeShutoProductModel
  @StateObject private var languageSettings: KaidoLanguageSettingsModel
  @StateObject private var planningLocation: WholeShutoPlanningLocationController
  @StateObject private var placeSearch: WholeShutoPlaceSearchController
  @StateObject private var savedRoutes: SavedRouteLibraryModel
  private let wholeShutoAttribution: WholeShutoAttribution
  @State private var showsSettings = false
  @State private var showsRouteCustomization = false
  @State private var showsJourneyReview = false
  @State private var showsJourneyEnding = false
  @State private var showsSavedRoutes = false
  @State private var showsDriveHistory = false
  @State private var isImportingSavedRoute = false
  @State private var showsManualOrigin = false
  @State private var waitsForPlanningLocation = false
  @State private var waitsForCircuitLocation = false
  @State private var showsCircuitAlternatives = false
  @State private var showsDestinationComposer = false
  @State private var showsEndJourneyConfirmation = false
  @State private var resumesAfterEndJourneyCancellation = false
  @State private var isPreparingEndJourneyConfirmation = false
  @State private var isPlanningDockExpanded = true
  @GestureState private var planningDockDragOffset: CGFloat = 0
  @State private var waitsForCustomRouteLocation = false
  @State private var pendingSavedRouteRecordID: String?
  @State private var savedRouteOpenErrorCode: String?
  @State private var savedRouteImportErrorCode: String?
  @State private var geographicCamera = WholeShutoGeographicMap.defaultCamera
  @State private var geographicFollowsRoute = true
  @State private var lastStableGeographicHeadingDegrees: Double?
  @State private var trackMapZoom = 1.0
  @State private var trackMapPan = CGSize.zero
  @State private var trackMapUserAdjustedViewport = false
  @FocusState private var focusedPlanningField: WholeShutoPlanningField?
  @State private var planningSearchField: WholeShutoPlanningField?

  init(
    model: WholeShutoProductModel? = nil,
    languageSettings: KaidoLanguageSettingsModel? = nil,
    planningLocation: WholeShutoPlanningLocationController? = nil,
    placeSearch: WholeShutoPlaceSearchController? = nil,
    savedRoutes: SavedRouteLibraryModel? = nil
  ) {
    let resolvedModel =
      model ?? WholeShutoForegroundReleaseFactory.makeModel()
    _model = StateObject(
      wrappedValue: resolvedModel
    )
    _languageSettings = StateObject(
      wrappedValue: languageSettings ?? KaidoLanguageSettingsModel()
    )
    _planningLocation = StateObject(
      wrappedValue:
        planningLocation ?? WholeShutoPlanningLocationController()
    )
    _placeSearch = StateObject(
      wrappedValue:
        placeSearch
        ?? WholeShutoPlaceSearchController(
          localPlaces: Self.localSearchPlaces(in: resolvedModel.database)
        )
    )
    _savedRoutes = StateObject(
      wrappedValue:
        savedRoutes
        ?? SavedRouteLibraryModel(
          store: try? FileSavedRouteLibraryStore.applicationSupport(),
          foregroundEntries: [],
          availabilityResolver: { [weak resolvedModel] record in
            resolvedModel?.savedRouteAvailability(record) ?? .unavailable
          }
        )
    )
    do {
      wholeShutoAttribution = try WholeShutoAttribution(
        database: resolvedModel.database
      )
    } catch {
      preconditionFailure(
        "Invalid whole-Shuto attribution catalog: \(error)"
      )
    }
  }

  var body: some View {
    Group {
      if isLandscape {
        landscapeLayout
      } else {
        portraitLayout
      }
    }
    .animation(.easeOut(duration: 0.22), value: model.phase)
    .animation(
      .easeOut(duration: 0.22),
      value: model.activeJunctionPrompt
    )
    .preferredColorScheme(mapAppearance.colorScheme)
    .sheet(isPresented: $showsRouteCustomization) {
      WholeShutoCustomRouteSheet(model: model)
        .environment(\.colorScheme, .dark)
    }
    .sheet(isPresented: $showsJourneyEnding) {
      WholeShutoJourneyEndingView(model: model, placeSearch: placeSearch)
        .environment(\.kaidoInterfaceLocale, languageSettings.interfaceLocale)
        .environment(\.colorScheme, .dark)
    }
    .sheet(isPresented: $showsJourneyReview) {
      WholeShutoJourneyReviewView(
        model: model,
        languageSettings: languageSettings,
        savedRoutes: savedRoutes,
        placeSearch: placeSearch,
        onStartLiveDrive: beginLiveDrive
      )
      .environment(\.colorScheme, .dark)
    }
    .sheet(isPresented: $showsSavedRoutes) {
      savedRouteLibrarySheet
        .environment(\.colorScheme, .dark)
    }
    .sheet(isPresented: $showsDriveHistory) {
      NavigationStack {
        DriveHistoryView(model: model, savedRoutes: savedRoutes, locale: languageSettings.interfaceLocale)
          .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
              Button(copy.resolve(japanese: "完了", simplifiedChinese: "完成", english: "Done")) { showsDriveHistory = false }
            }
          }
      }
    }
    .fileImporter(
      isPresented: $isImportingSavedRoute,
      allowedContentTypes: [.kaidoRoute, .json],
      allowsMultipleSelection: false
    ) { result in
      savedRouteImportErrorCode = importSavedRouteFile(
        result,
        into: savedRoutes
      )
    }
    .sheet(isPresented: $showsSettings) {
      WholeShutoSettingsView(
        languageSettings: languageSettings,
        model: model,
        savedRoutes: savedRoutes,
        checkedAt: model.database.checkedAt,
        attribution: wholeShutoAttribution
      )
      .presentationDragIndicator(.visible)
      .environment(
        \.kaidoInterfaceLocale,
        languageSettings.interfaceLocale
      )
    }
    .alert(
      endJourneyConfirmationTitle,
      isPresented: $showsEndJourneyConfirmation
    ) {
      Button(
        continueJourneyActionLabel,
        role: .cancel
      ) {
        resumeAfterEndJourneyCancellation()
      }
      Button(
        endJourneyActionLabel,
        role: .destructive
      ) {
        resumesAfterEndJourneyCancellation = false
        model.reset()
      }
    } message: {
      Text(endJourneyConfirmationMessage)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("whole-shuto-product")
    .accessibilityValue(model.phase.rawValue)
    .environment(
      \.kaidoInterfaceLocale,
      languageSettings.interfaceLocale
    )
    .onChange(of: scenePhase, initial: true) { _, newPhase in
      planningLocation.setForeground(newPhase == .active && !isDriving)
      Task {
        await model.handleScenePhase(newPhase.productRuntimePhase)
      }
    }
    .onChange(of: isDriving) { _, newValue in
      planningLocation.setForeground(scenePhase == .active && !newValue)
      updateIdleTimer()
    }
    .onChange(of: model.isLiveDrive, initial: true) {
      updateIdleTimer()
    }
    .onChange(of: model.phase) {
      updateIdleTimer()
      if model.phase == .review, model.isCircuitRouteSelected {
        showsJourneyReview = true
      }
    }
    .onDisappear {
      if ActiveDriveControl.model === model { ActiveDriveControl.model = nil }
      UIApplication.shared.isIdleTimerDisabled = false
    }
    .onAppear { ActiveDriveControl.model = model }
    .onOpenURL { url in
      guard url.isFileURL else { return }
      savedRouteImportErrorCode = importSavedRouteFile(.success([url]), into: savedRoutes)
        ?? savedRoutes.lastErrorCode
      showsSavedRoutes = true
    }
    .onChange(of: model.destinationQuery, initial: true) {
      updatePlanningPlaceSearch()
    }
    .onChange(of: model.originQuery, initial: true) {
      updatePlanningPlaceSearch()
    }
    .onChange(of: focusedPlanningField) { _, newField in
      if let newField {
        planningSearchField = newField
        updatePlanningPlaceSearch()
      }
    }
    .onChange(of: planningLocation.snapshot?.coordinate.latitude) {
      handlePlanningLocationUpdate()
    }
    .onChange(of: planningLocation.snapshot?.coordinate.longitude) {
      handlePlanningLocationUpdate()
    }
    .onChange(of: planningLocation.state) {
      handlePlanningLocationUpdate()
    }
  }

  private func updateIdleTimer() {
    UIApplication.shared.isIdleTimerDisabled =
      WholeShutoIdleTimerPolicy.disablesIdleTimer(
        isLiveDrive: model.isLiveDrive,
        phase: model.phase
      )
  }

  private var isLandscape: Bool {
    verticalSizeClass == .compact
  }

  static func localSearchPlaces(
    in database: ShutoNetworkDatabase
  ) -> [(WholeShutoPlaceSuggestion, WholeShutoPlace)] {
    database.directionalFacilities.map { facility in
      var accessRoles: [String] = []
      if facility.canEnter {
        accessRoles.append(
          "入口 \(facility.entranceDirections.joined(separator: " / "))"
        )
      }
      if facility.canExit {
        accessRoles.append(
          "出口 \(facility.exitDirections.joined(separator: " / "))"
        )
      }
      let accessText = accessRoles.isEmpty
        ? ""
        : " · \(accessRoles.joined(separator: " · "))"
      let title = "\(facility.nameJA) IC"
      return (
        WholeShutoPlaceSuggestion(
          id: "shuto-facility:\(facility.facilityID)",
          title: title,
          subtitle: "\(shieldLabel(facility.routeID))\(accessText)",
          isShutoFacility: true
        ),
        WholeShutoPlace(title: title, coordinate: facility.coordinate)
      )
    } + database.parkingAreas.map { parking in
      (
        WholeShutoPlaceSuggestion(id: "shuto-pa:\(parking.parkingAreaID)", title: parking.nameJA, subtitle: "PA · \(parking.directionJA ?? "")", isShutoFacility: true),
        WholeShutoPlace(title: parking.nameJA, coordinate: parking.coordinate, parkingAreaID: parking.parkingAreaID)
      )
    }
  }

  /// Starts the live drive and location session together from the foreground.
  /// The session only opens after the reviewed journey is admitted, so the
  /// app never holds the sensor while merely browsing routes.
  private func beginLiveDrive() {
    Task {
      guard await model.startLiveJourney() else { return }
      showsJourneyReview = false
    }
  }

  private var portraitLayout: some View {
    GeometryReader { geometry in
      ZStack {
        map
          .ignoresSafeArea()

        if usesExpandedTextLayout && !isDriving
          && model.phase != .completed
        {
          ScrollView {
            VStack(spacing: 0) {
              topBar
              dockContent
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
          }
          .scrollIndicators(.hidden)
          .scrollDismissesKeyboard(.interactively)
        } else {
          VStack(spacing: 0) {
            topBar
            if showsDestinationComposer && !isDriving
              && model.phase != .completed
            {
              ScrollView {
                dockContent
                  .padding(.top, 8)
                  .padding(.bottom, 12)
              }
              .scrollIndicators(.hidden)
              .scrollDismissesKeyboard(.interactively)
            } else {
              Spacer(minLength: 0)
              if !isDriving, model.phase != .completed {
                if isPlanningDockExpanded {
                  ScrollView {
                    dockContent
                  }
                  .scrollIndicators(.hidden)
                  .frame(maxHeight: geometry.size.height / 2)
                } else {
                  dockContent
                }
              } else {
                dockContent
              }
            }
          }
        }

        if let prompt = model.activeJunctionInsetPrompt {
          VStack {
            Spacer()
            WholeShutoJunctionInset(
              prompt: prompt,
              distanceText:
                model.distanceToNextReviewedJunctionMeters.map(distanceLabel)
            )
              .padding(.horizontal, 14)
              .padding(.bottom, 142)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
          .allowsHitTesting(false)
        }

        #if DEBUG
          planningLocationQualificationState
        #endif
      }
    }
  }

  /// Landscape: a fixed instrument column carries the title, guidance
  /// banner, and dock; the map owns the remaining width at full height.
  private var landscapeLayout: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        topBar
        if isDriving || model.phase == .completed {
          Spacer(minLength: 8)
          dockContent
        } else {
          ScrollView {
            dockContent
              .padding(.top, 8)
          }
          .scrollIndicators(.hidden)
        }
      }
      .frame(width: 384)
      .background(KaidoTheme.night)

      ZStack {
        map
          .ignoresSafeArea(edges: [.top, .bottom, .trailing])

        if let prompt = model.activeJunctionInsetPrompt {
          VStack {
            Spacer()
            WholeShutoJunctionInset(
              prompt: prompt,
              distanceText:
                model.distanceToNextReviewedJunctionMeters.map(distanceLabel)
            )
              .padding(.horizontal, 14)
              .padding(.bottom, 16)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
          .allowsHitTesting(false)
        }
      }
    }
    .background(KaidoTheme.night)
  }

  private var dockContent: some View {
    VStack(spacing: 0) {
      if let checkpointIssueCode = model.checkpointIssueCode {
        checkpointIssueBanner(checkpointIssueCode)
      }
      if model.driveHistoryIssue != nil {
        Text(copy.resolve(japanese: "今回の走行記録を保存できませんでした。", simplifiedChinese: "未能保存本次行程记录。", english: "This drive record could not be saved."))
          .font(.subheadline)
          .foregroundStyle(KaidoTheme.signalAmber)
          .padding(12)
      }

      if model.phase == .completed {
        arrivalDock
      } else if isDriving {
        if model.isLiveDrive,
          model.liveLocationState == .resumeRequired
            || model.liveLocationState == .resting
            || model.liveLocationState == .failed
        {
          liveResumeBanner
        }
        drivingDock
      } else {
        planningDock
      }
    }
    .environment(\.colorScheme, .dark)
  }

  private var liveResumeBanner: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(
        model.liveLocationState == .resting
          ? copy.resolve(
            japanese: "休憩中",
            simplifiedChinese: "休息中",
            english: "RESTING"
          )
          : copy.resolve(
            japanese: "位置情報は一時停止中です",
            simplifiedChinese: "实时定位已暂停",
            english: "LIVE LOCATION IS PAUSED"
          )
      )
      .font(.caption.weight(.black))
      .foregroundStyle(KaidoTheme.signalAmber)

      Button {
        Task { _ = await model.resumeLiveJourney() }
      } label: {
        Text(
          copy.resolve(
            japanese: "ナビを再開",
            simplifiedChinese: "恢复导航",
            english: "RESUME NAVIGATION"
          )
        )
        .font(.body.weight(.black))
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .foregroundStyle(KaidoTheme.night)
        .background(KaidoTheme.signalAmber)
        .clipShape(RoundedRectangle(cornerRadius: 10))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("whole-shuto-resume-live-drive")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(KaidoTheme.nightPanel)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("whole-shuto-live-resume-required")
  }

  private func checkpointIssueBanner(_ code: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "externaldrive.badge.exclamationmark")
        .accessibilityHidden(true)
      Text(checkpointIssueMessage(code))
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(KaidoTheme.evidenceCoral)
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(KaidoTheme.nightPanel)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("whole-shuto-checkpoint-issue")
    .accessibilityValue(code)
  }

  @ViewBuilder
  private var map: some View {
    if model.mapMode == .network {
      if let layout = model.trackMapLayout,
        let route = model.selectedRoute
      {
        WholeShutoTrackMapView(
          layout: layout,
          spans: model.trackMapSpans,
          entryFacilityID: route.routePlan.entryFacilityID,
          currentCoordinate: isDriving ? model.currentCoordinate : nil,
          routeProgressFraction:
            model.phase == .expressway ? model.progressFraction : nil,
          isPositionEstimated: isTrackMapPositionEstimated,
          visibleBottomFraction: mapVisibleBottomFraction,
          routeDistanceMeters: route.distanceMeters,
          labelTopInsetOverride: isLandscape ? 12 : nil,
          zoom: $trackMapZoom,
          pan: $trackMapPan,
          userAdjustedViewport: $trackMapUserAdjustedViewport
        )
      } else if let overview = WholeShutoNetworkOverviewCatalog.layout(
        for: model.database
      ) {
        WholeShutoNetworkOverviewView(
          layout: overview,
          visibleBottomFraction: mapVisibleBottomFraction,
          initialZoom: networkOverviewInitialZoom,
          overlay: planningOverlay(for: overview),
          labelTopInset: isLandscape ? 12 : 96
        )
      } else {
        WholeShutoNetworkDiagram(
          database: model.database,
          selectedRoute: model.selectedRoute,
          currentCoordinate: isDriving ? model.currentCoordinate : nil,
          usesDarkStyle: true,
          visibleBottomFraction: mapVisibleBottomFraction
        )
      }
    } else {
      WholeShutoGeographicMap(
        model: model,
        planningLocation: planningLocation.snapshot,
        camera: $geographicCamera,
        followsRoute: $geographicFollowsRoute,
        lastStableHeadingDegrees: $lastStableGeographicHeadingDegrees
      )
    }
  }

  private func planningOverlay(
    for layout: NetworkOverviewLayout
  ) -> WholeShutoNetworkOverviewView.PlanningOverlay {
    guard model.phase == .planning else { return .init() }
    var overlay = WholeShutoNetworkOverviewView.PlanningOverlay()
    if let circuit = model.selectedCircuit {
      overlay.highlightedRouteIDs = circuit.memberRouteIDs
    } else if let route = model.selectedRoute {
      overlay.highlightedRouteIDs = Set(route.routeIDsInOrder)
    }
    if let snapshot = planningLocation.snapshot {
      overlay.currentPosition = layout.projection.project(
        .init(
          latitude: snapshot.coordinate.latitude,
          longitude: snapshot.coordinate.longitude
        )
      )
    }
    if let entry = model.circuitEntryFacility {
      overlay.entranceMark = .init(
        point: layout.projection.project(
          .init(
            latitude: entry.coordinate.latitude,
            longitude: entry.coordinate.longitude
          )
        ),
        nameJA: entry.nameJA
      )
    }
    if let exit = model.circuitExitFacility {
      overlay.exitMark = .init(
        point: layout.projection.project(
          .init(
            latitude: exit.coordinate.latitude,
            longitude: exit.coordinate.longitude
          )
        ),
        nameJA: exit.nameJA
      )
    }
    return overlay
  }

  private var mapVisibleBottomFraction: Double {
    isLandscape
      ? 0.94
      : isDriving
        ? 0.92
        : isPlanningDockExpanded ? 0.66 : 0.88
  }

  private var networkOverviewInitialZoom: Double {
    ProcessInfo.processInfo.arguments.contains(
      "-WHOLE-SHUTO-NETWORK-DETAIL-ZOOM"
    ) ? 2.6 : 1
  }

  private var isTrackMapPositionEstimated: Bool {
    switch model.positionState {
    case .tunnelEstimated, .networkDegraded, .routeInterrupted:
      return true
    default:
      return false
    }
  }

  private var usesExpandedTextLayout: Bool {
    switch dynamicTypeSize {
    case .xSmall, .small, .medium, .large:
      false
    case .xLarge, .xxLarge, .xxxLarge, .accessibility1,
      .accessibility2, .accessibility3, .accessibility4, .accessibility5:
      true
    @unknown default:
      true
    }
  }

  private var topBar: some View {
    VStack(spacing: 8) {
      VStack(spacing: 6) {
        HStack(alignment: .top, spacing: 10) {
          topBarBackButton
          topBarTitle
          Spacer(minLength: 8)
          VStack(alignment: .trailing, spacing: 6) {
            topBarUtilityButtons
            mapModeControl
              .fixedSize(horizontal: true, vertical: false)
          }
        }
      }

      if isActiveNavigation {
        instructionBanner
      }
    }
    .padding(.horizontal, 14)
    .padding(.top, 7)
    .environment(\.colorScheme, .dark)
  }

  @ViewBuilder
  private var topBarBackButton: some View {
    if model.phase != .planning && model.phase != .completed {
      Button {
        if isActiveNavigation {
          requestEndJourney()
        } else {
          model.reset()
        }
      } label: {
        Image(systemName: isActiveNavigation ? "xmark" : "chevron.left")
          .font(.system(size: 14, weight: .black))
          .frame(width: 44, height: 44)
      }
      .buttonStyle(WholeShutoCircleButtonStyle(isDriving: isDriving))
      .accessibilityLabel(
        isActiveNavigation
          ? endJourneyActionLabel
          : copy.resolve(
            japanese: "経路計画に戻る",
            simplifiedChinese: "返回路线规划",
            english: "Back to route planning"
          )
      )
      .accessibilityIdentifier(
        isActiveNavigation
          ? "whole-shuto-end-journey"
          : "whole-shuto-back-to-planning"
      )
      .disabled(isPreparingEndJourneyConfirmation)
    }
  }

  private var topBarTitle: some View {
    Text("KAIDO")
      .font(.headline.weight(.black))
      .fontDesign(.rounded)
      .tracking(1.7)
      .foregroundStyle(KaidoTheme.routeWhite)
      .accessibilityIdentifier("whole-shuto-brand")
      .fixedSize()
      .padding(.horizontal, 9)
      .padding(.vertical, 6)
      .background(KaidoTheme.night.opacity(0.94), in: RoundedRectangle(cornerRadius: 10))
  }

  private var topBarUtilityButtons: some View {
    HStack(spacing: 6) {
      Button { showsSettings = true } label: {
        Image(systemName: "gearshape")
          .font(.system(size: 14, weight: .black))
          .frame(width: 44, height: 44)
      }
      .buttonStyle(WholeShutoCircleButtonStyle(isDriving: isDriving))
      .accessibilityLabel(copy.resolve(japanese: "設定", simplifiedChinese: "设置", english: "Settings"))
      .accessibilityIdentifier("whole-shuto-settings")
      Menu {
        if model.selectedCircuit?.kind == .loop && model.isLiveDrive {
          Button {
            Task { _ = await model.finishCurrentLap() }
          } label: {
            Label(copy.resolve(japanese: "この周回で終了", simplifiedChinese: "本圈结束后离开", english: "Finish this lap"), systemImage: "flag.checkered")
          }
          .disabled(!model.canFinishCurrentLap)
          .accessibilityIdentifier("whole-shuto-finish-current-lap")
        }
        Button { showsSavedRoutes = true } label: {
          Label(copy.resolve(japanese: "保存したルート", simplifiedChinese: "已保存路线", english: "Saved routes"), systemImage: "bookmark")
        }
        .accessibilityIdentifier("whole-shuto-menu-saved-routes")
        Button { showsDriveHistory = true } label: {
          Label(copy.resolve(japanese: "走行履歴", simplifiedChinese: "行程记录", english: "Drive history"), systemImage: "clock.arrow.circlepath")
        }
        .accessibilityIdentifier("whole-shuto-menu-history")
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 14, weight: .black))
          .frame(width: 44, height: 44)
      }
      .buttonStyle(WholeShutoCircleButtonStyle(isDriving: isDriving))
      .accessibilityLabel(copy.resolve(japanese: "メニュー", simplifiedChinese: "菜单", english: "Menu"))
      .accessibilityIdentifier("whole-shuto-menu")
    }
  }

  private var mapModeControl: some View {
    let layout =
      usesExpandedTextLayout
      ? AnyLayout(VStackLayout(spacing: 0))
      : AnyLayout(HStackLayout(spacing: 0))

    return layout {
      mapModeButton(
        .network,
        symbol: "point.3.connected.trianglepath.dotted",
        label: copy.resolve(
          japanese: "ルート図",
          simplifiedChinese: "路线图",
          english: "ROUTE MAP"
        )
      )
      mapModeButton(
        .geographic,
        symbol: "map.fill",
        label: copy.resolve(
          japanese: "地図",
          simplifiedChinese: "地图",
          english: "MAP"
        )
      )
    }
    .padding(3)
    .background(KaidoTheme.nightRaised.opacity(0.95))
    .clipShape(
      RoundedRectangle(
        cornerRadius: usesExpandedTextLayout ? 12 : 999
      )
    )
    .overlay {
      RoundedRectangle(
        cornerRadius: usesExpandedTextLayout ? 12 : 999
      )
        .stroke(KaidoTheme.nightDivider, lineWidth: 1)
    }
  }

  private func mapModeButton(
    _ mode: WholeShutoMapMode,
    symbol: String,
    label: String
  ) -> some View {
    Button {
      model.mapMode = mode
    } label: {
      HStack(spacing: 4) {
        Image(systemName: symbol)
        Text(label)
      }
      .font(.caption.weight(.black))
      .fontDesign(.rounded)
      .foregroundStyle(
        model.mapMode == mode
          ? KaidoTheme.routeWhite
          : KaidoTheme.nightQuiet
      )
      .padding(.horizontal, 9)
      .frame(minWidth: 44, minHeight: 44)
      .background(
        model.mapMode == mode
          ? KaidoTheme.routeGreen
          : KaidoTheme.nightRaised
      )
      .clipShape(Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .frame(minWidth: 44, minHeight: 44)
    .contentShape(Capsule())
    .accessibilityIdentifier("whole-shuto-map-\(mode.rawValue.lowercased())")
  }

  private var planningDock: some View {
    VStack(spacing: 0) {
      if isPlanningDockExpanded {
        planningDockHandle
        if model.phase == .planning {
          routeComposer
        } else {
          routeReview
        }
      } else {
        compactPlanningDockContent
      }
    }
    .background(KaidoTheme.nightPanel)
    .clipShape(
      UnevenRoundedRectangle(
        topLeadingRadius: 20,
        topTrailingRadius: 20
      )
    )
    .shadow(color: .black.opacity(0.16), radius: 18, y: -3)
    .offset(y: planningDockInteractiveOffset)
    .animation(
      .spring(response: 0.28, dampingFraction: 0.86),
      value: isPlanningDockExpanded
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("whole-shuto-planning-dock")
    .accessibilityValue(
      isPlanningDockExpanded ? "EXPANDED" : "COLLAPSED"
    )
  }

  private var planningDockHandle: some View {
    VStack(spacing: 5) {
      Capsule()
        .fill(KaidoTheme.roadGray.opacity(0.72))
        .frame(width: 42, height: 5)
      Image(
        systemName: isPlanningDockExpanded
          ? "chevron.down" : "chevron.up"
      )
      .font(.system(size: 10, weight: .black))
      .foregroundStyle(KaidoTheme.nightQuiet)
    }
    .frame(maxWidth: .infinity, minHeight: 44)
    .contentShape(Rectangle())
    .onTapGesture {
      setPlanningDockExpanded(!isPlanningDockExpanded)
    }
    .gesture(planningDockDragGesture)
    .accessibilityElement(children: .ignore)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction {
      setPlanningDockExpanded(!isPlanningDockExpanded)
    }
    .accessibilityLabel(
      copy.resolve(
        japanese: isPlanningDockExpanded ? "パネルを閉じる" : "パネルを開く",
        simplifiedChinese: isPlanningDockExpanded ? "收起面板" : "展开面板",
        english: isPlanningDockExpanded ? "Collapse panel" : "Expand panel"
      )
    )
    .accessibilityIdentifier("whole-shuto-planning-dock-handle")
  }

  private var compactPlanningDockContent: some View {
    Button {
      setPlanningDockExpanded(true)
    } label: {
      ZStack(alignment: .top) {
        Capsule()
          .fill(KaidoTheme.roadGray.opacity(0.72))
          .frame(width: 32, height: 4)

        HStack(spacing: 10) {
          Image(
            systemName: model.phase == .planning
              ? "point.3.connected.trianglepath.dotted"
              : "road.lanes"
          )
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(KaidoTheme.routeGreen)
          .frame(width: 28, height: 28)
          .background(KaidoTheme.routeGreen.opacity(0.14))
          .clipShape(Circle())

          VStack(alignment: .leading, spacing: 1) {
            Text(compactPlanningDockTitle)
              .font(.subheadline.weight(.bold))
              .foregroundStyle(KaidoTheme.routeWhite)
            Text(compactPlanningDockDetail)
              .font(.caption2.weight(.medium))
              .foregroundStyle(KaidoTheme.nightQuiet)
              .lineLimit(1)
          }
          Spacer(minLength: 8)
          Image(systemName: "chevron.up")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(KaidoTheme.nightQuiet)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
      }
      .frame(maxWidth: .infinity, minHeight: 60)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .simultaneousGesture(planningDockDragGesture)
    .accessibilityIdentifier("whole-shuto-planning-dock-summary")
  }

  private var compactPlanningDockTitle: String {
    if model.phase == .planning {
      return model.selectedCircuit?.displayName(
        for: languageSettings.interfaceLocale
      )
        ?? copy.resolve(
          japanese: "ルートを選ぶ",
          simplifiedChinese: "选择路线",
          english: "Choose a route"
        )
    }
    return routeSummaryTitle
  }

  private var compactPlanningDockDetail: String {
    if let entry = model.circuitEntryFacility,
      let exit = model.circuitExitFacility,
      model.phase == .planning
    {
      return "\(entry.nameJA) → \(exit.nameJA)"
    }
    if model.phase == .review {
      return "\(routeSummarySubtitle) · "
        + distanceLabel(model.selectedRoute?.distanceMeters ?? 0)
    }
    return planningLocationLongLabel
  }

  private var planningDockInteractiveOffset: CGFloat {
    if isPlanningDockExpanded {
      return max(0, planningDockDragOffset)
    }
    return min(0, planningDockDragOffset)
  }

  private var planningDockDragGesture: some Gesture {
    DragGesture(minimumDistance: 6)
      .updating($planningDockDragOffset) { value, state, _ in
        state = value.translation.height
      }
      .onEnded { value in
        if value.translation.height > 36 {
          setPlanningDockExpanded(false)
        } else if value.translation.height < -36 {
          setPlanningDockExpanded(true)
        }
      }
  }

  private func setPlanningDockExpanded(_ expanded: Bool) {
    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
      isPlanningDockExpanded = expanded
      if !expanded {
        showsDestinationComposer = false
        focusedPlanningField = nil
        placeSearch.dismissResults()
      }
    }
  }

  private var routeComposer: some View {
    VStack(spacing: 12) {
      circuitExperienceSection

      HStack(spacing: 8) {
        if !showsDestinationComposer {
          // The origin chip stays on the home even while the destination
          // composer is collapsed.
          planningLocationButton
        }
        optionalDestinationDivider
      }

      if showsDestinationComposer {
        journeySearchComposer
      }

      routeFailureBanner
    }
    .padding(.horizontal, 16)
    .padding(.top, 4)
    .padding(.bottom, 14)
  }

  /// The home leads with the route experience, not a destination field.
  private var circuitExperienceSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(
        copy.resolve(
          japanese: "ルートを選ぶ",
          simplifiedChinese: "选择路线",
          english: "CHOOSE A ROUTE"
        )
      )
      .font(.system(size: 11, weight: .bold))
      .foregroundStyle(.secondary)

      if let circuit = model.selectedCircuit {
        selectedCircuitPanel(circuit)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 10) {
            ForEach(model.bundledCircuits) { circuit in
              circuitCard(circuit)
            }
          }
        }

        Text(copy.resolve(
          japanese: "高速区間の参考値 · 接続道路と渋滞は含みません",
          simplifiedChinese: "高速路段参考 · 不含接驳与实时路况",
          english: "Expressway reference · excludes access roads and live traffic"
        ))
        .font(.caption)
        .foregroundStyle(KaidoTheme.nightQuiet)

        savedRouteHomeEntry
        Button { showsDriveHistory = true } label: {
          HStack {
            Label(copy.resolve(japanese: "走行履歴", simplifiedChinese: "行程记录", english: "Drive history"), systemImage: "clock.arrow.circlepath")
            Spacer()
            Image(systemName: "chevron.right")
          }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(KaidoTheme.positionCyan)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("whole-shuto-drive-history-open")
        customRouteHomeEntry
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("whole-shuto-circuit-experiences")
  }

  private var savedRouteHomeEntry: some View {
    Button {
      pendingSavedRouteRecordID = nil
      savedRouteOpenErrorCode = nil
      savedRouteImportErrorCode = nil
      showsSavedRoutes = true
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "bookmark.fill")
          .font(.system(size: 10, weight: .black))
        Text(
          copy.resolve(
            japanese: "保存したルート",
            simplifiedChinese: "已保存路线",
            english: "SAVED ROUTES"
          )
        )
        Spacer()
        Text("\(savedRoutes.records.count)")
          .font(.system(size: 9, weight: .black, design: .monospaced))
        Image(systemName: "chevron.right")
          .font(.system(size: 9, weight: .black))
      }
      .font(.system(size: 10, weight: .bold))
      .foregroundStyle(KaidoTheme.positionCyan)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("whole-shuto-saved-routes")
    .accessibilityValue("\(savedRoutes.records.count)")
  }

  private var savedRouteLibrarySheet: some View {
    VStack(spacing: 0) {
      HStack {
        Text(
          copy.resolve(
            japanese: "保存したルート",
            simplifiedChinese: "已保存路线",
            english: "Saved routes"
          )
        )
        .font(.system(size: 22, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)

        Spacer()

        Button {
          pendingSavedRouteRecordID = nil
          savedRouteOpenErrorCode = nil
          showsSavedRoutes = false
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 12, weight: .black))
            .frame(width: 44, height: 44)
            .background(KaidoTheme.nightRaised)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          copy.resolve(
            japanese: "保存したルートを閉じる",
            simplifiedChinese: "关闭已保存路线",
            english: "Close saved routes"
          )
        )
        .accessibilityIdentifier("whole-shuto-saved-routes-close")
      }
      .padding(.horizontal, 18)
      .padding(.top, 14)

      ScrollView {
        VStack(spacing: 12) {
          SavedRouteLibraryPanel(
            model: savedRoutes,
            openRecord: requestOpenSavedRoute,
            importPresentation: $isImportingSavedRoute
          )

          if let savedRouteOpenErrorCode {
            ReviewBoundaryCard(
              symbol: "location.slash.fill",
              title: copy.resolve(
                japanese: "出発地が必要です",
                simplifiedChinese: "需要出发地",
                english: "Origin required"
              ),
              detail: copy.resolve(
                japanese:
                  "現在地を利用できません。ホームで出発地を入力してから、もう一度開いてください。",
                simplifiedChinese:
                  "无法使用当前位置。请先在首页输入出发地，再重新打开。",
                english:
                  "Current location is unavailable. Enter an origin on the home screen, then open the route again."
              ),
              code: savedRouteOpenErrorCode,
              color: KaidoTheme.evidenceCoral
            )
            .accessibilityIdentifier("whole-shuto-saved-route-open-error")
          }

          if let savedRouteImportErrorCode {
            ReviewBoundaryCard(
              symbol: "doc.badge.exclamationmark",
              title: copy.resolve(
                japanese: "ルートを読み込めませんでした",
                simplifiedChinese: "无法导入路线",
                english: "Route import failed"
              ),
              detail: copy.resolve(
                japanese: "選択したファイルを確認して、もう一度お試しください。",
                simplifiedChinese: "请检查所选文件后重试。",
                english: "Check the selected file and try again."
              ),
              code: savedRouteImportErrorCode,
              color: KaidoTheme.evidenceCoral
            )
            .accessibilityIdentifier("whole-shuto-saved-route-import-error")
          }
        }
        .padding(18)
      }
      .scrollIndicators(.hidden)
    }
    .background(KaidoTheme.nightPanel)
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .presentationBackground(KaidoTheme.nightPanel)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("whole-shuto-saved-route-sheet")
  }

  private func requestOpenSavedRoute(_ recordID: String) {
    guard let record = savedRoutes.record(id: recordID) else {
      savedRouteOpenErrorCode =
        SavedRouteLibraryModelError.recordUnavailable.rawValue
      return
    }
    if model.currentCoordinate != nil || planningLocation.snapshot != nil || model.origin != nil {
      finishOpeningSavedRoute(record)
      return
    }
    switch planningLocation.state {
    case .denied, .unavailable:
      pendingSavedRouteRecordID = nil
      savedRouteOpenErrorCode = "LOCATION_UNAVAILABLE"
    case .idle, .permissionRequired, .locating, .measured, .stopped:
      pendingSavedRouteRecordID = recordID
      savedRouteOpenErrorCode = nil
      planningLocation.requestCurrentLocation()
    }
  }

  private func finishOpeningSavedRoute(_ record: SavedRouteRecord) {
    let opened = model.openSavedRoute(
      record,
      origin: (isDriving ? model.currentCoordinate : nil) ?? planningLocation.snapshot?.coordinate
    )
    pendingSavedRouteRecordID = nil
    if opened {
      savedRouteOpenErrorCode = nil
      showsSavedRoutes = false
    } else {
      savedRouteOpenErrorCode =
        model.failureCode ?? "SAVED_ROUTE_CURRENT_SNAPSHOT_INVALID"
    }
  }

  /// The advanced entry at the catalog's foot: exact entrance/exit routes
  /// for drivers who want to specify the pairing themselves.
  private var customRouteHomeEntry: some View {
    Button {
      if let snapshot = planningLocation.snapshot {
        model.selectCurrentOrigin(snapshot.coordinate)
        openCustomRouteEditor()
      } else if model.origin != nil {
        openCustomRouteEditor()
      } else if !model.usesCurrentLocationOrigin,
        !model.originQuery.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty
      {
        resolveManualOriginForCustomRoute()
      } else if planningLocation.state == .denied
        || planningLocation.state == .unavailable
      {
        showsManualOrigin = true
        showsDestinationComposer = true
        focusedPlanningField = .origin
      } else {
        waitsForCustomRouteLocation = true
        planningLocation.requestCurrentLocation()
        handlePlanningLocationUpdate()
      }
    } label: {
      HStack(spacing: 6) {
        if waitsForCustomRouteLocation {
          ProgressView()
            .controlSize(.small)
            .tint(KaidoTheme.positionCyan)
          Text(
            copy.resolve(
              japanese: "近くの入口を確認中",
              simplifiedChinese: "正在查找附近入口",
              english: "Finding nearby entrances"
            )
          )
        } else {
          Image(systemName: "slider.horizontal.3")
            .font(.system(size: 10, weight: .black))
          Text(
            copy.resolve(
              japanese: "カスタム · 入口と出口を指定",
              simplifiedChinese: "自定义 · 指定入口和出口",
              english: "CUSTOM · EXACT ENTRY AND EXIT"
            )
          )
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .black))
        }
      }
      .font(.system(size: 10, weight: .bold))
      .foregroundStyle(KaidoTheme.nightQuiet)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(waitsForCustomRouteLocation)
    .accessibilityIdentifier("whole-shuto-custom-from-home")
  }

  private func openCustomRouteEditor() {
    waitsForCustomRouteLocation = false
    model.prepareCustomRouteDraft()
    showsRouteCustomization = true
  }

  private func resolveManualOriginForCustomRoute() {
    waitsForCustomRouteLocation = true
    focusedPlanningField = nil
    placeSearch.dismissResults()
    Task {
      if await model.resolveTypedOriginPreview() {
        openCustomRouteEditor()
      } else {
        waitsForCustomRouteLocation = false
        showsManualOrigin = true
        showsDestinationComposer = true
        focusedPlanningField = .origin
      }
    }
  }

  /// The route's silhouette in the card, drawn from the precomputed
  /// normalized track shape.
  private func circuitThumbnail(_ points: [CGPoint]) -> some View {
    Canvas { context, size in
      let xs = points.map { Double($0.x) }
      let ys = points.map { Double($0.y) }
      guard let minX = xs.min(), let maxX = xs.max(),
        let minY = ys.min(), let maxY = ys.max(),
        maxX > minX, maxY > minY
      else { return }
      let inset = 3.0
      let width = Double(size.width)
      let height = Double(size.height)
      let scale = min(
        (width - 2 * inset) / (maxX - minX),
        (height - 2 * inset) / (maxY - minY)
      )
      let offsetX =
        inset + ((width - 2 * inset) - (maxX - minX) * scale) / 2
      let offsetY =
        inset + ((height - 2 * inset) - (maxY - minY) * scale) / 2
      var path = Path()
      for (index, value) in zip(xs, ys).enumerated() {
        let mapped = CGPoint(
          x: offsetX + (value.0 - minX) * scale,
          y: offsetY + (value.1 - minY) * scale
        )
        if index == 0 {
          path.move(to: mapped)
        } else {
          path.addLine(to: mapped)
        }
      }
      context.stroke(
        path,
        with: .color(KaidoTheme.confirmedGreen),
        style: StrokeStyle(
          lineWidth: 3,
          lineCap: .round,
          lineJoin: .round
        )
      )
      if points.count > 3 {
        let index = points.count / 3
        let point = CGPoint(
          x: offsetX + (Double(points[index].x) - minX) * scale,
          y: offsetY + (Double(points[index].y) - minY) * scale
        )
        let angle = atan2(
          Double(points[index + 1].y - points[index].y),
          Double(points[index + 1].x - points[index].x)
        )
        var arrow = Path()
        arrow.move(to: CGPoint(x: -4, y: -4))
        arrow.addLine(to: CGPoint(x: 3, y: 0))
        arrow.addLine(to: CGPoint(x: -4, y: 4))
        context.drawLayer { layer in
          layer.translateBy(x: point.x, y: point.y)
          layer.rotate(by: .radians(angle))
          layer.stroke(arrow, with: .color(KaidoTheme.routeWhite), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
      }
    }
    .frame(height: 52)
    .accessibilityHidden(true)
  }

  private func circuitKindText(
    _ circuit: ShutoCircuitDefinition
  ) -> String {
    switch circuit.kind {
    case .loop:
      return copy.resolve(
        japanese: "周回ルート",
        simplifiedChinese: "环线路线",
        english: "CIRCUIT"
      )
    case .tour:
      return copy.resolve(
        japanese: "ワンウェイツアー",
        simplifiedChinese: "单程巡游",
        english: "TOUR"
      )
    }
  }

  /// The parking areas the course stops at, named from the snapshot. A
  /// course that only passes a parking area contributes nothing here: the
  /// green line means the route drives in, not that a PA is somewhere along
  /// the way.
  private func circuitParkingStopNames(
    _ circuit: ShutoCircuitDefinition
  ) -> [String] {
    circuit.parkingAreaStopIDs.compactMap { parkingAreaID in
      model.database.parkingAreas
        .first { $0.parkingAreaID == parkingAreaID }?
        .nameJA
    }
  }

  /// The route marks the card's experience actually drives, in course order:
  /// the same shields the overhead signs carry, so a driver recognises the
  /// experience by road before reading the name.
  private func circuitShields(_ routeIDs: [String]) -> some View {
    HStack(spacing: 4) {
      ForEach(Array(routeIDs.enumerated()), id: \.offset) { _, routeID in
        Text(shieldLabel(routeID))
          .font(.system(size: 10, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
          .padding(.horizontal, 5)
          .frame(height: 18)
          .background(routeColor(routeID))
          .clipShape(RoundedRectangle(cornerRadius: 4))
      }
    }
    // Decorative: a standalone accessibility element here would be an
    // 18pt-tall VoiceOver stop inside the card's own button, which the
    // hit-region audit reads as an interactive target too small to press.
    // The card speaks the routes instead, on a target that is big enough.
    .accessibilityHidden(true)
  }

  /// What the card's button says it drives, for a reader that never sees the
  /// shields.
  private func circuitRoutesAccessibilityValue(
    _ circuit: ShutoCircuitDefinition
  ) -> String? {
    guard
      let preview = model.circuitPreviewsByID[circuit.circuitID],
      !preview.routeIDsInOrder.isEmpty
    else { return nil }
    return preview.routeIDsInOrder
      .map { routeDisplayLabel($0, in: model.database) }
      .joined(separator: " → ")
  }

  private func circuitCard(
    _ circuit: ShutoCircuitDefinition
  ) -> some View {
    Button {
      model.selectCircuit(circuit)
      if let snapshot = planningLocation.snapshot {
        model.selectCurrentOrigin(snapshot.coordinate)
        model.refreshCircuitEntrances()
      } else {
        planningLocation.requestCurrentLocation()
      }
    } label: {
      VStack(alignment: .leading, spacing: 5) {
        if let preview = model.circuitPreviewsByID[circuit.circuitID],
          preview.points.count > 1
        {
          circuitThumbnail(preview.points)
        } else {
          Image(
            systemName: circuit.kind == .loop
              ? "arrow.triangle.capsulepath"
              : "point.topleft.down.curvedto.point.bottomright.up"
          )
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(KaidoTheme.routeGreen)
          .frame(height: 38)
        }
        if let preview = model.circuitPreviewsByID[circuit.circuitID],
          !preview.routeIDsInOrder.isEmpty
        {
          circuitShields(preview.routeIDsInOrder)
        }
        Text(circuit.displayName(for: languageSettings.interfaceLocale))
          .font(.subheadline.weight(.bold))
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
        Text(circuitKindText(circuit))
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        if let preview = model.circuitPreviewsByID[circuit.circuitID] {
          Text(copy.resolve(
            japanese: "約\(preview.referenceMinutes)分 · \(distanceLabel(preview.distanceMeters))",
            simplifiedChinese: "约 \(preview.referenceMinutes) 分钟 · \(distanceLabel(preview.distanceMeters))",
            english: "~\(preview.referenceMinutes) min · \(distanceLabel(preview.distanceMeters))"
          ))
          .font(.system(.headline, design: .rounded).weight(.bold))
          .foregroundStyle(KaidoTheme.routeWhite)
          .monospacedDigit()
          .accessibilityIdentifier("whole-shuto-circuit-metrics-\(circuit.circuitID)")
          Text(copy.resolve(
            japanese: "分岐案内 \(preview.junctionCount)か所",
            simplifiedChinese: "\(preview.junctionCount) 处路口提示",
            english: "\(preview.junctionCount) junction cues"
          ))
          .font(.caption)
          .foregroundStyle(KaidoTheme.nightQuiet)
        }
        let landmarkNames = circuit.landmarkNames(
          for: languageSettings.interfaceLocale
        )
        if !landmarkNames.isEmpty {
          Text(landmarkNames.joined(separator: "・"))
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        let parkingStopNames = circuitParkingStopNames(circuit)
        if let parking = model.database.parkingAreas.first(where: { $0.parkingAreaID == circuit.defaultDestinationParkingAreaID }) {
          Text(copy.resolve(japanese: "目的地：", simplifiedChinese: "目的地：", english: "Destination: ") + parking.nameJA)
            .font(.caption.weight(.bold))
            .foregroundStyle(KaidoTheme.confirmedGreen)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("whole-shuto-circuit-destination-\(circuit.circuitID)")
        } else if !parkingStopNames.isEmpty {
          // Text alone, no parking glyph: the filled SF parking symbol
          // renders its counter in the card ground and fails the home's
          // contrast audit, and the green line already reads as a stop.
          Text(parkingStopNames.joined(separator: "・"))
            .font(.caption.weight(.bold))
            .foregroundStyle(KaidoTheme.confirmedGreen)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(
              "whole-shuto-circuit-pa-stops-\(circuit.circuitID)"
            )
        }
      }
      .frame(width: 222, alignment: .leading)
      .padding(14)
      .background(KaidoTheme.nightRaised.opacity(0.94))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(KaidoTheme.nightDivider, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(
      "whole-shuto-circuit-option-\(circuit.circuitID)"
    )
    .accessibilityValue(circuitRoutesAccessibilityValue(circuit) ?? "")
  }

  private func selectedCircuitPanel(
    _ circuit: ShutoCircuitDefinition
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Button {
          showsCircuitAlternatives = false
          model.clearCircuitDraft()
        } label: {
          HStack(spacing: 5) {
            Image(systemName: "chevron.left")
            Text(
              copy.resolve(
                japanese: "ルート一覧",
                simplifiedChinese: "返回路线列表",
                english: "ALL ROUTES"
              )
            )
          }
          .font(.caption.weight(.bold))
          .foregroundStyle(KaidoTheme.positionCyan)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("whole-shuto-circuit-back")

        Spacer()

        Text(circuit.displayName(for: languageSettings.interfaceLocale))
          .font(.system(size: 14, weight: .bold))
          .multilineTextAlignment(.trailing)
      }

      circuitPairingSummary(circuit)

      if !model.circuitEntranceCandidates.isEmpty {
        Button {
          showsCircuitAlternatives.toggle()
        } label: {
          HStack(spacing: 5) {
            Text(
              copy.resolve(
                japanese: "入口を変更",
                simplifiedChinese: "更换入口",
                english: "CHANGE ENTRANCE"
              )
            )
            Image(
              systemName: showsCircuitAlternatives
                ? "chevron.up" : "chevron.down"
            )
          }
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(.secondary)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("whole-shuto-circuit-alternatives")

        if showsCircuitAlternatives {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(
              Array(model.circuitEntranceCandidates.prefix(3)),
              id: \.facilityID
            ) { facility in
              circuitEntranceRow(facility)
            }
          }
        }
      }

      if circuit.kind == .loop {
        HStack(spacing: 10) {
          Text(
            copy.resolve(
              japanese: "周回数",
              simplifiedChinese: "圈数",
              english: "LAPS"
            )
          )
          .font(.system(size: 12, weight: .semibold))
          Spacer()
          Button {
            model.selectCircuitLaps(model.circuitLaps - 1)
          } label: {
            Image(systemName: "minus.circle")
              .font(.system(size: 20))
          }
          .buttonStyle(.plain)
          .disabled(model.circuitLaps <= 1)
          .accessibilityIdentifier("whole-shuto-circuit-laps-decrease")
          Text("×\(model.circuitLaps)")
            .font(.system(size: 15, weight: .bold))
            .monospacedDigit()
            .accessibilityIdentifier("whole-shuto-circuit-laps")
            .accessibilityValue("\(model.circuitLaps)")
          Button {
            model.selectCircuitLaps(model.circuitLaps + 1)
          } label: {
            Image(systemName: "plus.circle")
              .font(.system(size: 20))
          }
          .buttonStyle(.plain)
          .disabled(
            model.circuitLaps >= ShutoCircuitDefinition.loopLapRange.upperBound
          )
          .accessibilityIdentifier("whole-shuto-circuit-laps-increase")
        }
      }

      Button {
        beginCircuitJourney()
      } label: {
        HStack(spacing: 8) {
          if waitsForCircuitLocation {
            ProgressView()
              .tint(.white)
            Text(
              copy.resolve(
                japanese: "現在地を確認中",
                simplifiedChinese: "正在定位",
                english: "LOCATING"
              )
            )
          } else {
            Text(
              copy.resolve(
                japanese: "このルートで行く",
                simplifiedChinese: "使用此路线",
                english: "Use this route"
              )
            )
            Spacer()
            Image(systemName: "arrow.right")
          }
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(KaidoTheme.routeWhite)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(KaidoTheme.routeGreen)
        .clipShape(RoundedRectangle(cornerRadius: 10))
      }
      .buttonStyle(.plain)
      .disabled(!model.canStartCircuitJourney || waitsForCircuitLocation)
      .opacity(model.canStartCircuitJourney ? 1 : 0.45)
      .accessibilityIdentifier("whole-shuto-start-circuit")
    }
    .padding(12)
    .background(KaidoTheme.nightRaised.opacity(0.94))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(KaidoTheme.nightDivider, lineWidth: 1)
    }
  }

  /// The derived pairing as one factual line: entrance → exit plus the
  /// dated-evidence tariff band. Nothing is shown until derivation finishes.
  private func circuitPairingSummary(
    _ circuit: ShutoCircuitDefinition
  ) -> some View {
    Group {
      if model.isResolvingCircuitPairing || awaitsCircuitPairingOrigin {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text(
            awaitsCircuitPairingOrigin
              ? copy.resolve(
                japanese: "現在地を確認中",
                simplifiedChinese: "正在定位",
                english: "Finding your location"
              )
              : copy.resolve(
                japanese: model.selectedCircuit?.defaultDestinationParkingAreaID == nil ? "現在地から入口・出口を導出中" : "入口を選択中",
                simplifiedChinese: model.selectedCircuit?.defaultDestinationParkingAreaID == nil ? "正在按当前位置推导入口/出口" : "正在选择入口",
                english: model.selectedCircuit?.defaultDestinationParkingAreaID == nil ? "Deriving entrance and exit" : "Choosing an entrance"
              )
          )
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("whole-shuto-circuit-pairing-progress")
      } else if let entry = model.circuitEntryFacility,
        let destinationName = model.circuitDestinationNameJA
      {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 5) {
            Image(
              systemName: model.circuitEntranceWasOverridden
                ? "hand.tap.fill" : "location.fill"
            )
            Text(circuitPairingReasonLabel)
          }
          .font(.caption.weight(.black))
          .foregroundStyle(KaidoTheme.positionCyan)

          HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
              Text(
                copy.resolve(
                  japanese: "入口",
                  simplifiedChinese: "入口",
                  english: "ENTRANCE"
                )
              )
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
              Text(entry.nameJA)
                .font(.system(size: 13, weight: .bold))
            }
            Image(systemName: "arrow.right")
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(.secondary)
              .padding(.bottom, 3)
            VStack(alignment: .leading, spacing: 2) {
              Text(
                copy.resolve(
                  japanese: model.selectedCircuit?.defaultDestinationParkingAreaID == nil ? "おすすめ出口" : "目的地",
                  simplifiedChinese: model.selectedCircuit?.defaultDestinationParkingAreaID == nil ? "推荐出口" : "目的地",
                  english: model.selectedCircuit?.defaultDestinationParkingAreaID == nil ? "RECOMMENDED EXIT" : "DESTINATION"
                )
              )
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
              Text(destinationName)
                .font(.system(size: 13, weight: .bold))
            }
            if entry.etcOnly || model.circuitExitFacility?.etcOnly == true {
              Text("ETC")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(KaidoTheme.roadGray.opacity(0.25))
                .clipShape(Capsule())
            }
            Spacer()
          }
          HStack(spacing: 6) {
            if let band = model.circuitPairingBand {
              Text(circuitTariffText(band))
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(
                  circuitTariffIsMinimum(band)
                    ? KaidoTheme.routeGreen : Color.secondary
                )
                .accessibilityIdentifier(
                  "whole-shuto-circuit-pairing-tariff"
                )
            }
            if let meters = model.circuitEntranceDistanceMeters {
              Text(
                copy.resolve(
                  japanese: String(
                    format: "直線約%.1fkm",
                    meters / 1000
                  ),
                  simplifiedChinese: String(
                    format: "直线约 %.1f km",
                    meters / 1000
                  ),
                  english: String(
                    format: "≈ %.1f km straight-line",
                    meters / 1000
                  )
                )
              )
              .font(.system(size: 10.5, weight: .semibold))
              .monospacedDigit()
              .foregroundStyle(.secondary)
              let accessTier = ShutoEntranceAccessTier.classify(
                distanceMeters: meters
              )
              if accessTier != .nearby {
                Text(
                  copy.resolve(
                    japanese: accessTier == .far ? "遠め" : "遠方接続",
                    simplifiedChinese: accessTier == .far ? "较远" : "远途接入",
                    english: accessTier == .far ? "FAR" : "LONG ACCESS"
                  )
                )
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(KaidoTheme.signalAmber.opacity(0.3))
                .clipShape(Capsule())
                .accessibilityIdentifier(
                  accessTier == .far
                    ? "whole-shuto-circuit-entrance-far"
                    : "whole-shuto-circuit-entrance-extended"
                )
              }
            }
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("whole-shuto-circuit-pairing")
      } else {
        Text(
          model.origin == nil
            ? copy.resolve(
              japanese: "現在地を取得できません。出発地を入力してください",
              simplifiedChinese: "无法获取当前位置，请输入出发地",
              english: "Current location unavailable — enter an origin"
            )
            : copy.resolve(
              japanese: "この付近から入れる方向対応の入口が見つかりません",
              simplifiedChinese: "附近没有方向匹配的可用入口",
              english: "No direction-valid entrance reachable from here"
            )
        )
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(.secondary)
      }
    }
  }

  /// A card tapped before the location fix lands has no origin to derive
  /// from yet: the pairing is pending, not empty. Only a settled denial or
  /// failure ends the wait.
  private var awaitsCircuitPairingOrigin: Bool {
    guard model.origin == nil else { return false }
    switch planningLocation.state {
    case .idle, .permissionRequired, .locating, .measured, .stopped:
      return true
    case .denied, .unavailable:
      return false
    }
  }

  private var circuitPairingReasonLabel: String {
    if model.circuitEntranceWasOverridden {
      return copy.resolve(
        japanese: "選択した入口と出口",
        simplifiedChinese: "已选择的入口和出口",
        english: "Selected entry and exit"
      )
    }
    return model.usesCurrentLocationOrigin
      ? copy.resolve(
        japanese: "現在地から最寄りの到達可能な入口",
        simplifiedChinese: "根据当前位置推荐最近可达入口",
        english: "Nearest reachable entrance from your location"
      )
      : copy.resolve(
        japanese: "出発地から最寄りの到達可能な入口",
        simplifiedChinese: "根据出发地推荐最近可达入口",
        english: "Nearest reachable entrance from origin"
      )
  }

  private func circuitEntranceRow(
    _ facility: ShutoNetworkDatabase.Facility
  ) -> some View {
    let isSelected = model.circuitEntryFacilityID == facility.facilityID
    return Button {
      model.selectCircuitEntrance(facilityID: facility.facilityID)
    } label: {
      HStack(spacing: 8) {
        Image(
          systemName: isSelected ? "circle.inset.filled" : "circle"
        )
        .font(.system(size: 14))
        .foregroundStyle(
          isSelected ? KaidoTheme.routeGreen : Color.secondary
        )
        Text(facility.nameJA)
          .font(.system(size: 13, weight: .semibold))
        Text(facility.entranceDirections.joined(separator: "・"))
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(.secondary)
        if let origin = model.origin {
          Text(
            copy.resolve(
              japanese: "直線 \(distanceLabel(distance(origin.coordinate, facility.coordinate)))",
              simplifiedChinese:
                "直线 \(distanceLabel(distance(origin.coordinate, facility.coordinate)))",
              english:
                "\(distanceLabel(distance(origin.coordinate, facility.coordinate))) straight-line"
            )
          )
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .monospacedDigit()
        }
        if isSelected {
          Text(
            copy.resolve(
              japanese: "選択中",
              simplifiedChinese: "已选",
              english: "SELECTED"
            )
          )
          .font(.caption2.weight(.black))
          .foregroundStyle(KaidoTheme.night)
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .background(KaidoTheme.positionCyan)
          .clipShape(Capsule())
        }
        if facility.etcOnly {
          Text("ETC")
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(KaidoTheme.roadGray.opacity(0.25))
            .clipShape(Capsule())
        }
        Spacer()
        if let band =
          model.circuitTariffBandsByFacilityID[facility.facilityID]
        {
          Text(circuitTariffText(band))
            .font(.system(size: 10.5, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(
              circuitTariffIsMinimum(band)
                ? KaidoTheme.routeGreen : Color.secondary
            )
            .accessibilityIdentifier(
              "whole-shuto-circuit-tariff-\(facility.facilityID)"
            )
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(
      "whole-shuto-circuit-entrance-\(facility.facilityID)"
    )
  }

  private func distance(
    _ lhs: ShutoCoordinate,
    _ rhs: ShutoCoordinate
  ) -> Double {
    CLLocation(
      latitude: lhs.latitude,
      longitude: lhs.longitude
    ).distance(
      from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
    )
  }

  private func circuitTariffIsMinimum(_ band: ShutoTariffBand) -> Bool {
    if case .minimum = band { return true }
    return false
  }

  private func circuitTariffText(_ band: ShutoTariffBand) -> String {
    switch band {
    case .minimum(let yen):
      return copy.resolve(
        japanese: "¥\(yen)・最低料金帯",
        simplifiedChinese: "¥\(yen)·最低费用档",
        english: "¥\(yen) MIN BAND"
      )
    case .estimated(let yen):
      return copy.resolve(
        japanese: "目安 ¥\(yen)",
        simplifiedChinese: "约 ¥\(yen)",
        english: "≈ ¥\(yen)"
      )
    case .maximum(let yen):
      return copy.resolve(
        japanese: "¥\(yen)・上限",
        simplifiedChinese: "¥\(yen)·上限",
        english: "¥\(yen) CAP"
      )
    }
  }

  /// The destination is an optional continuation after route choice, so the
  /// search composer stays collapsed behind this divider by default.
  private var optionalDestinationDivider: some View {
    Button {
      showsDestinationComposer.toggle()
      if !showsDestinationComposer {
        focusedPlanningField = nil
        placeSearch.dismissResults()
      }
    } label: {
      HStack(spacing: 8) {
        Rectangle()
          .fill(KaidoTheme.nightDivider)
          .frame(height: 1)
        Text(
          copy.resolve(
            japanese: "または目的地へ",
            simplifiedChinese: "或者：去一个地方",
            english: "OR GO SOMEWHERE"
          )
        )
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .fixedSize()
        Image(
          systemName: showsDestinationComposer
            ? "chevron.up" : "chevron.down"
        )
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.secondary)
        Rectangle()
          .fill(KaidoTheme.nightDivider)
          .frame(height: 1)
      }
      .frame(maxWidth: .infinity, minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contentShape(Rectangle())
    .accessibilityIdentifier("whole-shuto-destination-toggle")
  }

  private func beginCircuitJourney() {
    focusedPlanningField = nil
    placeSearch.dismissResults()

    if model.origin != nil {
      model.startCircuitJourney()
      return
    }
    if let snapshot = planningLocation.snapshot {
      model.selectCurrentOrigin(snapshot.coordinate)
      model.refreshCircuitEntrances()
      model.startCircuitJourneyWhenPaired()
      return
    }
    if planningLocation.state == .denied
      || planningLocation.state == .unavailable
    {
      showsManualOrigin = true
      showsDestinationComposer = true
      focusedPlanningField = .origin
      return
    }
    waitsForCircuitLocation = true
    planningLocation.requestCurrentLocation()
    handlePlanningLocationUpdate()
  }

  private var journeySearchComposer: some View {
    VStack(spacing: 10) {
      HStack(spacing: 8) {
        planningLocationButton
        routeField(
          symbol:
            model.hasSelectedDestinationPreview
            ? "checkmark" : "magnifyingglass",
          tint: KaidoTheme.routeGreen,
          label: copy.resolve(
            japanese: "目的地",
            simplifiedChinese: "目的地",
            english: "DESTINATION"
          ),
          text: $model.destinationQuery,
          prompt: copy.resolve(
            japanese: "行き先を検索",
            simplifiedChinese: "搜索目的地",
            english: "Search destination"
          ),
          accessibilityIdentifier: "whole-shuto-destination-search",
          focus: .destination
        )
        .padding(.horizontal, 8)
        .background(KaidoTheme.nightRaised.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
          RoundedRectangle(cornerRadius: 12)
            .stroke(KaidoTheme.nightDivider, lineWidth: 1)
        }
      }

      if showsManualOrigin
        || planningLocation.state == .denied
        || planningLocation.state == .unavailable
      {
        routeField(
          symbol: "mappin.and.ellipse",
          tint: KaidoTheme.positionCyan,
          label: copy.resolve(
            japanese: "出発地",
            simplifiedChinese: "出发地",
            english: "ORIGIN"
          ),
          text: $model.originQuery,
          prompt: copy.resolve(
            japanese: "出発地を入力",
            simplifiedChinese: "输入出发地",
            english: "Enter origin"
          ),
          accessibilityIdentifier: "whole-shuto-manual-origin",
          focus: .origin
        )
        .padding(.horizontal, 8)
        .background(KaidoTheme.nightRaised.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
          RoundedRectangle(cornerRadius: 12)
            .stroke(KaidoTheme.nightDivider, lineWidth: 1)
        }
      }

      planningPlaceSearchResults

      planRouteButton(
        title: copy.resolve(
          japanese: "ルートを検索",
          simplifiedChinese: "查找路线",
          english: "Find routes"
        )
      )
      .disabled(
        !canSubmitRoutePlan
      )
      .opacity(
        canSubmitRoutePlan ? 1 : 0.45
      )
    }
  }

  @ViewBuilder
  private var planningPlaceSearchResults: some View {
    if planningSearchField != nil {
      switch placeSearch.state {
      case .searching:
        HStack(spacing: 8) {
          ProgressView()
          Text(
            copy.resolve(
              japanese: "検索中",
              simplifiedChinese: "正在搜索",
              english: "Searching"
            )
          )
          Spacer()
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(KaidoTheme.nightQuiet)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .accessibilityIdentifier("whole-shuto-place-search-progress")
      case .results, .unavailable:
        VStack(spacing: 0) {
          if placeSearch.state == .unavailable {
            HStack(spacing: 7) {
              Image(systemName: "wifi.exclamationmark")
              Text(
                copy.resolve(
                  japanese: "検索できません。接続を確認して再検索してください。",
                  simplifiedChinese: "搜索失败，请检查网络后重试。",
                  english: "Search unavailable. Check your connection and retry."
                )
              )
              Spacer()
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(KaidoTheme.signalAmber)
            .accessibilityIdentifier("whole-shuto-place-search-unavailable")
          }
          ForEach(placeSearch.suggestions) { suggestion in
            Button {
              selectPlanningSuggestion(suggestion)
            } label: {
              HStack(spacing: 10) {
                Image(
                  systemName: suggestion.isShutoFacility
                    ? "road.lanes" : "mappin"
                )
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(
                  suggestion.isShutoFacility
                    ? KaidoTheme.positionCyan : KaidoTheme.routeGreen
                )
                .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                  HStack(spacing: 6) {
                    Text(suggestion.title)
                      .font(.system(size: 13, weight: .bold))
                      .foregroundStyle(KaidoTheme.routeWhite)
                      .lineLimit(1)
                    if suggestion.isShutoFacility {
                      Text("EXPWY")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(KaidoTheme.night)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(KaidoTheme.positionCyan)
                        .clipShape(Capsule())
                    }
                  }
                  if !suggestion.subtitle.isEmpty {
                    Text(suggestion.subtitle)
                      .font(.system(size: 9, weight: .medium))
                      .foregroundStyle(KaidoTheme.nightQuiet)
                      .lineLimit(1)
                  }
                }
                Spacer()
                Image(systemName: "arrow.up.left")
                  .font(.system(size: 9, weight: .bold))
                  .foregroundStyle(KaidoTheme.roadGray)
              }
              .padding(.horizontal, 10)
              .frame(height: 46)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
              suggestion.subtitle.isEmpty
                ? suggestion.title
                : "\(suggestion.title), \(suggestion.subtitle)"
            )
            .accessibilityIdentifier(
              "whole-shuto-place-suggestion-\(suggestion.id)"
            )

            if suggestion.id != placeSearch.suggestions.last?.id {
              Divider()
                .padding(.leading, 44)
            }
          }
        }
        .background(KaidoTheme.nightRaised.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
          RoundedRectangle(cornerRadius: 12)
            .stroke(KaidoTheme.nightDivider, lineWidth: 1)
        }
      case .empty:
        Text(copy.resolve(
          japanese: "見つかりません。別の名前や住所で検索してください。",
          simplifiedChinese: "未找到地点，请换个名称或地址。",
          english: "No places found. Try another name or address."))
          .font(.footnote)
          .foregroundStyle(KaidoTheme.nightQuiet)
          .accessibilityIdentifier("whole-shuto-place-search-empty")
      case .idle:
        EmptyView()
      }
    }
  }

  private var planningLocationButton: some View {
    Button {
      model.originQuery = ""
      if let snapshot = planningLocation.snapshot {
        showsManualOrigin = false
        model.selectCurrentOrigin(snapshot.coordinate)
      } else if planningLocation.state == .denied
        || planningLocation.state == .unavailable
      {
        showsManualOrigin = true
        showsDestinationComposer = true
        focusedPlanningField = .origin
      } else {
        showsManualOrigin = false
      }
      planningLocation.requestCurrentLocation()
    } label: {
      VStack(spacing: 3) {
        Image(systemName: planningLocationSymbol)
          .font(.system(size: 15, weight: .bold))
        Text(planningLocationShortLabel)
          .font(.system(size: 8, weight: .bold))
          .lineLimit(1)
      }
      .foregroundStyle(
        planningLocation.state == .measured
          ? KaidoTheme.routeWhite : KaidoTheme.positionCyan
      )
      .frame(width: 62, height: 52)
      .background(
        planningLocation.state == .measured
          ? KaidoTheme.positionCyan
          : KaidoTheme.nightRaised.opacity(0.94)
      )
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(KaidoTheme.positionCyan.opacity(0.7), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("whole-shuto-current-location")
    .accessibilityLabel(planningLocationLongLabel)
  }

  private func planRouteButton(title: String) -> some View {
    Button {
      beginRoutePlanning()
    } label: {
      HStack(spacing: 8) {
        if model.isPlanning || waitsForPlanningLocation {
          ProgressView()
            .tint(.white)
          Text(
            waitsForPlanningLocation
              ? copy.resolve(
                japanese: "現在地を確認中",
                simplifiedChinese: "正在定位",
                english: "LOCATING"
              )
              : copy.resolve(
                japanese: "ルートを検索中",
                simplifiedChinese: "正在查找路线",
                english: "FINDING ROUTES"
              )
          )
        } else {
          Text(title)
          Spacer()
          Image(systemName: "arrow.right")
        }
      }
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(KaidoTheme.routeWhite)
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity)
      .frame(height: 48)
      .background(KaidoTheme.routeGreen)
      .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    .buttonStyle(.plain)
    .disabled(model.isPlanning || waitsForPlanningLocation)
    .accessibilityIdentifier("whole-shuto-plan-route")
  }

  private var canSubmitRoutePlan: Bool {
    let hasDestination = model.hasSelectedDestinationPreview
    let hasRequiredManualOrigin =
      !(showsManualOrigin
        || planningLocation.state == .denied
        || planningLocation.state == .unavailable)
      || model.hasSelectedOriginPreview
    return hasDestination
      && hasRequiredManualOrigin
      && !model.isPlanning
      && !waitsForPlanningLocation
  }

  private func beginRoutePlanning() {
    guard canSubmitRoutePlan else { return }
    focusedPlanningField = nil
    placeSearch.dismissResults()

    guard model.usesCurrentLocationOrigin else {
      model.planJourney()
      return
    }
    if let snapshot = planningLocation.snapshot {
      model.selectCurrentOrigin(snapshot.coordinate)
      model.planJourney()
      return
    }
    if model.origin != nil {
      model.planJourney()
      return
    }

    waitsForPlanningLocation = true
    planningLocation.requestCurrentLocation()
    handlePlanningLocationUpdate()
  }

  private func handlePlanningLocationUpdate() {
    if let snapshot = planningLocation.snapshot,
      planningLocation.state == .measured
    {
      model.selectCurrentOrigin(snapshot.coordinate)
      model.refreshCircuitEntrances()
      if waitsForCustomRouteLocation {
        openCustomRouteEditor()
        return
      }
      if let pendingSavedRouteRecordID,
        let record = savedRoutes.record(id: pendingSavedRouteRecordID)
      {
        finishOpeningSavedRoute(record)
        return
      }
      if waitsForCircuitLocation {
        waitsForCircuitLocation = false
        model.startCircuitJourneyWhenPaired()
        return
      }
      guard waitsForPlanningLocation else { return }
      waitsForPlanningLocation = false
      model.planJourney()
      return
    }

    guard
      waitsForPlanningLocation || waitsForCircuitLocation
        || waitsForCustomRouteLocation
        || pendingSavedRouteRecordID != nil
    else {
      return
    }
    switch planningLocation.state {
    case .denied, .unavailable:
      if pendingSavedRouteRecordID != nil {
        pendingSavedRouteRecordID = nil
        savedRouteOpenErrorCode = "LOCATION_UNAVAILABLE"
      }
      waitsForPlanningLocation = false
      waitsForCircuitLocation = false
      waitsForCustomRouteLocation = false
      showsManualOrigin = true
      showsDestinationComposer = true
      focusedPlanningField = .origin
    case .idle, .permissionRequired, .locating, .measured, .stopped:
      break
    }
  }

  @ViewBuilder
  private var routeFailureBanner: some View {
    if let failureCode = model.failureCode {
      HStack(spacing: 7) {
        Image(systemName: "exclamationmark.triangle.fill")
        Text(failureMessage(failureCode))
        Spacer()
        if failureCode == "LOCATION_UNAVAILABLE" {
          Button(
            copy.resolve(
              japanese: "出発地を入力",
              simplifiedChinese: "输入出发地",
              english: "ENTER ORIGIN"
            )
          ) {
            showsManualOrigin = true
          }
          .font(.system(size: 10, weight: .black))
        }
      }
      .font(.system(size: 10, weight: .bold))
      .foregroundStyle(KaidoTheme.evidenceCoral)
    }
  }

  private func routeField(
    symbol: String,
    tint: Color,
    label: String,
    text: Binding<String>,
    prompt: String,
    accessibilityIdentifier: String,
    focus: WholeShutoPlanningField
  ) -> some View {
    HStack(spacing: 10) {
      ZStack {
        Circle()
          .fill(tint.opacity(0.18))
          .frame(width: 30, height: 30)
        Image(systemName: symbol)
          .font(.system(size: 11, weight: .black))
          .foregroundStyle(tint)
      }

      VStack(alignment: .leading, spacing: 1) {
        Text(label)
          .font(.system(size: 8, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.nightQuiet)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        TextField(prompt, text: text)
          .accessibilityIdentifier(accessibilityIdentifier)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(KaidoTheme.routeWhite)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .textInputAutocapitalization(.never)
          .focused($focusedPlanningField, equals: focus)
          .submitLabel(.search)
          .onSubmit { searchPlanningPlaces(for: focus) }
      }
      Button(copy.resolve(japanese: "検索", simplifiedChinese: "搜索", english: "Search")) {
        searchPlanningPlaces(for: focus)
      }
      .font(.system(size: 13, weight: .bold))
      .frame(minWidth: 44, minHeight: 44)
      .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityIdentifier(focus == .destination
        ? "whole-shuto-destination-search-submit" : "whole-shuto-origin-search-submit")
    }
    .frame(height: 52)
  }

  private var routeReview: some View {
    VStack(spacing: 11) {
      routeReviewSummary
        .foregroundStyle(KaidoTheme.routeWhite)

      if model.isCircuitRouteSelected {
        Button {
          model.prepareCustomRouteDraft()
          showsRouteCustomization = true
        } label: {
          Label(copy.resolve(japanese: "入口と出口を変更", simplifiedChinese: "修改入口与出口", english: "Change entrance and exit"),
            systemImage: "slider.horizontal.3")
          .font(.subheadline.weight(.semibold))
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier("whole-shuto-route-selection")
      } else {
        routeSelection
      }

      routeBoundaryPair

      Button { showsJourneyEnding = true } label: {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text(copy.resolve(japanese: "行程の終点", simplifiedChinese: "行程结束于", english: "Journey ends at"))
              .font(.caption)
            Text(model.journeyEnding.label(for: languageSettings.interfaceLocale))
              .font(.subheadline.weight(.semibold))
          }
          Spacer()
          Image(systemName: "chevron.right")
        }
        .frame(minHeight: 44)
      }
      .accessibilityIdentifier("whole-shuto-edit-ending")

      routeReviewAction
    }
    .padding(.horizontal, 16)
    .padding(.top, 4)
    .padding(.bottom, 12)
  }

  @ViewBuilder
  private var routeReviewSummary: some View {
    if usesExpandedTextLayout {
      stackedRouteReviewSummary
    } else {
      HStack(alignment: .top, spacing: 12) {
        routeReviewPrimarySummary
        Spacer(minLength: 12)
        routeReviewDistanceSummary
      }
    }
  }

  private var stackedRouteReviewSummary: some View {
    VStack(alignment: .leading, spacing: 8) {
      routeReviewPrimarySummary
      HStack {
        Spacer(minLength: 0)
        routeReviewDistanceSummary
      }
    }
  }

  private var routeReviewPrimarySummary: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(routeSummaryTitle)
        .font(.title3.weight(.black))
        .fontDesign(.rounded)
        .accessibilityIdentifier("whole-shuto-route-summary-title")
      Text(routeSummarySubtitle)
        .font(.caption.weight(.bold))
    }
    .fixedSize(horizontal: false, vertical: true)
    .layoutPriority(1)
  }

  private var routeReviewDistanceSummary: some View {
    VStack(alignment: .trailing, spacing: 1) {
      Text(
        copy.resolve(
          japanese: "高速",
          simplifiedChinese: "高速",
          english: "EXPRESSWAY"
        )
      )
      .font(.body.weight(.black))
      .fontDesign(.rounded)
      .foregroundStyle(KaidoTheme.nightQuiet)
      Text(distanceLabel(model.selectedRoute?.distanceMeters ?? 0))
        .font(.title2.weight(.black))
        .fontDesign(.rounded)
    }
    .fixedSize(horizontal: true, vertical: true)
  }

  private var routeBoundaryPair: some View {
    let layout =
      usesExpandedTextLayout
      ? AnyLayout(VStackLayout(spacing: 8))
      : AnyLayout(HStackLayout(spacing: 8))

    return layout {
      routeBoundary(
        title: model.selectedRoute?.entryFacility.nameJA ?? "—",
        detail: (model.selectedRoute?.entryFacility.entranceDirections ?? [])
          .joined(separator: " / "),
        label: copy.resolve(
          japanese: "入口",
          simplifiedChinese: "入口",
          english: "ENTRY"
        ),
        tint: KaidoTheme.positionCyan
      )
      Image(systemName: "arrow.right")
        .font(.system(size: 11, weight: .black))
        .foregroundStyle(KaidoTheme.roadGray)
        .rotationEffect(
          usesExpandedTextLayout ? .degrees(90) : .zero
        )
      routeBoundary(
        title: model.selectedRoute?.destinationNameJA ?? "—",
        detail: (model.selectedRoute?.exitFacility?.exitDirections ?? [])
          .joined(separator: " / "),
        label: copy.resolve(
          japanese: model.endsAtParkingArea ? "目的地" : "出口",
          simplifiedChinese: model.endsAtParkingArea ? "目的地" : "出口",
          english: model.endsAtParkingArea ? "DESTINATION" : "EXIT"
        ),
        tint: KaidoTheme.evidenceCoral
      )
    }
  }

  @ViewBuilder
  private var routeReviewAction: some View {
    if model.isUpdatingSurfaceRoute {
      HStack(spacing: 10) {
        ProgressView()
          .tint(KaidoTheme.routeGreen)
        Text(
          copy.resolve(
            japanese: "地上区間を確認中",
            simplifiedChinese: "正在确认地面接驳",
            english: "CONFIRMING SURFACE LEGS"
          )
        )
        .font(.caption.weight(.black))
        .fontDesign(.rounded)
        Spacer()
      }
      .foregroundStyle(KaidoTheme.routeWhite)
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity, minHeight: 48)
      .background(KaidoTheme.nightRaised.opacity(0.92))
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("whole-shuto-surface-route-status")
      .accessibilityValue("RESOLVING")
    } else if !model.isJourneyReadyForPreview {
      HStack(spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(KaidoTheme.signalAmber)
        VStack(alignment: .leading, spacing: 2) {
          Text(
            copy.resolve(
              japanese: "地上区間を確認できません",
              simplifiedChinese: "无法确认地面接驳",
              english: "SURFACE LEGS UNAVAILABLE"
            )
          )
          .font(.caption.weight(.black))
          .fontDesign(.rounded)
          Text(
            copy.resolve(
              japanese: "通信を確認して再試行してください",
              simplifiedChinese: "检查网络后重试",
              english: "Check the connection and try again"
            )
          )
          .font(.body.weight(.semibold))
          .foregroundStyle(KaidoTheme.nightQuiet)
        }
        Spacer()
        Button {
          model.retrySurfaceRoutes()
        } label: {
          Text(
            copy.resolve(
              japanese: "再試行",
              simplifiedChinese: "重试",
              english: "RETRY"
            )
          )
          .font(.caption.weight(.black))
          .fontDesign(.rounded)
          .foregroundStyle(KaidoTheme.routeGreen)
          .padding(.horizontal, 12)
          .frame(minHeight: 34)
          .background(KaidoTheme.routeGreen.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("whole-shuto-retry-surface-route")
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 54)
      .background(KaidoTheme.signalAmber.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .stroke(KaidoTheme.signalAmber.opacity(0.42), lineWidth: 1)
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("whole-shuto-surface-route-status")
      .accessibilityValue("UNAVAILABLE")
    } else {
      Button {
        showsJourneyReview = true
      } label: {
        HStack(spacing: 9) {
          Text(
            copy.resolve(
              japanese: "行程を確認",
              simplifiedChinese: "确认行程",
              english: "REVIEW JOURNEY"
            )
          )
          .font(.headline.weight(.black))
          .fontDesign(.rounded)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .layoutPriority(1)
          Spacer()
          Image(systemName: "arrow.right")
            .font(.system(size: 13, weight: .black))
        }
        .foregroundStyle(KaidoTheme.routeWhite)
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(KaidoTheme.routeGreen)
        .clipShape(RoundedRectangle(cornerRadius: 10))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("whole-shuto-review-journey")
    }
  }

  private var routeSelection: some View {
    GeometryReader { geometry in
      let visibleCardCount = usesExpandedTextLayout ? 1 : 2
      let occupiedSpacing = CGFloat(visibleCardCount - 1) * 7
      let cardWidth = max(
        1,
        (geometry.size.width - 2 - occupiedSpacing)
          / CGFloat(visibleCardCount)
      )
      ScrollViewReader { proxy in
        ScrollView(.horizontal) {
          HStack(spacing: 7) {
            if !model.recommendations.isEmpty {
              routeSelectionButton(at: 0, width: cardWidth)
                .id(routeSelectionScrollID(at: 0))
            }

            routeCustomizationButton(width: cardWidth)
              .id("whole-shuto-route-customization-choice")

            ForEach(
              model.recommendations.indices.dropFirst(),
              id: \.self
            ) { index in
              routeSelectionButton(at: index, width: cardWidth)
                .id(routeSelectionScrollID(at: index))
            }
          }
          .padding(.horizontal, 1)
          .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .onChange(of: model.selectedRecommendationIndex) { _, index in
          withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(
              routeSelectionScrollID(at: index),
              anchor: .center
            )
          }
        }
        .onChange(of: showsRouteCustomization) { _, isPresented in
          guard isPresented else { return }
          withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(
              "whole-shuto-route-customization-choice",
              anchor: .center
            )
          }
        }
        .onChange(of: model.isCustomRouteSelected) { _, isSelected in
          guard isSelected else { return }
          withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(
              "whole-shuto-route-customization-choice",
              anchor: .center
            )
          }
        }
        .accessibilityIdentifier("whole-shuto-route-selection")
      }
    }
    .frame(height: resolvedRouteSelectionCardHeight)
  }

  private var resolvedRouteSelectionCardHeight: CGFloat {
    routeSelectionCardHeight
      * (usesExpandedTextLayout ? 1.35 : 1)
  }

  private func routeSelectionScrollID(at index: Int) -> String {
    "whole-shuto-route-choice-\(index)"
  }

  private func routeCustomizationButton(width: CGFloat) -> some View {
    Button {
      model.prepareCustomRouteDraft()
      showsRouteCustomization = true
    } label: {
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text(
            copy.resolve(
              japanese: "カスタム",
              simplifiedChinese: "自定义",
              english: "CUSTOM"
            )
          )
          Spacer()
          if model.isCustomRouteSelected && model.isUpdatingSurfaceRoute {
            ProgressView()
              .controlSize(.mini)
              .tint(KaidoTheme.routeWhite)
          } else if model.isCustomRouteSelected {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 12, weight: .bold))
          } else {
            Image(systemName: "slider.horizontal.3")
              .font(.system(size: 12, weight: .bold))
          }
        }
        .font(.caption.weight(.black))
        Text(customRouteCardDetail)
          .font(.caption.weight(.bold))
          .fixedSize(horizontal: false, vertical: true)
        if let route = model.customRecommendation?.route {
          Text(routeBoundarySummary(route))
            .font(.body.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 4) {
            Image(
              systemName:
                model.customRouteChoiceMetrics == nil
                ? "point.topleft.down.to.point.bottomright.curvepath"
                : "clock"
            )
            .font(.system(size: 10, weight: .black))
            Text(
              routeChoiceComparisonLabel(
                metrics: model.customRouteChoiceMetrics,
                shutoDistanceMeters: route.distanceMeters
              )
            )
            .font(.body.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .foregroundStyle(
        model.isCustomRouteSelected
          ? KaidoTheme.routeWhite : KaidoTheme.routeWhite
      )
      .padding(.horizontal, 12)
      .frame(
        width: width,
        height: resolvedRouteSelectionCardHeight,
        alignment: .leading
      )
      .background(
        model.isCustomRouteSelected
          ? KaidoTheme.routeGreenDeep : KaidoTheme.nightRaised
      )
      .clipShape(RoundedRectangle(cornerRadius: 9))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("whole-shuto-customize-route")
    .accessibilityAddTraits(
      model.isCustomRouteSelected ? .isSelected : []
    )
    .accessibilityValue(customRouteCardAccessibilityValue)
  }

  private func routeSelectionButton(
    at index: Int,
    width: CGFloat
  ) -> some View {
    Button {
      showsRouteCustomization = false
      model.selectRecommendation(at: index)
    } label: {
      let route = model.recommendations[index].route
      let metrics = model.routeChoiceMetrics(at: index)
      let isSelected =
        index == model.selectedRecommendationIndex
        && !model.isCustomRouteSelected
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 5) {
          Text(recommendationLabel(at: index))
          Spacer()
          if isSelected && model.isUpdatingSurfaceRoute {
            ProgressView()
              .controlSize(.mini)
              .tint(KaidoTheme.routeWhite)
          } else if isSelected {
            Image(systemName: "checkmark.circle.fill")
          }
        }
        .font(.caption.weight(.black))
        Text(
          route.routeIDsInOrder
            .map { routeDisplayLabel($0, in: model.database) }
            .joined(separator: " → ")
        )
        .font(.subheadline.weight(.black))
        .fontDesign(.rounded)
        .fixedSize(horizontal: false, vertical: true)
        Text(routeBoundarySummary(route))
          .font(.body.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 4) {
          Image(
            systemName:
              metrics == nil
              ? "point.topleft.down.to.point.bottomright.curvepath"
              : "clock"
          )
          .font(.system(size: 10, weight: .black))
          Text(
            routeChoiceComparisonLabel(
              metrics: metrics,
              shutoDistanceMeters: route.distanceMeters
            )
          )
          .font(.body.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .foregroundStyle(
        isSelected
          ? KaidoTheme.routeWhite
          : KaidoTheme.routeWhite
      )
      .padding(.horizontal, 12)
      .frame(
        width: width,
        height: resolvedRouteSelectionCardHeight,
        alignment: .leading
      )
      .background(
        isSelected
          ? KaidoTheme.routeGreenDeep
          : KaidoTheme.nightRaised
      )
      .clipShape(RoundedRectangle(cornerRadius: 9))
    }
    .buttonStyle(.plain)
    .accessibilityRepresentation {
      Button {
        showsRouteCustomization = false
        model.selectRecommendation(at: index)
      } label: {
        Text(recommendationLabel(at: index))
      }
      .accessibilityIdentifier("whole-shuto-route-option-\(index)")
      .accessibilityAddTraits(
        index == model.selectedRecommendationIndex
          && !model.isCustomRouteSelected
          ? .isSelected : []
      )
      .accessibilityValue(
        model.isUpdatingSurfaceRoute
          && index == model.selectedRecommendationIndex
          ? routeSelectionAccessibilityValue(at: index)
            + "; "
            + copy.resolve(
              japanese: "ルートを確認中",
              simplifiedChinese: "正在确认路线",
              english: "CONFIRMING ROUTE"
            )
          : routeSelectionAccessibilityValue(at: index)
      )
    }
  }

  private func routeBoundary(
    title: String,
    detail: String,
    label: String,
    tint: Color
  ) -> some View {
    HStack(spacing: 8) {
      Circle()
        .fill(tint)
        .frame(width: 9, height: 9)
      VStack(alignment: .leading, spacing: 1) {
        Text("\(label) · \(title)")
          .font(.caption.weight(.black))
          .fontDesign(.rounded)
          .fixedSize(horizontal: false, vertical: true)
        Text(
          detail.isEmpty
            ? copy.resolve(
              japanese: "進行方向はルートで確定",
              simplifiedChinese: "方向由路线确定",
              english: "Direction fixed by route"
            )
            : detail
        )
        .font(.body.weight(.semibold))
        .foregroundStyle(KaidoTheme.nightQuiet)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .foregroundStyle(KaidoTheme.routeWhite)
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
    .background(KaidoTheme.nightRaised)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private var drivingDock: some View {
    VStack(spacing: 8) {
      routeJoinBanner
      lapChangeControls
      drivingDockControls
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(KaidoTheme.night.opacity(0.96))
    .overlay(alignment: .top) {
      Rectangle()
        .fill(KaidoTheme.nightDivider)
        .frame(height: 1)
    }
  }

  /// A drive that starts on the expressway never meets the reviewed entry
  /// ramp, so the ramp match alone would wait forever. The driver settles what
  /// the sensors cannot; the matcher still has to place the car itself.
  @ViewBuilder private var routeJoinBanner: some View {
    switch model.routeJoinState {
    case .unavailable:
      EmptyView()
    case .offered, .unresolved:
      Button {
        Task { _ = await model.declareAlreadyOnRoute() }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "arrow.turn.up.right")
            .font(.system(size: 13, weight: .black))
          Text(
            model.routeJoinState == .unresolved
              ? copy.resolve(
                japanese: "位置を確認できません · 再試行",
                simplifiedChinese: "未能确认位置 · 重试",
                english: "POSITION UNCONFIRMED · RETRY"
              )
              : copy.resolve(
                japanese: "すでに高速道路を走行中",
                simplifiedChinese: "我已在高速上",
                english: "ALREADY ON THE EXPRESSWAY"
              )
          )
          .font(.system(size: 12, weight: .black, design: .rounded))
          Spacer(minLength: 0)
        }
        .foregroundStyle(KaidoTheme.night)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(KaidoTheme.confirmedGreen)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("whole-shuto-route-join")
      .accessibilityValue(model.routeJoinState.rawValue)
    case .resolving:
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
          .tint(KaidoTheme.confirmedGreen)
        Text(
          copy.resolve(
            japanese: "位置を確認中",
            simplifiedChinese: "正在确认位置",
            english: "CONFIRMING POSITION"
          )
        )
        .font(.system(size: 12, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.confirmedGreen)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .background(KaidoTheme.nightRaised)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("whole-shuto-route-join")
      .accessibilityValue(model.routeJoinState.rawValue)
    }
  }

  /// The finished drive's own numbers, and each lap it actually closed.
  @ViewBuilder private var arrivalDriveRecord: some View {
    if model.showsDriveRecord,
      model.driveRecord.hasSpeedRecord || !model.driveRecord.completedLaps.isEmpty
    {
      VStack(alignment: .leading, spacing: 5) {
        if let summary = driveRecordSpeedSummary {
          Text(summary)
            .accessibilityIdentifier("whole-shuto-arrival-record-speed")
        }
        ForEach(model.driveRecord.completedLaps) { lap in
          HStack(spacing: 6) {
            Text(
              copy.resolve(
                japanese: "\(lap.lapNumber)周目",
                simplifiedChinese: "第\(lap.lapNumber)圈",
                english: "LAP \(lap.lapNumber)"
              )
            )
            Spacer(minLength: 8)
            Text(lapDuration(lap.durationMilliseconds))
              .foregroundStyle(KaidoTheme.routeWhite)
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("whole-shuto-arrival-lap-\(lap.lapNumber)")
        }
      }
      .font(.system(size: 11, weight: .bold, design: .rounded))
      .monospacedDigit()
      .foregroundStyle(KaidoTheme.nightQuiet)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityIdentifier("whole-shuto-arrival-drive-record")
    }
  }

  /// Changing the lap count from behind the wheel.
  ///
  /// Dropping one moves the drive a whole lap forward inside the plan it is
  /// already running. Adding one cannot: a lap the plan does not contain has
  /// to be planned, released, and joined, so the drive keeps running while
  /// that is built.
  @ViewBuilder private var lapChangeControls: some View {
    if model.isLiveDrive,
      model.phase == .expressway,
      model.selectedCircuit?.kind == .loop
    {
      HStack(spacing: 8) {
        Text(
          copy.resolve(
            japanese: "この周回の後",
            simplifiedChinese: "本圈之后",
            english: "AFTER THIS LAP"
          )
        )
        .font(.system(size: 10, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.nightQuiet)

        Text(copy.resolve(
          japanese: "\(model.remainingWholeLapsAhead) 周",
          simplifiedChinese: "\(model.remainingWholeLapsAhead) 圈",
          english: "\(model.remainingWholeLapsAhead) laps"
        ))
          .font(.system(size: 13, weight: .black, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(KaidoTheme.routeWhite)
          .accessibilityIdentifier("whole-shuto-driving-laps")
          .accessibilityValue("\(model.remainingWholeLapsAhead)")

        Spacer(minLength: 0)

        if model.isChangingLaps {
          ProgressView()
            .controlSize(.small)
            .tint(KaidoTheme.confirmedGreen)
            .accessibilityIdentifier("whole-shuto-lap-change-progress")
        } else {
          Button {
            Task { _ = await model.dropOneLap() }
          } label: {
            Text(
              copy.resolve(
                japanese: "1周減らす",
                simplifiedChinese: "少跑一圈",
                english: "ONE FEWER"
              )
            )
            .font(.system(size: 11, weight: .black, design: .rounded))
            .padding(.horizontal, 10)
            .frame(height: 44)
            .foregroundStyle(KaidoTheme.routeWhite)
            .background(KaidoTheme.nightRaised)
            .clipShape(Capsule())
          }
          .buttonStyle(.plain)
          .disabled(model.remainingWholeLapsAhead < 1)
          .opacity(model.remainingWholeLapsAhead < 1 ? 0.4 : 1)
          .accessibilityIdentifier("whole-shuto-drop-lap")

          Button {
            Task { _ = await model.addOneLap() }
          } label: {
            Text(
              copy.resolve(
                japanese: "1周増やす",
                simplifiedChinese: "多跑一圈",
                english: "ONE MORE"
              )
            )
            .font(.system(size: 11, weight: .black, design: .rounded))
            .padding(.horizontal, 10)
            .frame(height: 44)
            .foregroundStyle(KaidoTheme.night)
            .background(KaidoTheme.confirmedGreen)
            .clipShape(Capsule())
          }
          .buttonStyle(.plain)
          .disabled(
            model.circuitLaps
              >= ShutoCircuitDefinition.loopLapRange.upperBound
          )
          .opacity(
            model.circuitLaps
              >= ShutoCircuitDefinition.loopLapRange.upperBound ? 0.4 : 1
          )
          .accessibilityIdentifier("whole-shuto-add-lap")
        }
      }
      .accessibilityIdentifier("whole-shuto-driving-lap-controls")
    }
  }

  /// The drive's own numbers, on the expressway leg where they mean anything.
  /// A record, not a target: no goal, no comparison, no encouragement.
  @ViewBuilder private var driveRecordStrip: some View {
    if model.showsDriveRecord,
      model.phase == .expressway,
      model.driveRecord.hasSpeedRecord || model.driveRecord.hasLapRecord
    {
      HStack(spacing: 8) {
        if let summary = driveRecordSpeedSummary {
          Text(summary)
            .accessibilityIdentifier("whole-shuto-drive-record-speed")
        }
        if let lap = driveRecordLapSummary {
          if driveRecordSpeedSummary != nil {
            Text("·").foregroundStyle(KaidoTheme.nightDivider)
          }
          Text(lap)
            .accessibilityIdentifier("whole-shuto-drive-record-lap")
        }
        Spacer(minLength: 0)
      }
      .font(.system(size: 11, weight: .bold, design: .rounded))
      .monospacedDigit()
      .foregroundStyle(KaidoTheme.nightQuiet)
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("whole-shuto-drive-record")
    }
  }

  private var driveRecordSpeedSummary: String? {
    let record = model.driveRecord
    guard let average = record.averageSpeedMetersPerSecond,
      let maximum = record.maximumSpeedMetersPerSecond,
      let minimum = record.minimumSpeedMetersPerSecond
    else {
      return nil
    }
    return copy.resolve(
      japanese: "平均 \(kilometersPerHour(average))"
        + " · 最高 \(kilometersPerHour(maximum))"
        + " · 最低 \(kilometersPerHour(minimum)) km/h",
      simplifiedChinese: "平均 \(kilometersPerHour(average))"
        + " · 最高 \(kilometersPerHour(maximum))"
        + " · 最低 \(kilometersPerHour(minimum)) km/h",
      english: "AVG \(kilometersPerHour(average))"
        + " · MAX \(kilometersPerHour(maximum))"
        + " · MIN \(kilometersPerHour(minimum)) KM/H"
    )
  }

  private var driveRecordLapSummary: String? {
    let record = model.driveRecord
    if let lastLap = record.completedLaps.last {
      return copy.resolve(
        japanese: "\(lastLap.lapNumber)周目 \(lapDuration(lastLap.durationMilliseconds))",
        simplifiedChinese: "第\(lastLap.lapNumber)圈 \(lapDuration(lastLap.durationMilliseconds))",
        english: "LAP \(lastLap.lapNumber) \(lapDuration(lastLap.durationMilliseconds))"
      )
    }
    guard let lapNumber = record.currentLapNumber else { return nil }
    return copy.resolve(
      japanese: "\(lapNumber)周目",
      simplifiedChinese: "第\(lapNumber)圈",
      english: "LAP \(lapNumber)"
    )
  }

  private func kilometersPerHour(_ metersPerSecond: Double) -> String {
    "\(Int((metersPerSecond * 3.6).rounded()))"
  }

  private func lapDuration(_ milliseconds: Int) -> String {
    let totalSeconds = max(0, milliseconds / 1_000)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
  }

  private var drivingDockControls: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 6) {
          Circle()
            .fill(positionStatusColor)
            .frame(width: 7, height: 7)
          Text(positionStatusLabel)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(positionStatusColor)
            .accessibilityIdentifier("whole-shuto-position-state")
            .accessibilityValue(
              model.isLiveDrive
                ? model.liveLocationState.rawValue
                : model.positionState.rawValue
            )
        }

        HStack(spacing: 6) {
          Text(remainingReferenceTimeLabel)
            .font(.system(size: 19, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)
            .accessibilityIdentifier(
              "whole-shuto-journey-remaining-time"
            )
          Text("·")
            .foregroundStyle(KaidoTheme.nightQuiet)
          Text(journeyRemainingLabel)
            .accessibilityIdentifier("whole-shuto-journey-remaining")
        }
        .font(.system(size: 11, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.confirmedGreen)
        .lineLimit(1)
        .minimumScaleFactor(0.72)

        journeyProgressRail

        Text(drivingBoundaryLabel)
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(KaidoTheme.nightQuiet)
          .lineLimit(1)

        driveRecordStrip
      }

      Spacer(minLength: 4)

      if model.canFinishLiveExpressway {
        Button {
          Task { _ = await model.finishLiveExpressway() }
        } label: {
          Image(systemName: "rectangle.portrait.and.arrow.right")
            .font(.system(size: 16, weight: .black))
            .frame(width: 48, height: 48)
        }
        .buttonStyle(WholeShutoCircleButtonStyle(isDriving: true))
        .accessibilityLabel(
          copy.resolve(
            japanese: "高速区間を完了",
            simplifiedChinese: "完成高速路段",
            english: "Finish expressway section"
          )
        )
        .accessibilityIdentifier("whole-shuto-finish-expressway")
      }

      if model.isLiveDrive, model.isPlaying {
        Button {
          Task { _ = await model.restLiveJourney() }
        } label: {
          Image(systemName: "pause.fill")
            .font(.system(size: 15, weight: .black))
            .frame(width: 48, height: 48)
        }
        .buttonStyle(WholeShutoCircleButtonStyle(isDriving: true))
        .accessibilityLabel(
          copy.resolve(
            japanese: "休憩する",
            simplifiedChinese: "休息",
            english: "Rest"
          )
        )
        .accessibilityHint(
          copy.resolve(
            japanese: "案内と位置情報を一時停止し、あとで再開できます",
            simplifiedChinese: "暂停导航和定位，之后可继续",
            english: "Pauses guidance and location until you resume"
          )
        )
        .accessibilityIdentifier("whole-shuto-rest-live-drive")
      }

      // Stepping belongs to the preview only; a live drive follows the
      // vehicle and cannot be advanced by hand.
      if !model.isLiveDrive {
      Button {
        model.advanceSimulation()
      } label: {
        Image(systemName: "forward.end.fill")
          .font(.system(size: 13, weight: .black))
          .frame(width: 42, height: 42)
      }
      .buttonStyle(WholeShutoCircleButtonStyle(isDriving: true))
      .accessibilityLabel(
        copy.resolve(
          japanese: "一段階進む",
          simplifiedChinese: "前进一步",
          english: "Advance one step"
        )
      )
      .accessibilityIdentifier("whole-shuto-preview-step")

      Button {
        Task {
          if model.isPlaying {
            await model.pausePlayback()
          } else {
            model.resumePlayback()
          }
        }
      } label: {
        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 15, weight: .black))
          .frame(width: 48, height: 48)
          .foregroundStyle(KaidoTheme.night)
          .background(KaidoTheme.confirmedGreen)
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        model.isPlaying
          ? copy.resolve(
            japanese: "プレビューを一時停止",
            simplifiedChinese: "暂停预演",
            english: "Pause preview"
          )
          : copy.resolve(
            japanese: "プレビューを再開",
            simplifiedChinese: "继续预演",
            english: "Resume preview"
          )
      )
      .accessibilityIdentifier("whole-shuto-preview-playback")
      .accessibilityValue(model.isPlaying ? "PLAYING" : "PAUSED")
      }
    }
  }

  private var journeyProgressRail: some View {
    GeometryReader { geometry in
      let progress = model.journeyProgressFraction
      let width = max(0, geometry.size.width)
      let completedWidth = width * progress

      ZStack(alignment: .leading) {
        Capsule()
          .fill(KaidoTheme.nightDivider)
          .frame(height: 4)
        Capsule()
          .fill(KaidoTheme.confirmedGreen)
          .frame(width: completedWidth, height: 4)
        Circle()
          .fill(KaidoTheme.routeWhite)
          .frame(width: 8, height: 8)
          .overlay {
            Circle()
              .stroke(KaidoTheme.confirmedGreen, lineWidth: 2)
          }
          .offset(x: min(max(0, completedWidth - 4), max(0, width - 8)))
      }
      .frame(height: 8)
    }
    .frame(height: 8)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      copy.resolve(
        japanese: "全行程の進捗",
        simplifiedChinese: "全程进度",
        english: "Journey progress"
      )
    )
    .accessibilityIdentifier("whole-shuto-journey-progress")
    .accessibilityValue(
      "\(Int((model.journeyProgressFraction * 100).rounded()))%"
    )
  }

  private var arrivalDock: some View {
    VStack(spacing: 13) {
      HStack(spacing: 12) {
        ZStack {
          Circle()
            .fill(KaidoTheme.confirmedGreen)
            .frame(width: 46, height: 46)
          Image(systemName: "checkmark")
            .font(.system(size: 19, weight: .black))
            .foregroundStyle(KaidoTheme.night)
        }

        VStack(alignment: .leading, spacing: 2) {
          Text(
            arrivalTitle
          )
          .font(.system(size: 9, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.confirmedGreen)
          Text(
            model.destination?.title
              ?? copy.resolve(
                japanese: "目的地",
                simplifiedChinese: "目的地",
                english: "Destination"
              )
          )
          .font(.system(size: 22, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .accessibilityIdentifier("whole-shuto-arrival-destination")
        }

        Spacer(minLength: 6)

        Text(
          distanceLabel(model.plannedJourneyDistanceMeters ?? 0)
        )
        .font(.system(size: 16, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)
        .accessibilityLabel(
          copy.resolve(
            japanese: "全行程",
            simplifiedChinese: "完整行程",
            english: "Full journey"
          )
        )
        .accessibilityIdentifier("whole-shuto-arrival-distance")
      }

      HStack(spacing: 8) {
        Image(systemName: "arrow.up.right")
          .font(.system(size: 9, weight: .black))
          .foregroundStyle(KaidoTheme.positionCyan)
        Text(drivingBoundaryLabel)
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(KaidoTheme.nightQuiet)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        Spacer()
      }

      if model.entryIsUnconfirmed {
        arrivalEntryDeclaration
      }
      arrivalDriveRecord
      if model.showsDriveRecord, model.driveRecord.hasRecordedIntervals {
        Button(copy.resolve(japanese: "走行履歴を見る", simplifiedChinese: "查看行程记录", english: "View drive history")) {
          showsDriveHistory = true
        }
        .frame(minHeight: 44)
      }

      Button {
        model.reset()
      } label: {
        Text(
          copy.resolve(
            japanese: "完了",
            simplifiedChinese: "完成",
            english: "Done"
          )
        )
        .font(.system(size: 13, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.night)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(KaidoTheme.confirmedGreen)
        .clipShape(RoundedRectangle(cornerRadius: 10))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("whole-shuto-finish-journey")
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 12)
    .background(KaidoTheme.night.opacity(0.97))
    .overlay(alignment: .top) {
      Rectangle()
        .fill(KaidoTheme.nightDivider)
        .frame(height: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("whole-shuto-arrival-dock")
  }

  /// After a declared join the drive knows where it was placed, not where
  /// it entered. Parked at the end, the driver can name the entrance from
  /// the ones the plan passed before the join; the toll and the drive record
  /// follow, and nothing is assumed until then.
  private var arrivalEntryDeclaration: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(
        copy.resolve(
          japanese: "どの入口から入りましたか？",
          simplifiedChinese: "这次从哪个入口进入的？",
          english: "Which entrance did you use?"
        )
      )
      .font(.system(size: 11, weight: .black, design: .rounded))
      .foregroundStyle(KaidoTheme.signalAmber)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(model.declarableEntryCandidates) { facility in
            Button {
              model.declareEntry(facilityID: facility.facilityID)
            } label: {
              HStack(spacing: 5) {
                Text(shieldLabel(facility.routeID))
                  .font(.system(size: 9, weight: .black, design: .rounded))
                  .foregroundStyle(KaidoTheme.night)
                  .padding(.horizontal, 5)
                  .frame(height: 16)
                  .background(KaidoTheme.routeGreen)
                  .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(facility.nameJA)
                  .font(.system(size: 12, weight: .bold))
                  .foregroundStyle(KaidoTheme.routeWhite)
              }
              .padding(.horizontal, 12)
              .frame(minHeight: 44)
              .background(KaidoTheme.nightRaised)
              .clipShape(RoundedRectangle(cornerRadius: 10))
              .overlay {
                RoundedRectangle(cornerRadius: 10)
                  .stroke(KaidoTheme.nightDivider, lineWidth: 1)
              }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(
              "whole-shuto-declare-entry-\(facility.facilityID)"
            )
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("whole-shuto-entry-declaration")
  }

  private var speechControls: some View {
    Menu {
      Picker(copy.resolve(japanese: "案内", simplifiedChinese: "播报方式", english: "Guidance"), selection: Binding(
        get: { model.speechMode }, set: { model.setSpeechMode($0) }
      )) {
        ForEach(GuidanceSpeechMode.allCases, id: \.self) { mode in
          Text(mode.title(in: languageSettings.interfaceLocale)).tag(mode)
        }
      }
      Button {
        model.repeatGuidance()
      } label: {
        Label(copy.resolve(japanese: "もう一度聞く", simplifiedChinese: "重听当前指令", english: "Repeat current direction"),
          systemImage: "arrow.counterclockwise")
      }
      .disabled(!model.canRepeatGuidance)
      .accessibilityIdentifier("whole-shuto-repeat-guidance")
    } label: {
      Image(systemName: speechStatusSymbol)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(speechStatusIsBlocked ? KaidoTheme.signalAmber : KaidoTheme.routeWhite)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .accessibilityIdentifier("whole-shuto-guidance-speech")
    .accessibilityLabel(copy.resolve(japanese: "音声案内", simplifiedChinese: "导航语音", english: "Guidance voice"))
    .accessibilityValue(model.speechMode.title(in: languageSettings.interfaceLocale) + " · " + speechStatusLabel)
  }

  private var instructionBanner: some View {
    HStack(spacing: 13) {
      ZStack {
        RoundedRectangle(cornerRadius: 11)
          .fill(KaidoTheme.routeGreen)
          .frame(width: 56, height: 70)
        Image(systemName: instructionSymbol)
          .font(.system(size: 25, weight: .black))
          .foregroundStyle(KaidoTheme.routeWhite)
          .accessibilityIdentifier("whole-shuto-guidance-maneuver")
          .accessibilityLabel(instructionTitle)
      }

      VStack(alignment: .leading, spacing: 1) {
        Text(instructionKicker)
          .font(.system(size: 11, weight: .black, design: .rounded))
          .tracking(0.5)
          .foregroundStyle(KaidoTheme.confirmedGreen)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .accessibilityIdentifier(
            nextJunctionDistanceLabel == nil
              ? "whole-shuto-guidance-kicker"
              : "whole-shuto-next-junction"
          )

        Text(primaryGuidanceDistanceLabel)
          .font(.system(size: 28, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .accessibilityIdentifier("whole-shuto-guidance-distance")

        Text(instructionTitle)
          .font(.system(size: 20, weight: .bold, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("whole-shuto-guidance-instruction")
        if model.hasCurrentGuidancePosition,
          let original = model.activeSurfaceInstruction,
          original != model.surfaceInstruction(in: languageSettings.interfaceLocale)
        {
          Text(original)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(KaidoTheme.nightQuiet)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("whole-shuto-source-instruction")
        }
      }

      Spacer()

      VStack(spacing: 8) {
        speechControls

        if let routeID = activeRouteShield {
          Text(shieldLabel(routeID))
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)
            .frame(minWidth: 42, minHeight: 32)
            .background(routeColor(routeID))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
      }
    }
    .padding(10)
    .background(KaidoTheme.night.opacity(0.94))
    .clipShape(RoundedRectangle(cornerRadius: 15))
    .overlay {
      RoundedRectangle(cornerRadius: 15)
        .stroke(KaidoTheme.nightDivider, lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("whole-shuto-guidance-card")
  }

  private var isDriving: Bool {
    ![.planning, .review].contains(model.phase)
  }

  private var isActiveNavigation: Bool {
    isDriving && model.phase != .completed
  }

  private func requestEndJourney() {
    guard !isPreparingEndJourneyConfirmation else { return }
    isPreparingEndJourneyConfirmation = true
    Task {
      let shouldResume = await model.pausePlayback()
      isPreparingEndJourneyConfirmation = false
      guard isActiveNavigation else {
        resumesAfterEndJourneyCancellation = false
        return
      }
      resumesAfterEndJourneyCancellation = shouldResume
      showsEndJourneyConfirmation = true
    }
  }

  private var endJourneyConfirmationTitle: String {
    model.isLiveDrive
      ? copy.resolve(
        japanese: "ナビを終了しますか？",
        simplifiedChinese: "结束本次导航？",
        english: "End navigation?"
      )
      : copy.resolve(
        japanese: "プレビューを終了しますか？",
        simplifiedChinese: "结束本次预演？",
        english: "End this preview?"
      )
  }

  private var continueJourneyActionLabel: String {
    model.isLiveDrive
      ? copy.resolve(
        japanese: "ナビを続ける",
        simplifiedChinese: "继续导航",
        english: "Continue navigation"
      )
      : copy.resolve(
        japanese: "続ける",
        simplifiedChinese: "继续预演",
        english: "Continue preview"
      )
  }

  private var endJourneyActionLabel: String {
    model.isLiveDrive
      ? copy.resolve(
        japanese: "ナビを終了",
        simplifiedChinese: "结束导航",
        english: "End navigation"
      )
      : copy.resolve(
        japanese: "プレビューを終了",
        simplifiedChinese: "结束预演",
        english: "End preview"
      )
  }

  private var endJourneyConfirmationMessage: String {
    model.isLiveDrive
      ? copy.resolve(
        japanese: "現在のナビを終了して、ルート検索に戻ります。",
        simplifiedChinese: "将结束当前导航并返回路线规划。",
        english: "The current navigation will end and route planning will reopen."
      )
      : copy.resolve(
        japanese: "現在の進行状況は破棄され、ルート検索に戻ります。",
        simplifiedChinese: "当前行程进度将被清除，并返回路线规划。",
        english:
          "Current journey progress will be cleared and route planning will reopen."
      )
  }

  private var arrivalTitle: String {
    model.isLiveDrive
      ? copy.resolve(
        japanese: "目的地に到着",
        simplifiedChinese: "已到达目的地",
        english: "ARRIVED AT DESTINATION"
      )
      : copy.resolve(
        japanese: "全行程プレビュー完了",
        simplifiedChinese: "完整行程预演完成",
        english: "FULL JOURNEY PREVIEW COMPLETE"
      )
  }

  private func resumeAfterEndJourneyCancellation() {
    defer { resumesAfterEndJourneyCancellation = false }
    guard
      resumesAfterEndJourneyCancellation,
      isActiveNavigation,
      !model.isPlaying
    else {
      return
    }
    model.resumePlayback()
  }

  private var routeSummaryTitle: String {
    guard let route = model.selectedRoute else {
      return copy.resolve(
        japanese: "ルート",
        simplifiedChinese: "路线",
        english: "ROUTE"
      )
    }
    // Circuit journeys repeat their member sequence every lap; the summary
    // names each component once while laps stay visible elsewhere.
    var routeIDs = route.routeIDsInOrder
    if model.isCircuitRouteSelected {
      var seen = Set<String>()
      routeIDs = routeIDs.filter { seen.insert($0).inserted }
    }
    return routeIDs
      .map { routeDisplayLabel($0, in: model.database) }
      .joined(separator: "  →  ")
  }

  private var routeSummarySubtitle: String {
    guard let route = model.selectedRoute else { return "" }
    return driveEntryLabel + " → " + routeDestinationName(route)
  }

  private func recommendationLabel(at index: Int) -> String {
    index == 0
      ? copy.resolve(
        japanese: "おすすめ",
        simplifiedChinese: "推荐",
        english: "RECOMMENDED"
      )
      : copy.resolve(
        japanese: "候補 \(index)",
        simplifiedChinese: "备选 \(index)",
        english: "OPTION \(index)"
      )
  }

  private func routeSelectionAccessibilityValue(at index: Int) -> String {
    guard model.recommendations.indices.contains(index) else {
      return ""
    }
    let route = model.recommendations[index].route
    return
      route.routeIDsInOrder.map(shieldLabel).joined(separator: ", ")
      + "; "
      + routeBoundarySummary(route)
      + "; "
      + routeChoiceComparisonLabel(
        metrics: model.routeChoiceMetrics(at: index),
        shutoDistanceMeters: route.distanceMeters
      )
  }

  private var customRouteCardDetail: String {
    guard let route = model.customRecommendation?.route else {
      return copy.resolve(
        japanese: "入口・出口を指定",
        simplifiedChinese: "指定入口和出口",
        english: "Choose entry and exit"
      )
    }
    return route.routeIDsInOrder
      .map(shieldLabel)
      .joined(separator: " · ")
  }

  private var customRouteCardAccessibilityValue: String {
    guard let route = model.customRecommendation?.route else {
      return copy.resolve(
        japanese: "未設定",
        simplifiedChinese: "尚未设置",
        english: "Not configured"
      )
    }
    return
      customRouteCardDetail
      + "; "
      + routeBoundarySummary(route)
      + "; "
      + routeChoiceComparisonLabel(
        metrics: model.customRouteChoiceMetrics,
        shutoDistanceMeters: route.distanceMeters
      )
  }

  private func routeDestinationName(_ route: ShutoPlannedRoute) -> String {
    route.destinationParkingArea == nil ? exitName(route.destinationNameJA) : route.destinationNameJA
  }

  private func routeBoundarySummary(_ route: ShutoPlannedRoute) -> String {
    "\(entryName(route.entryFacility.nameJA)) → "
      + routeDestinationName(route)
  }

  private func expresswayDistanceLabel(_ distanceMeters: Double) -> String {
    copy.resolve(
      japanese: "高速 \(distanceLabel(distanceMeters))",
      simplifiedChinese: "高速 \(distanceLabel(distanceMeters))",
      english: "EXPRESSWAY \(distanceLabel(distanceMeters))"
    )
  }

  private func routeChoiceComparisonLabel(
    metrics: WholeShutoRouteChoiceMetrics?,
    shutoDistanceMeters: Double
  ) -> String {
    guard let metrics else {
      return expresswayDistanceLabel(shutoDistanceMeters)
    }
    let minutes = max(
      1,
      Int(ceil(metrics.expectedTravelTimeSeconds / 60))
    )
    return copy.resolve(
      japanese:
        "全行程 約\(minutes)分 · "
        + distanceLabel(metrics.totalDistanceMeters),
      simplifiedChinese:
        "全程约\(minutes)分钟 · "
        + distanceLabel(metrics.totalDistanceMeters),
      english:
        "TOTAL ~\(minutes) MIN · "
        + distanceLabel(metrics.totalDistanceMeters)
    )
  }

  private var instructionSymbol: String {
    if !model.hasCurrentGuidancePosition { return "location.circle" }
    if model.isReroutingSurfaceRoute {
      return "arrow.triangle.2.circlepath"
    }
    return switch model.phase {
    case .surfaceAccess, .surfaceEgress:
      SurfaceManeuver.from(instruction: model.activeSurfaceInstruction ?? "").symbol
    case .entryTransition: "mappin.and.ellipse"
    case .expressway:
      switch displayedJunctionPrompt?.branchSide {
      case .left: "arrow.up.left"
      case .right: "arrow.up.right"
      case .straight, nil: "arrow.up"
      }
    case .exitTransition: "mappin.and.ellipse"
    case .completed: "checkmark"
    case .planning, .review: "map"
    }
  }

  private var instructionKicker: String {
    if !model.hasCurrentGuidancePosition {
      return copy.resolve(japanese: "現在地", simplifiedChinese: "当前位置", english: "CURRENT POSITION")
    }
    if model.isReroutingSurfaceRoute {
      return copy.resolve(
        japanese: "新しい経路を検索中",
        simplifiedChinese: "正在重新规划",
        english: "REROUTING"
      )
    }
    return switch model.phase {
    case .surfaceAccess:
      copy.resolve(
        japanese: "一般道",
        simplifiedChinese: "一般道路",
        english: "SURFACE ROAD"
      )
    case .entryTransition:
      copy.resolve(
        japanese: "高速道路へ進入",
        simplifiedChinese: "进入高速",
        english: "ENTER THE EXPRESSWAY"
      )
    case .expressway:
      if model.presentationProjection?.voice.stage == .prepare {
        copy.resolve(japanese: "この先の分岐", simplifiedChinese: "前方分岔", english: "UPCOMING JUNCTION")
      } else {
      // Only a reviewed branch is "approaching a junction"; a mainline
      // continuation keeps the ordinary upcoming-junction kicker.
      model.activeJunctionInsetPrompt == nil
        ? upcomingJunctionKicker
        : copy.resolve(
          japanese: "分岐に接近",
          simplifiedChinese: "接近分岔",
          english: "JUNCTION AHEAD"
        )
      }
    case .exitTransition:
      copy.resolve(
        japanese: "高速道路を退出",
        simplifiedChinese: "驶出高速",
        english: "EXIT THE EXPRESSWAY"
      )
    case .surfaceEgress:
      copy.resolve(
        japanese: "一般道",
        simplifiedChinese: "一般道路",
        english: "SURFACE ROAD"
      )
    case .completed:
      copy.resolve(
        japanese: "到着",
        simplifiedChinese: "已到达",
        english: "ARRIVED"
      )
    case .planning, .review: ""
    }
  }

  private var instructionTitle: String {
    if !model.hasCurrentGuidancePosition { return positionStatusLabel }
    guard let route = model.selectedRoute else { return "" }
    if model.isReroutingSurfaceRoute {
      return copy.resolve(
        japanese: "安全に進みながらお待ちください",
        simplifiedChinese: "请安全行驶，正在计算新路线",
        english: "Continue safely while a new route is calculated"
      )
    }
    switch model.phase {
    case .surfaceAccess:
      return model.surfaceInstruction(in: languageSettings.interfaceLocale)
        ?? copy.resolve(
          japanese: "\(entryName(route.entryFacility.nameJA))へ進む",
          simplifiedChinese: "前往 \(entryName(route.entryFacility.nameJA))",
          english: "Continue to \(entryName(route.entryFacility.nameJA))"
        )
    case .entryTransition:
      let routeLabel =
        route.routeIDsInOrder.first.map(shieldLabel)
        ?? copy.resolve(
          japanese: "高速道路",
          simplifiedChinese: "高速",
          english: "the expressway"
        )
      return copy.resolve(
        japanese: "\(route.entryFacility.nameJA)から \(routeLabel) へ",
        simplifiedChinese:
          "从 \(route.entryFacility.nameJA) 进入 \(routeLabel)",
        english: "Enter \(routeLabel) from \(route.entryFacility.nameJA)"
      )
    case .expressway:
      if let prompt = displayedJunctionPrompt {
        return prompt.localizedContent[languageSettings.interfaceLocale]?
          .displayText
          ?? "\(localizedJunctionName(prompt)): "
          + shieldLabel(prompt.outgoingRouteID)
      }
      let routeLabel =
        activeRouteShield.map(shieldLabel)
        ?? copy.resolve(
          japanese: "現在のルート",
          simplifiedChinese: "当前路线",
          english: "the current route"
        )
      return copy.resolve(
        japanese: "\(routeLabel)をそのまま進む",
        simplifiedChinese: "沿 \(routeLabel) 继续",
        english: "Continue on \(routeLabel)"
      )
    case .exitTransition:
      return copy.resolve(
        japanese: "\(routeDestinationName(route))から退出",
        simplifiedChinese: "从 \(routeDestinationName(route))驶出",
        english: "Leave from \(routeDestinationName(route))"
      )
    case .surfaceEgress:
      let destination =
        model.destination?.title
        ?? copy.resolve(
          japanese: "目的地",
          simplifiedChinese: "目的地",
          english: "destination"
        )
      return model.surfaceInstruction(in: languageSettings.interfaceLocale)
        ?? copy.resolve(
          japanese: "\(destination)へ進む",
          simplifiedChinese: "继续前往 \(destination)",
          english: "Continue to \(destination)"
        )
    case .completed:
      let destination =
        model.destination?.title
        ?? copy.resolve(
          japanese: "目的地",
          simplifiedChinese: "目的地",
          english: "destination"
        )
      return copy.resolve(
        japanese: "\(destination)に到着",
        simplifiedChinese: "已到达 \(destination)",
        english: "Arrived at \(destination)"
      )
    case .planning, .review:
      return ""
    }
  }

  private var displayedJunctionPrompt: WholeShutoJunctionPrompt? {
    guard model.phase == .expressway, model.hasCurrentGuidancePosition else { return nil }
    return model.activeJunctionPrompt
      ?? model.nextReviewedJunctionPrompt
  }

  private var activeRouteShield: String? {
    if let prompt = displayedJunctionPrompt {
      return prompt.outgoingRouteID
    }
    if model.phase == .expressway, let routeID = model.activeRouteID {
      return routeID
    }
    guard let route = model.selectedRoute else { return nil }
    let index = min(
      route.routeIDsInOrder.count - 1,
      max(
        0,
        Int(
          model.progressFraction
            * Double(max(route.routeIDsInOrder.count, 1))
        )
      )
    )
    guard route.routeIDsInOrder.indices.contains(index) else { return nil }
    return route.routeIDsInOrder[index]
  }

  private var positionStatusLabel: String {
    let prefix =
      model.restoredFromCheckpoint
      ? copy.resolve(
        japanese: "復元済み · ",
        simplifiedChinese: "已恢复 · ",
        english: "RESTORED · "
      )
      : ""
    switch model.positionState {
    case .resting:
      return prefix
        + copy.resolve(
          japanese: "休憩中 · 案内は待機",
          simplifiedChinese: "休息中 · 导航等待",
          english: "RESTING · GUIDANCE WAITING"
        )
    case .surfacePreview:
      if model.isLiveDrive {
        return prefix
          + copy.resolve(
            japanese: "一般道案内 · 現在地",
            simplifiedChinese: "普通道路导航 · 实时定位",
            english: "SURFACE NAVIGATION · LIVE POSITION"
          )
      }
      return prefix
        + copy.resolve(
          japanese: "一般道 · プレビュー",
          simplifiedChinese: "一般道路 · 预演",
          english: "SURFACE ROAD · PREVIEW"
        )
    case .surfaceRoutePending:
      return prefix
        + copy.resolve(
          japanese: "一般道 · ルート接続待ち",
          simplifiedChinese: "一般道路 · 等待接入路线",
          english: "SURFACE ROAD · WAITING TO JOIN ROUTE"
        )
    case .boundaryTransition:
      if model.isLiveDrive {
        return prefix
          + copy.resolve(
            japanese: "境界移行 · 現在地",
            simplifiedChinese: "边界转换 · 实时定位",
            english: "BOUNDARY TRANSITION · LIVE POSITION"
          )
      }
      return prefix
        + copy.resolve(
          japanese: "境界移行 · プレビュー",
          simplifiedChinese: "边界转换 · 预演",
          english: "BOUNDARY TRANSITION · PREVIEW"
        )
    case .networkPreview:
      if model.isLiveDrive {
        return prefix
          + copy.resolve(
            japanese: "案内中 · 現在地",
            simplifiedChinese: "导航中 · 实时定位",
            english: "NAVIGATING · LIVE POSITION"
          )
      }
      return prefix
        + copy.resolve(
          japanese: "ルート再生 · 模擬 \(simulationReplayParametersLabel)",
          simplifiedChinese: "路线回放 · 模拟 \(simulationReplayParametersLabel)",
          english: "ROUTE REPLAY · SIMULATED \(simulationReplayParametersLabel)"
        )
    case .networkDegraded:
      switch model.liveLocationState {
      case .awaitingAuthorization, .acquiring:
        return prefix
          + copy.resolve(
            japanese: "現在地を確認中",
            simplifiedChinese: "正在确认当前位置",
            english: "ACQUIRING CURRENT POSITION"
          )
      case .resting:
        return prefix
          + copy.resolve(
            japanese: "休憩中",
            simplifiedChinese: "休息中",
            english: "RESTING"
          )
      case .resumeRequired:
        return prefix
          + copy.resolve(
            japanese: "ナビ一時停止中",
            simplifiedChinese: "导航已暂停",
            english: "NAVIGATION PAUSED"
          )
      case .permissionDenied:
        return prefix
          + copy.resolve(
            japanese: "位置情報の許可なし",
            simplifiedChinese: "未获得定位权限",
            english: "LOCATION PERMISSION REQUIRED"
          )
      case .inactive, .failed:
        return prefix
          + copy.resolve(
            japanese: "位置情報を利用できません",
            simplifiedChinese: "定位暂不可用",
            english: "LOCATION UNAVAILABLE"
          )
      case .available, .degraded, .stale:
        return prefix
          + copy.resolve(
            japanese: "位置不確か · 自動再取得中",
            simplifiedChinese: "定位弱 · 正在自动重新定位",
            english: "WEAK POSITION · REACQUIRING"
          )
      }
    case .tunnelEstimated:
      if model.isLiveDrive {
        if model.liveLocationState == .available {
          return prefix
            + copy.resolve(
              japanese: "トンネル位置推定 · 低信頼",
              simplifiedChinese: "隧道位置估算 · 低置信",
              english: "TUNNEL ESTIMATE · LOW CONFIDENCE"
            )
        }
        return prefix
          + copy.resolve(
            japanese: "トンネル位置推定 · 位置情報を待機中",
            simplifiedChinese: "隧道位置估算 · 等待定位恢复",
            english: "TUNNEL ESTIMATE · AWAITING POSITION"
          )
      }
      return prefix
        + copy.resolve(
          japanese: "トンネル位置推定 · 模擬 \(simulationReplayParametersLabel)",
          simplifiedChinese: "隧道位置推算 · 模拟 \(simulationReplayParametersLabel)",
          english: "TUNNEL ESTIMATE · SIMULATED \(simulationReplayParametersLabel)"
        )
    case .routeInterrupted:
      if model.runtimeRecoveryStatus == .active {
        return prefix
          + copy.resolve(
            japanese: "ルート逸脱 · 前方で復帰",
            simplifiedChinese: "偏离路线 · 前方绕回汇合",
            english: "OFF ROUTE · REJOIN AHEAD"
          )
      }
      return prefix
        + copy.resolve(
          japanese: "ルート中断 · 復帰経路なし",
          simplifiedChinese: "路线中断 · 无绕回路线",
          english: "ROUTE INTERRUPTED · NO REJOIN PATH"
        )
    case .completed:
      return copy.resolve(
        japanese: "ルート完了",
        simplifiedChinese: "路线完成",
        english: "ROUTE COMPLETE"
      )
    case .unavailable:
      return ""
    }
  }

  private var speechStatusSymbol: String {
    if model.speechMode == .muted { return "speaker.slash.fill" }
    return switch model.speechStatus {
    case .scheduled, .speaking:
      "speaker.wave.2.fill"
    case .interrupted, .failed, .invalidProjection:
      "speaker.slash.fill"
    case .idle, .suppressed, .stopped:
      "speaker.fill"
    }
  }

  private var speechStatusLabel: String {
    if model.speechMode == .muted { return model.speechMode.title(in: languageSettings.interfaceLocale) }
    return switch model.speechStatus {
    case .idle:
      model.hasCompletedActiveGuidancePrompt
        ? copy.resolve(
          japanese: "案内済み",
          simplifiedChinese: "已播报",
          english: "GUIDANCE SPOKEN"
        )
        : copy.resolve(
          japanese: "審査済み案内を待機",
          simplifiedChinese: "等待已审核提示",
          english: "WAITING FOR REVIEWED GUIDANCE"
        )
    case .scheduled:
      copy.resolve(
        japanese: "案内を予約",
        simplifiedChinese: "已安排",
        english: "GUIDANCE SCHEDULED"
      )
    case .speaking:
      copy.resolve(
        japanese: "案内中",
        simplifiedChinese: "播报中",
        english: "SPEAKING"
      )
    case .suppressed(let reason):
      copy.resolve(
        japanese: "重複案内なし · \(reason.rawValue)",
        simplifiedChinese: "未重复播报 · \(reason.rawValue)",
        english: "NOT REPEATED · \(reason.rawValue)"
      )
    case .interrupted:
      copy.resolve(
        japanese: "システムにより中断",
        simplifiedChinese: "已被系统中断",
        english: "INTERRUPTED BY SYSTEM"
      )
    case .stopped:
      copy.resolve(
        japanese: "停止中",
        simplifiedChinese: "已暂停",
        english: "STOPPED"
      )
    case .failed(let code):
      copy.resolve(
        japanese: "利用不可 · \(code.rawValue)",
        simplifiedChinese: "不可用 · \(code.rawValue)",
        english: "UNAVAILABLE · \(code.rawValue)"
      )
    case .invalidProjection:
      copy.resolve(
        japanese: "案内IDが不一致",
        simplifiedChinese: "提示身份不一致",
        english: "GUIDANCE IDENTITY MISMATCH"
      )
    }
  }

  private var speechStatusIsBlocked: Bool {
    switch model.speechStatus {
    case .interrupted, .failed, .invalidProjection:
      true
    case .idle, .scheduled, .speaking, .suppressed, .stopped:
      false
    }
  }

  private var simulationReplayParametersLabel: String {
    let speedKilometersPerHour = Int(
      (WholeShutoProductModel.simulationReferenceSpeedMetersPerSecond * 3.6).rounded()
    )
    return "\(speedKilometersPerHour) km/h · "
      + "\(WholeShutoProductModel.simulationPlaybackSpeed.multiplier)×"
  }

  private var positionStatusColor: Color {
    switch model.positionState {
    case .completed:
      return KaidoTheme.confirmedGreen
    case .networkDegraded, .tunnelEstimated, .routeInterrupted:
      return KaidoTheme.signalAmber
    case .resting:
      return KaidoTheme.nightQuiet
    default:
      return KaidoTheme.positionCyan
    }
  }

  private var primaryGuidanceDistanceLabel: String {
    guard model.hasCurrentGuidancePosition else { return "—" }
    guard let route = model.selectedRoute else { return "—" }
    if model.isReroutingSurfaceRoute { return "…" }
    switch model.phase {
    case .surfaceAccess:
      return distanceLabel(
        model.activeSurfaceInstructionRemainingMeters
          ?? (model.accessRoute?.distanceMeters ?? 0)
          * (1 - model.progressFraction)
      )
    case .entryTransition:
      return copy.resolve(
        japanese: "まもなく",
        simplifiedChinese: "现在",
        english: "NOW"
      )
    case .expressway:
      if let distance = model.distanceToNextReviewedJunctionMeters {
        return distanceLabel(distance)
      }
      return distanceLabel(
        route.distanceMeters * (1 - model.progressFraction)
      )
    case .exitTransition:
      return copy.resolve(
        japanese: "まもなく",
        simplifiedChinese: "现在",
        english: "NOW"
      )
    case .surfaceEgress:
      return distanceLabel(
        model.activeSurfaceInstructionRemainingMeters
          ?? (model.egressRoute?.distanceMeters ?? 0)
          * (1 - model.progressFraction)
      )
    case .completed:
      return copy.resolve(
        japanese: "到着",
        simplifiedChinese: "到达",
        english: "ARRIVED"
      )
    case .planning, .review:
      return ""
    }
  }

  private var remainingReferenceTimeLabel: String {
    guard let seconds = model.remainingPreviewDurationSeconds else {
      return "—"
    }
    let minutes = max(0, Int(ceil(seconds / 60)))
    if minutes < 60 {
      return copy.resolve(
        japanese: "残り約 \(minutes) 分",
        simplifiedChinese: "约 \(minutes) 分钟",
        english: "ABOUT \(minutes) MIN"
      )
    }
    let hours = minutes / 60
    let remainder = minutes % 60
    return copy.resolve(
      japanese: "残り約 \(hours) 時間 \(remainder) 分",
      simplifiedChinese: "约 \(hours) 小时 \(remainder) 分钟",
      english: "ABOUT \(hours) HR \(remainder) MIN"
    )
  }

  private var drivingBoundaryLabel: String {
    guard let route = model.selectedRoute else { return "" }
    return driveEntryLabel + " → " + routeDestinationName(route)
  }

  /// The entrance the drive can vouch for; a declared join leaves it
  /// unconfirmed until the driver names it.
  private var driveEntryLabel: String {
    if let entry = model.driveEntryFacility {
      return entryName(entry.nameJA)
    }
    return copy.resolve(
      japanese: "入口未確認",
      simplifiedChinese: "入口未确认",
      english: "Entry unconfirmed"
    )
  }

  private var journeyRemainingLabel: String {
    let remaining = distanceLabel(
      model.remainingJourneyDistanceMeters ?? 0
    )
    return copy.resolve(
      japanese: "全行程残り \(remaining)",
      simplifiedChinese: "全程剩余 \(remaining)",
      english: "TOTAL \(remaining)"
    )
  }

  private var nextJunctionDistanceLabel: String? {
    guard model.hasCurrentGuidancePosition,
      let prompt = model.nextReviewedJunctionPrompt,
      let distance = model.distanceToNextReviewedJunctionMeters
    else {
      return nil
    }
    return "\(localizedJunctionName(prompt)) \(distanceLabel(distance))"
  }

  private var upcomingJunctionKicker: String {
    guard let nextJunctionDistanceLabel else {
      return copy.resolve(
        japanese: "そのまま進む",
        simplifiedChinese: "继续行驶",
        english: "CONTINUE"
      )
    }
    return copy.resolve(
      japanese: "次 · \(nextJunctionDistanceLabel)",
      simplifiedChinese: "下一处 · \(nextJunctionDistanceLabel)",
      english: "NEXT · \(nextJunctionDistanceLabel)"
    )
  }

  private var planningLocationSymbol: String {
    switch planningLocation.state {
    case .locating:
      "location.magnifyingglass"
    case .measured:
      "location.fill"
    case .stopped:
      "location"
    case .denied, .unavailable:
      "location.slash"
    case .idle, .permissionRequired:
      "location"
    }
  }

  private func updatePlanningPlaceSearch() {
    guard model.phase == .planning else { return }
    guard let focusedPlanningField = focusedPlanningField ?? planningSearchField else {
      placeSearch.dismissResults()
      return
    }
    if focusedPlanningField == .destination,
      model.hasSelectedDestinationPreview
    {
      placeSearch.dismissResults()
      return
    }
    if focusedPlanningField == .origin,
      model.hasSelectedOriginPreview
    {
      placeSearch.dismissResults()
      return
    }
    if focusedPlanningField == .origin,
      model.origin != nil,
      !model.usesCurrentLocationOrigin
    {
      model.clearOriginPreview()
    }
    if focusedPlanningField == .destination, model.destination != nil {
      model.clearDestinationPreview()
    }
    placeSearch.clearSelection()
    placeSearch.update(
      query:
        focusedPlanningField == .origin
        ? model.originQuery : model.destinationQuery,
      near:
        planningLocation.snapshot?.coordinate
        ?? model.origin?.coordinate
    )
  }

  private func searchPlanningPlaces(for field: WholeShutoPlanningField) {
    planningSearchField = field
    focusedPlanningField = nil
    if field == .destination { model.clearDestinationPreview() }
    else { model.clearOriginPreview() }
    Task {
      await placeSearch.search(
        query: field == .origin ? model.originQuery : model.destinationQuery,
        near: planningLocation.snapshot?.coordinate ?? model.origin?.coordinate)
    }
  }

  private func selectPlanningSuggestion(
    _ suggestion: WholeShutoPlaceSuggestion
  ) {
    guard let field = planningSearchField else { return }
    Task {
      do {
        let place = try await placeSearch.resolve(suggestion)
        if field == .origin {
          model.selectOriginPreview(place)
          showsManualOrigin = true
          model.refreshCircuitEntrances()
          focusedPlanningField = .destination
        } else {
          model.selectDestinationPreview(place)
          focusedPlanningField = nil
        }
      } catch {
        // The search controller exposes the failure beside the search action.
      }
    }
  }

  private var planningLocationShortLabel: String {
    switch planningLocation.state {
    case .locating:
      copy.resolve(
        japanese: "測位中",
        simplifiedChinese: "定位中",
        english: "Locating"
      )
    case .measured:
      copy.resolve(
        japanese: "現在地",
        simplifiedChinese: "当前位置",
        english: "Current"
      )
    case .stopped:
      copy.resolve(
        japanese: "停止中",
        simplifiedChinese: "已停止",
        english: "Stopped"
      )
    case .denied:
      copy.resolve(
        japanese: "許可なし",
        simplifiedChinese: "未授权",
        english: "Denied"
      )
    case .unavailable:
      copy.resolve(
        japanese: "取得不可",
        simplifiedChinese: "不可用",
        english: "Unavailable"
      )
    case .idle, .permissionRequired:
      copy.resolve(
        japanese: "現在地",
        simplifiedChinese: "当前位置",
        english: "Current"
      )
    }
  }

  private var planningLocationLongLabel: String {
    switch planningLocation.state {
    case .measured:
      copy.resolve(
        japanese: "現在地を使用中",
        simplifiedChinese: "正在使用真实当前位置",
        english: "Using current device location"
      )
    case .denied:
      copy.resolve(
        japanese: "位置情報は許可されていません",
        simplifiedChinese: "未获得位置权限",
        english: "Location permission is denied"
      )
    case .stopped:
      copy.resolve(
        japanese: "現在地の更新を停止中",
        simplifiedChinese: "当前位置更新已停止",
        english: "Current-location updates stopped"
      )
    default:
      copy.resolve(
        japanese: "現在地を使用",
        simplifiedChinese: "使用当前位置",
        english: "Use current location"
      )
    }
  }

  #if DEBUG
    private var planningLocationQualificationState: some View {
      Color.clear
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Planning location state")
        .accessibilityValue(planningLocationStateCode)
        .accessibilityIdentifier("whole-shuto-planning-location-state")
    }

    private var planningLocationStateCode: String {
      switch planningLocation.state {
      case .idle:
        "IDLE"
      case .permissionRequired:
        "AWAITING_AUTHORIZATION"
      case .locating:
        "RUNNING"
      case .measured:
        "MEASURED"
      case .stopped:
        "STOPPED"
      case .denied:
        "DENIED"
      case .unavailable:
        "UNAVAILABLE"
      }
    }
  #endif

  private func distanceLabel(_ meters: Double) -> String {
    if meters >= 1_000 {
      return String(format: "%.1f km", meters / 1_000)
    }
    return "\(Int(max(0, meters).rounded())) m"
  }

  private func failureMessage(_ code: String) -> String {
    switch code {
    case "DESTINATION_REQUIRED":
      return copy.resolve(
        japanese: "目的地を入力してください",
        simplifiedChinese: "请输入目的地",
        english: "Enter a destination"
      )
    case "LOCATION_UNAVAILABLE":
      return copy.resolve(
        japanese: "現在地を取得できません。出発地を入力できます",
        simplifiedChinese: "无法读取当前位置，也可输入出发地",
        english: "Current location unavailable; enter an origin"
      )
    case "NO_SHUTO_ROUTE":
      return copy.resolve(
        japanese: "進行方向が有効な高速ルートが見つかりません",
        simplifiedChinese: "未找到方向合法的高速路线",
        english: "No direction-valid expressway route found"
      )
    default:
      return copy.resolve(
        japanese: "場所またはルートを解決できません",
        simplifiedChinese: "地点或路线暂时无法解析",
        english: "Place or route could not be resolved"
      )
    }
  }

  private func checkpointIssueMessage(_ code: String) -> String {
    switch code {
    case "WHOLE_SHUTO_CHECKPOINT_LOAD_FAILED":
      return copy.resolve(
        japanese: "前回のルートを読み込めなかったため、再開データを消去しました",
        simplifiedChinese: "无法读取上次路线，已清除恢复数据",
        english: "The previous route could not be read; its resume data was cleared"
      )
    case "WHOLE_SHUTO_CHECKPOINT_SCHEMA_UNSUPPORTED":
      return copy.resolve(
        japanese: "前回のルートは未対応の保存形式だったため、消去しました",
        simplifiedChinese: "上次路线使用不支持的保存格式，已清除",
        english: "The previous route used an unsupported save format and was cleared"
      )
    case "WHOLE_SHUTO_CHECKPOINT_NETWORK_MISMATCH":
      return copy.resolve(
        japanese: "前回のルートは現在の地図と一致しないため、消去しました",
        simplifiedChinese: "上次路线与当前地图不匹配，已清除",
        english: "The previous route did not match this map and was cleared"
      )
    case "WHOLE_SHUTO_CHECKPOINT_SAVE_FAILED":
      return copy.resolve(
        japanese: "このルートの再開データを保存できませんでした",
        simplifiedChinese: "无法保存此路线的恢复数据",
        english: "Resume data for this route could not be saved"
      )
    case "WHOLE_SHUTO_CHECKPOINT_REMOVE_FAILED":
      return copy.resolve(
        japanese: "古い再開データを消去できませんでした。再起動後の再開を使用しないでください",
        simplifiedChinese: "无法清除旧恢复数据；请勿依赖重启后的恢复状态",
        english: "Old resume data could not be cleared; do not rely on it after restart"
      )
    default:
      return copy.resolve(
        japanese: "前回のルートを安全に再開できなかったため、消去しました",
        simplifiedChinese: "无法安全恢复上次路线，已清除恢复数据",
        english: "The previous route could not be restored safely; its resume data was cleared"
      )
    }
  }

  private func entryName(_ nameJA: String) -> String {
    copy.resolve(
      japanese: "\(nameJA)入口",
      simplifiedChinese: "\(nameJA)入口",
      english: "\(nameJA) entry"
    )
  }

  private func exitName(_ nameJA: String) -> String {
    copy.resolve(
      japanese: "\(nameJA)出口",
      simplifiedChinese: "\(nameJA)出口",
      english: "\(nameJA) exit"
    )
  }

  private func localizedJunctionName(
    _ prompt: WholeShutoJunctionPrompt
  ) -> String {
    prompt.localizedJunctionNames[languageSettings.interfaceLocale]
      ?? prompt.nameJA
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: languageSettings.interfaceLocale)
  }
}

private struct WholeShutoCustomRouteSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var model: WholeShutoProductModel
  @State private var entryQuery = ""
  @State private var exitQuery = ""

  var body: some View {
    VStack(spacing: 0) {
      header

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          draftRouteThread
          facilitySelector(
            title: copy.resolve(
              japanese: "入口",
              simplifiedChinese: "入口",
              english: "ENTRY"
            ),
            tint: KaidoTheme.positionCyan,
            candidates: model.customEntryCandidates,
            selectedFacilityID: model.customEntryFacilityID,
            usesEntranceDirection: true,
            orderingLabel: copy.resolve(
              japanese: "近い順 · 選択中を先頭表示",
              simplifiedChinese: "按距离排序 · 已选项置顶",
              english: "Nearest first · selection pinned"
            ),
            identifierPrefix: "whole-shuto-custom-entry",
            query: $entryQuery,
            referenceCoordinate: model.origin?.coordinate
          ) {
            model.selectCustomEntry(facilityID: $0)
          }
          facilitySelector(
            title: copy.resolve(
              japanese: "出口",
              simplifiedChinese: "出口",
              english: "EXIT"
            ),
            tint: KaidoTheme.evidenceCoral,
            candidates: model.customExitCandidates,
            selectedFacilityID: model.customExitFacilityID,
            usesEntranceDirection: false,
            orderingLabel: model.editsSelectedCircuit
              ? copy.resolve(
                japanese: "入口からの走行順 · 選択中を先頭表示",
                simplifiedChinese: "按从入口起的行驶顺序 · 已选项置顶",
                english: "In driving order from the entrance · selection pinned"
              )
              : copy.resolve(
                japanese: "近い順 · 選択中を先頭表示",
                simplifiedChinese: "按距离排序 · 已选项置顶",
                english: "Nearest first · selection pinned"
              ),
            identifierPrefix: "whole-shuto-custom-exit",
            query: $exitQuery,
            referenceCoordinate:
              model.destination?.coordinate ?? model.origin?.coordinate
          ) {
            model.selectCustomExit(facilityID: $0)
          }
          preferenceSelector
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
      }
      .scrollIndicators(.hidden)

      applyButton
    }
    .background(KaidoTheme.nightPanel)
    .presentationDetents([.fraction(0.82), .large])
    .presentationDragIndicator(.visible)
    .presentationCornerRadius(26)
    .presentationBackground(KaidoTheme.nightPanel)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("whole-shuto-route-customization")
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(
          copy.resolve(
            japanese: "ルートをカスタマイズ",
            simplifiedChinese: "自定义路线",
            english: "CUSTOM ROUTE"
          )
        )
        .font(.system(size: 21, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)

        Text(
          copy.resolve(
            japanese: "進行方向が有効な入口・出口とルート傾向を選択",
            simplifiedChinese: "选择方向合法的入口、出口和路线取向",
            english: "Choose a direction-valid entry, exit, and route style"
          )
        )
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(KaidoTheme.nightQuiet)
      }

      Spacer()

      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .black))
          .foregroundStyle(KaidoTheme.routeWhite)
          .frame(width: 44, height: 44)
          .background(KaidoTheme.nightRaised)
          .clipShape(Circle())
          .overlay {
            Circle()
              .stroke(KaidoTheme.nightDivider, lineWidth: 1)
          }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        copy.resolve(
          japanese: "閉じる",
          simplifiedChinese: "关闭",
          english: "Close"
        )
      )
      .accessibilityIdentifier("whole-shuto-custom-route-close")
    }
    .padding(.horizontal, 18)
    .padding(.top, 18)
    .padding(.bottom, 14)
  }

  private var draftRouteThread: some View {
    HStack(spacing: 9) {
      routeEndpoint(
        model.customEntryFacility?.nameJA ?? "—",
        tint: KaidoTheme.positionCyan
      )

      VStack(spacing: 4) {
        HStack(spacing: 3) {
          Rectangle()
            .fill(KaidoTheme.routeGreen)
            .frame(height: 3)
          Image(systemName: "arrowtriangle.right.fill")
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(KaidoTheme.routeGreen)
        }
        Text(draftRouteShieldLabel)
          .font(.system(size: 10, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeGreenDeep)
          .lineLimit(1)
          .minimumScaleFactor(0.62)
      }

      routeEndpoint(
        model.customExitFacility?.nameJA ?? "—",
        tint: KaidoTheme.evidenceCoral
      )
    }
    .padding(12)
    .background(KaidoTheme.nightRaised)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(KaidoTheme.nightDivider, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("whole-shuto-custom-route-preview")
    .accessibilityValue(
      model.customDraftRoute == nil ? "UNAVAILABLE" : "AVAILABLE"
    )
  }

  private func routeEndpoint(
    _ title: String,
    tint: Color
  ) -> some View {
    HStack(spacing: 5) {
      Circle()
        .fill(tint)
        .frame(width: 8, height: 8)
      Text(title)
        .font(.system(size: 10, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }
    .frame(maxWidth: 96, alignment: .leading)
  }

  private func facilitySelector(
    title: String,
    tint: Color,
    candidates: [ShutoNetworkDatabase.Facility],
    selectedFacilityID: String?,
    usesEntranceDirection: Bool,
    orderingLabel: String,
    identifierPrefix: String,
    query: Binding<String>,
    referenceCoordinate: ShutoCoordinate?,
    onSelect: @escaping (String) -> Void
  ) -> some View {
    let normalizedQuery = query.wrappedValue.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let matchingCandidates = candidates.filter { facility in
      normalizedQuery.isEmpty
        || facility.nameJA.localizedCaseInsensitiveContains(normalizedQuery)
        || shieldLabel(facility.routeID)
          .localizedCaseInsensitiveContains(normalizedQuery)
        || (facility.entranceDirections + facility.exitDirections)
          .contains {
            $0.localizedCaseInsensitiveContains(normalizedQuery)
          }
    }
    let visibleCandidates =
      normalizedQuery.isEmpty
      ? Array(matchingCandidates.prefix(12))
      : matchingCandidates

    return VStack(alignment: .leading, spacing: 7) {
      HStack {
        Text(title)
          .font(.caption.weight(.black))
          .fontDesign(.rounded)
          .foregroundStyle(KaidoTheme.nightQuiet)
        Spacer()
        Text(orderingLabel)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(KaidoTheme.nightQuiet)
      }

      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(KaidoTheme.positionCyan)
        TextField(
          copy.resolve(
            japanese: "IC名または路線番号",
            simplifiedChinese: "搜索 IC 名称或路线编号",
            english: "Search IC or route"
          ),
          text: query
        )
        .font(.body.weight(.semibold))
        .foregroundStyle(KaidoTheme.routeWhite)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        if !normalizedQuery.isEmpty {
          Button {
            query.wrappedValue = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(KaidoTheme.nightQuiet)
              .frame(width: 32, height: 32)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            copy.resolve(
              japanese: "検索を消去",
              simplifiedChinese: "清除搜索",
              english: "Clear search"
            )
          )
        }
      }
      .padding(.horizontal, 12)
      .frame(minHeight: 46)
      .background(KaidoTheme.nightRaised)
      .clipShape(RoundedRectangle(cornerRadius: 11))
      .overlay {
        RoundedRectangle(cornerRadius: 11)
          .stroke(KaidoTheme.nightDivider, lineWidth: 1)
      }
      .accessibilityIdentifier("\(identifierPrefix)-search")

      if visibleCandidates.isEmpty {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
          Text(
            normalizedQuery.isEmpty
              ? copy.resolve(
                japanese: "出発地を選ぶと候補を表示します",
                simplifiedChinese: "选择出发地后显示候选",
                english: "Choose an origin to see candidates"
              )
              : copy.resolve(
                japanese: "一致するICがありません",
                simplifiedChinese: "没有匹配的 IC",
                english: "No matching IC"
              )
          )
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(KaidoTheme.signalAmber)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .accessibilityIdentifier("\(identifierPrefix)-empty")
      } else {
        ScrollViewReader { proxy in
          ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
              ForEach(visibleCandidates) { facility in
                let isSelected =
                  facility.facilityID == selectedFacilityID
                Button {
                  onSelect(facility.facilityID)
                } label: {
                  VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                      Text(shieldLabel(facility.routeID))
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(height: 19)
                        .background(routeColor(facility.routeID))
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                      Spacer()

                      if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                          .font(.system(size: 11, weight: .black))
                          .foregroundStyle(tint)
                      }
                    }

                    Text(facility.nameJA)
                      .font(.system(size: 13, weight: .black))
                      .foregroundStyle(KaidoTheme.routeWhite)
                      .lineLimit(1)

                    Text(
                      facilityDirection(
                        facility,
                        usesEntranceDirection: usesEntranceDirection
                      )
                    )
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(KaidoTheme.nightQuiet)
                    .lineLimit(1)

                    if let referenceCoordinate {
                      Text(
                        facilityDistanceLabel(
                          facility,
                          from: referenceCoordinate
                        )
                      )
                      .font(.caption2.weight(.bold))
                      .foregroundStyle(
                        isSelected
                          ? tint : KaidoTheme.nightQuiet
                      )
                      .monospacedDigit()
                    }
                  }
                  .padding(.horizontal, 10)
                  .frame(width: 132, height: 78, alignment: .leading)
                  .background(
                    isSelected ? tint.opacity(0.13) : KaidoTheme.nightRaised
                  )
                  .clipShape(RoundedRectangle(cornerRadius: 11))
                  .overlay {
                    RoundedRectangle(cornerRadius: 11)
                      .stroke(
                        isSelected ? tint : KaidoTheme.nightDivider,
                        lineWidth: isSelected ? 2 : 1
                      )
                  }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                  "\(facility.nameJA), \(shieldLabel(facility.routeID)), "
                    + facilityDirection(
                      facility,
                      usesEntranceDirection: usesEntranceDirection
                    )
                )
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier(
                  "\(identifierPrefix)-\(facility.facilityID)"
                )
                .id(facility.facilityID)
              }
            }
          }
          .scrollIndicators(.visible)
          .onAppear {
            guard let selectedFacilityID else { return }
            proxy.scrollTo(selectedFacilityID, anchor: .leading)
          }
          .onChange(of: selectedFacilityID) { _, facilityID in
            guard let facilityID else { return }
            withAnimation(.easeOut(duration: 0.2)) {
              proxy.scrollTo(facilityID, anchor: .leading)
            }
          }
        }
      }
    }
  }

  private func facilityDistanceLabel(
    _ facility: ShutoNetworkDatabase.Facility,
    from reference: ShutoCoordinate
  ) -> String {
    let meters = CLLocation(
      latitude: reference.latitude,
      longitude: reference.longitude
    ).distance(
      from: CLLocation(
        latitude: facility.coordinate.latitude,
        longitude: facility.coordinate.longitude
      )
    )
    return distanceLabel(meters)
  }

  private var preferenceSelector: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(
        copy.resolve(
          japanese: "ルート傾向",
          simplifiedChinese: "路线取向",
          english: "ROUTE STYLE"
        )
      )
      .font(.system(size: 9, weight: .black, design: .rounded))
      .foregroundStyle(KaidoTheme.nightQuiet)

      HStack(spacing: 7) {
        ForEach(ShutoRoutePreference.allCases, id: \.rawValue) { preference in
          let isSelected = model.customPreference == preference
          Button {
            model.selectCustomPreference(preference)
          } label: {
            Text(preferenceLabel(preference))
              .font(.system(size: 10, weight: .black, design: .rounded))
              .foregroundStyle(
                isSelected ? KaidoTheme.routeWhite : KaidoTheme.routeWhite
              )
              .lineLimit(1)
              .minimumScaleFactor(0.7)
              .frame(maxWidth: .infinity)
              .frame(height: 38)
              .background(
                isSelected
                  ? KaidoTheme.routeGreenDeep : KaidoTheme.nightRaised
              )
              .clipShape(RoundedRectangle(cornerRadius: 9))
              .overlay {
                RoundedRectangle(cornerRadius: 9)
                  .stroke(
                    isSelected
                      ? KaidoTheme.routeGreenDeep : KaidoTheme.nightDivider,
                    lineWidth: 1
                  )
              }
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(isSelected ? .isSelected : [])
          .accessibilityIdentifier(
            "whole-shuto-custom-preference-\(preference.rawValue.lowercased())"
          )
        }
      }
    }
  }

  private var applyButton: some View {
    VStack(spacing: 7) {
      if model.customDraftRoute == nil {
        Text(
          copy.resolve(
            japanese: "この入口と出口を結ぶ有効なルートはありません",
            simplifiedChinese: "所选入口与出口之间没有方向合法的路线",
            english: "No direction-valid route connects this entry and exit"
          )
        )
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(KaidoTheme.signalAmber)
      }

      Button {
        if model.applyCustomRoute() {
          dismiss()
        }
      } label: {
        HStack(spacing: 8) {
          Text(
            copy.resolve(
              japanese: "このルートを使用",
              simplifiedChinese: "使用这条路线",
              english: "USE THIS ROUTE"
            )
          )
          Spacer()
          if let route = model.customDraftRoute {
            Text(distanceLabel(route.distanceMeters))
              .font(.system(size: 11, weight: .black, design: .rounded))
          }
          Image(systemName: "arrow.right")
        }
        .font(.system(size: 13, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(KaidoTheme.routeGreen)
        .clipShape(RoundedRectangle(cornerRadius: 11))
      }
      .buttonStyle(.plain)
      .disabled(!model.canApplyCustomRoute)
      .opacity(model.canApplyCustomRoute ? 1 : 0.42)
      .accessibilityIdentifier("whole-shuto-apply-custom-route")
    }
    .padding(.horizontal, 18)
    .padding(.top, 10)
    .padding(.bottom, 12)
    .background(.ultraThinMaterial)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(KaidoTheme.nightDivider)
        .frame(height: 1)
    }
  }

  private var draftRouteShieldLabel: String {
    guard let route = model.customDraftRoute else {
      return copy.resolve(
        japanese: "経路なし",
        simplifiedChinese: "无可用路线",
        english: "NO ROUTE"
      )
    }
    return route.routeIDsInOrder
      .map(shieldLabel)
      .joined(separator: " · ")
  }

  private func facilityDirection(
    _ facility: ShutoNetworkDatabase.Facility,
    usesEntranceDirection: Bool
  ) -> String {
    let directions =
      usesEntranceDirection
      ? facility.entranceDirections : facility.exitDirections
    return directions.isEmpty
      ? copy.resolve(
        japanese: "ルートで方向確定",
        simplifiedChinese: "方向由路线确定",
        english: "Direction fixed by route"
      )
      : directions.joined(separator: " / ")
  }

  private func preferenceLabel(
    _ preference: ShutoRoutePreference
  ) -> String {
    switch preference {
    case .recommended:
      copy.resolve(
        japanese: "おすすめ",
        simplifiedChinese: "推荐",
        english: "Recommended"
      )
    case .fewerJunctions:
      copy.resolve(
        japanese: "分岐を減らす",
        simplifiedChinese: "少分岔",
        english: "Fewer junctions"
      )
    case .preferBayshore:
      copy.resolve(
        japanese: "湾岸線優先",
        simplifiedChinese: "湾岸优先",
        english: "Prefer Bayshore"
      )
    }
  }

  private func distanceLabel(_ meters: Double) -> String {
    meters >= 1_000
      ? String(format: "%.1f km", meters / 1_000)
      : "\(Int(max(0, meters).rounded())) m"
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

private struct WholeShutoCircleButtonStyle: ButtonStyle {
  let isDriving: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(KaidoTheme.routeWhite)
      .background(KaidoTheme.nightRaised.opacity(0.95))
      .clipShape(Circle())
      .overlay {
        Circle()
          .stroke(KaidoTheme.nightDivider, lineWidth: 1)
      }
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
  }
}

private struct WholeShutoNetworkDiagram: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  let database: ShutoNetworkDatabase
  let selectedRoute: ShutoPlannedRoute?
  let currentCoordinate: ShutoCoordinate?
  let usesDarkStyle: Bool
  let visibleBottomFraction: Double

  private var nodesByID: [Int64: ShutoCoordinate] {
    Dictionary(
      uniqueKeysWithValues: database.nodes.map {
        ($0.nodeID, $0.coordinate)
      }
    )
  }

  var body: some View {
    Canvas { context, size in
      let transform = DiagramTransform(
        size: size,
        visibleBottomFraction: visibleBottomFraction
      )
      context.fill(
        Path(CGRect(origin: .zero, size: size)),
        with: .color(
          usesDarkStyle ? KaidoTheme.night : KaidoTheme.nightPanel
        )
      )

      drawWater(context: &context, size: size)

      let nodeCoordinates = nodesByID
      // Track-map visual language: one quiet casing pass under all routes,
      // then calm solid route colors on top.
      var wayPaths: [(path: Path, routeID: String)] = []
      for way in database.ways where way.kind == "MAINLINE" {
        let points = way.nodeIDs.compactMap {
          nodeCoordinates[$0].map(transform.point)
        }
        guard points.count > 1 else { continue }
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() {
          path.addLine(to: point)
        }
        wayPaths.append(
          (path, way.routeMemberships.first?.routeID ?? "")
        )
      }
      for way in wayPaths {
        context.stroke(
          way.path,
          with: .color(
            usesDarkStyle
              ? Color(red: 0.11, green: 0.14, blue: 0.2)
              : Color(red: 0.85, green: 0.87, blue: 0.9)
          ),
          style: StrokeStyle(
            lineWidth: 4.2,
            lineCap: .round,
            lineJoin: .round
          )
        )
      }
      for way in wayPaths {
        context.stroke(
          way.path,
          with: .color(
            routeColor(way.routeID).opacity(usesDarkStyle ? 0.78 : 0.88)
          ),
          style: StrokeStyle(
            lineWidth: 2.3,
            lineCap: .round,
            lineJoin: .round
          )
        )
      }

      if let selectedRoute {
        let points = selectedRoute.coordinates.map(transform.point)
        if points.count > 1 {
          var path = Path()
          path.move(to: points[0])
          for point in points.dropFirst() {
            path.addLine(to: point)
          }
          context.stroke(
            path,
            with: .color(
              usesDarkStyle
                ? KaidoTheme.routeWhite.opacity(0.86)
                : Color.white.opacity(0.95)
            ),
            style: StrokeStyle(
              lineWidth: 10,
              lineCap: .round,
              lineJoin: .round
            )
          )
          context.stroke(
            path,
            with: .color(KaidoTheme.signalAmber),
            style: StrokeStyle(
              lineWidth: 6,
              lineCap: .round,
              lineJoin: .round
            )
          )
        }
        marker(
          context: &context,
          at: transform.point(selectedRoute.entryFacility.coordinate),
          color: KaidoTheme.positionCyan,
          label: copy.resolve(
            japanese: "入",
            simplifiedChinese: "入",
            english: "E"
          )
        )
        marker(
          context: &context,
          at: transform.point(selectedRoute.destinationCoordinate),
          color: KaidoTheme.evidenceCoral,
          label: copy.resolve(
            japanese: selectedRoute.destinationParkingArea != nil ? "PA" : "出",
            simplifiedChinese: selectedRoute.destinationParkingArea != nil ? "PA" : "出",
            english: selectedRoute.destinationParkingArea != nil ? "PA" : "X"
          )
        )
      }

      for junction in database.junctions.prefix(39) {
        guard let coordinate = junction.coordinate else { continue }
        let point = transform.point(coordinate)
        context.fill(
          Path(
            ellipseIn: CGRect(
              x: point.x - 2.2,
              y: point.y - 2.2,
              width: 4.4,
              height: 4.4
            )
          ),
          with: .color(
            usesDarkStyle
              ? KaidoTheme.routeWhite.opacity(0.8)
              : KaidoTheme.routeWhite.opacity(0.65)
          )
        )
      }

      // The network scale shows route identity, not every facility: IC dots
      // move to the selected-route track map, and PA marks stay quiet.
      for parkingArea in database.parkingAreas {
        let point = transform.point(parkingArea.coordinate)
        let frame = CGRect(
          x: point.x - 3.4,
          y: point.y - 3.4,
          width: 6.8,
          height: 6.8
        )
        context.fill(
          Path(roundedRect: frame, cornerRadius: 1.8),
          with: .color(KaidoTheme.signalAmber.opacity(0.82))
        )
        context.draw(
          context.resolve(
            Text("P")
              .font(.system(size: 4.4, weight: .black))
              .foregroundStyle(KaidoTheme.night)
          ),
          at: point
        )
      }

      if let currentCoordinate {
        let point = transform.point(currentCoordinate)
        context.fill(
          Path(
            ellipseIn: CGRect(
              x: point.x - 7,
              y: point.y - 7,
              width: 14,
              height: 14
            )
          ),
          with: .color(Color.white)
        )
        context.fill(
          Path(
            ellipseIn: CGRect(
              x: point.x - 4.5,
              y: point.y - 4.5,
              width: 9,
              height: 9
            )
          ),
          with: .color(KaidoTheme.positionCyan)
        )
      }

      drawRouteShields(
        context: &context,
        transform: transform,
        nodeCoordinates: nodeCoordinates
      )
    }
    .overlay(alignment: .bottomTrailing) {
      VStack(alignment: .trailing, spacing: 2) {
        Text("NETWORK")
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .tracking(0.8)
        Text(
          copy.resolve(
            japanese: "路線関係図 · 道路縮尺ではありません",
            simplifiedChinese: "线路关系图 · 非道路比例",
            english: "NETWORK DIAGRAM · NOT TO ROAD SCALE"
          )
        )
        .font(.system(size: 7, weight: .bold))
      }
      .foregroundStyle(
        usesDarkStyle ? KaidoTheme.nightQuiet : KaidoTheme.nightQuiet
      )
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(.ultraThinMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .padding(12)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier("whole-shuto-network-map")
    .accessibilityLabel(
      copy.resolve(
        japanese: "全体路線図",
        simplifiedChinese: "全网线路图",
        english: "Whole-network map"
      )
    )
    .accessibilityValue(
      selectedRoute == nil
        ? copy.resolve(
          japanese: "26路線",
          simplifiedChinese: "26条路线",
          english: "26 routes"
        )
        : selectedRoute!.routeIDsInOrder
          .map(shieldLabel)
          .joined(
            separator: copy.resolve(
              japanese: "から",
              simplifiedChinese: "到",
              english: " to "
            )
          )
    )
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }

  private func drawWater(
    context: inout GraphicsContext,
    size: CGSize
  ) {
    var bay = Path()
    bay.move(to: CGPoint(x: size.width * 0.58, y: size.height * 0.54))
    bay.addCurve(
      to: CGPoint(x: size.width, y: size.height * 0.44),
      control1: CGPoint(x: size.width * 0.76, y: size.height * 0.47),
      control2: CGPoint(x: size.width * 0.88, y: size.height * 0.46)
    )
    bay.addLine(to: CGPoint(x: size.width, y: size.height))
    bay.addLine(to: CGPoint(x: size.width * 0.44, y: size.height))
    bay.addCurve(
      to: CGPoint(x: size.width * 0.58, y: size.height * 0.54),
      control1: CGPoint(x: size.width * 0.50, y: size.height * 0.77),
      control2: CGPoint(x: size.width * 0.54, y: size.height * 0.64)
    )
    context.fill(
      bay,
      with: .color(
        usesDarkStyle
          ? Color(hex: 0x112C36)
          : KaidoTheme.surfaceWater
      )
    )
  }

  private func drawRouteShields(
    context: inout GraphicsContext,
    transform: DiagramTransform,
    nodeCoordinates: [Int64: ShutoCoordinate]
  ) {
    let featured = [
      "C1", "C2", "B", "1_HANEDA", "3", "4", "5", "6_MUKOJIMA", "7", "K1", "K7_YOKOHAMA_KITA", "S1",
    ]
    // Anchor each shield mid-route, then push overlapping shields apart so
    // the central cluster stays readable.
    var placements: [(routeID: String, point: CGPoint)] = []
    for routeID in featured {
      let coordinates = database.ways
        .filter {
          $0.kind == "MAINLINE"
            && $0.routeMemberships.contains { $0.routeID == routeID }
        }
        .flatMap(\.nodeIDs)
        .compactMap { nodeCoordinates[$0] }
      guard !coordinates.isEmpty else { continue }
      let coordinate = coordinates[coordinates.count / 2]
      placements.append(
        (routeID, transform.point(coordinate))
      )
    }
    let minimumShieldGap = 24.0
    for index in placements.indices {
      var point = placements[index].point
      for earlier in placements[..<index] {
        let dx = point.x - earlier.point.x
        let dy = point.y - earlier.point.y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance < minimumShieldGap {
          let push = minimumShieldGap - distance
          if distance > 0.001 {
            point.x += dx / distance * push
            point.y += dy / distance * push
          } else {
            point.y -= minimumShieldGap
          }
        }
      }
      placements[index].point = point
    }
    for placement in placements {
      let point = placement.point
      let resolved = context.resolve(
        Text(shieldLabel(placement.routeID))
          .font(.system(size: 7, weight: .black, design: .rounded))
          .foregroundStyle(Color.white)
      )
      let frame = CGRect(
        x: point.x - 11,
        y: point.y - 8,
        width: 22,
        height: 16
      )
      let shield = Path(roundedRect: frame, cornerRadius: 4)
      context.fill(shield, with: .color(routeColor(placement.routeID)))
      context.stroke(
        shield,
        with: .color(
          usesDarkStyle
            ? KaidoTheme.night.opacity(0.9)
            : Color.white.opacity(0.9)
        ),
        style: StrokeStyle(lineWidth: 1.2)
      )
      context.draw(resolved, at: point)
    }
  }

  private func marker(
    context: inout GraphicsContext,
    at point: CGPoint,
    color: Color,
    label: String
  ) {
    let frame = CGRect(
      x: point.x - 10,
      y: point.y - 10,
      width: 20,
      height: 20
    )
    context.fill(
      Path(ellipseIn: frame),
      with: .color(Color.white)
    )
    context.fill(
      Path(ellipseIn: frame.insetBy(dx: 2.5, dy: 2.5)),
      with: .color(color)
    )
    context.draw(
      context.resolve(
        Text(label)
          .font(.system(size: 7, weight: .black))
          .foregroundStyle(Color.white)
      ),
      at: point
    )
  }
}

private struct DiagramTransform {
  let size: CGSize
  let visibleBottomFraction: Double

  func point(_ coordinate: ShutoCoordinate) -> CGPoint {
    let minimumLongitude = 139.29
    let maximumLongitude = 140.14
    let minimumLatitude = 35.34
    let maximumLatitude = 35.94
    let x =
      (coordinate.longitude - minimumLongitude)
      / (maximumLongitude - minimumLongitude)
    let y =
      (maximumLatitude - coordinate.latitude)
      / (maximumLatitude - minimumLatitude)
    return CGPoint(
      x: 16 + min(1, max(0, x)) * (size.width - 32),
      y:
        62
        + min(1, max(0, y))
        * max(100, size.height * visibleBottomFraction - 108)
    )
  }
}

/// One-time per-snapshot cache of every mainline carriageway, both
/// directions, for the muted context layer beneath the highlighted route.
/// Cached as `MKPolyline` objects so the map content diff during route
/// playback compares object identity instead of thousands of coordinates.
@MainActor
private enum WholeShutoNetworkBackdrop {
  private static var cached:
    (snapshotID: String, polylines: [MKPolyline])?

  static func polylines(
    for database: ShutoNetworkDatabase
  ) -> [MKPolyline] {
    if let cached, cached.snapshotID == database.networkSnapshotID {
      return cached.polylines
    }
    let nodeCoordinates = Dictionary(
      uniqueKeysWithValues: database.nodes.map {
        ($0.nodeID, $0.coordinate)
      }
    )
    // Stitch directed mainline ways into long chains by shared end nodes:
    // ~1000 short ways collapse into a few dozen polylines, which keeps the
    // map content diff cheap while the route progress republishes.
    let ways = database.ways.filter {
      $0.kind == "MAINLINE" && $0.nodeIDs.count > 1
    }
    var used = [Bool](repeating: false, count: ways.count)
    var byFirstNode: [Int64: [Int]] = [:]
    for (index, way) in ways.enumerated() {
      byFirstNode[way.nodeIDs[0], default: []].append(index)
    }
    var polylines: [MKPolyline] = []
    for index in ways.indices where !used[index] {
      used[index] = true
      var nodeIDs = ways[index].nodeIDs
      while let nextIndex = byFirstNode[nodeIDs[nodeIDs.count - 1]]?
        .first(where: { !used[$0] })
      {
        used[nextIndex] = true
        nodeIDs.append(contentsOf: ways[nextIndex].nodeIDs.dropFirst())
      }
      // Thin to ~60 m spacing: the muted hairline needs shape, not fidelity,
      // and fewer vertices keep the overlay cheap during route playback.
      let raw = nodeIDs.compactMap { nodeCoordinates[$0] }
      var coordinates: [CLLocationCoordinate2D] = []
      var lastKept: ShutoCoordinate?
      for (offset, coordinate) in raw.enumerated() {
        let isEndpoint = offset == 0 || offset == raw.count - 1
        if let lastKept, !isEndpoint {
          let dLatitude = (coordinate.latitude - lastKept.latitude) * 110_540
          let dLongitude =
            (coordinate.longitude - lastKept.longitude) * 90_000
          if (dLatitude * dLatitude + dLongitude * dLongitude)
            .squareRoot() < 60
          {
            continue
          }
        }
        lastKept = coordinate
        coordinates.append(coordinate.mapCoordinate)
      }
      if coordinates.count > 1 {
        polylines.append(
          MKPolyline(coordinates: coordinates, count: coordinates.count)
        )
      }
    }
    cached = (database.networkSnapshotID, polylines)
    return polylines
  }
}

private struct WholeShutoGeographicMap: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var model: WholeShutoProductModel
  let planningLocation: WholeShutoPlanningLocationSnapshot?
  static let defaultCamera = MapCameraPosition.region(
    MKCoordinateRegion(
      center: CLLocationCoordinate2D(
        latitude: 35.6762,
        longitude: 139.6503
      ),
      latitudinalMeters: 82_000,
      longitudinalMeters: 82_000
    )
  )
  @Binding var camera: MapCameraPosition
  @Binding var followsRoute: Bool
  @Binding var lastStableHeadingDegrees: Double?

  /// Touch outranks the route: a map gesture releases follow for
  /// `gestureResumeDelay`, while the explicit control releases it until the
  /// driver asks for it back.
  @State private var gestureResumeTask: Task<Void, Never>?
  /// The eye altitude the driver last set by hand. Follow mode re-centers
  /// and re-orients around it instead of snapping back to the phase default.
  @State private var userCameraDistanceMeters: Double?
  /// The tapped basemap place, and whether the camera was following when it
  /// was tapped, so the drive can pick following back up on dismissal.
  @State private var selectedMapFeature: MapFeature?
  @State private var followedBeforeFeatureSelection = false
  @State private var cameraHeadingDegrees = 0.0
  @State private var cameraPitchDegrees = 0.0
  private static let gestureResumeDelay = Duration.seconds(10)
  private static let userCameraDistanceRange: ClosedRange<Double> =
    120...24_000
  /// What a driver can act on from behind the wheel. The full basemap
  /// catalog is planning material — central Tokyo puts eight restaurant
  /// labels over the route in a single frame — so the drive keeps only what
  /// a stop is made for, and the parked map keeps everything.
  private static let drivingPointsOfInterest: [MKPointOfInterestCategory] = [
    .gasStation,
    .evCharger,
    .parking,
    .restroom,
  ]

  var body: some View {
    Map(position: $camera, selection: $selectedMapFeature) {
      // The whole expressway network — both carriageways of every mainline —
      // as a muted context layer beneath the active route. It never carries
      // guidance authority; stacked carriageways may coincide in plan view.
      ForEach(
        WholeShutoNetworkBackdrop.polylines(for: model.database),
        id: \.self
      ) { polyline in
        MapPolyline(polyline)
          .stroke(
            KaidoTheme.roadGray.opacity(0.34),
            style: StrokeStyle(
              lineWidth: 2.4,
              lineCap: .round,
              lineJoin: .round
            )
          )
      }

      if let accessRoute = model.accessRoute,
        model.phase == .review || model.phase == .surfaceAccess
      {
        // Casing under a solid core, the way every driving map draws a
        // route. A dash cannot carry "provider leg, not Kaido authority"
        // here: the casing shows through its gaps and the leg reads as a
        // striped ribbon rather than a road. Colour carries that meaning
        // instead — cyan in, coral out, against the route's green.
        MapPolyline(
          coordinates: accessRoute.coordinates.map(\.mapCoordinate)
        )
        .stroke(
          KaidoTheme.night.opacity(0.8),
          style: StrokeStyle(
            lineWidth: 9,
            lineCap: .round,
            lineJoin: .round
          )
        )
        MapPolyline(
          coordinates: accessRoute.coordinates.map(\.mapCoordinate)
        )
        .stroke(
          KaidoTheme.positionCyan,
          style: StrokeStyle(
            lineWidth: 5.5,
            lineCap: .round,
            lineJoin: .round
          )
        )
      }

      if let route = model.selectedRoute {
        // Casing, then the route colour, then progress — the layer order
        // every navigation renderer uses. The casing must be darker than
        // the line it borders: a white one blends into MapKit's own white
        // motorway fill and the route stops looking like an overlay at all.
        MapPolyline(
          coordinates: route.coordinates.map(\.mapCoordinate)
        )
        .stroke(
          KaidoTheme.night.opacity(0.85),
          style: StrokeStyle(
            lineWidth: 11,
            lineCap: .round,
            lineJoin: .round
          )
        )
        if let progress = model.routeProgressGeometry {
          if progress.traveledCoordinates.count > 1 {
            // What is behind the driver recedes instead of competing: the
            // same line, dimmed, rather than a second colour of its own.
            MapPolyline(
              coordinates:
                progress.traveledCoordinates.map(\.mapCoordinate)
            )
            .stroke(
              KaidoTheme.routeGreen.opacity(0.3),
              style: StrokeStyle(
                lineWidth: 7,
                lineCap: .round,
                lineJoin: .round
              )
            )
          }
          if progress.remainingCoordinates.count > 1 {
            MapPolyline(
              coordinates:
                progress.remainingCoordinates.map(\.mapCoordinate)
            )
            .stroke(
              KaidoTheme.routeGreen,
              style: StrokeStyle(
                lineWidth: 7,
                lineCap: .round,
                lineJoin: .round
              )
            )
          }
        } else {
          MapPolyline(
            coordinates: route.coordinates.map(\.mapCoordinate)
          )
          .stroke(
            KaidoTheme.routeGreen,
            style: StrokeStyle(
              lineWidth: 7,
              lineCap: .round,
              lineJoin: .round
            )
          )
        }

        if model.activeRecoveryRouteCoordinates.count > 1 {
          MapPolyline(
            coordinates: model.activeRecoveryRouteCoordinates.map(\.mapCoordinate)
          )
          .stroke(
            KaidoTheme.signalAmber,
            style: StrokeStyle(
              lineWidth: 8,
              lineCap: .round,
              lineJoin: .round,
              dash: [10, 6]
            )
          )
        }

        Annotation(
          facilityBoundaryName(
            route.entryFacility.nameJA,
            isEntry: true
          ),
          coordinate: route.entryFacility.coordinate.mapCoordinate
        ) {
          WholeShutoMapMarker(
            text: copy.resolve(
              japanese: "入",
              simplifiedChinese: "入",
              english: "E"
            ),
            color: KaidoTheme.positionCyan
          )
        }
        Annotation(
          route.destinationParkingArea == nil ? facilityBoundaryName(route.destinationNameJA, isEntry: false) : route.destinationNameJA,
          coordinate: route.destinationCoordinate.mapCoordinate
        ) {
          WholeShutoMapMarker(
            text: copy.resolve(
              japanese: route.destinationParkingArea != nil ? "PA" : "出",
              simplifiedChinese: route.destinationParkingArea != nil ? "PA" : "出",
              english: route.destinationParkingArea != nil ? "PA" : "X"
            ),
            color: KaidoTheme.evidenceCoral
          )
        }
      }

      ForEach(visibleFacilities) { facility in
        Annotation(
          facility.nameJA,
          coordinate: facility.coordinate.mapCoordinate
        ) {
          WholeShutoFacilityLabel(
            prefix: "IC",
            name: facility.nameJA,
            color: KaidoTheme.routeGreenDeep
          )
        }
      }

      ForEach(visibleParkingAreas) { parkingArea in
        Annotation(
          parkingArea.nameJA,
          coordinate: parkingArea.coordinate.mapCoordinate
        ) {
          WholeShutoFacilityLabel(
            prefix: "P",
            name: parkingArea.baseNameJA,
            color: KaidoTheme.signalAmber,
            darkText: true
          )
        }
      }

      if let egressRoute = model.egressRoute,
        model.phase == .review || model.phase == .surfaceEgress
          || model.phase == .completed
      {
        MapPolyline(
          coordinates: egressRoute.coordinates.map(\.mapCoordinate)
        )
        .stroke(
          KaidoTheme.night.opacity(0.8),
          style: StrokeStyle(
            lineWidth: 9,
            lineCap: .round,
            lineJoin: .round
          )
        )
        MapPolyline(
          coordinates: egressRoute.coordinates.map(\.mapCoordinate)
        )
        .stroke(
          KaidoTheme.evidenceCoral,
          style: StrokeStyle(
            lineWidth: 5.5,
            lineCap: .round,
            lineJoin: .round
          )
        )
      }

      ForEach(visibleJunctionPrompts) { prompt in
        Annotation(
          prompt.nameJA,
          coordinate: prompt.coordinate.mapCoordinate
        ) {
          WholeShutoFacilityLabel(
            prefix: "JCT",
            name: prompt.nameJA,
            color: KaidoTheme.routeWhite
          )
        }
      }

      if !isDriving, let planningLocation,
        planningLocation.horizontalAccuracyMeters > 0,
        planningLocation.horizontalAccuracyMeters <= 1_000
      {
        MapCircle(
          center: planningLocation.coordinate.mapCoordinate,
          radius: planningLocation.horizontalAccuracyMeters
        )
        .foregroundStyle(KaidoTheme.positionCyan.opacity(0.12))
        .stroke(KaidoTheme.positionCyan.opacity(0.38), lineWidth: 1)
      }

      if !isDriving, let origin = model.origin {
        Annotation(
          copy.resolve(
            japanese: "出発地",
            simplifiedChinese: "出发地",
            english: "Origin"
          ),
          coordinate: origin.coordinate.mapCoordinate
        ) {
          WholeShutoMapMarker(
            text: "A",
            color: KaidoTheme.positionCyan
          )
        }
      }

      if !isDriving, let destination = model.destination {
        Annotation(
          copy.resolve(
            japanese: "目的地",
            simplifiedChinese: "目的地",
            english: "Destination"
          ),
          coordinate: destination.coordinate.mapCoordinate
        ) {
          WholeShutoMapMarker(
            text: "B",
            color: KaidoTheme.evidenceCoral
          )
          .accessibilityIdentifier("whole-shuto-selected-destination")
        }
      }

      if model.positionState == .tunnelEstimated,
        let current = displayedPosition,
        let uncertainty = model.tunnelEstimateUncertaintyMeters
      {
        MapCircle(
          center: current.mapCoordinate,
          radius: uncertainty
        )
        .foregroundStyle(KaidoTheme.signalAmber.opacity(0.12))
        .stroke(
          KaidoTheme.signalAmber.opacity(0.55),
          style: StrokeStyle(lineWidth: 2, dash: [5, 4])
        )
      }

      if let current = displayedPosition {
        Annotation(
          positionAnnotationLabel,
          coordinate: current.mapCoordinate
        ) {
          ZStack {
            Circle()
              .fill(Color.white)
              .frame(width: 27, height: 27)
              .shadow(radius: 4)
            Image(
              systemName:
                displayedHeadingDegrees == nil
                ? "circle.fill" : "location.north.fill"
            )
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(
              model.positionState == .tunnelEstimated
                || model.positionState == .routeInterrupted
                ? KaidoTheme.signalAmber : KaidoTheme.positionCyan
            )
            .rotationEffect(
              .degrees(
                NavigationDirectionPresentation.screenAngle(
                  bearing: displayedHeadingDegrees ?? 0,
                  cameraHeading: cameraHeadingDegrees,
                  cameraPitch: cameraPitchDegrees
                )
              )
            )
            .transaction { $0.animation = nil }
          }
          .accessibilityIdentifier("whole-shuto-current-position")
          .accessibilityLabel(positionAnnotationLabel)
        }
      }
    }
    .mapStyle(
      model.phase == .planning || model.phase == .review
        // Congestion colouring is unreadable at journey framing — it paints
        // the whole Kanto basemap and the selected route stops standing out
        // — and nothing here acts on it. The drive frames close enough for
        // it to mean something.
        ? .standard(elevation: .flat)
        : .standard(
          elevation: .realistic,
          pointsOfInterest: .including(Self.drivingPointsOfInterest),
          showsTraffic: true
        )
    )
    // Apple's place card carries the operating hours MapKit does not expose
    // as data. It is the only way this product can answer "is it open"; that
    // answer is Apple's, and it never reaches a Kaido route or toll decision.
    .mapFeatureSelectionAccessory(.callout(.compact))
    // A ward boundary or a bay is not a place to stop, and selecting one
    // would take the camera off the route for nothing.
    .mapFeatureSelectionDisabled { $0.kind != .pointOfInterest }
    .mapControls {
      MapCompass()
    }
    .simultaneousGesture(
      DragGesture(minimumDistance: 6)
        .onChanged { _ in releaseFollowForGesture() }
    )
    .simultaneousGesture(
      MagnifyGesture(minimumScaleDelta: 0.01)
        .onChanged { _ in releaseFollowForGesture() }
    )
    .simultaneousGesture(
      RotateGesture(minimumAngleDelta: .degrees(2))
        .onChanged { _ in releaseFollowForGesture() }
    )
    .onMapCameraChange(frequency: .continuous) { context in
      cameraHeadingDegrees = context.camera.heading
      cameraPitchDegrees = context.camera.pitch
      // Only a camera the driver came to rest on defines their zoom;
      // follow-mode writes would otherwise record their own default back.
      guard !followsRoute else { return }
      userCameraDistanceMeters = min(
        Self.userCameraDistanceRange.upperBound,
        max(Self.userCameraDistanceRange.lowerBound, context.camera.distance)
      )
    }
    .accessibilityIdentifier("whole-shuto-geographic-map")
    .accessibilityValue(
      !followsRoute
        ? "FREE"
        : model.navigationHeadingDegrees == nil
          ? "FOLLOWING_NORTH_UP_NO_HEADING"
          : "FOLLOWING_ROUTE_HEADING"
    )
    .overlay(alignment: .trailing) {
      if isActiveNavigation {
        Button {
          // An explicit release is sticky: it cancels the timed resume a
          // gesture would have scheduled.
          gestureResumeTask?.cancel()
          gestureResumeTask = nil
          followsRoute.toggle()
          if followsRoute {
            updateCamera(force: true)
          }
        } label: {
          Image(
            systemName:
              followsRoute
              ? "arrow.up.left.and.arrow.down.right"
              : "location.fill"
          )
          .font(.system(size: 15, weight: .black))
          .frame(width: 44, height: 44)
        }
        .buttonStyle(WholeShutoCircleButtonStyle(isDriving: true))
        .accessibilityLabel(
          followsRoute
            ? copy.resolve(
              japanese: "地図を自由に見る",
              simplifiedChinese: "自由浏览地图",
              english: "Browse map freely"
            )
            : copy.resolve(
              japanese: "ルート追従に戻る",
              simplifiedChinese: "回到路线跟随",
              english: "Resume route following"
            )
        )
        .accessibilityIdentifier("whole-shuto-route-following-control")
        .accessibilityValue(followsRoute ? "FOLLOWING" : "FREE")
        .padding(.trailing, 14)
      }
    }
    .onAppear {
      updateCamera()
    }
    .onChange(of: model.phase) {
      // A new phase is a new frame: surface, transition, and expressway want
      // different eye altitudes, so a hand-set camera belongs to the phase
      // the driver set it in and never strands the next one off-position.
      userCameraDistanceMeters = nil
      selectedMapFeature = nil
      gestureResumeTask?.cancel()
      gestureResumeTask = nil
      followsRoute = true
      updateCamera(force: true)
    }
    .onChange(of: selectedMapFeature != nil) { _, isSelected in
      handleMapFeatureSelection(isSelected: isSelected)
    }
    .onDisappear {
      gestureResumeTask?.cancel()
      gestureResumeTask = nil
    }
    .onChange(of: model.currentCoordinate?.latitude) {
      updateCamera()
    }
    .onChange(of: model.currentCoordinate?.longitude) {
      updateCamera()
    }
    .onChange(of: planningLocation?.coordinate.latitude) {
      updateCamera()
    }
    .onChange(of: planningLocation?.coordinate.longitude) {
      updateCamera()
    }
    .onChange(of: model.progressFraction) {
      updateCamera()
    }
  }

  private var visibleRouteIDs: Set<String> {
    Set(model.selectedRoute?.routeIDsInOrder ?? [])
  }

  private var visibleFacilities: [ShutoNetworkDatabase.Facility] {
    guard
      !visibleRouteIDs.isEmpty,
      isDriving,
      let current = model.currentCoordinate
    else {
      return []
    }
    let facilities = model.database.directionalFacilities.filter {
      $0.operationalStatus == "AVAILABLE"
        && visibleRouteIDs.contains($0.routeID)
    }
    return
      facilities
      .map { ($0, geographicDistance($0.coordinate, current)) }
      .filter { $0.1 <= 3_000 }
      .sorted { $0.1 < $1.1 }
      .prefix(3)
      .map(\.0)
  }

  private var visibleJunctionPrompts: [WholeShutoJunctionPrompt] {
    guard isDriving else { return [] }
    let activeID = model.activeJunctionPrompt?.id
    return model.junctionPrompts
      .filter {
        $0.id != activeID
          && $0.progressFraction > model.progressFraction + 0.006
      }
      .prefix(2)
      .map { $0 }
  }

  private var visibleParkingAreas: [ShutoNetworkDatabase.ParkingArea] {
    guard
      !visibleRouteIDs.isEmpty,
      isDriving,
      let current = model.currentCoordinate
    else {
      return []
    }
    let parkingAreas = model.database.parkingAreas.filter {
      $0.routeID.map(visibleRouteIDs.contains) == true
    }
    return parkingAreas.filter {
      geographicDistance($0.coordinate, current) <= 7_000
    }
  }

  private var isDriving: Bool {
    ![WholeShutoJourneyPhase.planning, .review].contains(model.phase)
  }

  private var isActiveNavigation: Bool {
    isDriving && model.phase != .completed
  }

  private var displayedPosition: ShutoCoordinate? {
    isDriving ? model.currentCoordinate : planningLocation?.coordinate
  }

  private var displayedHeadingDegrees: Double? {
    isDriving
      ? model.vehicleHeadingDegrees
      : planningLocation?.courseDegrees
  }

  private var positionAnnotationLabel: String {
    guard isDriving else {
      return copy.resolve(
        japanese: "現在地",
        simplifiedChinese: "当前位置",
        english: "Current location"
      )
    }
    if model.isLiveDrive {
      if model.positionState == .routeInterrupted,
        model.runtimeRecoveryStatus == .active
      {
        return copy.resolve(
          japanese: "復帰経路上の現在地",
          simplifiedChinese: "绕回路线当前位置",
          english: "Current location on rejoin route"
        )
      }
      if model.positionState == .tunnelEstimated {
        return copy.resolve(
          japanese: "推定位置",
          simplifiedChinese: "估算位置",
          english: "Estimated position"
        )
      }
      return copy.resolve(
        japanese: "現在地",
        simplifiedChinese: "当前位置",
        english: "Current location"
      )
    }
    return copy.resolve(
      japanese: "模擬位置",
      simplifiedChinese: "模拟位置",
      english: "Simulated position"
    )
  }

  private func facilityBoundaryName(
    _ nameJA: String,
    isEntry: Bool
  ) -> String {
    if isEntry {
      return copy.resolve(
        japanese: "\(nameJA)入口",
        simplifiedChinese: "\(nameJA)入口",
        english: "\(nameJA) entry"
      )
    }
    return copy.resolve(
      japanese: "\(nameJA)出口",
      simplifiedChinese: "\(nameJA)出口",
      english: "\(nameJA) exit"
    )
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }

  /// A pan, pinch, or rotate hands the camera to the driver at once —
  /// otherwise the next position fix drags the map back out from under their
  /// finger. Only a live drive takes it back on its own, after
  /// `gestureResumeDelay` of no touch; a parked map stays where they left it
  /// until the journey moves to another phase.
  private func releaseFollowForGesture() {
    releaseFollow(resumesAutomatically: true)
  }

  private func releaseFollow(resumesAutomatically: Bool) {
    if followsRoute {
      followsRoute = false
    }
    gestureResumeTask?.cancel()
    gestureResumeTask = nil
    guard resumesAutomatically, isActiveNavigation else { return }
    gestureResumeTask = Task { @MainActor in
      try? await Task.sleep(for: Self.gestureResumeDelay)
      guard !Task.isCancelled, isActiveNavigation, !followsRoute else {
        return
      }
      followsRoute = true
      updateCamera(force: true)
    }
  }

  /// An open place card outranks the timer as well as the route: re-centring
  /// underneath it would carry the callout off-screen mid-read. Following
  /// returns when the card closes, and only if it was on beforehand.
  private func handleMapFeatureSelection(isSelected: Bool) {
    if isSelected {
      followedBeforeFeatureSelection = followsRoute
      releaseFollow(resumesAutomatically: false)
      return
    }
    guard followedBeforeFeatureSelection else { return }
    followedBeforeFeatureSelection = false
    gestureResumeTask?.cancel()
    gestureResumeTask = nil
    followsRoute = true
    updateCamera(force: true)
  }

  private var followCameraDistanceMeters: Double {
    userCameraDistanceMeters ?? model.navigationCameraDistanceMeters
  }

  private func updateCamera(force: Bool = false) {
    guard force || followsRoute else { return }
    guard isDriving, let current = model.currentCoordinate else {
      followsRoute = true
      lastStableHeadingDegrees = nil
      // `.automatic` would frame every overlay including the whole-network
      // backdrop (the full Kanto span); frame the journey or the driver's
      // surroundings instead.
      withAnimation(.easeOut(duration: 0.5)) {
        if let region = journeyRegion() {
          camera = .region(region)
        } else if let planningLocation {
          camera = .region(
            MKCoordinateRegion(
              center: planningLocation.coordinate.mapCoordinate,
              latitudinalMeters: 14_000,
              longitudinalMeters: 14_000
            )
          )
        }
      }
      return
    }
    lastStableHeadingDegrees = model.navigationHeadingDegrees
    withAnimation(.easeOut(duration: 0.35)) {
      if let heading = lastStableHeadingDegrees {
        camera = .camera(
          MapCamera(
            centerCoordinate: current.mapCoordinate,
            distance: followCameraDistanceMeters,
            heading: heading,
            pitch: 45
          )
        )
      } else {
        camera = .camera(
          MapCamera(
            centerCoordinate: current.mapCoordinate,
            distance: followCameraDistanceMeters,
            heading: 0,
            pitch: 0
          )
        )
      }
    }
  }

  /// Bounding region over the selected route plus resolved surface legs,
  /// with padding so the review frame reads as one journey.
  private func journeyRegion() -> MKCoordinateRegion? {
    guard let route = model.selectedRoute else { return nil }
    var coordinates: [ShutoCoordinate] = []
    coordinates.append(
      contentsOf: stride(from: 0, to: route.coordinates.count, by: 8)
        .map { route.coordinates[$0] }
    )
    for leg in [model.accessRoute, model.egressRoute].compactMap({ $0 }) {
      coordinates.append(
        contentsOf: stride(from: 0, to: leg.coordinates.count, by: 8)
          .map { leg.coordinates[$0] }
      )
    }
    if let origin = model.origin {
      coordinates.append(origin.coordinate)
    }
    guard let first = coordinates.first else { return nil }
    var minLatitude = first.latitude
    var maxLatitude = first.latitude
    var minLongitude = first.longitude
    var maxLongitude = first.longitude
    for coordinate in coordinates.dropFirst() {
      minLatitude = min(minLatitude, coordinate.latitude)
      maxLatitude = max(maxLatitude, coordinate.latitude)
      minLongitude = min(minLongitude, coordinate.longitude)
      maxLongitude = max(maxLongitude, coordinate.longitude)
    }
    return MKCoordinateRegion(
      center: CLLocationCoordinate2D(
        latitude: (minLatitude + maxLatitude) / 2,
        longitude: (minLongitude + maxLongitude) / 2
      ),
      span: MKCoordinateSpan(
        latitudeDelta: max(0.02, (maxLatitude - minLatitude) * 1.35),
        longitudeDelta: max(0.02, (maxLongitude - minLongitude) * 1.35)
      )
    )
  }

  private func geographicDistance(
    _ first: ShutoCoordinate,
    _ second: ShutoCoordinate
  ) -> Double {
    CLLocation(
      latitude: first.latitude,
      longitude: first.longitude
    ).distance(
      from: CLLocation(
        latitude: second.latitude,
        longitude: second.longitude
      )
    )
  }
}

private struct WholeShutoMapMarker: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.system(size: 8, weight: .black))
      .foregroundStyle(Color.white)
      .frame(width: 25, height: 25)
      .background(color)
      .clipShape(Circle())
      .overlay {
        Circle().stroke(Color.white, lineWidth: 2)
      }
      .shadow(radius: 3)
  }
}

private struct WholeShutoFacilityLabel: View {
  let prefix: String
  let name: String
  let color: Color
  var darkText = false

  var body: some View {
    HStack(spacing: 3) {
      Text(prefix)
        .font(.system(size: 7, weight: .black, design: .rounded))
      Text(name)
        .font(.system(size: 8, weight: .black, design: .rounded))
        .lineLimit(1)
    }
    .foregroundStyle(darkText ? KaidoTheme.night : Color.white)
    .padding(.horizontal, 6)
    .frame(height: 20)
    .background(color)
    .clipShape(Capsule())
    .overlay {
      Capsule().stroke(Color.white.opacity(0.9), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.24), radius: 3, y: 1)
  }
}

private struct WholeShutoJunctionInset: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  let prompt: WholeShutoJunctionPrompt
  let distanceText: String?

  var body: some View {
    HStack(spacing: 12) {
      junctionGraphic
        .frame(width: 112, height: 92)

      VStack(alignment: .leading, spacing: 4) {
        Text(
          copy.resolve(
            japanese: "分岐に接近 · \(localizedJunctionName)",
            simplifiedChinese: "接近分岔 · \(localizedJunctionName)",
            english: "JUNCTION AHEAD · \(localizedJunctionName)"
          )
        )
        .font(.system(size: 14, weight: .bold, design: .rounded))
        .foregroundStyle(KaidoTheme.confirmedGreen)
        HStack(spacing: 6) {
          Text(shieldLabel(prompt.incomingRouteID))
            .junctionShield(color: routeColor(prompt.incomingRouteID))
          Image(systemName: "arrow.right")
            .font(.system(size: 9, weight: .black))
          Text(shieldLabel(prompt.outgoingRouteID))
            .junctionShield(color: routeColor(prompt.outgoingRouteID))
        }
        Text(verbatim: prompt.japaneseSignText)
          .font(.system(size: 17, weight: .bold, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .background(KaidoTheme.night.opacity(0.97))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(KaidoTheme.signalAmber.opacity(0.72), lineWidth: 1.5)
    }
    .shadow(color: .black.opacity(0.36), radius: 12, y: 5)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      accessibilitySummary
    )
    .accessibilityIdentifier("whole-shuto-junction-inset")
  }

  private var branchLabel: String {
    switch prompt.branchSide {
    case .left:
      copy.resolve(
        japanese: "左方向へ分岐",
        simplifiedChinese: "左分岔",
        english: "branch left"
      )
    case .right:
      copy.resolve(
        japanese: "右方向へ分岐",
        simplifiedChinese: "右分岔",
        english: "branch right"
      )
    case .straight:
      copy.resolve(
        japanese: "直進",
        simplifiedChinese: "直行",
        english: "continue straight"
      )
    }
  }

  private var laneGuidanceLabel: String {
    switch prompt.laneGuidanceState {
    case .notReleased:
      copy.resolve(
        japanese: "車線案内なし",
        simplifiedChinese: "暂无车道提示",
        english: "Lane guidance unavailable"
      )
    }
  }

  private var localizedJunctionName: String {
    prompt.localizedJunctionNames[interfaceLocale] ?? prompt.nameJA
  }

  private var localizedDisplayText: String {
    prompt.localizedContent[interfaceLocale]?.displayText
      ?? "\(branchLabel) · \(shieldLabel(prompt.outgoingRouteID))"
  }

  private var accessibilitySummary: String {
    let distance = distanceText.map { "\($0), " } ?? ""
    return copy.resolve(
      japanese:
        "\(distance)\(localizedJunctionName)、"
        + "\(shieldLabel(prompt.incomingRouteID))から\(branchLabel)、"
        + "\(localizedDisplayText)、日本語標識\(prompt.japaneseSignText)、"
        + laneGuidanceLabel,
      simplifiedChinese:
        "\(distance)\(localizedJunctionName)，"
        + "从\(shieldLabel(prompt.incomingRouteID))\(branchLabel)，"
        + "\(localizedDisplayText)，日文路牌\(prompt.japaneseSignText)，"
        + laneGuidanceLabel,
      english:
        "\(distance)\(localizedJunctionName), from "
        + "\(shieldLabel(prompt.incomingRouteID)), \(branchLabel), "
        + "\(localizedDisplayText), Japanese sign "
        + "\(prompt.japaneseSignText), \(laneGuidanceLabel)"
    )
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }

  private var junctionGraphic: some View {
    Canvas { context, size in
      let bottom = CGPoint(x: size.width / 2, y: size.height)
      let split = CGPoint(x: size.width / 2, y: size.height * 0.56)
      let left = CGPoint(x: size.width * 0.22, y: 12)
      let straight = CGPoint(x: size.width / 2, y: 10)
      let right = CGPoint(x: size.width * 0.78, y: 12)

      var approach = Path()
      approach.move(to: bottom)
      approach.addLine(to: split)
      context.stroke(
        approach,
        with: .color(KaidoTheme.signalAmber),
        style: StrokeStyle(lineWidth: 8, lineCap: .round)
      )

      func branchPath(to endpoint: CGPoint) -> Path {
        var path = Path()
        path.move(to: split)
        path.addCurve(
          to: endpoint,
          control1: CGPoint(
            x: split.x + (endpoint.x - split.x) * 0.18,
            y: size.height * 0.37
          ),
          control2: CGPoint(
            x: split.x + (endpoint.x - split.x) * 0.78,
            y: size.height * 0.25
          )
        )
        return path
      }

      let selectedEnd: CGPoint
      let alternativeEnds: [CGPoint]
      switch prompt.branchSide {
      case .left:
        selectedEnd = left
        alternativeEnds = [straight]
      case .right:
        selectedEnd = right
        alternativeEnds = [straight]
      case .straight:
        selectedEnd = straight
        alternativeEnds = [left, right]
      }
      for endpoint in alternativeEnds {
        context.stroke(
          branchPath(to: endpoint),
          with: .color(KaidoTheme.nightDivider),
          style: StrokeStyle(lineWidth: 7, lineCap: .round)
        )
      }
      context.stroke(
        branchPath(to: selectedEnd),
        with: .color(KaidoTheme.signalAmber),
        style: StrokeStyle(lineWidth: 8, lineCap: .round)
      )

      let routeCue = context.resolve(
        Text(shieldLabel(prompt.outgoingRouteID))
          .font(.system(size: 13, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
      )
      let cueFrame = CGRect(
        x: selectedEnd.x - 18,
        y: selectedEnd.y - 10,
        width: 36,
        height: 25
      )
      context.fill(
        Path(roundedRect: cueFrame, cornerRadius: 6),
        with: .color(routeColor(prompt.outgoingRouteID))
      )
      context.draw(
        routeCue,
        at: CGPoint(x: selectedEnd.x, y: selectedEnd.y + 2.5)
      )
    }
    .background(KaidoTheme.nightRaised)
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }
}

private struct WholeShutoSettingsView: View {
  @AppStorage(KaidoMapAppearance.preferenceKey) private var mapAppearance: KaidoMapAppearance = .automatic
  @ObservedObject var languageSettings: KaidoLanguageSettingsModel
  @ObservedObject var model: WholeShutoProductModel
  @ObservedObject var savedRoutes: SavedRouteLibraryModel
  let checkedAt: String
  let attribution: WholeShutoAttribution
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          Picker(copy.resolve(japanese: "地図の表示", simplifiedChinese: "地图外观", english: "Map appearance"), selection: $mapAppearance) {
            Text(copy.resolve(japanese: "自動", simplifiedChinese: "跟随系统", english: "Automatic")).tag(KaidoMapAppearance.automatic)
            Text(copy.resolve(japanese: "昼", simplifiedChinese: "日间", english: "Day")).tag(KaidoMapAppearance.day)
            Text(copy.resolve(japanese: "夜", simplifiedChinese: "夜间", english: "Night")).tag(KaidoMapAppearance.night)
          }
          .accessibilityIdentifier("whole-shuto-map-appearance")
        }
        Section {
          NavigationLink {
            WholeShutoLanguagePickerPage(
              title: copy.resolve(
                japanese: "画面表示",
                simplifiedChinese: "界面语言",
                english: "Interface language"
              ),
              selection: languageSettings.interfaceLocale,
              accessibilityPrefix: "whole-shuto-interface-language",
              onSelect: { languageSettings.selectInterfaceLocale($0) }
            )
          } label: {
            LabeledContent(
              copy.resolve(
                japanese: "画面表示",
                simplifiedChinese: "界面语言",
                english: "Interface"
              ),
              value: languageSettings.interfaceLocale.nativeLanguageName
            )
          }
          .accessibilityIdentifier("whole-shuto-interface-language")

          NavigationLink {
            WholeShutoLanguagePickerPage(
              title: copy.resolve(
                japanese: "音声案内",
                simplifiedChinese: "导航语音",
                english: "Guidance voice"
              ),
              selection: languageSettings.guidanceVoiceLocale,
              accessibilityPrefix: "whole-shuto-guidance-voice-language",
              onSelect: { languageSettings.selectGuidanceVoiceLocale($0) }
            )
          } label: {
            LabeledContent(
              copy.resolve(
                japanese: "音声案内",
                simplifiedChinese: "导航语音",
                english: "Guidance voice"
              ),
              value: languageSettings.guidanceVoiceLocale.nativeLanguageName
            )
          }
          .accessibilityIdentifier("whole-shuto-guidance-voice-language")
          NavigationLink {
            WholeShutoVoiceSettingsView(model: model, languages: languageSettings)
          } label: {
            Label(copy.resolve(japanese: "声と案内", simplifiedChinese: "声音与播报", english: "Voice and guidance"),
              systemImage: "speaker.wave.2")
          }
          .accessibilityIdentifier("whole-shuto-voice-settings")
          Text(
            copy.resolve(
              japanese: "一般道の曲がる方向は選択した言語で案内し、道路名は地図の原文を表示します。",
              simplifiedChinese: "普通道路的转向使用所选语言，路名保留地图原文供查看。",
              english:
                "Ordinary-road turns use the selected language. Street names remain visible in the original map instruction."
            )
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        } header: {
          Text(
            copy.resolve(
              japanese: "言語",
              simplifiedChinese: "语言",
              english: "Language"
            )
          )
        } footer: {
          Text(
            copy.resolve(
              japanese: "標識とルート番号は日本語のまま表示します。",
              simplifiedChinese: "路牌和路线编号仍显示日文。",
              english: "Road signs and route shields stay in Japanese."
            )
          )
        }

        Section {
          Picker(
            copy.resolve(
              japanese: "高速道路",
              simplifiedChinese: "高速道路",
              english: "Highways"
            ),
            selection: Binding(
              get: { model.surfaceRoutePreference },
              set: { model.setSurfaceRoutePreference($0) }
            )
          ) {
            Text(
              copy.resolve(
                japanese: "高速道路を優先",
                simplifiedChinese: "高速为主",
                english: "Prefer highways"
              )
            )
            .tag(WholeShutoSurfaceRoutePreference.preferHighways)
            .accessibilityIdentifier(
              "whole-shuto-surface-route-preference-prefer-highways"
            )

            Text(
              copy.resolve(
                japanese: "できるだけ避ける",
                simplifiedChinese: "尽量回避",
                english: "Avoid when possible"
              )
            )
            .tag(WholeShutoSurfaceRoutePreference.avoidHighways)
            .accessibilityIdentifier(
              "whole-shuto-surface-route-preference-avoid-highways"
            )
          }
          .accessibilityIdentifier(
            "whole-shuto-surface-route-preference"
          )
        } header: {
          Text(
            copy.resolve(
              japanese: "ルート案内",
              simplifiedChinese: "路线偏好",
              english: "Route preference"
            )
          )
        } footer: {
          Text(
            model.surfaceRoutePreference == .avoidHighways
              ? copy.resolve(
                japanese:
                  "選んだルート以外は、できるだけ一般道へ。",
                simplifiedChinese:
                  "保留所选路线，接驳尽量走普通道路。",
                english:
                  "Keep your route; prefer local roads for connections."
              )
              : copy.resolve(
                japanese: "近くの入口から高速道路へ。追加料金は別途。",
                simplifiedChinese: "优先就近上高速，额外通行费另计。",
                english: "Prefer a nearby highway entrance. Extra tolls may apply."
              )
          )
        }

        Section {
          Toggle(
            copy.resolve(
              japanese: "走行記録",
              simplifiedChinese: "行驶记录",
              english: "Drive record"
            ),
            isOn: Binding(
              get: { model.showsDriveRecord },
              set: { model.setShowsDriveRecord($0) }
            )
          )
          .accessibilityIdentifier("whole-shuto-drive-record-setting")
          NavigationLink {
            DriveHistoryView(model: model, savedRoutes: savedRoutes, locale: languageSettings.interfaceLocale)
          } label: {
            Label(copy.resolve(japanese: "走行履歴", simplifiedChinese: "行程记录", english: "Drive history"), systemImage: "clock.arrow.circlepath")
          }
        } footer: {
          Text(
            copy.resolve(
              japanese: "端末内に走行記録を保存します。オフにすると新しい記録を停止します。保存済みの記録は履歴から削除できます。",
              simplifiedChinese: "记录保存在本机。关闭后停止记录新行程，已存记录可在历史中删除。",
              english: "Records stay on this device. Turning this off stops new recording; saved records can be deleted in history."
            )
          )
        }

        // The map surface carries no source mark, so the required OSM
        // attribution and its licence text live here. Each limitation is a
        // scannable field rather than a paragraph a driver has to read.
        Section {
          Link(destination: attribution.sourceURL) {
            Label(attribution.attribution, systemImage: "map")
          }
          .accessibilityIdentifier(attribution.sourceAccessibilityIdentifier)

          NavigationLink {
            licenseDocument(
              text: ProductPrivacyDisclosure.mapDataLicenseText(),
              missing: copy.resolve(
                japanese: "地図データのライセンス文書を読み込めませんでした。",
                simplifiedChinese: "无法读取地图数据许可证文本。",
                english: "The map data license text could not be loaded."
              ),
              identifier: "whole-shuto-map-data-license-document"
            )
            .navigationTitle(
              copy.resolve(
                japanese: "地図データライセンス",
                simplifiedChinese: "地图数据许可证",
                english: "Map Data License"
              )
            )
          } label: {
            LabeledContent(
              copy.resolve(
                japanese: "ライセンス",
                simplifiedChinese: "许可",
                english: "Licence"
              ),
              value: attribution.licenceLabel
            )
          }
          .accessibilityIdentifier(attribution.licenceAccessibilityIdentifier)

          LabeledContent(
            copy.resolve(
              japanese: "データ",
              simplifiedChinese: "数据",
              english: "Data"
            ),
            value: copy.resolve(
              japanese: "事業者公式 · OSM 形状候補",
              simplifiedChinese: "运营方官方 · OSM 几何候选",
              english: "Operator official · OSM geometry"
            )
          )

          LabeledContent(
            copy.resolve(
              japanese: "未確認",
              simplifiedChinese: "未确认",
              english: "Unconfirmed"
            ),
            value: copy.resolve(
              japanese: "未審査分岐の音声 · 通行 · PA",
              simplifiedChinese: "未审核路口语音 · 通行 · PA",
              english: "Unreviewed junctions · passage · PA"
            )
          )
          .accessibilityIdentifier("whole-shuto-known-limitations")

          LabeledContent(
            copy.resolve(
              japanese: "確認日",
              simplifiedChinese: "确认日",
              english: "Checked"
            ),
            value: checkedAt
          )
        } header: {
          Text(
            copy.resolve(
              japanese: "この地図について",
              simplifiedChinese: "关于此地图",
              english: "About this map"
            )
          )
        }

        Section {
          LabeledContent(
            copy.resolve(
              japanese: "位置情報",
              simplifiedChinese: "定位",
              english: "Location"
            ),
            value: copy.resolve(
              japanese: "この端末のみ",
              simplifiedChinese: "仅本机处理",
              english: "On this device"
            )
          )
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("whole-shuto-location-privacy")

          Link(destination: ProductPrivacyDisclosure.policyURL) {
            Label(
              copy.resolve(
                japanese: "プライバシーポリシー",
                simplifiedChinese: "隐私政策",
                english: "Privacy Policy"
              ),
              systemImage: "hand.raised"
            )
          }
          .accessibilityIdentifier("whole-shuto-privacy-policy")

          NavigationLink {
            licenseDocument(
              text: ProductPrivacyDisclosure.sourceLicenseText(),
              missing: copy.resolve(
                japanese: "ライセンス文書を読み込めませんでした。",
                simplifiedChinese: "无法读取许可证文本。",
                english: "The license text could not be loaded."
              ),
              identifier: "whole-shuto-source-license-document"
            )
            .navigationTitle(
              copy.resolve(
                japanese: "オープンソースライセンス",
                simplifiedChinese: "开源许可证",
                english: "Open Source License"
              )
            )
          } label: {
            Label(
              copy.resolve(
                japanese: "オープンソースライセンス",
                simplifiedChinese: "开源许可证",
                english: "Open Source License"
              ),
              systemImage: "doc.text"
            )
          }
          .accessibilityIdentifier("whole-shuto-source-license")

          LabeledContent(
            copy.resolve(
              japanese: "バージョン",
              simplifiedChinese: "版本",
              english: "Version"
            ),
            value: ProductPrivacyDisclosure.versionDescription()
          )
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("whole-shuto-app-version")
          .accessibilityValue(
            ProductPrivacyDisclosure.versionDescription()
          )
        } header: {
          Text(
            copy.resolve(
              japanese: "プライバシーとアプリ",
              simplifiedChinese: "隐私与 App",
              english: "Privacy & app"
            )
          )
        }
      }
      .accessibilityIdentifier("whole-shuto-settings-form")
      .navigationTitle(
        copy.resolve(
          japanese: "設定",
          simplifiedChinese: "设置",
          english: "Settings"
        )
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(
            copy.resolve(
              japanese: "完了",
              simplifiedChinese: "完成",
              english: "Done"
            )
          ) {
            dismiss()
          }
          .accessibilityIdentifier("whole-shuto-settings-done")
        }
      }
    }
  }

  private func licenseDocument(
    text: String?,
    missing: String,
    identifier: String
  ) -> some View {
    ScrollView {
      Text(text ?? missing)
        .font(.footnote.monospaced())
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .accessibilityIdentifier(identifier)
    }
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: languageSettings.interfaceLocale)
  }
}

private struct WholeShutoLanguagePickerPage: View {
  let title: String
  let selection: KaidoReleaseLocale
  let accessibilityPrefix: String
  let onSelect: (KaidoReleaseLocale) -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

  var body: some View {
    List {
      ForEach(KaidoReleaseLocale.allCases, id: \.self) { locale in
        Button {
          onSelect(locale)
          dismiss()
        } label: {
          HStack {
            Text(locale.nativeLanguageName)
            Spacer()
            if locale == selection {
              Image(systemName: "checkmark")
                .fontWeight(.bold)
                .foregroundStyle(KaidoTheme.routeGreen)
            }
          }
        }
        .foregroundStyle(KaidoTheme.routeWhite)
        .accessibilityAddTraits(locale == selection ? .isSelected : [])
        .accessibilityIdentifier(
          "\(accessibilityPrefix)-\(locale.rawValue)"
        )
        .accessibilityValue(
          locale == selection
            ? copy.resolve(
              japanese: "選択中",
              simplifiedChinese: "已选择",
              english: "Selected"
            )
            : copy.resolve(
              japanese: "未選択",
              simplifiedChinese: "未选择",
              english: "Not selected"
            )
        )
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

extension Text {
  fileprivate func junctionShield(color: Color) -> some View {
    font(.system(size: 9, weight: .black, design: .rounded))
      .foregroundStyle(Color.white)
      .padding(.horizontal, 7)
      .frame(height: 22)
      .background(color)
      .clipShape(RoundedRectangle(cornerRadius: 5))
  }
}

extension ShutoCoordinate {
  fileprivate var mapCoordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
}

func shieldLabel(_ routeID: String) -> String {
  routeID
    .replacingOccurrences(of: "_HANEDA", with: "")
    .replacingOccurrences(of: "_UENO", with: "")
    .replacingOccurrences(of: "_MUKOJIMA", with: "")
    .replacingOccurrences(of: "_MISATO", with: "")
    .replacingOccurrences(of: "_YOKOHAMA_KITA", with: "")
    .replacingOccurrences(of: "_YOKOHAMA_HOKUSEI", with: "")
}

func routeDisplayLabel(
  _ routeID: String,
  in database: ShutoNetworkDatabase
) -> String {
  let shield = shieldLabel(routeID)
  guard
    let officialName = database.routes.first(where: {
      $0.routeID == routeID
    })?.officialNameJA
  else { return shield }
  return "\(shield) · \(officialName)"
}

/// Shield grounds, each dark enough that `KaidoTheme.routeWhite` route marks
/// clear 4.5:1 at the small sizes the shields are actually printed at. The
/// hues stay the operator's route families; the amber `7`/`10` ground moves
/// furthest because a highway-bright orange cannot carry light text.
func routeColor(_ routeID: String) -> Color {
  switch routeID {
  case "C1", "1_HANEDA", "1_UENO", "5", "S1", "S2", "S5":
    return Color(hex: 0x2670AD)
  case "C2", "6_MUKOJIMA", "6_MISATO", "K6":
    return Color(hex: 0x297A55)
  case "B", "9", "11", "K5":
    return Color(hex: 0x7B5FA4)
  case "3", "K1", "K2", "K3":
    return Color(hex: 0x34658D)
  case "4", "K7_YOKOHAMA_KITA", "K7_YOKOHAMA_HOKUSEI":
    return Color(hex: 0xBE4238)
  case "7", "10":
    return Color(hex: 0x966122)
  case "2":
    return Color(hex: 0x7C5E99)
  default:
    return KaidoTheme.routeGreen
  }
}
