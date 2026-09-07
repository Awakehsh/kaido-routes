import KaidoDomain
import SwiftUI

struct DriveHistoryView: View {
  @ObservedObject var model: WholeShutoProductModel
  @ObservedObject var savedRoutes: SavedRouteLibraryModel
  let locale: KaidoReleaseLocale
  @State private var records: [DriveHistoryEntry] = []
  @State private var loadFailed = false
  @State private var pendingDeletion: DriveHistoryEntry?

  var body: some View {
    List {
      if loadFailed || model.driveHistoryIssue != nil {
        Section {
          Text(copy.resolve(japanese: "走行記録を読み込めないか、前回の記録を保存できませんでした。",
            simplifiedChinese: "行程记录无法读取，或上次记录未能保存。",
            english: "History could not be read, or the last record could not be saved."))
          Button(copy.resolve(japanese: "再読み込み", simplifiedChinese: "重新读取", english: "Reload")) { load() }
        }
      }
      if records.isEmpty && !loadFailed {
        ContentUnavailableView(
          copy.resolve(japanese: "走行記録はありません", simplifiedChinese: "暂无行程记录", english: "No drive history"),
          systemImage: "clock.arrow.circlepath",
          description: Text(copy.resolve(japanese: "記録をオンにして走行すると、終了後にここに保存されます。",
            simplifiedChinese: "开启行驶记录后，已记录的行程会在结束时保存在这里。",
            english: "With recording enabled, recorded drives are saved here when they end."))
        )
      }
      ForEach(records) { record in
        let kilometers = (record.recordedDistanceMeters / 1_000).formatted(.number.precision(.fractionLength(1)))
        NavigationLink {
          DriveHistoryDetailView(record: record, savedRoutes: savedRoutes, locale: locale)
        } label: {
          VStack(alignment: .leading, spacing: 5) {
            Text(record.routeName).font(.headline)
            Text(Date(timeIntervalSince1970: Double(record.startedAtMilliseconds) / 1_000), style: .date)
              .font(.subheadline).foregroundStyle(.secondary)
            Text(copy.resolve(
              japanese: "記録 \(kilometers) km · \(record.laps.count)周",
              simplifiedChinese: "已记录 \(kilometers) km · \(record.laps.count) 圈",
              english: "Recorded \(kilometers) km · \(record.laps.count) laps"
            ))
            .font(.caption).foregroundStyle(.secondary)
          }
        }
        .swipeActions {
          Button(role: .destructive) { pendingDeletion = record } label: {
            Label(copy.resolve(japanese: "削除", simplifiedChinese: "删除", english: "Delete"), systemImage: "trash")
          }
        }
      }
    }
    .navigationTitle(copy.resolve(japanese: "走行履歴", simplifiedChinese: "行程记录", english: "Drive history"))
    .environment(\.locale, Locale(identifier: locale.rawValue))
    .accessibilityIdentifier("whole-shuto-drive-history")
    .onAppear { load() }
    .confirmationDialog(
      copy.resolve(japanese: "この走行記録を削除しますか？", simplifiedChinese: "删除这次行程记录？", english: "Delete this drive record?"),
      isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    ) {
      Button(copy.resolve(japanese: "削除", simplifiedChinese: "删除", english: "Delete"), role: .destructive) {
        guard let record = pendingDeletion else { return }
        do { try model.driveHistoryStore.remove(id: record.id); load() }
        catch { loadFailed = true }
        pendingDeletion = nil
      }
    }
  }

  private func load() {
    do { records = try model.driveHistoryStore.load(); loadFailed = false }
    catch { loadFailed = true }
  }

  private var copy: KaidoInterfaceText { KaidoInterfaceText(locale: locale) }
}

private struct DriveHistoryDetailView: View {
  let record: DriveHistoryEntry
  @ObservedObject var savedRoutes: SavedRouteLibraryModel
  let locale: KaidoReleaseLocale
  @State private var exportURL: URL?
  @State private var shareFailed = false
  @State private var saveFailed = false

