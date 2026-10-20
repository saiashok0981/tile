import AppKit

@MainActor
final class TileRootView: NSView {
    weak var contentSurface: NSView?

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    func interiorGapRects() -> [NSRect] {
        guard let contentSurface else { return [] }
        func panes(in view: NSView) -> [PaneView] {
            view.subviews.flatMap { child in
                (child as? PaneView).map { [$0] } ?? panes(in: child)
            }
        }
        let frames = panes(in: contentSurface).map { $0.convert($0.bounds, to: self) }
        guard frames.count > 1 else { return [] }
        func verticalGap(_ left: NSRect, _ right: NSRect) -> NSRect {
            NSRect(x: left.maxX, y: max(left.minY, right.minY),
                   width: max(0, right.minX - left.maxX),
                   height: max(0, min(left.maxY, right.maxY) - max(left.minY, right.minY)))
        }
        if frames.count == 2 { return [verticalGap(frames[0], frames[1])] }
        let top = Array(frames.prefix(2))
        let bottom = Array(frames.dropFirst(2))
        let horizontal = NSRect(x: frames.map(\.minX).min() ?? 0,
                                y: bottom.map(\.maxY).max() ?? 0,
                                width: (frames.map(\.maxX).max() ?? 0) - (frames.map(\.minX).min() ?? 0),
                                height: max(0, (top.map(\.minY).min() ?? 0) - (bottom.map(\.maxY).max() ?? 0)))
        var gaps = [verticalGap(top[0], top[1]), horizontal]
        if bottom.count == 2 { gaps.append(verticalGap(bottom[0], bottom[1])) }
        return gaps.filter { !$0.isEmpty }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        let background = NSBezierPath(rect: bounds)
        if PaneLayout.transparentGaps {
            for gap in interiorGapRects() { background.appendRect(gap) }
            background.windingRule = .evenOdd
        }
        background.fill()
    }
}

enum TileClock {
    static func label(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "EEEE dd/MM/yyyy HH:mm"
        return formatter.string(from: date)
    }
}

@MainActor
final class Workspace {
    let id: UUID
    var panes: [TerminalSession]
    var lastTopColumn = 0
    var topRatio: CGFloat = 0.5
    var bottomRatio: CGFloat = 0.5
    var rowRatio: CGFloat = 0.5
    init(id: UUID = UUID(), panes: [TerminalSession] = []) {
        self.id = id
        self.panes = panes
    }
}

@MainActor
final class RatioSplitView: NSSplitView, NSSplitViewDelegate {
    var ratio: CGFloat = 0.5
    var onRatioChange: ((CGFloat) -> Void)?
    private var initialized = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func drawDivider(in rect: NSRect) {
        if !PaneLayout.transparentGaps { super.drawDivider(in: rect) }
    }

    override func layout() {
        super.layout()
        let length = isVertical ? bounds.width : bounds.height
        guard !initialized, subviews.count == 2, length > dividerThickness else { return }
        initialized = true
        setPosition((length - dividerThickness) * ratio, ofDividerAt: 0)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard initialized, subviews.count == 2 else { return }
        let length = (isVertical ? bounds.width : bounds.height) - dividerThickness
        guard length > 0 else { return }
        let first = isVertical ? subviews[0].frame.width : subviews[0].frame.height
        ratio = min(max(first / length, 0.1), 0.9)
        onRatioChange?(ratio)
    }
}

