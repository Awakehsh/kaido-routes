import Foundation
import KaidoDomain
import SwiftUI
import UniformTypeIdentifiers

@MainActor
func importSavedRouteFile(
  _ result: Result<[URL], Error>,
  into model: SavedRouteLibraryModel
) -> String? {
  do {
    guard let url = try result.get().first else {
      return "SAVED_ROUTE_IMPORT_SELECTION_EMPTY"
    }
    guard url.isFileURL else { return "SAVED_ROUTE_IMPORT_READ_FAILED" }
    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed {
        url.stopAccessingSecurityScopedResource()
      }
    }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let maximumBytes = 16 * 1_024 * 1_024
    guard let data = try file.read(upToCount: maximumBytes + 1), data.count <= maximumBytes else {
      return "SAVED_ROUTE_IMPORT_READ_FAILED"
    }
    let suggestedName = url.deletingPathExtension().lastPathComponent
    model.importSharedRoute(
      data,
      suggestedName:
        suggestedName.isEmpty
        ? "Imported route"
        : suggestedName
    )
    return nil
  } catch {
    return "SAVED_ROUTE_IMPORT_READ_FAILED"
  }
}

private struct SavedRouteImportModifier: ViewModifier {
  @Binding var isPresented: Bool
  let enabled: Bool
  let onCompletion: (Result<[URL], Error>) -> Void

  func body(content: Content) -> some View {
    if enabled {
      content.fileImporter(
        isPresented: $isPresented,
      allowedContentTypes: [.kaidoRoute, .json],
        allowsMultipleSelection: false,
        onCompletion: onCompletion
      )
    } else {
      content
    }
  }
}

struct SavedRouteLibraryPanel: View {
  @ObservedObject var model: SavedRouteLibraryModel
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

  let openRecord: (String) -> Void
  /// When set, the parent presents the document picker. A picker attached
  /// inside an already-presented sheet often never appears.
  var importPresentation: Binding<Bool>? = nil

  @State private var isImporting = false
  @State private var isExporting = false
  @State private var exportDocument: SharedRouteFileDocument?
  @State private var exportFileName = "kaido-route"
  @State private var renameRecordID: String?
  @State private var renameName = ""
  @State private var deleteRecordID: String?
  @State private var transferErrorCode: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      transferControls

      if model.records.isEmpty {
        emptyState
      } else {
        ForEach(model.records, id: \.id) { record in
          recordCard(record)
        }
      }

