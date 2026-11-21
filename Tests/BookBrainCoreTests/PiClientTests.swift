import Foundation
import XCTest

@testable import BookBrainCore

final class PiClientTests: XCTestCase {
  let model = APIModel(provider: .anthropic, id: "example", name: "Example", vision: true)

  func testChatsKeepTheirModelAndOnlyReplayTheirOwnHistory() throws {
    var book = Book(title: "Geometry", author: "Example")
    book.currentChat.apiModel = model
    book.currentChat.exchanges = [
      Exchange(question: "Shape?", excerpt: "", location: "", answer: "Circle")
    ]
    let first = book.currentChat.id
    book.newChat()
    XCTAssertEqual(book.currentChat.apiModel, model)
    book.currentChat.apiModel = nil
    book.currentChat.question = "Hello"
    XCTAssertFalse(try ReadingPrompt.make(book: book).contains("Circle"))
    let restored = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(book))
    book = restored
    book.openChat(first)
    book.currentChat.question = "Why?"
    XCTAssertEqual(book.currentChat.apiModel, model)
    XCTAssertTrue(try ReadingPrompt.make(book: book).contains("Circle"))
  }

  @MainActor
  func testPipeReturnsScopedPDFErrorsAndStreamsAnswer() async throws {
    let exe = try fixture(
      """
      IFS= read -r request
      echo '{"type":"tool","name":"read_book_page","args":{"attachment_id":"foreign","page":1}}'
      IFS= read -r response
      case "$response" in *'not attached'*) ;; *) exit 2 ;; esac
      echo '{"type":"delta","text":"Done"}'
      echo '{"type":"done","text":"Done"}'
      """)
    defer { try? FileManager.default.removeItem(at: exe) }
    let pi = PiClient(executable: exe)
    var updates: [String] = []
    let result = try await pi.ask(
      model: model, key: "synthetic", prompt: "Hello", inputs: [],
      pdf: PDFReferences(book: nil, attachments: [:]), onLookup: {},
      onUpdate: { updates.append($0) })
    XCTAssertEqual(result, "Done")
    XCTAssertEqual(updates, ["Done"])
  }

  @MainActor
  func testStopDuringReplyCancelsWithoutCompleting() async throws {
    let exe = try fixture(
      """
      IFS= read -r request
      echo '{"type":"delta","text":"partial"}'
      IFS= read -r waiting
      """)
    defer { try? FileManager.default.removeItem(at: exe) }
    let pi = PiClient(executable: exe)
    do {
      _ = try await pi.ask(
        model: model, key: "synthetic", prompt: "Hello", inputs: [], pdf: nil,
        onLookup: {}, onUpdate: { _ in pi.cancel() })
      XCTFail("Expected cancellation")
    } catch is CancellationError {}
  }

  private func fixture(_ body: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    return url
  }
}
