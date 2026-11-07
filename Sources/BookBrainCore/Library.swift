import Foundation

public struct Exchange: Codable, Identifiable, Equatable {
  public var id = UUID()
  public var date = Date()
  public var question: String
  public var excerpt: String
  public var location: String
  public var answer: String

  public init(question: String, excerpt: String, location: String, answer: String) {
    self.question = question
    self.excerpt = excerpt
    self.location = location
    self.answer = answer
  }
}

public struct ReadingChat: Codable, Identifiable, Equatable {
  public var id = UUID()
  public var createdAt = Date()
  public var customTitle = ""
  public var threadID: String?
  public var location = ""
  public var excerpt = ""
  public var question = ""
  public var exchanges: [Exchange] = []

  public init() {}

  public var title: String {
    if !customTitle.isEmpty { return customTitle }
    for text in [exchanges.first?.question ?? "", question, excerpt] {
      let line = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
      if !line.isEmpty { return line.count > 64 ? String(line.prefix(63)) + "…" : line }
    }
    return "Nova conversa"
  }

  public var isBlank: Bool {
    exchanges.isEmpty && question.isEmpty && excerpt.isEmpty && location.isEmpty
      && customTitle.isEmpty
  }
}

public struct Book: Codable, Identifiable, Equatable {
  public var id = UUID()
  public var title: String
  public var author: String
  public var pdf: BookPDF?
  public var currentChat = ReadingChat()
  public private(set) var savedChats: [ReadingChat] = []

  public init(title: String, author: String) {
    self.title = title
    self.author = author
  }

  public mutating func newChat() {
    guard !currentChat.isBlank else { return }
    savedChats.insert(currentChat, at: 0)
    currentChat = ReadingChat()
  }

  public mutating func openChat(_ id: UUID) {
    guard let index = savedChats.firstIndex(where: { $0.id == id }) else { return }
    let chosen = savedChats.remove(at: index)
    if !currentChat.isBlank { savedChats.insert(currentChat, at: 0) }
    currentChat = chosen
  }

  public mutating func deleteChat(_ id: UUID) {
    if currentChat.id == id {
      currentChat = savedChats.isEmpty ? ReadingChat() : savedChats.removeFirst()
    } else {
      savedChats.removeAll { $0.id == id }
    }
  }

  public mutating func renameChat(_ id: UUID, to title: String) {
    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if currentChat.id == id {
      currentChat.customTitle = name
    } else if let index = savedChats.firstIndex(where: { $0.id == id }) {
      savedChats[index].customTitle = name
    }
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, author, pdf, currentChat, savedChats
  }
  private enum LegacyKeys: String, CodingKey { case location, excerpt, question, exchanges }

  public init(from decoder: Decoder) throws {
    let fields = try decoder.container(keyedBy: CodingKeys.self)
    id = try fields.decode(UUID.self, forKey: .id)
    title = try fields.decode(String.self, forKey: .title)
    author = try fields.decodeIfPresent(String.self, forKey: .author) ?? ""
    pdf = try fields.decodeIfPresent(BookPDF.self, forKey: .pdf)
    if fields.contains(.currentChat) || fields.contains(.savedChats) {
      currentChat = try fields.decode(ReadingChat.self, forKey: .currentChat)
      savedChats = try fields.decode([ReadingChat].self, forKey: .savedChats)
    } else {
      // Before conversations, the book itself held a single transcript and draft.
      let legacy = try decoder.container(keyedBy: LegacyKeys.self)
      currentChat.id = id
      currentChat.location = try legacy.decode(String.self, forKey: .location)
      currentChat.excerpt = try legacy.decode(String.self, forKey: .excerpt)
      currentChat.question = try legacy.decode(String.self, forKey: .question)
      currentChat.exchanges = try legacy.decode([Exchange].self, forKey: .exchanges)
      if let first = currentChat.exchanges.first { currentChat.createdAt = first.date }
    }
  }
}

public struct Library: Codable, Equatable {
  public var books: [Book] = []
  public var selectedBookID: UUID?

  public init() {}
}

public struct LibraryStore {
  public let directory: URL
  public var file: URL { directory.appendingPathComponent("library.json") }

  public init(directory: URL) { self.directory = directory }

  public func load() throws -> Library {
    guard FileManager.default.fileExists(atPath: file.path) else { return Library() }
    return try JSONDecoder().decode(Library.self, from: Data(contentsOf: file))
  }

  public func save(_ library: Library) throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(library).write(to: file, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
  }
}
