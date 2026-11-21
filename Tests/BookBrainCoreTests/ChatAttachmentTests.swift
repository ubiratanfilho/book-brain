import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest

@testable import BookBrainCore

final class ChatAttachmentTests: XCTestCase {
  private func pdf(_ url: URL, text: String) throws {
    var bounds = CGRect(x: 0, y: 0, width: 300, height: 400)
    let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &bounds, nil))
    context.beginPDFPage(nil)
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(
        string: text,
        attributes: [
          .init(kCTFontAttributeName as String): CTFontCreateWithName(
            "Helvetica" as CFString, 12, nil)
        ]))
    context.textPosition = CGPoint(x: 20, y: 300)
    CTLineDraw(line, context)
    context.endPDFPage()
    context.closePDF()
  }

  func testManagedAttachmentsSurviveSourceRemovalAndStayPrivateAndChatScoped() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = LibraryStore(directory: directory.appendingPathComponent("library"))
    var book = Book(title: "Synthetic Notes", author: "Test author")
    let original = directory.appendingPathComponent("notes.md")
    try Data("Synthetic note: the marker is amber.".utf8).write(to: original)
    let text = try store.importAttachment(original, bookID: book.id, chatID: book.currentChat.id)
    try FileManager.default.removeItem(at: original)
    book.currentChat.attachments = [text]
    XCTAssertFalse(book.currentChat.isBlank)
    XCTAssertEqual(book.currentChat.title, "notes.md")
    let inputs = try store.attachmentInputs([text], bookID: book.id, chatID: book.currentChat.id)
    let value = try XCTUnwrap(inputs.first?["text"] as? String)
    XCTAssertTrue(value.contains("amber"))
    XCTAssertFalse(value.contains(directory.path))
    XCTAssertFalse(try ReadingPrompt.make(book: book).contains(directory.path))
    let file = store.attachmentURL(text, bookID: book.id, chatID: book.currentChat.id)
    XCTAssertEqual(
      try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int, 0o600)
    XCTAssertThrowsError(
      try store.attachmentInputs([text], bookID: UUID(), chatID: book.currentChat.id))
    XCTAssertThrowsError(try store.attachmentInputs([text], bookID: book.id, chatID: UUID()))
    var library = Library()
    library.books = [book]
    library.selectedBookID = book.id
    try store.save(library)
    XCTAssertEqual(try store.load(), library)
    library.books[0].newChat()
    XCTAssertTrue(library.books[0].currentChat.attachments.isEmpty)
    library.books[0].openChat(book.currentChat.id)
    XCTAssertEqual(library.books[0].currentChat.attachments, [text])
  }

  func testImageResizingProducesNativeImageInputAndLimitsAreEnforced() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LibraryStore(directory: directory)
    let book = UUID()
    let chat = UUID()
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: 3000, height: 30, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 3000, height: 30))
    let image = try XCTUnwrap(context.makeImage())
    let bytes = NSMutableData()
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let attachment = try store.importImage(
      bytes as Data, name: "Synthetic screenshot.png", bookID: book, chatID: chat)
    let inputs = try store.attachmentInputs([attachment], bookID: book, chatID: chat)
    let url = try XCTUnwrap(inputs.last?["url"] as? String)
    XCTAssertEqual(inputs.last?["type"] as? String, "image")
    let data = try XCTUnwrap(
      Data(base64Encoded: String(url.dropFirst("data:image/png;base64,".count))))
    let decoded = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let resized = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
    XCTAssertEqual(resized.width, 2400)
    XCTAssertThrowsError(
      try store.attachmentInputs(Array(repeating: attachment, count: 9), bookID: book, chatID: chat)
    )
    XCTAssertThrowsError(
      try store.importImage(
        Data("not an image".utf8), name: "broken.png", bookID: book, chatID: chat))
    let huge = directory.appendingPathComponent("too-large.txt")
    XCTAssertTrue(FileManager.default.createFile(atPath: huge.path, contents: nil))
    let handle = try FileHandle(forWritingTo: huge)
    try handle.truncate(atOffset: UInt64(ChatAttachment.byteLimit + 1))
    try handle.close()
    XCTAssertThrowsError(try store.importAttachment(huge, bookID: book, chatID: chat))
    let excessiveText = directory.appendingPathComponent("too-long.txt")
    try Data(String(repeating: "a", count: ChatAttachment.textLimit + 1).utf8).write(
      to: excessiveText)
    XCTAssertThrowsError(try store.importAttachment(excessiveText, bookID: book, chatID: chat))
    XCTAssertThrowsError(try store.importAttachment(directory, bookID: book, chatID: chat))
  }

  func testPDFToolsSelectOnlyTheApprovedDocumentAndRejectPathsAndForeignIDs() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let book = directory.appendingPathComponent("book.pdf")
    let supplement = directory.appendingPathComponent("supplement.pdf")
    try pdf(book, text: "The book marker is sapphire.")
    try pdf(supplement, text: "The supplement marker is amber.")
    let references = PDFReferences(
      book: BookPDFReader(file: book), attachments: ["approved-id": BookPDFReader(file: supplement)]
    )
    let page = try await references.contents(
      for: BookPDFReader.read, arguments: ["page": 1, "attachment_id": "approved-id"])
    XCTAssertTrue(page.first?["text"]?.contains("amber") == true)
    let original = try await references.contents(for: BookPDFReader.read, arguments: ["page": 1])
    XCTAssertTrue(original.first?["text"]?.contains("sapphire") == true)
    for arguments: [String: Any] in [
      ["page": 1, "attachment_id": "another-chat"],
      ["page": 1, "attachment_id": true],
      ["page": 1, "attachment_id": "approved-id", "path": book.path],
    ] {
      do {
        _ = try await references.contents(for: BookPDFReader.read, arguments: arguments)
        XCTFail("An out-of-scope attachment request was accepted")
      } catch {}
    }
    let store = LibraryStore(directory: directory.appendingPathComponent("library"))
    let imported = try store.importAttachment(supplement, bookID: UUID(), chatID: UUID())
    XCTAssertEqual(imported.kind, .pdf)
    XCTAssertEqual(imported.pageCount, 1)
  }

  func testOlderLibraryWithoutAttachmentFieldsLoadsWithoutLosingHistory() throws {
    var book = Book(title: "Synthetic Book", author: "Test author")
    book.currentChat.threadID = "old-thread"
    book.currentChat.question = "Draft"
    book.currentChat.exchanges = [
      Exchange(question: "Earlier", excerpt: "Passage", location: "p. 1", answer: "Reply")
    ]
    var value = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(book)) as? [String: Any])
    var chat = try XCTUnwrap(value["currentChat"] as? [String: Any])
    chat.removeValue(forKey: "attachments")
    chat.removeValue(forKey: "hasAttachmentTools")
    var exchanges = try XCTUnwrap(chat["exchanges"] as? [[String: Any]])
    exchanges[0].removeValue(forKey: "attachments")
    chat["exchanges"] = exchanges
    value["currentChat"] = chat
    let decoded = try JSONDecoder().decode(
      Book.self, from: JSONSerialization.data(withJSONObject: value))
    XCTAssertEqual(decoded.currentChat.question, "Draft")
    XCTAssertEqual(decoded.currentChat.exchanges, book.currentChat.exchanges)
    XCTAssertFalse(decoded.currentChat.hasAttachmentTools)
    XCTAssertTrue(decoded.currentChat.attachments.isEmpty)
  }

  @MainActor
  func testChatPDFToolCallsReachOnlyTheSelectedAttachmentThroughTheTransport() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LibraryStore(directory: directory.appendingPathComponent("library"))
    let source = directory.appendingPathComponent("supplement.pdf")
    try pdf(source, text: "The supplement marker is amber.")
    var book = Book(title: "Synthetic Book", author: "Test author")
    let attachment = try store.importAttachment(
      source, bookID: book.id, chatID: book.currentChat.id)
    book.currentChat.attachments = [attachment]
    book.currentChat.question = "CHAT_PDF_SCOPE"
    let fixture = try XCTUnwrap(
      Bundle.module.url(forResource: "fake-codex", withExtension: "py", subdirectory: "Fixtures"))
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
    let client = CodexClient(executable: fixture, requestTimeout: 3, answerTimeout: 3)
    defer { client.disconnect() }
    try await client.connect()
    var lookedUp = false
    let reply = try await client.ask(
      prompt: ReadingPrompt.make(book: book), threadID: nil,
      pdfAttachments: [
        attachment.id.uuidString: BookPDFReader(
          file: store.attachmentURL(attachment, bookID: book.id, chatID: book.currentChat.id))
      ],
      onLookup: { if $0.contains("PDF") { lookedUp = true } }, onUpdate: { _ in })
    XCTAssertTrue(lookedUp)
    XCTAssertEqual(reply.text, "Hello, reader! 📖 Your context is saved.")
  }
}