      if transferErrorCode != nil {
        Text(copy.resolve(japanese: "ルートを読み込み・書き出しできませんでした。もう一度お試しください。", simplifiedChinese: "未能导入或导出路线，请重试。", english: "The route could not be imported or exported. Try again."))
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.evidenceCoral)
          .accessibilityIdentifier("saved-route-transfer-error")
      }
    }
    .padding(14)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .stroke(KaidoTheme.steel.opacity(0.8), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("saved-route-library")
    .accessibilityValue(
      "\(model.records.count) RECORDS · "
        + "\(model.lastErrorCode ?? "READY")"
    )
    .modifier(
      SavedRouteImportModifier(
        isPresented: importing,
        enabled: importPresentation == nil,
        onCompletion: importSharedRoute
      )
    )
    .fileExporter(
      isPresented: $isExporting,
      document: exportDocument,
      contentType: .kaidoRoute,
      defaultFilename: exportFileName
    ) { result in
      if case .failure = result {
        transferErrorCode =
          "SAVED_ROUTE_EXPORT_PRESENTATION_FAILED"
      } else {
        transferErrorCode = nil
      }
      exportDocument = nil
    }
    .alert(
      copy.resolve(
        japanese: "ルート名を変更",
        simplifiedChinese: "重命名路线",
        english: "Rename route"
      ),
      isPresented: renamePresentation
    ) {
      TextField(
        copy.resolve(
          japanese: "ルート名",
          simplifiedChinese: "路线名称",
          english: "Route name"
        ),
        text: $renameName
      )
      Button(
        copy.resolve(
          japanese: "キャンセル",
          simplifiedChinese: "取消",
          english: "Cancel"
        ),
        role: .cancel
      ) {
        renameRecordID = nil
      }
      Button(
        copy.resolve(
          japanese: "保存",
          simplifiedChinese: "保存",
          english: "Save"
        )
      ) {
        guard let renameRecordID else { return }
        model.rename(
          recordID: renameRecordID,
          displayName: renameName
        )
        self.renameRecordID = nil
      }
      .disabled(
        renameName.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty
      )
    } message: {
      Text(
        copy.resolve(
          japanese:
            "ルートの新しい名前を入力してください。",
          simplifiedChinese:
            "输入路线的新名称。",
          english:
            "Enter a new name for this route."
        )
      )
    }
    .confirmationDialog(
      copy.resolve(
        japanese: "保存ルートを削除しますか？",
        simplifiedChinese: "删除已保存路线？",
        english: "Delete saved route?"
      ),
      isPresented: deletePresentation,
      titleVisibility: .visible
    ) {
      Button(
        copy.resolve(
          japanese: "削除",
          simplifiedChinese: "删除",
          english: "Delete"
        ),
        role: .destructive
      ) {
        guard let deleteRecordID else { return }
        model.delete(recordID: deleteRecordID)
        self.deleteRecordID = nil
      }
      Button(
        copy.resolve(
          japanese: "キャンセル",
          simplifiedChinese: "取消",
          english: "Cancel"
        ),
        role: .cancel
      ) {
        deleteRecordID = nil
      }
    } message: {
      Text(
        copy.resolve(
          japanese:
            "この端末の保存記録だけを削除します。元の共有ファイルやリリースは変更しません。",
          simplifiedChinese:
            "只删除本机保存记录，不修改原始共享文件或发布包。",
          english:
            "This removes only the local saved record. It does not change an exported file or product release."
        )
      )
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(
          copy.resolve(
            japanese:
              "保存したルートを選んで、経路を確認できます。",
            simplifiedChinese:
              "选择已保存的路线，查看行程。",
            english:
              "Choose a saved route to review your journey."
          )
        )
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(KaidoTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 8)

      StatusCapsule(
        title: copy.resolve(japanese: "\(model.records.count) 件", simplifiedChinese: "\(model.records.count) 条", english: "\(model.records.count) saved"),
        color:
          model.storageAvailable
          ? KaidoTheme.signalAmber
          : KaidoTheme.evidenceCoral
      )
    }
  }

  private var emptyState: some View {
    ReviewBoundaryCard(
      symbol:
        model.storageAvailable
        ? "bookmark"
        : "externaldrive.fill.badge.xmark",
      title:
        model.storageAvailable
        ? copy.resolve(
          japanese: "保存ルートはまだありません",
          simplifiedChinese: "还没有保存路线",
          english: "No saved routes yet"
        )
        : copy.resolve(
          japanese: "ルート保存を利用できません",
          simplifiedChinese: "路线存储不可用",
          english: "Saved-route storage unavailable"
        ),
      detail:
        model.storageAvailable
        ? copy.resolve(
          japanese:
            "経路を明示的な出口まで作成し、出発前確認で名前を付けて保存します。",
          simplifiedChinese:
            "将路线编排到明确出口，然后在行前确认中命名保存。",
          english:
            "Author through an explicit exit, then name and save the route during pre-drive review."
        )
        : copy.resolve(
          japanese:
            "ルートを保存できません。アプリを開き直してお試しください。",
          simplifiedChinese:
            "无法保存路线，请重新打开应用后重试。",
          english:
            "Routes could not be saved. Reopen the app and try again."
        ),
      code:
        model.lastErrorCode
        ?? (model.storageAvailable
          ? "SAVED_ROUTE_LIBRARY_EMPTY"
          : SavedRouteLibraryModelError.storeUnavailable.rawValue),
      color:
        model.storageAvailable
        ? KaidoTheme.steel
        : KaidoTheme.evidenceCoral
    )
    .accessibilityIdentifier("saved-route-library-empty")
  }

  private var transferControls: some View {
    Button {
      transferErrorCode = nil
      importing.wrappedValue = true
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "square.and.arrow.down")
        Text(
          copy.resolve(
            japanese: "共有ルートを読み込む",
            simplifiedChinese: "导入共享路线",
            english: "Import shared route"
          )
        )
        Spacer()
      }
      .font(.system(size: 14, weight: .bold))
      .foregroundStyle(
        model.storageAvailable
          ? KaidoTheme.positionCyan
          : KaidoTheme.muted
      )
      .padding(.horizontal, 11)
      .frame(height: 44)
      .background(KaidoTheme.asphalt.opacity(0.72))
      .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    .buttonStyle(.plain)
    .disabled(!model.storageAvailable)
    .accessibilityIdentifier("saved-route-import")
  }

  private func recordCard(_ record: SavedRouteRecord) -> some View {
    let availability = model.availability(for: record)
    return VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          Text(record.displayName)
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)

          Text(String(record.savedAt.prefix(10)))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(KaidoTheme.muted)
        }

        Spacer(minLength: 8)

        StatusCapsule(
          title: availabilityTitle(availability),
          color: availabilityColor(availability)
        )
      }

      Button {
        openRecord(record.id)
      } label: {
        HStack {
          Image(systemName: "arrowshape.turn.up.right.fill")
          Text(
            copy.resolve(
              japanese: "このルートを選ぶ",
              simplifiedChinese: "选择此路线",
              english: "Select this route"
            )
          )
          Spacer()
          Image(systemName: "chevron.right")
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(
          canOpen(availability)
            ? KaidoTheme.asphalt
            : KaidoTheme.muted
        )
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(
          canOpen(availability)
            ? KaidoTheme.positionCyan
            : KaidoTheme.steel.opacity(0.4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11))
      }
      .buttonStyle(.plain)
      .disabled(!canOpen(availability))
      .accessibilityIdentifier("saved-route-open-\(record.id)")
      .accessibilityValue(availabilityTitle(availability))

      lifecycleControls(record)
    }
    .padding(12)
    .background(KaidoTheme.asphalt.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("saved-route-record-\(record.id)")
  }

  private func lifecycleControls(
    _ record: SavedRouteRecord
  ) -> some View {
    HStack(spacing: 7) {
      lifecycleButton(
        title: copy.resolve(
          japanese: "名前",
          simplifiedChinese: "重命名",
          english: "Rename"
        ),
        symbol: "pencil",
        identifier: "saved-route-rename-\(record.id)"
      ) {
        renameName = record.displayName
        renameRecordID = record.id
      }
      lifecycleButton(
        title: copy.resolve(
          japanese: "書き出す",
          simplifiedChinese: "导出",
          english: "Export"
        ),
        symbol: "square.and.arrow.up",
        identifier: "saved-route-export-\(record.id)"
      ) {
        prepareExport(record)
      }
      lifecycleButton(
        title: copy.resolve(
          japanese: "削除",
          simplifiedChinese: "删除",
          english: "Delete"
        ),
        symbol: "trash",
        color: KaidoTheme.evidenceCoral,
        identifier: "saved-route-delete-\(record.id)"
      ) {
        deleteRecordID = record.id
      }
    }
  }

  private func lifecycleButton(
    title: String,
    symbol: String,
    color: Color = KaidoTheme.muted,
    identifier: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: symbol)
        Text(title)
      }
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(color)
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .background(KaidoTheme.steel.opacity(0.22))
      .clipShape(RoundedRectangle(cornerRadius: 9))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(identifier)
  }

  private func prepareExport(_ record: SavedRouteRecord) {
    guard
      let data = model.exportSharedRoute(recordID: record.id)
    else {
      return
    }
    do {
      exportDocument = try SharedRouteFileDocument(data: data)
      exportFileName = SharedRouteFileDocument.exportFileName(record.displayName)
      transferErrorCode = nil
      isExporting = true
    } catch {
      exportDocument = nil
      transferErrorCode = "SAVED_ROUTE_EXPORT_DOCUMENT_INVALID"
    }
  }

  private var importing: Binding<Bool> {
    importPresentation ?? $isImporting
  }

  private func importSharedRoute(
    _ result: Result<[URL], Error>
  ) {
    transferErrorCode = importSavedRouteFile(result, into: model)
  }

  private var renamePresentation: Binding<Bool> {
    Binding(
      get: { renameRecordID != nil },
      set: {
        if !$0 {
          renameRecordID = nil
        }
      }
    )
  }

  private var deletePresentation: Binding<Bool> {
    Binding(
      get: { deleteRecordID != nil },
      set: {
        if !$0 {
          deleteRecordID = nil
        }
      }
    )
  }

  private func canOpen(
    _ availability: SavedRouteLibraryAvailability
  ) -> Bool {
    switch availability {
    case .selected, .currentSnapshot:
      true
    case .unavailable, .ambiguous, .invalid:
      false
    }
  }

  private func availabilityTitle(
    _ availability: SavedRouteLibraryAvailability
  ) -> String {
    switch availability {
    case .selected:
      copy.resolve(japanese: "選択可能", simplifiedChinese: "可选择", english: "Available")
    case .currentSnapshot:
      copy.resolve(japanese: "選択可能", simplifiedChinese: "可选择", english: "Available")
    case .unavailable:
      copy.resolve(japanese: "地図の更新が必要", simplifiedChinese: "需要更新地图", english: "Map update needed")
    case .ambiguous:
      copy.resolve(japanese: "ルートを確認できません", simplifiedChinese: "无法确认路线", english: "Route unavailable")
    case .invalid:
      copy.resolve(japanese: "無効なファイル", simplifiedChinese: "文件无效", english: "Invalid file")
    }
  }

  private func availabilityColor(
    _ availability: SavedRouteLibraryAvailability
  ) -> Color {
    switch availability {
    case .selected, .currentSnapshot:
      KaidoTheme.positionCyan
    case .unavailable:
      KaidoTheme.signalAmber
    case .ambiguous, .invalid:
      KaidoTheme.evidenceCoral
    }
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}

