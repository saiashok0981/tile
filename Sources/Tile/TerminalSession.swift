import AppKit
import SwiftTerm

@MainActor
final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    let id: UUID
    let view: LocalProcessTerminalView
    var directory: String
    var title = "Terminal"
    var onChange: (() -> Void)?

    init(id: UUID = UUID(), directory: String) {
        self.id = id
        self.directory = directory
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        super.init()
        view.processDelegate = self
        let size = UserDefaults.standard.object(forKey: "fontSize") as? Int ?? 13
        view.font = NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
        let shell = UserDefaults.standard.string(forKey: "shellPath") ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        view.startProcess(executable: shell, execName: "-" + URL(fileURLWithPath: shell).lastPathComponent, currentDirectory: directory)
    }

    var hasRunningCommand: Bool {
        guard view.process.running else { return false }
        let shell = view.process.shellPid
        let fd = view.process.childfd
        guard shell > 0, fd >= 0 else { return false }
        let foreground = tcgetpgrp(fd)
        if foreground > 0 && foreground != shell { return true }
        let children = Process()
        children.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        children.arguments = ["-P", String(shell)]
        children.standardOutput = FileHandle.nullDevice
        children.standardError = FileHandle.nullDevice
        guard (try? children.run()) != nil else { return false }
        children.waitUntilExit()
        return children.terminationStatus == 0
    }

    func refreshDirectory() {
        let pid = view.process.shellPid
        guard pid > 0 else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", String(pid), "-d", "cwd", "-Fn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            process.waitUntilExit()
            if let line = output.split(separator: "\n").first(where: { $0.hasPrefix("n/") }) {
                directory = String(line.dropFirst())
            }
        } catch { }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        self.title = title.isEmpty ? "Terminal" : title
        onChange?()
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory else { return }
        if let url = URL(string: directory), url.isFileURL { self.directory = url.path }
        else if directory.hasPrefix("/") { self.directory = directory }
    }
    func processTerminated(source: TerminalView, exitCode: Int32?) { onChange?() }
}
