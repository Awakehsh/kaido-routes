import CoreLocation
import KaidoAppleAdapters
import KaidoDomain
import KaidoRouting
import MapKit
import SwiftUI

private enum WholeShutoPlanningField: Hashable {
  case origin
  case destination
}

struct WholeShutoProductView: View {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var model: WholeShutoProductModel
  @StateObject private var languageSettings: KaidoLanguageSettingsModel
  @StateObject private var planningLocation: WholeShutoPlanningLocationController
  @StateObject private var placeSearch: WholeShutoPlaceSearchController
  @State private var showsNetworkFacts = false
  @State private var showsLanguageSettings = false
  @State private var showsRouteCustomization = false
  @State private var showsManualOrigin = false
  @State private var waitsForPlanningLocation = false
  @State private var showsEndJourneyConfirmation = false
  @State private var resumesAfterEndJourneyCancellation = false
  @FocusState private var focusedPlanningField: WholeShutoPlanningField?

  init(
    model: WholeShutoProductModel? = nil,
    languageSettings: KaidoLanguageSettingsModel? = nil,
    planningLocation: WholeShutoPlanningLocationController? = nil,
    placeSearch: WholeShutoPlaceSearchController? = nil
  ) {
    _model = StateObject(
      wrappedValue: model ?? WholeShutoProductModel()
    )
    _languageSettings = StateObject(
      wrappedValue: languageSettings ?? KaidoLanguageSettingsModel()
    )
    _planningLocation = StateObject(
      wrappedValue:
        planningLocation ?? WholeShutoPlanningLocationController()
    )
    _placeSearch = StateObject(
      wrappedValue: placeSearch ?? WholeShutoPlaceSearchController()
    )
  }