struct SavedRouteSavePanel: View {
  @ObservedObject var library: SavedRouteLibraryModel
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @State private var displayName = ""

  let routePlan: RoutePlan?
  let save: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(
        copy.resolve(
          japanese: "このルートを保存",
          simplifiedChinese: "保存这条路线",
          english: "Save this route"
        )
      )
      .font(.system(size: 15, weight: .black, design: .rounded))
      .foregroundStyle(KaidoTheme.routeWhite)

      Text(
        copy.resolve(
          japanese:
            "RoutePlan、snapshot、全 occurrence を一つの値として保存します。保存だけではナビ可能になりません。",
          simplifiedChinese:
            "RoutePlan、snapshot 与全部 occurrence 会作为一个完整值保存；保存本身不会使路线可导航。",
          english:
            "The RoutePlan, snapshot, and every occurrence are saved as one value. Saving alone never makes it navigable."
        )
      )
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(KaidoTheme.muted)
      .fixedSize(horizontal: false, vertical: true)

      TextField(
        copy.resolve(
          japanese: "ルート名",
          simplifiedChinese: "路线名称",
          english: "Route name"
        ),
        text: $displayName
      )
      .textInputAutocapitalization(.words)
      .autocorrectionDisabled()
      .padding(.horizontal, 12)
      .frame(height: 42)
      .background(KaidoTheme.asphalt)
      .clipShape(RoundedRectangle(cornerRadius: 11))
      .foregroundStyle(KaidoTheme.routeWhite)
      .accessibilityIdentifier("saved-route-name")

