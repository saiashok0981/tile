# 01: Link agent events to live panes

**What to build:** Tile can receive a bounded local agent event, link it to the live terminal pane and shell launch that produced it, and show a sourced status in that pane. Closed panes and fresh shells after restoration cannot inherit an earlier agent's state.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] A versioned local event bridge accepts bounded messages quickly and a missing Tile bridge never blocks the CLI.
- [ ] A shell launch token and generation distinguish live panes, including agents in the same directory and panes moved between workspaces or windows.
- [ ] A synthetic linked event updates pane status with source and last-seen time; terminal command activity remains independent.
- [ ] Unlinked, stale, malformed, or replayed events cannot present a precise live state; restored panes begin Unknown.

