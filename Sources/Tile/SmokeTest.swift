import AppKit

@MainActor
func runFourPaneLayoutTest() -> Bool {
    _ = NSApplication.shared
    let app = TileApp()
    app.newWindow()
    let controller = app.windows[0]
    defer {
        controller.allowClose = true
        controller.allSessions.forEach { $0.view.terminate() }
        controller.window?.close()
    }
    func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
    guard let root = controller.window?.contentView,
          let plus = descendants(root).compactMap({ $0 as? NSButton }).first(where: { $0.title == "+" }) else {
        fputs("Four-pane check: plus button is missing\n", stderr)
        return false
    }
    plus.performClick(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let firstFrames = descendants(root).compactMap { $0 as? SelectableTerminalView }.map { $0.convert($0.bounds, to: nil) }
    guard firstFrames.count == 2,
          firstFrames.allSatisfy({ $0.width > 100 && $0.height > 100 }),
          firstFrames[0].intersection(firstFrames[1]).isEmpty else {
        fputs("Two-pane check failed: frames \(firstFrames)\n", stderr)
        return false
    }
    for _ in 0..<2 { plus.performClick(nil) }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let terminals = descendants(root).compactMap { $0 as? SelectableTerminalView }
    let frames = terminals.map { $0.convert($0.bounds, to: nil) }
    guard terminals.count == 4,
          frames.allSatisfy({ $0.width > 100 && $0.height > 100 }),
          frames.allSatisfy({ root.bounds.contains($0) }),
          (0..<4).allSatisfy({ i in
              ((i + 1)..<4).allSatisfy { j in frames[i].intersection(frames[j]).isEmpty }
          }) else {
        fputs("Four-pane check failed: \(terminals.count) views, frames \(frames)\n", stderr)
        return false
    }
    print("Four-pane layout check passed: four visible, non-overlapping terminals")
    return true
}

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
