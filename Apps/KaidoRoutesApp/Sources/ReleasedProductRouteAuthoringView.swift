import Foundation
import KaidoDomain
import KaidoPresentation
import SwiftUI

struct ReleasedProductRouteAuthoringPanel: View {
  @Environment(\.kaidoInterfaceLocale) private var interfaceLocale
  @ObservedObject var model: ReleasedProductRouteAuthoringModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if model.hasSelection {
        selectedRoute
      } else {
        routeCatalog
      }
    }
    .padding(16)
    .background(KaidoTheme.instrument)
    .clipShape(RoundedRectangle(cornerRadius: 22))
    .overlay {
      RoundedRectangle(cornerRadius: 22)
        .stroke(KaidoTheme.positionCyan.opacity(0.42), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("released-route-authoring-panel")
  }

  private var routeCatalog: some View {
    VStack(alignment: .leading, spacing: 12) {
      panelHeader(
        title: copy.resolve(
          japanese: "リリース済み経路を選択",
          simplifiedChinese: "选择已发布路线",
          english: "Choose a released route"
        ),
        detail: copy.resolve(
          japanese:
            "各候補は一つの検証済み RoutePlan と完全な編集レシピに固定されています。",
          simplifiedChinese:
            "每个候选都绑定一份完整验证的 RoutePlan 与编辑配方。",
          english:
            "Each option is bound to one fully validated RoutePlan and authoring recipe."
        )
      )

      ForEach(model.options) { option in
        Button {
          model.selectRelease(option.productReleaseID)
        } label: {
          VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
              Text(option.entranceTitle)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(KaidoTheme.routeWhite)

              Spacer(minLength: 8)

              Text(String(format: "%.1f km", option.actualDistanceKM))
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(KaidoTheme.signalAmber)
            }

            Text(option.finalChoiceTitle)
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(KaidoTheme.positionCyan)

            HStack(spacing: 8) {
              Text(
                copy.resolve(
                  japanese: "\(option.decisionCount) 分岐",
                  simplifiedChinese: "\(option.decisionCount) 个分岔",
                  english: "\(option.decisionCount) decisions"
                )
              )
              if option.hasGuidanceAudio {
                Text("AUDIO")
              }
            }
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundStyle(KaidoTheme.muted)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(13)
          .background(KaidoTheme.asphalt.opacity(0.5))
          .clipShape(RoundedRectangle(cornerRadius: 14))
          .overlay {
            RoundedRectangle(cornerRadius: 14)
              .stroke(KaidoTheme.steel.opacity(0.78), lineWidth: 1)
          }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
          "released-route-option-\(option.productReleaseID)"
        )
        .accessibilityLabel(
          "\(option.entranceTitle)；\(option.finalChoiceTitle)"
        )
        .accessibilityValue("RELEASED_ROUTE_OPTION")
      }
    }
  }

  @ViewBuilder
  private var selectedRoute: some View {
    if let option = model.options.first(where: {
      $0.productReleaseID == model.selectedReleaseID
    }) {
      VStack(alignment: .leading, spacing: 13) {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text(option.entranceTitle)
              .font(.system(size: 18, weight: .black, design: .rounded))
              .foregroundStyle(KaidoTheme.routeWhite)

            Text(option.finalChoiceTitle)
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(KaidoTheme.positionCyan)

            Text(verbatim: option.productReleaseID)
              .font(.system(size: 8, weight: .medium, design: .monospaced))
              .foregroundStyle(KaidoTheme.muted)
          }

          Spacer(minLength: 8)

          Button {
            model.clearSelection()
          } label: {
            Text(
              copy.resolve(
                japanese: "経路を変更",
                simplifiedChinese: "更换路线",
                english: "Change route"
              )
            )
            .font(.system(size: 11, weight: .black))
          }
          .buttonStyle(.bordered)
          .tint(KaidoTheme.muted)
          .accessibilityIdentifier("released-route-change")
        }

        if let step = model.currentStep {
          releasedStep(step)
        } else if model.compiledRoutePlan == nil {
          compileControl
        }

        if let routePlan = model.compiledRoutePlan {
          compiledIdentity(routePlan)
          vehicleClassPicker
          paymentMethodPicker
        }

        if let errorCode = model.lastErrorCode {
          ReviewBoundaryCard(
            symbol: "exclamationmark.shield.fill",
            title: blockedTitle(errorCode),
            detail: blockedDetail(errorCode),
            code: errorCode,
            color: KaidoTheme.evidenceCoral
          )
          .accessibilityIdentifier("released-route-authoring-blocker")

          if canRefreshPreDriveEvidence(errorCode) {
            Button {
              model.refreshPreDriveReview()
            } label: {
              Label(
                copy.resolve(
                  japanese: "出発前証拠を再確認",
                  simplifiedChinese: "重新检查行前证据",
                  english: "Refresh pre-drive evidence"
                ),
                systemImage: "arrow.clockwise"
              )
              .frame(maxWidth: .infinity)
              .font(.system(size: 13, weight: .black))
            }
            .buttonStyle(.borderedProminent)
            .tint(KaidoTheme.positionCyan)
            .accessibilityIdentifier("released-pre-drive-refresh")
          }
        }

        if model.reviewReady {
          ReviewBoundaryCard(
            symbol: "checkmark.seal.fill",
            title: copy.resolve(
              japanese: "リリース経路と出発前証拠が一致",
              simplifiedChinese: "发布路线与行前证据一致",
              english: "Released route and pre-drive evidence match"
            ),
            detail: copy.resolve(
              japanese:
                "選択した車種区分と支払方法、コンパイル済み RoutePlan、料金記録、通行状態は同じ走行セッションに固定されています。",
              simplifiedChinese:
                "所选车型与支付方式、编译 RoutePlan、计费记录与通行状态均已绑定同一行程会话。",
              english:
                "The selected vehicle class and payment method, compiled RoutePlan, tariff record, and passage state are bound to the same drive session."
            ),
            code: "RELEASED PRE-DRIVE · READY",
            color: KaidoTheme.positionCyan
          )
          .accessibilityIdentifier("released-route-review-ready")
        }
      }
    }
  }

  private func releasedStep(
    _ step: ReleasedRouteEditorStepPresentation
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(step.decisionTitle)
        .font(.system(size: 15, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)

      Button {
        model.selectReleasedChoice(step.choiceID)
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          Text(step.choiceTitle)
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(KaidoTheme.asphalt)

          Text(step.choiceDetail)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(KaidoTheme.asphalt.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(KaidoTheme.signalAmber)
        .clipShape(RoundedRectangle(cornerRadius: 13))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("released-route-choice-\(step.choiceID)")
      .accessibilityLabel("\(step.choiceTitle)；\(step.choiceDetail)")
      .accessibilityValue("RELEASED_RECIPE_CHOICE")
    }
    .padding(12)
    .background(KaidoTheme.asphalt.opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private var compileControl: some View {
    Button {
      model.compile()
    } label: {
      Label(
        copy.resolve(
          japanese: "リリース経路をコンパイル",
          simplifiedChinese: "编译发布路线",
          english: "Compile released route"
        ),
        systemImage: "checkmark.seal.fill"
      )
      .frame(maxWidth: .infinity)
      .font(.system(size: 14, weight: .black))
    }
    .buttonStyle(.borderedProminent)
    .tint(KaidoTheme.signalAmber)
    .foregroundStyle(KaidoTheme.asphalt)
    .disabled(!model.canCompile)
    .accessibilityIdentifier("released-route-compile")
  }

  private var vehicleClassPicker: some View {
    VStack(alignment: .leading, spacing: 10) {
      panelHeader(
        title: copy.resolve(
          japanese: "この走行の車種区分",
          simplifiedChinese: "选择本次行程的车型",
          english: "Choose the vehicle class for this drive"
        ),
        detail: copy.resolve(
          japanese:
            "首都高の公式5区分から選択します。支払方法は別に選択します。",
          simplifiedChinese:
            "请从首都高官方五类车型中选择；支付方式另行选择。",
          english:
            "Choose one of Shuto Expressway's five official classes. Select payment separately."
        )
      )

      ForEach(model.availableVehicleClasses, id: \.rawValue) { vehicleClass in
        let isSelected = model.selectedVehicleClass == vehicleClass
        Button {
          model.selectVehicleClass(vehicleClass)
        } label: {
          HStack(spacing: 10) {
            Image(
              systemName: isSelected
                ? "checkmark.circle.fill"
                : "circle"
            )
            .foregroundStyle(
              isSelected ? KaidoTheme.signalAmber : KaidoTheme.muted
            )

            VStack(alignment: .leading, spacing: 2) {
              Text(vehicleClassTitle(vehicleClass))
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(KaidoTheme.routeWhite)
              Text(
                "\(vehicleClass.rawValue) · \(vehicleClass.officialJapaneseLabel)"
              )
              .font(.system(size: 8, weight: .bold, design: .monospaced))
              .foregroundStyle(KaidoTheme.muted)
            }

            Spacer(minLength: 4)
          }
          .padding(11)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            isSelected
              ? KaidoTheme.signalAmber.opacity(0.12)
              : KaidoTheme.asphalt.opacity(0.45)
          )
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .overlay {
            RoundedRectangle(cornerRadius: 12)
              .stroke(
                isSelected
                  ? KaidoTheme.signalAmber.opacity(0.72)
                  : KaidoTheme.steel.opacity(0.55),
                lineWidth: 1
              )
          }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
          "released-vehicle-class-\(vehicleClass.rawValue)"
        )
        .accessibilityLabel(
          "\(vehicleClassTitle(vehicleClass))；\(vehicleClass.officialJapaneseLabel)"
        )
        .accessibilityValue(isSelected ? "SELECTED" : "NOT_SELECTED")
      }
    }
    .padding(12)
    .background(KaidoTheme.asphalt.opacity(0.34))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private var paymentMethodPicker: some View {
    VStack(alignment: .leading, spacing: 10) {
      panelHeader(
        title: copy.resolve(
          japanese: "この走行の支払方法",
          simplifiedChinese: "选择本次行程的支付方式",
          english: "Choose the payment method for this drive"
        ),
        detail: copy.resolve(
          japanese:
            "選択だけでは入口の利用可否を証明しません。経路ごとの証拠が必要です。",
          simplifiedChinese:
            "选择支付方式并不证明入口可用；仍需路线对应的当前证据。",
          english:
            "Selection does not prove entrance availability; current route-specific evidence is still required."
        )
      )

      HStack(spacing: 8) {
        ForEach(model.availablePaymentMethods, id: \.rawValue) { paymentMethod in
          let isSelected = model.selectedPaymentMethod == paymentMethod
          Button {
            model.selectPaymentMethod(paymentMethod)
          } label: {
            VStack(alignment: .leading, spacing: 3) {
              Text(paymentMethodTitle(paymentMethod))
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(KaidoTheme.routeWhite)
              Text(paymentMethod.rawValue)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(KaidoTheme.muted)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              isSelected
                ? KaidoTheme.positionCyan.opacity(0.14)
                : KaidoTheme.asphalt.opacity(0.45)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
              RoundedRectangle(cornerRadius: 12)
                .stroke(
                  isSelected
                    ? KaidoTheme.positionCyan.opacity(0.72)
                    : KaidoTheme.steel.opacity(0.55),
                  lineWidth: 1
                )
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier(
            "released-payment-method-\(paymentMethod.rawValue)"
          )
          .accessibilityLabel(paymentMethodTitle(paymentMethod))
          .accessibilityValue(isSelected ? "SELECTED" : "NOT_SELECTED")
        }
      }
    }
    .padding(12)
    .background(KaidoTheme.asphalt.opacity(0.34))
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private func compiledIdentity(_ routePlan: RoutePlan) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "point.3.connected.trianglepath.dotted")
        .foregroundStyle(KaidoTheme.positionCyan)

      VStack(alignment: .leading, spacing: 2) {
        Text(
          copy.resolve(
            japanese: "正確な occurrence 順序を保持",
            simplifiedChinese: "已保留精确 occurrence 顺序",
            english: "Exact occurrence order retained"
          )
        )
        .font(.system(size: 12, weight: .black))
        .foregroundStyle(KaidoTheme.routeWhite)

        Text(
          "\(routePlan.occurrences.count) OCCURRENCES · "
            + "\(routePlan.actualDistanceKM.map { String(format: "%.1f KM", $0) } ?? "—")"
        )
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .foregroundStyle(KaidoTheme.muted)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(KaidoTheme.positionCyan.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 13))
  }

  private func panelHeader(title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 18, weight: .black, design: .rounded))
        .foregroundStyle(KaidoTheme.routeWhite)
      Text(detail)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(KaidoTheme.muted)
    }
  }

  private func blockedTitle(_ code: String) -> String {
    if code
      == ReleasedProductRouteAuthoringError.vehicleClassRequired.rawValue
    {
      return copy.resolve(
        japanese: "車種区分を選択してください",
        simplifiedChinese: "请选择车型",
        english: "Choose a vehicle class"
      )
    }
    if code
      == ReleasedProductRouteAuthoringError.paymentMethodRequired.rawValue
    {
      return copy.resolve(
        japanese: "支払方法を選択してください",
        simplifiedChinese: "请选择支付方式",
        english: "Choose a payment method"
      )
    }
    if code
      == ReleasedProductRouteAuthoringError.preDriveEvidenceUnavailable.rawValue
    {
      return copy.resolve(
        japanese: "現在の出発前証拠がありません",
        simplifiedChinese: "缺少当前行前证据",
        english: "Current pre-drive evidence is unavailable"
      )
    }
    if code == PreDriveEvidenceResolutionError.expired.code {
      return copy.resolve(
        japanese: "出発前証拠の有効期限が切れました",
        simplifiedChinese: "行前证据已过期",
        english: "Pre-drive evidence has expired"
      )
    }
    if code == PreDriveEvidenceResolutionError.notYetValid.code {
      return copy.resolve(
        japanese: "出発前証拠はまだ有効ではありません",
        simplifiedChinese: "行前证据尚未生效",
        english: "Pre-drive evidence is not yet valid"
      )
    }
    if code == PreDriveEvidenceResolutionError.profileUnavailable.code {
      return copy.resolve(
        japanese: "この料金区分の証拠がありません",
        simplifiedChinese: "缺少该计费组合的证据",
        english: "Evidence is unavailable for this tariff profile"
      )
    }
    if isRejectedPreDriveEvidence(code) {
      return copy.resolve(
        japanese: "出発前証拠が一致しません",
        simplifiedChinese: "行前证据不匹配",
        english: "Pre-drive evidence does not match"
      )
    }
    return copy.resolve(
      japanese: "リリース経路を続行できません",
      simplifiedChinese: "发布路线无法继续",
      english: "Released route cannot continue"
    )
  }

  private func blockedDetail(_ code: String) -> String {
    if code
      == ReleasedProductRouteAuthoringError.vehicleClassRequired.rawValue
    {
      return copy.resolve(
        japanese:
          "料金証拠を要求する前に、この走行の首都高車種区分を明示的に選択してください。",
        simplifiedChinese:
          "请求计费证据前，请明确选择本次行程对应的首都高车型分类。",
        english:
          "Select this drive's Shuto vehicle class before requesting tariff evidence."
      )
    }
    if code
      == ReleasedProductRouteAuthoringError.paymentMethodRequired.rawValue
    {
      return copy.resolve(
        japanese:
          "料金証拠を要求する前に、この走行の ETC または現金を明示的に選択してください。",
        simplifiedChinese:
          "请求计费证据前，请明确选择本次行程使用 ETC 或现金。",
        english:
          "Select ETC or cash for this drive before requesting tariff evidence."
      )
    }
    if code
      == ReleasedProductRouteAuthoringError.preDriveEvidenceUnavailable.rawValue
    {
      return copy.resolve(
        japanese:
          "同じ RoutePlan に結び付く料金記録と通行状態が届くまで、ナビを開始しません。",
        simplifiedChinese:
          "在取得绑定同一 RoutePlan 的计费记录与通行状态前，不会启动导航。",
        english:
          "Navigation stays locked until tariff and passage evidence for this exact RoutePlan is available."
      )
    }
    if code == PreDriveEvidenceResolutionError.expired.code {
      return copy.resolve(
        japanese:
          "期限切れの料金・通行証拠は使用しません。更新された証拠パッケージが必要です。",
        simplifiedChinese:
          "不会使用过期的计费与通行证据；需要更新后的证据包。",
        english:
          "Expired tariff and passage evidence is never used. An updated evidence bundle is required."
      )
    }
    if code == PreDriveEvidenceResolutionError.notYetValid.code {
      return copy.resolve(
        japanese:
          "この証拠の有効期間が始まるまでナビを開始しません。",
        simplifiedChinese:
          "在该证据有效期开始前不会启动导航。",
        english:
          "Navigation stays locked until this evidence validity window begins."
      )
    }
    if code == PreDriveEvidenceResolutionError.profileUnavailable.code {
      return copy.resolve(
        japanese:
          "選択した車種区分と支払方法に完全一致する証拠記録がありません。",
        simplifiedChinese:
          "没有与所选车型和支付方式完全匹配的证据记录。",
        english:
          "No evidence record exactly matches the selected vehicle class and payment method."
      )
    }
    if code
      == PreDriveReviewEvaluationError.sessionVehicleClassMismatch.code
    {
      return copy.resolve(
        japanese:
          "選択した車種区分と、証拠提供者が返した車種区分が一致しません。",
        simplifiedChinese:
          "所选车型与证据提供器返回的车型不一致。",
        english:
          "The selected vehicle class does not match the class returned by the evidence provider."
      )
    }
    if code
      == PreDriveReviewEvaluationError.sessionPaymentMethodMismatch.code
    {
      return copy.resolve(
        japanese:
          "選択した支払方法と、証拠提供者が返した支払方法が一致しません。",
        simplifiedChinese:
          "所选支付方式与证据提供器返回的支付方式不一致。",
        english:
          "The selected payment method does not match the method returned by the evidence provider."
      )
    }
    if code
      == PreDriveReviewEvaluationError.tariffVehicleClassMismatch.code
    {
      return copy.resolve(
        japanese:
          "証拠セット内の料金記録に異なる車種区分が含まれています。",
        simplifiedChinese:
          "证据集中包含了其他车型的计费记录。",
        english:
          "The evidence set contains a tariff record for another vehicle class."
      )
    }
    if code
      == PreDriveReviewEvaluationError.tariffPaymentMethodMismatch.code
    {
      return copy.resolve(
        japanese:
          "証拠セット内の料金記録に異なる支払方法が含まれています。",
        simplifiedChinese:
          "证据集中包含了其他支付方式的计费记录。",
        english:
          "The evidence set contains a tariff record for another payment method."
      )
    }
    if isRejectedPreDriveEvidence(code) {
      return copy.resolve(
        japanese:
          "RoutePlan、ネットワークスナップショット、料金、または通行証拠が完全一致しません。",
        simplifiedChinese:
          "RoutePlan、网络快照、计费或通行证据未通过精确匹配。",
        english:
          "The RoutePlan, network snapshot, tariff, or passage evidence failed exact matching."
      )
    }
    return copy.resolve(
      japanese: "リリース ID または編集レシピが一致しません。",
      simplifiedChinese: "发布身份或编辑配方不一致。",
      english: "The release identity or authoring recipe does not match."
    )
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }

  private func vehicleClassTitle(_ vehicleClass: ShutoVehicleClass) -> String {
    switch vehicleClass {
    case .lightMotorcycle:
      copy.resolve(
        japanese: "軽・二輪",
        simplifiedChinese: "轻型汽车／摩托车",
        english: "Kei vehicle / motorcycle"
      )
    case .standard:
      copy.resolve(
        japanese: "普通車",
        simplifiedChinese: "普通车",
        english: "Standard vehicle"
      )
    case .medium:
      copy.resolve(
        japanese: "中型車",
        simplifiedChinese: "中型车",
        english: "Medium vehicle"
      )
    case .large:
      copy.resolve(
        japanese: "大型車",
        simplifiedChinese: "大型车",
        english: "Large vehicle"
      )
    case .extraLarge:
      copy.resolve(
        japanese: "特大車",
        simplifiedChinese: "特大型车",
        english: "Extra-large vehicle"
      )
    }
  }

  private func paymentMethodTitle(_ paymentMethod: ShutoPaymentMethod) -> String {
    switch paymentMethod {
    case .etc:
      "ETC"
    case .cash:
      copy.resolve(
        japanese: "現金",
        simplifiedChinese: "现金",
        english: "Cash"
      )
    }
  }

  private func canRefreshPreDriveEvidence(_ code: String) -> Bool {
    code
      == ReleasedProductRouteAuthoringError.preDriveEvidenceUnavailable.rawValue
      || isRejectedPreDriveEvidence(code)
  }

  private func isRejectedPreDriveEvidence(_ code: String) -> Bool {
    code.hasPrefix("PRE_DRIVE_")
      || code
        == ReleasedProductRouteAuthoringError.preDriveEvidenceRejected.rawValue
  }
}
