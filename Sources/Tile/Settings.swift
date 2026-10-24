import AppKit
import UserNotifications

enum PaneLayout {
    static var gap: CGFloat {
        let saved = UserDefaults.standard.object(forKey: "paneGap") as? Int ?? 8
        return CGFloat(min(max(saved, 0), 24))
    }
    static var transparentGaps: Bool { UserDefaults.standard.bool(forKey: "transparentPaneGaps") }
    static var cornerRadius: CGFloat {
        let saved = UserDefaults.standard.object(forKey: "paneCornerRadius") as? Int ?? 0
        return CGFloat(min(max(saved, 0), 24))
    }
}

enum TerminalTheme: String, CaseIterable {
    case oceanBlue, classicDark

    static var current: TerminalTheme {
        TerminalTheme(rawValue: UserDefaults.standard.string(forKey: "terminalTheme") ?? "") ?? .oceanBlue
    }
    var name: String {
        switch self {
        case .oceanBlue: "Ocean Blue"
        case .classicDark: "Classic Dark"
        }
    }
    var background: NSColor {
        switch self {
        case .oceanBlue: NSColor(srgbRed: 0.055, green: 0.13, blue: 0.22, alpha: 1)
        case .classicDark: NSColor(srgbRed: 0.06, green: 0.065, blue: 0.075, alpha: 1)
        }
    }
    var foreground: NSColor { NSColor(srgbRed: 0.89, green: 0.94, blue: 0.97, alpha: 1) }
    var header: NSColor {
        switch self {
        case .oceanBlue: NSColor(srgbRed: 0.09, green: 0.19, blue: 0.29, alpha: 1)
        case .classicDark: NSColor(srgbRed: 0.13, green: 0.14, blue: 0.16, alpha: 1)
        }
    }
}

enum TileAction: String, CaseIterable {
    case newPane, newWindow, focusPane, focusSelectedTerminal, renamePane, closePane, reopenPane, toggleFullScreen
    case nextWorkspace, previousWorkspace
    case focusLeft, focusRight, focusUp, focusDown
    case swapLeft, swapRight, swapUp, swapDown
    case moveToNextWorkspace, raiseWindow
    case nextAgentAttention, returnToPreviousPane
    case workspace1, workspace2, workspace3, workspace4, workspace5
    case workspace6, workspace7, workspace8, workspace9

    var title: String {
        switch self {
        case .newPane: "New terminal"
        case .newWindow: "New window"
        case .focusPane: "Focus pane"
        case .focusSelectedTerminal: "Focus selected terminal"
        case .renamePane: "Rename selected terminal"
        case .closePane: "Close selected terminal"
        case .reopenPane: "Reopen closed terminal"
        case .toggleFullScreen: "Toggle full screen"
        case .nextWorkspace: "Next workspace"
        case .previousWorkspace: "Previous workspace"
        case .focusLeft: "Focus left"
        case .focusRight: "Focus right"
        case .focusUp: "Focus up"
        case .focusDown: "Focus down"
        case .swapLeft: "Swap left"
        case .swapRight: "Swap right"
        case .swapUp: "Swap up"
        case .swapDown: "Swap down"
        case .moveToNextWorkspace: "Move pane to next workspace"
        case .raiseWindow: "Show Tile from another app"
        case .nextAgentAttention: "Next agent needing attention"
        case .returnToPreviousPane: "Return to previous pane"
        case .workspace1: "Workspace 1"
        case .workspace2: "Workspace 2"
        case .workspace3: "Workspace 3"
        case .workspace4: "Workspace 4"
        case .workspace5: "Workspace 5"
        case .workspace6: "Workspace 6"
        case .workspace7: "Workspace 7"
        case .workspace8: "Workspace 8"
        case .workspace9: "Workspace 9"
        }
    }
    var defaultShortcut: String {
        switch self {
        case .newPane: "cmd+n"
        case .newWindow: "cmd+shift+n"
        case .focusPane: "cmd+shift+f"
        case .focusSelectedTerminal: "cmd+shift+return"
        case .renamePane: "cmd+shift+r"
        case .closePane: "cmd+shift+w"
        case .reopenPane: "cmd+shift+t"
        case .toggleFullScreen: "cmd+ctrl+f"
        case .nextWorkspace: "cmd+option+right"
        case .previousWorkspace: "cmd+option+left"
        case .focusLeft: "option+left"
        case .focusRight: "option+right"
        case .focusUp: "option+up"
        case .focusDown: "option+down"
        case .swapLeft: "cmd+ctrl+shift+left"
        case .swapRight: "cmd+ctrl+shift+right"
        case .swapUp: "cmd+ctrl+shift+up"
        case .swapDown: "cmd+ctrl+shift+down"
        case .moveToNextWorkspace: "cmd+ctrl+shift+return"
        case .raiseWindow: "cmd+option+space"
        case .nextAgentAttention: "cmd+option+a"
        case .returnToPreviousPane: "cmd+option+shift+a"
        case .workspace1: "cmd+1"
        case .workspace2: "cmd+2"
        case .workspace3: "cmd+3"
        case .workspace4: "cmd+4"
        case .workspace5: "cmd+option+5"
        case .workspace6: "cmd+option+6"
        case .workspace7: "cmd+option+7"
        case .workspace8: "cmd+option+8"
        case .workspace9: "cmd+option+9"
        }
    }
    private var previousDefaultShortcut: String? {
        switch self {
        case .focusLeft: "cmd+ctrl+left"
        case .focusRight: "cmd+ctrl+right"
        case .focusUp: "cmd+ctrl+up"
        case .focusDown: "cmd+ctrl+down"
        case .workspace1: "cmd+option+1"
        case .workspace2: "cmd+option+2"
        case .workspace3: "cmd+option+3"
        case .workspace4: "cmd+option+4"
        default: nil
        }
    }
    var shortcut: String {
        guard let saved = UserDefaults.standard.string(forKey: "shortcut.\(rawValue)") else { return defaultShortcut }
        return saved == previousDefaultShortcut ? defaultShortcut : saved
    }
}