  var body: some View {
    List {
      Section {
        Text(record.routeName).font(.headline)
        LabeledContent(copy.resolve(japanese: "開始", simplifiedChinese: "开始时间", english: "Started")) {
          Text(Date(timeIntervalSince1970: Double(record.startedAtMilliseconds) / 1_000), format: .dateTime.month().day().hour().minute())
        }
        Text(record.arrived
          ? copy.resolve(japanese: "目的地に到着", simplifiedChinese: "已抵达", english: "Arrived")
          : copy.resolve(japanese: "ナビ終了", simplifiedChinese: "已结束导航", english: "Navigation ended"))
      }
      Section {
        LabeledContent(copy.resolve(japanese: "記録距離", simplifiedChinese: "已记录距离", english: "Recorded distance")) {
          Text(record.recordedDistanceMeters / 1_000, format: .number.precision(.fractionLength(1))) + Text(" km")
        }
        LabeledContent(copy.resolve(japanese: "記録時間", simplifiedChinese: "有效记录时长", english: "Recorded time"),
          value: duration(record.recordedDurationMilliseconds))
        speedRow(copy.resolve(japanese: "平均", simplifiedChinese: "平均速度", english: "Average speed"), record.averageSpeedMetersPerSecond)
        speedRow(copy.resolve(japanese: "最高", simplifiedChinese: "最高速度", english: "Maximum speed"), record.maximumSpeedMetersPerSecond)
        speedRow(copy.resolve(japanese: "最低", simplifiedChinese: "最低速度", english: "Minimum speed"), record.minimumSpeedMetersPerSecond)
        ForEach(record.laps) { lap in
          LabeledContent(copy.resolve(japanese: "\(lap.lapNumber)周目", simplifiedChinese: "第 \(lap.lapNumber) 圈", english: "Lap \(lap.lapNumber)"),
            value: duration(lap.durationMilliseconds))
        }
      } footer: {
        Text(copy.resolve(japanese: "有効な観測がある区間のみを集計しています。記録のない区間を補完しません。",
          simplifiedChinese: "仅统计有有效观测的路段，不补算缺失时段。",
          english: "Summaries cover recorded intervals only; missing intervals are not filled in."))
      }
      Section {
        Button(copy.resolve(japanese: "計画ルートを保存", simplifiedChinese: "保存计划路线", english: "Save planned route")) {
          savedRoutes.save(routePlan: record.routePlan, displayName: record.routeName,
            evidenceState: .communityCandidate, templateParameters: record.templateParameters)
          saveFailed = savedRoutes.lastErrorCode != nil
        }
        .disabled(savedRoutes.records.contains { $0.document.routePlan == record.routePlan })
        if let exportURL {
          ShareLink(item: exportURL, preview: SharePreview(record.routeName)) {
            Label(copy.resolve(japanese: "計画ルートを共有", simplifiedChinese: "分享计划路线", english: "Share planned route"), systemImage: "square.and.arrow.up")
          }
        }
        if shareFailed || saveFailed {
          Text(copy.resolve(japanese: "ルートを保存または共有できませんでした。", simplifiedChinese: "未能保存或分享路线。", english: "The route could not be saved or shared."))
            .foregroundStyle(.secondary)
        }
      } footer: {
        Text(copy.resolve(japanese: "共有するのは計画ルートです。走行記録や現在地は含みません。",
          simplifiedChinese: "仅分享计划路线，不包含行驶统计和当前位置。",
          english: "Sharing includes the planned route, without drive statistics or your current location."))
      }
    }
    .navigationTitle(copy.resolve(japanese: "走行記録", simplifiedChinese: "行程详情", english: "Drive details"))
    .task {
      do {
        let document = SharedRouteDocument(evidenceState: .communityCandidate,
          templateParameters: record.templateParameters, routePlan: record.routePlan)
        let data = try SharedRouteCodec.encode(document)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KaidoShare-\(record.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(SharedRouteFileDocument.exportFileName(record.routeName)).appendingPathExtension("kaidoroute")
        try data.write(to: url, options: .atomic)
        exportURL = url
      } catch { shareFailed = true }
    }
  }

  private func speedRow(_ title: String, _ speed: Double?) -> some View {
    LabeledContent(title) {
      if let speed { Text(speed * 3.6, format: .number.precision(.fractionLength(0))) + Text(" km/h") }
      else { Text("—") }
    }
  }

  private func duration(_ milliseconds: Int) -> String {
    String(format: "%d:%02d", milliseconds / 60_000, milliseconds / 1_000 % 60)
  }

  private var copy: KaidoInterfaceText { KaidoInterfaceText(locale: locale) }
}
