import AppKit

@MainActor
final class TileApp: NSObject, NSApplicationDelegate {
    static let panePasteboardType = NSPasteboard.PasteboardType("dev.tile.terminal-pane")
    var windows: [TileWindow] = []
    weak var lastWindow: TileWindow?
    var dragEnabled: Bool { UserDefaults.standard.object(forKey: "dragEnabled") as? Bool ?? true }
    private var keyMonitor: Any?
    private var settingsWindow: SettingsWindow?
    private let hotKey = GlobalHotKey()
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !restoreWorkspace() { newWindow() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.settingsWindow?.window?.isKeyWindow == true { return event }
            if event.keyCode == 53, self.activeWindow?.escapeFocus() == true { return nil }
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
    func select(_ session: TerminalSession) {
        guard let window = window(containing: session) else { return }
        window.selectedPane = session.id
        window.window?.makeKeyAndOrderFront(nil)
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
        windows.removeAll { $0 === window }
        if lastWindow === window { lastWindow = windows.last }
        if !isTerminating { saveWorkspace() }
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
        guard let shortcut = Shortcuts.from(event), let window = activeWindow else { return false }
        guard let action = TileAction.allCases.first(where: { $0.shortcut == shortcut }) else { return false }
        switch action {
        case .newPane: addPane(to: window)
        case .focusPane: window.toggleFocus()
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
        fileMenu.addItem(withTitle: "Focus Pane", action: #selector(menuFocus), keyEquivalent: "").target = self
        fileItem.submenu = fileMenu
        bar.addItem(fileItem)
        NSApp.mainMenu = bar
    }
    @objc private func menuNewPane() { if let window = activeWindow { addPane(to: window) } else { newWindow() } }
    @objc private func menuNewWindow() { newWindow() }
    @objc private func menuFocus() { activeWindow?.toggleFocus() }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
if CommandLine.arguments.contains("--smoke-test") {
    exit(runSmokeTest() ? 0 : 1)
} else if CommandLine.arguments.contains("--layout-test") {
    exit(runFourPaneLayoutTest() ? 0 : 1)
} else {
    let delegate = TileApp()
    app.delegate = delegate
    app.run()
}
