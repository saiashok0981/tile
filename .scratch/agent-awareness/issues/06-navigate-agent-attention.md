# 06: Navigate agent attention with shortcuts

**What to build:** A keyboard user can cycle deterministically through agents needing attention in the active workspace and return to the exact pane they were using before the jump.

**Blocked by:** 05: Open the workspace agent overview and attention queue.

**Status:** ready-for-agent

- [ ] Settings exposes configurable, collision-free defaults for Next agent needing attention and Return to previous pane.
- [ ] Next cycles through the current queue in a stable order, activates the owning window and workspace, and focuses its terminal.
- [ ] Return restores the prior live window, workspace, and pane; if that pane was closed, the action fails safely without selecting a different session.
- [ ] Checks cover several attention items, pane moves, workspace changes, and a queue that changes between key presses.

