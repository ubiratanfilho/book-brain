import AppKit
import BookBrainCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
  @Published var library: Library { didSet { scheduleSave() } }
  @Published var notice: String?
  @Published var captureIssue: String?
  @Published private(set) var isImporting = false
  @Published private(set) var canCopyFromKindle = CGPreflightPostEventAccess()
  @Published var storageError: String?
  @Published var isConnecting = false
  @Published var isConnected = false
  @Published var isBusy = false
  @Published var streamingAnswer = ""
  @Published var answerStatus = ""
  @Published var pendingQuestion = ""
  @Published var modelName = ""
  @Published var showNewBook = false
  @Published var floating = true
  @Published var focusQuestion = 0

  let store: LibraryStore
  let clipboard = PassageClipboard(.general)
  private var client: CodexClient?
  private var saveTask: Task<Void, Never>?
  private var canSave = false

  init() {
    let directory = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("BookBrain", isDirectory: true)
    store = LibraryStore(directory: directory)
    library = Library()
    do {
      library = try store.load()
      if !library.books.contains(where: { $0.id == library.selectedBookID }) {
        library.selectedBookID = library.books.first?.id
      }
      canSave = true
    } catch {
      storageError =
        "Couldn't open your chat history. The original file is safe. \(error.localizedDescription)"
    }
  }

  var selectedBook: Book? { library.books.first { $0.id == library.selectedBookID } }
  var isEditable: Bool { canSave && !isBusy && !isImporting }

  func field(_ keyPath: WritableKeyPath<ReadingChat, String>) -> Binding<String> {
    Binding(
      get: { self.selectedBook?.currentChat[keyPath: keyPath] ?? "" },
      set: { value in
        guard self.isEditable,
          let index = self.library.books.firstIndex(where: { $0.id == self.library.selectedBookID })
        else { return }
        self.library.books[index].currentChat[keyPath: keyPath] = value
        if keyPath == \.excerpt { self.captureIssue = nil }
      }
    )
  }

  func saveBook(id: UUID?, title: String, author: String, pdfURL: URL?) async throws {
    guard isEditable else {
      throw BookBrainError.message("Wait for the current operation to finish.")
    }
    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let writer = author.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !writer.isEmpty else {
      throw BookBrainError.message("Enter both the title and the author's name.")
    }
    guard name.count <= 200, writer.count <= 200 else {
      throw BookBrainError.message("Use up to 200 characters in each field.")
    }
    isImporting = true
    defer { isImporting = false }
    var next = library
    if let id {
      guard let index = next.books.firstIndex(where: { $0.id == id }), pdfURL == nil else {
        throw BookBrainError.message("Couldn't update this book.")
      }
      next.books[index].title = name
      next.books[index].author = writer
      try commitLibrary(next)
    } else {
      var book = Book(title: name, author: writer)
      if let pdfURL {
        let bookID = book.id
        let destination = store
        book.pdf = try await Task.detached(priority: .userInitiated) {
          try destination.importPDF(pdfURL, for: bookID)
        }.value
      }
      next.books.append(book)
      next.selectedBookID = book.id
      do { try commitLibrary(next) } catch {
        if book.pdf != nil { try FileManager.default.removeItem(at: store.pdfURL(for: book.id)) }
        throw error
      }
    }
    captureIssue = nil
    notice = nil
  }

  private func commitLibrary(_ next: Library) throws {
    try store.save(next)
    library = next
    saveTask?.cancel()
    storageError = nil
  }

  func selectBook(_ id: UUID) {
    guard isEditable else { return }
    library.selectedBookID = id
    captureIssue = nil
    notice = nil
  }

  func deleteSelectedBook() {
    guard isEditable, let book = selectedBook else { return }
    var next = library
    next.books.removeAll { $0.id == book.id }
    next.selectedBookID = next.books.first?.id
    do {
      try commitLibrary(next)
      captureIssue = nil
      let file = store.pdfURL(for: book.id)
      if book.pdf != nil, FileManager.default.fileExists(atPath: file.path) {
        try FileManager.default.removeItem(at: file)
      }
    } catch { notice = error.localizedDescription }
  }

  func changeChat(_ edit: (inout Book) -> Void) {
    guard isEditable,
      let index = library.books.firstIndex(where: { $0.id == library.selectedBookID })
    else { return }
    edit(&library.books[index])
    captureIssue = nil
    notice = nil
    saveNow()
  }

  func refreshCopyAccess() { canCopyFromKindle = CGPreflightPostEventAccess() }

  private var copyAccessInstructions: String {
    let settingsPath: String
    if #available(macOS 27, *) {
      settingsPath = "System Settings → Privacy & Security → Device Control and Data Access"
    } else {
      settingsPath = "System Settings → Privacy & Security → Accessibility"
    }
    return "Enable Book Brain in \(settingsPath), then return to Kindle and press ⌘⇧B."
  }

  func requestCopyAccess() {
    canCopyFromKindle = CGRequestPostEventAccess()
    if !canCopyFromKindle {
      notice = copyAccessInstructions
    }
  }

  func pasteExcerpt(from kindle: NSRunningApplication? = nil) async {
    guard !isImporting else { return }
    guard isEditable else {
      notice = "Wait for the current reply or click Stop before changing the passage."
      return
    }
    guard let index = library.books.firstIndex(where: { $0.id == library.selectedBookID }) else {
      showNewBook = true
      notice = "Add a book, then click Paste passage."
      return
    }
    isImporting = true
    defer { isImporting = false }
    notice = nil
    do {
      let excerpt: String
      if let kindle {
        refreshCopyAccess()
        if canCopyFromKindle {
          excerpt = try await clipboard.readNewExcerpt { try KindleSelection.copy(in: kindle) }
        } else if clipboard.hasNewCopy {
          excerpt = try await clipboard.readNewExcerpt()
        } else {
          throw BookBrainError.message(copyAccessInstructions)
        }
      } else {
        excerpt = try await clipboard.readNewExcerpt()
      }
      library.books[index].currentChat.excerpt = excerpt
      captureIssue = nil
      focusQuestion += 1
    } catch {
      captureIssue = error.localizedDescription
    }
  }

  func connect() async {
    guard !isConnecting, !isBusy else { return }
    isConnecting = true
    isConnected = false
    notice = nil
    defer { isConnecting = false }
    client?.disconnect()
    let savedPath = UserDefaults.standard.string(forKey: "codexExecutable")
    let executable = savedPath.map { URL(fileURLWithPath: $0) } ?? CodexClient.findExecutable()
    guard let executable else {
      notice = "Couldn't find Codex. Install it or choose its executable from the Codex menu."
      return
    }
    let connection = CodexClient(executable: executable)
    client = connection
    do {
      try await connection.connect()
      isConnected = true
      modelName = connection.model
    } catch { notice = error.localizedDescription }
  }

  func chooseExecutable() {
    let panel = NSOpenPanel()
    panel.title = "Choose the Codex executable"
    panel.canChooseDirectories = false
    panel.showsHiddenFiles = true
    if panel.runModal() == .OK, let url = panel.url {
      UserDefaults.standard.set(url.path, forKey: "codexExecutable")
      Task { await connect() }
    }
  }

  func send() async {
    guard isEditable, captureIssue == nil, isConnected, let client, let snapshot = selectedBook
    else { return }
    let prompt: String
    do { prompt = try ReadingPrompt.make(book: snapshot) } catch {
      notice = error.localizedDescription
      return
    }
    isBusy = true
    answerStatus = "Preparing reply…"
    pendingQuestion = snapshot.currentChat.question
    streamingAnswer = ""
    notice = nil
    saveNow()
    defer {
      isBusy = false
      pendingQuestion = ""
      streamingAnswer = ""
      isConnected = client.isConnected
    }
    do {
      let reader = snapshot.pdf.map { _ in BookPDFReader(file: store.pdfURL(for: snapshot.id)) }
      let answer = try await client.ask(
        prompt: prompt, threadID: snapshot.currentChat.threadID, pdf: reader,
        onLookup: { [weak self] in self?.answerStatus = $0 },
        onUpdate: { [weak self] text in self?.streamingAnswer = text })
      guard let index = library.books.firstIndex(where: { $0.id == snapshot.id }),
        library.books[index].currentChat.id == snapshot.currentChat.id
      else { return }
      library.books[index].currentChat.threadID = answer.threadID
      library.books[index].currentChat.exchanges.append(
        Exchange(
          question: snapshot.currentChat.question, excerpt: snapshot.currentChat.excerpt,
          location: snapshot.currentChat.location, answer: answer.text
        ))
      library.books[index].currentChat.question = ""
      saveNow()
      focusQuestion += 1
    } catch is CancellationError {
      notice = "Reply stopped. Your passage and question are saved."
    } catch {
      notice = error.localizedDescription
    }
  }

  func cancel() {
    client?.disconnect()
    isConnected = false
  }

  func saveNow() {
    saveTask?.cancel()
    guard canSave else { return }
    do {
      try store.save(library)
      storageError = nil
    } catch {
      storageError = "Couldn't save your chat history. \(error.localizedDescription)"
    }
  }

  func shutdown() {
    saveNow()
    client?.disconnect()
  }

  private func scheduleSave() {
    guard canSave else { return }
    saveTask?.cancel()
    saveTask = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
      self?.saveNow()
    }
  }
}
