import SwiftUI
import XCTest

@testable import BookBrain

final class AnswerMarkdownTests: XCTestCase {
  @MainActor
  private func render(_ markdown: String) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(
      content: AnswerMarkdown(source: markdown)
        .frame(width: 280).padding(10).foregroundStyle(.black).background(.white)
        .environment(\.colorScheme, .light))
    return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
  }

  @MainActor
  func testThirdLevelHeadingHidesMarkersAndHasDistinctTypography() throws {
    let title = "2. Outlier coletivo"
    let heading = try render("### " + title)
    XCTAssertEqual(
      heading.tiffRepresentation, try render("### " + title + " ###").tiffRepresentation)
    XCTAssertGreaterThan(heading.pixelsHigh, try render(title).pixelsHigh)
  }

  @MainActor
  func testCodeFencesHideLanguageAndPreserveLiteralHashesWhileStreaming() throws {
    let content = "### login → consulta\n  transferência"
    let code = try render("```text\n" + content + "\n```")
    for equivalent in ["~~~\n" + content + "\n~~~", "```text\n" + content] {
      XCTAssertEqual(code.tiffRepresentation, try render(equivalent).tiffRepresentation)
    }
    XCTAssertNotEqual(code.tiffRepresentation, try render(content).tiffRepresentation)
  }
}
