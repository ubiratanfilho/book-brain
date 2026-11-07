import AppKit
import XCTest

@testable import BookBrainCore

final class KindleCitationTests: XCTestCase {
  func testEnglishAndPortugueseCitationsAndStandaloneFooters() {
    let examples = [
      ("A. Reader. Field Notes (p. 42). Sample Press. Kindle Edition.", "Page 42"),
      ("Field Notes (pp. 42–43).\nSample Press. Kindle Edition.", "Pages 42–43"),
      (
        "A. Reader. Field Notes (Kindle Locations 1,212-1,215). Kindle Edition.",
        "Kindle locations 1,212–1,215"
      ),
      ("Caderno (pág. 12). Editora Exemplo. Edição do Kindle.", "Page 12"),
      ("Caderno (posições 1.200–1.240). Edição Kindle.", "Kindle locations 1.200–1.240"),
      ("Location 812 of 9,000", "Kindle location 812"),
      ("Página 42 de 300", "Page 42"),
      ("Location 810 | Page 42", "Page 42"),
      ("Notes (Location 810; Page 42). Kindle Edition.", "Page 42"),
    ]
    for (footer, expected) in examples {
      var book = Book(title: "Field Notes", author: "A. Reader")
      let copied = "Example selection.\r\n\r\n" + footer
      book.captureKindlePassage(copied)
      XCTAssertEqual(book.currentChat.location, expected, footer)
      XCTAssertEqual(book.currentChat.excerpt, copied)
    }
  }

  func testNewCaptureWithoutReferenceClearsPreviousLocationAndIgnoresProse() {
    var book = Book(title: "Field Notes", author: "A. Reader")
    for excerpt in [
      "See page 17 for the explanation.",
      "First paragraph.\nThe exercise refers to page 20.",
      "A citation inside the passage (p. 15).\n\nA. Reader. Field Notes. Kindle Edition.",
      "The first line.\n(p. 15) is a cross-reference.\nA. Reader. Field Notes. Kindle Edition.",
      "The passage.\n\nA. Reader. Page 404 and other stories. Kindle Edition.",
      "First paragraph.\n\nSee the remark (p. 19).\nA. Reader. Field Notes. Kindle Edition.",
      "Example.\nPage 12.5",
    ] {
      book.currentChat.location = "Manual chapter"
      book.captureKindlePassage(excerpt)
      XCTAssertEqual(book.currentChat.location, "", excerpt)
      XCTAssertEqual(book.currentChat.excerpt, excerpt)
    }
  }

  @MainActor
  func testFreshCopySuppliesLocationAndManualCorrectionReachesPrompt() async throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let clipboard = PassageClipboard(board)
    var book = Book(title: "Field Notes", author: "A. Reader")
    book.currentChat.location = "Page 10"
    book.captureKindlePassage(
      try await clipboard.readNewExcerpt {
        board.clearContents()
        board.setString(
          "Synthetic passage.\nA. Reader. Field Notes (p. 42). Kindle Edition.", forType: .string)
      })
    XCTAssertEqual(book.currentChat.location, "Page 42")
    book.currentChat.location = "Page 43, chapter 4"
    book.currentChat.question = "What does this mean?"
    let prompt = try ReadingPrompt.make(book: book)
    let payload = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(prompt.utf8)) as? [String: Any])
    XCTAssertEqual(payload["current_location"] as? String, "Page 43, chapter 4")
  }
}
