import AppKit

@MainActor
final class ManagedCodexSession: NSWindowController, NSWindowDelegate {
    let pane: TerminalSession
    weak var app: TileApp?
    var onClose: (() -> Void)?
    private let transcript = NSTextView()
    private let prompt = NSTextField()
    private let sendButton = NSButton(title: "Send", target: nil, action: nil)
    private let usageLabel = NSTextField(labelWithString: "Usage unavailable")
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private var buffer = Data()
    private var threadID: String?
    private var requestID = 100
    private var pendingRequestActions: [String: String] = [:]
    private var tokens: Int?
    private var tokensObservedAt: Date?
    private var primary: AgentQuotaWindow?
    private var secondary: AgentQuotaWindow?
    private var quotaObservedAt: Date?
    private var plan: String?
    private var ended = false
    var isConnected: Bool { threadID != nil }

    init(pane: TerminalSession, app: TileApp) {
        self.pane = pane
        self.app = app
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Managed Codex — \(pane.displayTitle)"
        super.init(window: window)
        window.delegate = self
        let root = NSView()
        window.contentView = root
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = transcript
        transcript.isEditable = false
        transcript.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        prompt.placeholderString = "Ask Codex in this directory"
        prompt.target = self
        prompt.action = #selector(sendPrompt)
        sendButton.target = self
        sendButton.action = #selector(sendPrompt)
        usageLabel.textColor = .secondaryLabelColor
        usageLabel.font = NSFont.systemFont(ofSize: 11)
        for view in [scroll, prompt, sendButton, usageLabel] {
            root.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: usageLabel.topAnchor, constant: -8),
            usageLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            usageLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            usageLabel.bottomAnchor.constraint(equalTo: prompt.topAnchor, constant: -8),
            prompt.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            prompt.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            prompt.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            sendButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            sendButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            sendButton.widthAnchor.constraint(equalToConstant: 72)
        ])
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        start()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    private func append(_ value: String) {
        transcript.textStorage?.append(NSAttributedString(string: value))
        transcript.scrollToEndOfDocument(nil)
    }

    private func start() {
        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        guard let executable = (searchPaths + ["/usr/local/bin", "/opt/homebrew/bin"])
            .map({ URL(fileURLWithPath: $0).appending(path: "codex").path })
            .first(where: FileManager.default.isExecutableFile(atPath:)) else {
            append("Codex CLI is unavailable. Install it before starting a managed session.\n")
            sendButton.isEnabled = false
            return
        }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                Task { @MainActor [weak self] in self?.receive(data) }
            }
            send(["method": "initialize", "id": 1, "params": ["clientInfo": ["name": "tile", "title": "Tile", "version": "0.1.0"]]])
            append("Connecting to Codex app server…\n")
        } catch {
            append("Could not start Codex app server: \(error.localizedDescription)\n")
            sendButton.isEnabled = false
        }
    }

    private func send(_ message: [String: Any]) {
        guard process.isRunning,
              let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        inputPipe.fileHandleForWriting.write(data + Data([0x0A]))
    }

    private func request(_ method: String, params: [String: Any]? = nil) {
        requestID += 1
        var message: [String: Any] = ["id": requestID, "method": method]
        if let params { message["params"] = params }
        send(message)
    }

    @objc private func sendPrompt() {
        guard let threadID else { append("Codex is still connecting.\n"); return }
        let text = prompt.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        prompt.stringValue = ""
        append("\nYou: \(text)\nCodex: ")
        request("turn/start", params: ["threadId": threadID, "input": [["type": "text", "text": text]], "cwd": pane.directory])
    }

    func submitPrompt(_ text: String) {
        prompt.stringValue = text
        sendPrompt()
    }

    private func receive(_ data: Data) {
        if data.isEmpty {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            append("\nCodex app server disconnected.\n")
            sendButton.isEnabled = false
            endSession()
            return
        }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            handle(message)
        }
        if buffer.count > 1_000_000 { buffer.removeAll(); append("\nCodex message exceeded Tile's limit.\n") }
    }

    private func handle(_ message: [String: Any]) {
        if let id = message["id"] as? Int, let error = message["error"] as? [String: Any] {
            append("\nCodex request \(id) failed: \(error["message"] as? String ?? "Unknown error")\n")
            return
        }
        if message["id"] as? Int == 1 {
            send(["method": "initialized", "params": [:]])
            send(["method": "thread/start", "id": 2, "params": ["cwd": pane.directory, "serviceName": "tile"]])
            return
        }
        if message["id"] as? Int == 2,
           let result = message["result"] as? [String: Any],
           let thread = result["thread"] as? [String: Any],
           let id = thread["id"] as? String {
            threadID = id
            append("Connected. Session \(id).\n")
            send(["method": "account/rateLimits/read", "id": 3])
            emit("start")
            return
        }
        if message["id"] as? Int == 3,
           let result = message["result"] as? [String: Any] {
            parseRateLimits(result["rateLimits"] as? [String: Any])
            return
        }
        guard let method = message["method"] as? String,
              let params = message["params"] as? [String: Any] else { return }
        if let threadID, let incoming = params["threadId"] as? String, incoming != threadID { return }
        switch method {
        case "turn/started": emit("start")
        case "turn/completed":
            let turn = params["turn"] as? [String: Any] ?? [:]
            let status = turn["status"] as? String ?? ""
            emit(status == "completed" ? "completion" : "failure", actionID: turn["id"] as? String)
            append("\n[Turn \(status)]\n")
            send(["method": "account/rateLimits/read", "id": 3])
        case "item/agentMessage/delta":
            if let delta = params["delta"] as? String { append(delta) }
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            approval(message, params: params)
        case "tool/requestUserInput":
            question(message, params: params)
        case "item/permissions/requestApproval":
            permissions(message, params: params)
        case "mcpServer/elicitation/request":
            if let id = message["id"] { send(["id": id, "result": ["action": "cancel", "content": NSNull()]]) }
        case "serverRequest/resolved":
            if let requestID = params["requestId"],
               let actionID = pendingRequestActions.removeValue(forKey: String(describing: requestID)) {
                emit("resolved", actionID: actionID)
            }
        case "thread/tokenUsage/updated":
            let usage = params["tokenUsage"] as? [String: Any] ?? [:]
            let total = usage["total"] as? [String: Any] ?? [:]
            if let value = total["totalTokens"] as? Int {
                tokens = value
                tokensObservedAt = Date()
                publishUsage()
            }
        case "account/rateLimits/updated":
            parseRateLimits(params["rateLimits"] as? [String: Any])
        case "error":
            let error = params["error"] as? [String: Any]
            append("\nCodex error: \(error?["message"] as? String ?? "Unknown error")\n")
        default: break
        }
    }

    private func emit(_ event: String, actionID: String? = nil) {
        guard let threadID else { return }
        let wire = AgentWireEvent(version: 1, provider: .codex, sessionID: threadID,
                                  paneToken: pane.agentToken, event: event, actionID: actionID,
                                  observedAt: Date(), source: "Codex app server")
        app?.agentMonitor.ingest(wire)
    }

    private func approval(_ message: [String: Any], params: [String: Any]) {
        guard let id = message["id"] else { return }
        let actionID = params["itemId"] as? String
        if let actionID { pendingRequestActions[String(describing: id)] = actionID }
        emit("approval", actionID: actionID)
        let alert = NSAlert()
        alert.messageText = "Codex requests approval"
        let command = params["command"] as? String ?? ""
        alert.informativeText = [params["reason"] as? String, command].compactMap { $0 }.joined(separator: "\n")
        alert.addButton(withTitle: "Decline")
        alert.addButton(withTitle: "Approve once")
        let decision = alert.runModal() == .alertSecondButtonReturn ? "accept" : "decline"
        send(["id": id, "result": ["decision": decision]])
    }

    private func question(_ message: [String: Any], params: [String: Any]) {
        guard let id = message["id"], let questions = params["questions"] as? [[String: Any]] else { return }
        let actionID = params["itemId"] as? String
        if let actionID { pendingRequestActions[String(describing: id)] = actionID }
        emit("question", actionID: actionID)
        var answers: [String: Any] = [:]
        for item in questions {
            guard let key = item["id"] as? String else { continue }
            let alert = NSAlert()
            alert.messageText = item["question"] as? String ?? "Codex asks a question"
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
            let options = item["options"] as? [[String: Any]] ?? []
            alert.informativeText = options.compactMap { $0["label"] as? String }.joined(separator: " · ")
            alert.accessoryView = field
            alert.addButton(withTitle: "Answer")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal() == .alertFirstButtonReturn ? field.stringValue : ""
            answers[key] = ["answers": [response]]
        }
        send(["id": id, "result": ["answers": answers]])
    }

    private func permissions(_ message: [String: Any], params: [String: Any]) {
        guard let id = message["id"] else { return }
        let actionID = params["itemId"] as? String
        if let actionID { pendingRequestActions[String(describing: id)] = actionID }
        emit("approval", actionID: actionID)
        let requested = params["permissions"] as? [String: Any] ?? [:]
        let alert = NSAlert()
        alert.messageText = "Codex requests additional permissions"
        let requestText = (try? JSONSerialization.data(withJSONObject: requested, options: .prettyPrinted))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        alert.informativeText = "\(params["reason"] as? String ?? "")\n\(requestText)"
        alert.addButton(withTitle: "Decline")
        alert.addButton(withTitle: "Grant for this turn")
        let granted = alert.runModal() == .alertSecondButtonReturn ? requested : [:]
        send(["id": id, "result": ["permissions": granted, "scope": "turn"]])
    }

    private func parseRateLimits(_ snapshot: [String: Any]?) {
        guard let snapshot else { return }
        plan = snapshot["planType"] as? String
        func window(_ name: String) -> AgentQuotaWindow? {
            guard let values = snapshot[name] as? [String: Any],
                  let used = values["usedPercent"] as? Double,
                  let reset = values["resetsAt"] as? Double,
                  (0...100).contains(used), reset > Date().timeIntervalSince1970 else { return nil }
            return AgentQuotaWindow(usedPercent: used, resetsAt: Date(timeIntervalSince1970: reset),
                                    durationMinutes: values["windowDurationMins"] as? Int)
        }
        primary = window("primary")
        secondary = window("secondary")
        quotaObservedAt = Date()
        publishUsage()
    }

    private func publishUsage() {
        let tokensFresh = tokensObservedAt.map { Date().timeIntervalSince($0) <= 120 } ?? false
        let quotaFresh = quotaObservedAt.map { Date().timeIntervalSince($0) <= 120 } ?? false
        let freshTokens = tokensFresh ? tokens : nil
        let freshPrimary = quotaFresh ? primary : nil
        let freshSecondary = quotaFresh ? secondary : nil
        let tokenText = freshTokens.map { "Thread total \($0) tokens" } ?? "Thread tokens unavailable"
        let quotaText = freshPrimary.map { "Primary \(Int($0.usedPercent))% used" } ?? "Quota unavailable"
        usageLabel.stringValue = "\(tokenText) · \(quotaText) · \(plan ?? "Plan unavailable")"
        guard let threadID else { return }
        let usage = AgentUsage(sampledAt: Date(), estimatedSessionCostUSD: nil,
                               fiveHour: nil, sevenDay: nil,
                               threadTotalTokens: freshTokens, codexPrimary: freshPrimary,
                               codexSecondary: freshSecondary, accountPlan: quotaFresh ? plan : nil)
        app?.agentMonitor.updateManagedUsage(usage, session: pane, threadID: threadID)
    }

    func windowWillClose(_ notification: Notification) {
        endSession()
        outputPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        onClose?()
    }

    private func endSession() {
        guard !ended else { return }
        ended = true
        emit("end")
    }
}
