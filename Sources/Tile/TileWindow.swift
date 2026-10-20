import AppKit

@MainActor
final class Workspace {
    let id: UUID
    var panes: [TerminalSession]
    init(id: UUID = UUID(), panes: [TerminalSession] = []) {
        self.id = id
        self.panes = panes
    }
}

@MainActor
final class PaneHeader: NSView, NSDraggingSource {
    weak var owner: TileApp?
    let session: TerminalSession
    private var startPoint: NSPoint?
    init(session: TerminalSession, owner: TileApp) {
        self.session = session
        self.owner = owner
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        owner?.select(session)
    }
    override func mouseDragged(with event: NSEvent) {
        guard owner?.dragEnabled == true, let startPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - startPoint.x, point.y - startPoint.y) > 5 else { return }
        self.startPoint = nil
        let pasteboard = NSPasteboardItem()
        pasteboard.setString(session.id.uuidString, forType: TileApp.panePasteboardType)
        let item = NSDraggingItem(pasteboardWriter: pasteboard)
        let image = NSImage(size: NSSize(width: 160, height: 30))
        image.lockFocus()
        NSColor.controlBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: 160, height: 30).fill()
        session.title.draw(at: NSPoint(x: 8, y: 7), withAttributes: [.foregroundColor: NSColor.labelColor])
        image.unlockFocus()
        item.setDraggingFrame(NSRect(x: point.x, y: point.y, width: 160, height: 30), contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard operation == [], let owner, let window = owner.window(containing: self.session) else { return }
        owner.detach(self.session, from: window, at: screenPoint)
    }
}

@MainActor
final class PaneView: NSView {
    let session: TerminalSession
    let header: PaneHeader
    private let title = NSTextField(labelWithString: "")
    private let close = NSButton(title: "×", target: nil, action: nil)
    var onClose: (() -> Void)?
    init(session: TerminalSession, owner: TileApp) {
        self.session = session
        header = PaneHeader(session: session, owner: owner)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        title.stringValue = session.title
        title.lineBreakMode = .byTruncatingTail
        close.bezelStyle = .inline
        close.target = self
        close.action = #selector(closePane)
        addSubview(header)
        header.addSubview(title)
        header.addSubview(close)
        addSubview(session.view)
        session.onChange = { [weak self] in self?.title.stringValue = session.title }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func layout() {
        super.layout()
        let headerHeight: CGFloat = 28
        header.frame = NSRect(x: 0, y: bounds.height - headerHeight, width: bounds.width, height: headerHeight)
        title.isHidden = UserDefaults.standard.object(forKey: "showPaneTitles") as? Bool == false
        title.frame = NSRect(x: 8, y: 4, width: max(0, bounds.width - 48), height: 20)
        close.frame = NSRect(x: max(0, bounds.width - 30), y: 3, width: 26, height: 22)
        session.view.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - headerHeight))
    }
    @objc private func closePane() { onClose?() }
}

@MainActor
final class DropSurface: NSView {
    weak var owner: TileWindow?
    var target: TerminalSession?
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([TileApp.panePasteboardType])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        owner?.app?.dragEnabled == true ? .move : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let id = sender.draggingPasteboard.string(forType: TileApp.panePasteboardType),
              let uuid = UUID(uuidString: id), let owner, let app = owner.app else { return false }
        return app.move(uuid, to: owner, before: target)
    }
}

@MainActor
final class TileWindow: NSWindowController, NSWindowDelegate {
    let id: UUID
    weak var app: TileApp?
    var workspaces: [Workspace]
    var selectedWorkspace = 0
    var selectedPane: UUID?
    var focused = false
    var allowClose = false
    private let root = NSView()
    private let toolbar = NSStackView()
    private let tabs = NSStackView()
    private let content = DropSurface(frame: .zero)
    private let plus = NSButton(title: "+", target: nil, action: nil)
    private let focus = NSButton(title: "Focus", target: nil, action: nil)
    private let settings = NSButton(title: "⚙", target: nil, action: nil)

