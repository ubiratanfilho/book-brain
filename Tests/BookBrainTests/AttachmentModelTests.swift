import AppKit
import BookBrainCore
import SwiftUI
import XCTest

@testable import BookBrain

@MainActor
final class AttachmentModelTests: XCTestCase {
  private func screenshot() throws -> Data {
    let image = NSImage(size: NSSize(width: 160, height: 80), flipped: false) { bounds in
      NSColor.white.setFill()
      bounds.fill()
      NSColor.blue.setFill()
      NSRect(x: 20, y: 20, width: 40, height: 40).fill()
      return true
    }
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
    return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
  }

  private func client(in directory: URL) async throws -> CodexClient {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(
        "BookBrainCoreTests/Fixtures/fake-codex.py")
    let fixture = directory.appendingPathComponent("fake-codex.py")
    try FileManager.default.copyItem(at: source, to: fixture)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
    let client = CodexClient(executable: fixture, requestTimeout: 3, answerTimeout: 3)
    try await client.connect()
    return client
  }

  private func waitForImport(_ model: AppModel) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while model.isImporting && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertFalse(model.isImporting)
    XCTAssertNil(model.notice)
  }

  func testFilesAreSentAsNativeInputSavedInHistoryAndRemovedWithTheirChat() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LibraryStore(directory: directory.appendingPathComponent("library"))
    var book = Book(title: "Synthetic Book", author: "Test author")
    book.currentChat.threadID = "legacy-thread"
    book.currentChat.hasAttachmentTools = false
    book.currentChat.question = "Ordinary follow-up"
    book.currentChat.exchanges = [
      Exchange(question: "Earlier question", excerpt: "", location: "", answer: "Earlier answer")
    ]
    var library = Library()
    library.books = [book, Book(title: "Other book", author: "Test author")]
    library.selectedBookID = book.id
    try store.save(library)
    let connection = try await client(in: directory)
    defer { connection.disconnect() }
    let model = AppModel(store: store, client: connection)
    await model.send()
    XCTAssertNil(model.notice)
    XCTAssertEqual(model.selectedBook?.currentChat.threadID, "legacy-thread")
    XCTAssertEqual(model.selectedBook?.currentChat.hasAttachmentTools, false)
    model.field(\.question).wrappedValue = "ATTACHMENTS"
    let image = directory.appendingPathComponent("Synthetic screenshot.png")
    let notes = directory.appendingPathComponent("notes.txt")
    try screenshot().write(to: image)
    try Data("Synthetic attachment notes.".utf8).write(to: notes)
    model.addAttachments(.files([image, notes]))
    try await waitForImport(model)
    let attachments = try XCTUnwrap(model.selectedBook?.currentChat.attachments)
    XCTAssertEqual(attachments.count, 2)
    await model.send()
    XCTAssertNil(model.notice)
    let chat = try XCTUnwrap(model.selectedBook?.currentChat)
    XCTAssertEqual(chat.exchanges.last?.attachments, attachments)
    XCTAssertTrue(chat.attachments.isEmpty)
    XCTAssertTrue(chat.hasAttachmentTools)
    XCTAssertNotEqual(chat.threadID, "legacy-thread")
    XCTAssertEqual(try store.load(), model.library)
    let files = attachments.map { store.attachmentURL($0, bookID: book.id, chatID: chat.id) }
    XCTAssertTrue(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

    model.changeChat { $0.newChat() }
    XCTAssertTrue(model.selectedBook?.currentChat.allAttachments.isEmpty == true)
    model.selectBook(library.books[1].id)
    XCTAssertTrue(model.selectedBook?.currentChat.allAttachments.isEmpty == true)
    model.selectBook(book.id)
    model.changeChat { $0.openChat(chat.id) }
    XCTAssertEqual(model.selectedBook?.currentChat.exchanges.last?.attachments, attachments)
    model.changeChat { $0.deleteChat(chat.id) }
    XCTAssertTrue(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: notes.path))
  }

  func testGeneratedImagesPersistAsAnswersAndInvalidPathsPreserveDraft() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LibraryStore(directory: directory.appendingPathComponent("library"))
    let book = Book(title: "Test", author: "Example")
    var library = Library()
    library.books = [book]
    library.selectedBookID = book.id
    try store.save(library)
    let connection = try await client(in: directory)
    defer { connection.disconnect() }
    let model = AppModel(store: store, client: connection)
    for question in ["IMAGE", "IMAGE_FILE"] {
      model.field(\.question).wrappedValue = question
      await model.send()
      XCTAssertNil(model.notice)
      let chat = try XCTUnwrap(try store.load().books.first?.currentChat)
      let exchange = try XCTUnwrap(chat.exchanges.last)
      XCTAssertTrue(exchange.answer.isEmpty)
      XCTAssertTrue(exchange.attachments.isEmpty)
      let image = try XCTUnwrap(exchange.generatedImages.first)
      XCTAssertNotNil(
        NSImage(contentsOf: store.attachmentURL(image, bookID: book.id, chatID: chat.id)))
    }
    model.field(\.question).wrappedValue = "IMAGE_INVALID_PATH"
    await model.send()
    XCTAssertTrue(model.notice?.contains("Invalid image location") == true)
    XCTAssertEqual(model.selectedBook?.currentChat.exchanges.count, 2)
    XCTAssertEqual(model.selectedBook?.currentChat.question, "IMAGE_INVALID_PATH")
  }

  func testFailedSendRetainsImageDraftAndImageOnlyRetryCanBeSent() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LibraryStore(directory: directory.appendingPathComponent("library"))
    var book = Book(title: "Synthetic Book", author: "Test author")
    book.currentChat.question = "FAIL"
    var library = Library()
    library.books = [book]
    library.selectedBookID = book.id
    try store.save(library)
    let connection = try await client(in: directory)
    defer { connection.disconnect() }
    let model = AppModel(store: store, client: connection)
    model.addAttachments(.image(try screenshot()))
    try await waitForImport(model)
    let attached = try XCTUnwrap(model.selectedBook?.currentChat.attachments)
    await model.send()
    XCTAssertNotNil(model.notice)
    XCTAssertEqual(model.selectedBook?.currentChat.attachments, attached)
    XCTAssertTrue(model.selectedBook?.currentChat.exchanges.isEmpty == true)
    XCTAssertEqual(try store.load().books[0].currentChat.attachments, attached)
    model.field(\.question).wrappedValue = ""
    await model.send()
    XCTAssertNil(model.notice)
    XCTAssertEqual(model.selectedBook?.currentChat.exchanges.last?.attachments, attached)
    XCTAssertFalse(model.selectedBook?.currentChat.exchanges.last?.question.isEmpty == true)
  }

  func testAttachmentPickerImportsAtomicallyAndRemovalOnlyDeletesManagedCopy() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LibraryStore(directory: directory.appendingPathComponent("library"))
    let book = Book(title: "Synthetic Book", author: "Test author")
    var library = Library()
    library.books = [book]
    library.selectedBookID = book.id
    try store.save(library)
    let model = AppModel(store: store)
    let valid = directory.appendingPathComponent("notes.txt")
    let invalid = directory.appendingPathComponent("binary.bin")
    try Data("A synthetic note.".utf8).write(to: valid)
    try Data([0, 1, 2]).write(to: invalid)
    model.addAttachments(.files([valid, invalid]))
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while model.isImporting && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertNotNil(model.notice)
    XCTAssertTrue(model.selectedBook?.currentChat.attachments.isEmpty == true)
    let folder = store.attachmentsDirectory(bookID: book.id, chatID: book.currentChat.id)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    model.addAttachments(.files([valid]))
    try await waitForImport(model)
    let attachment = try XCTUnwrap(model.selectedBook?.currentChat.attachments.first)
    let managed = store.attachmentURL(attachment, bookID: book.id, chatID: book.currentChat.id)
    model.removeAttachment(attachment.id)
    XCTAssertTrue(model.selectedBook?.currentChat.attachments.isEmpty == true)
    XCTAssertFalse(FileManager.default.fileExists(atPath: managed.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: valid.path))
  }

  func testAttachmentComposerFitsNormalCompactAndMinimumWindowSizes() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LibraryStore(directory: directory)
    var book = Book(title: "Synthetic Field Notes", author: "Anne Vale")
    let attachment = try store.importImage(
      screenshot(), name: "Synthetic screenshot.png", bookID: book.id, chatID: book.currentChat.id)
    book.currentChat.attachments = [attachment]
    book.currentChat.question = "Can you explain the figure?"
    book.currentChat.exchanges = [
      Exchange(
        question: "What should I look for?", excerpt: "", location: "",
        answer: "Look at the blue square in this fictional example.")
    ]
    var library = Library()
    library.books = [book]
    library.selectedBookID = book.id
    try store.save(library)
    let model = AppModel(store: store)
    model.isConnected = true
    for size in [
      NSSize(width: 640, height: 900), NSSize(width: 350, height: 500),
      NSSize(width: 300, height: 280),
    ] {
      let host = NSHostingView(
        rootView: ContentView(
          model: model, shortcutAvailable: true, setFloating: { _ in },
          setCompact: { _ in }
        ).environment(\.colorScheme, .light))
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.alphaValue = 0
      window.contentView = host
      window.orderBack(nil)
      defer { window.orderOut(nil) }
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      host.layoutSubtreeIfNeeded()
      func editor(in view: NSView) -> QuestionTextView? {
        if let field = view as? QuestionTextView { return field }
        return view.subviews.lazy.compactMap { editor(in: $0) }.first
      }
      let field = try XCTUnwrap(editor(in: host))
      let frame = field.convert(field.visibleRect, to: host)
      XCTAssertGreaterThan(frame.width, 80)
      XCTAssertGreaterThan(frame.height, 15)
      XCTAssertTrue(host.bounds.contains(frame), "Question field was clipped at \(size)")
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let path = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("book-brain-attachments-\(Int(size.width))x\(Int(size.height)).png")
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: path)
      print("Synthetic attachment preview: \(path.path)")
    }
  }
}
