import KaidoPresentation
import Testing

@Test("Reviewed Japanese spoken forms render without mutating release text")
func reviewedJapaneseSpokenFormsRenderDeterministically() {
  let spokenText = "B 湾岸線、横浜方面へ"

  let rendered = GuidanceSpokenFormRenderer.render(
    spokenText: spokenText,
    spokenForms: [
      "B": "ビー",
      "湾岸線": "わんがんせん",
    ]
  )

  #expect(spokenText == "B 湾岸線、横浜方面へ")
  #expect(rendered == "ビー わんがんせん、横浜方面へ")
}

@Test("An already expanded spoken form is not duplicated")
func alreadyExpandedSpokenFormRemainsStable() {
  #expect(
    GuidanceSpokenFormRenderer.render(
      spokenText: "Keep left for Route B toward Yokohama",
      spokenForms: ["B": "Route B"]
    ) == "Keep left for Route B toward Yokohama"
  )
}

@Test("Spoken form rendering is longest-first and non-cascading")
func spokenFormRenderingIsLongestFirstAndNonCascading() {
  #expect(
    GuidanceSpokenFormRenderer.render(
      spokenText: "C1、B",
      spokenForms: [
        "C": "シー",
        "C1": "シーワン",
        "B": "Route B",
        "Route B": "unexpected cascade",
      ]
    ) == "シーワン、Route B"
  )
}
