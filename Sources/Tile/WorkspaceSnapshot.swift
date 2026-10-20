import AppKit

struct WorkspaceSnapshot: Codable {
    struct Pane: Codable { let id: UUID; let directory: String }
    struct Group: Codable { let id: UUID; let panes: [Pane] }
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
        let snapshot = WorkspaceSnapshot(windows: windows.compactMap { controller in
            guard let frame = controller.window?.frame else { return nil }
            let groups = controller.workspaces.map { workspace in
                WorkspaceSnapshot.Group(id: workspace.id, panes: workspace.panes.map { session in
                    session.refreshDirectory()
                    return WorkspaceSnapshot.Pane(id: session.id, directory: session.directory)
                })
            }
            return WorkspaceSnapshot.Window(id: controller.id, frame: NSStringFromRect(frame), selectedWorkspace: controller.selectedWorkspace, workspaces: groups)
        })
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: "workspaceSnapshot") }
    }

    func restoreWorkspace() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: "workspaceSnapshot"),
              let snapshot = try? JSONDecoder().decode(WorkspaceSnapshot.self, from: data),
              !snapshot.windows.isEmpty else { return false }
        for saved in snapshot.windows {
            let groups = saved.workspaces.map { group in
                Workspace(id: group.id, panes: group.panes.map { TerminalSession(id: $0.id, directory: $0.directory) })
            }
            let controller = TileWindow(id: saved.id, workspaces: groups, owner: self)
            windows.append(controller)
            controller.selectedWorkspace = min(max(saved.selectedWorkspace, 0), controller.workspaces.count - 1)
            controller.selectedPane = controller.workspace.panes.first?.id
            controller.render()
            let frame = NSRectFromString(saved.frame)
            if !frame.isEmpty { controller.window?.setFrame(frame, display: true) }
            lastWindow = controller
        }
        lastWindow?.window?.makeKeyAndOrderFront(nil)
        return true
    }
}
