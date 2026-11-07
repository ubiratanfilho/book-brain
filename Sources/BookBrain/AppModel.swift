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
        "Não foi possível abrir seu histórico. O arquivo foi preservado. \(error.localizedDescription)"
    }
  }

  var selectedBook: Book? { library.books.first { $0.id == library.selectedBookID } }
  var isEditable: Bool { canSave && !isBusy && !isImporting }

  func field(_ keyPath: WritableKeyPath<Book, String>) -> Binding<String> {
    Binding(
      get: { self.selectedBook?[keyPath: keyPath] ?? "" },
      set: { value in
        guard self.isEditable,
          let index = self.library.books.firstIndex(where: { $0.id == self.library.selectedBookID })
        else { return }
        self.library.books[index][keyPath: keyPath] = value
        if keyPath == \.excerpt { self.captureIssue = nil }
      }
    )
  }

  func createBook(title: String) {
    guard isEditable else { return }
    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    let book = Book(title: String(name.prefix(200)))
    library.books.append(book)
    captureIssue = nil
    library.selectedBookID = book.id
    saveNow()
  }

  func selectBook(_ id: UUID) {
    guard isEditable else { return }
    library.selectedBookID = id
    captureIssue = nil
    notice = nil
  }

  func deleteSelectedBook() {
    guard isEditable, let id = library.selectedBookID else { return }
    library.books.removeAll { $0.id == id }
    captureIssue = nil
    library.selectedBookID = library.books.first?.id
    saveNow()
  }

  func refreshCopyAccess() { canCopyFromKindle = CGPreflightPostEventAccess() }

  func requestCopyAccess() {
    canCopyFromKindle = CGRequestPostEventAccess()
    if !canCopyFromKindle {
      notice =
        "Ative Book Brain em Ajustes do Sistema → Privacidade e Segurança → Acessibilidade. Depois, volte ao Kindle e use ⌘⇧B."
    }
  }

  func pasteExcerpt(from kindle: NSRunningApplication? = nil) async {
    guard !isImporting else { return }
    guard isEditable else {
      notice = "Aguarde a resposta atual ou clique em Parar antes de trocar o trecho."
      return
    }
    guard let index = library.books.firstIndex(where: { $0.id == library.selectedBookID }) else {
      showNewBook = true
      notice = "Adicione o livro e clique em Colar trecho."
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
          throw BookBrainError.message(
            "Para trazer a seleção direto do Kindle com ⌘⇧B, autorize o Book Brain em Acessibilidade."
          )
        }
      } else {
        excerpt = try await clipboard.readNewExcerpt()
      }
      library.books[index].excerpt = excerpt
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
      notice = "Codex não encontrado. Instale o Codex ou escolha o executável no menu de conexão."
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
    panel.title = "Selecione o executável codex"
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
    pendingQuestion = snapshot.question
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
      let answer = try await client.ask(prompt: prompt) { [weak self] text in
        self?.streamingAnswer = text
      }
      guard let index = library.books.firstIndex(where: { $0.id == snapshot.id }) else { return }
      library.books[index].exchanges.append(
        Exchange(
          question: snapshot.question, excerpt: snapshot.excerpt,
          location: snapshot.location, answer: answer
        ))
      library.books[index].question = ""
      saveNow()
      focusQuestion += 1
    } catch is CancellationError {
      notice = "Resposta interrompida. Seu trecho e sua pergunta foram mantidos."
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
      storageError = "Não foi possível salvar o histórico: \(error.localizedDescription)"
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