enum Shortcuts {
    static func normalized(_ value: String) -> String? {
        let parts = value.lowercased().replacingOccurrences(of: " ", with: "").split(separator: "+").map(String.init)
        let key = parts.last ?? ""
        let isSimpleKey = key.count == 1 && key.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
        guard isSimpleKey || ["left", "right", "up", "down", "space", "return"].contains(key),
              parts.dropLast().allSatisfy({ ["cmd", "ctrl", "option", "shift"].contains($0) }) else { return nil }
        let modifiers = Set(parts.dropLast())
        guard modifiers.count == parts.count - 1 else { return nil }
        return (["cmd", "ctrl", "option", "shift"].filter(modifiers.contains) + [key]).joined(separator: "+")
    }
    static func from(_ event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts: [String] = []
        if flags.contains(.command) { parts.append("cmd") }
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("option") }
        if flags.contains(.shift) { parts.append("shift") }
        let key: String
        switch event.keyCode {
        case 123: key = "left"
        case 124: key = "right"
        case 125: key = "down"
        case 126: key = "up"
        case 36: key = "return"
        case 49: key = "space"
        default: key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        }
        guard !key.isEmpty else { return nil }
        return (parts + [key]).joined(separator: "+")
    }
}

@MainActor
final class SettingsWindow: NSWindowController, NSWindowDelegate {
    private let dragCheck = NSButton(checkboxWithTitle: "Enable dragging panes", target: nil, action: nil)
    private let titlesCheck = NSButton(checkboxWithTitle: "Show pane titles", target: nil, action: nil)
    private let transparentGapsCheck = NSButton(checkboxWithTitle: "Transparent gaps between terminals", target: nil, action: nil)
    private let fontSize = NSTextField()
    private let themePicker = NSPopUpButton()
    private let paneGap = NSTextField()
    private let cornerSlider = NSSlider()
    private let cornerValue = NSTextField(labelWithString: "")
    private let shellPath = NSTextField()
    private let claudeAgentCheck = NSButton(checkboxWithTitle: "Monitor Claude Code", target: nil, action: nil)
    private let codexAgentCheck = NSButton(checkboxWithTitle: "Monitor Codex", target: nil, action: nil)
    private let geminiAgentCheck = NSButton(checkboxWithTitle: "Monitor Gemini CLI", target: nil, action: nil)
    private let notificationChecks: [(String, String)] = [
        ("notifyAgentActivity", "Quiet update when an agent starts"),
        ("notifyAgentApproval", "Notify for approval"),
        ("notifyAgentQuestion", "Notify for question"),
        ("notifyAgentFailure", "Notify for failure"),
        ("notifyAgentCompletion", "Notify for completed turn")
    ]
    private var notificationButtons: [String: NSButton] = [:]
    private var shortcutFields: [TileAction: NSTextField] = [:]
    var onSave: (() -> Void)?
    var onCornerPreview: ((CGFloat) -> Void)?
    private let initialCornerRadius = PaneLayout.cornerRadius
    private var saved = false

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 680), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Tile Settings"
        super.init(window: window)
        window.delegate = self
        let root = NSScrollView(frame: window.contentView!.bounds)
        root.hasVerticalScroller = true
        root.autoresizingMask = [.width, .height]
        window.contentView = root
        let formHeight = max(CGFloat(1450), CGFloat(TileAction.allCases.count * 31 + 680))
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 510, height: formHeight))
        root.documentView = form
        var y: CGFloat = formHeight - 38
        func label(_ text: String, at x: CGFloat = 20, width: CGFloat = 240) {
            let view = NSTextField(labelWithString: text)
            view.frame = NSRect(x: x, y: y, width: width, height: 22)
            form.addSubview(view)
        }
        label("Terminal and layout")
        y -= 34
        dragCheck.frame = NSRect(x: 20, y: y, width: 260, height: 22)
        dragCheck.state = UserDefaults.standard.bool(forKey: "dragEnabled") ? .on : .off
        form.addSubview(dragCheck)
        y -= 28
        titlesCheck.frame = NSRect(x: 20, y: y, width: 260, height: 22)
        titlesCheck.state = UserDefaults.standard.object(forKey: "showPaneTitles") as? Bool == false ? .off : .on
        form.addSubview(titlesCheck)
        y -= 30
        label("Gap between terminals (0–24 pt)")
        paneGap.frame = NSRect(x: 270, y: y, width: 210, height: 23)
        paneGap.stringValue = String(Int(PaneLayout.gap))
        form.addSubview(paneGap)
        y -= 30
        label("Terminal corner radius")
        cornerSlider.frame = NSRect(x: 270, y: y, width: 165, height: 23)
        cornerSlider.minValue = 0
        cornerSlider.maxValue = 24
        cornerSlider.doubleValue = Double(initialCornerRadius)
        cornerSlider.isContinuous = true
        cornerSlider.identifier = NSUserInterfaceItemIdentifier("tile.cornerRadius")
        cornerSlider.target = self
        cornerSlider.action = #selector(previewCornerRadius(_:))
        form.addSubview(cornerSlider)
        cornerValue.frame = NSRect(x: 442, y: y, width: 45, height: 22)
        cornerValue.stringValue = "\(Int(initialCornerRadius)) pt"
        form.addSubview(cornerValue)
        y -= 30
        transparentGapsCheck.frame = NSRect(x: 20, y: y, width: 320, height: 22)
        transparentGapsCheck.state = PaneLayout.transparentGaps ? .on : .off
        form.addSubview(transparentGapsCheck)
        y -= 30
        label("Terminal colors")
        themePicker.frame = NSRect(x: 270, y: y, width: 210, height: 25)
        for theme in TerminalTheme.allCases { themePicker.addItem(withTitle: theme.name) }
        themePicker.selectItem(at: TerminalTheme.allCases.firstIndex(of: .current) ?? 0)
        form.addSubview(themePicker)
        y -= 30
        label("Font size")
        fontSize.frame = NSRect(x: 270, y: y, width: 210, height: 23)
        fontSize.stringValue = String(UserDefaults.standard.object(forKey: "fontSize") as? Int ?? 13)
        form.addSubview(fontSize)
        y -= 30
        label("Shell path")
        shellPath.frame = NSRect(x: 270, y: y, width: 210, height: 23)
        shellPath.stringValue = UserDefaults.standard.string(forKey: "shellPath") ?? (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        form.addSubview(shellPath)
        y -= 38
        label("Agent monitoring (new CLI sessions)", width: 470)
        y -= 28
        for (provider, check) in [(AgentProvider.claude, claudeAgentCheck), (.codex, codexAgentCheck), (.gemini, geminiAgentCheck)] {
            check.frame = NSRect(x: 20, y: y, width: 300, height: 22)
            check.state = AgentIntegrations.isEnabled(provider) ? .on : .off
            form.addSubview(check)
            y -= 27
        }
        label("Codex also requires reviewing Tile hooks with /hooks in Codex.", width: 470)
        y -= 26
        y -= 8
        label("Agent notifications", width: 470)
        y -= 28
        for (key, name) in notificationChecks {
            let check = NSButton(checkboxWithTitle: name, target: nil, action: nil)
            check.frame = NSRect(x: 20, y: y, width: 300, height: 22)
            check.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
            form.addSubview(check)
            notificationButtons[key] = check
            y -= 27
        }
        y -= 15
        label("Keyboard shortcuts (cmd, ctrl, option, shift)", width: 470)
        y -= 30
        for action in TileAction.allCases {
            label(action.title)
            let field = NSTextField(frame: NSRect(x: 270, y: y, width: 210, height: 23))
            field.stringValue = action.shortcut
            form.addSubview(field)
            shortcutFields[action] = field
            y -= 31
        }
        let save = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        save.frame = NSRect(x: 390, y: max(10, y - 14), width: 90, height: 28)
        form.addSubview(save)
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    @objc private func previewCornerRadius(_ sender: NSSlider) {
        let radius = Int(sender.doubleValue.rounded())
        cornerValue.stringValue = "\(radius) pt"
        onCornerPreview?(CGFloat(radius))
    }
    func windowWillClose(_ notification: Notification) {
        if !saved { onCornerPreview?(initialCornerRadius) }
    }
    @objc private func saveSettings() {
        var values: [TileAction: String] = [:]
        for (action, field) in shortcutFields {
            guard let normalized = Shortcuts.normalized(field.stringValue), normalized.contains("+") else {
                showError("Enter a shortcut with a modifier for \(action.title).")
                return
            }
            values[action] = normalized
        }
        guard Set(values.values).count == values.count else { showError("Each shortcut must be unique."); return }
        guard !values.values.contains("cmd+q") else { showError("Command-Q is reserved for Quit Tile."); return }
        guard let global = values[.raiseWindow], GlobalHotKey.supports(global) else {
            showError("Choose a supported key for the app-wide shortcut.")
            return
        }
        guard let size = Int(fontSize.stringValue), (9...36).contains(size) else { showError("Font size must be 9–36."); return }
        guard let gap = Int(paneGap.stringValue), (0...24).contains(gap) else { showError("Terminal gap must be 0–24 points."); return }
        guard FileManager.default.isExecutableFile(atPath: shellPath.stringValue) else { showError("Shell path must be executable."); return }
        for (provider, check) in [(AgentProvider.claude, claudeAgentCheck), (.codex, codexAgentCheck), (.gemini, geminiAgentCheck)] {
            let wanted = check.state == .on
            guard wanted != AgentIntegrations.isEnabled(provider) else { continue }
            do { try AgentIntegrations.setEnabled(wanted, for: provider) }
            catch { showError(error.localizedDescription); return }
        }
        let defaults = UserDefaults.standard
        for (key, _) in notificationChecks { defaults.set(notificationButtons[key]?.state == .on, forKey: key) }
        if Bundle.main.bundleURL.pathExtension == "app",
           notificationChecks.contains(where: { notificationButtons[$0.0]?.state == .on }) {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
        defaults.set(dragCheck.state == .on, forKey: "dragEnabled")
        defaults.set(titlesCheck.state == .on, forKey: "showPaneTitles")
        defaults.set(size, forKey: "fontSize")
        defaults.set(gap, forKey: "paneGap")
        defaults.set(Int(cornerSlider.doubleValue.rounded()), forKey: "paneCornerRadius")
        defaults.set(transparentGapsCheck.state == .on, forKey: "transparentPaneGaps")
        defaults.set(TerminalTheme.allCases[themePicker.indexOfSelectedItem].rawValue, forKey: "terminalTheme")
        defaults.set(shellPath.stringValue, forKey: "shellPath")
        for (action, value) in values { defaults.set(value, forKey: "shortcut.\(action.rawValue)") }
        saved = true
        onSave?()
        close()
    }
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
