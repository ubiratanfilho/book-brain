import Darwin
import Foundation

public enum APIProvider: String, Codable, CaseIterable {
  case anthropic, google, openai
  public var name: String {
    switch self {
    case .anthropic: return "Anthropic"
    case .google: return "Google"
    case .openai: return "OpenAI"
    }
  }
}

public struct APIModel: Codable, Equatable {
  public let provider: APIProvider
  public let id: String
  public let name: String
  public let vision: Bool
}

// Each turn has its own process, pipes and approved PDF readers. No session files are created.
@MainActor
public final class PiClient {
  private let process = Process()
  private var stopped = false

  public init(executable: URL) {
    process.executableURL = executable
    process.currentDirectoryURL = URL(fileURLWithPath: "/")
    process.environment = [:]
    process.standardError = FileHandle.nullDevice
  }

  public func cancel() {
    stopped = true
    if process.isRunning { process.terminate() }
  }

  public func ask(
    model: APIModel, key: String, prompt: String, inputs: [[String: Any]], pdf: PDFReferences?,
    onLookup: () -> Void, onUpdate: (String) -> Void
  ) async throws -> String {
    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    try process.run()
    let writer = input.fileHandleForWriting
    // A stop or helper crash can close stdin while an image is being written.
    _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
    let reader = output.fileHandleForReading
    let deadline = Task {
      try await Task.sleep(for: .seconds(180))
      if process.isRunning { process.terminate() }
    }
    defer {
      deadline.cancel()
      try? writer.close()
      if process.isRunning { process.terminate() }
    }
    let events = AsyncThrowingStream<[String: Any], Error> { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        defer { try? reader.close() }
        var lines = JSONLines()
        do {
          while true {
            let data = reader.availableData
            if data.isEmpty { break }
            for event in try lines.append(data) { continuation.yield(event) }
          }
          continuation.finish()
        } catch { continuation.finish(throwing: error) }
      }
    }
    func write(_ message: [String: Any]) async throws {
      var data = try JSONSerialization.data(withJSONObject: message)
      data.append(10)
      let packet = data
      try await Task.detached { try writer.write(contentsOf: packet) }.value
    }
    var text = ""
    var calls = 0
    do {
      try await write([
        "provider": model.provider.rawValue, "model": model.id, "key": key, "prompt": prompt,
        "inputs": inputs, "instructions": ReadingPrompt.systemInstructions(apiMode: true),
        "tools": pdf == nil ? [] : BookPDFReader.specs, "callLimit": BookPDFReader.callLimit,
      ])
      for try await event in events {
        if stopped { throw CancellationError() }
        switch event["type"] as? String {
        case "start": text = ""
        case "delta":
          guard let delta = event["text"] as? String else { throw protocolError }
          text += delta
          onUpdate(text)
        case "done":
          guard let answer = event["text"] as? String, !answer.isEmpty else { throw protocolError }
          return answer
        case "error":
          throw BookBrainError.message(event["text"] as? String ?? "API request failed.")
        case "tool":
          guard let pdf, let name = event["name"] as? String,
            [BookPDFReader.search, BookPDFReader.read].contains(name),
            let arguments = event["args"] as? [String: Any]
          else { throw protocolError }
          calls += 1
          guard calls <= BookPDFReader.callLimit else {
            throw BookBrainError.message("PDF lookup limit reached. Try a more specific question.")
          }
          onLookup()
          let response: [String: Any]
          do { response = ["items": try await pdf.contents(for: name, arguments: arguments)] } catch
          { response = ["error": error.localizedDescription] }
          if stopped { throw CancellationError() }
          try await write(response)
        default: throw protocolError
        }
      }
      throw BookBrainError.message("The API helper stopped before the reply finished. Try again.")
    } catch {
      if stopped { throw CancellationError() }
      throw error
    }
  }

  private var protocolError: BookBrainError { .message("Unexpected response from the API helper.") }
}
