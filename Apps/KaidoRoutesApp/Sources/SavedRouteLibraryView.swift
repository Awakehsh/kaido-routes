import KaidoDomain
import SwiftUI

struct SavedRouteLibraryPanel: View {
  @ObservedObject var model: SavedRouteLibraryModel
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

  let openRecord: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header

      if model.records.isEmpty {
        emptyState
      } else {
        ForEach(model.records, id: \.id) { record in
          recordCard(record)
        }
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
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(
          copy.resolve(
            japanese: "保存したルート",
            simplifiedChinese: "已保存路线",
            english: "Saved routes"
          )
        )
        .font(.system(size: 18, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)

        Text(
          copy.resolve(
            japanese:
              "保存はナビ権限を作りません。現在のリリースと RoutePlan 全体が一致したルートだけを駐車中 editor で開けます。",
            simplifiedChinese:
              "保存不会产生导航权限；只有与当前发布包完整 RoutePlan 一致的路线才能在停车编辑器中重新打开。",
            english:
              "Saving grants no navigation authority. Only a whole-RoutePlan match to one current release can reopen in the parked editor."
          )
        )
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(KaidoTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 8)

      StatusCapsule(
        title: "\(model.records.count) SAVED",
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
            "Application Support を使用できないため、メモリだけの保存にはフォールバックしません。",
          simplifiedChinese:
            "Application Support 不可用，因此不会退回到假装持久化的内存存储。",
          english:
            "Application Support is unavailable, so the app does not pretend an in-memory value was persisted."
        ),
      code:
        model.lastErrorCode
        ?? SavedRouteLibraryModelError.storeUnavailable.rawValue,
      color:
        model.storageAvailable
        ? KaidoTheme.steel
        : KaidoTheme.evidenceCoral
    )
    .accessibilityIdentifier("saved-route-library-empty")
  }

  private func recordCard(_ record: SavedRouteRecord) -> some View {
    let availability = model.availability(for: record)
    return VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          Text(record.displayName)
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(KaidoTheme.routeWhite)

          Text(
            "\(record.document.routePlan.occurrences.count) OCCURRENCES"
              + " · \(record.origin.rawValue)"
          )
          .font(.system(size: 8, weight: .black, design: .monospaced))
          .foregroundStyle(KaidoTheme.muted)
        }

        Spacer(minLength: 8)

        StatusCapsule(
          title: availabilityTitle(availability),
          color: availabilityColor(availability)
        )
      }

      Text(verbatim: record.document.routePlan.id)
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)
        .lineLimit(2)

      Text(verbatim: record.document.routePlan.networkSnapshotID)
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)
        .lineLimit(2)

      Button {
        openRecord(record.id)
      } label: {
        HStack {
          Image(systemName: "arrowshape.turn.up.right.fill")
          Text(
            copy.resolve(
              japanese: "駐車中 editor で開く",
              simplifiedChinese: "在停车编辑器中打开",
              english: "Open in parked editor"
            )
          )
          Spacer()
          Image(systemName: "chevron.right")
        }
        .font(.system(size: 11, weight: .black))
        .foregroundStyle(
          canOpen(availability)
            ? KaidoTheme.asphalt
            : KaidoTheme.muted
        )
        .padding(.horizontal, 12)
        .frame(height: 40)
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
    }
    .padding(12)
    .background(KaidoTheme.asphalt.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("saved-route-record-\(record.id)")
  }

  private func canOpen(
    _ availability: SavedRouteLibraryAvailability
  ) -> Bool {
    if case .selected = availability { return true }
    return false
  }

  private func availabilityTitle(
    _ availability: SavedRouteLibraryAvailability
  ) -> String {
    switch availability {
    case .selected:
      "CURRENT RELEASE"
    case .unavailable:
      "REVIEW REQUIRED"
    case .ambiguous:
      "AMBIGUOUS"
    case .invalid:
      "INVALID"
    }
  }

  private func availabilityColor(
    _ availability: SavedRouteLibraryAvailability
  ) -> Color {
    switch availability {
    case .selected:
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
      .font(.system(size: 9, weight: .semibold))
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
              japanese: "Application Support に保存",
              simplifiedChinese: "保存到 Application Support",
              english: "Save to Application Support"
            )
          )
          Spacer()
        }
        .font(.system(size: 11, weight: .black))
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

      if let savedID = library.lastSavedRecordID {
        Text("SAVED · \(savedID)")
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
