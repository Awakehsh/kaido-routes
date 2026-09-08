import KaidoDomain
import KaidoRouting
import SwiftUI

extension WholeShutoJourneyEnding {
  func label(for locale: KaidoReleaseLocale) -> String {
    let copy = KaidoInterfaceText(locale: locale)
    switch self {
    case .returnToOrigin:
      return copy.resolve(
        japanese: "出発地に戻る", simplifiedChinese: "返回出发地", english: "Return to start")
    case .exit:
      return copy.resolve(
        japanese: "高速出口で終了", simplifiedChinese: "在高速出口结束", english: "End at an expressway exit")
    case .destination:
      return copy.resolve(
        japanese: "別の場所へ向かう", simplifiedChinese: "前往其他地点", english: "Continue to another place")
    }
  }
}

struct WholeShutoJourneyEndingView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.kaidoInterfaceLocale) private var locale
  @ObservedObject var model: WholeShutoProductModel
  @ObservedObject var placeSearch: WholeShutoPlaceSearchController
  @State private var ending: WholeShutoJourneyEnding = .returnToOrigin
  @State private var query = ""
  @State private var destination: WholeShutoPlace?
  @State private var exitID = ""
  @State private var exits: [ShutoNetworkDatabase.Facility] = []
  @State private var isApplying = false
  @State private var error: String?

  private var copy: KaidoInterfaceText { KaidoInterfaceText(locale: locale) }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          ForEach(WholeShutoJourneyEnding.allCases, id: \.self) { option in
            Button {
              ending = option
              error = nil
              placeSearch.dismissResults()
            } label: {
              HStack {
                Text(option.label(for: locale))
                Spacer()
                if ending == option { Image(systemName: "checkmark") }
              }
              .frame(minHeight: 32)
              .contentShape(Rectangle())
            }
            .accessibilityIdentifier("whole-shuto-ending-\(option.rawValue)")
            .accessibilityAddTraits(ending == option ? .isSelected : [])
          }
        }
        if ending == .returnToOrigin {
          Section {
            Text(model.origin?.title ?? "—")
            Text(
              copy.resolve(
                japanese: "出発前に確認した出発地まで案内します。", simplifiedChinese: "返回本次行程确认的出发地点。",
                english: "Return to the fixed starting point of this journey.")
            )
            .font(.footnote).foregroundStyle(.secondary)
          }
        } else if ending == .exit {
          Section {
            Picker(
              copy.resolve(japanese: "出口", simplifiedChinese: "出口", english: "Exit"),
              selection: $exitID
            ) {
              ForEach(exits, id: \.facilityID) { exit in
                Text("\(exit.nameJA) · \(exit.exitDirections.joined(separator: " / "))")
                  .tag(exit.facilityID)
              }
            }
            .accessibilityIdentifier("whole-shuto-ending-exit-picker")
            Text(
              copy.resolve(
                japanese: "選択した出口を出たところで案内を終了します。", simplifiedChinese: "完成所选出口的驶离引导后结束导航。",
                english: "Guidance ends after leaving through the selected exit.")
            )
            .font(.footnote).foregroundStyle(.secondary)
          }
        } else {
          Section {
            TextField(
              copy.resolve(
                japanese: "場所を検索", simplifiedChinese: "搜索地点", english: "Search for a place"),
              text: $query
            )
            .accessibilityIdentifier("whole-shuto-ending-search")
            .onChange(of: query) {
              if destination?.title != query { destination = nil }
              placeSearch.update(
                query: query, near: model.destination?.coordinate ?? model.origin?.coordinate)
            }
            ForEach(placeSearch.suggestions) { suggestion in
              Button {
                Task {
                  isApplying = true
                  defer { isApplying = false }
                  do {
                    let place = try await placeSearch.resolve(suggestion)
                    destination = place
                    query = place.title
                    error = nil
                  } catch { showSearchError() }
                }
              } label: {
                VStack(alignment: .leading) {
                  Text(suggestion.title)
                  Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary)
                }
              }
              .accessibilityIdentifier("whole-shuto-ending-suggestion-\(suggestion.id)")
            }
            Text(
              copy.resolve(
                japanese: "選んだ高速ルートの後、そのまま目的地まで案内します。", simplifiedChinese: "完成所选高速路线后，自动继续导航至此地点。",
                english:
                  "After the selected expressway route, guidance continues automatically to this place."
              )
            )
            .font(.footnote).foregroundStyle(.secondary)
          }
        }
        if let error { Section { Text(error).foregroundStyle(.red) } }
        Section {
          Button(action: apply) {
            HStack {
              Text(
                copy.resolve(
                  japanese: "この終点を使う", simplifiedChinese: "使用此结束方式", english: "Use this ending"))
              if isApplying { ProgressView() }
            }
          }
          .accessibilityIdentifier("whole-shuto-ending-apply")
          .disabled(
            isApplying
              || (ending == .destination
                && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          )
        }
      }
      .disabled(isApplying)
      .navigationTitle(
        copy.resolve(japanese: "行程の終点", simplifiedChinese: "行程结束于", english: "Journey ending")
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(copy.resolve(japanese: "キャンセル", simplifiedChinese: "取消", english: "Cancel")) {
            dismiss()
          }
          .disabled(isApplying)
        }
      }
    }
    .interactiveDismissDisabled(isApplying)
    .task {
      ending = model.journeyEnding
      exitID = model.selectedRoute?.exitFacility.facilityID ?? ""
      exits = model.selectedRoute.map { [$0.exitFacility] } ?? []
      if ending == .destination {
        destination = model.destination
        query = model.destination?.title ?? ""
      }
      do {
        exits = try await model.journeyExitCandidates()
      } catch {
        self.error = copy.resolve(
          japanese: "他の出口を確認できません。現在の出口はそのまま使えます。",
          simplifiedChinese: "无法获取其他出口，仍可使用当前已选出口。",
          english: "Other exits could not be loaded. You can keep the selected exit."
        )
      }
    }
    .onDisappear { placeSearch.dismissResults() }
  }

  private func apply() {
    isApplying = true
    error = nil
    Task {
      defer { isApplying = false }
      do {
        switch ending {
        case .returnToOrigin: model.selectJourneyEnding(.returnToOrigin)
        case .exit: try await model.selectJourneyExit(exitID)
        case .destination:
          let place: WholeShutoPlace
          if let destination {
            place = destination
          } else {
            place = try await model.resolveJourneyDestination(query)
          }
          model.selectJourneyEnding(.destination, destination: place)
        }
        dismiss()
      } catch {
        if ending == .exit {
          self.error = copy.resolve(
            japanese: "この出口につながるルートがありません。別の出口を選んでください。",
            simplifiedChinese: "所选路线无法合法到达此出口，请选择其他出口。",
            english: "This route cannot reach that exit. Choose another exit.")
        } else {
          showSearchError()
        }
      }
    }
  }

  private func showSearchError() {
    error = copy.resolve(
      japanese: "場所を確認できません。再検索してください。", simplifiedChinese: "无法确认地点，请重新搜索。",
      english: "Could not resolve this place. Please search again.")
  }
}
