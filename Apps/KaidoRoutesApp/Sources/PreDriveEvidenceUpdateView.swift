import Foundation
import KaidoAppleAdapters
import SwiftUI
import UniformTypeIdentifiers

struct PreDriveEvidenceUpdatePanel: View {
  @ObservedObject var model: PreDriveEvidenceUpdateModel
  let selectedProductReleaseID: String?
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale

  @State private var isImporting = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(
            copy.resolve(
              japanese: "署名済み出発前証拠",
              simplifiedChinese: "签名行前证据更新",
              english: "Signed pre-drive evidence update"
            )
          )
          .font(.system(size: 17, weight: .black, design: .rounded))
          .foregroundStyle(KaidoTheme.routeWhite)

          Text(
            copy.resolve(
              japanese:
                "App を再配布せず、同じリリース経路の料金・通行証拠だけを更新します。",
              simplifiedChinese:
                "无需重新发布 App，只更新同一发布路线的费用与通行证据。",
              english:
                "Refresh tariff and passage evidence for the same release without republishing the App."
            )
          )
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(KaidoTheme.muted)
        }

        Spacer(minLength: 8)

        StatusCapsule(
          title: model.state.label,
          color: stateColor
        )
      }

      VStack(spacing: 8) {
        if let selectedProductReleaseID,
          model.canRefresh(
            productReleaseID: selectedProductReleaseID
          )
            || model.state
              == .refreshing(
                productReleaseID: selectedProductReleaseID
              )
        {
          Button {
            Task {
              await model.refresh(
                productReleaseID: selectedProductReleaseID
              )
            }
          } label: {
            Label(
              copy.resolve(
                japanese: "署名済み証拠を更新",
                simplifiedChinese: "刷新签名证据",
                english: "Refresh signed evidence"
              ),
              systemImage: "arrow.clockwise.shield.fill"
            )
            .frame(maxWidth: .infinity)
            .font(.system(size: 12, weight: .black))
          }
          .buttonStyle(.borderedProminent)
          .tint(KaidoTheme.positionCyan)
          .disabled(
            !model.canRefresh(
              productReleaseID: selectedProductReleaseID
            )
          )
          .accessibilityIdentifier(
            "pre-drive-evidence-update-refresh"
          )
        }

        Button {
          isImporting = true
        } label: {
          Label(
            copy.resolve(
              japanese: "署名済み更新を読み込む",
              simplifiedChinese: "导入签名更新",
              english: "Import signed update"
            ),
            systemImage: "checkmark.shield.fill"
          )
          .frame(maxWidth: .infinity)
          .font(.system(size: 12, weight: .black))
        }
        .buttonStyle(.bordered)
        .tint(KaidoTheme.positionCyan)
        .disabled(!model.canImport)
        .accessibilityIdentifier(
          "pre-drive-evidence-update-import"
        )
      }

      Text(statusDetail)
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(stateColor)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("pre-drive-evidence-update-status")

      Text(
        copy.resolve(
          japanese:
            "署名だけでは証拠を有効にしません。product、RoutePlan、車種、支払方法、出典、時刻、有効期限の全ゲートを再検証します。",
          simplifiedChinese:
            "签名本身不会让证据生效；仍会重新验证 product、RoutePlan、车型、支付方式、来源、时间与有效期。",
          english:
            "A signature alone grants no authority. Product, RoutePlan, profile, source, chronology, and expiry gates are all revalidated."
        )
      )
      .font(.system(size: 9, weight: .medium))
      .foregroundStyle(KaidoTheme.muted)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .stroke(stateColor.opacity(0.55), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("pre-drive-evidence-update-panel")
    .fileImporter(
      isPresented: $isImporting,
      allowedContentTypes: [.json],
      allowsMultipleSelection: false,
      onCompletion: importEnvelope
    )
  }

  private var stateColor: Color {
    switch model.state {
    case .ready, .installed:
      KaidoTheme.positionCyan
    case .refreshing:
      KaidoTheme.signalAmber
    case .unavailable:
      KaidoTheme.muted
    case .blocked:
      KaidoTheme.evidenceCoral
    }
  }

  private var statusDetail: String {
    switch model.state {
    case .unavailable:
      copy.resolve(
        japanese: "この product release には信頼済み公開鍵がありません。",
        simplifiedChinese: "此 product release 未绑定可信公钥。",
        english: "No trusted public key is enrolled for this product release."
      )
    case .ready:
      copy.resolve(
        japanese:
          "\(model.trustedProductCount) 件の product release が署名更新を受け入れます。",
        simplifiedChinese:
          "\(model.trustedProductCount) 个 product release 可接收签名更新。",
        english:
          "\(model.trustedProductCount) product release(s) accept signed updates."
      )
    case .refreshing(let productReleaseID):
      copy.resolve(
        japanese: "\(productReleaseID) の固定 HTTPS 取得先を確認中。",
        simplifiedChinese: "正在检查 \(productReleaseID) 的固定 HTTPS 端点。",
        english:
          "Checking the pinned HTTPS endpoint for \(productReleaseID)."
      )
    case .installed(let productReleaseID, let evidenceReleaseID):
      "\(productReleaseID) · \(evidenceReleaseID)"
    case .blocked(let code):
      code
    }
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }

  private func importEnvelope(
    _ result: Result<[URL], Error>
  ) {
    guard case .success(let urls) = result else {
      return
    }
    guard urls.count == 1, let url = urls.first else {
      model.rejectImport(.importUnreadable)
      return
    }
    let accessing = url.startAccessingSecurityScopedResource()
    defer {
      if accessing {
        url.stopAccessingSecurityScopedResource()
      }
    }
    do {
      let values = try url.resourceValues(
        forKeys: [.isRegularFileKey, .fileSizeKey]
      )
      guard
        values.isRegularFile == true,
        let size = values.fileSize,
        size > 0,
        size <= PreDriveEvidenceUpdateCodec.maximumEnvelopeByteCount
      else {
        model.rejectImport(.importTooLarge)
        return
      }
      model.importEnvelope(
        try Data(contentsOf: url, options: [.mappedIfSafe])
      )
    } catch {
      model.rejectImport(.importUnreadable)
    }
  }
}
