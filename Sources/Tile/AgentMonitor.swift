import AppKit
import Darwin

enum AgentProvider: String, Codable, CaseIterable {
    case claude = "Claude Code"
    case codex = "Codex"
    case gemini = "Gemini CLI"
}

enum AgentPhase: String, Codable {
    case running, approvalRequired, questionRequired, failed, completedNeedsReview, idle, unknown

    var label: String {
        switch self {
        case .running: "Working"
        case .approvalRequired: "Approval"
        case .questionRequired: "Question"
        case .failed: "Failed"
        case .completedNeedsReview: "Review"
        case .idle: "Idle"
        case .unknown: "Unknown"
        }
    }
    var priority: Int? {
        switch self {
        case .approvalRequired: 0
        case .questionRequired: 1
        case .failed: 2
        case .completedNeedsReview: 3
        default: nil
        }
    }
}

struct AgentWireEvent: Codable {
    let version: Int
    let provider: AgentProvider
    let sessionID: String
    let paneToken: UUID
    let event: String
    let actionID: String?
    let observedAt: Date
    let source: String
    var usage: AgentUsage? = nil
}

struct AgentQuotaWindow: Codable {
    let usedPercent: Double
    let resetsAt: Date
    var durationMinutes: Int? = nil
}

struct AgentUsage: Codable {
    let sampledAt: Date
    let estimatedSessionCostUSD: Double?
    let fiveHour: AgentQuotaWindow?
    let sevenDay: AgentQuotaWindow?
    var threadTotalTokens: Int? = nil
    var codexPrimary: AgentQuotaWindow? = nil
    var codexSecondary: AgentQuotaWindow? = nil
    var accountPlan: String? = nil
}

struct AgentSnapshot {
    let provider: AgentProvider
    let sessionID: String
    let paneID: UUID
    let phase: AgentPhase
    let source: String
    let observedAt: Date
    let actionID: String?
    let usage: AgentUsage?
}

private struct AgentEventLedger: Codable {
    let savedAt: Date
    let delivered: [String]
    let dismissed: [String]
    let resolved: [String]
}

@MainActor
final class AgentMonitor {
    var onChange: (() -> Void)?
    var onNewAttention: ((AgentSnapshot) -> Void)?
    var onRoutineStart: ((AgentSnapshot) -> Void)?
    private var snapshots: [UUID: AgentSnapshot] = [:]
    private var pendingActions: [String: AgentSnapshot] = [:]
    private var delivered: Set<String> = []
    private var dismissed: Set<String> = []
    private var resolved: Set<String> = []
    private var recentClaudeApproval: Set<UUID> = []
    private var turnGeneration: [UUID: Int] = [:]
    private let liveSession: (UUID) -> TerminalSession?
    private let ledgerURL: URL?

