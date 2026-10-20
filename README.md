# Tile

Tile is an open-source macOS terminal workspace. It keeps up to four live shells visible per workspace and lets you move a terminal between windows without restarting its process.

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
- Click **Focus** or press `Command-Shift-F` to expand a pane. Escape restores the split layout.
- Open **⚙** to change shortcuts, shell path, font size, pane-title visibility, and drag behavior.
- `Command-Option-Space` brings the most recent Tile window forward from another app.

The app restores window and workspace layouts with fresh shells after relaunch. It does not keep commands running after quitting.

## Foundation

Tile embeds [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for terminal emulation and local pseudo-terminal sessions. Its workspace and window code is separate from that library.
