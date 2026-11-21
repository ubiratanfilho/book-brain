import Foundation

// A pipe read can split a JSON line anywhere, including inside a UTF-8 character.
struct JSONLines {
  private var buffer = Data()

  private let allowsImageResults: Bool
  init(allowsImageResults: Bool = false) { self.allowsImageResults = allowsImageResults }

  mutating func append(_ data: Data) throws -> [[String: Any]] {
    var messages: [[String: Any]] = []
    let normalLimit = 8 * 1024 * 1024
    let limit = allowsImageResults ? 28 * 1024 * 1024 : normalLimit
    var rest = data[...]
    while !rest.isEmpty {
      let newline = rest.firstIndex(of: 10)
      let end = newline ?? rest.endIndex
      guard buffer.count + rest.distance(from: rest.startIndex, to: end) <= limit else {
        throw BookBrainError.message("The assistant sent a larger reply than expected.")
      }
      buffer.append(contentsOf: rest[..<end])
      guard let newline else { break }
      rest = rest[rest.index(after: newline)...]
      if buffer.isEmpty { continue }
      guard let object = try JSONSerialization.jsonObject(with: buffer) as? [String: Any] else {
        throw BookBrainError.message("The assistant returned an invalid reply.")
      }
      if buffer.count > normalLimit {
        let params = object["params"] as? [String: Any]
        let item = params?["item"] as? [String: Any]
        guard object["method"] as? String == "item/completed",
          item?["type"] as? String == "imageGeneration"
        else {
          throw BookBrainError.message("The assistant sent a larger reply than expected.")
        }
      }
      buffer.removeAll()
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
