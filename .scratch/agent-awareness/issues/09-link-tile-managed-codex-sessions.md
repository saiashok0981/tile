# 09: Link Tile-managed Codex sessions

**What to build:** A user can start a deliberately Tile-managed Codex session in a terminal pane and see that session's documented app-server status linked to the pane. Ordinary interactive Codex CLI sessions continue using hooks.

**Blocked by:** 03: Show Codex CLI status in its pane.

**Status:** ready-for-agent

- [ ] Managed-session ownership and pane linkage are explicit, survive pane moves, and end when the owning process or pane exits.
- [ ] Documented app-server approval, question, and turn lifecycle signals update only the linked managed session; requests are answered in the original CLI or supported managed surface.
- [ ] Existing unmanaged CLI sessions are not claimed by the app-server integration and retain their supported hooks status.
- [ ] An in-pane managed-session check covers linking, approval or question, completion, restart, and missing app-server data.

