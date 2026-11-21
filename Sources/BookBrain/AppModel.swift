import AppKit
import BookBrainCore
import SwiftUI
import UniformTypeIdentifiers

enum PassageSource {
  case paste
  case shortcut(kindle: NSRunningApplication?)
}

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
  @Published var pendingAttachments: [ChatAttachment] = []
  @Published private(set) var codexModels: [CodexModel] = []
  @Published var showNewBook = false
  @Published var floating = true
  @Published var focusQuestion = 0

  let store: LibraryStore
  let clipboard = PassageClipboard(.general)
  private var apiClient: PiClient?
  private var client: CodexClient?
  private var saveTask: Task<Void, Never>?
  private var canSave = false

  init(store: LibraryStore? = nil, client: CodexClient? = nil) {
    self.store =
      store
      ?? LibraryStore(
        directory: FileManager.default.urls(
          for: .applicationSupportDirectory, in: .userDomainMask)[0]
          .appendingPathComponent("BookBrain", isDirectory: true))
    self.client = client
    isConnected = client?.isConnected == true
    codexModels = client?.models ?? []
    library = Library()
    do {
      library = try self.store.load()
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
  var apiModel: APIModel? { selectedBook?.currentChat.apiModel }
  var readyToSend: Bool { apiModel != nil || isConnected }
  var canChangeProvider: Bool { selectedBook?.currentChat.exchanges.isEmpty == true && isEditable }

  var codexModelID: String {
    selectedBook?.currentChat.codexModel ?? client?.defaultModel?.model ?? ""
  }
  var codexSupportsFast: Bool {
    codexModels.first { $0.model == codexModelID }?.supportsFast == true
  }

  func configureCodex(modelID: String, fast: Bool) {
    guard apiModel == nil, isConnected, isEditable,
      codexModels.contains(where: { $0.model == modelID }),
      let index = library.books.firstIndex(where: { $0.id == library.selectedBookID })
    else { return }
    var next = library
    next.books[index].currentChat.codexModel = modelID
    next.books[index].currentChat.codexFast = fast
    do { try commitLibrary(next) } catch { notice = error.localizedDescription }
  }

  func configureAPI(_ model: APIModel?, newKey: String) throws {
    guard isEditable,
      let index = library.books.firstIndex(where: { $0.id == library.selectedBookID }),
      canChangeProvider || (apiModel?.provider == model?.provider && apiModel?.id == model?.id)
    else {
      throw BookBrainError.message("Start a new chat to change the provider or model.")
    }
    if let model {
      if newKey.isEmpty {
        _ = try APIKeyStore.key(for: model.provider)
      } else {
        try APIKeyStore.save(newKey, for: model.provider)
      }
    }
    var next = library
    next.books[index].currentChat.apiModel = model
    try commitLibrary(next)
    notice = nil
  }

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
      let attachments = store.directory.appendingPathComponent("Attachments", isDirectory: true)
        .appendingPathComponent(book.id.uuidString, isDirectory: true)
      if FileManager.default.fileExists(atPath: attachments.path) {
        try FileManager.default.removeItem(at: attachments)
      }
    } catch { notice = error.localizedDescription }
  }

  func changeChat(_ edit: (inout Book) -> Void) {
    guard isEditable,
      let index = library.books.firstIndex(where: { $0.id == library.selectedBookID })
    else { return }
    let previous = library.books[index]
    var next = library
    edit(&next.books[index])
    do {
      try commitLibrary(next)
      let remaining = Set(
        ([next.books[index].currentChat] + next.books[index].savedChats).map(\.id))
      for chat in [previous.currentChat] + previous.savedChats where !remaining.contains(chat.id) {
        let directory = store.attachmentsDirectory(bookID: previous.id, chatID: chat.id)
        if FileManager.default.fileExists(atPath: directory.path) {
          try FileManager.default.removeItem(at: directory)
        }
      }
      captureIssue = nil
      notice = nil
    } catch { notice = error.localizedDescription }
  }

  func refreshCopyAccess() { canCopyFromKindle = CGPreflightPostEventAccess() }

  private var copyAccessInstructions: String {
    let settingsPath: String
    if #available(macOS 27, *) {
      settingsPath = "System Settings → Privacy & Security → Device Control and Data Access"
    } else {
      settingsPath = "System Settings → Privacy & Security → Accessibility"
    }
    return """
      Enable Book Brain in \(settingsPath), then return to Kindle and press ⌘⇧B. \
      If it is already enabled, quit Book Brain, remove the old entry, add this copy, and reopen it.
      """
  }

  func requestCopyAccess() {
    canCopyFromKindle = CGRequestPostEventAccess()
    if !canCopyFromKindle {
      notice = copyAccessInstructions
    }
  }

  func pasteExcerpt(_ source: PassageSource = .paste) async {
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
      if case .shortcut(let kindle?) = source {
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
      switch source {
      case .shortcut: library.books[index].captureKindlePassage(excerpt)
      case .paste: library.books[index].currentChat.excerpt = excerpt
      }
      captureIssue = nil
      focusQuestion += 1
    } catch {
      captureIssue = error.localizedDescription
    }
  }

  func connect() async {
    guard apiModel == nil, !isConnecting, !isBusy else { return }
    isConnecting = true
    isConnected = false
    notice = nil
    defer { isConnecting = false }
    client?.disconnect()
    let savedPath = UserDefaults.standard.string(forKey: "codexExecutable")
    let executable = savedPath.map { URL(fileURLWithPath: $0) } ?? CodexClient.findExecutable()
    guard let executable else {
      notice =
        "Couldn't find Codex. Choose an API key for a new chat or locate the Codex executable in the connection menu."
      return
    }
    let connection = CodexClient(executable: executable)
    client = connection
    do {
      try await connection.connect()
      isConnected = true
      codexModels = connection.models
    } catch { if apiModel == nil { notice = error.localizedDescription } }
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

  func chooseAttachments() {
    guard isEditable, selectedBook != nil else { return }
    let panel = NSOpenPanel()
    panel.title = "Attach files to this message"
    panel.allowedContentTypes = [
      .image, .pdf, .plainText, .sourceCode, .json, .xml, .commaSeparatedText, .tabSeparatedText,
    ]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    if panel.runModal() == .OK { addAttachments(.files(panel.urls)) }
  }

  func addAttachments(_ source: AttachmentPaste) {
    guard isEditable, let book = selectedBook else { return }
    let count: Int
    switch source {
    case .files(let urls): count = urls.count
    case .image: count = 1
    }
    guard book.currentChat.attachments.count + count <= ChatAttachment.countLimit else {
      notice = "Attach up to 8 files to each message."
      return
    }
    isImporting = true
    notice = nil
    let destination = store
    Task {
      defer { isImporting = false }
      do {
        let imported = try await Task.detached(priority: .userInitiated) {
          var added: [ChatAttachment] = []
          do {
            switch source {
            case .files(let urls):
              for url in urls {
                added.append(
                  try destination.importAttachment(
                    url, bookID: book.id, chatID: book.currentChat.id))
              }
            case .image(let data):
              added.append(
                try destination.importImage(
                  data, name: "Pasted screenshot.png", bookID: book.id, chatID: book.currentChat.id)
              )
            }
            _ = try destination.attachmentInputs(
              book.currentChat.attachments + added, bookID: book.id, chatID: book.currentChat.id)
            return added
          } catch {
            for attachment in added {
              try? FileManager.default.removeItem(
                at: destination.attachmentURL(
                  attachment, bookID: book.id, chatID: book.currentChat.id))
            }
            throw error
          }
        }.value
        var next = library
        guard let index = next.books.firstIndex(where: { $0.id == book.id }),
          next.books[index].currentChat.id == book.currentChat.id
        else {
          for attachment in imported {
            try? FileManager.default.removeItem(
              at: store.attachmentURL(attachment, bookID: book.id, chatID: book.currentChat.id))
          }
          return
        }
        next.books[index].currentChat.attachments += imported
        do { try commitLibrary(next) } catch {
          for attachment in imported {
            try? FileManager.default.removeItem(
              at: store.attachmentURL(attachment, bookID: book.id, chatID: book.currentChat.id))
          }
          throw error
        }
        focusQuestion += 1
      } catch { notice = error.localizedDescription }
    }
  }

  func removeAttachment(_ id: UUID) {
    guard isEditable, let book = selectedBook,
      let attachment = book.currentChat.attachments.first(where: { $0.id == id }),
      let index = library.books.firstIndex(where: { $0.id == book.id })
    else { return }
    var next = library
    next.books[index].currentChat.attachments.removeAll { $0.id == id }
    do {
      try commitLibrary(next)
      try FileManager.default.removeItem(
        at: store.attachmentURL(attachment, bookID: book.id, chatID: book.currentChat.id))
    } catch { notice = error.localizedDescription }
  }

  func send() async {
    guard isEditable, captureIssue == nil, readyToSend, var snapshot = selectedBook
    else { return }
    // Older Codex threads cannot acquire new dynamic tool schemas on resume.
    if !snapshot.currentChat.hasAttachmentTools && !snapshot.currentChat.attachments.isEmpty {
      snapshot.currentChat.threadID = nil
    }
    let prompt: String
    let attachmentInputs: [[String: Any]]
    do {
      if let model = snapshot.currentChat.apiModel, !model.vision,
        snapshot.currentChat.attachments.contains(where: { $0.kind == .image })
      {
        throw BookBrainError.message(
          "This model accepts text only. Use a chat with an image-capable model for screenshots.")
      }
      prompt = try ReadingPrompt.make(book: snapshot)
      attachmentInputs = try store.attachmentInputs(
        snapshot.currentChat.attachments, bookID: snapshot.id, chatID: snapshot.currentChat.id)
    } catch {
      notice = error.localizedDescription
      return
    }
    isBusy = true
    answerStatus = "Preparing reply…"
    pendingQuestion = snapshot.currentChat.questionForSending
    pendingAttachments = snapshot.currentChat.attachments
    streamingAnswer = ""
    notice = nil
    saveNow()
    defer {
      isBusy = false
      pendingQuestion = ""
      pendingAttachments = []
      streamingAnswer = ""
      apiClient = nil
      isConnected = client?.isConnected == true
    }
    do {
      let reader = snapshot.pdf.map { _ in BookPDFReader(file: store.pdfURL(for: snapshot.id)) }
      let pdfAttachments = Dictionary(
        uniqueKeysWithValues: snapshot.currentChat.allAttachments.filter { $0.kind == .pdf }.map {
          (
            $0.id.uuidString,
            BookPDFReader(
              file: store.attachmentURL($0, bookID: snapshot.id, chatID: snapshot.currentChat.id))
          )
        })
      let answer: (text: String, threadID: String?, images: [Data])
      if let model = snapshot.currentChat.apiModel {
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: "BookBrainPi") else {
          throw BookBrainError.message("Build and open Book Brain.app to use API mode.")
        }
        let key = try APIKeyStore.key(for: model.provider)
        let pi = PiClient(executable: executable)
        apiClient = pi
        let references =
          reader == nil && pdfAttachments.isEmpty
          ? nil : PDFReferences(book: reader, attachments: pdfAttachments)
        let text = try await pi.ask(
          model: model, key: key, prompt: prompt, inputs: attachmentInputs, pdf: references,
          onLookup: { self.answerStatus = "Reading the PDF…" },
          onUpdate: { self.streamingAnswer = $0 })
        answer = (text, nil, [])
      } else {
        guard let client else {
          throw BookBrainError.message("Connect to Codex to send a question.")
        }
        let reply = try await client.ask(
          prompt: prompt, threadID: snapshot.currentChat.threadID,
          modelID: snapshot.currentChat.codexModel,
          fast: snapshot.currentChat.codexFast, pdf: reader,
          attachmentInputs: attachmentInputs, pdfAttachments: pdfAttachments,
          onLookup: { [weak self] in self?.answerStatus = $0 },
          onUpdate: { [weak self] text in self?.streamingAnswer = text })
        answer = (reply.text, reply.threadID, reply.images)
      }
      guard let index = library.books.firstIndex(where: { $0.id == snapshot.id }),
        library.books[index].currentChat.id == snapshot.currentChat.id
      else { return }
      var next = library
      var images: [ChatAttachment] = []
      do {
        for (offset, data) in answer.images.enumerated() {
          images.append(
            try store.importImage(
              data, name: "Generated image \(offset + 1).png",
              bookID: snapshot.id, chatID: snapshot.currentChat.id))
        }
        next.books[index].currentChat.threadID = answer.threadID
        next.books[index].currentChat.hasAttachmentTools =
          snapshot.currentChat.hasAttachmentTools || snapshot.currentChat.threadID == nil
        next.books[index].currentChat.exchanges.append(
          Exchange(
            question: snapshot.currentChat.questionForSending,
            excerpt: snapshot.currentChat.excerpt,
            location: snapshot.currentChat.location, answer: answer.text,
            attachments: snapshot.currentChat.attachments, generatedImages: images
          ))
        next.books[index].currentChat.question = ""
        next.books[index].currentChat.attachments = []
        try commitLibrary(next)
      } catch {
        for image in images {
          try? FileManager.default.removeItem(
            at: store.attachmentURL(image, bookID: snapshot.id, chatID: snapshot.currentChat.id))
        }
        throw error
      }
      focusQuestion += 1
    } catch is CancellationError {
      notice = "Reply stopped. Your passage and question are saved."
    } catch {
      notice = error.localizedDescription
    }
  }

  func cancel() {
    if let apiClient {
      apiClient.cancel()
      return
    }
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
    apiClient?.cancel()
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
