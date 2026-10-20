import AppKit

@MainActor
func runSmokeTest() -> Bool {
    let defaults = UserDefaults.standard
    let previousSnapshot = defaults.data(forKey: "workspaceSnapshot")
    defer { defaults.set(previousSnapshot, forKey: "workspaceSnapshot") }

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
    for _ in 0..<4 { app.addPane(to: source) }
    guard source.workspaces.count == 2,
          source.workspaces[0].panes.count == 4,
          source.workspaces[1].panes.count == 1,
          let session = source.currentSession else {
        fputs("Workspace overflow check failed\n", stderr)
        return false
    }
    let pid = session.view.process.shellPid
    guard pid > 0 else { fputs("Shell did not start\n", stderr); return false }
    guard !session.hasRunningCommand else { fputs("Idle shell was marked busy\n", stderr); return false }
    app.newWindow()
    let destination = app.windows[1]
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
          restored.windows[1].allSessions.contains(where: { $0.directory == "/private/tmp" }),
          restored.windows[1].allSessions.allSatisfy({ $0.view.process.running }) else {
        fputs("Restored window or shell check failed\n", stderr)
        return false
    }
    print("Tile smoke test passed: overflow, live move, directory inheritance, focus, workspace movement, command detection, and restoration")
    return true
}
