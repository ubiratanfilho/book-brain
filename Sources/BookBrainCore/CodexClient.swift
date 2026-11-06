import Foundation

@MainActor
public final class CodexClient {
  public private(set) var model = ""
  public private(set) var isConnected = false

  private let executable: URL
  private let requestTimeout: UInt64
  private let answerTimeout: UInt64
  private var process: Process?
  private var input: FileHandle?
  private var output: FileHandle?
  private var diagnostics: FileHandle?
  private var lines = JSONLines()
  private var nextID = 0
  private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
  private var deadlines: [Int: Task<Void, Never>] = [:]
  private var answerDeadline: Task<Void, Never>?
  private var activeThread: String?
  private var reply: CheckedContinuation<String, Error>?
  private var onUpdate: ((String) -> Void)?
  private var accumulator = AnswerAccumulator()
  private var threadConfig: [String: Any] = [:]
  private var workingDirectory: URL?

  public init(executable: URL, requestTimeout: UInt64 = 30, answerTimeout: UInt64 = 180) {
    self.executable = executable
    self.requestTimeout = requestTimeout
    self.answerTimeout = answerTimeout
  }

  public static func findExecutable() -> URL? {
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    let candidates =
      path.split(separator: ":").map { "\($0)/codex" } + [
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        "/Applications/Codex.app/Contents/Resources/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
      ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
      .map { URL(fileURLWithPath: $0) }
  }

  // Process-local overrides; never edit the reader's Codex settings or credentials.
  static let configuration = [
    "approval_policy=\"never\"", "web_search=\"disabled\"",
    "permissions.book-brain.filesystem={\":minimal\"=\"read\",\":workspace_roots\"=\"read\"}",
    "permissions.book-brain.network.enabled=false",
    "project_doc_max_bytes=0", "skills.include_instructions=false",
    "memories.use_memories=false", "memories.generate_memories=false",
    "tools.update_plan.enabled=false", "tools.experimental_request_user_input.enabled=false",
    "features.shell_tool=false", "features.unified_exec=false",
    "features.code_mode=false", "features.code_mode_host=false", "features.js_repl=false",
    "features.apply_patch_freeform=false", "features.apps=false", "features.plugins=false",
    "features.connectors=false", "features.browser_use=false", "features.computer_use=false",
    "features.multi_agent=false", "features.collab=false", "features.memory_tool=false",
    "features.skill_search=false", "features.skip_host_skill_discovery=true",
    "features.hooks=false", "features.codex_hooks=false", "features.plugin_hooks=false",
    "features.image_generation=false", "features.view_image=false", "features.goals=false",
  ]

  public func connect() async throws {
    if isConnected { return }
    guard process == nil else {
      throw BookBrainError.message("A conexão com o Codex já está em andamento.")
    }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("BookBrain-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    workingDirectory = directory
    let child = Process()
    child.executableURL = executable
    child.arguments =
      ["app-server", "--listen", "stdio://"]
      + Self.configuration.flatMap { ["-c", $0] }
    child.currentDirectoryURL = directory
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    child.standardInput = stdin
    child.standardOutput = stdout
    child.standardError = stderr
    input = stdin.fileHandleForWriting
    output = stdout.fileHandleForReading
    diagnostics = stderr.fileHandleForReading
    lines = JSONLines()
    process = child
    output?.readabilityHandler = { [weak self, weak child] handle in
      let data = handle.availableData
      Task { @MainActor in
        guard let self, self.process === child, !data.isEmpty else { return }
        do {
          for message in try self.lines.append(data) { self.receive(message) }
        } catch { self.stop(error: error) }
      }
    }
    // Drain stderr without persisting paths, account information, or book content.
    diagnostics?.readabilityHandler = { handle in _ = handle.availableData }
    child.terminationHandler = { [weak self, weak child] _ in
      Task { @MainActor in
        guard let self, self.process === child else { return }
        self.stop(error: BookBrainError.message("O Codex encerrou a conexão. Conecte novamente."))
      }
    }
    do {
      try child.run()
      _ = try await request(
        "initialize",
        [
          "clientInfo": ["name": "book_brain", "title": "Book Brain", "version": "0.1.0"],
          "capabilities": ["experimentalApi": true],
        ])
      try write(["method": "initialized"])
      let account = try await request("account/read", ["refreshToken": false])
      guard account["account"] is [String: Any] else {
        throw BookBrainError.message(
          "Entre no Codex primeiro: execute codex login no Terminal e reconecte.")
      }
      let models = try await request("model/list", ["includeHidden": false])
      guard let entries = models["data"] as? [[String: Any]],
        let selected = entries.first(where: { $0["isDefault"] as? Bool == true }),
        let name = selected["model"] as? String
      else {
        throw BookBrainError.message(
          "O Codex não informou um modelo padrão. Verifique sua instalação.")
      }
      model = name
      // Map overrides merge with the user's config: explicitly disable each inherited MCP.
      let config = try await request("config/read", ["includeLayers": false])
      guard let values = config["config"] as? [String: Any] else {
        throw BookBrainError.message("Não foi possível verificar as configurações do Codex.")
      }
      threadConfig = [:]
      if let servers = values["mcp_servers"] as? [String: Any] {
        threadConfig["mcp_servers"] = Dictionary(
          uniqueKeysWithValues: servers.keys.map {
            ($0, ["enabled": false])
          })
      }
      isConnected = true
    } catch {
      stop(error: error)
      throw error
    }
  }

  public func ask(prompt: String, onUpdate: @escaping (String) -> Void) async throws -> String {
    guard isConnected, let directory = workingDirectory else {
      throw BookBrainError.message("Conecte ao Codex antes de enviar.")
    }
    guard activeThread == nil else {
      throw BookBrainError.message("Aguarde a resposta atual.")
    }
    let result = try await request(
      "thread/start",
      [
        "model": model, "cwd": directory.path, "ephemeral": true,
        "approvalPolicy": "never", "permissions": "book-brain",
        "baseInstructions": ReadingPrompt.instructions,
        "developerInstructions": "This is a text-only reading conversation. Do not use any tools.",
        "config": threadConfig,
      ])
    guard let profile = result["activePermissionProfile"] as? [String: Any],
      profile["id"] as? String == "book-brain",
      result["approvalPolicy"] as? String == "never"
    else {
      let error = BookBrainError.message(
        "O Codex não confirmou as permissões restritas. Atualize o Codex antes de continuar.")
      stop(error: error)
      throw error
    }
    guard let thread = result["thread"] as? [String: Any], let id = thread["id"] as? String else {
      throw BookBrainError.message("O Codex não iniciou a conversa.")
    }
    activeThread = id
    accumulator = AnswerAccumulator()
    self.onUpdate = onUpdate
    return try await withCheckedThrowingContinuation { continuation in
      reply = continuation
      answerDeadline = Task { [weak self] in
        guard let self else { return }
        do { try await Task.sleep(nanoseconds: self.answerTimeout * 1_000_000_000) } catch {
          return
        }
        self.stop(
          error: BookBrainError.message(
            "A resposta demorou demais. Seu rascunho foi mantido; tente reconectar."))
      }
      Task {
        do {
          _ = try await request(
            "turn/start",
            [
              "threadId": id, "input": [["type": "text", "text": prompt]],
              "approvalPolicy": "never",
              "permissions": "book-brain",
            ])
        } catch { finish(.failure(error)) }
      }
    }
  }

  public func disconnect() { stop(error: CancellationError()) }

  private func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
    nextID += 1
    let id = nextID
    return try await withCheckedThrowingContinuation { continuation in
      pending[id] = continuation
      deadlines[id] = Task { [weak self] in
        guard let self else { return }
        do { try await Task.sleep(nanoseconds: self.requestTimeout * 1_000_000_000) } catch {
          return
        }
        self.stop(error: BookBrainError.message("O Codex não respondeu a tempo. Tente reconectar."))
      }
      do { try write(["id": id, "method": method, "params": params]) } catch { stop(error: error) }
    }
  }

  private func write(_ message: [String: Any]) throws {
    guard let input, process?.isRunning == true else {
      throw BookBrainError.message("A conexão com o Codex foi encerrada.")
    }
    var data = try JSONSerialization.data(withJSONObject: message)
    data.append(10)
    try input.write(contentsOf: data)
  }

  private func receive(_ message: [String: Any]) {
    if message["method"] != nil, let id = message["id"] {
      // This app exposes no tools, approvals, or interactive server requests.
      do {
        try write([
          "id": id,
          "error": [
            "code": -32601,
            "message": "Book Brain does not allow tool execution or approval requests.",
          ],
        ])
      } catch { stop(error: error) }
      return
    }
    if let id = message["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
      deadlines.removeValue(forKey: id)?.cancel()
      if let error = message["error"] as? [String: Any] {
        continuation.resume(
          throwing: BookBrainError.message(
            error["message"] as? String ?? "Erro de comunicação com o Codex."))
      } else if let result = message["result"] as? [String: Any] {
        continuation.resume(returning: result)
      } else {
        continuation.resume(throwing: BookBrainError.message("Resposta incompleta do Codex."))
      }
      return
    }
    guard let method = message["method"] as? String,
      let params = message["params"] as? [String: Any],
      let activeThread, params["threadId"] as? String == activeThread
    else { return }
    switch method {
    case "item/agentMessage/delta":
      if let id = params["itemId"] as? String, let delta = params["delta"] as? String {
        accumulator.append(id: id, delta: delta)
        onUpdate?(accumulator.text)
      }
    case "item/started", "item/completed":
      if method == "item/started", let item = params["item"] as? [String: Any],
        let type = item["type"] as? String,
        !["userMessage", "agentMessage", "reasoning", "contextCompaction"].contains(type)
      {
        stop(
          error: BookBrainError.message(
            "O Codex tentou usar uma ferramenta. A sessão foi encerrada; este app só permite conversar sobre texto."
          ))
        return
      }
      if let item = params["item"] as? [String: Any], item["type"] as? String == "agentMessage",
        let id = item["id"] as? String, let text = item["text"] as? String
      {
        accumulator.update(id: id, text: text, phase: item["phase"] as? String)
        onUpdate?(accumulator.text)
      }
    case "turn/completed":
      guard let turn = params["turn"] as? [String: Any] else { return }
      switch turn["status"] as? String {
      case "completed":
        if accumulator.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          finish(
            .failure(BookBrainError.message("O Codex terminou sem uma resposta. Tente novamente.")))
        } else {
          finish(.success(accumulator.text))
        }
      case "interrupted": finish(.failure(CancellationError()))
      default:
        let error = turn["error"] as? [String: Any]
        finish(
          .failure(
            BookBrainError.message(
              error?["message"] as? String ?? "Não foi possível concluir a resposta.")))
      }
    default: break
    }
  }

  private func finish(_ result: Result<String, Error>) {
    answerDeadline?.cancel()
    answerDeadline = nil
    let thread = activeThread
    activeThread = nil
    onUpdate = nil
    let continuation = reply
    reply = nil
    continuation?.resume(with: result)
    if let thread, isConnected {
      Task { _ = try? await request("thread/unsubscribe", ["threadId": thread]) }
    }
  }

  private func stop(error: Error) {
    isConnected = false
    finish(.failure(error))
    let requests = Array(pending.values)
    pending.removeAll()
    for deadline in deadlines.values { deadline.cancel() }
    deadlines.removeAll()
    for continuation in requests { continuation.resume(throwing: error) }
    output?.readabilityHandler = nil
    diagnostics?.readabilityHandler = nil
    try? input?.close()
    input = nil
    output = nil
    diagnostics = nil
    let child = process
    process = nil
    child?.terminationHandler = nil
    if let child, child.isRunning {
      child.terminate()
      Task {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
      }
    }
    if let directory = workingDirectory { try? FileManager.default.removeItem(at: directory) }
    workingDirectory = nil
  }
}
