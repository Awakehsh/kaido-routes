import Foundation

/// Renders reviewed locale-specific term pronunciations without mutating the
/// released spoken-text identity used by exact offline-audio lookup.
public enum GuidanceSpokenFormRenderer {
  public static func render(
    spokenText: String,
    spokenForms: [String: String]
  ) -> String {
    let orderedForms =
      spokenForms
      .filter { !$0.key.isEmpty && !$0.value.isEmpty }
      .sorted {
        if $0.key.count != $1.key.count {
          return $0.key.count > $1.key.count
        }
        return $0.key < $1.key
      }
    guard !orderedForms.isEmpty else { return spokenText }

    var rendered = ""
    var cursor = spokenText.startIndex
    while cursor < spokenText.endIndex {
      guard
        let form = orderedForms.first(where: {
          spokenText[cursor...].hasPrefix($0.key)
        })
      else {
        rendered.append(spokenText[cursor])
        cursor = spokenText.index(after: cursor)
        continue
      }

      let upperBound = spokenText.index(
        cursor,
        offsetBy: form.key.count
      )
      let sourceRange = cursor..<upperBound
      if replacementAlreadySurroundsSource(
        in: spokenText,
        sourceRange: sourceRange,
        source: form.key,
        replacement: form.value
      ) {
        rendered.append(contentsOf: spokenText[sourceRange])
      } else {
        rendered.append(contentsOf: form.value)
      }
      cursor = upperBound
    }
    return rendered
  }

  private static func replacementAlreadySurroundsSource(
    in spokenText: String,
    sourceRange: Range<String.Index>,
    source: String,
    replacement: String
  ) -> Bool {
    var searchStart = replacement.startIndex
    while searchStart < replacement.endIndex,
      let embeddedRange = replacement.range(
        of: source,
        range: searchStart..<replacement.endIndex
      )
    {
      let prefix = replacement[..<embeddedRange.lowerBound]
      let suffix = replacement[embeddedRange.upperBound...]
      if spokenText[..<sourceRange.lowerBound].hasSuffix(prefix),
        spokenText[sourceRange.upperBound...].hasPrefix(suffix)
      {
        return true
      }
      searchStart = embeddedRange.upperBound
    }
    return source == replacement
  }
}
