import Foundation
import KaidoDomain
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

          if errorCode
            == ReleasedProductRouteAuthoringError
            .preDriveEvidenceUnavailable.rawValue
          {
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
                "コンパイル済み RoutePlan、料金記録、通行状態は同じ RoutePlan とネットワークスナップショットに固定されています。",
              simplifiedChinese:
                "编译 RoutePlan、计费记录与通行状态均已绑定同一 RoutePlan 与网络快照。",
              english:
                "The compiled RoutePlan, tariff record, and passage state are bound to the same RoutePlan and network snapshot."
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
      == ReleasedProductRouteAuthoringError.preDriveEvidenceUnavailable.rawValue
    {
      return copy.resolve(
        japanese: "現在の出発前証拠がありません",
        simplifiedChinese: "缺少当前行前证据",
        english: "Current pre-drive evidence is unavailable"
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
    return copy.resolve(
      japanese: "リリース ID または編集レシピが一致しません。",
      simplifiedChinese: "发布身份或编辑配方不一致。",
      english: "The release identity or authoring recipe does not match."
    )
  }

  private var copy: KaidoInterfaceText {
    KaidoInterfaceText(locale: interfaceLocale)
  }
}
