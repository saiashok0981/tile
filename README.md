# Tile

Tile is an open-source macOS terminal workspace. It keeps up to four live shells visible per workspace and lets you move a terminal between windows without restarting its process.

Download the current Apple Silicon preview at [tile-terminal-workspace.tinyyew1024.chatgpt.site](https://tile-terminal-workspace.tinyyew1024.chatgpt.site). It is not yet Developer ID signed or notarized, so macOS may block it on first launch.

## Build

Requires an Apple Silicon Mac, macOS 15 or later, and Swift 6.2 or later with the macOS command line tools. Run:

```sh
./scripts/build-app.sh
```

The script builds `dist/Tile.app` and `dist/Tile-macOS-arm64.zip`. It uses an ad hoc signature for local use; a public distribution needs Developer ID signing and notarization.

## Use

- Click **+** or press `Command-N` to add a terminal. The fifth pane starts another numbered workspace.
- Click a workspace number, or use `Command-Option-Left/Right` to switch. `Command-Option-1` through `9` selects a numbered workspace.
- Drag a pane by its header to rearrange it, move it into another Tile window, or make a new window on another monitor.
- Click the pencil in a pane header, or double-click the header, to give that terminal a name such as `dev`, `api`, or `codex`. An empty name restores the terminal-provided title. Names are restored after relaunch.
- A green border marks a pane while a command is running. This includes AI agents and other foreground commands; it does not attempt to identify the type of command.
- Click **Focus** or press `Command-Shift-F` to expand a pane. Escape restores the split layout.
- Open **⚙** to change shortcuts, shell path, font size, the gap between panes, pane-title visibility, drag behavior, and terminal colors. Enable **Transparent gaps between terminals** to see through only the interior spaces between panes; the toolbar and outer margins stay solid. New terminals use the Ocean Blue theme by default; Classic Dark is also available.
- The toolbar shows the current weekday, date, and time using your Mac’s local time zone.
- `Command-Option-Space` brings the most recent Tile window forward from another app.

The app restores window and workspace layouts with fresh shells after relaunch. It does not keep commands running after quitting.

## Foundation

Tile embeds [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for terminal emulation and local pseudo-terminal sessions. Its workspace and window code is separate from that library.
