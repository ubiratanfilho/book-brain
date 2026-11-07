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

  public func readNewExcerpt() async throws -> String {
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
            "A cópia ultrapassa 12.000 caracteres. Copie um trecho menor.")
        }
        previousGeneration = generation
        return excerpt
      }
      // The reader can press the shortcut while Kindle is still publishing its copy.
      try await Task.sleep(for: .milliseconds(50))
    } while ContinuousClock.now < deadline
    throw BookBrainError.message(
      "Falta uma nova cópia. No Kindle, selecione o trecho, clique em Copiar (ou use ⌘C) e pressione ⌘⇧B."
    )
  }
}