    static var defaultLedgerURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Tile/agent-events.json")
    }

    init(ledgerURL: URL? = nil, liveSession: @escaping (UUID) -> TerminalSession?) {
        self.ledgerURL = ledgerURL
        self.liveSession = liveSession
        if let ledgerURL, let data = try? Data(contentsOf: ledgerURL),
           let saved = try? JSONDecoder().decode(AgentEventLedger.self, from: data),
           Date().timeIntervalSince(saved.savedAt) < 86_400 {
            delivered = Set(saved.delivered.prefix(512))
            dismissed = Set(saved.dismissed.prefix(512))
            resolved = Set(saved.resolved.prefix(512))
        }
    }

    func snapshot(for paneID: UUID) -> AgentSnapshot? {
        guard let snapshot = snapshots[paneID] else { return nil }
        if Date().timeIntervalSince(snapshot.observedAt) > 120 {
            return AgentSnapshot(provider: snapshot.provider, sessionID: snapshot.sessionID,
                                 paneID: paneID, phase: .unknown, source: snapshot.source,
                                 observedAt: snapshot.observedAt, actionID: nil,
                                 usage: snapshot.usage.flatMap { Date().timeIntervalSince($0.sampledAt) <= 120 ? $0 : nil })
        }
        return snapshot
    }

    func attention(in panes: [TerminalSession]) -> [AgentSnapshot] {
        let paneIDs = Set(panes.map(\.id))
        return pendingActions.values.filter { item in
            guard paneIDs.contains(item.paneID) else { return false }
            guard item.phase.priority != nil else { return false }
            return !dismissed.contains(key(for: item))
        }.sorted {
            let left = $0.phase.priority ?? 9
            let right = $1.phase.priority ?? 9
            if left != right { return left < right }
            if $0.observedAt != $1.observedAt { return $0.observedAt < $1.observedAt }
            return $0.paneID.uuidString < $1.paneID.uuidString
        }
    }

    func dismiss(_ item: AgentSnapshot) {
        dismissed.insert(key(for: item))
        pendingActions.removeValue(forKey: key(for: item))
        if let current = snapshots[item.paneID], key(for: current) == key(for: item) {
            snapshots[item.paneID] = AgentSnapshot(provider: current.provider, sessionID: current.sessionID,
                                                   paneID: current.paneID, phase: .unknown,
                                                   source: "Dismissed in Tile; provider state unconfirmed",
                                                   observedAt: current.observedAt,
                                                   actionID: nil, usage: current.usage)
        }
        persistLedger()
        onChange?()
    }

    func ingest(_ event: AgentWireEvent) {
        guard event.version == 1,
              !event.sessionID.isEmpty, event.sessionID.count <= 200,
              let session = liveSession(event.paneToken),
              session.agentToken == event.paneToken,
              session.view.process.running else { return }
        let phase: AgentPhase
        switch event.event {
        case "start", "progress", "resolved": phase = .running
        case "approval": phase = .approvalRequired
        case "question": phase = .questionRequired
        case "failure": phase = .failed
        case "completion": phase = .completedNeedsReview
        case "end": phase = .idle
        case "usage": phase = snapshots[session.id]?.phase ?? .unknown
        default: return
        }
        if let previous = snapshots[session.id], previous.sessionID != event.sessionID {
            dismissed = dismissed.filter { !$0.hasPrefix("\(session.id.uuidString):") }
            delivered = delivered.filter { !$0.hasPrefix("\(session.id.uuidString):") }
            resolved = resolved.filter { !$0.hasPrefix("\(session.id.uuidString):") }
            recentClaudeApproval.remove(session.id)
            pendingActions = pendingActions.filter { $0.value.paneID != session.id }
            turnGeneration[session.id] = 0
        }
        if event.provider == .claude, event.event == "approval",
           event.source.contains("Notification"),
           recentClaudeApproval.contains(session.id) { return }
        if event.event == "start" {
            turnGeneration[session.id, default: 0] += 1
            recentClaudeApproval.remove(session.id)
        }
        if event.event == "resolved" {
            let matching = pendingActions.filter { _, item in
                item.paneID == session.id && event.actionID != nil && item.actionID == event.actionID
            }
            for (key, _) in matching { resolved.insert(key); pendingActions.removeValue(forKey: key) }
        }
        if event.event == "end" {
            pendingActions = pendingActions.filter { $0.value.paneID != session.id }
        }
        let actionID = event.actionID ?? "\(event.event):\(event.sessionID):\(turnGeneration[session.id, default: 0])"
        let candidate = AgentSnapshot(provider: event.provider, sessionID: event.sessionID,
                                      paneID: session.id, phase: phase,
                                      source: event.event == "usage" ? (snapshots[session.id]?.source ?? event.source) : event.source,
                                      observedAt: event.event == "usage" ? (snapshots[session.id]?.observedAt ?? event.observedAt) : event.observedAt,
                                      actionID: event.event == "usage" ? snapshots[session.id]?.actionID : actionID,
                                      usage: event.usage ?? snapshots[session.id]?.usage)
        if phase.priority != nil, resolved.contains(key(for: candidate)) { return }
        if let previous = snapshots[session.id], previous.sessionID == candidate.sessionID,
           previous.phase == candidate.phase, previous.actionID == candidate.actionID,
           event.usage == nil {
            return
        }
        let wasRunning = snapshots[session.id]?.phase == .running
        snapshots[session.id] = candidate
        if phase.priority != nil { pendingActions[key(for: candidate)] = candidate }
        if event.provider == .claude, event.event == "approval" { recentClaudeApproval.insert(session.id) }
        if event.event == "start", !wasRunning { onRoutineStart?(candidate) }
        if phase.priority != nil, delivered.insert(key(for: candidate)).inserted { onNewAttention?(candidate) }
        persistLedger()
        onChange?()
    }

    func remove(paneID: UUID) {
        snapshots.removeValue(forKey: paneID)
        pendingActions = pendingActions.filter { $0.value.paneID != paneID }
        dismissed = dismissed.filter { !$0.hasPrefix("\(paneID.uuidString):") }
        delivered = delivered.filter { !$0.hasPrefix("\(paneID.uuidString):") }
        resolved = resolved.filter { !$0.hasPrefix("\(paneID.uuidString):") }
        recentClaudeApproval.remove(paneID)
        turnGeneration.removeValue(forKey: paneID)
        persistLedger()
        onChange?()
    }

    func updateManagedUsage(_ usage: AgentUsage, session: TerminalSession, threadID: String) {
        guard let previous = snapshots[session.id], previous.provider == .codex,
              previous.sessionID == threadID else { return }
        snapshots[session.id] = AgentSnapshot(provider: previous.provider, sessionID: threadID,
                                              paneID: session.id, phase: previous.phase,
                                              source: previous.source, observedAt: previous.observedAt,
                                              actionID: previous.actionID, usage: usage)
        onChange?()
    }

    private func key(for item: AgentSnapshot) -> String {
        "\(item.paneID.uuidString):\(item.sessionID):\(item.phase.rawValue):\(item.actionID ?? "")"
    }

    private func persistLedger() {
        guard let ledgerURL else { return }
        let maxEntries = 512
        if delivered.count > maxEntries { delivered = Set(delivered.prefix(maxEntries)) }
        if dismissed.count > maxEntries { dismissed = Set(dismissed.prefix(maxEntries)) }
        if resolved.count > maxEntries { resolved = Set(resolved.prefix(maxEntries)) }
        let ledger = AgentEventLedger(savedAt: Date(), delivered: Array(delivered),
                                      dismissed: Array(dismissed), resolved: Array(resolved))
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: ledgerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: ledgerURL, options: .atomic)
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ledgerURL.path)
    }
}

