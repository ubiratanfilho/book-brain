import Foundation

extension Book {
  public mutating func captureKindlePassage(_ text: String) {
    currentChat.excerpt = text
    currentChat.location = KindleCitation.location(in: text, bookTitle: title) ?? ""
  }
}

private enum KindleCitation {
  private static let edition = #/(?i)\b(?:Kindle\h+Edition|Edição\h+(?:do\h+)?Kindle)\.?\h*$/#
  private static let locator =
    #/
    (?i)\b
    (?:
      (pages?|pp?\.|páginas?|págs?\.)
      | (?:Kindle\h+)?(?:locations?|locs?\.?|pos\.|posiç(?:ão|ões)|localizaç(?:ão|ões))(?:\h+(?:do\h+)?Kindle)?
    )
    \h*:?\h* ([0-9]+(?:[,.][0-9]{3})*)
    (?:\h*[-–—]\h*([0-9]+(?:[,.][0-9]{3})*))?
    (?:\h+(?:of|de)\h+[0-9]+(?:[,.][0-9]{3})*)?
    (?![\p{L}\p{N}]|[,.][0-9])
    /#

  static func location(in text: String, bookTitle: String) -> String? {
    let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    guard lines.count > 1, let last = lines.last else { return nil }
    let footer: String
    if let signature = last.firstMatch(of: edition) {
      // A wrapped attribution can span several lines. Start after the known title
      // when possible, so a page mentioned earlier in the passage cannot win.
      let attribution = last[..<signature.range.lowerBound]
      let preceding = lines.dropFirst().dropLast()
      let boundary = preceding.lastIndex { $0.allSatisfy(\.isWhitespace) }
      let start = boundary.map { preceding.index(after: $0) } ?? preceding.startIndex
      let paragraph = (preceding[start...] + [attribution]).joined(separator: " ")
      if let titleRange = paragraph.range(
        of: bookTitle, options: [.backwards, .caseInsensitive, .diacriticInsensitive])
      {
        footer = String(paragraph[titleRange.upperBound...])
      } else {
        footer = String(attribution)
      }
    } else {
      // A plain footer must consist entirely of locators, never prose like “see page 42”.
      footer = last.trimmingCharacters(in: CharacterSet(charactersIn: " \t().[]"))
      let fields = footer.components(separatedBy: CharacterSet(charactersIn: "|·•;"))
      guard
        fields.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).wholeMatch(of: locator) != nil }
        )
      else { return nil }
    }

    var position: String?
    for match in footer.matches(of: locator) {
      let before = footer[..<match.range.lowerBound].last { !$0.isWhitespace }
      let after = footer[match.range.upperBound...].first { !$0.isWhitespace }
      guard before.map({ "([,;|·•".contains($0) }) ?? true,
        after.map({ ")]|;,·•.".contains($0) }) ?? true
      else { continue }
      let range = match.3.map { "–" + $0 } ?? ""
      if match.1 != nil {
        return (range.isEmpty ? "Page " : "Pages ") + match.2 + range
      }
      position = (range.isEmpty ? "Kindle location " : "Kindle locations ") + match.2 + range
    }
    return position
  }
}
