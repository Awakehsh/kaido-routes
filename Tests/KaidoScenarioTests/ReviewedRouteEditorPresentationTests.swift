import Foundation
import KaidoDomain
import KaidoRouting
import Testing

@Test("Reviewed editor presentation covers every catalog identity and locale")
func reviewedEditorPresentationAcceptsExactCoverage() throws {
  let catalog = presentationEditorCatalog()
  let presentation = presentationCatalog(for: catalog)

  #expect(presentation.validationIssues(for: catalog).isEmpty)
  #expect(
    presentation.title(
      forEntrance: "test.entrance",
      locale: .simplifiedChinese
    ) == "测试入口"
  )
  #expect(
    presentation.title(
      forDecisionPoint: "test.decision",
      locale: .japanese
    ) == "テスト分岐"
  )
  #expect(
    presentation.presentation(forChoice: "test.choice.exit")?
      .detail.value(for: .english) == "Use the reviewed directional exit"
  )

  let data = try JSONEncoder().encode(presentation)
  let decoded = try JSONDecoder().decode(
    ReviewedRouteEditorPresentationCatalog.self,
    from: data
  )
  #expect(decoded == presentation)
}

@Test("Reviewed editor presentation rejects missing, orphaned, and partial labels")
func reviewedEditorPresentationRejectsCoverageDrift() {
  let catalog = presentationEditorCatalog()
  let partialText = RouteEditorLocalizedText(
    values: [.japanese: "出口"]
  )
  let presentation = ReviewedRouteEditorPresentationCatalog(
    id: "test.presentation",
    networkSnapshotID: catalog.networkSnapshotID,
    entrances: [],
    decisionPoints: [
      ReviewedRouteEditorDecisionPresentation(
        decisionPointID: "test.decision.orphan",
        title: partialText
      )
    ],
    choices: [
      ReviewedRouteEditorChoicePresentation(
        choiceID: "test.choice.exit",
        title: partialText,
        detail: partialText
      )
    ]
  )

  let issues = presentation.validationIssues(for: catalog)
  #expect(issues.contains("editor presentation is missing entrance test.entrance"))
  #expect(issues.contains("editor presentation is missing decision point test.decision"))
  #expect(
    issues.contains(
      "editor presentation contains orphan decision point test.decision.orphan"
    )
  )
  #expect(
    issues.contains(
      "choice test.choice.exit title: localized text must cover every release locale exactly"
    )
  )
}

@Test("Reviewed editor presentation refuses unknown locale keys")
func reviewedEditorPresentationRejectsUnknownLocale() {
  let data = Data(#"{"ja-JP":"出口","fr":"Sortie"}"#.utf8)
  #expect(throws: DecodingError.self) {
    try JSONDecoder().decode(RouteEditorLocalizedText.self, from: data)
  }
}

private func presentationEditorCatalog() -> ReviewedRouteEditorCatalog {
  ReviewedRouteEditorCatalog(
    networkSnapshotID: "test.snapshot.presentation",
    entrances: [
      ReviewedRouteEditorEntrance(
        facilityID: "test.entrance",
        initialEdgeID: "test.edge.entry",
        initialEdgeTollDomainID: "test.toll",
        firstDecisionPointID: "test.decision"
      )
    ],
    decisionPoints: [
      ReviewedRouteEditorDecisionPoint(
        id: "test.decision",
        incomingApproachID: "test.approach",
        junctionComplexID: "test.junction",
        choices: [
          ReviewedRouteEditorChoice(
            id: "test.choice.exit",
            movementID: "test.movement.exit",
            movementTollDomainID: "test.toll",
            outgoingEdgeID: "test.edge.exit",
            outgoingEdgeTollDomainID: "test.toll",
            destination: .exitFacility("test.exit")
          )
        ]
      )
    ]
  )
}

private func presentationCatalog(
  for catalog: ReviewedRouteEditorCatalog
) -> ReviewedRouteEditorPresentationCatalog {
  ReviewedRouteEditorPresentationCatalog(
    id: "test.presentation",
    networkSnapshotID: catalog.networkSnapshotID,
    entrances: [
      ReviewedRouteEditorEntrancePresentation(
        facilityID: "test.entrance",
        title: localizedEditorText(
          japanese: "テスト入口",
          chinese: "测试入口",
          english: "Test entrance"
        )
      )
    ],
    decisionPoints: [
      ReviewedRouteEditorDecisionPresentation(
        decisionPointID: "test.decision",
        title: localizedEditorText(
          japanese: "テスト分岐",
          chinese: "测试分岔",
          english: "Test decision"
        )
      )
    ],
    choices: [
      ReviewedRouteEditorChoicePresentation(
        choiceID: "test.choice.exit",
        title: localizedEditorText(
          japanese: "出口へ",
          chinese: "驶向出口",
          english: "Take exit"
        ),
        detail: localizedEditorText(
          japanese: "確認済みの方向別出口を使用",
          chinese: "使用已审核的方向性出口",
          english: "Use the reviewed directional exit"
        )
      )
    ]
  )
}

private func localizedEditorText(
  japanese: String,
  chinese: String,
  english: String
) -> RouteEditorLocalizedText {
  RouteEditorLocalizedText(
    values: [
      .japanese: japanese,
      .simplifiedChinese: chinese,
      .english: english,
    ]
  )
}
