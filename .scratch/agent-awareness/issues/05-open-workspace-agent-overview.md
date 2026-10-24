# 05: Open the workspace agent overview and attention queue

**What to build:** The active Tile window shows an overview for its active numbered workspace and a queue of unresolved agent actions. A user can inspect each agent's provider, pane, state, source, and freshness, then jump to the original terminal.

**Blocked by:** 02: Show Claude Code status in its pane.

**Status:** ready-for-agent

- [ ] The overview counts only agents in the active numbered workspace of the active window; pane status stays visible wherever its pane appears.
- [ ] The queue orders approval, question, failure, then completed-needs-review and has one row per unresolved action.
- [ ] Jump activates and focuses the owning window, workspace, and live terminal pane, including after a pane moves.
- [ ] Reviewed or dismissed completion items leave the queue; stale data shows Unknown, and all badges and counts derive from the same snapshot.

