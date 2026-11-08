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

  private func matches(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) throws -> Bool {
    guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh,
      lhs.bitsPerPixel == rhs.bitsPerPixel
    else { return false }
    XCTAssertEqual(lhs.bitsPerSample, 8)
    XCTAssertEqual(rhs.bitsPerSample, 8)
    let left = try XCTUnwrap(lhs.bitmapData)
    let right = try XCTUnwrap(rhs.bitmapData)
    let rowLength = lhs.pixelsWide * lhs.bitsPerPixel / 8
    // Equivalent renders can differ by one intensity level at antialiased edges.
    for y in 0..<lhs.pixelsHigh {
      let a = left.advanced(by: y * lhs.bytesPerRow)
      let b = right.advanced(by: y * rhs.bytesPerRow)
      for i in 0..<rowLength where abs(Int(a[i]) - Int(b[i])) > 1 { return false }
    }
    return true
  }

  @MainActor
  func testThirdLevelHeadingHidesMarkersAndHasDistinctTypography() throws {
    let title = "2. Collective outlier"
    let heading = try render("### " + title)
    XCTAssertTrue(try matches(heading, render("### " + title + " ###")))
    XCTAssertGreaterThan(heading.pixelsHigh, try render(title).pixelsHigh)
  }

  @MainActor
  func testCodeFencesHideLanguageAndPreserveLiteralHashesWhileStreaming() throws {
    let content = "### login → balance inquiry\n  transfer"
    let code = try render("```text\n" + content + "\n```")
    for equivalent in ["~~~\n" + content + "\n~~~", "```text\n" + content] {
      XCTAssertTrue(try matches(code, render(equivalent)))
    }
    XCTAssertFalse(try matches(code, render(content)))
  }
}
