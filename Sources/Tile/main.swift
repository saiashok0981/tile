import AppKit
import UserNotifications

@MainActor
final class TileApp: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    struct ClosedPane {
        let directory: String
        let customTitle: String?
        let windowID: UUID
        let workspaceID: UUID
        let workspaceIndex: Int
        let paneIndex: Int
        let topRatio: CGFloat
        let bottomRatio: CGFloat
        let rowRatio: CGFloat
    }
    static let panePasteboardType = NSPasteboard.PasteboardType("dev.tile.terminal-pane")
    var windows: [TileWindow] = []
    weak var lastWindow: TileWindow?
    var recentlyClosedPane: ClosedPane?
    var dragEnabled: Bool { UserDefaults.standard.bool(forKey: "dragEnabled") }
    private var keyMonitor: Any?
    private var settingsWindow: SettingsWindow?
    private var managedCodexSessions: [UUID: ManagedCodexSession] = [:]
    private let agentBridge = AgentBridge()
    lazy var agentMonitor = AgentMonitor(ledgerURL: AgentMonitor.defaultLedgerURL) { [weak self] token in
        self?.windows.flatMap(\.allSessions).first { $0.agentToken == token }
    }
    private let hotKey = GlobalHotKey()
    private var isTerminating = false
    var isRestoringWorkspace = false
    private var pendingLayoutSave: DispatchWorkItem?
    private var previousAgentLocation: (window: UUID, workspace: UUID, pane: UUID)?
    private var lastAgentAttention: UUID?
    func scheduleLayoutSave() {
        guard !isRestoringWorkspace else { return }
        pendingLayoutSave?.cancel()
        let save = DispatchWorkItem { [weak self] in self?.saveWorkspace() }
        pendingLayoutSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: save)
    }
    private var desktopFullScreenWindowIDs: Set<UUID> = []
    private var previousPresentationOptions: NSApplication.PresentationOptions?

    func applicationDidFinishLaunching(_ notification: Notification) {
        agentBridge.onEvent = { [weak self] event in self?.agentMonitor.ingest(event) }
        agentMonitor.onChange = { [weak self] in self?.windows.forEach { $0.refreshAgentUI() } }
        agentMonitor.onNewAttention = { [weak self] item in self?.notifyAboutAgent(item) }
        agentMonitor.onRoutineStart = { [weak self] item in self?.notifyAboutAgent(item) }
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().delegate = self
        }
        agentBridge.start()
        if !restoreWorkspace() { newWindow() }
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.settingsWindow?.window?.isKeyWindow == true { return event }
            if event.keyCode == 53 {
                if self.activeWindow?.escapeFocus() == true { return nil }
                if self.activeWindow?.escapeDesktopFullScreen() == true { return nil }
            }
            if self.handleShortcut(event) { return nil }
            return event
        }
        buildMenu()
        hotKey.onPress = { [weak self] in self?.raiseWindow() }
        _ = hotKey.register(TileAction.raiseWindow.shortcut)
        NSApp.activate(ignoringOtherApps: true)
    }
    var activeWindow: TileWindow? { windows.first { $0.window?.isKeyWindow == true } ?? lastWindow ?? windows.first }
    func window(containing session: TerminalSession) -> TileWindow? {
        windows.first { $0.allSessions.contains { $0.id == session.id } }
    }
    func newWindow(session: TerminalSession? = nil, at point: NSPoint? = nil) {
        let shell = session ?? TerminalSession(directory: FileManager.default.homeDirectoryForCurrentUser.path)
        let controller = TileWindow(workspaces: [Workspace(panes: [shell])], owner: self)
        windows.append(controller)
        lastWindow = controller
        if let point { controller.window?.setFrameOrigin(point) }
        controller.window?.makeKeyAndOrderFront(nil)
        saveWorkspace()
    }
    func addPane(to window: TileWindow) {
        window.currentSession?.refreshDirectory()
        let directory = window.currentSession?.directory ?? FileManager.default.homeDirectoryForCurrentUser.path
        window.add(TerminalSession(directory: directory))
        saveWorkspace()
    }
    func reopenClosedPane() {
        guard let closed = recentlyClosedPane else { return }
        let session = TerminalSession(directory: closed.directory)
        session.customTitle = closed.customTitle
        if let destination = windows.first(where: { $0.id == closed.windowID }) ?? activeWindow {
            destination.reopen(session, from: closed)
            destination.window?.makeKeyAndOrderFront(nil)
        } else {
            newWindow(session: session)
        }
        recentlyClosedPane = nil
        saveWorkspace()
    }
    func select(_ session: TerminalSession) {
        guard let window = window(containing: session) else { return }
        if let index = window.workspaces.firstIndex(where: { $0.panes.contains { $0.id == session.id } }),
           index != window.selectedWorkspace { window.selectWorkspace(index) }
        window.selectedPane = session.id
        window.window?.makeKeyAndOrderFront(nil)
        window.focusTerminal(session)
    }
    func detach(_ session: TerminalSession, from source: TileWindow, at point: NSPoint) {
        source.remove(session)
        newWindow(session: session, at: point)
        saveWorkspace()
    }
    func move(_ id: UUID, to destination: TileWindow, before target: TerminalSession?) -> Bool {
        guard let source = windows.first(where: { $0.allSessions.contains(where: { $0.id == id }) }),
              let session = source.allSessions.first(where: { $0.id == id }) else { return false }
        if source === destination, let target,
           let from = destination.workspace.panes.firstIndex(where: { $0.id == id }),
           let to = destination.workspace.panes.firstIndex(where: { $0.id == target.id }) {
            destination.workspace.panes.swapAt(from, to)
            destination.render()
            saveWorkspace()
            return true
        }
        source.remove(session)
        destination.add(session, before: target)
        saveWorkspace()
        return true
    }
    func removeWindow(_ window: TileWindow) {
        window.allSessions.forEach { agentMonitor.remove(paneID: $0.id) }
        windows.removeAll { $0 === window }
        if lastWindow === window { lastWindow = windows.last }
        if !isTerminating { saveWorkspace() }
    }
    func agentDidExit(_ session: TerminalSession) {
        managedCodexSessions.removeValue(forKey: session.id)?.close()
        agentMonitor.remove(paneID: session.id)
    }
    func showManagedCodex(for session: TerminalSession) {
        if let existing = managedCodexSessions[session.id] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let managed = ManagedCodexSession(pane: session, app: self)
        managed.onClose = { [weak self] in self?.managedCodexSessions.removeValue(forKey: session.id) }
        managedCodexSessions[session.id] = managed
    }
    func nextAgentNeedingAttention(in window: TileWindow) {
        let items = agentMonitor.attention(in: window.workspace.panes)
        guard !items.isEmpty else { return }
        if previousAgentLocation == nil, let current = window.currentSession {
            previousAgentLocation = (window.id, window.workspace.id, current.id)
        }
        let nextIndex: Int
        if let last = lastAgentAttention, let index = items.firstIndex(where: { $0.paneID == last }) {
            nextIndex = (index + 1) % items.count
        } else { nextIndex = 0 }
        let paneID = items[nextIndex].paneID
        lastAgentAttention = paneID
        if let session = window.workspace.panes.first(where: { $0.id == paneID }) { select(session) }
    }
    func returnToPreviousPane() {
        guard let previousAgentLocation,
              let session = windows.flatMap(\.allSessions).first(where: { $0.id == previousAgentLocation.pane }) else {
            self.previousAgentLocation = nil
            lastAgentAttention = nil
            return
        }
        self.previousAgentLocation = nil
        lastAgentAttention = nil
        select(session)
    }
    private func notifyAboutAgent(_ item: AgentSnapshot) {
        let key: String
        switch item.phase {
        case .running: key = "notifyAgentActivity"
        case .approvalRequired: key = "notifyAgentApproval"
        case .questionRequired: key = "notifyAgentQuestion"
        case .failed: key = "notifyAgentFailure"
        case .completedNeedsReview: key = "notifyAgentCompletion"
        default: return
        }
        guard Bundle.main.bundleURL.pathExtension == "app",
              UserDefaults.standard.bool(forKey: key), !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(item.provider.rawValue): \(item.phase.label)"
        content.body = "Open the Tile terminal to review this agent."
        if item.phase == .running || item.phase == .completedNeedsReview { content.interruptionLevel = .passive }
        content.userInfo = ["paneID": item.paneID.uuidString]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let pane = response.notification.request.content.userInfo["paneID"] as? String
        Task { @MainActor [weak self] in
            if let pane, let id = UUID(uuidString: pane),
               let session = self?.windows.flatMap(\.allSessions).first(where: { $0.id == id }) {
                NSApp.activate(ignoringOtherApps: true)
                self?.select(session)
            }
        }
        completionHandler()
    }
    @objc func displaysChanged() {
        windows.forEach { $0.keepOnAvailableScreen() }
        saveWorkspace()
    }
    func setDesktopFullScreen(_ active: Bool, for id: UUID) {
        if active {
            if desktopFullScreenWindowIDs.isEmpty { previousPresentationOptions = NSApp.presentationOptions }
            desktopFullScreenWindowIDs.insert(id)
            NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
        } else {
            desktopFullScreenWindowIDs.remove(id)
            if desktopFullScreenWindowIDs.isEmpty, let previousPresentationOptions {
                NSApp.presentationOptions = previousPresentationOptions
                self.previousPresentationOptions = nil
            }
        }
    }
    func confirmClose(_ sessions: [TerminalSession]) -> Bool {
        guard sessions.contains(where: \.hasRunningCommand) else { return true }
        let alert = NSAlert()
        alert.messageText = "A command is still running"
        alert.informativeText = "Closing will terminate the running command. Close anyway?"
        alert.addButton(withTitle: "Keep Open")
        alert.addButton(withTitle: "Close")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard confirmClose(windows.flatMap(\.allSessions)) else { return .terminateCancel }
        saveWorkspace()
        isTerminating = true
        windows.forEach { $0.allowClose = true; $0.allSessions.forEach { $0.view.terminate() } }
        return .terminateNow
    }
    func showSettings() {
        let settings = SettingsWindow()
        settings.onCornerPreview = { [weak self] radius in
            self?.windows.forEach { $0.updateCornerRadius(radius) }
        }
        settings.onSave = { [weak self] in
            guard let self else { return }
            let size = UserDefaults.standard.object(forKey: "fontSize") as? Int ?? 13
            self.windows.flatMap(\.allSessions).forEach {
                $0.view.font = NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
                $0.applyTheme()
            }
            self.windows.forEach { $0.render() }
            _ = self.hotKey.register(TileAction.raiseWindow.shortcut)
        }
        settingsWindow = settings
        settings.showWindow(nil)
        settings.window?.makeKeyAndOrderFront(nil)
    }
    private func raiseWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if windows.isEmpty { newWindow() }
        (lastWindow ?? windows.first)?.window?.makeKeyAndOrderFront(nil)
    }
    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard NSApp.modalWindow == nil,
              let keyWindow = NSApp.keyWindow,
              let window = windows.first(where: { $0.window === keyWindow }),
              let shortcut = Shortcuts.from(event) else { return false }
        guard let action = TileAction.allCases.first(where: { $0.shortcut == shortcut }) else { return false }
        let directionalActions: Set<TileAction> = [.focusLeft, .focusRight, .focusUp, .focusDown,
                                                    .swapLeft, .swapRight, .swapUp, .swapDown]
        if directionalActions.contains(action) && !(keyWindow.firstResponder is SelectableTerminalView) { return false }
        switch action {
        case .newPane: addPane(to: window)
        case .newWindow: newWindow()
        case .focusPane: window.toggleFocus()
        case .focusSelectedTerminal: window.focusTerminal(window.currentSession)
        case .renamePane: if let session = window.currentSession { window.rename(session) }
        case .closePane: if let session = window.currentSession { window.close(session) }
        case .reopenPane: reopenClosedPane()
        case .toggleFullScreen: window.toggleDesktopFullScreen()
        case .nextWorkspace: window.selectWorkspace(window.selectedWorkspace + 1)
        case .previousWorkspace: window.selectWorkspace(window.selectedWorkspace - 1)
        case .focusLeft: window.navigate(dx: -1, dy: 0, swap: false)
        case .focusRight: window.navigate(dx: 1, dy: 0, swap: false)
        case .focusUp: window.navigate(dx: 0, dy: -1, swap: false)
        case .focusDown: window.navigate(dx: 0, dy: 1, swap: false)
        case .swapLeft: window.navigate(dx: -1, dy: 0, swap: true)
        case .swapRight: window.navigate(dx: 1, dy: 0, swap: true)
        case .swapUp: window.navigate(dx: 0, dy: -1, swap: true)
        case .swapDown: window.navigate(dx: 0, dy: 1, swap: true)
        case .moveToNextWorkspace: window.movePaneToNextWorkspace()
        case .raiseWindow: window.window?.makeKeyAndOrderFront(nil)
        case .nextAgentAttention: nextAgentNeedingAttention(in: window)
        case .returnToPreviousPane: returnToPreviousPane()
        case .workspace1: window.selectWorkspace(0)
        case .workspace2: window.selectWorkspace(1)
        case .workspace3: window.selectWorkspace(2)
        case .workspace4: window.selectWorkspace(3)
        case .workspace5: window.selectWorkspace(4)
        case .workspace6: window.selectWorkspace(5)
        case .workspace7: window.selectWorkspace(6)
        case .workspace8: window.selectWorkspace(7)
        case .workspace9: window.selectWorkspace(8)
        }
        return true
    }
    private func buildMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Tile", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        bar.addItem(appItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Terminal", action: #selector(menuNewPane), keyEquivalent: "").target = self
        fileMenu.addItem(withTitle: "New Window", action: #selector(menuNewWindow), keyEquivalent: "").target = self
        fileMenu.addItem(withTitle: "Reopen Closed Terminal", action: #selector(menuReopenClosedPane), keyEquivalent: "").target = self
        fileMenu.addItem(withTitle: "Focus Selected Terminal", action: #selector(menuFocusSelectedTerminal), keyEquivalent: "").target = self
        fileMenu.addItem(withTitle: "Rename Selected Terminal", action: #selector(menuRenamePane), keyEquivalent: "").target = self
        fileMenu.addItem(withTitle: "Close Selected Terminal", action: #selector(menuClosePane), keyEquivalent: "").target = self
        fileMenu.addItem(withTitle: "Focus Pane", action: #selector(menuFocus), keyEquivalent: "").target = self
        fileItem.submenu = fileMenu
        bar.addItem(fileItem)
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let fullScreenItem = NSMenuItem(title: "Toggle Full Screen", action: #selector(menuToggleFullScreen), keyEquivalent: "")
        fullScreenItem.target = self
        viewMenu.addItem(fullScreenItem)
        viewItem.submenu = viewMenu
        bar.addItem(viewItem)
        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Keyboard Shortcuts…", action: #selector(menuShortcutReference), keyEquivalent: "").target = self
        helpItem.submenu = helpMenu
        bar.addItem(helpItem)
        NSApp.mainMenu = bar
    }
    @objc private func menuNewPane() { if let window = activeWindow { addPane(to: window) } else { newWindow() } }
    @objc private func menuNewWindow() { newWindow() }
    @objc private func menuReopenClosedPane() { reopenClosedPane() }
    @objc private func menuFocusSelectedTerminal() { if let window = activeWindow { window.focusTerminal(window.currentSession) } }
    @objc private func menuRenamePane() { if let session = activeWindow?.currentSession { activeWindow?.rename(session) } }
    @objc private func menuClosePane() { if let session = activeWindow?.currentSession { activeWindow?.close(session) } }
    @objc private func menuFocus() { activeWindow?.toggleFocus() }
    @objc private func menuToggleFullScreen() { activeWindow?.toggleDesktopFullScreen() }
    @objc private func menuShortcutReference() {
        let alert = NSAlert()
        alert.messageText = "Keyboard shortcuts"
        alert.informativeText = TileAction.allCases.map { "\($0.title): \($0.shortcut)" }.joined(separator: "\n")
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Settings…")
        if alert.runModal() == .alertSecondButtonReturn { showSettings() }
    }
}

if let statusIndex = CommandLine.arguments.firstIndex(of: "--agent-statusline") {
    let encoded = CommandLine.arguments.dropFirst(statusIndex + 1).first ?? ""
    let original = Data(base64Encoded: encoded).flatMap { String(data: $0, encoding: .utf8) }
    AgentHook.runClaudeStatusLine(originalCommand: original)
    exit(0)
}
if let hookIndex = CommandLine.arguments.firstIndex(of: "--agent-hook") {
    AgentHook.run(arguments: Array(CommandLine.arguments.dropFirst(hookIndex + 1)))
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.applicationIconImage = TileBrand.appIcon
if CommandLine.arguments.contains("--smoke-test") {
    exit(runSmokeTest() ? 0 : 1)
} else if CommandLine.arguments.contains("--agent-test") {
    exit(runAgentWorkflowTest() ? 0 : 1)
} else if CommandLine.arguments.contains("--managed-codex-test") {
    exit(runManagedCodexProtocolTest() ? 0 : 1)
} else if CommandLine.arguments.contains("--layout-test") {
    exit(runFourPaneLayoutTest() ? 0 : 1)
} else if CommandLine.arguments.contains("--focus-test") {
    exit(runInputFocusTest() ? 0 : 1)
} else if CommandLine.arguments.contains("--keyboard-test") {
    exit(runKeyboardWorkflowTest() ? 0 : 1)
} else {
    let delegate = TileApp()
    app.delegate = delegate
    app.run()
}
