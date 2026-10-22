import AppKit

struct WorkspaceSnapshot: Codable {
    struct Pane: Codable { let id: UUID; let directory: String; let customTitle: String? }
    struct Group: Codable {
        let id: UUID
        let panes: [Pane]
        let topRatio: Double?
        let bottomRatio: Double?
        let rowRatio: Double?
    }
    struct Window: Codable {
        let id: UUID
        let frame: String
        let selectedWorkspace: Int
        let workspaces: [Group]
    }
    let windows: [Window]
}

@MainActor
extension TileApp {
    func saveWorkspace() {
        guard !isRestoringWorkspace else { return }
        let snapshot = WorkspaceSnapshot(windows: windows.compactMap { controller in
            guard let frame = controller.frameForRestoration else { return nil }
            let groups = controller.workspaces.map { workspace in
                WorkspaceSnapshot.Group(id: workspace.id, panes: workspace.panes.map { session in
                    session.refreshDirectory()
                    return WorkspaceSnapshot.Pane(id: session.id, directory: session.directory, customTitle: session.customTitle)
                }, topRatio: Double(workspace.topRatio), bottomRatio: Double(workspace.bottomRatio), rowRatio: Double(workspace.rowRatio))
            }
            return WorkspaceSnapshot.Window(id: controller.id, frame: NSStringFromRect(frame), selectedWorkspace: controller.selectedWorkspace, workspaces: groups)
        })
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: "workspaceSnapshot") }
    }

    func restoreWorkspace() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: "workspaceSnapshot"),
              let snapshot = try? JSONDecoder().decode(WorkspaceSnapshot.self, from: data),
              !snapshot.windows.isEmpty else { return false }
        isRestoringWorkspace = true
        for saved in snapshot.windows {
            let groups = saved.workspaces.map { group in
                let workspace = Workspace(id: group.id, panes: group.panes.map { pane in
                    let session = TerminalSession(id: pane.id, directory: pane.directory)
                    session.customTitle = pane.customTitle
                    return session
                })
                workspace.topRatio = CGFloat(group.topRatio ?? 0.5)
                workspace.bottomRatio = CGFloat(group.bottomRatio ?? 0.5)
                workspace.rowRatio = CGFloat(group.rowRatio ?? 0.5)
                return workspace
            }
            let controller = TileWindow(id: saved.id, workspaces: groups, owner: self)
            windows.append(controller)
            controller.selectedWorkspace = min(max(saved.selectedWorkspace, 0), controller.workspaces.count - 1)
            controller.selectedPane = controller.workspace.panes.first?.id
            controller.render()
            let frame = NSRectFromString(saved.frame)
            if !frame.isEmpty { controller.window?.setFrame(TileWindow.reachableFrame(frame, screens: NSScreen.screens.map(\.visibleFrame)), display: true) }
            lastWindow = controller
        }
        lastWindow?.window?.makeKeyAndOrderFront(nil)
        isRestoringWorkspace = false
        saveWorkspace()
        return true
    }
}