@MainActor
final class PaneHeader: NSView, NSDraggingSource {
    weak var owner: TileApp?
    let session: TerminalSession
    var onRename: (() -> Void)?
    private var startPoint: NSPoint?
    init(session: TerminalSession, owner: TileApp) {
        self.session = session
        self.owner = owner
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = TerminalTheme.current.header.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onRename?(); return }
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
        TerminalTheme.current.header.setFill()
        NSRect(x: 0, y: 0, width: 160, height: 30).fill()
        session.displayTitle.draw(at: NSPoint(x: 8, y: 7), withAttributes: [.foregroundColor: TerminalTheme.current.foreground])
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
    private let renameButton = NSButton(title: "✎", target: nil, action: nil)
    private let close = NSButton(title: "×", target: nil, action: nil)
    private var activityTimer: Timer?
    var onClose: (() -> Void)?
    var onRename: (() -> Void)?
    init(session: TerminalSession, owner: TileApp) {
        self.session = session
        header = PaneHeader(session: session, owner: owner)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = TerminalTheme.current.background.cgColor
        title.stringValue = session.displayTitle
        title.textColor = TerminalTheme.current.foreground
        title.lineBreakMode = .byTruncatingTail
        close.bezelStyle = .inline
        close.contentTintColor = TerminalTheme.current.foreground
        renameButton.bezelStyle = .inline
        renameButton.contentTintColor = TerminalTheme.current.foreground
        renameButton.target = self
        renameButton.action = #selector(renamePane)
        renameButton.toolTip = "Rename terminal"
        close.target = self
        close.action = #selector(closePane)
        addSubview(header)
        header.onRename = { [weak self] in self?.onRename?() }
        header.addSubview(title)
        header.addSubview(renameButton)
        header.addSubview(close)
        addSubview(session.view)
        session.onChange = { [weak self] in self?.title.stringValue = session.displayTitle }
        updateActivity()
        activityTimer = Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(refreshActivity), userInfo: nil, repeats: true)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil { activityTimer?.invalidate(); activityTimer = nil }
    }
    override func layout() {
        super.layout()
        let headerHeight: CGFloat = 28
        header.frame = NSRect(x: 0, y: bounds.height - headerHeight, width: bounds.width, height: headerHeight)
        title.isHidden = UserDefaults.standard.object(forKey: "showPaneTitles") as? Bool == false
        title.frame = NSRect(x: 8, y: 4, width: max(0, bounds.width - 78), height: 20)
        renameButton.frame = NSRect(x: max(0, bounds.width - 60), y: 3, width: 26, height: 22)
        close.frame = NSRect(x: max(0, bounds.width - 30), y: 3, width: 26, height: 22)
        session.view.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - headerHeight))
    }
    @objc private func closePane() { onClose?() }
    @objc private func renamePane() { onRename?() }
    @objc private func refreshActivity() { updateActivity() }
    func updateActivity() {
        let running = session.hasRunningCommand
        layer?.borderWidth = running ? 2 : 0
        layer?.borderColor = running ? NSColor.systemGreen.cgColor : nil
    }
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
    private let root = TileRootView()
    private let toolbar = NSStackView()
    private let tabs = NSStackView()
    private let toolbarSpacer = NSView()
    private let clockLabel = NSTextField(labelWithString: "")
    private var clockTimer: Timer?
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
        root.wantsLayer = true
        toolbar.wantsLayer = true
        content.wantsLayer = true
        content.owner = self
        root.contentSurface = content
        root.addSubview(toolbar)
        root.addSubview(content)
        toolbar.orientation = .horizontal
        toolbar.distribution = .fill
        toolbar.spacing = 8
        tabs.orientation = .horizontal
        tabs.spacing = 3
        toolbar.addArrangedSubview(tabs)
        toolbarSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolbar.addArrangedSubview(toolbarSpacer)
        clockLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        clockLabel.alignment = .right
        clockLabel.identifier = NSUserInterfaceItemIdentifier("tile.clock")
        clockLabel.setContentHuggingPriority(.required, for: .horizontal)
        toolbar.addArrangedSubview(clockLabel)
        updateClock()
        clockTimer = Timer.scheduledTimer(timeInterval: 15, target: self, selector: #selector(updateClock), userInfo: nil, repeats: true)
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

    func add(_ session: TerminalSession, before target: TerminalSession? = nil) {
        if workspace.panes.count == 4 {
            workspaces.append(Workspace(panes: [session]))
            selectedWorkspace = workspaces.count - 1
        } else if let target, let index = workspace.panes.firstIndex(where: { $0.id == target.id }) {
            workspace.panes.insert(session, at: index)
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
        applyGapAppearance()
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
        guard let app else { return }
        let panes = sessions.map { session -> DropSurface in
            let drop = DropSurface(frame: .zero)
            drop.owner = self
            drop.target = session
            session.view.onSelect = { [weak app, weak session] in
                guard let session else { return }
                app?.select(session)
            }
            let pane = PaneView(session: session, owner: app)
            pane.onClose = { [weak self] in self?.close(session) }
            pane.onRename = { [weak self] in self?.rename(session) }
            drop.addSubview(pane)
            pane.translatesAutoresizingMaskIntoConstraints = false
            let gap = PaneLayout.gap
            drop.wantsLayer = true
            drop.layer?.backgroundColor = (PaneLayout.transparentGaps ? NSColor.clear : NSColor.windowBackgroundColor).cgColor
            NSLayoutConstraint.activate([
                pane.leadingAnchor.constraint(equalTo: drop.leadingAnchor, constant: gap / 2),
                pane.trailingAnchor.constraint(equalTo: drop.trailingAnchor, constant: -gap / 2),
                pane.topAnchor.constraint(equalTo: drop.topAnchor, constant: gap / 2),
                pane.bottomAnchor.constraint(equalTo: drop.bottomAnchor, constant: -gap / 2)
            ])
            return drop
        }
        guard !panes.isEmpty else { return }
        let body: NSView
        if panes.count <= 2 {
            body = split(panes, vertical: true, ratio: workspace.topRatio) { [workspace] in workspace.topRatio = $0 }
        }
        else {
            let top = split(Array(panes.prefix(2)), vertical: true, ratio: workspace.topRatio) { [workspace] in workspace.topRatio = $0 }
            let bottom = split(Array(panes.dropFirst(2)), vertical: true, ratio: workspace.bottomRatio) { [workspace] in workspace.bottomRatio = $0 }
            body = split([top, bottom], vertical: false, ratio: workspace.rowRatio) { [workspace] in workspace.rowRatio = $0 }
        }
        content.addSubview(body)
        body.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor), body.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            body.topAnchor.constraint(equalTo: content.topAnchor), body.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        window?.title = "Tile — Workspace \(selectedWorkspace + 1)"
    }
    private func applyGapAppearance() {
        let transparent = PaneLayout.transparentGaps
        window?.isOpaque = !transparent
        window?.backgroundColor = transparent ? .clear : .windowBackgroundColor
        root.layer?.backgroundColor = NSColor.clear.cgColor
        content.layer?.backgroundColor = (transparent ? NSColor.clear : NSColor.windowBackgroundColor).cgColor
        toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.needsDisplay = true
    }
    private func split(_ views: [NSView], vertical: Bool, ratio: CGFloat, onChange: @escaping (CGFloat) -> Void) -> NSView {
        guard views.count > 1 else { return views[0] }
        let split = RatioSplitView(frame: .zero)
        split.isVertical = vertical
        split.dividerStyle = .thin
        split.ratio = ratio
        split.onRatioChange = onChange
        views.forEach(split.addSubview)
        return split
    }
    func close(_ session: TerminalSession) {
        guard app?.confirmClose([session]) == true else { return }
        remove(session, terminate: true)
        app?.saveWorkspace()
    }
    func rename(_ session: TerminalSession) {
        let alert = NSAlert()
        alert.messageText = "Name this terminal"
        alert.informativeText = "Double-click its header to change the name again. Leave it blank to use the terminal title."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = session.customTitle ?? ""
        field.placeholderString = session.title
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        session.customTitle = name.isEmpty ? nil : name
        session.onChange?()
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
        let next: Int
        if workspace.panes.count == 3 && row == 0 && dy == 1 {
            workspace.lastTopColumn = column
            next = 2
        } else if workspace.panes.count == 3 && row == 1 && dy == -1 {
            next = workspace.lastTopColumn
        } else {
            next = nextRow * 2 + nextColumn
        }
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
    @objc private func updateClock() { clockLabel.stringValue = TileClock.label(for: Date()) }
    @objc private func selectTab(_ sender: NSButton) { selectWorkspace(sender.tag) }
    func windowDidBecomeKey(_ notification: Notification) { app?.lastWindow = self }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard allowClose || app?.confirmClose(allSessions) == true else { return false }
        allSessions.forEach { $0.view.terminate() }
        allowClose = true
        return true
    }
    func windowWillClose(_ notification: Notification) {
        clockTimer?.invalidate()
        clockTimer = nil
        app?.removeWindow(self)
    }
}
