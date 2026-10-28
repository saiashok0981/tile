import Foundation

enum AgentIntegrationError: LocalizedError {
    case invalidSettings(String)
    case missingExecutable

    var errorDescription: String? {
        switch self {
        case .invalidSettings(let name): "Cannot edit \(name): it is not a JSON settings object."
        case .missingExecutable: "Tile's executable path is unavailable."
        }
    }
}

enum AgentIntegrations {
    static func settingsURL(for provider: AgentProvider, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        switch provider {
        case .claude: home.appending(path: ".claude/settings.json")
        case .codex: home.appending(path: ".codex/hooks.json")
        case .gemini: home.appending(path: ".gemini/settings.json")
        }
    }

    static func isEnabled(_ provider: AgentProvider, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let url = settingsURL(for: provider, home: home)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = object["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { groups in
            guard let groups = groups as? [[String: Any]] else { return false }
            return groups.contains { group in
                guard let commands = group["hooks"] as? [[String: Any]] else { return false }
                return commands.contains { isTileCommand($0, provider: provider) }
            }
        }
    }

    static func setEnabled(_ enabled: Bool, for provider: AgentProvider,
                           home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           executable: String? = Bundle.main.executablePath) throws {
        let url = settingsURL(for: provider, home: home)
        let manager = FileManager.default
        var root: [String: Any] = [:]
        if manager.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AgentIntegrationError.invalidSettings(url.path)
            }
            root = value
        }
        if root["hooks"] != nil && !(root["hooks"] is [String: Any]) {
            throw AgentIntegrationError.invalidSettings(url.path)
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var statusLineBackupToRemove: URL?
        for (event, groups) in hooks {
            guard let groups = groups as? [[String: Any]] else { continue }
            let retained = groups.compactMap { group -> [String: Any]? in
                guard let commands = group["hooks"] as? [[String: Any]] else { return group }
                let others = commands.filter { !isTileCommand($0, provider: provider) }
                guard !others.isEmpty else { return nil }
                var copy = group
                copy["hooks"] = others
                return copy
            }
            if retained.isEmpty { hooks.removeValue(forKey: event) }
            else { hooks[event] = retained }
        }
        if enabled {
            guard let executable else { throw AgentIntegrationError.missingExecutable }
            for event in events(for: provider) {
                let command = "'\(executable.replacingOccurrences(of: "'", with: "'\\''"))' --agent-hook '\(provider.rawValue)' \(event)"
                var handler: [String: Any] = ["type": "command", "command": command, "timeout": provider == .gemini ? 1000 : 1]
                if provider == .gemini { handler["name"] = "tile-agent-\(event.lowercased())" }
                let group: [String: Any] = ["hooks": [handler]]
                var groups = hooks[event] as? [[String: Any]] ?? []
                groups.append(group)
                hooks[event] = groups
            }
            if provider == .claude {
                let original = root["statusLine"] ?? NSNull()
                let backupURL = url.deletingLastPathComponent().appending(path: "tile-statusline-original.json")
                let currentCommand = (original as? [String: Any])?["command"] as? String ?? ""
                let savedOriginal: Any
                if currentCommand.contains("--agent-statusline"),
                   let backup = try? Data(contentsOf: backupURL),
                   let saved = try? JSONSerialization.jsonObject(with: backup) as? [String: Any] {
                    savedOriginal = saved["statusLine"] ?? NSNull()
                } else {
                    savedOriginal = original
                }
                let originalCommand = (savedOriginal as? [String: Any])?["command"] as? String ?? ""
                if !manager.fileExists(atPath: backupURL.path) {
                    let originalData = try JSONSerialization.data(withJSONObject: ["statusLine": savedOriginal])
                    try manager.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try originalData.write(to: backupURL, options: .atomic)
                    try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
                }
                let encoded = Data(originalCommand.utf8).base64EncodedString()
                let command = "'\(executable.replacingOccurrences(of: "'", with: "'\\''"))' --agent-statusline '\(encoded)'"
                var statusLine = original as? [String: Any] ?? [:]
                statusLine["type"] = "command"
                statusLine["command"] = command
                root["statusLine"] = statusLine
            }
        } else if provider == .claude {
            let command = (root["statusLine"] as? [String: Any])?["command"] as? String ?? ""
            let backupURL = url.deletingLastPathComponent().appending(path: "tile-statusline-original.json")
            if command.contains("--agent-statusline"),
               let backup = try? Data(contentsOf: backupURL),
               let saved = try? JSONSerialization.jsonObject(with: backup) as? [String: Any] {
                if var original = saved["statusLine"] as? [String: Any] {
                    let current = root["statusLine"] as? [String: Any] ?? [:]
                    for (key, value) in current where key != "command" && key != "type" {
                        original[key] = value
                    }
                    root["statusLine"] = original
                } else { root.removeValue(forKey: "statusLine") }
                statusLineBackupToRemove = backupURL
            }
        }
        root["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("tile-backup-\(UUID().uuidString)")
            try manager.copyItem(at: url, to: backup)
        }
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        if let statusLineBackupToRemove { try? manager.removeItem(at: statusLineBackupToRemove) }
    }

    private static func events(for provider: AgentProvider) -> [String] {
        switch provider {
        case .claude: ["SessionStart", "UserPromptSubmit", "PermissionRequest", "PreToolUse", "Notification", "PostToolUse", "PostToolUseFailure", "Stop", "StopFailure", "SessionEnd"]
        case .codex: ["SessionStart", "UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop", "Interrupt", "SessionEnd"]
        case .gemini: ["SessionStart", "BeforeAgent", "Notification", "AfterTool", "AfterAgent", "SessionEnd"]
        }
    }

    private static func isTileCommand(_ handler: [String: Any], provider: AgentProvider) -> Bool {
        guard let command = handler["command"] as? String else { return false }
        return command.contains("--agent-hook '\(provider.rawValue)'")
    }
}