enum AgentHook {
    static func run(arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard arguments.count >= 2,
              let provider = AgentProvider.allCases.first(where: { $0.rawValue.lowercased() == arguments[0].lowercased() }),
              let tokenText = environment["TILE_AGENT_PANE_TOKEN"], let token = UUID(uuidString: tokenText),
              let socketPath = environment["TILE_AGENT_SOCKET"], socketPath.utf8.count < 104,
              let input = boundedInput(),
              let payload = try? JSONSerialization.jsonObject(with: input) as? [String: Any]
        else { return }
        let hook = arguments[1]
        let sessionID = (payload["session_id"] as? String)
            ?? (payload["thread_id"] as? String)
            ?? (payload["sessionId"] as? String)
        guard let sessionID, !sessionID.isEmpty else { return }
        let event: String
        switch (provider, hook) {
        case (_, "SessionStart"), (.gemini, "BeforeAgent"), (.codex, "UserPromptSubmit"), (.claude, "UserPromptSubmit"):
            event = "start"
        case (.claude, "PermissionRequest"), (.codex, "PermissionRequest"):
            event = "approval"
        case (.claude, "PreToolUse") where payload["tool_name"] as? String == "AskUserQuestion":
            event = "question"
        case (.claude, "Notification") where payload["notification_type"] as? String == "permission_prompt":
            event = "approval"
        case (.gemini, "Notification") where payload["notification_type"] as? String == "ToolPermission":
            event = "approval"
        case (.claude, "StopFailure"), (.claude, "PostToolUseFailure"), (.codex, "Interrupt"):
            event = "failure"
        case (.gemini, "AfterTool") where (payload["tool_response"] as? [String: Any])?["error"] != nil:
            event = "failure"
        case (.claude, "Stop"), (.codex, "Stop"), (.gemini, "AfterAgent"):
            event = "completion"
        case (_, "SessionEnd"):
            event = "end"
        case (.claude, "PostToolUse"), (.codex, "PostToolUse"), (.gemini, "AfterTool"):
            event = "resolved"
        default: return
        }
        let actionID = (payload["tool_use_id"] as? String)
            ?? (payload["tool_call_id"] as? String)
            ?? (payload["event_id"] as? String)
        let wire = AgentWireEvent(version: 1, provider: provider, sessionID: sessionID,
                                  paneToken: token, event: event, actionID: actionID,
                                  observedAt: Date(), source: "\(provider.rawValue) \(hook) hook")
        send(wire, socketPath: socketPath)
    }

