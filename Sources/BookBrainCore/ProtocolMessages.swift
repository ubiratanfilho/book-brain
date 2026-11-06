import Foundation

// A pipe read can split a JSON line anywhere, including inside a UTF-8 character.
struct JSONLines {
  private var buffer = Data()

  mutating func append(_ data: Data) throws -> [[String: Any]] {
    buffer.append(data)
    guard buffer.count <= 8 * 1_024 * 1_024 else {
      throw BookBrainError.message("O Codex enviou uma resposta maior que o esperado.")
    }
    var messages: [[String: Any]] = []
    while let end = buffer.firstIndex(of: 10) {
      let line = buffer[..<end]
      buffer.removeSubrange(...end)
      if line.isEmpty { continue }
      guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
        throw BookBrainError.message("Resposta inválida do Codex.")
      }
      messages.append(object)
    }
    return messages
  }
}

struct AnswerAccumulator {
  private var order: [String] = []
  private var texts: [String: String] = [:]
  private var commentary: Set<String> = []

  mutating func update(id: String, text: String, phase: String?) {
    if texts[id] == nil { order.append(id) }
    texts[id] = text
    if phase == "commentary" { commentary.insert(id) }
  }

  mutating func append(id: String, delta: String) {
    if texts[id] == nil { order.append(id) }
    texts[id, default: ""] += delta
  }

  var text: String {
    order.filter { !commentary.contains($0) }
      .compactMap { texts[$0] }.filter { !$0.isEmpty }.joined(separator: "\n\n")
  }
}
