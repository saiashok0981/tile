# Tile

Tile is an open-source macOS terminal workspace. It keeps up to four live shells visible per workspace and lets you move a terminal between windows without restarting its process.

Download the current Apple Silicon preview from the [Tile website on GitHub Pages](https://saiashok0981.github.io/tile/). It is not yet Developer ID signed or notarized, so macOS may block it on first launch.

The installable ZIP is also available in the [GitHub preview release](https://github.com/saiashok0981/tile/releases/tag/v0.1.0-preview.1).

## Build

Requires an Apple Silicon Mac, macOS 15 or later, and Swift 6.2 or later with the macOS command line tools. Run:

```sh
./scripts/build-app.sh
```

The script builds `dist/Tile.app` and `dist/Tile-macOS-arm64.zip`. It uses an ad hoc signature for local use; a public distribution needs Developer ID signing and notarization.

## Use

- Click **+** or press `Command-N` to add a terminal. The fifth pane starts another numbered workspace.
- The active workspace has a `▸` marker. Click a workspace number, or use `Command-Option-Left/Right` to switch. `Command-1` through `4` selects workspaces 1–4; `Command-Option-5` through `9` selects workspaces 5–9.
- Use `Option-Arrow` to focus an adjacent terminal. At an edge, focus stays in the current pane. These defaults take over `Option-Left/Right` word movement inside terminals; change them in Settings if you prefer word movement.
- Drag a pane by its header to rearrange it, move it into another Tile window, or make a new window on another monitor.
- Click the pencil in a pane header, double-click the header, or press `Command-Shift-R` to name the selected terminal. An empty name restores the terminal-provided title. Names are restored after relaunch.
- Press `Command-Shift-Return` to return input to the selected terminal, or `Command-Shift-W` to close it. A running command still requires confirmation. Open **Help → Keyboard Shortcuts** for the current bindings.
- A green border marks a pane while a command is running. This includes AI agents and other foreground commands; it does not attempt to identify the type of command.
- Click **Focus** or press `Command-Shift-F` to expand a pane. Escape restores the split layout.
- Click the green window button or press `Control-Command-F` to fill the display while staying on the desktop. Transparent pane gaps show the wallpaper or windows behind Tile. Click **Exit Full Screen**, press `Control-Command-F`, or press Escape to restore the window.
- Open **⚙** to change shortcuts, shell path, font size, the gap between panes, pane-title visibility, drag behavior, and terminal colors. Enable **Transparent gaps between terminals** to see through only the interior spaces between panes; the toolbar and outer margins stay solid. New terminals use the Ocean Blue theme by default; Classic Dark is also available.
- The toolbar shows the current weekday, date, and time using your Mac’s local time zone.
- `Command-Option-Space` brings the most recent Tile window forward from another app.

The app restores window and workspace layouts with fresh shells after relaunch. It does not keep commands running after quitting.

## Foundation

Tile embeds [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for terminal emulation and local pseudo-terminal sessions. Its workspace and window code is separate from that library.