    private static func boundedInput() -> Data? {
        var result = Data()
        while result.count <= 65_536 {
            guard let chunk = try? FileHandle.standardInput.read(upToCount: 8192) else {
                return result.isEmpty ? nil : result
            }
            if chunk.isEmpty { return result }
            result.append(chunk)
        }
        return nil
    }

    static func runClaudeStatusLine(originalCommand: String?, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let input = (try? FileHandle.standardInput.readToEnd()) ?? Data()
        if let payload = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
           let sessionID = payload["session_id"] as? String,
           let tokenText = environment["TILE_AGENT_PANE_TOKEN"], let token = UUID(uuidString: tokenText),
           let socketPath = environment["TILE_AGENT_SOCKET"] {
            let cost = (payload["cost"] as? [String: Any])?["total_cost_usd"] as? Double
            let limits = payload["rate_limits"] as? [String: Any] ?? [:]
            func window(_ name: String) -> AgentQuotaWindow? {
                guard let values = limits[name] as? [String: Any],
                      let used = values["used_percentage"] as? Double,
                      let reset = values["resets_at"] as? Double,
                      (0...100).contains(used), reset > Date().timeIntervalSince1970 else { return nil }
                return AgentQuotaWindow(usedPercent: used, resetsAt: Date(timeIntervalSince1970: reset))
            }
            let usage = AgentUsage(sampledAt: Date(), estimatedSessionCostUSD: cost,
                                   fiveHour: window("five_hour"), sevenDay: window("seven_day"))
            let wire = AgentWireEvent(version: 1, provider: .claude, sessionID: sessionID,
                                      paneToken: token, event: "usage", actionID: nil,
                                      observedAt: Date(), source: "Claude Code status line", usage: usage)
            send(wire, socketPath: socketPath)
        }
        guard let originalCommand, !originalCommand.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", originalCommand]
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            inputPipe.fileHandleForWriting.write(input)
            try? inputPipe.fileHandleForWriting.close()
            let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            FileHandle.standardOutput.write(output)
        } catch { }
    }

    private static func send(_ wire: AgentWireEvent, socketPath: String) {
        guard let data = try? JSONEncoder().encode(wire) else { return }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        socketPath.withCString { pointer in
            withUnsafeMutablePointer(to: &address.sun_path) {
                _ = strlcpy(UnsafeMutableRawPointer($0).assumingMemoryBound(to: CChar.self), pointer, capacity)
            }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return }
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.send(fd, base.advanced(by: offset), bytes.count - offset, 0)
                guard written > 0 else { break }
                offset += written
            }
        }
    }
}

@MainActor
final class AgentBridge {
    static var currentPath: String?
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private var socketPath: String?
    var onEvent: ((AgentWireEvent) -> Void)?

    func start() {
        guard descriptor < 0 else { return }
        let path = "/tmp/tile-agent-\(getuid())-\(getpid()).sock"
        guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else { return }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        path.withCString { pointer in
            withUnsafeMutablePointer(to: &address.sun_path) {
                _ = strlcpy(UnsafeMutableRawPointer($0).assumingMemoryBound(to: CChar.self), pointer,
                            pathCapacity)
            }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else { close(fd); return }
        _ = chmod(path, 0o600)
        descriptor = fd
        socketPath = path
        Self.currentPath = path
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.acceptOne() }
        source.resume()
        self.source = source
    }

    private func acceptOne() {
        let client = accept(descriptor, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }
        var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
        _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 2048)
        while data.count <= 8192 {
            let count = recv(client, &bytes, bytes.count, 0)
            if count == 0 { break }
            guard count > 0 else { return }
            data.append(contentsOf: bytes.prefix(count))
        }
        guard !data.isEmpty, data.count <= 8192,
              let event = try? JSONDecoder().decode(AgentWireEvent.self, from: data) else { return }
        onEvent?(event)
    }

    deinit {
        source?.cancel()
        if descriptor >= 0 { close(descriptor) }
        if let socketPath { unlink(socketPath) }
    }
}
