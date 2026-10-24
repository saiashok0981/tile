import AppKit

@MainActor
func runAgentWorkflowTest() -> Bool {
    let manager = FileManager.default
    let home = manager.temporaryDirectory.appending(path: "tile-agent-test-\(UUID().uuidString)")
    defer { try? manager.removeItem(at: home) }
    do {
        let url = AgentIntegrations.settingsURL(for: .claude, home: home)
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original: [String: Any] = [
            "theme": "dark",
            "statusLine": ["type": "command", "command": "printf original"],
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "printf kept"]]]]]
        ]
        try JSONSerialization.data(withJSONObject: original).write(to: url)
        try AgentIntegrations.setEnabled(true, for: .claude, home: home, executable: "/tmp/Tile")
        guard AgentIntegrations.isEnabled(.claude, home: home) else { return false }
        try AgentIntegrations.setEnabled(true, for: .claude, home: home, executable: "/tmp/Tile")
        if var enabled = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
           var statusLine = enabled["statusLine"] as? [String: Any] {
            statusLine["padding"] = 3
            enabled["statusLine"] = statusLine
            try JSONSerialization.data(withJSONObject: enabled).write(to: url)
        } else { return false }
        try AgentIntegrations.setEnabled(false, for: .claude, home: home, executable: "/tmp/Tile")
        let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        guard restored?["theme"] as? String == "dark",
              (restored?["statusLine"] as? [String: Any])?["command"] as? String == "printf original",
              (restored?["statusLine"] as? [String: Any])?["padding"] as? Int == 3,
              let hooks = restored?["hooks"] as? [String: Any],
              let stop = hooks["Stop"] as? [[String: Any]], stop.count == 1 else { return false }
    } catch {
        fputs("Agent settings merge failed: \(error)\n", stderr)
        return false
    }
    let session = TerminalSession(directory: manager.homeDirectoryForCurrentUser.path)
    defer { session.view.terminate() }
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    let monitor = AgentMonitor { token in token == session.agentToken ? session : nil }
    var changes = 0
    var alerts = 0
    monitor.onChange = { changes += 1 }
    monitor.onNewAttention = { _ in alerts += 1 }
    let approval = AgentWireEvent(version: 1, provider: .claude, sessionID: "session-1",
                                  paneToken: session.agentToken, event: "approval", actionID: "action-1",
                                  observedAt: Date(), source: "Claude Code PermissionRequest hook")
    monitor.ingest(approval)
    monitor.ingest(approval)
    guard monitor.snapshot(for: session.id)?.phase == .approvalRequired,
          monitor.attention(in: [session]).count == 1,
          changes == 1, alerts == 1 else { return false }
    let wrong = AgentWireEvent(version: 1, provider: .claude, sessionID: "session-1",
                               paneToken: UUID(), event: "failure", actionID: "action-2",
                               observedAt: Date(), source: "test")
    monitor.ingest(wrong)
    guard monitor.snapshot(for: session.id)?.phase == .approvalRequired else { return false }
    let resolved = AgentWireEvent(version: 1, provider: .claude, sessionID: "session-1",
                                  paneToken: session.agentToken, event: "resolved", actionID: "action-1",
                                  observedAt: Date(), source: "Claude Code PostToolUse hook")
    monitor.ingest(resolved)
    guard monitor.attention(in: [session]).isEmpty else { return false }
    let completed = AgentWireEvent(version: 1, provider: .claude, sessionID: "session-1",
                                   paneToken: session.agentToken, event: "completion", actionID: "turn-1",
                                   observedAt: Date(), source: "Claude Code Stop hook")
    monitor.ingest(completed)
    guard monitor.attention(in: [session]).first?.phase == .completedNeedsReview else { return false }
    if let item = monitor.attention(in: [session]).first { monitor.dismiss(item) }
    guard monitor.attention(in: [session]).isEmpty else { return false }
    let nextTurn = AgentWireEvent(version: 1, provider: .claude, sessionID: "session-1",
                                  paneToken: session.agentToken, event: "start", actionID: nil,
                                  observedAt: Date(), source: "Claude Code UserPromptSubmit hook")
    monitor.ingest(nextTurn)
    let completedNextTurn = AgentWireEvent(version: 1, provider: .claude, sessionID: "session-1",
                                           paneToken: session.agentToken, event: "completion", actionID: "turn-2",
                                           observedAt: Date(), source: "Claude Code Stop hook")
    monitor.ingest(completedNextTurn)
    guard monitor.attention(in: [session]).count == 1 else { return false }
    let bridge = AgentBridge()
    bridge.onEvent = { monitor.ingest($0) }
    bridge.start()
    guard let socketPath = AgentBridge.currentPath,
          let executable = Bundle.main.executablePath else { return false }
    let statusLine = Process()
    statusLine.executableURL = URL(fileURLWithPath: executable)
    statusLine.arguments = ["--agent-statusline", Data("cat".utf8).base64EncodedString()]
    let statusInput = Pipe()
    let statusOutput = Pipe()
    statusLine.standardInput = statusInput
    statusLine.standardOutput = statusOutput
    statusLine.standardError = FileHandle.nullDevice
    do {
        try statusLine.run()
        let sample = Data(#"{"session_id":"sample","cost":{"total_cost_usd":0.25}}"#.utf8)
        statusInput.fileHandleForWriting.write(sample)
        try? statusInput.fileHandleForWriting.close()
        let forwarded = statusOutput.fileHandleForReading.readDataToEndOfFile()
        statusLine.waitUntilExit()
        guard forwarded == sample else { return false }
    } catch { return false }
    func sendHook(_ provider: String, _ event: String, _ payload: String,
                  socketOverride: String? = nil) -> Bool {
        let hook = Process()
        hook.executableURL = URL(fileURLWithPath: executable)
        hook.arguments = ["--agent-hook", provider, event]
        var environment = ProcessInfo.processInfo.environment
        environment["TILE_AGENT_PANE_TOKEN"] = session.agentToken.uuidString
        environment["TILE_AGENT_SOCKET"] = socketOverride ?? socketPath
        hook.environment = environment
        let input = Pipe()
        hook.standardInput = input
        hook.standardOutput = FileHandle.nullDevice
        hook.standardError = FileHandle.nullDevice
        do {
            try hook.run()
            input.fileHandleForWriting.write(Data(payload.utf8))
            try? input.fileHandleForWriting.close()
            while hook.isRunning { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        } catch { return false }
        return hook.terminationStatus == 0
    }
    guard sendHook("Claude Code", "PermissionRequest", #"{"session_id":"session-2","tool_use_id":"action-2"}"#),
          monitor.attention(in: [session]).first?.sessionID == "session-2" else { return false }
    let alertCount = alerts
    guard sendHook("Claude Code", "Notification", #"{"session_id":"session-2","notification_type":"permission_prompt"}"#),
          alerts == alertCount else { return false }
    let noBridge = "/tmp/tile-agent-missing-\(UUID().uuidString).sock"
    guard sendHook("Codex", "PermissionRequest", #"{"session_id":"missing-bridge","tool_use_id":"missing"}"#,
                   socketOverride: noBridge),
          alerts == alertCount else { return false }
    let delayedNotification = AgentWireEvent(version: 1, provider: .claude, sessionID: "session-2",
                                             paneToken: session.agentToken, event: "approval", actionID: nil,
                                             observedAt: Date().addingTimeInterval(45),
                                             source: "Claude Code Notification hook")
    monitor.ingest(delayedNotification)
    guard alerts == alertCount, monitor.attention(in: [session]).count == 1 else { return false }
    guard sendHook("Codex", "PermissionRequest", #"{"session_id":"session-3","turn_id":"turn-3","tool_use_id":"tool-3"}"#),
          monitor.snapshot(for: session.id)?.provider == .codex,
          monitor.snapshot(for: session.id)?.phase == .approvalRequired else { return false }
    guard sendHook("Gemini CLI", "Notification", #"{"session_id":"session-4","notification_type":"ToolPermission"}"#),
          monitor.snapshot(for: session.id)?.provider == .gemini,
          monitor.snapshot(for: session.id)?.phase == .approvalRequired else { return false }
    let question = AgentWireEvent(version: 1, provider: .gemini, sessionID: "session-4",
                                  paneToken: session.agentToken, event: "question", actionID: "question-4",
                                  observedAt: Date(), source: "fixture")
    monitor.ingest(question)
    guard monitor.attention(in: [session]).count == 2 else { return false }
    let unknownResolution = AgentWireEvent(version: 1, provider: .gemini, sessionID: "session-4",
                                           paneToken: session.agentToken, event: "resolved", actionID: nil,
                                           observedAt: Date(), source: "Gemini CLI AfterTool hook")
    monitor.ingest(unknownResolution)
    guard monitor.attention(in: [session]).count == 2 else { return false }
    let stale = AgentWireEvent(version: 1, provider: .gemini, sessionID: "session-5",
                               paneToken: session.agentToken, event: "approval", actionID: "stale-1",
                               observedAt: Date().addingTimeInterval(-121), source: "Gemini CLI Notification hook")
    monitor.ingest(stale)
    guard monitor.snapshot(for: session.id)?.phase == .unknown,
          monitor.attention(in: [session]).first?.sessionID == "session-5" else { return false }
    session.view.terminate()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    let restored = TerminalSession(directory: session.directory)
    defer { restored.view.terminate() }
    let afterRestart = AgentMonitor { token in
        if token == session.agentToken { return session }
        if token == restored.agentToken { return restored }
        return nil
    }
    afterRestart.ingest(approval)
    guard afterRestart.snapshot(for: restored.id) == nil else { return false }
    let fresh = AgentWireEvent(version: 1, provider: .codex, sessionID: "new-shell",
                               paneToken: restored.agentToken, event: "start", actionID: nil,
                               observedAt: Date(), source: "Codex SessionStart hook")
    afterRestart.ingest(fresh)
    return afterRestart.snapshot(for: restored.id)?.phase == .running
}

@MainActor
func runManagedCodexProtocolTest() -> Bool {
    let app = TileApp()
    let session = TerminalSession(directory: FileManager.default.homeDirectoryForCurrentUser.path)
    defer { session.view.terminate() }
    let managed = ManagedCodexSession(pane: session, app: app)
    let deadline = Date().addingTimeInterval(5)
    while !managed.isConnected && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    let connected = managed.isConnected
    managed.close()
    if !connected { fputs("Managed Codex did not complete the app-server handshake\n", stderr) }
    return connected
}

@MainActor
func runCodexLiveVerification() -> Bool {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appending(path: "tile-codex-live-\(UUID().uuidString)")
    do { try manager.createDirectory(at: directory, withIntermediateDirectories: true) }
    catch { fputs("Cannot create live-test directory: \(error)\n", stderr); return false }
    defer { try? manager.removeItem(at: directory) }

    let bridge = AgentBridge()
    bridge.start()
    guard AgentBridge.currentPath != nil else { fputs("Agent bridge did not start\n", stderr); return false }
    let app = TileApp()
    let pane = TerminalSession(directory: directory.path)
    defer { pane.view.terminate() }
    let secondPane = TerminalSession(directory: directory.path)
    defer { secondPane.view.terminate() }
    let window = TileWindow(workspaces: [Workspace(panes: [pane])], owner: app)
    app.windows.append(window)
    window.window?.makeKeyAndOrderFront(nil)
    let destination = TileWindow(workspaces: [Workspace(panes: [secondPane])], owner: app)
    app.windows.append(destination)
    defer { window.close(); destination.close() }
    var events: [String] = []
    var eventTokens: [UUID] = []
    bridge.onEvent = { event in
        events.append(event.event)
        eventTokens.append(event.paneToken)
        app.agentMonitor.ingest(event)
    }

    let output = directory.appending(path: "codex.jsonl")
    let errors = directory.appending(path: "codex.stderr")
    let done = directory.appending(path: "done")
    let secondOutput = directory.appending(path: "codex-second.jsonl")
    let secondErrors = directory.appending(path: "codex-second.stderr")
    let secondDone = directory.appending(path: "second-done")
    let command = "codex exec -C '\(directory.path)' --skip-git-repo-check --ephemeral --sandbox read-only --dangerously-bypass-hook-trust --json 'Reply exactly READY. Do not use tools.' </dev/null >'\(output.path)' 2>'\(errors.path)'; printf '%s' \"$?\" >'\(done.path)'\n"
    let secondCommand = "codex exec -C '\(directory.path)' --skip-git-repo-check --ephemeral --sandbox read-only --dangerously-bypass-hook-trust --json 'Reply exactly READY. Do not use tools.' </dev/null >'\(secondOutput.path)' 2>'\(secondErrors.path)'; printf '%s' \"$?\" >'\(secondDone.path)'\n"
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    let bytes = Array(command.utf8)
    pane.view.process.send(data: bytes[...])
    let secondBytes = Array(secondCommand.utf8)
    secondPane.view.process.send(data: secondBytes[...])
    let originalPID = pane.view.process.shellPid
    window.remove(pane)
    destination.add(pane)
    guard pane.view.process.shellPid == originalPID,
          app.window(containing: pane) === destination else { return false }
    let deadline = Date().addingTimeInterval(90)
    while (!manager.fileExists(atPath: done.path) || !manager.fileExists(atPath: secondDone.path)) && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    let status = (try? String(contentsOf: done, encoding: .utf8)) ?? "timed out"
    let secondStatus = (try? String(contentsOf: secondDone, encoding: .utf8)) ?? "timed out"
    let outputText = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
    let secondOutputText = (try? String(contentsOf: secondOutput, encoding: .utf8)) ?? ""
    let errorText = (try? String(contentsOf: errors, encoding: .utf8)) ?? ""
    let secondErrorText = (try? String(contentsOf: secondErrors, encoding: .utf8)) ?? ""
    let turnCompleted = outputText.contains("\"type\":\"turn.completed\"")
    let secondTurnCompleted = secondOutputText.contains("\"type\":\"turn.completed\"")
    let snapshot = app.agentMonitor.snapshot(for: pane.id)
    let secondSnapshot = app.agentMonitor.snapshot(for: secondPane.id)
    func hookCount(_ name: String, token: UUID) -> Int {
        zip(events, eventTokens).filter { $0.0 == name && $0.1 == token }.count
    }
    print("Codex live panes: exits=\(status),\(secondStatus), turnsCompleted=\(turnCompleted),\(secondTurnCompleted), hooks=\(events), linkedPanes=\(Set(eventTokens).count), movedPanePhase=\(snapshot?.phase.label ?? "none"), secondPanePhase=\(secondSnapshot?.phase.label ?? "none")")
    if status != "0" { fputs("Codex stderr: \(errorText.prefix(600))\n", stderr) }
    if secondStatus != "0" { fputs("Second Codex stderr: \(secondErrorText.prefix(600))\n", stderr) }
    return status == "0" && secondStatus == "0" && turnCompleted && secondTurnCompleted &&
        snapshot?.provider == .codex && secondSnapshot?.provider == .codex &&
        snapshot?.sessionID != secondSnapshot?.sessionID &&
        hookCount("start", token: pane.agentToken) >= 1 &&
        hookCount("start", token: secondPane.agentToken) >= 1 &&
        hookCount("completion", token: pane.agentToken) == 1 &&
        hookCount("completion", token: secondPane.agentToken) == 1 &&
        hookCount("end", token: pane.agentToken) == 1 &&
        hookCount("end", token: secondPane.agentToken) == 1
}

@MainActor
func runManagedCodexLiveVerification() -> Bool {
    let directory = FileManager.default.temporaryDirectory.appending(path: "tile-managed-codex-live-\(UUID().uuidString)")
    do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    catch { return false }
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = TileApp()
    let pane = TerminalSession(directory: directory.path)
    defer { pane.view.terminate() }
    let window = TileWindow(workspaces: [Workspace(panes: [pane])], owner: app)
    app.windows.append(window)
    window.window?.makeKeyAndOrderFront(nil)
    let managed = ManagedCodexSession(pane: pane, app: app)
    defer { managed.close(); window.close() }
    let connectionDeadline = Date().addingTimeInterval(10)
    while !managed.isConnected && Date() < connectionDeadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    guard managed.isConnected else { fputs("Managed Codex did not connect\n", stderr); return false }
    managed.submitPrompt("Reply exactly READY. Do not use tools.")
    let turnDeadline = Date().addingTimeInterval(60)
    while Date() < turnDeadline {
        let snapshot = app.agentMonitor.snapshot(for: pane.id)
        if snapshot?.phase == .completedNeedsReview { break }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    let snapshot = app.agentMonitor.snapshot(for: pane.id)
    let usage = snapshot?.usage
    print("Managed Codex live pane: phase=\(snapshot?.phase.label ?? "none"), threadTokens=\(usage?.threadTotalTokens.map(String.init) ?? "unavailable"), accountPrimary=\(usage?.codexPrimary.map { String(Int($0.usedPercent)) } ?? "unavailable"), accountSecondary=\(usage?.codexSecondary.map { String(Int($0.usedPercent)) } ?? "unavailable"), attention=\(app.agentMonitor.attention(in: [pane]).count)")
    managed.close()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    let ended = app.agentMonitor.snapshot(for: pane.id)?.phase == .idle &&
        app.agentMonitor.attention(in: [pane]).isEmpty
    return snapshot?.phase == .completedNeedsReview && usage?.threadTotalTokens != nil && ended
}

@MainActor
func viewDescendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(viewDescendants)
}

@MainActor
func runKeyboardWorkflowTest() -> Bool {
    let defaults = UserDefaults.standard
    let previousSnapshot = defaults.data(forKey: "workspaceSnapshot")
    let actions: [TileAction] = [.focusLeft, .focusRight, .focusUp, .focusDown,
                                 .workspace1, .workspace2, .focusSelectedTerminal,
                                 .renamePane, .closePane]
    let savedShortcuts = Dictionary(uniqueKeysWithValues: actions.map { ($0, defaults.object(forKey: "shortcut.\($0.rawValue)")) })
    defaults.removeObject(forKey: "workspaceSnapshot")
    for action in actions { defaults.removeObject(forKey: "shortcut.\(action.rawValue)") }
    defer {
        defaults.set(previousSnapshot, forKey: "workspaceSnapshot")
        for (action, value) in savedShortcuts { defaults.set(value, forKey: "shortcut.\(action.rawValue)") }
    }
    let app = TileApp()
    NSApp.delegate = app
    var passed = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        guard let controller = app.windows.first, let tileWindow = controller.window,
              tileWindow.isKeyWindow else {
            fputs("Keyboard check has no active Tile window\n", stderr)
            NSApp.stop(nil)
            return
        }
        @MainActor func sendKey(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags) {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                               timestamp: 0, windowNumber: tileWindow.windowNumber,
                                               context: nil, characters: characters,
                                               charactersIgnoringModifiers: characters,
                                               isARepeat: false, keyCode: code) else { return }
            NSApp.sendEvent(event)
        }
        for _ in 0..<3 { app.addPane(to: controller) }
        controller.focusTerminal(controller.workspace.panes[0])
        sendKey(124, "", .option)
        guard controller.selectedPane == controller.workspace.panes[1].id else {
            fputs("Option-Right did not focus the adjacent terminal\n", stderr)
            NSApp.stop(nil)
            return
        }
        sendKey(125, "", .option)
        guard controller.selectedPane == controller.workspace.panes[3].id else {
            fputs("Option-Down did not focus the adjacent terminal\n", stderr)
            NSApp.stop(nil)
            return
        }
        sendKey(124, "", .option)
        guard controller.selectedPane == controller.workspace.panes[3].id else {
            fputs("Navigation past a pane edge changed focus\n", stderr)
            NSApp.stop(nil)
            return
        }
        app.addPane(to: controller)
        sendKey(18, "1", .command)
        guard controller.selectedWorkspace == 0, tileWindow.firstResponder === controller.currentSession?.view else {
            fputs("Command-1 did not switch workspace and focus its terminal\n", stderr)
            NSApp.stop(nil)
            return
        }
        sendKey(19, "2", .command)
        guard controller.selectedWorkspace == 1 else {
            fputs("Command-2 did not switch workspace\n", stderr)
            NSApp.stop(nil)
            return
        }
        _ = tileWindow.makeFirstResponder(nil)
        sendKey(36, "\r", [.command, .shift])
        guard tileWindow.firstResponder === controller.currentSession?.view else {
            fputs("Focus selected terminal shortcut did not restore input\n", stderr)
            NSApp.stop(nil)
            return
        }
        sendKey(18, "1", .command)
        let count = controller.workspace.panes.count
        sendKey(13, "w", [.command, .shift])
        guard controller.workspace.panes.count == count - 1 else {
            fputs("Close selected terminal shortcut did not close the pane\n", stderr)
            NSApp.stop(nil)
            return
        }
        guard let renamed = controller.currentSession else { NSApp.stop(nil); return }
        let saveRename = Timer(timeInterval: 0.1, repeats: false) { _ in
            MainActor.assumeIsolated {
                guard let modal = NSApp.modalWindow,
                      let root = modal.contentView else {
                    fputs("Rename dialog is not modal\n", stderr)
                    NSApp.stopModal(withCode: .cancel)
                    return
                }
                let descendants = viewDescendants(root)
                guard let field = descendants.compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable }),
                      let save = descendants.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Save" }) else {
                    fputs("Rename dialog controls are missing\n", stderr)
                    NSApp.stopModal(withCode: .cancel)
                    return
                }
                field.stringValue = "Renamed by keyboard"
                save.performClick(nil)
            }
        }
        RunLoop.main.add(saveRename, forMode: RunLoop.Mode("NSModalPanelRunLoopMode"))
        sendKey(15, "r", [.command, .shift])
        guard renamed.customTitle == "Renamed by keyboard" else {
            fputs("Rename selected terminal shortcut did not rename the pane\n", stderr)
            NSApp.stop(nil)
            return
        }
        controller.selectWorkspace(1)
        app.newWindow()
        guard let other = app.windows.last, other !== controller,
              let otherWindow = other.window, otherWindow.isKeyWindow else {
            fputs("Second Tile window did not become active\n", stderr)
            NSApp.stop(nil)
            return
        }
        for _ in 0..<4 { app.addPane(to: other) }
        guard other.selectedWorkspace == 1 else { NSApp.stop(nil); return }
        guard let switchFirst = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                                  timestamp: 0, windowNumber: otherWindow.windowNumber,
                                                  context: nil, characters: "1", charactersIgnoringModifiers: "1",
                                                  isARepeat: false, keyCode: 18) else { NSApp.stop(nil); return }
        NSApp.sendEvent(switchFirst)
        guard other.selectedWorkspace == 0, controller.selectedWorkspace == 1 else {
            fputs("Switching workspaces changed another Tile window\n", stderr)
            NSApp.stop(nil)
            return
        }
        passed = true
        NSApp.stop(nil)
    }
    NSApp.run()
    for window in Array(app.windows) {
        window.allowClose = true
        window.allSessions.forEach { $0.view.terminate() }
        window.window?.close()
    }
    if passed { print("Keyboard workflow check passed") }
    return passed
}

