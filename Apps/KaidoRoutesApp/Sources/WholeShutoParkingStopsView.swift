import KaidoRouting
import SwiftUI

struct WholeShutoParkingStopsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.kaidoInterfaceLocale) private var locale
  @ObservedObject var model: WholeShutoProductModel
  @State private var options: [ShutoParkingStopOption] = []
  @State private var selected: Set<String> = []
  @State private var isLoading = true
  @State private var isApplying = false
  @State private var error: String?

  private var copy: KaidoInterfaceText { KaidoInterfaceText(locale: locale) }

  var body: some View {
    NavigationStack {
      Form {
        if !model.includedParkingStops.isEmpty {
          Section(copy.resolve(japanese: "ルートに含まれるPA", simplifiedChinese: "路线已包含", english: "Included in the route")) {
            ForEach(model.includedParkingStops) { parking in
              Label(parking.nameJA, systemImage: "checkmark")
            }
          }
        }
        Section {
          if isLoading {
            ProgressView()
          } else if options.isEmpty && error == nil {
            Text(copy.resolve(japanese: "このルートに追加できるPAはありません。", simplifiedChinese: "此路线没有可添加的 PA。", english: "No additional PA stops on this route."))
              .accessibilityIdentifier("whole-shuto-parking-stops-empty")
          } else {
            ForEach(options) { option in
              Button {
                if selected.contains(option.id) { selected.remove(option.id) }
                else { selected.insert(option.id) }
              } label: {
                HStack {
                  Text(option.parkingArea.nameJA)
                  Spacer()
                  Image(systemName: selected.contains(option.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(option.id) ? Color.accentColor : Color.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("whole-shuto-parking-stop-\(option.id)")
              .accessibilityAddTraits(selected.contains(option.id) ? .isSelected : [])
            }
          }
        } footer: {
          Text(copy.resolve(japanese: "最初に通るときに立ち寄ります。", simplifiedChinese: "在首次经过时停靠。", english: "Stop on the first pass."))
        }
        if let error { Section { Text(error).foregroundStyle(.red) } }
        Section {
          Button {
            isApplying = true
            error = nil
            Task {
              defer { isApplying = false }
              do {
                try await model.selectJourneyParkingStops(selected.sorted())
                dismiss()
              } catch {
                self.error = copy.resolve(japanese: "この組み合わせでは停車できません。選び直してください。", simplifiedChinese: "这些停靠无法组合，请调整选择。", english: "These stops cannot be combined. Adjust your selection.")
              }
            }
          } label: {
            HStack {
              Text(copy.resolve(japanese: "適用", simplifiedChinese: "应用", english: "Apply"))
              if isApplying { ProgressView() }
            }
          }
          .accessibilityIdentifier("whole-shuto-parking-stops-apply")
          .disabled(isLoading || isApplying)
        }
      }
      .disabled(isApplying)
      .navigationTitle(copy.resolve(japanese: "PAに立ち寄る", simplifiedChinese: "PA 停靠", english: "PA stops"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(copy.resolve(japanese: "キャンセル", simplifiedChinese: "取消", english: "Cancel")) { dismiss() }
            .disabled(isApplying)
        }
      }
    }
    .interactiveDismissDisabled(isApplying)
    .task {
      selected = Set(model.parkingStopSelection?.parkingAreaIDs ?? [])
      do { options = try await model.journeyParkingStopOptions() }
      catch {
        self.error = copy.resolve(japanese: "PAを確認できません。", simplifiedChinese: "无法获取沿途 PA。", english: "Unable to load PA stops.")
      }
      isLoading = false
    }
  }
}
