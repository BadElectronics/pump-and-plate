import Flutter
import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// 'fitapp/appleai' and 'fitapp/appleai/events': Apple's on-device model
/// (Apple Intelligence, iOS 26 and later), offered next to the downloadable
/// models. Like them, it runs on the iPhone and nothing leaves it.
///
/// Each conversation is a session with an id from the app. A message's
/// answer streams back as events tagged with the session and a turn number:
/// "text" (new words), "call" (the model wants a function; the app answers
/// with toolResult and the answer continues), "error" and "done".
final class AppleAIChannel: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  /// Sessions by id (AppleChatSession on iOS 26+). Only touched on the main thread.
  private var sessions: [String: AnyObject] = [:]

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  /// Sends one event to the app, on the main thread.
  func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { self.sink?(event) }
  }

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    if call.method == "status" {
      result(Self.status())
      return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    #if canImport(FoundationModels)
      if #available(iOS 26.0, *) {
        handleSession(call.method, args: args, result)
        return
      }
    #endif
    result(FlutterError(code: "unavailable", message: "Apple's on-device model needs iOS 26 or later.", details: nil))
  }

  /// "available", "notEligible" (this iPhone can't run it), "notEnabled"
  /// (Apple Intelligence is off), "notReady" (still downloading) or
  /// "unsupported" (iOS older than 26).
  static func status() -> String {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, *) {
        switch SystemLanguageModel.default.availability {
        case .available:
          return "available"
        case .unavailable(let reason):
          switch reason {
          case .deviceNotEligible:
            return "notEligible"
          case .appleIntelligenceNotEnabled:
            return "notEnabled"
          case .modelNotReady:
            return "notReady"
          @unknown default:
            return "notReady"
          }
        }
      }
    #endif
    return "unsupported"
  }

  #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func handleSession(_ method: String, args: [String: Any], _ result: @escaping FlutterResult) {
      let id = args["session"] as? String ?? ""
      let session = sessions[id] as? AppleChatSession
      switch method {
      case "open":
        (sessions.removeValue(forKey: id) as? AppleChatSession)?.stop()
        do {
          sessions[id] = try AppleChatSession(
            id: id,
            instructions: args["instructions"] as? String ?? "",
            tools: args["tools"] as? [[String: Any]] ?? [],
            temperature: (args["temperature"] as? NSNumber)?.doubleValue ?? 0.7,
            emit: { [weak self] event in self?.emit(event) })
          result(nil)
        } catch {
          result(FlutterError(code: "open", message: "Apple's model couldn't start: \(error.localizedDescription)", details: nil))
        }
      case "send":
        guard let session else {
          result(Self.missing())
          return
        }
        session.send(args["text"] as? String ?? "", turn: (args["turn"] as? NSNumber)?.intValue ?? 0)
        result(nil)
      case "toolResult":
        guard let session else {
          result(Self.missing())
          return
        }
        session.toolResult(args["json"] as? String ?? "{}", turn: (args["turn"] as? NSNumber)?.intValue ?? 0)
        result(nil)
      case "prewarm":
        session?.prewarm()
        result(nil)
      case "stop":
        session?.stop()
        result(nil)
      case "close":
        (sessions.removeValue(forKey: id) as? AppleChatSession)?.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    private static func missing() -> FlutterError {
      FlutterError(code: "session", message: "This conversation was closed. Send your message again.", details: nil)
    }
  #endif
}