    init(id: UUID = UUID(), workspaces: [Workspace], owner: TileApp) {
        self.id = id
        self.workspaces = workspaces.isEmpty ? [Workspace()] : workspaces
        self.app = owner
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Tile"
        window.minSize = NSSize(width: 500, height: 320)
        super.init(window: window)
        window.delegate = self
        window.contentView = root
        content.owner = self
        root.addSubview(toolbar)
        root.addSubview(content)
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        tabs.orientation = .horizontal
        tabs.spacing = 3
        toolbar.addArrangedSubview(tabs)
        for (button, action) in [(plus, #selector(addPane)), (focus, #selector(toggleFocus)), (settings, #selector(openSettings))] {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
            toolbar.addArrangedSubview(button)
        }
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            toolbar.heightAnchor.constraint(equalToConstant: 30),
            content.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        render()
        showWindow(nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    var workspace: Workspace { workspaces[selectedWorkspace] }
    var allSessions: [TerminalSession] { workspaces.flatMap(\.panes) }
    var currentSession: TerminalSession? { workspace.panes.first { $0.id == selectedPane } ?? workspace.panes.first }

    func add(_ session: TerminalSession) {
        if workspace.panes.count == 4 {
            workspaces.append(Workspace(panes: [session]))
            selectedWorkspace = workspaces.count - 1
        } else { workspace.panes.append(session) }
        selectedPane = session.id
        focused = false
        render()
        window?.makeFirstResponder(session.view)
    }
    func remove(_ session: TerminalSession, terminate: Bool = false) {
        for workspace in workspaces { workspace.panes.removeAll { $0.id == session.id } }
        if terminate { session.view.terminate() }
        workspaces.removeAll { $0.panes.isEmpty }
        if workspaces.isEmpty { workspaces = [Workspace()] }
        selectedWorkspace = min(selectedWorkspace, workspaces.count - 1)
        selectedPane = workspace.panes.first?.id
        focused = false
        render()
    }
    func render() {
        guard window != nil else { return }
        tabs.arrangedSubviews.forEach { tabs.removeArrangedSubview($0); $0.removeFromSuperview() }
        for index in workspaces.indices {
            let button = NSButton(title: "\(index + 1)", target: self, action: #selector(selectTab(_:)))
            button.tag = index
            button.bezelStyle = .rounded
            button.state = index == selectedWorkspace ? .on : .off
            tabs.addArrangedSubview(button)
        }
        content.subviews.forEach { $0.removeFromSuperview() }
        let sessions = focused ? workspace.panes.filter { $0.id == selectedPane } : workspace.panes
        let panes = sessions.map { session -> DropSurface in
            let drop = DropSurface(frame: .zero)
            drop.owner = self
            drop.target = session
            let pane = PaneView(session: session, owner: app!)
            pane.onClose = { [weak self] in self?.close(session) }
            drop.addSubview(pane)
            pane.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                pane.leadingAnchor.constraint(equalTo: drop.leadingAnchor), pane.trailingAnchor.constraint(equalTo: drop.trailingAnchor),
                pane.topAnchor.constraint(equalTo: drop.topAnchor), pane.bottomAnchor.constraint(equalTo: drop.bottomAnchor)
            ])
            return drop
        }
        guard !panes.isEmpty else { return }
        let body: NSView
        if panes.count <= 2 { body = split(panes, vertical: true, name: "\(id)-\(workspace.id)-top") }
        else {
            let top = split(Array(panes.prefix(2)), vertical: true, name: "\(id)-\(workspace.id)-top")
            let bottom = split(Array(panes.dropFirst(2)), vertical: true, name: "\(id)-\(workspace.id)-bottom")
            body = split([top, bottom], vertical: false, name: "\(id)-\(workspace.id)-rows")
        }
        content.addSubview(body)
        body.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor), body.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            body.topAnchor.constraint(equalTo: content.topAnchor), body.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        window?.title = "Tile — Workspace \(selectedWorkspace + 1)"
    }
    private func split(_ views: [NSView], vertical: Bool, name: String) -> NSView {
        guard views.count > 1 else { return views[0] }
        let split = NSSplitView()
        split.isVertical = vertical
        split.dividerStyle = .thin
        split.autosaveName = name
        views.forEach(split.addSubview)
        return split
    }
    func close(_ session: TerminalSession) {
        guard app?.confirmClose([session]) == true else { return }
        remove(session, terminate: true)
        app?.saveWorkspace()
    }
    func selectWorkspace(_ index: Int) {
        guard workspaces.indices.contains(index) else { return }
        selectedWorkspace = index
        selectedPane = workspace.panes.first?.id
        focused = false
        render()
        app?.saveWorkspace()
    }
    func escapeFocus() -> Bool {
        guard focused else { return false }
        focused = false
        render()
        return true
    }
    func navigate(dx: Int, dy: Int, swap: Bool) {
        guard let current = workspace.panes.firstIndex(where: { $0.id == selectedPane }) else { return }
        let column = current % 2
        let row = current / 2
        let nextColumn = column + dx
        let nextRow = row + dy
        guard (0...1).contains(nextColumn), (0...1).contains(nextRow) else { return }
        let next = nextRow * 2 + nextColumn
        guard next < workspace.panes.count else { return }
        if swap { workspace.panes.swapAt(current, next); render() }
        selectedPane = workspace.panes[next].id
        window?.makeFirstResponder(workspace.panes[next].view)
    }
    func movePaneToNextWorkspace() {
        guard let session = currentSession else { return }
        let old = workspace
        let next = selectedWorkspace + 1
        if next >= workspaces.count || workspaces[next].panes.count == 4 { workspaces.insert(Workspace(), at: next) }
        old.panes.removeAll { $0.id == session.id }
        workspaces[next].panes.append(session)
        if old.panes.isEmpty { workspaces.removeAll { $0 === old }; selectedWorkspace = min(next - 1, workspaces.count - 1) }
        else { selectedWorkspace = next }
        selectedPane = session.id
        render()
        app?.saveWorkspace()
    }
    @objc private func addPane() { app?.addPane(to: self) }
    @objc func toggleFocus() {
        if selectedPane == nil { selectedPane = workspace.panes.first?.id }
        focused.toggle()
        render()
    }
    @objc private func openSettings() { app?.showSettings() }
    @objc private func selectTab(_ sender: NSButton) { selectWorkspace(sender.tag) }
    func windowDidBecomeKey(_ notification: Notification) { app?.lastWindow = self }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard allowClose || app?.confirmClose(allSessions) == true else { return false }
        allSessions.forEach { $0.view.terminate() }
        allowClose = true
        return true
    }
    func windowWillClose(_ notification: Notification) { app?.removeWindow(self) }
}
