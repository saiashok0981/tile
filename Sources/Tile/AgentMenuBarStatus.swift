import AppKit

private final class AgentDashboardDocument: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class AgentMenuBarStatus: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var onSelect: ((UUID) -> Void)?
    private var notchPanel: NSPanel?
    private var notchButton: NSButton?
    private let dashboard = NSPopover()
    private var dashboardAgents: [(TerminalSession, AgentSnapshot, AgentDetail?)] = []
    private var elapsedLabels: [(NSTextField, AgentSnapshot, AgentDetail?)] = []
    private var elapsedTimer: Timer?
    var notchControlFrame: NSRect? { notchPanel?.isVisible == true ? notchPanel?.frame : nil }
    var dashboardIsShown: Bool { dashboard.isShown }
    var linkedAgentCount: Int { dashboardAgents.count }

    override init() {
        super.init()
        dashboard.behavior = .transient
        item.button?.target = self
        item.button?.action = #selector(toggleDashboard)
        reposition()
        update([])
        elapsedTimer = Timer.scheduledTimer(timeInterval: 1, target: self,
                                            selector: #selector(refreshElapsed),
                                            userInfo: nil, repeats: true)
    }

    func reposition() {
        guard let area = NSScreen.screens.compactMap(\.auxiliaryTopRightArea).first,
              area.width >= 120, area.height >= 24 else {
            notchPanel?.orderOut(nil)
            item.isVisible = true
            return
        }
        if notchPanel == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            let surface = NSView(frame: NSRect(x: 0, y: 0, width: 112, height: 24))
            surface.wantsLayer = true
            surface.layer?.backgroundColor = NSColor.black.cgColor
            surface.layer?.cornerRadius = 12
            let button = NSButton(frame: surface.bounds)
            button.isBordered = false
            button.target = self
            button.action = #selector(toggleDashboard)
            button.setAccessibilityLabel("Open Tile agent status")
            surface.addSubview(button)
            panel.contentView = surface
            notchPanel = panel
            notchButton = button
        }
        let frame = NSRect(x: area.minX + 6, y: area.midY - 12, width: 112, height: 24)
        notchPanel?.setFrame(frame, display: true)
        notchPanel?.orderFrontRegardless()
        item.isVisible = false
    }

    func update(_ agents: [(TerminalSession, AgentSnapshot, AgentDetail?)]) {
        let ranked = agents.sorted { left, right in
            let leftRank = rank(left.1.phase)
            let rightRank = rank(right.1.phase)
            if leftRank != rightRank { return leftRank < rightRank }
            return left.1.observedAt > right.1.observedAt
        }
        dashboardAgents = ranked
        let title: String
        if let first = ranked.first?.1 {
            let state = first.phase == .running ? "Running" : first.phase.label
            title = "\(first.provider.rawValue): \(state)"
        } else {
            title = "Tile"
        }
        item.button?.title = title
        item.button?.setAccessibilityLabel("Tile agent status: \(title)")

        let shortState = ranked.first.map { $0.1.phase == .running ? "Running" : $0.1.phase.label } ?? "Tile"
        let badge = NSMutableAttributedString(string: "● \(shortState)", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ])
        badge.addAttribute(.foregroundColor,
                           value: ranked.first?.1.phase == .running ? NSColor.systemGreen : NSColor.lightGray,
                           range: NSRange(location: 0, length: 1))
        notchButton?.attributedTitle = badge
        notchButton?.setAccessibilityLabel("Tile agent status: \(title). Open agent list")

        if dashboard.isShown { renderDashboard() }
    }

    @objc func toggleDashboard() {
        guard let anchor = item.isVisible ? item.button : notchButton else { return }
        if dashboard.isShown { dashboard.close(); return }
        renderDashboard()
        dashboard.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        refreshElapsed()
    }

    private func renderDashboard() {
        let width: CGFloat = 390
        let rowHeights = dashboardAgents.map {
            158 + CGFloat(min(8, $0.2?.recent.count ?? 0)) * 19 + ($0.1.usage == nil ? 0 : 20)
        }
        let documentHeight = max(80, rowHeights.reduce(0, +) + 12)
        let height = min(520, documentHeight + 52)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let heading = NSTextField(labelWithString: "Agents in Tile")
        heading.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        heading.frame = NSRect(x: 16, y: height - 36, width: 220, height: 22)
        root.addSubview(heading)
        let count = NSTextField(labelWithString: "\(dashboardAgents.count) linked")
        count.textColor = .secondaryLabelColor
        count.alignment = .right
        count.frame = NSRect(x: 260, y: height - 35, width: 112, height: 20)
        root.addSubview(count)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height - 48))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let document = AgentDashboardDocument(frame: NSRect(x: 0, y: 0, width: width, height: documentHeight))
        scroll.documentView = document
        root.addSubview(scroll)
        elapsedLabels.removeAll()
        if dashboardAgents.isEmpty {
            addLabel("No linked agents yet. Start an agent in a Tile pane.",
                     to: document, x: 16, y: 22, width: 350, color: .secondaryLabelColor)
        }
        var y: CGFloat = 12
        for (index, entry) in dashboardAgents.enumerated() {
            let (session, snapshot, detail) = entry
            addLabel("\(snapshot.provider.rawValue) · \(session.displayTitle)", to: document,
                     x: 16, y: y, width: 278, font: .systemFont(ofSize: 13, weight: .semibold))
            let open = NSButton(title: "Open", target: self, action: #selector(openDashboardAgent(_:)))
            open.bezelStyle = .rounded
            open.tag = index
            open.frame = NSRect(x: 308, y: y - 2, width: 65, height: 24)
            document.addSubview(open)
            y += 27
            let status = snapshot.phase == .running ? "Running" : snapshot.phase.label
            addLabel("Status: \(status)", to: document, x: 16, y: y, width: 350,
                     color: snapshot.phase == .running ? .systemGreen : .labelColor)
            y += 22
            addLabel("Task: \(detail?.task ?? "Not reported by agent")", to: document,
                     x: 16, y: y, width: 356)
            y += 22
            addLabel("Now: \(detail?.currentAction ?? status)", to: document,
                     x: 16, y: y, width: 356)
            y += 22
            let elapsed = addLabel("", to: document, x: 16, y: y, width: 356,
                                   color: .secondaryLabelColor)
            elapsedLabels.append((elapsed, snapshot, detail))
            y += 22
            if let usage = snapshot.usage {
                var metrics: [String] = []
                if let tokens = usage.threadTotalTokens { metrics.append("\(tokens) thread tokens") }
                if let cost = usage.estimatedSessionCostUSD { metrics.append(String(format: "$%.2f session", cost)) }
                addLabel("Usage: \(metrics.isEmpty ? "Unavailable" : metrics.joined(separator: " · "))",
                         to: document, x: 16, y: y, width: 356, color: .secondaryLabelColor)
                y += 20
                var quotas: [String] = []
                if let primary = usage.codexPrimary { quotas.append("Primary \(Int(primary.usedPercent))%") }
                if let secondary = usage.codexSecondary { quotas.append("Secondary \(Int(secondary.usedPercent))%") }
                if let fiveHour = usage.fiveHour { quotas.append("5h \(Int(fiveHour.usedPercent))%") }
                if let sevenDay = usage.sevenDay { quotas.append("7d \(Int(sevenDay.usedPercent))%") }
                addLabel("Quota: \(quotas.isEmpty ? "Unavailable" : quotas.joined(separator: " · "))",
                         to: document, x: 16, y: y, width: 356, color: .secondaryLabelColor)
            } else {
                addLabel("Source: \(snapshot.source)", to: document, x: 16, y: y, width: 356,
                         color: .secondaryLabelColor)
            }
            y += 23
            for activity in detail?.recent.prefix(8) ?? [] {
                addLabel("\(activity.at.formatted(date: .omitted, time: .shortened))  \(activity.text)",
                         to: document, x: 27, y: y, width: 339, color: .secondaryLabelColor)
                y += 19
            }
            y += 8
            let divider = NSBox(frame: NSRect(x: 16, y: y, width: 356, height: 1))
            divider.boxType = .separator
            document.addSubview(divider)
            y += 12
        }
        refreshElapsed()
        let controller = NSViewController()
        controller.view = root
        dashboard.contentViewController = controller
        dashboard.contentSize = root.frame.size
    }

    @discardableResult
    private func addLabel(_ text: String, to parent: NSView, x: CGFloat, y: CGFloat,
                          width: CGFloat, font: NSFont = .systemFont(ofSize: 12),
                          color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = text
        label.frame = NSRect(x: x, y: y, width: width, height: 18)
        parent.addSubview(label)
        return label
    }

    @objc private func refreshElapsed() {
        guard dashboard.isShown else { return }
        for (label, snapshot, detail) in elapsedLabels {
            guard let start = detail?.startedAt else { label.stringValue = "Elapsed: Not available"; continue }
            let end = detail?.finishedAt ?? (snapshot.phase == .unknown ? snapshot.observedAt : Date())
            let seconds = max(0, Int(end.timeIntervalSince(start)))
            label.stringValue = String(format: "Elapsed: %02d:%02d", seconds / 60, seconds % 60)
        }
    }

    @objc private func openDashboardAgent(_ sender: NSButton) {
        guard dashboardAgents.indices.contains(sender.tag) else { return }
        let id = dashboardAgents[sender.tag].0.id
        dashboard.close()
        onSelect?(id)
    }

    private func rank(_ phase: AgentPhase) -> Int {
        switch phase {
        case .approvalRequired: 0
        case .questionRequired: 1
        case .failed: 2
        case .running: 3
        case .completedNeedsReview: 4
        case .idle: 5
        case .unknown: 6
        }
    }

}
