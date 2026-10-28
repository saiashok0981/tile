# Tile work for the next session

Source: `PRT.md` and the codebase audit. Tickets 1–4 are implemented. The items below are deferred until the next session; they are not approval to implement them now.

## Agent awareness tickets 01–12

Status checked 23 October 2026. The implementation is in the current branch. See [`docs/agent-integration-matrix.md`](docs/agent-integration-matrix.md) for provider versions, live results, commands, and limitations.

### Implemented

- [x] **01 — Link agent events to live panes.** Versioned local socket, shell token, pane/session matching, stale state, and malformed or unlinked event handling.
- [x] **02 — Claude Code status.** Opt-in hooks, approval/question/failure/completion mapping, deduplication, and status-line forwarding. Local fixtures pass; live Claude verification is pending because Claude Code is signed out.
- [x] **03 — Codex CLI status.** Opt-in hooks and supported state mapping. Two authenticated CLI turns in separate Tile panes verified start, completion, session end, distinct pane links, and a pane move. Real permission and failure events remain unobserved.
- [x] **04 — Gemini CLI status implementation.** Opt-in hook mapping and local fixtures exist. Live Gemini checks are deferred at the user's request; Gemini CLI is not installed.
- [x] **05 — Agent overview and attention queue.** Workspace overview, sourced status, attention actions, jumping to the terminal, and dismissal.
- [x] **06 — Attention shortcuts.** Configurable next-attention and return-to-previous-pane shortcuts.
- [x] **07 — Action notifications.** Per-event preferences, foreground suppression, event deduplication, and notification routing.
- [x] **08 — Claude usage.** Status-line metrics and existing status-line forwarding are implemented and fixture-tested; live quota verification awaits Claude sign-in.
- [x] **09 — Tile-managed Codex.** Separate managed app-server UI linked to its Tile pane. A live authenticated turn reached Review; closing the panel cleared its attention item.
- [x] **10 — Managed Codex usage.** A live turn delivered thread token totals and account primary/secondary rate-limit windows.
- [x] **11 — Gemini usage fallback.** Usage and quota show Unavailable until live machine-readable usage is validated.

### Remaining for ticket 12

- [ ] Rerun `swift run Tile --codex-live-test` after the latest assertion changes. The previous two-pane run passed; the final rerun was interrupted before it completed.
- [ ] Run ordinary Codex hooks after reviewing and trusting Tile's hook definitions with `/hooks`. Without that trust, Codex skipped hooks and Tile could not link the session. The authenticated verification used a one-run bypass for the inspected Tile hooks; it did not change stored trust.
- [ ] Capture real Codex CLI approval and failure/interruption events, and real managed-session approval, question, and failure events. Current coverage for these states is fixture/schema-based.
- [ ] Resume Claude live checks after Claude Code is signed in: approval, question, failure, completion, restart, and available quota metrics.
- [ ] Keep Gemini live verification deferred. Do not install or test Gemini as part of the current Codex-only pass.
- [ ] Update the verification matrix with any new live results and keep unsupported states or metrics marked Unknown/Unavailable.
- [ ] After the final verification changes, rerun `./scripts/test.sh` and `./scripts/build-app.sh`.

## Existing Tile feature backlog

Publish the preview release tomorrow after reviewing the current feature set.

### Priority 0

### 5. Make pane dragging opt-in

Blocked by: tickets 2 and 4.

- New installations start with pane dragging disabled.
- Settings clearly enables or disables dragging, and the choice persists across launches.
- An existing saved dragging preference is preserved, including a saved `on` value.
- Core pane tasks remain usable with dragging off.

### Priority 1

### 6. Verify independent Tile windows

Blocked by: none.

- Separate windows can show different active workspaces and layouts at the same time.
- Switching or arranging one window does not change another window's workspace state.
- Moving a window between monitors does not merge, overwrite, or duplicate its state.

### 7. Keep restored windows reachable after monitor changes

Blocked by: ticket 6.

- A window saved on a disconnected monitor reopens on an available display.
- Disconnecting or reconnecting a monitor does not duplicate or discard workspaces.
- Restoration behaves predictably across different display arrangements.

### 8. Verify and explain restart restoration

Blocked by: none.

- Relaunch restores supported window, workspace, layout, pane-name, and directory details.
- Restored panes start fresh shells; running processes and their scrollback are not described as restored.
- The user-facing description matches observed behavior and backend capabilities.

### 9. Reopen a recently closed pane

Blocked by: tickets 4 and 8.

- Confirm technical feasibility and define what metadata can be recovered.
- If feasible, offer a keyboard-accessible reopen action that creates a fresh shell with the supported pane details.
- Recovery does not claim to resume the closed process or silently duplicate a live session.

### Priority 2

### 10. Refine Focus mode

Blocked by: ticket 1.

- Entering Focus mode gives the chosen terminal more space and makes exit clear.
- Exiting restores the prior split layout and terminal input focus.
- Escape continues to reach terminal programs outside Focus mode.

### 11. Improve control accessibility and compact layout

Blocked by: tickets 3 and 4.

- Essential icon-only controls have clear accessible names and keyboard access.
- The toolbar and pane controls stay usable in smaller windows.
- Contrast and terminal readability remain sound across available themes and font sizes.

### 12. Review shortcut customisation and conflicts

Blocked by: tickets 2, 3, and 4.

- All completed pane and workspace actions can be customised where appropriate.
- Conflicting or duplicate bindings are handled clearly.
- The shortcut reference, Settings, and actual key handling agree.