@MainActor
func runInputFocusTest() -> Bool {
    let defaults = UserDefaults.standard
    let previousSnapshot = defaults.data(forKey: "workspaceSnapshot")
    defer { defaults.set(previousSnapshot, forKey: "workspaceSnapshot") }
    let app = TileApp()
    app.newWindow()
    let controller = app.windows[0]
    defer {
        controller.allowClose = true
        controller.allSessions.forEach { $0.view.terminate() }
        controller.window?.close()
    }
    var passed = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        guard let root = controller.window?.contentView,
              let first = controller.currentSession else { NSApp.stop(nil); return }
        @MainActor func hasFocusCue(_ session: TerminalSession) -> Bool {
            guard let pane = viewDescendants(root).compactMap({ $0 as? PaneView }).first(where: { $0.session === session }) else { return false }
            return viewDescendants(pane).contains { $0.identifier?.rawValue == "tile.inputFocusIndicator" && !$0.isHidden }
        }
        guard controller.window?.isKeyWindow == true,
              controller.window?.firstResponder === first.view,
              hasFocusCue(first) else {
            fputs("Initial terminal input focus is not visible\n", stderr)
            NSApp.stop(nil)
            return
        }
        app.addPane(to: controller)
        guard let second = controller.currentSession,
              controller.window?.firstResponder === second.view,
              hasFocusCue(second), !hasFocusCue(first) else {
            fputs("New terminal input focus cue did not follow input\n", stderr)
            NSApp.stop(nil)
            return
        }
        _ = controller.window?.makeFirstResponder(first.view)
        guard hasFocusCue(first), !hasFocusCue(second) else {
            fputs("Terminal input focus cue did not follow responder change\n", stderr)
            NSApp.stop(nil)
            return
        }
        _ = controller.window?.makeFirstResponder(nil)
        guard !hasFocusCue(first), !hasFocusCue(second) else {
            fputs("Terminal input focus cue stayed active outside terminal input\n", stderr)
            NSApp.stop(nil)
            return
        }
        _ = controller.window?.makeFirstResponder(second.view)
        controller.toggleFocus()
        guard controller.focused,
              viewDescendants(root).compactMap({ $0 as? PaneView }).count == 1,
              controller.window?.firstResponder === second.view else {
            fputs("Focus mode did not expand and focus the selected terminal\n", stderr)
            NSApp.stop(nil)
            return
        }
        _ = controller.window?.makeFirstResponder(nil)
        guard controller.escapeFocus(), !controller.focused,
              viewDescendants(root).compactMap({ $0 as? PaneView }).count == 2,
              controller.window?.firstResponder === second.view else {
            fputs("Leaving Focus did not restore split layout and input\n", stderr)
            NSApp.stop(nil)
            return
        }
        controller.close(second)
        guard controller.window?.firstResponder === first.view, hasFocusCue(first) else {
            fputs("Closing the active terminal did not focus the remaining terminal\n", stderr)
            NSApp.stop(nil)
            return
        }
        passed = true
        NSApp.stop(nil)
    }
    NSApp.run()
    if passed { print("Input focus check passed") }
    return passed
}

