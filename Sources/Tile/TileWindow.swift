import AppKit

@MainActor
final class TileDesktopWindow: NSWindow {
    var onToggleFullScreen: (() -> Void)?
    var onFirstResponderChange: (() -> Void)?

    override func toggleFullScreen(_ sender: Any?) {
        onToggleFullScreen?()
    }
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let accepted = super.makeFirstResponder(responder)
        if accepted { onFirstResponderChange?() }
        return accepted
    }
}

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
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
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
    private let agentStatus = NSTextField(labelWithString: "")
    private let inputFocusIndicator = NSTextField(labelWithString: "▸")
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
        applyCornerRadius(PaneLayout.cornerRadius)
        title.stringValue = session.displayTitle
        title.textColor = TerminalTheme.current.foreground
        title.lineBreakMode = .byTruncatingTail
        agentStatus.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        agentStatus.alignment = .right
        agentStatus.lineBreakMode = .byTruncatingTail
        inputFocusIndicator.identifier = NSUserInterfaceItemIdentifier("tile.inputFocusIndicator")
        inputFocusIndicator.textColor = .systemBlue
        inputFocusIndicator.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        inputFocusIndicator.isHidden = true
        close.bezelStyle = .inline
        close.contentTintColor = TerminalTheme.current.foreground
        renameButton.bezelStyle = .inline
        renameButton.contentTintColor = TerminalTheme.current.foreground
        renameButton.target = self
        renameButton.action = #selector(renamePane)
        renameButton.toolTip = "Rename terminal"
        renameButton.setAccessibilityLabel("Rename terminal")
        close.target = self
        close.action = #selector(closePane)
        close.toolTip = "Close terminal"
        close.setAccessibilityLabel("Close terminal")
        addSubview(header)
        header.onRename = { [weak self] in self?.onRename?() }
        header.addSubview(inputFocusIndicator)
        header.addSubview(title)
        header.addSubview(agentStatus)
        header.addSubview(renameButton)
        header.addSubview(close)
        addSubview(session.view)
        session.onChange = { [weak self] in self?.title.stringValue = session.displayTitle }
        updateActivity()
        updateAgentStatus(owner.agentMonitor.snapshot(for: session.id))
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
        inputFocusIndicator.frame = NSRect(x: 6, y: 4, width: 12, height: 20)
        title.frame = NSRect(x: 20, y: 4, width: max(0, bounds.width - 185), height: 20)
        agentStatus.frame = NSRect(x: max(0, bounds.width - 157), y: 4, width: 92, height: 20)
        renameButton.frame = NSRect(x: max(0, bounds.width - 60), y: 3, width: 26, height: 22)
        close.frame = NSRect(x: max(0, bounds.width - 30), y: 3, width: 26, height: 22)
        session.view.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - headerHeight))
        if PaneLayout.transparentGaps { (window?.contentView as? TileRootView)?.needsDisplay = true }
    }
    @objc private func closePane() { onClose?() }
    @objc private func renamePane() { onRename?() }
    @objc private func refreshActivity() {
        updateActivity()
        updateAgentStatus(header.owner?.agentMonitor.snapshot(for: session.id))
    }
    func applyCornerRadius(_ radius: CGFloat) {
        layer?.cornerRadius = radius
        layer?.masksToBounds = radius > 0
    }
    func showInputFocus(_ active: Bool) {
        inputFocusIndicator.isHidden = !active
        header.layer?.backgroundColor = (active
            ? TerminalTheme.current.header.blended(withFraction: 0.2, of: .systemBlue) ?? TerminalTheme.current.header
            : TerminalTheme.current.header).cgColor
        title.textColor = TerminalTheme.current.foreground.withAlphaComponent(active ? 1 : 0.8)
    }
    func updateActivity() {
        let running = session.hasRunningCommand
        layer?.borderWidth = running ? 2 : 0
        layer?.borderColor = running ? NSColor.systemGreen.cgColor : nil
    }
    func updateAgentStatus(_ snapshot: AgentSnapshot?) {
        guard let snapshot else { agentStatus.stringValue = ""; agentStatus.isHidden = true; return }
        agentStatus.isHidden = false
        agentStatus.stringValue = "\(snapshot.provider.rawValue): \(snapshot.phase.label)"
        agentStatus.textColor = snapshot.phase.priority == nil ? .secondaryLabelColor : .systemOrange
        let detail = "\(snapshot.provider.rawValue), \(snapshot.phase.label), from \(snapshot.source), last seen \(snapshot.observedAt.formatted())"
        agentStatus.toolTip = detail
        agentStatus.setAccessibilityLabel(detail)
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
    private let brand = TileBrandView()
    private let tabs = NSStackView()
    private let workspacePicker = NSPopUpButton()
    private let toolbarSpacer = NSView()
    private let toolbarTrailingSpacer = NSView()
    private let clockLabel = NSTextField(labelWithString: "")
    private var clockTimer: Timer?
    private let content = DropSurface(frame: .zero)
    private var paneViews: [PaneView] = []
    private let plus = NSButton(title: "+", target: nil, action: nil)
    private let focus = NSButton(title: "Focus", target: nil, action: nil)
    private let exitFullScreen = NSButton(title: "Exit Full Screen", target: nil, action: nil)
    private let settings = NSButton(title: "⚙", target: nil, action: nil)
    private let agentButton = NSButton(title: "Agents 0", target: nil, action: nil)
    private let managedCodexButton = NSButton(title: "Codex", target: nil, action: nil)
    private var toolbarTopConstraint: NSLayoutConstraint?
    private var normalFrame: NSRect?
    private var normalStyleMask: NSWindow.StyleMask?
    private var normalHasShadow = true

    init(id: UUID = UUID(), workspaces: [Workspace], owner: TileApp) {
        self.id = id
        self.workspaces = workspaces.isEmpty ? [Workspace()] : workspaces
        self.app = owner
        let window = TileDesktopWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Tile"
        window.minSize = NSSize(width: 500, height: 320)
        window.collectionBehavior = [.fullScreenNone, .fullScreenDisallowsTiling]
        super.init(window: window)
        window.delegate = self
        window.onToggleFullScreen = { [weak self] in self?.toggleDesktopFullScreen() }
        window.onFirstResponderChange = { [weak self] in self?.updateInputFocusCue() }
        configureZoomButton()
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
        brand.identifier = NSUserInterfaceItemIdentifier("tile.brand")
        brand.setContentHuggingPriority(.required, for: .horizontal)
        toolbar.addArrangedSubview(brand)
        tabs.orientation = .horizontal
        tabs.spacing = 3
        tabs.identifier = NSUserInterfaceItemIdentifier("tile.workspaceTabs")
        toolbar.addArrangedSubview(tabs)
        workspacePicker.isHidden = true
        workspacePicker.setAccessibilityLabel("Choose workspace")
        workspacePicker.target = self
        workspacePicker.action = #selector(selectWorkspaceFromPicker(_:))
        toolbar.addArrangedSubview(workspacePicker)
        toolbarSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolbarSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        toolbar.addArrangedSubview(toolbarSpacer)
        clockLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        clockLabel.alignment = .center
        clockLabel.identifier = NSUserInterfaceItemIdentifier("tile.clock")
        clockLabel.setContentHuggingPriority(.required, for: .horizontal)
        toolbar.addArrangedSubview(clockLabel)
        toolbarTrailingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolbarTrailingSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        toolbar.addArrangedSubview(toolbarTrailingSpacer)
        agentButton.target = self
        agentButton.identifier = NSUserInterfaceItemIdentifier("tile.agentOverview")
        agentButton.action = #selector(openAgentOverview)
        agentButton.bezelStyle = .rounded
        agentButton.setAccessibilityLabel("Agent overview")
        toolbar.addArrangedSubview(agentButton)
        managedCodexButton.target = self
        managedCodexButton.action = #selector(openManagedCodex)
        managedCodexButton.bezelStyle = .rounded
        managedCodexButton.toolTip = "Open a managed Codex session for the selected pane"
        managedCodexButton.setAccessibilityLabel("Open managed Codex session")
        toolbar.addArrangedSubview(managedCodexButton)
        toolbarSpacer.widthAnchor.constraint(equalTo: toolbarTrailingSpacer.widthAnchor).isActive = true
        updateClock()
        clockTimer = Timer.scheduledTimer(timeInterval: 15, target: self, selector: #selector(updateClock), userInfo: nil, repeats: true)
        exitFullScreen.isHidden = true
        plus.toolTip = "New terminal"
        plus.setAccessibilityLabel("New terminal")
        focus.toolTip = "Focus selected terminal pane"
        focus.setAccessibilityLabel("Focus selected terminal pane")
        exitFullScreen.setAccessibilityLabel("Exit full screen")
        settings.toolTip = "Settings"
        settings.setAccessibilityLabel("Settings")
        for (button, action) in [(plus, #selector(addPane)), (focus, #selector(toggleFocus)), (exitFullScreen, #selector(toggleDesktopFullScreen)), (settings, #selector(openSettings))] {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
            toolbar.addArrangedSubview(button)
        }
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        let topConstraint = toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 8)
        toolbarTopConstraint = topConstraint
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            topConstraint,
            toolbar.heightAnchor.constraint(equalToConstant: 38),
            content.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        render()
        showWindow(nil)
        updateCompactToolbar()
        focusTerminal(currentSession)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    var workspace: Workspace { workspaces[selectedWorkspace] }
    var allSessions: [TerminalSession] { workspaces.flatMap(\.panes) }
    var currentSession: TerminalSession? { workspace.panes.first { $0.id == selectedPane } ?? workspace.panes.first }
    var isDesktopFullScreen: Bool { normalFrame != nil }
    var frameForRestoration: NSRect? { normalFrame ?? window?.frame }
    static func reachableFrame(_ frame: NSRect, screens: [NSRect]) -> NSRect {
        guard !screens.isEmpty else { return frame }
        let intersections = screens.map { screen -> (NSRect, CGFloat) in
            let area = frame.intersection(screen)
            return (screen, area.width * area.height)
        }
        let best = intersections.max { $0.1 < $1.1 }
        let screen: NSRect
        if let best, best.1 > 0 { screen = best.0 }
        else { screen = screens[0] }
        let width = min(frame.width, screen.width)
        let height = min(frame.height, screen.height)
        return NSRect(x: min(max(frame.minX, screen.minX), screen.maxX - width),
                      y: min(max(frame.minY, screen.minY), screen.maxY - height),
                      width: width, height: height)
    }
    func keepOnAvailableScreen() {
        guard let window, !isDesktopFullScreen else { return }
        let frame = Self.reachableFrame(window.frame, screens: NSScreen.screens.map(\.visibleFrame))
        if frame != window.frame { window.setFrame(frame, display: true) }
    }
    func focusTerminal(_ session: TerminalSession?) {
        guard let session else { return }
        _ = window?.makeFirstResponder(session.view)
    }
    private func configureZoomButton() {
        window?.standardWindowButton(.zoomButton)?.target = self
        window?.standardWindowButton(.zoomButton)?.action = #selector(toggleDesktopFullScreen)
    }

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
        focusTerminal(session)
    }
    func reopen(_ session: TerminalSession, from closed: TileApp.ClosedPane) {
        if let target = workspaces.firstIndex(where: { $0.id == closed.workspaceID && $0.panes.count < 4 }) {
            selectedWorkspace = target
        } else if !workspaces.contains(where: { $0.id == closed.workspaceID }) {
            if workspaces.count == 1 && workspaces[0].panes.isEmpty { workspaces.removeAll() }
            let recovered = Workspace(id: closed.workspaceID)
            recovered.topRatio = closed.topRatio
            recovered.bottomRatio = closed.bottomRatio
            recovered.rowRatio = closed.rowRatio
            selectedWorkspace = min(closed.workspaceIndex, workspaces.count)
            workspaces.insert(recovered, at: selectedWorkspace)
        } else {
            workspaces.append(Workspace())
            selectedWorkspace = workspaces.count - 1
        }
        workspace.panes.insert(session, at: min(max(closed.paneIndex, 0), workspace.panes.count))
        selectedPane = session.id
        focused = false
        render()
        focusTerminal(session)
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
        focusTerminal(currentSession)
    }
    func render() {
        guard window != nil else { return }
        applyGapAppearance()
        tabs.arrangedSubviews.forEach { tabs.removeArrangedSubview($0); $0.removeFromSuperview() }
        for index in workspaces.indices {
            let active = index == selectedWorkspace
            let button = NSButton(title: active ? "▸ \(index + 1)" : "\(index + 1)", target: self, action: #selector(selectTab(_:)))
            button.tag = index
            button.bezelStyle = .rounded
            button.setButtonType(.toggle)
            button.state = active ? .on : .off
            let description = active ? "Workspace \(index + 1), active" : "Switch to workspace \(index + 1)"
            button.toolTip = description
            button.setAccessibilityLabel(description)
            tabs.addArrangedSubview(button)
        }
        workspacePicker.removeAllItems()
        for index in workspaces.indices { workspacePicker.addItem(withTitle: "Workspace \(index + 1)") }
        workspacePicker.selectItem(at: selectedWorkspace)
        focus.title = focused ? "Exit Focus" : "Focus"
        focus.toolTip = focused ? "Exit Focus and restore the split layout" : "Focus selected terminal pane"
        focus.setAccessibilityLabel(focus.toolTip ?? focus.title)
        updateCompactToolbar()
        content.subviews.forEach { $0.removeFromSuperview() }
        paneViews.removeAll()
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
            paneViews.append(pane)
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
        updateInputFocusCue()
        refreshAgentUI()
    }
    func refreshAgentUI() {
        guard let monitor = app?.agentMonitor else { return }
        let all = workspace.panes.compactMap { monitor.snapshot(for: $0.id) }
        let attention = monitor.attention(in: workspace.panes)
        agentButton.title = "Agents \(all.count) · \(attention.count)"
        agentButton.setAccessibilityLabel("\(all.count) agents, \(attention.count) need attention in workspace \(selectedWorkspace + 1)")
        paneViews.forEach { $0.updateAgentStatus(monitor.snapshot(for: $0.session.id)) }
    }
    @objc private func openAgentOverview() {
        guard let monitor = app?.agentMonitor else { return }
        let menu = NSMenu(title: "Agents in Workspace \(selectedWorkspace + 1)")
        let sessions = workspace.panes.compactMap { session -> (TerminalSession, AgentSnapshot)? in
            guard let snapshot = monitor.snapshot(for: session.id) else { return nil }
            return (session, snapshot)
        }
        if sessions.isEmpty { menu.addItem(withTitle: "No linked agents", action: nil, keyEquivalent: "") }
        for (session, item) in sessions {
            let row = NSMenuItem(title: "\(item.provider.rawValue) · \(session.displayTitle) · \(item.phase.label) · \(item.observedAt.formatted(date: .omitted, time: .shortened))", action: #selector(jumpToAgent(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = session.id.uuidString
            row.toolTip = item.source
            menu.addItem(row)
            if let usage = item.usage {
                let fresh = Date().timeIntervalSince(usage.sampledAt) <= 120
                let cost = fresh ? usage.estimatedSessionCostUSD.map { String(format: "est. session $%.2f", $0) } ?? "Cost unavailable" : "Cost stale"
                func quota(_ name: String, _ value: AgentQuotaWindow?) -> String {
                    guard fresh, let value else { return "\(name) unavailable" }
                    let duration = value.durationMinutes.map { " \($0)m" } ?? ""
                    return "\(name)\(duration) \(Int(value.usedPercent))% used, resets \(value.resetsAt.formatted(date: .abbreviated, time: .shortened))"
                }
                let detail: String
                if item.provider == .codex {
                    let tokens = fresh ? usage.threadTotalTokens.map { "Thread total \($0) tokens" } ?? "Thread tokens unavailable" : "Thread tokens stale"
                    let plan = usage.accountPlan.map { "Account \($0)" } ?? "Account plan unavailable"
                    detail = "\(tokens) · \(plan) · \(quota("Account primary", usage.codexPrimary)) · \(quota("Account secondary", usage.codexSecondary))"
                } else { detail = "\(cost) · \(quota("5h", usage.fiveHour)) · \(quota("7d", usage.sevenDay))" }
                let metric = NSMenuItem(title: detail, action: nil, keyEquivalent: "")
                metric.toolTip = "\(item.provider == .codex ? "Codex app server" : "Claude Code status line"), sampled \(usage.sampledAt.formatted())"
                menu.addItem(metric)
            } else {
                let metric = NSMenuItem(title: "Usage unavailable · Quota unavailable", action: nil, keyEquivalent: "")
                metric.toolTip = "No supported fresh usage source for this session"
                menu.addItem(metric)
            }
        }
        let pending = monitor.attention(in: workspace.panes)
        if !pending.isEmpty {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Needs attention", action: nil, keyEquivalent: "")
            for item in pending {
                let paneTitle = workspace.panes.first(where: { $0.id == item.paneID })?.displayTitle ?? "Terminal"
                let stale = Date().timeIntervalSince(item.observedAt) > 120 ? " (last reported)" : ""
                let row = NSMenuItem(title: "\(item.phase.label)\(stale) · \(item.provider.rawValue) · \(paneTitle)", action: nil, keyEquivalent: "")
                row.toolTip = "\(item.source), last seen \(item.observedAt.formatted())"
                let actions = NSMenu()
                let jump = NSMenuItem(title: "Jump to terminal", action: #selector(jumpToAgent(_:)), keyEquivalent: "")
                jump.target = self
                jump.representedObject = item.paneID.uuidString
                actions.addItem(jump)
                let dismiss = NSMenuItem(title: item.phase == .completedNeedsReview ? "Mark reviewed" : "Dismiss action", action: #selector(dismissAgentAction(_:)), keyEquivalent: "")
                dismiss.target = self
                dismiss.representedObject = item
                actions.addItem(dismiss)
                row.submenu = actions
                menu.addItem(row)
            }
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: agentButton.bounds.height), in: agentButton)
    }
    @objc private func openManagedCodex() {
        guard let session = currentSession else { return }
        app?.showManagedCodex(for: session)
    }
    @objc private func jumpToAgent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let paneID = UUID(uuidString: id),
              let session = app?.windows.flatMap(\.allSessions).first(where: { $0.id == paneID }) else { return }
        app?.select(session)
    }
    @objc private func dismissAgentAction(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? AgentSnapshot else { return }
        app?.agentMonitor.dismiss(item)
    }
    private func updateInputFocusCue() {
        let responder = window?.isKeyWindow == true ? window?.firstResponder : nil
        if let session = workspace.panes.first(where: { $0.view === responder }) { selectedPane = session.id }
        paneViews.forEach { $0.showInputFocus(responder === $0.session.view) }
    }
    private func applyGapAppearance() {
        let transparent = PaneLayout.transparentGaps
        window?.isOpaque = !transparent
        // A tiny nonzero alpha avoids AppKit's dark fallback while leaving gaps clear.
        window?.backgroundColor = transparent ? NSColor.windowBackgroundColor.withAlphaComponent(0.01) : .windowBackgroundColor
        root.layer?.backgroundColor = NSColor.clear.cgColor
        content.layer?.backgroundColor = (transparent ? NSColor.clear : NSColor.windowBackgroundColor).cgColor
        toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.needsDisplay = true
    }
    @objc func toggleDesktopFullScreen() {
        guard let window else { return }
        if let normalFrame, let normalStyleMask {
            window.styleMask = normalStyleMask
            window.hasShadow = normalHasShadow
            toolbarTopConstraint?.constant = 8
            exitFullScreen.isHidden = true
            window.setFrame(normalFrame, display: true)
            self.normalFrame = nil
            self.normalStyleMask = nil
            configureZoomButton()
            app?.setDesktopFullScreen(false, for: id)
        } else {
            guard let screen = window.screen ?? NSScreen.main else { return }
            normalFrame = window.frame
            normalStyleMask = window.styleMask
            normalHasShadow = window.hasShadow
            window.styleMask = .borderless
            window.hasShadow = false
            toolbarTopConstraint?.constant = max(8, screen.safeAreaInsets.top + 8)
            exitFullScreen.isHidden = false
            window.setFrame(screen.frame, display: true)
            app?.setDesktopFullScreen(true, for: id)
        }
        window.makeKeyAndOrderFront(nil)
        root.needsLayout = true
        root.needsDisplay = true
        app?.saveWorkspace()
    }
    func escapeDesktopFullScreen() -> Bool {
        guard isDesktopFullScreen else { return false }
        toggleDesktopFullScreen()
        return true
    }
    private func split(_ views: [NSView], vertical: Bool, ratio: CGFloat, onChange: @escaping (CGFloat) -> Void) -> NSView {
        guard views.count > 1 else { return views[0] }
        let split = RatioSplitView(frame: .zero)
        split.isVertical = vertical
        split.dividerStyle = .thin
        split.ratio = ratio
        split.onRatioChange = { [weak self] value in
            onChange(value)
            self?.app?.scheduleLayoutSave()
        }
        views.forEach(split.addSubview)
        return split
    }
    func updateCornerRadius(_ radius: CGFloat) {
        paneViews.forEach { $0.applyCornerRadius(radius) }
    }
    func close(_ session: TerminalSession) {
        guard app?.confirmClose([session]) == true else { return }
        session.refreshDirectory()
        if let workspaceIndex = workspaces.firstIndex(where: { $0.panes.contains(where: { $0.id == session.id }) }),
           let paneIndex = workspaces[workspaceIndex].panes.firstIndex(where: { $0.id == session.id }) {
            let workspace = workspaces[workspaceIndex]
            app?.recentlyClosedPane = TileApp.ClosedPane(directory: session.directory, customTitle: session.customTitle,
                                                         windowID: id, workspaceID: workspace.id,
                                                         workspaceIndex: workspaceIndex, paneIndex: paneIndex,
                                                         topRatio: workspace.topRatio, bottomRatio: workspace.bottomRatio,
                                                         rowRatio: workspace.rowRatio)
        }
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
        focusTerminal(currentSession)
        app?.saveWorkspace()
    }
    func escapeFocus() -> Bool {
        guard focused else { return false }
        focused = false
        render()
        focusTerminal(currentSession)
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
        focusTerminal(workspace.panes[next])
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
        focusTerminal(session)
        app?.saveWorkspace()
    }
    @objc private func addPane() { app?.addPane(to: self) }
    @objc func toggleFocus() {
        if selectedPane == nil { selectedPane = workspace.panes.first?.id }
        focused.toggle()
        render()
        focusTerminal(currentSession)
    }
    private func updateCompactToolbar() {
        let compact = (window?.contentView?.bounds.width ?? 1080) < 760 || workspaces.count > 4
        brand.isHidden = compact
        clockLabel.isHidden = compact
        tabs.isHidden = compact
        workspacePicker.isHidden = !compact
    }
    @objc private func openSettings() { app?.showSettings() }
    @objc private func updateClock() {
        clockLabel.stringValue = TileClock.label(for: Date())
        refreshAgentUI()
    }
    @objc private func selectTab(_ sender: NSButton) { selectWorkspace(sender.tag) }
    @objc private func selectWorkspaceFromPicker(_ sender: NSPopUpButton) { selectWorkspace(sender.indexOfSelectedItem) }
    func windowDidResize(_ notification: Notification) { updateCompactToolbar() }
    func windowDidBecomeKey(_ notification: Notification) {
        app?.lastWindow = self
        updateInputFocusCue()
    }
    func windowDidResignKey(_ notification: Notification) { updateInputFocusCue() }
    func windowDidMove(_ notification: Notification) { app?.saveWorkspace() }
    func windowDidEndLiveResize(_ notification: Notification) { app?.saveWorkspace() }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard allowClose || app?.confirmClose(allSessions) == true else { return false }
        allSessions.forEach { $0.view.terminate() }
        allowClose = true
        return true
    }
    func windowWillClose(_ notification: Notification) {
        if isDesktopFullScreen { app?.setDesktopFullScreen(false, for: id) }
        clockTimer?.invalidate()
        clockTimer = nil
        app?.removeWindow(self)
    }
}
