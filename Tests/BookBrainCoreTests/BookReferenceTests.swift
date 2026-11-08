import CoreText
import PDFKit
import XCTest

@testable import BookBrainCore

final class BookReferenceTests: XCTestCase {
  private func makePDF(in directory: URL, pages: [String]) throws -> URL {
    let url = directory.appendingPathComponent("manuscrito.pdf")
    var bounds = CGRect(x: 0, y: 0, width: 500, height: 650)
    let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &bounds, nil))
    for text in pages {
      context.beginPDFPage(nil)
      if !text.isEmpty {
        let attributes = [
          NSAttributedString.Key(kCTFontAttributeName as String):
            CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        ]
        context.textPosition = CGPoint(x: 20, y: 550)
        CTLineDraw(
          CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes)), context)
      } else {
        context.fill(CGRect(x: 100, y: 100, width: 40, height: 60))
      }
      context.endPDFPage()
    }
    context.closePDF()
    return url
  }

  func testManagedCopySurvivesOriginalRemovalAndLimitsQueriesToSelectedDocument() async throws {
    let fm = FileManager.default
    let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: directory) }
    let store = LibraryStore(directory: directory.appendingPathComponent("library"))
    let source = try makePDF(in: directory, pages: ["Prefacio", "O codigo do lacre e Safira.", ""])
    var book = Book(title: "Caderno", author: "Ana Vale")
    book.pdf = try store.importPDF(source, for: book.id)
    XCTAssertEqual(book.pdf?.pageCount, 3)
    var lib = Library()
    lib.books = [book]
    try store.save(lib)
    let restored = try XCTUnwrap(store.load().books.first)
    XCTAssertEqual(restored.author, "Ana Vale")
    XCTAssertEqual(restored.pdf, book.pdf)
    try fm.removeItem(at: source)
    let reader = BookPDFReader(file: store.pdfURL(for: restored.id))
    let hits = try await reader.contents(for: BookPDFReader.search, arguments: ["query": "LACRE"])
    XCTAssertTrue(hits.first?["text"]?.contains("PDF p. 2") == true)
    let page = try await reader.contents(for: BookPDFReader.read, arguments: ["page": 2])
    XCTAssertTrue(page.first?["text"]?.contains("Safira") == true)
    let scan = try await reader.contents(for: BookPDFReader.read, arguments: ["page": 3])
    XCTAssertTrue(scan.last?["imageUrl"]?.hasPrefix("data:image/jpeg;base64,") == true)
    for args: [String: Any] in [
      ["page": 0], ["page": 4], ["page": true], ["page": 1, "path": "/etc/passwd"],
    ] {
      do {
        _ = try await reader.contents(for: BookPDFReader.read, arguments: args)
        XCTFail("Invalid PDF request accepted")
      } catch {}
    }
    book.currentChat.question = "Qual é o código?"
    let payload = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(ReadingPrompt.make(book: book).utf8))
        as? [String: Any])
    XCTAssertEqual(payload["book_author"] as? String, book.author)
    XCTAssertEqual((payload["attached_pdf"] as? [String: Int])?["page_count"], 3)
    XCTAssertFalse(String(describing: payload).contains(store.directory.path))
    let bad = directory.appendingPathComponent("invalid.pdf")
    try Data("not a PDF".utf8).write(to: bad)
    let badID = UUID()
    XCTAssertThrowsError(try store.importPDF(bad, for: badID))
    XCTAssertFalse(fm.fileExists(atPath: store.pdfURL(for: badID).path))
  }

  @MainActor
  func testLiveAttachedBookConsultationAndResume() async throws {
    guard ProcessInfo.processInfo.environment["BOOK_BRAIN_LIVE_TEST"] == "1" else {
      throw XCTSkip("Opt-in Codex integration")
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let seal = String(UUID().uuidString.prefix(8))
    let drawer = String(UUID().uuidString.prefix(8))
    let source = try makePDF(
      in: directory,
      pages: [
        "Caderno da expedicao: prefacio.", "O codigo do lacre e \(seal).",
        "A gaveta tem o codigo \(drawer).",
      ])
    let store = LibraryStore(directory: directory.appendingPathComponent("library"))
    var book = Book(title: "Caderno da expedição sintética", author: "Ana Vale")
    book.pdf = try store.importPDF(source, for: book.id)
    let client = CodexClient(executable: try XCTUnwrap(CodexClient.findExecutable()))
    defer { client.disconnect() }
    for (index, entry) in [("lacre", seal), ("gaveta", drawer)].enumerated() {
      try await client.connect()
      book.currentChat.question =
        "Consulte a página \(index+2) do PDF anexado. Qual é o código de \(entry.0)? Informe o código exato e a página."
      var lookedUp = false
      let answer = try await client.ask(
        prompt: ReadingPrompt.make(book: book), threadID: book.currentChat.threadID,
        pdf: BookPDFReader(file: store.pdfURL(for: book.id)),
        onLookup: { if $0.contains("PDF") { lookedUp = true } }, onUpdate: { _ in })
      XCTAssertTrue(lookedUp, "No executed PDF query")
      XCTAssertTrue(
        answer.text.localizedCaseInsensitiveContains(entry.1),
        "Unexpected synthetic PDF answer: \(answer.text)")
      if let previous = book.currentChat.threadID { XCTAssertEqual(answer.threadID, previous) }
      book.currentChat.threadID = answer.threadID
      client.disconnect()
    }
  }

  @MainActor
  func testLiveBookWebSearch() async throws {
    guard ProcessInfo.processInfo.environment["BOOK_BRAIN_LIVE_TEST"] == "1" else {
      throw XCTSkip("Opt-in web search integration")
    }
    let client = CodexClient(executable: try XCTUnwrap(CodexClient.findExecutable()))
    defer { client.disconnect() }
    try await client.connect()
    var book = Book(title: "Frankenstein", author: "Mary Wollstonecraft Shelley")
    book.currentChat.question =
      "Pesquise agora na web e confira no site do Project Gutenberg o título da obra no registro do ebook 84. Responda em uma frase e inclua o link Markdown do registro consultado."
    var searched = false
    let answer = try await client.ask(
      prompt: ReadingPrompt.make(book: book), threadID: nil,
      onLookup: { if $0.contains("web") { searched = true } }, onUpdate: { _ in })
    XCTAssertTrue(searched, "No hosted web search was observed: \(answer.text)")
    XCTAssertTrue(
      answer.text.contains("gutenberg.org"), "Expected a link to the source: \(answer.text)")
  }
}