@MainActor
func runFourPaneLayoutTest() -> Bool {
    _ = NSApplication.shared
    let defaults = UserDefaults.standard
    let previousGap = defaults.object(forKey: "paneGap")
    let previousTransparency = defaults.object(forKey: "transparentPaneGaps")
    let previousRadius = defaults.object(forKey: "paneCornerRadius")
    let previousSnapshot = defaults.data(forKey: "workspaceSnapshot")
    defaults.set(16, forKey: "paneGap")
    defaults.set(true, forKey: "transparentPaneGaps")
    defaults.set(0, forKey: "paneCornerRadius")
    defer {
        defaults.set(previousGap, forKey: "paneGap")
        defaults.set(previousTransparency, forKey: "transparentPaneGaps")
        defaults.set(previousRadius, forKey: "paneCornerRadius")
        defaults.set(previousSnapshot, forKey: "workspaceSnapshot")
    }
    let app = TileApp()
    app.newWindow()
    let controller = app.windows[0]
    defer {
        controller.allowClose = true
        controller.allSessions.forEach { $0.view.terminate() }
        controller.window?.close()
    }
    guard let root = controller.window?.contentView as? TileRootView,
          let plus = viewDescendants(root).compactMap({ $0 as? NSButton }).first(where: { $0.title == "+" }),
          let settings = viewDescendants(root).compactMap({ $0 as? NSButton }).first(where: { $0.title == "⚙" }),
          let brand = viewDescendants(root).compactMap({ $0 as? TileBrandView }).first(where: { $0.identifier?.rawValue == "tile.brand" }),
          let tabs = viewDescendants(root).compactMap({ $0 as? NSStackView }).first(where: { $0.identifier?.rawValue == "tile.workspaceTabs" }),
          let agents = viewDescendants(root).compactMap({ $0 as? NSButton }).first(where: { $0.identifier?.rawValue == "tile.agentOverview" }),
          let clock = viewDescendants(root).compactMap({ $0 as? NSTextField }).first(where: { $0.identifier?.rawValue == "tile.clock" }) else {
        fputs("Four-pane check: toolbar control or logo is missing\n", stderr)
        return false
    }
    guard (controller.window?.backgroundColor.alphaComponent ?? 1) <= 0.02 else {
        fputs("Normal-sized window lost clear pane gaps\n", stderr)
        return false
    }
    controller.window?.setContentSize(NSSize(width: 1600, height: 900))
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    root.layoutSubtreeIfNeeded()
    let settingsFrame = settings.convert(settings.bounds, to: root)
    let brandFrame = brand.convert(brand.bounds, to: root)
    let tabsFrame = tabs.convert(tabs.bounds, to: root)
    let agentsFrame = agents.convert(agents.bounds, to: root)
    let clockFrame = clock.convert(clock.bounds, to: root)
    let freeSpaceCenter = (tabsFrame.maxX + agentsFrame.minX) / 2
    guard settingsFrame.maxX >= root.bounds.maxX - 20,
          brandFrame.width >= 70,
          brandFrame.minX >= 0,
          abs(clockFrame.midX - freeSpaceCenter) < 2,
          TileBrand.image.size.width > 0,
          [TileClock.label(for: Date()), TileClock.label(for: Date().addingTimeInterval(-60))].contains(clock.stringValue) else {
        fputs("Wide-window toolbar alignment failed: settings at \(settingsFrame.maxX), edge \(root.bounds.maxX), clock center \(clockFrame.midX), free-space center \(freeSpaceCenter)\n", stderr)
        return false
    }
    controller.window?.setContentSize(NSSize(width: 500, height: 500))
    root.layoutSubtreeIfNeeded()
    guard let picker = viewDescendants(root).compactMap({ $0 as? NSPopUpButton }).first(where: { $0.isHidden == false }),
          brand.isHidden, clock.isHidden, tabs.isHidden,
          !plus.isHidden, !settings.isHidden,
          root.bounds.contains(plus.convert(plus.bounds, to: root)),
          root.bounds.contains(settings.convert(settings.bounds, to: root)),
          root.bounds.contains(picker.convert(picker.bounds, to: root)) else {
        fputs("Compact toolbar hides an essential control\n", stderr)
        return false
    }
    controller.window?.setContentSize(NSSize(width: 1600, height: 900))
    plus.performClick(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let firstFrames = viewDescendants(root).compactMap { $0 as? SelectableTerminalView }.map { $0.convert($0.bounds, to: nil) }
    guard firstFrames.count == 2,
          firstFrames.allSatisfy({ $0.width > 100 && $0.height > 100 }),
          firstFrames[0].intersection(firstFrames[1]).isEmpty else {
        fputs("Two-pane check failed: frames \(firstFrames)\n", stderr)
        return false
    }
    for _ in 0..<2 { plus.performClick(nil) }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let terminals = viewDescendants(root).compactMap { $0 as? SelectableTerminalView }
    let frames = terminals.map { $0.convert($0.bounds, to: nil) }
    let paneFrames = viewDescendants(root).compactMap { $0 as? PaneView }.map { $0.convert($0.bounds, to: nil) }
    let gapSurfaces = viewDescendants(root).compactMap { $0 as? DropSurface }
    let interiorGaps = root.interiorGapRects()
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(root.bounds.width), pixelsHigh: Int(root.bounds.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        fputs("Could not render the gap transparency check\n", stderr)
        return false
    }
    root.cacheDisplay(in: root.bounds, to: bitmap)
    let interiorPoint = interiorGaps.first.map { NSPoint(x: $0.midX, y: $0.midY) } ?? .zero
    let gapAlpha = bitmap.colorAt(x: Int(interiorPoint.x), y: Int(interiorPoint.y))?.alphaComponent ?? 1
    let outerAlpha = bitmap.colorAt(x: 2, y: Int(interiorPoint.y))?.alphaComponent ?? 0
    guard terminals.count == 4,
          paneFrames.count == 4,
          interiorGaps.count == 3,
          gapAlpha < 0.05,
          outerAlpha > 0.95,
          interiorGaps.allSatisfy({ $0.minX >= paneFrames.map(\.minX).min()! && $0.maxX <= paneFrames.map(\.maxX).max()! }),
          interiorGaps.allSatisfy({ $0.minY >= paneFrames.map(\.minY).min()! && $0.maxY <= paneFrames.map(\.maxY).max()! }),
          controller.window?.isOpaque == false,
          gapSurfaces.allSatisfy({ ($0.layer?.backgroundColor?.alpha ?? 0) == 0 }),
          paneFrames[1].minX - paneFrames[0].maxX >= 14,
          paneFrames[0].minY - paneFrames[2].maxY >= 14,
          frames.allSatisfy({ $0.width > 100 && $0.height > 100 }),
          frames.allSatisfy({ root.bounds.contains($0) }),
          (0..<4).allSatisfy({ i in
              ((i + 1)..<4).allSatisfy { j in frames[i].intersection(frames[j]).isEmpty }
          }) else {
        fputs("Four-pane check failed: \(terminals.count) views, frames \(frames)\n", stderr)
        return false
    }
    controller.window?.setContentSize(NSSize(width: 1200, height: 760))
    controller.window?.center()
    guard let screen = controller.window?.screen, let normalFrame = controller.window?.frame else {
        fputs("No screen for desktop full-screen check\n", stderr)
        return false
    }
    let presentationOptions = NSApp.presentationOptions
    let shellPIDs = controller.allSessions.map { $0.view.process.shellPid }
    guard controller.window?.standardWindowButton(.zoomButton)?.action == #selector(TileWindow.toggleDesktopFullScreen) else {
        fputs("Green window button is not connected to desktop full screen\n", stderr)
        return false
    }
    controller.window?.toggleFullScreen(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    let savedFrame = UserDefaults.standard.data(forKey: "workspaceSnapshot")
        .flatMap { try? JSONDecoder().decode(WorkspaceSnapshot.self, from: $0) }?
        .windows.first?.frame
    guard controller.isDesktopFullScreen,
          controller.window?.frame == screen.frame,
          controller.window?.styleMask.contains(.fullScreen) == false,
          controller.window?.styleMask.contains(.titled) == false,
          (controller.window?.backgroundColor.alphaComponent ?? 1) <= 0.02,
          NSApp.presentationOptions.contains([.autoHideMenuBar, .autoHideDock]),
          savedFrame == NSStringFromRect(normalFrame),
          controller.allSessions.map({ $0.view.process.shellPid }) == shellPIDs else {
        fputs("Wallpaper-visible full-screen mode failed\n", stderr)
        return false
    }
    controller.window?.toggleFullScreen(nil)
    guard !controller.isDesktopFullScreen,
          controller.window?.frame == normalFrame,
          controller.window?.styleMask.contains(.titled) == true,
          controller.window?.standardWindowButton(.zoomButton)?.action == #selector(TileWindow.toggleDesktopFullScreen),
          NSApp.presentationOptions == presentationOptions else {
        fputs("Leaving wallpaper-visible full-screen mode failed: active \(controller.isDesktopFullScreen), frame \(String(describing: controller.window?.frame)), original \(normalFrame), titled \(String(describing: controller.window?.styleMask.contains(.titled))), presentation \(NSApp.presentationOptions)\n", stderr)
        return false
    }
    app.showSettings()
    guard let settingsWindow = NSApp.windows.first(where: { $0.title == "Tile Settings" }),
          let settingsRoot = settingsWindow.contentView,
          let slider = viewDescendants(settingsRoot).compactMap({ $0 as? NSSlider }).first(where: { $0.identifier?.rawValue == "tile.cornerRadius" }) else {
        fputs("Corner radius slider is missing\n", stderr)
        return false
    }
    slider.doubleValue = 16
    _ = NSApp.sendAction(slider.action!, to: slider.target, from: slider)
    guard viewDescendants(root).compactMap({ $0 as? PaneView }).allSatisfy({ $0.layer?.cornerRadius == 16 && $0.layer?.masksToBounds == true }) else {
        fputs("Corner radius live preview failed\n", stderr)
        return false
    }
    settingsWindow.close()
    guard viewDescendants(root).compactMap({ $0 as? PaneView }).allSatisfy({ $0.layer?.cornerRadius == 0 }) else {
        fputs("Corner radius cancel preview failed\n", stderr)
        return false
    }
    defaults.set(12, forKey: "paneCornerRadius")
    controller.render()
    root.layoutSubtreeIfNeeded()
    guard viewDescendants(root).compactMap({ $0 as? PaneView }).allSatisfy({ $0.layer?.cornerRadius == 12 }) else {
        fputs("Saved corner radius was not applied to new pane views\n", stderr)
        return false
    }
    UserDefaults.standard.set(false, forKey: "transparentPaneGaps")
    controller.render()
    guard controller.window?.isOpaque == true,
          controller.window?.backgroundColor.alphaComponent == 1 else {
        fputs("Opaque gap setting check failed\n", stderr)
        return false
    }
    print("Four-pane layout check passed: four visible, non-overlapping terminals")
    return true
}

@MainActor
func runSmokeTest() -> Bool {
    let defaults = UserDefaults.standard
    let previousSnapshot = defaults.data(forKey: "workspaceSnapshot")
    let previousTheme = defaults.string(forKey: "terminalTheme")
    let previousFocusLeft = defaults.object(forKey: "shortcut.focusLeft")
    let previousDrag = defaults.object(forKey: "dragEnabled")
    defaults.set(TerminalTheme.oceanBlue.rawValue, forKey: "terminalTheme")
    defer {
        defaults.set(previousSnapshot, forKey: "workspaceSnapshot")
        defaults.set(previousTheme, forKey: "terminalTheme")
        defaults.set(previousFocusLeft, forKey: "shortcut.focusLeft")
        defaults.set(previousDrag, forKey: "dragEnabled")
    }
    defaults.removeObject(forKey: "dragEnabled")
    let preferenceCheck = TileApp()
    guard !preferenceCheck.dragEnabled else { fputs("Dragging is on for a new installation\n", stderr); return false }
    defaults.set(true, forKey: "dragEnabled")
    guard preferenceCheck.dragEnabled else { fputs("Saved dragging-on preference was lost\n", stderr); return false }
    defaults.set(false, forKey: "dragEnabled")
    guard !preferenceCheck.dragEnabled else { fputs("Saved dragging-off preference was lost\n", stderr); return false }
    guard Shortcuts.normalized("cmd+cmd+n") == nil,
          TileAction.allCases.map(\.defaultShortcut).count == Set(TileAction.allCases.map(\.defaultShortcut)).count else {
        fputs("Shortcut validation or defaults conflict\n", stderr); return false
    }
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let disconnectedFrame = NSRect(x: 3000, y: 100, width: 1080, height: 720)
    guard TileWindow.reachableFrame(disconnectedFrame, screens: [screen]) == NSRect(x: 360, y: 100, width: 1080, height: 720),
          TileWindow.reachableFrame(NSRect(x: -100, y: -80, width: 700, height: 500), screens: [screen]).minX == 0,
          TileWindow.reachableFrame(NSRect(x: 1500, y: 100, width: 600, height: 500),
                                    screens: [screen, NSRect(x: 1440, y: 0, width: 1440, height: 900)]).minX == 1500 else {
        fputs("Disconnected display frame was not recovered\n", stderr); return false
    }
    defaults.set("cmd+ctrl+left", forKey: "shortcut.focusLeft")
    guard TileAction.focusLeft.shortcut == "option+left" else {
        fputs("Previously saved default pane navigation was not updated\n", stderr)
        return false
    }
    defaults.set("ctrl+option+left", forKey: "shortcut.focusLeft")
    guard TileAction.focusLeft.shortcut == "ctrl+option+left" else {
        fputs("Custom pane navigation was changed unexpectedly\n", stderr)
        return false
    }

    let app = TileApp()
    app.newWindow()
    let source = app.windows[0]
    defer {
        for window in Array(app.windows) {
            window.allowClose = true
            window.allSessions.forEach { $0.view.terminate() }
            window.window?.close()
        }
    }
    let closedSession = source.currentSession!
    closedSession.customTitle = "recent work"
    let originalDirectory = closedSession.directory
    source.close(closedSession)
    guard app.recentlyClosedPane?.customTitle == "recent work" else {
        fputs("Closed terminal metadata was not captured\n", stderr); return false
    }
    app.reopenClosedPane()
    guard let reopened = source.currentSession,
          reopened.id != closedSession.id,
          reopened.view.process.shellPid != closedSession.view.process.shellPid,
          reopened.customTitle == "recent work",
          reopened.directory == originalDirectory,
          reopened.view.process.running,
          !source.allSessions.contains(where: { $0 === closedSession }),
          app.recentlyClosedPane == nil else {
        fputs("Reopen did not create a fresh shell with saved pane details\n", stderr); return false
    }
    for _ in 0..<4 { app.addPane(to: source) }
    let recoveredWorkspaceID = source.workspace.id
    source.workspace.topRatio = 0.63
    let solePane = source.currentSession!
    source.close(solePane)
    app.reopenClosedPane()
    guard source.selectedWorkspace == 1,
          source.workspace.id == recoveredWorkspaceID,
          source.workspace.topRatio == 0.63,
          source.workspace.panes.count == 1 else {
        fputs("Reopening the last pane did not recover its workspace\n", stderr); return false
    }
    guard TileAction.focusLeft.defaultShortcut == "option+left",
          TileAction.focusRight.defaultShortcut == "option+right",
          TileAction.workspace1.defaultShortcut == "cmd+1",
          TileAction.workspace4.defaultShortcut == "cmd+4" else {
        fputs("Expected pane and workspace keyboard defaults are missing\n", stderr)
        return false
    }
    func workspaceButtonTitles() -> [String] {
        guard let root = source.window?.contentView,
              let tabs = viewDescendants(root).compactMap({ $0 as? NSStackView }).first(where: { $0.identifier?.rawValue == "tile.workspaceTabs" }) else { return [] }
        return tabs.arrangedSubviews.compactMap { ($0 as? NSButton)?.title }
    }
    guard workspaceButtonTitles() == ["1", "▸ 2"] else {
        fputs("Active workspace is not clear in the switcher\n", stderr)
        return false
    }
    source.selectWorkspace(0)
    guard workspaceButtonTitles() == ["▸ 1", "2"],
          source.window?.firstResponder === source.currentSession?.view else {
        fputs("Workspace switcher did not update or focus the selected workspace\n", stderr)
        return false
    }
    source.selectWorkspace(1)
    guard source.workspaces.count == 2,
          source.workspaces[0].panes.count == 4,
          source.workspaces[1].panes.count == 1,
          let session = source.currentSession else {
        fputs("Workspace overflow check failed\n", stderr)
        return false
    }
    let pid = session.view.process.shellPid
    guard pid > 0 else { fputs("Shell did not start\n", stderr); return false }
    let blue = session.view.nativeBackgroundColor.usingColorSpace(.deviceRGB)
    guard let blue, blue.blueComponent > blue.redComponent + 0.1 else {
        fputs("Blue terminal theme check failed\n", stderr)
        return false
    }
    defaults.set(TerminalTheme.classicDark.rawValue, forKey: "terminalTheme")
    session.applyTheme()
    let dark = session.view.nativeBackgroundColor.usingColorSpace(.deviceRGB)
    guard let dark, dark.blueComponent < 0.1 else {
        fputs("Terminal theme switching check failed\n", stderr)
        return false
    }
    defaults.set(TerminalTheme.oceanBlue.rawValue, forKey: "terminalTheme")
    session.applyTheme()
    guard !session.hasRunningCommand else { fputs("Idle shell was marked busy\n", stderr); return false }
    app.newWindow()
    let destination = app.windows[1]
    source.selectWorkspace(1)
    source.workspace.topRatio = 0.42
    destination.workspace.topRatio = 0.67
    let sourceWorkspaceIDs = source.workspaces.map(\.id)
    let destinationWorkspaceIDs = destination.workspaces.map(\.id)
    destination.window?.setFrame(NSRect(x: 3000, y: 100, width: 700, height: 500), display: true)
    app.displaysChanged()
    guard source.selectedWorkspace == 1,
          source.workspace.topRatio == 0.42,
          destination.selectedWorkspace == 0,
          destination.workspace.topRatio == 0.67,
          source.workspaces.map(\.id) == sourceWorkspaceIDs,
          destination.workspaces.map(\.id) == destinationWorkspaceIDs,
          let destinationFrame = destination.window?.frame,
          NSScreen.screens.contains(where: { $0.visibleFrame.contains(destinationFrame) }) else {
        fputs("Display reconciliation changed independent window state\n", stderr); return false
    }
    guard app.move(session.id, to: destination, before: nil),
          destination.allSessions.contains(where: { $0.id == session.id }),
          session.view.process.shellPid == pid,
          session.view.process.running else {
        fputs("Live session move check failed\n", stderr)
        return false
    }
    let command = Array("cd /private/tmp\n".utf8)
    session.view.process.send(data: command[...])
    var inheritedDirectory = false
    for _ in 0..<30 {
        Thread.sleep(forTimeInterval: 0.1)
        session.refreshDirectory()
        if session.directory == "/private/tmp" { inheritedDirectory = true; break }
    }
    guard inheritedDirectory else { fputs("Working directory check failed\n", stderr); return false }
    app.addPane(to: destination)
    guard destination.currentSession?.directory == "/private/tmp" else {
        fputs("New terminal did not inherit the directory\n", stderr)
        return false
    }
    let runningPane = destination.currentSession!
    let sleepCommand = Array("sleep 5\n".utf8)
    runningPane.view.process.send(data: sleepCommand[...])
    var detectedRunningCommand = false
    for _ in 0..<30 {
        Thread.sleep(forTimeInterval: 0.1)
        if runningPane.hasRunningCommand { detectedRunningCommand = true; break }
    }
    guard detectedRunningCommand else {
        fputs("Running command detection failed\n", stderr)
        return false
    }
    if let content = destination.window?.contentView,
       let runningView = viewDescendants(content).compactMap({ $0 as? PaneView }).first(where: { $0.session === runningPane }) {
        runningView.updateActivity()
        guard runningView.layer?.borderWidth == 2 else {
            fputs("Running command border check failed\n", stderr)
            return false
        }
    } else {
        fputs("Running pane view missing\n", stderr)
        return false
    }

    let topRight = destination.workspace.panes[1]
    destination.selectedPane = topRight.id
    destination.navigate(dx: 0, dy: 1, swap: false)
    guard destination.selectedPane == destination.workspace.panes[2].id else {
        fputs("Three-pane downward navigation failed\n", stderr)
        return false
    }
    destination.navigate(dx: 0, dy: -1, swap: false)
    guard destination.selectedPane == topRight.id else {
        fputs("Three-pane upward navigation failed\n", stderr)
        return false
    }

    let otherPane = destination.workspace.panes.first!
    let click = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10),
                                   modifierFlags: [], timestamp: 0,
                                   windowNumber: destination.window?.windowNumber ?? 0,
                                   context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    otherPane.view.mouseDown(with: click)
    guard destination.selectedPane == otherPane.id else {
        fputs("Terminal focus did not select the pane\n", stderr)
        return false
    }
    app.addPane(to: destination)
    app.addPane(to: destination)
    app.addPane(to: destination)
    destination.movePaneToNextWorkspace()
    destination.selectWorkspace(1)
    destination.movePaneToNextWorkspace()
    guard destination.selectedWorkspace == 1,
          destination.workspace.panes.contains(where: { $0.id == destination.selectedPane }) else {
        fputs("Moving the sole pane selected the wrong workspace\n", stderr)
        return false
    }

    app.saveWorkspace()
    runningPane.customTitle = "dev api"
    source.selectWorkspace(0)
    source.workspace.topRatio = 0.37
    app.saveWorkspace()
    let originalPIDs = Set(app.windows.flatMap(\.allSessions).map { $0.view.process.shellPid })
    let restored = TileApp()
    guard restored.restoreWorkspace() else { fputs("Workspace restore failed\n", stderr); return false }
    defer {
        for window in Array(restored.windows) {
            window.allowClose = true
            window.allSessions.forEach { $0.view.terminate() }
            window.window?.close()
        }
    }
    guard restored.windows.count == 2,
          restored.windows[0].selectedWorkspace == 0,
          abs(restored.windows[0].workspace.topRatio - 0.37) < 0.01,
          restored.windows[0].workspaces.map(\.id) == source.workspaces.map(\.id),
          restored.windows[1].allSessions.contains(where: { $0.customTitle == "dev api" }),
          restored.windows[1].allSessions.contains(where: { $0.directory == "/private/tmp" }),
          restored.windows[1].allSessions.allSatisfy({ $0.view.process.running }),
          restored.windows.flatMap(\.allSessions).allSatisfy({ !originalPIDs.contains($0.view.process.shellPid) }) else {
        fputs("Restored window or shell check failed\n", stderr)
        return false
    }
    print("Tile smoke test passed: overflow, live move, directory inheritance, focus, workspace movement, command detection, and restoration")
    return true
}
