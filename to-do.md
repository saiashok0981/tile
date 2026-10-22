# Tile work for the next session

Source: `PRT.md` and the codebase audit. Tickets 1–4 are implemented. The items below are deferred until the next session; they are not approval to implement them now.

## Priority 0

### 5. Make pane dragging opt-in

Blocked by: tickets 2 and 4.

- New installations start with pane dragging disabled.
- Settings clearly enables or disables dragging, and the choice persists across launches.
- An existing saved dragging preference is preserved, including a saved `on` value.
- Core pane tasks remain usable with dragging off.

## Priority 1

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

## Priority 2

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