  var body: some View {
    ZStack {
      map
        .ignoresSafeArea()

      VStack(spacing: 0) {
        topBar
        Spacer(minLength: 0)

        if model.phase == .completed {
          arrivalDock
        } else if isDriving {
          drivingDock
        } else {
          planningDock
        }
      }

      if let prompt = model.activeJunctionPrompt {
        VStack {
          Spacer()
          WholeShutoJunctionInset(prompt: prompt)
            .padding(.horizontal, 14)
            .padding(.bottom, 142)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .allowsHitTesting(false)
      }
    }
    .animation(.easeOut(duration: 0.22), value: model.phase)
    .animation(
      .easeOut(duration: 0.22),
      value: model.activeJunctionPrompt
    )
    .preferredColorScheme(isDriving ? .dark : .light)
    .sheet(isPresented: $showsRouteCustomization) {
      WholeShutoCustomRouteSheet(model: model)
    }
    .sheet(isPresented: $showsNetworkFacts) {
      WholeShutoNetworkFactsView(model: model)
    }
    .sheet(isPresented: $showsLanguageSettings) {
      WholeShutoLanguageSettingsView(model: languageSettings)
    }
    .alert(
      copy.resolve(
        japanese: "プレビューを終了しますか？",
        simplifiedChinese: "结束本次预演？",
        english: "End this preview?"
      ),
      isPresented: $showsEndJourneyConfirmation
    ) {
      Button(
        copy.resolve(
          japanese: "続ける",
          simplifiedChinese: "继续预演",
          english: "Continue preview"
        ),
        role: .cancel
      ) {
        resumeAfterEndJourneyCancellation()
      }
      Button(
        copy.resolve(
          japanese: "プレビューを終了",
          simplifiedChinese: "结束预演",
          english: "End preview"
        ),
        role: .destructive
      ) {
        resumesAfterEndJourneyCancellation = false
        model.reset()
      }
    } message: {
      Text(
        copy.resolve(
          japanese: "現在の進行状況は破棄され、ルート検索に戻ります。",
          simplifiedChinese: "当前行程进度将被清除，并返回路线规划。",
          english:
            "Current journey progress will be cleared and route planning will reopen."
        )
      )
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("whole-shuto-product")
    .accessibilityValue(model.phase.rawValue)
    .environment(
      \.kaidoInterfaceLocale,
      languageSettings.interfaceLocale
    )
    .onChange(of: scenePhase, initial: true) { _, newPhase in
      model.handleScenePhase(newPhase.productRuntimePhase)
      planningLocation.setForeground(newPhase == .active && !isDriving)
    }
    .onChange(of: isDriving) { _, newValue in
      planningLocation.setForeground(scenePhase == .active && !newValue)
    }
    .onChange(of: model.destinationQuery, initial: true) {
      updateDestinationSearch()
    }
    .onChange(of: focusedPlanningField) { _, newField in
      if newField == .destination {
        updateDestinationSearch()
      } else {
        placeSearch.dismissResults()
      }
    }
    .onChange(of: planningLocation.snapshot?.coordinate.latitude) {
      handlePlanningLocationUpdate()
      updateDestinationSearch()
    }
    .onChange(of: planningLocation.snapshot?.coordinate.longitude) {
      handlePlanningLocationUpdate()
      updateDestinationSearch()
    }
    .onChange(of: planningLocation.state) {
      handlePlanningLocationUpdate()
    }
  }

  @ViewBuilder
  private var map: some View {
    if model.mapMode == .network {
      WholeShutoNetworkDiagram(
        database: model.database,
        selectedRoute: model.selectedRoute,
        currentCoordinate: isDriving ? model.currentCoordinate : nil,
        usesDarkStyle: isDriving,
        visibleBottomFraction:
          isDriving ? 0.92 : 0.66
      )
    } else {
      WholeShutoGeographicMap(
        model: model,
        planningLocation: planningLocation.snapshot
      )
    }
  }

  private var topBar: some View {
    VStack(spacing: 8) {
      HStack(spacing: 10) {
        if model.phase != .planning && model.phase != .completed {
          Button {
            if isActiveNavigation {
              requestEndJourney()
            } else {
              model.reset()
            }
          } label: {
            Image(
              systemName: isActiveNavigation ? "xmark" : "chevron.left"
            )
              .font(.system(size: 14, weight: .black))
              .frame(width: 38, height: 38)
          }
          .buttonStyle(WholeShutoCircleButtonStyle(isDriving: isDriving))
          .accessibilityLabel(
            isActiveNavigation
              ? copy.resolve(
                japanese: "プレビューを終了",
                simplifiedChinese: "结束预演",
                english: "End preview"
              )
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
        }

        VStack(alignment: .leading, spacing: 0) {
          Text("KAIDO")
            .font(.system(size: 9, weight: .black, design: .rounded))
            .tracking(1.7)
            .foregroundStyle(
              isDriving ? KaidoTheme.confirmedGreen : KaidoTheme.routeGreen
            )
          Text(topTitle)
            .font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundStyle(
              isDriving ? KaidoTheme.routeWhite : KaidoTheme.ink
            )
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }

        Spacer()

        mapModeControl

        if !isDriving {
          Button {
            showsLanguageSettings = true
          } label: {
            Image(systemName: "globe")
              .font(.system(size: 14, weight: .black))
              .frame(width: 38, height: 38)
          }
          .buttonStyle(WholeShutoCircleButtonStyle(isDriving: false))
          .accessibilityLabel(
            copy.resolve(
              japanese: "言語設定",
              simplifiedChinese: "语言设置",
              english: "Language settings"
            )
          )
          .accessibilityIdentifier("whole-shuto-language-settings")

          Button {
            showsNetworkFacts = true
          } label: {
            Image(systemName: "info")
              .font(.system(size: 14, weight: .black))
              .frame(width: 38, height: 38)
          }
          .buttonStyle(WholeShutoCircleButtonStyle(isDriving: false))
          .accessibilityLabel(
            copy.resolve(
              japanese: "首都高全体データについて",
              simplifiedChinese: "全网数据说明",
              english: "Whole-network data information"
            )
          )
        }
      }

      if isActiveNavigation {
        instructionBanner
      }
    }
    .padding(.horizontal, 14)
    .padding(.top, 7)
  }

  private var mapModeControl: some View {
    HStack(spacing: 0) {
      mapModeButton(
        .geographic,
        symbol: "map.fill",
        label: copy.resolve(
          japanese: "地図",
          simplifiedChinese: "地图",
          english: "MAP"
        )
      )
      mapModeButton(
        .network,
        symbol: "point.3.connected.trianglepath.dotted",
        label: copy.resolve(
          japanese: "全体",
          simplifiedChinese: "全网",
          english: "NET"
        )
      )
    }
    .padding(3)
    .background(
      isDriving
        ? KaidoTheme.instrument.opacity(0.94)
        : KaidoTheme.paperRaised.opacity(0.96)
    )
    .clipShape(Capsule())
    .overlay {
      Capsule()
        .stroke(
          isDriving ? KaidoTheme.steel : KaidoTheme.paperDivider,
          lineWidth: 1
        )
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
          .font(.system(size: 10, weight: .black))
        Text(label)
          .font(.system(size: 9, weight: .black, design: .rounded))
      }
      .foregroundStyle(
        model.mapMode == mode
          ? KaidoTheme.routeWhite
          : isDriving ? KaidoTheme.muted : KaidoTheme.quietText
      )
      .padding(.horizontal, 9)
      .frame(height: 30)
      .background(
        model.mapMode == mode
          ? KaidoTheme.routeGreen
          : Color.clear
      )
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("whole-shuto-map-\(mode.rawValue.lowercased())")
  }

  private var planningDock: some View {
    VStack(spacing: 0) {
      if model.phase == .planning {
        routeComposer
      } else {
        routeReview
      }
    }
    .background(.ultraThinMaterial)
    .clipShape(
      UnevenRoundedRectangle(
        topLeadingRadius: 20,
        topTrailingRadius: 20
      )
    )
    .overlay(alignment: .top) {
      Capsule()
        .fill(KaidoTheme.roadGray.opacity(0.65))
        .frame(width: 36, height: 4)
        .padding(.top, 8)
    }
    .shadow(color: .black.opacity(0.16), radius: 18, y: -3)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("whole-shuto-planning-dock")
  }

  private var routeComposer: some View {
    VStack(spacing: 12) {
      journeySearchComposer

      routeFailureBanner
    }
    .padding(.horizontal, 16)
    .padding(.top, 22)
    .padding(.bottom, 14)
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
        .background(KaidoTheme.paperRaised.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
          RoundedRectangle(cornerRadius: 12)
            .stroke(KaidoTheme.paperDivider, lineWidth: 1)
        }
      }

      destinationSearchResults

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
        .background(KaidoTheme.paperRaised.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
          RoundedRectangle(cornerRadius: 12)
            .stroke(KaidoTheme.paperDivider, lineWidth: 1)
        }
      }

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
  private var destinationSearchResults: some View {
    if focusedPlanningField == .destination {
      switch placeSearch.state {
      case .searching, .resolving:
        HStack(spacing: 8) {
          ProgressView()
          Text(
            placeSearch.state == .resolving
              ? copy.resolve(
                japanese: "目的地を確認中",
                simplifiedChinese: "正在确认目的地",
                english: "Confirming destination"
              )
              : copy.resolve(
                japanese: "検索中",
                simplifiedChinese: "正在搜索",
                english: "Searching"
              )
          )
          Spacer()
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(KaidoTheme.quietText)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .accessibilityIdentifier("whole-shuto-place-search-progress")
      case .results:
        VStack(spacing: 0) {
          ForEach(placeSearch.suggestions.prefix(4)) { suggestion in
            Button {
              selectDestinationSuggestion(suggestion)
            } label: {
              HStack(spacing: 10) {
                Image(systemName: "mappin")
                  .font(.system(size: 11, weight: .bold))
                  .foregroundStyle(KaidoTheme.routeGreen)
                  .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                  Text(suggestion.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(KaidoTheme.ink)
                    .lineLimit(1)
                  if !suggestion.subtitle.isEmpty {
                    Text(suggestion.subtitle)
                      .font(.system(size: 9, weight: .medium))
                      .foregroundStyle(KaidoTheme.quietText)
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

            if suggestion.id != placeSearch.suggestions.prefix(4).last?.id {
              Divider()
                .padding(.leading, 44)
            }
          }
        }
        .background(KaidoTheme.paperRaised.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
          RoundedRectangle(cornerRadius: 12)
            .stroke(KaidoTheme.paperDivider, lineWidth: 1)
        }
      case .unavailable:
        HStack(spacing: 7) {
          Image(systemName: "wifi.exclamationmark")
          Text(
            copy.resolve(
              japanese: "候補を取得できません。入力した名称で検索できます",
              simplifiedChinese: "暂时无法获取建议，仍可按输入名称查找",
              english: "Suggestions unavailable. Search the entered name"
            )
          )
          Spacer()
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(KaidoTheme.signalAmber)
        .accessibilityIdentifier("whole-shuto-place-search-unavailable")
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
          : KaidoTheme.paperRaised.opacity(0.94)
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
    let hasDestination = !model.destinationQuery.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).isEmpty
    let hasRequiredManualOrigin =
      !(showsManualOrigin
        || planningLocation.state == .denied
        || planningLocation.state == .unavailable)
      || !model.originQuery.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
    return hasDestination
      && hasRequiredManualOrigin
      && !model.isPlanning
      && !waitsForPlanningLocation
  }

  private func beginRoutePlanning() {
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
      guard waitsForPlanningLocation else { return }
      waitsForPlanningLocation = false
      model.planJourney()
      return
    }

    guard waitsForPlanningLocation else { return }
    switch planningLocation.state {
    case .denied, .unavailable:
      waitsForPlanningLocation = false
      showsManualOrigin = true
      focusedPlanningField = .origin
    case .idle, .permissionRequired, .locating, .measured:
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
          .foregroundStyle(KaidoTheme.quietText)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        TextField(prompt, text: text)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(KaidoTheme.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .textInputAutocapitalization(.never)
          .focused($focusedPlanningField, equals: focus)
          .submitLabel(focus == .destination ? .route : .next)
          .onSubmit {
            if focus == .origin {
              focusedPlanningField = .destination
            } else if !model.destinationQuery.isEmpty {
              model.planJourney()
            }
          }
      }
    }
    .frame(height: 52)
    .accessibilityIdentifier(accessibilityIdentifier)
  }

  private var routeReview: some View {
    VStack(spacing: 11) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(routeSummaryTitle)
            .font(.system(size: 19, weight: .black, design: .rounded))
          Text(routeSummarySubtitle)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(KaidoTheme.quietText)
        }
        Spacer()
        Text(distanceLabel(model.selectedRoute?.distanceMeters ?? 0))
          .font(.system(size: 20, weight: .black, design: .rounded))
      }
      .foregroundStyle(KaidoTheme.ink)

      routeSelection

      HStack(spacing: 8) {
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
        routeBoundary(
          title: model.selectedRoute?.exitFacility.nameJA ?? "—",
          detail: (model.selectedRoute?.exitFacility.exitDirections ?? [])
            .joined(separator: " / "),
          label: copy.resolve(
            japanese: "出口",
            simplifiedChinese: "出口",
            english: "EXIT"
          ),
          tint: KaidoTheme.evidenceCoral
        )
      }

      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(
            copy.resolve(
              japanese: "現在の通行状況",
              simplifiedChinese: "当前通行状态",
              english: "CURRENT PASSAGE STATUS"
            )
          )
          .font(.system(size: 8, weight: .black))
          Text(
            copy.resolve(
              japanese: "リアルタイム未確認 · 出発前に確認してください",
              simplifiedChinese: "尚未连接实时路况 · 出发前需确认",
              english: "Realtime unconfirmed · Check before departure"
            )
          )
          .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(KaidoTheme.signalAmber)
        Spacer()
        Button {
          model.startNavigationSimulation()
        } label: {
          HStack(spacing: 8) {
            if model.isUpdatingSurfaceRoute {
              ProgressView()
                .tint(KaidoTheme.routeWhite)
              Text(
                copy.resolve(
                  japanese: "ルートを確認中",
                  simplifiedChinese: "正在确认路线",
                  english: "CONFIRMING ROUTE"
                )
              )
            } else {
              Text(
                copy.resolve(
                  japanese: "全行程をプレビュー",
                  simplifiedChinese: "开始完整预演",
                  english: "PREVIEW FULL JOURNEY"
                )
              )
              Image(systemName: "play.fill")
            }
          }
          .font(.system(size: 12, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
          .padding(.horizontal, 15)
          .frame(height: 45)
          .background(KaidoTheme.routeGreen)
          .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(model.isUpdatingSurfaceRoute)
        .opacity(model.isUpdatingSurfaceRoute ? 0.78 : 1)
        .accessibilityIdentifier("whole-shuto-start-simulation")
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 22)
    .padding(.bottom, 12)
  }

  private var routeSelection: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal) {
        HStack(spacing: 7) {
          if !model.recommendations.isEmpty {
            routeSelectionButton(at: 0)
              .id(routeSelectionScrollID(at: 0))
          }

          routeCustomizationButton
            .id("whole-shuto-route-customization-choice")

          ForEach(
            model.recommendations.indices.dropFirst(),
            id: \.self
          ) { index in
            routeSelectionButton(at: index)
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

  private func routeSelectionScrollID(at index: Int) -> String {
    "whole-shuto-route-choice-\(index)"
  }

  private var routeCustomizationButton: some View {
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
        .font(.system(size: 9, weight: .black))
        Text(customRouteCardDetail)
          .font(.system(size: 10, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.72)
      }
      .foregroundStyle(
        model.isCustomRouteSelected
          ? KaidoTheme.routeWhite : KaidoTheme.ink
      )
      .padding(.horizontal, 12)
      .frame(width: 124, height: 68, alignment: .leading)
      .background(
        model.isCustomRouteSelected
          ? KaidoTheme.routeGreenDeep : KaidoTheme.paperRaised
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

  private func routeSelectionButton(at index: Int) -> some View {
    Button {
      showsRouteCustomization = false
      model.selectRecommendation(at: index)
    } label: {
      let route = model.recommendations[index].route
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
        .font(.system(size: 9, weight: .black))
        Text(
          route.routeIDsInOrder
            .map(shieldLabel)
            .joined(separator: " · ")
        )
        .font(.system(size: 11, weight: .black, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.56)
        HStack(spacing: 4) {
          Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
            .font(.system(size: 8, weight: .black))
          Text(distanceLabel(route.distanceMeters))
            .font(.system(size: 10, weight: .bold))
        }
      }
      .foregroundStyle(
        isSelected
          ? KaidoTheme.routeWhite
          : KaidoTheme.ink
      )
      .padding(.horizontal, 12)
      .frame(width: 150, height: 68, alignment: .leading)
      .background(
        isSelected
          ? KaidoTheme.routeGreen
          : KaidoTheme.paperRaised
      )
      .clipShape(RoundedRectangle(cornerRadius: 9))
    }
    .buttonStyle(.plain)
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
          .font(.system(size: 11, weight: .black, design: .rounded))
          .lineLimit(1)
        Text(
          detail.isEmpty
            ? copy.resolve(
              japanese: "進行方向はルートで確定",
              simplifiedChinese: "方向由路线确定",
              english: "Direction fixed by route"
            )
            : detail
        )
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(KaidoTheme.quietText)
        .lineLimit(1)
      }
    }
    .foregroundStyle(KaidoTheme.ink)
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
    .background(KaidoTheme.paperRaised.opacity(0.88))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private var drivingDock: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Circle()
            .fill(positionStatusColor)
            .frame(width: 7, height: 7)
          Text(positionStatusLabel)
            .font(.system(size: 8, weight: .black, design: .rounded))
            .foregroundStyle(positionStatusColor)
            .accessibilityIdentifier("whole-shuto-position-state")
            .accessibilityValue(model.positionState.rawValue)
        }
        Text(drivingDistanceLabel)
          .font(.system(size: 20, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
        HStack(spacing: 6) {
          Text(journeyRemainingLabel)
            .accessibilityIdentifier("whole-shuto-journey-remaining")
          if let nextJunctionDistanceLabel {
            Text("·")
            Text(nextJunctionDistanceLabel)
              .accessibilityIdentifier("whole-shuto-next-junction")
          }
        }
        .font(.system(size: 9, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.confirmedGreen)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        Text(drivingBoundaryLabel)
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(KaidoTheme.muted)
          .lineLimit(1)
      }

      Spacer(minLength: 4)

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
        model.togglePlayback()
      } label: {
        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 15, weight: .black))
          .frame(width: 48, height: 48)
          .foregroundStyle(KaidoTheme.asphalt)
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
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(KaidoTheme.asphalt.opacity(0.96))
    .overlay(alignment: .top) {
      Rectangle()
        .fill(KaidoTheme.steel)
        .frame(height: 1)
    }
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
            .foregroundStyle(KaidoTheme.asphalt)
        }

        VStack(alignment: .leading, spacing: 2) {
          Text(
            copy.resolve(
              japanese: "全行程プレビュー完了",
              simplifiedChinese: "完整行程预演完成",
              english: "FULL JOURNEY PREVIEW COMPLETE"
            )
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
          .foregroundStyle(KaidoTheme.muted)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        Spacer()
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
        .foregroundStyle(KaidoTheme.asphalt)
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
    .background(KaidoTheme.asphalt.opacity(0.97))
    .overlay(alignment: .top) {
      Rectangle()
        .fill(KaidoTheme.steel)
        .frame(height: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("whole-shuto-arrival-dock")
  }

  private var instructionBanner: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 9)
          .fill(KaidoTheme.routeGreen)
          .frame(width: 48, height: 48)
        Image(systemName: instructionSymbol)
          .font(.system(size: 22, weight: .black))
          .foregroundStyle(KaidoTheme.routeWhite)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(instructionKicker)
          .font(.system(size: 8, weight: .black, design: .rounded))
          .tracking(0.5)
          .foregroundStyle(KaidoTheme.confirmedGreen)
        Text(instructionTitle)
          .font(.system(size: 16, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
          .lineLimit(2)
      }
      Spacer()
      Image(systemName: speechStatusSymbol)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(
          speechStatusIsBlocked
            ? KaidoTheme.signalAmber
            : KaidoTheme.routeWhite
        )
        .accessibilityIdentifier("whole-shuto-guidance-speech")
        .accessibilityLabel(
          copy.resolve(
            japanese: "音声案内",
            simplifiedChinese: "导航语音",
            english: "Guidance voice"
          )
        )
        .accessibilityValue(speechStatusLabel)
      if let routeID = activeRouteShield {
        Text(shieldLabel(routeID))
          .font(.system(size: 12, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
          .frame(minWidth: 38, minHeight: 30)
          .background(routeColor(routeID))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
    }
    .padding(8)
    .background(KaidoTheme.asphalt.opacity(0.94))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(KaidoTheme.steel, lineWidth: 1)
    }
  }

  private var isDriving: Bool {
    ![.planning, .review].contains(model.phase)
  }

  private var isActiveNavigation: Bool {
    isDriving && model.phase != .completed
  }

  private func requestEndJourney() {
    resumesAfterEndJourneyCancellation = model.isPlaying
    if model.isPlaying {
      model.togglePlayback()
    }
    showsEndJourneyConfirmation = true
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
    model.togglePlayback()
  }

  private var topTitle: String {
    if model.phase == .completed {
      return copy.resolve(
        japanese: "行程完了",
        simplifiedChinese: "行程完成",
        english: "JOURNEY COMPLETE"
      )
    }
    if isDriving {
      return copy.resolve(
        japanese: "首都高ナビプレビュー",
        simplifiedChinese: "首都高导航预演",
        english: "SHUTO NAVIGATION PREVIEW"
      )
    }
    return model.phase == .review
      ? copy.resolve(
        japanese: "ルート確認",
        simplifiedChinese: "路线确认",
        english: "ROUTE REVIEW"
      )
      : copy.resolve(
        japanese: "首都高全体",
        simplifiedChinese: "首都高全网",
        english: "WHOLE SHUTO"
      )
  }

  private var routeSummaryTitle: String {
    guard let route = model.selectedRoute else {
      return copy.resolve(
        japanese: "ルート",
        simplifiedChinese: "路线",
        english: "ROUTE"
      )
    }
    return route.routeIDsInOrder
      .map(shieldLabel)
      .joined(separator: "  →  ")
  }

  private var routeSummarySubtitle: String {
    guard let route = model.selectedRoute else { return "" }
    return
      "\(entryName(route.entryFacility.nameJA)) → "
      + exitName(route.exitFacility.nameJA)
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
      + distanceLabel(route.distanceMeters)
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
      customRouteCardDetail + "; " + distanceLabel(route.distanceMeters)
  }

  private var instructionSymbol: String {
    switch model.phase {
    case .surfaceAccess: "arrow.turn.up.right"
    case .entryTransition: "arrow.up.right"
    case .expressway:
      model.activeJunctionPrompt == nil
        ? "arrow.up" : "arrow.triangle.branch"
    case .exitTransition: "arrow.up.right"
    case .surfaceEgress: "arrow.turn.up.left"
    case .completed: "checkmark"
    case .planning, .review: "map"
    }
  }

  private var instructionKicker: String {
    switch model.phase {
    case .surfaceAccess:
      copy.resolve(
        japanese: "一般道 · 入口へ",
        simplifiedChinese: "一般道路 · 前往入口",
        english: "SURFACE ROAD · TO ENTRY"
      )
    case .entryTransition:
      copy.resolve(
        japanese: "首都高へ進入",
        simplifiedChinese: "进入首都高",
        english: "ENTER SHUTO EXPRESSWAY"
      )
    case .expressway:
      model.activeJunctionPrompt == nil
        ? upcomingJunctionKicker
        : copy.resolve(
          japanese: "分岐に接近",
          simplifiedChinese: "接近分岔",
          english: "JUNCTION AHEAD"
        )
    case .exitTransition:
      copy.resolve(
        japanese: "首都高を退出",
        simplifiedChinese: "驶出首都高",
        english: "EXIT SHUTO EXPRESSWAY"
      )
    case .surfaceEgress:
      copy.resolve(
        japanese: "一般道 · 目的地へ",
        simplifiedChinese: "一般道路 · 前往目的地",
        english: "SURFACE ROAD · TO DESTINATION"
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
    guard let route = model.selectedRoute else { return "" }
    switch model.phase {
    case .surfaceAccess:
      return copy.resolve(
        japanese: "\(entryName(route.entryFacility.nameJA))へ進む",
        simplifiedChinese: "前往 \(entryName(route.entryFacility.nameJA))",
        english: "Continue to \(entryName(route.entryFacility.nameJA))"
      )
    case .entryTransition:
      let routeLabel =
        route.routeIDsInOrder.first.map(shieldLabel)
        ?? copy.resolve(
          japanese: "首都高",
          simplifiedChinese: "首都高",
          english: "Shuto Expressway"
        )
      return copy.resolve(
        japanese: "\(route.entryFacility.nameJA)から \(routeLabel) へ",
        simplifiedChinese:
          "从 \(route.entryFacility.nameJA) 进入 \(routeLabel)",
        english: "Enter \(routeLabel) from \(route.entryFacility.nameJA)"
      )
    case .expressway:
      if let prompt = model.activeJunctionPrompt {
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
        japanese: "\(exitName(route.exitFacility.nameJA))から退出",
        simplifiedChinese: "从 \(exitName(route.exitFacility.nameJA))驶出",
        english: "Leave from \(exitName(route.exitFacility.nameJA))"
      )
    case .surfaceEgress:
      let destination =
        model.destination?.title
        ?? copy.resolve(
          japanese: "目的地",
          simplifiedChinese: "目的地",
          english: "destination"
        )
      return copy.resolve(
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

  private var activeRouteShield: String? {
    if let prompt = model.activeJunctionPrompt {
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
    case .surfacePreview:
      return prefix
        + copy.resolve(
          japanese: "MapKit 一般道 · プレビュー",
          simplifiedChinese: "MapKit 一般道路 · 预演",
          english: "MAPKIT SURFACE ROAD · PREVIEW"
        )
    case .boundaryTransition:
      return prefix
        + copy.resolve(
          japanese: "境界移行 · プレビュー",
          simplifiedChinese: "边界转换 · 预演",
          english: "BOUNDARY TRANSITION · PREVIEW"
        )
    case .networkPreview:
      return prefix
        + copy.resolve(
          japanese: "ルート再生 · 模擬 \(simulationReplayParametersLabel)",
          simplifiedChinese: "路线回放 · 模拟 \(simulationReplayParametersLabel)",
          english: "ROUTE REPLAY · SIMULATED \(simulationReplayParametersLabel)"
        )
    case .networkDegraded:
      return prefix
        + copy.resolve(
          japanese: "位置証拠不足 · 進行停止",
          simplifiedChinese: "定位证据不足 · 未推进",
          english: "INSUFFICIENT POSITION EVIDENCE · HELD"
        )
    case .tunnelEstimated:
      return prefix
        + copy.resolve(
          japanese: "トンネル位置推定 · 模擬 \(simulationReplayParametersLabel)",
          simplifiedChinese: "隧道位置推算 · 模拟 \(simulationReplayParametersLabel)",
          english: "TUNNEL ESTIMATE · SIMULATED \(simulationReplayParametersLabel)"
        )
    case .routeInterrupted:
      return prefix
        + copy.resolve(
          japanese: "ルート中断 · 公開済み復帰ルートなし",
          simplifiedChinese: "路线中断 · 无已发布重入路线",
          english: "ROUTE INTERRUPTED · NO RELEASED REENTRY"
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
    switch model.speechStatus {
    case .scheduled, .speaking:
      "speaker.wave.2.fill"
    case .interrupted, .failed, .invalidProjection:
      "speaker.slash.fill"
    case .idle, .suppressed, .stopped:
      "speaker.fill"
    }
  }

  private var speechStatusLabel: String {
    switch model.speechStatus {
    case .idle:
      model.hasConsumedActiveGuidancePrompt
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
    default:
      return KaidoTheme.positionCyan
    }
  }

  private var drivingDistanceLabel: String {
    guard let route = model.selectedRoute else { return "—" }
    switch model.phase {
    case .surfaceAccess:
      return distanceLabel(
        (model.accessRoute?.distanceMeters ?? 0)
          * (1 - model.progressFraction)
      )
    case .entryTransition:
      let routeLabel = route.routeIDsInOrder.first.map(shieldLabel) ?? ""
      return copy.resolve(
        japanese: "\(routeLabel)へ進入",
        simplifiedChinese: "进入 \(routeLabel)",
        english: "ENTER \(routeLabel)"
      )
    case .expressway:
      return distanceLabel(
        route.distanceMeters * (1 - model.progressFraction)
      )
    case .exitTransition:
      return exitName(route.exitFacility.nameJA)
    case .surfaceEgress:
      return distanceLabel(
        (model.egressRoute?.distanceMeters ?? 0)
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

  private var drivingBoundaryLabel: String {
    guard let route = model.selectedRoute else { return "" }
    return
      "\(entryName(route.entryFacility.nameJA)) → "
      + exitName(route.exitFacility.nameJA)
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
    guard
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
    case .denied, .unavailable:
      "location.slash"
    case .idle, .permissionRequired:
      "location"
    }
  }

  private func updateDestinationSearch() {
    guard
      model.phase == .planning,
      focusedPlanningField == .destination
    else {
      placeSearch.dismissResults()
      return
    }
    if model.hasSelectedDestinationPreview {
      placeSearch.dismissResults()
      return
    }
    if model.destination != nil {
      model.clearDestinationPreview()
    }
    placeSearch.clearSelection()
    placeSearch.update(
      query: model.destinationQuery,
      near: planningLocation.snapshot?.coordinate
    )
  }

  private func selectDestinationSuggestion(
    _ suggestion: WholeShutoPlaceSuggestion
  ) {
    Task {
      do {
        let place = try await placeSearch.resolve(suggestion)
        model.selectDestinationPreview(place)
        focusedPlanningField = nil
      } catch {
        // The typed query remains available for the normal route-search path.
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
    default:
      copy.resolve(
        japanese: "現在地を使用",
        simplifiedChinese: "使用当前位置",
        english: "Use current location"
      )
    }
  }

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
        japanese: "進行方向が有効な首都高ルートが見つかりません",
        simplifiedChinese: "未找到方向合法的首都高路线",
        english: "No direction-valid Shuto route found"
      )
    default:
      return copy.resolve(
        japanese: "場所またはルートを解決できません",
        simplifiedChinese: "地点或路线暂时无法解析",
        english: "Place or route could not be resolved"
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
            identifierPrefix: "whole-shuto-custom-entry"
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
            identifierPrefix: "whole-shuto-custom-exit"
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
    .background(KaidoTheme.paper)
    .presentationDetents([.height(520), .large])
    .presentationDragIndicator(.hidden)
    .presentationCornerRadius(26)
    .presentationBackground(KaidoTheme.paper)
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
        .foregroundStyle(KaidoTheme.ink)

        Text(
          copy.resolve(
            japanese: "進行方向が有効な入口・出口とルート傾向を選択",
            simplifiedChinese: "选择方向合法的入口、出口和路线取向",
            english: "Choose a direction-valid entry, exit, and route style"
          )
        )
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(KaidoTheme.quietText)
      }

      Spacer()

      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .black))
          .foregroundStyle(KaidoTheme.ink)
          .frame(width: 36, height: 36)
          .background(KaidoTheme.paperRaised)
          .clipShape(Circle())
          .overlay {
            Circle()
              .stroke(KaidoTheme.paperDivider, lineWidth: 1)
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
    .background(KaidoTheme.paperRaised)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(KaidoTheme.paperDivider, lineWidth: 1)
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
        .foregroundStyle(KaidoTheme.ink)
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
    identifierPrefix: String,
    onSelect: @escaping (String) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.system(size: 9, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.quietText)

      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(candidates) { facility in
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
                  .foregroundStyle(KaidoTheme.ink)
                  .lineLimit(1)

                Text(
                  facilityDirection(
                    facility,
                    usesEntranceDirection: usesEntranceDirection
                  )
                )
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(KaidoTheme.quietText)
                .lineLimit(1)
              }
              .padding(.horizontal, 10)
              .frame(width: 124, height: 64, alignment: .leading)
              .background(
                isSelected ? tint.opacity(0.13) : KaidoTheme.paperRaised
              )
              .clipShape(RoundedRectangle(cornerRadius: 11))
              .overlay {
                RoundedRectangle(cornerRadius: 11)
                  .stroke(
                    isSelected ? tint : KaidoTheme.paperDivider,
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
          }
        }
      }
      .scrollIndicators(.hidden)
    }
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
      .foregroundStyle(KaidoTheme.quietText)

      HStack(spacing: 7) {
        ForEach(ShutoRoutePreference.allCases, id: \.rawValue) { preference in
          let isSelected = model.customPreference == preference
          Button {
            model.selectCustomPreference(preference)
          } label: {
            Text(preferenceLabel(preference))
              .font(.system(size: 10, weight: .black, design: .rounded))
              .foregroundStyle(
                isSelected ? KaidoTheme.routeWhite : KaidoTheme.ink
              )
              .lineLimit(1)
              .minimumScaleFactor(0.7)
              .frame(maxWidth: .infinity)
              .frame(height: 38)
              .background(
                isSelected
                  ? KaidoTheme.routeGreenDeep : KaidoTheme.paperRaised
              )
              .clipShape(RoundedRectangle(cornerRadius: 9))
              .overlay {
                RoundedRectangle(cornerRadius: 9)
                  .stroke(
                    isSelected
                      ? KaidoTheme.routeGreenDeep : KaidoTheme.paperDivider,
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
        .fill(KaidoTheme.paperDivider)
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
      .foregroundStyle(
        isDriving ? KaidoTheme.routeWhite : KaidoTheme.ink
      )
      .background(
        isDriving
          ? KaidoTheme.instrument.opacity(0.94)
          : KaidoTheme.paperRaised.opacity(0.96)
      )
      .clipShape(Circle())
      .overlay {
        Circle()
          .stroke(
            isDriving ? KaidoTheme.steel : KaidoTheme.paperDivider,
            lineWidth: 1
          )
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
          usesDarkStyle ? KaidoTheme.asphalt : KaidoTheme.paper
        )
      )

      drawWater(context: &context, size: size)

      let nodeCoordinates = nodesByID
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
        let routeID = way.routeMemberships.first?.routeID ?? ""
        context.stroke(
          path,
          with: .color(
            routeColor(routeID).opacity(usesDarkStyle ? 0.50 : 0.62)
          ),
          style: StrokeStyle(
            lineWidth: usesDarkStyle ? 2.5 : 2.2,
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
          at: transform.point(selectedRoute.exitFacility.coordinate),
          color: KaidoTheme.evidenceCoral,
          label: copy.resolve(
            japanese: "出",
            simplifiedChinese: "出",
            english: "X"
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
              : KaidoTheme.ink.opacity(0.65)
          )
        )
      }

      for facility in database.directionalFacilities
      where facility.operationalStatus == "AVAILABLE" {
        let point = transform.point(facility.coordinate)
        context.fill(
          Path(
            ellipseIn: CGRect(
              x: point.x - 1.6,
              y: point.y - 1.6,
              width: 3.2,
              height: 3.2
            )
          ),
          with: .color(
            usesDarkStyle
              ? KaidoTheme.muted.opacity(0.72)
              : KaidoTheme.quietText.opacity(0.52)
          )
        )
      }

      for parkingArea in database.parkingAreas {
        let point = transform.point(parkingArea.coordinate)
        let frame = CGRect(
          x: point.x - 4.5,
          y: point.y - 4.5,
          width: 9,
          height: 9
        )
        context.fill(
          Path(roundedRect: frame, cornerRadius: 2),
          with: .color(KaidoTheme.signalAmber)
        )
        context.draw(
          context.resolve(
            Text("P")
              .font(.system(size: 5, weight: .black))
              .foregroundStyle(KaidoTheme.asphalt)
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
        Text("SHUTO NETWORK")
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
        usesDarkStyle ? KaidoTheme.muted : KaidoTheme.quietText
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
        japanese: "首都高全体路線図",
        simplifiedChinese: "首都高全网线路图",
        english: "Whole-Shuto network map"
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
      let point = transform.point(coordinate)
      let label = shieldLabel(routeID)
      let resolved = context.resolve(
        Text(label)
          .font(.system(size: 7, weight: .black, design: .rounded))
          .foregroundStyle(Color.white)
      )
      let frame = CGRect(
        x: point.x - 11,
        y: point.y - 8,
        width: 22,
        height: 16
      )
      context.fill(
        Path(roundedRect: frame, cornerRadius: 4),
        with: .color(routeColor(routeID))
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

private struct WholeShutoGeographicMap: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var model: WholeShutoProductModel
  let planningLocation: WholeShutoPlanningLocationSnapshot?
  @State private var camera = MapCameraPosition.region(
    MKCoordinateRegion(
      center: CLLocationCoordinate2D(
        latitude: 35.6762,
        longitude: 139.6503
      ),
      latitudinalMeters: 82_000,
      longitudinalMeters: 82_000
    )
  )
  @State private var followsRoute = true

  var body: some View {
    Map(position: $camera) {
      if let accessRoute = model.accessRoute,
        model.phase == .review || model.phase == .surfaceAccess
      {
        MapPolyline(
          coordinates: accessRoute.coordinates.map(\.mapCoordinate)
        )
        .stroke(
          KaidoTheme.positionCyan,
          style: StrokeStyle(
            lineWidth: 5,
            lineCap: .round,
            lineJoin: .round,
            dash: [7, 5]
          )
        )
      }

      if let route = model.selectedRoute {
        MapPolyline(
          coordinates: route.coordinates.map(\.mapCoordinate)
        )
        .stroke(
          Color.white.opacity(0.88),
          style: StrokeStyle(
            lineWidth: 10,
            lineCap: .round,
            lineJoin: .round
          )
        )
        if let progress = model.routeProgressGeometry {
          if progress.traveledCoordinates.count > 1 {
            MapPolyline(
              coordinates:
                progress.traveledCoordinates.map(\.mapCoordinate)
            )
            .stroke(
              KaidoTheme.muted,
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
          facilityBoundaryName(
            route.exitFacility.nameJA,
            isEntry: false
          ),
          coordinate: route.exitFacility.coordinate.mapCoordinate
        ) {
          WholeShutoMapMarker(
            text: copy.resolve(
              japanese: "出",
              simplifiedChinese: "出",
              english: "X"
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
          KaidoTheme.evidenceCoral,
          style: StrokeStyle(
            lineWidth: 5,
            lineCap: .round,
            lineJoin: .round,
            dash: [7, 5]
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
            color: KaidoTheme.ink
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
            .foregroundStyle(KaidoTheme.positionCyan)
            .rotationEffect(
              .degrees(displayedHeadingDegrees ?? 0)
            )
          }
          .accessibilityIdentifier("whole-shuto-current-position")
        }
      }
    }
    .mapStyle(
      model.phase == .planning || model.phase == .review
        ? .standard(elevation: .flat)
        : .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
    )
    .mapControls {
      MapCompass()
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
      updateCamera()
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
      ? model.navigationHeadingDegrees
      : planningLocation?.courseDegrees
  }

  private var positionAnnotationLabel: String {
    isDriving
      ? copy.resolve(
        japanese: "模擬位置",
        simplifiedChinese: "模拟位置",
        english: "Simulated position"
      )
      : copy.resolve(
        japanese: "現在地",
        simplifiedChinese: "当前位置",
        english: "Current location"
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

  private func updateCamera(force: Bool = false) {
    guard force || followsRoute else { return }
    guard isDriving, let current = model.currentCoordinate else {
      followsRoute = true
      if model.selectedRoute != nil || planningLocation != nil {
        camera = .automatic
      }
      return
    }
    withAnimation(.easeOut(duration: 0.35)) {
      if let heading = model.navigationHeadingDegrees {
        camera = .camera(
          MapCamera(
            centerCoordinate: current.mapCoordinate,
            distance: model.navigationCameraDistanceMeters,
            heading: heading,
            pitch: 45
          )
        )
      } else {
        camera = .camera(
          MapCamera(
            centerCoordinate: current.mapCoordinate,
            distance: model.navigationCameraDistanceMeters,
            heading: 0,
            pitch: 0
          )
        )
      }
    }
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
    .foregroundStyle(darkText ? KaidoTheme.asphalt : Color.white)
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
        .font(.system(size: 9, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.confirmedGreen)
        Text(localizedDisplayText)
          .font(.system(size: 19, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
        HStack(spacing: 6) {
          Text(shieldLabel(prompt.incomingRouteID))
            .junctionShield(color: routeColor(prompt.incomingRouteID))
          Image(systemName: "arrow.right")
            .font(.system(size: 9, weight: .black))
          Text(shieldLabel(prompt.outgoingRouteID))
            .junctionShield(color: routeColor(prompt.outgoingRouteID))
        }
        Text(verbatim: prompt.japaneseSignText)
          .font(.system(size: 10, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)
        Text(
          prompt.routeShields.map(shieldLabel)
            .joined(separator: " · ")
        )
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)
        Text("\(laneGuidanceLabel) · \(prompt.checkedAt)")
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(KaidoTheme.muted)
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .background(KaidoTheme.asphalt.opacity(0.97))
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
        japanese: "車線番号は未公開",
        simplifiedChinese: "车道编号尚未发布",
        english: "Lane numbers not released"
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
    copy.resolve(
      japanese:
        "\(localizedJunctionName)、"
        + "\(shieldLabel(prompt.incomingRouteID))から\(branchLabel)、"
        + "\(localizedDisplayText)、日本語標識\(prompt.japaneseSignText)、"
        + laneGuidanceLabel,
      simplifiedChinese:
        "\(localizedJunctionName)，"
        + "从\(shieldLabel(prompt.incomingRouteID))\(branchLabel)，"
        + "\(localizedDisplayText)，日文路牌\(prompt.japaneseSignText)，"
        + laneGuidanceLabel,
      english:
        "\(localizedJunctionName), from "
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
          with: .color(KaidoTheme.steel),
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
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }
}

private struct WholeShutoLanguageSettingsView: View {
  @ObservedObject var model: KaidoLanguageSettingsModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(KaidoReleaseLocale.allCases, id: \.self) { locale in
            languageButton(
              locale,
              selection: model.interfaceLocale
            ) {
              model.selectInterfaceLocale(locale)
            }
            .accessibilityIdentifier(
              "whole-shuto-interface-language-\(locale.rawValue)"
            )
          }
        } header: {
          Text(
            copy.resolve(
              japanese: "画面表示",
              simplifiedChinese: "界面语言",
              english: "INTERFACE LANGUAGE"
            )
          )
        } footer: {
          Text(
            copy.resolve(
              japanese: "画面上の説明文と操作項目の言語を変更します。",
              simplifiedChinese: "更改界面说明和操作项的语言。",
              english: "Changes explanatory copy and controls."
            )
          )
        }

        Section {
          ForEach(KaidoReleaseLocale.allCases, id: \.self) { locale in
            languageButton(
              locale,
              selection: model.guidanceVoiceLocale
            ) {
              model.selectGuidanceVoiceLocale(locale)
            }
            .accessibilityIdentifier(
              "whole-shuto-guidance-voice-language-\(locale.rawValue)"
            )
          }
        } header: {
          Text(
            copy.resolve(
              japanese: "音声案内",
              simplifiedChinese: "导航语音",
              english: "GUIDANCE VOICE"
            )
          )
        } footer: {
          Text(
            copy.resolve(
              japanese: "画面表示とは独立して、審査済み音声案内の言語を選択します。",
              simplifiedChinese: "独立于界面语言，选择已审核导航语音的语言。",
              english:
                "Selects reviewed spoken guidance independently from the interface."
            )
          )
        }

        Section {
          Label(
            copy.resolve(
              japanese: "物理標識とルート番号は日本語のまま表示します。",
              simplifiedChinese: "实体路牌和路线编号始终保留日文原文。",
              english:
                "Physical sign targets and route shields remain visible in Japanese."
            ),
            systemImage: "signpost.right"
          )
        }
      }
      .navigationTitle(
        copy.resolve(
          japanese: "言語設定",
          simplifiedChinese: "语言设置",
          english: "Language Settings"
        )
      )
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
          .accessibilityIdentifier("whole-shuto-language-settings-done")
        }
      }
    }
  }

  private func languageButton(
    _ locale: KaidoReleaseLocale,
    selection: KaidoReleaseLocale,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack {
        Text(copy.languageName(locale))
        Spacer()
        if locale == selection {
          Image(systemName: "checkmark")
            .fontWeight(.bold)
            .foregroundStyle(KaidoTheme.routeGreen)
        }
      }
    }
    .foregroundStyle(KaidoTheme.ink)
    .accessibilityAddTraits(locale == selection ? .isSelected : [])
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

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: model.interfaceLocale)
  }
}

private struct WholeShutoNetworkFactsView: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var model: WholeShutoProductModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section(
          copy.resolve(
            japanese: "全体範囲",
            simplifiedChinese: "全网范围",
            english: "NETWORK SCOPE"
          )
        ) {
          fact(
            copy.resolve(
              japanese: "路線",
              simplifiedChinese: "路线",
              english: "Routes"
            ),
            "\(model.database.routes.count)"
          )
          fact(
            copy.resolve(
              japanese: "IC 名称",
              simplifiedChinese: "IC 名称",
              english: "IC names"
            ),
            "\(model.database.directionalFacilities.count)"
          )
          fact("JCT", "\(model.database.junctions.count)")
          fact(
            copy.resolve(
              japanese: "JCT 公式詳細図索引",
              simplifiedChinese: "JCT 官方详图索引",
              english: "Official JCT detail index"
            ),
            "\(officialJunctionReferenceCount)"
              + " / \(model.database.junctions.count)"
          )
          fact("PA", "\(model.database.parkingAreas.count)")
          fact(
            copy.resolve(
              japanese: "データ確認日",
              simplifiedChinese: "数据日期",
              english: "Data checked"
            ),
            model.database.checkedAt
          )
        }

        Section(
          copy.resolve(
            japanese: "精度の境界",
            simplifiedChinese: "准确性边界",
            english: "ACCURACY BOUNDARIES"
          )
        ) {
          Label(
            copy.resolve(
              japanese: "路線、IC方向、JCT、PAの一覧は首都高の現行公式ページに基づきます。",
              simplifiedChinese: "路线、IC 方向、JCT 与 PA 名单来自首都高当前官方页面。",
              english:
                "Route, directional IC, JCT, and PA lists come from current Shuto Expressway pages."
            ),
            systemImage: "checkmark.seal"
          )
          Label(
            copy.resolve(
              japanese: "道路形状と接続は固定版OSM候補で、公式の車線単位の権限ではありません。",
              simplifiedChinese: "道路几何和连通为固定版本 OSM 候选，不代表官方车道级授权。",
              english:
                "Road geometry and connectivity are fixed-version OSM candidates, not official lane-level authority."
            ),
            systemImage: "point.3.connected.trianglepath.dotted"
          )
          Label(
            copy.resolve(
              japanese: "リアルタイム通行、臨時通行止め、料金、PA営業状況は未確認です。",
              simplifiedChinese: "实时通行、临时封闭、收费与 PA 开放状态尚未确认。",
              english:
                "Realtime passage, temporary closures, tolls, and PA availability are unconfirmed."
            ),
            systemImage: "exclamationmark.triangle"
          )
        }
      }
      .navigationTitle(
        copy.resolve(
          japanese: "首都高全体",
          simplifiedChinese: "首都高全网",
          english: "Whole Shuto"
        )
      )
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(
            copy.resolve(
              japanese: "完了",
              simplifiedChinese: "完成",
              english: "Done"
            )
          ) { dismiss() }
        }
      }
    }
  }

  private func fact(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
    }
  }

  private var officialJunctionReferenceCount: Int {
    model.database.junctions.filter {
      $0.officialDetailSHA256.count == 64
    }.count
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

private func shieldLabel(_ routeID: String) -> String {
  routeID
    .replacingOccurrences(of: "_HANEDA", with: "")
    .replacingOccurrences(of: "_UENO", with: "")
    .replacingOccurrences(of: "_MUKOJIMA", with: "")
    .replacingOccurrences(of: "_MISATO", with: "")
    .replacingOccurrences(of: "_YOKOHAMA_KITA", with: "")
    .replacingOccurrences(of: "_YOKOHAMA_HOKUSEI", with: "")
}

private func routeColor(_ routeID: String) -> Color {
  switch routeID {
  case "C1", "1_HANEDA", "1_UENO", "5", "S1", "S2", "S5":
    return Color(hex: 0x2877B7)
  case "C2", "6_MUKOJIMA", "6_MISATO", "K6":
    return Color(hex: 0x2F8E63)
  case "B", "9", "11", "K5":
    return Color(hex: 0x8065A7)
  case "3", "K1", "K2", "K3":
    return Color(hex: 0x34658D)
  case "4", "K7_YOKOHAMA_KITA", "K7_YOKOHAMA_HOKUSEI":
    return Color(hex: 0xC84E45)
  case "7", "10":
    return Color(hex: 0xC9822E)
  case "2":
    return Color(hex: 0x7C5E99)
  default:
    return KaidoTheme.routeGreen
  }
}