#if canImport(FoundationModels)

  /// One conversation with Apple's model.
  @available(iOS 26.0, *)
  final class AppleChatSession: @unchecked Sendable {
    let id: String
    private let session: LanguageModelSession
    private let bridge: ToolBridge
    private let temperature: Double
    private let emitter: ([String: Any]) -> Void

    /// Guards the three below: the answer being written, which one it is,
    /// and the turn its events are tagged with.
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var activeTask: UUID?
    private var turn = 0

    init(
      id: String, instructions: String, tools: [[String: Any]], temperature: Double,
      emit: @escaping ([String: Any]) -> Void
    ) throws {
      self.id = id
      self.temperature = temperature
      self.emitter = emit
      let bridge = ToolBridge()
      self.bridge = bridge
      var built: [any Tool] = []
      for tool in tools {
        guard let name = tool["name"] as? String else { continue }
        let schema = try SchemaBuilder.schema(
          name: name, json: tool["schema"] as? [String: Any] ?? ["type": "object"])
        built.append(
          BridgedTool(
            name: name, description: tool["description"] as? String ?? name, parameters: schema, bridge: bridge))
      }
      session = LanguageModelSession(model: SystemLanguageModel.default, tools: built, instructions: instructions)
      bridge.onCall = { [weak self] name, json in self?.emitCall(name: name, json: json) }
    }

    func prewarm() {
      session.prewarm()
    }

    /// Starts an answer. An earlier answer still running is stopped first.
    func send(_ text: String, turn: Int) {
      let taskId = UUID()
      lock.lock()
      let previous = task
      activeTask = taskId
      self.turn = turn
      lock.unlock()
      previous?.cancel()
      bridge.cancelPending()

      let session = self.session
      let options = GenerationOptions(temperature: temperature)
      let newTask = Task { [weak self] in
        // One answer at a time: let the stopped one wind down first, or the
        // model reports it's busy.
        await previous?.value
        while session.isResponding && !Task.isCancelled {
          try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if Task.isCancelled {
          self?.finish(taskId)
          return
        }
        var shown = ""
        do {
          let stream = session.streamResponse(to: text, options: options)
          for try await snapshot in stream {
            if Task.isCancelled { break }
            // Each snapshot holds the answer so far; pass on only what's new.
            let full = snapshot.content
            let delta = full.hasPrefix(shown) ? String(full.dropFirst(shown.count)) : full
            shown = full
            if !delta.isEmpty {
              self?.emit(taskId, ["type": "text", "text": delta])
            }
          }
          self?.finish(taskId)
        } catch {
          if Task.isCancelled || error is CancellationError {
            self?.finish(taskId)
          } else {
            self?.emit(taskId, ["type": "error", "message": Self.describe(error)])
            self?.finish(taskId, quietly: true)
          }
        }
      }
      lock.lock()
      if activeTask == taskId { task = newTask }
      lock.unlock()
    }

    /// The app's answer to a function call; the model then carries on.
    func toolResult(_ json: String, turn: Int) {
      lock.lock()
      self.turn = turn
      lock.unlock()
      bridge.resolve(json)
    }

    /// Stops the answer being written, if any, and tells the app it ended.
    func stop() {
      lock.lock()
      let wasActive = activeTask != nil
      activeTask = nil
      let running = task
      task = nil
      let turn = self.turn
      lock.unlock()
      running?.cancel()
      bridge.cancelPending()
      if wasActive {
        emitter(["session": id, "turn": turn, "type": "done"])
      }
    }

    /// Sends an event only for the answer currently being written.
    private func emit(_ taskId: UUID, _ event: [String: Any]) {
      lock.lock()
      let current = activeTask == taskId
      let turn = self.turn
      lock.unlock()
      guard current else { return }
      var tagged = event
      tagged["session"] = id
      tagged["turn"] = turn
      emitter(tagged)
    }

    private func finish(_ taskId: UUID, quietly: Bool = false) {
      if !quietly { emit(taskId, ["type": "done"]) }
      lock.lock()
      if activeTask == taskId {
        activeTask = nil
        task = nil
      }
      lock.unlock()
    }

    private func emitCall(name: String, json: String) {
      lock.lock()
      let active = activeTask
      lock.unlock()
      guard let active else { return }
      emit(active, ["type": "call", "name": name, "args": json])
    }

    /// The model's errors in plain words. Matched by name so newer iOS
    /// versions that rename a case still get a sensible message.
    static func describe(_ error: Error) -> String {
      let text = String(describing: error)
      if text.contains("exceededContextWindowSize") || text.contains("contextSizeExceeded") {
        return "This conversation got too long for Apple's model."
      }
      if text.contains("guardrailViolation") || text.contains("refusal") {
        return "Apple's model wouldn't answer that. Try wording it differently."
      }
      if text.contains("assetsUnavailable") {
        return "Apple's model isn't ready. Check that Apple Intelligence is on, then try again."
      }
      if text.contains("rateLimited") || text.contains("concurrentRequests") {
        return "Apple's model is busy. Try again in a moment."
      }
      if text.contains("unsupportedLanguageOrLocale") {
        return "Apple's model doesn't support this language yet."
      }
      return "Apple's model stopped: \(error.localizedDescription)"
    }
  }

  /// Hands function calls to the app one at a time and waits for each
  /// answer. (The model may ask for several at once; each gets its own card
  /// and its own answer, in order.)
  @available(iOS 26.0, *)
  final class ToolBridge: @unchecked Sendable {
    private struct Waiting {
      let name: String
      let json: String
      let continuation: CheckedContinuation<String, Never>
    }

    private let lock = NSLock()
    /// The call the app has been shown and is answering.
    private var current: CheckedContinuation<String, Never>?
    /// Calls waiting their turn.
    private var queue: [Waiting] = []
    var onCall: ((String, String) -> Void)?

    static let cancelled = #"{"status":"cancelled"}"#

    func call(name: String, json: String) async -> String {
      await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
        lock.lock()
        if current == nil {
          current = continuation
          let notify = onCall
          lock.unlock()
          notify?(name, json)
        } else {
          queue.append(Waiting(name: name, json: json, continuation: continuation))
          lock.unlock()
        }
      }
    }

    /// The app's answer to the call it was shown; the next waiting call, if
    /// any, goes to the app.
    func resolve(_ json: String) {
      lock.lock()
      let answered = current
      current = nil
      var next: Waiting?
      if !queue.isEmpty {
        next = queue.removeFirst()
        current = next?.continuation
      }
      let notify = onCall
      lock.unlock()
      answered?.resume(returning: json)
      if let next { notify?(next.name, next.json) }
    }

    /// Ends every call still waiting (the answer was stopped or replaced).
    func cancelPending() {
      lock.lock()
      var all = queue.map { $0.continuation }
      if let current { all.insert(current, at: 0) }
      current = nil
      queue = []
      lock.unlock()
      for c in all { c.resume(returning: Self.cancelled) }
    }
  }

  /// One of the app's functions, described to the model with a schema built
  /// at runtime from the app's definition.
  @available(iOS 26.0, *)
  struct BridgedTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let bridge: ToolBridge

    func call(arguments: GeneratedContent) async throws -> String {
      await bridge.call(name: name, json: arguments.jsonString)
    }
  }

  /// Turns the app's function parameters (a simplified JSON Schema with
  /// properties as an ordered list) into Apple's schema type.
  @available(iOS 26.0, *)
  enum SchemaBuilder {
    static func schema(name: String, json: [String: Any]) throws -> GenerationSchema {
      try GenerationSchema(root: node(name: name, json: json), dependencies: [])
    }

    static func node(name: String, json: [String: Any]) -> DynamicGenerationSchema {
      let description = json["description"] as? String
      if let choices = json["enum"] as? [String], !choices.isEmpty {
        return DynamicGenerationSchema(name: name, description: description, anyOf: choices)
      }
      switch json["type"] as? String ?? "string" {
      case "object":
        let properties = json["properties"] as? [[String: Any]] ?? []
        let built = properties.compactMap { property -> DynamicGenerationSchema.Property? in
          guard let propertyName = property["name"] as? String else { return nil }
          let child = property["schema"] as? [String: Any] ?? [:]
          return DynamicGenerationSchema.Property(
            name: propertyName,
            description: child["description"] as? String,
            schema: node(name: "\(name)_\(propertyName)", json: child),
            isOptional: !((property["required"] as? Bool) ?? false))
        }
        return DynamicGenerationSchema(name: name, description: description, properties: built)
      case "array":
        let items = json["items"] as? [String: Any] ?? ["type": "string"]
        return DynamicGenerationSchema(
          arrayOf: node(name: "\(name)_item", json: items), minimumElements: nil, maximumElements: nil)
      case "integer":
        return DynamicGenerationSchema(type: Int.self, guides: [])
      case "number":
        return DynamicGenerationSchema(type: Double.self, guides: [])
      case "boolean":
        return DynamicGenerationSchema(type: Bool.self, guides: [])
      default:
        return DynamicGenerationSchema(type: String.self, guides: [])
      }
    }
  }

#endif
