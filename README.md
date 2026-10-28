# Tile

Tile is an open-source macOS terminal workspace. It keeps up to four live shells visible per workspace and lets you move a terminal between windows without restarting its process.

Download the current Apple Silicon preview from the [Tile website on GitHub Pages](https://saiashok0981.github.io/tile/). It is not yet Developer ID signed or notarized, so macOS may block it on first launch.

The installable ZIP is also available in the [GitHub preview release](https://github.com/saiashok0981/tile/releases/tag/v0.1.0-preview.2).

## Build

Requires an Apple Silicon Mac, macOS 15 or later, and Swift 6.2 or later with the macOS command line tools. Run:

```sh
./scripts/build-app.sh
```

The script builds `dist/Tile.app` and `dist/Tile-macOS-arm64.zip`. It uses an ad hoc signature for local use; a public distribution needs Developer ID signing and notarization.

## Checks

Run `./scripts/test.sh` for the local app checks. Pull requests run those checks, linting, package validation, and security analysis in GitHub Actions. See [CI and local Codex repair](docs/ci.md) for the jobs, evidence artifacts, and local repair steps.

## Use

- Click **+** or press `Command-N` to add a terminal. The fifth pane starts another numbered workspace.
- The active workspace has a `▸` marker. Click a workspace number, or use `Command-Option-Left/Right` to switch. `Command-1` through `4` selects workspaces 1–4; `Command-Option-5` through `9` selects workspaces 5–9.
- Use `Option-Arrow` to focus an adjacent terminal. At an edge, focus stays in the current pane. These defaults take over `Option-Left/Right` word movement inside terminals; change them in Settings if you prefer word movement.
- Dragging starts off on new installations. Select **Enable dragging panes** in Settings to rearrange panes by their headers or move a live terminal between windows. Keyboard navigation and pane actions work with dragging off.
- Click the pencil in a pane header, double-click the header, or press `Command-Shift-R` to name the selected terminal. An empty name restores the terminal-provided title. Names are restored after relaunch.
- Press `Command-Shift-Return` to return input to the selected terminal, or `Command-Shift-W` to close it. A running command still requires confirmation. `Command-Shift-T` reopens the most recently closed pane with a fresh shell, its name, and its directory. Open **Help → Keyboard Shortcuts** for the current bindings.
- A green border marks any running foreground command. If you opt into agent monitoring, a separate pane badge reports Claude Code, Codex, or Gemini CLI status from linked provider events. **Unknown** means Tile has no fresh, reliable status.
- In **⚙ → Agent monitoring**, enable each CLI integration separately. Tile adds only its own hooks to your user settings and saves a backup before changing them. New CLI sessions in Tile panes inherit the link; sessions already running may remain Unknown.
- Codex requires you to review and trust the new Tile hook definitions with `/hooks` inside Codex. Until then, Codex skips them and Tile cannot link that session. Recheck `/hooks` after Tile updates a hook definition.
- **Agents** in the toolbar shows agents and actions in the active numbered workspace. Open it to inspect source and last update, jump to the original terminal, or mark a completed turn reviewed. `Command-Option-A` cycles through actions; `Command-Option-Shift-A` returns to the previous live pane. Change either shortcut in Settings.
- The **Codex** toolbar button opens a separate managed Codex panel for the selected pane. It starts its own app-server session for prompts and approvals; ordinary Codex terminal sessions continue to use hooks. Managed account quota and thread token totals appear when the service provides them.
- Claude Code quota windows and estimated session cost appear when its status-line feed provides them. Tile forwards any status-line command already configured. Missing or stale metrics read **Unavailable**. Gemini usage and quota remain Unavailable until a reliable machine-readable source is validated.
- Agent notifications are optional per event in Settings. macOS controls notification permission and Do Not Disturb.
- Click **Focus** or press `Command-Shift-F` to expand a pane. **Exit Focus** or Escape restores the split layout and terminal input focus.
- Click the green window button or press `Control-Command-F` to fill the display while staying on the desktop. Transparent pane gaps show the wallpaper or windows behind Tile. Click **Exit Full Screen**, press `Control-Command-F`, or press Escape to restore the window.
- Open **⚙** to change shortcuts, shell path, font size, the gap between panes, pane-title visibility, drag behavior, and terminal colors. Enable **Transparent gaps between terminals** to see through only the interior spaces between panes; the toolbar and outer margins stay solid. New terminals use the Ocean Blue theme by default; Classic Dark is also available.
- The toolbar shows the current weekday, date, and time using your Mac’s local time zone.
- `Command-Option-Space` brings the most recent Tile window forward from another app.

The app restores windows, workspaces, pane order, split sizes, pane names, and working directories after relaunch. Each restored pane starts a fresh shell. Running processes and terminal scrollback do not return. Windows saved on a disconnected display reopen on an available display.

## Foundation

Tile embeds [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for terminal emulation and local pseudo-terminal sessions. Its workspace and window code is separate from that library.
