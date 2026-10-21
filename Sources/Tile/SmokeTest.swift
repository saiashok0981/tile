import AppKit

@MainActor
func viewDescendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(viewDescendants)
}

@MainActor
func runInputFocusTest() -> Bool {
    let defaults = UserDefaults.standard
    let previousSnapshot = defaults.data(forKey: "workspaceSnapshot")
    defer { defaults.set(previousSnapshot, forKey: "workspaceSnapshot") }
    let app = TileApp()
    app.newWindow()
    let controller = app.windows[0]
    defer {
        controller.allowClose = true
        controller.allSessions.forEach { $0.view.terminate() }
        controller.window?.close()
    }
    var passed = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        guard let root = controller.window?.contentView,
              let first = controller.currentSession else { NSApp.stop(nil); return }
        @MainActor func hasFocusCue(_ session: TerminalSession) -> Bool {
            guard let pane = viewDescendants(root).compactMap({ $0 as? PaneView }).first(where: { $0.session === session }) else { return false }
            return viewDescendants(pane).contains { $0.identifier?.rawValue == "tile.inputFocusIndicator" && !$0.isHidden }
        }
        guard controller.window?.isKeyWindow == true,
              controller.window?.firstResponder === first.view,
              hasFocusCue(first) else {
            fputs("Initial terminal input focus is not visible\n", stderr)
            NSApp.stop(nil)
            return
        }
        app.addPane(to: controller)
        guard let second = controller.currentSession,
              controller.window?.firstResponder === second.view,
              hasFocusCue(second), !hasFocusCue(first) else {
            fputs("New terminal input focus cue did not follow input\n", stderr)
            NSApp.stop(nil)
            return
        }
        _ = controller.window?.makeFirstResponder(first.view)
        guard hasFocusCue(first), !hasFocusCue(second) else {
            fputs("Terminal input focus cue did not follow responder change\n", stderr)
            NSApp.stop(nil)
            return
        }
        _ = controller.window?.makeFirstResponder(nil)
        guard !hasFocusCue(first), !hasFocusCue(second) else {
            fputs("Terminal input focus cue stayed active outside terminal input\n", stderr)
            NSApp.stop(nil)
            return
        }
        _ = controller.window?.makeFirstResponder(second.view)
        controller.close(second)
        guard controller.window?.firstResponder === first.view, hasFocusCue(first) else {
            fputs("Closing the active terminal did not focus the remaining terminal\n", stderr)
            NSApp.stop(nil)
            return
        }
        passed = true
        NSApp.stop(nil)
    }
    NSApp.run()
    if passed { print("Input focus check passed") }
    return passed
}

