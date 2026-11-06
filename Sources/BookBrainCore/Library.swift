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

public struct Book: Codable, Identifiable, Equatable {
  public var id = UUID()
  public var title: String
  public var location = ""
  public var excerpt = ""
  public var question = ""
  public var exchanges: [Exchange] = []

  public init(title: String) { self.title = title }
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
