import AppKit

@MainActor
public final class PassageClipboard {
  private let pasteboard: NSPasteboard
  private var previousGeneration: Int?

  public init(_ pasteboard: NSPasteboard) {
    self.pasteboard = pasteboard
  }

  // Selection alone does not update the pasteboard. Record only its revision when
  // the reader returns to Kindle, without reading any clipboard content.
  public func beginReading() {
    previousGeneration = pasteboard.changeCount
  }

  public var hasNewCopy: Bool {
    guard let previousGeneration else { return false }
    return previousGeneration != pasteboard.changeCount
  }

  public func readNewExcerpt(copySelection: (() throws -> Void)? = nil) async throws -> String {
    if let copySelection {
      previousGeneration = pasteboard.changeCount
      try copySelection()
    }
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(750))
    repeat {
      try Task.checkCancellation()
      let generation = pasteboard.changeCount
      if generation != previousGeneration,
        let text = pasteboard.string(forType: .string),
        generation == pasteboard.changeCount
      {
        let excerpt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !excerpt.isEmpty else { break }
        guard excerpt.count <= ReadingPrompt.excerptLimit else {
          throw BookBrainError.message(
            "The selection exceeds 12,000 characters. Copy a shorter passage.")
        }
        previousGeneration = generation
        return excerpt
      }
      // The reader can press the shortcut while Kindle is still publishing its copy.
      try await Task.sleep(for: .milliseconds(50))
    } while ContinuousClock.now < deadline
    if copySelection != nil {
      throw BookBrainError.message(
        "Kindle didn't provide a new passage. Select text in the book and press ⌘⇧B again."
      )
    }
    throw BookBrainError.message(
      "A fresh copy is needed. Select a passage in Kindle, choose Copy (or press ⌘C), then press ⌘⇧B."
    )
  }
}