      Button {
        save(displayName)
      } label: {
        HStack {
          Image(systemName: "bookmark.fill")
          Text(
            copy.resolve(
              japanese: "ルートを保存",
              simplifiedChinese: "保存路线",
              english: "Save route"
            )
          )
          Spacer()
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(
          canSave ? KaidoTheme.asphalt : KaidoTheme.muted
        )
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(
          canSave
            ? KaidoTheme.signalAmber
            : KaidoTheme.steel.opacity(0.4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11))
      }
      .buttonStyle(.plain)
      .disabled(!canSave)
      .accessibilityIdentifier("saved-route-save")
      .accessibilityValue(library.lastErrorCode ?? "READY")

      if library.lastSavedRecordID != nil {
        Text(copy.resolve(japanese: "保存しました", simplifiedChinese: "已保存", english: "Route saved"))
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.positionCyan)
          .accessibilityIdentifier("saved-route-save-success")
      } else if let error = library.lastErrorCode,
        error
          != SavedRouteLibraryModelError.storeUnavailable.rawValue
      {
        Text(error)
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.evidenceCoral)
          .accessibilityIdentifier("saved-route-save-error")
      }
    }
    .padding(14)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .stroke(KaidoTheme.signalAmber.opacity(0.46), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("saved-route-save-panel")
  }

  private var canSave: Bool {
    routePlan != nil
      && library.storageAvailable
      && !displayName.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).isEmpty
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}