@MainActor
func runFourPaneLayoutTest() -> Bool {
    _ = NSApplication.shared
    let defaults = UserDefaults.standard
    let previousGap = defaults.object(forKey: "paneGap")
    let previousTransparency = defaults.object(forKey: "transparentPaneGaps")
    let previousRadius = defaults.object(forKey: "paneCornerRadius")
    let previousSnapshot = defaults.data(forKey: "workspaceSnapshot")
    defaults.set(16, forKey: "paneGap")
    defaults.set(true, forKey: "transparentPaneGaps")
    defaults.set(0, forKey: "paneCornerRadius")
    defer {
        defaults.set(previousGap, forKey: "paneGap")
        defaults.set(previousTransparency, forKey: "transparentPaneGaps")
        defaults.set(previousRadius, forKey: "paneCornerRadius")
        defaults.set(previousSnapshot, forKey: "workspaceSnapshot")
    }
    let app = TileApp()
    app.newWindow()
    let controller = app.windows[0]
    defer {
        controller.allowClose = true
        controller.allSessions.forEach { $0.view.terminate() }
        controller.window?.close()
    }
    guard let root = controller.window?.contentView as? TileRootView,
          let plus = viewDescendants(root).compactMap({ $0 as? NSButton }).first(where: { $0.title == "+" }),
          let settings = viewDescendants(root).compactMap({ $0 as? NSButton }).first(where: { $0.title == "⚙" }),
          let brand = viewDescendants(root).compactMap({ $0 as? TileBrandView }).first(where: { $0.identifier?.rawValue == "tile.brand" }),
          let tabs = viewDescendants(root).compactMap({ $0 as? NSStackView }).first(where: { $0.identifier?.rawValue == "tile.workspaceTabs" }),
          let clock = viewDescendants(root).compactMap({ $0 as? NSTextField }).first(where: { $0.identifier?.rawValue == "tile.clock" }) else {
        fputs("Four-pane check: toolbar control or logo is missing\n", stderr)
        return false
    }
    guard (controller.window?.backgroundColor.alphaComponent ?? 1) <= 0.02 else {
        fputs("Normal-sized window lost clear pane gaps\n", stderr)
        return false
    }
    controller.window?.setContentSize(NSSize(width: 1600, height: 900))
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    root.layoutSubtreeIfNeeded()
    let settingsFrame = settings.convert(settings.bounds, to: root)
    let brandFrame = brand.convert(brand.bounds, to: root)
    let tabsFrame = tabs.convert(tabs.bounds, to: root)
    let plusFrame = plus.convert(plus.bounds, to: root)
    let clockFrame = clock.convert(clock.bounds, to: root)
    let freeSpaceCenter = (tabsFrame.maxX + plusFrame.minX) / 2
    guard settingsFrame.maxX >= root.bounds.maxX - 20,
          brandFrame.width >= 70,
          brandFrame.minX >= 0,
          abs(clockFrame.midX - freeSpaceCenter) < 2,
          TileBrand.image.size.width > 0,
          [TileClock.label(for: Date()), TileClock.label(for: Date().addingTimeInterval(-60))].contains(clock.stringValue) else {
        fputs("Wide-window toolbar alignment failed: settings at \(settingsFrame.maxX), edge \(root.bounds.maxX), clock center \(clockFrame.midX), free-space center \(freeSpaceCenter)\n", stderr)
        return false
    }
    plus.performClick(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let firstFrames = viewDescendants(root).compactMap { $0 as? SelectableTerminalView }.map { $0.convert($0.bounds, to: nil) }
    guard firstFrames.count == 2,
          firstFrames.allSatisfy({ $0.width > 100 && $0.height > 100 }),
          firstFrames[0].intersection(firstFrames[1]).isEmpty else {
        fputs("Two-pane check failed: frames \(firstFrames)\n", stderr)
        return false
    }
    for _ in 0..<2 { plus.performClick(nil) }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let terminals = viewDescendants(root).compactMap { $0 as? SelectableTerminalView }
    let frames = terminals.map { $0.convert($0.bounds, to: nil) }
    let paneFrames = viewDescendants(root).compactMap { $0 as? PaneView }.map { $0.convert($0.bounds, to: nil) }
    let gapSurfaces = viewDescendants(root).compactMap { $0 as? DropSurface }
    let interiorGaps = root.interiorGapRects()
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(root.bounds.width), pixelsHigh: Int(root.bounds.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        fputs("Could not render the gap transparency check\n", stderr)
        return false
    }
    root.cacheDisplay(in: root.bounds, to: bitmap)
    let interiorPoint = interiorGaps.first.map { NSPoint(x: $0.midX, y: $0.midY) } ?? .zero
    let gapAlpha = bitmap.colorAt(x: Int(interiorPoint.x), y: Int(interiorPoint.y))?.alphaComponent ?? 1
    let outerAlpha = bitmap.colorAt(x: 2, y: Int(interiorPoint.y))?.alphaComponent ?? 0
    guard terminals.count == 4,
          paneFrames.count == 4,
          interiorGaps.count == 3,
          gapAlpha < 0.05,
          outerAlpha > 0.95,
          interiorGaps.allSatisfy({ $0.minX >= paneFrames.map(\.minX).min()! && $0.maxX <= paneFrames.map(\.maxX).max()! }),
          interiorGaps.allSatisfy({ $0.minY >= paneFrames.map(\.minY).min()! && $0.maxY <= paneFrames.map(\.maxY).max()! }),
          controller.window?.isOpaque == false,
          gapSurfaces.allSatisfy({ ($0.layer?.backgroundColor?.alpha ?? 0) == 0 }),
          paneFrames[1].minX - paneFrames[0].maxX >= 14,
          paneFrames[0].minY - paneFrames[2].maxY >= 14,
          frames.allSatisfy({ $0.width > 100 && $0.height > 100 }),
          frames.allSatisfy({ root.bounds.contains($0) }),
          (0..<4).allSatisfy({ i in
              ((i + 1)..<4).allSatisfy { j in frames[i].intersection(frames[j]).isEmpty }
          }) else {
        fputs("Four-pane check failed: \(terminals.count) views, frames \(frames)\n", stderr)
        return false
    }
    controller.window?.setContentSize(NSSize(width: 1200, height: 760))
    controller.window?.center()
    guard let screen = controller.window?.screen, let normalFrame = controller.window?.frame else {
        fputs("No screen for desktop full-screen check\n", stderr)
        return false
    }
    let presentationOptions = NSApp.presentationOptions
    let shellPIDs = controller.allSessions.map { $0.view.process.shellPid }
    guard controller.window?.standardWindowButton(.zoomButton)?.action == #selector(TileWindow.toggleDesktopFullScreen) else {
        fputs("Green window button is not connected to desktop full screen\n", stderr)
        return false
    }
    controller.window?.toggleFullScreen(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    let savedFrame = UserDefaults.standard.data(forKey: "workspaceSnapshot")
        .flatMap { try? JSONDecoder().decode(WorkspaceSnapshot.self, from: $0) }?
        .windows.first?.frame
    guard controller.isDesktopFullScreen,
          controller.window?.frame == screen.frame,
          controller.window?.styleMask.contains(.fullScreen) == false,
          controller.window?.styleMask.contains(.titled) == false,
          (controller.window?.backgroundColor.alphaComponent ?? 1) <= 0.02,
          NSApp.presentationOptions.contains([.autoHideMenuBar, .autoHideDock]),
          savedFrame == NSStringFromRect(normalFrame),
          controller.allSessions.map({ $0.view.process.shellPid }) == shellPIDs else {
        fputs("Wallpaper-visible full-screen mode failed\n", stderr)
        return false
    }
    controller.window?.toggleFullScreen(nil)
    guard !controller.isDesktopFullScreen,
          controller.window?.frame == normalFrame,
          controller.window?.styleMask.contains(.titled) == true,
          controller.window?.standardWindowButton(.zoomButton)?.action == #selector(TileWindow.toggleDesktopFullScreen),
          NSApp.presentationOptions == presentationOptions else {
        fputs("Leaving wallpaper-visible full-screen mode failed: active \(controller.isDesktopFullScreen), frame \(String(describing: controller.window?.frame)), original \(normalFrame), titled \(String(describing: controller.window?.styleMask.contains(.titled))), presentation \(NSApp.presentationOptions)\n", stderr)
        return false
    }
    app.showSettings()
    guard let settingsWindow = NSApp.windows.first(where: { $0.title == "Tile Settings" }),
          let settingsRoot = settingsWindow.contentView,
          let slider = viewDescendants(settingsRoot).compactMap({ $0 as? NSSlider }).first(where: { $0.identifier?.rawValue == "tile.cornerRadius" }) else {
        fputs("Corner radius slider is missing\n", stderr)
        return false
    }
    slider.doubleValue = 16
    _ = NSApp.sendAction(slider.action!, to: slider.target, from: slider)
    guard viewDescendants(root).compactMap({ $0 as? PaneView }).allSatisfy({ $0.layer?.cornerRadius == 16 && $0.layer?.masksToBounds == true }) else {
        fputs("Corner radius live preview failed\n", stderr)
        return false
    }
    settingsWindow.close()
    guard viewDescendants(root).compactMap({ $0 as? PaneView }).allSatisfy({ $0.layer?.cornerRadius == 0 }) else {
        fputs("Corner radius cancel preview failed\n", stderr)
        return false
    }
    defaults.set(12, forKey: "paneCornerRadius")
    controller.render()
    root.layoutSubtreeIfNeeded()
    guard viewDescendants(root).compactMap({ $0 as? PaneView }).allSatisfy({ $0.layer?.cornerRadius == 12 }) else {
        fputs("Saved corner radius was not applied to new pane views\n", stderr)
        return false
    }
    UserDefaults.standard.set(false, forKey: "transparentPaneGaps")
    controller.render()
    guard controller.window?.isOpaque == true,
          controller.window?.backgroundColor.alphaComponent == 1 else {
        fputs("Opaque gap setting check failed\n", stderr)
        return false
    }
    print("Four-pane layout check passed: four visible, non-overlapping terminals")
    return true
}

@MainActor
func runSmokeTest() -> Bool {
    let defaults = UserDefaults.standard
    let previousSnapshot = defaults.data(forKey: "workspaceSnapshot")
    let previousTheme = defaults.string(forKey: "terminalTheme")
    defaults.set(TerminalTheme.oceanBlue.rawValue, forKey: "terminalTheme")
    defer {
        defaults.set(previousSnapshot, forKey: "workspaceSnapshot")
        defaults.set(previousTheme, forKey: "terminalTheme")
    }

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
    let blue = session.view.nativeBackgroundColor.usingColorSpace(.deviceRGB)
    guard let blue, blue.blueComponent > blue.redComponent + 0.1 else {
        fputs("Blue terminal theme check failed\n", stderr)
        return false
    }
    defaults.set(TerminalTheme.classicDark.rawValue, forKey: "terminalTheme")
    session.applyTheme()
    let dark = session.view.nativeBackgroundColor.usingColorSpace(.deviceRGB)
    guard let dark, dark.blueComponent < 0.1 else {
        fputs("Terminal theme switching check failed\n", stderr)
        return false
    }
    defaults.set(TerminalTheme.oceanBlue.rawValue, forKey: "terminalTheme")
    session.applyTheme()
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
    if let content = destination.window?.contentView,
       let runningView = viewDescendants(content).compactMap({ $0 as? PaneView }).first(where: { $0.session === runningPane }) {
        runningView.updateActivity()
        guard runningView.layer?.borderWidth == 2 else {
            fputs("Running command border check failed\n", stderr)
            return false
        }
    } else {
        fputs("Running pane view missing\n", stderr)
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
    runningPane.customTitle = "dev api"
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
          restored.windows[1].allSessions.contains(where: { $0.customTitle == "dev api" }),
          restored.windows[1].allSessions.contains(where: { $0.directory == "/private/tmp" }),
          restored.windows[1].allSessions.allSatisfy({ $0.view.process.running }) else {
        fputs("Restored window or shell check failed\n", stderr)
        return false
    }
    print("Tile smoke test passed: overflow, live move, directory inheritance, focus, workspace movement, command detection, and restoration")
    return true
}
