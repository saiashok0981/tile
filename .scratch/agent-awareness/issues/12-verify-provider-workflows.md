# 12: Verify the three provider workflows end to end

**What to build:** Users and contributors can see which agent states and metrics Tile reliably supports for the installed Claude Code, Codex, and Gemini CLI versions, verified through real sessions in Tile panes.

**Blocked by:** 02: Show Claude Code status in its pane; 03: Show Codex CLI status in its pane; 04: Show Gemini CLI status in its pane; 05: Open the workspace agent overview and attention queue; 07: Notify once per actionable event; 08: Show Claude usage and quota with provenance; 10: Show managed Codex usage and quota; 11: Show validated Gemini usage.

**Status:** ready-for-agent

- [ ] A compatibility matrix records installed provider versions and verified support for approval, question, failure, turn completion, session exit, and available metrics.
- [ ] Real Tile-pane checks cover restart, stale data, duplicate signals, two agents in one directory, pane moves, and missing bridges.
- [ ] Unsupported behavior is recorded as Unknown or Unavailable in Tile and in the matrix; completion never claims the task was verified.
- [ ] Any gap between documented schemas and observed payloads is captured with a reproducible case and addressed or explicitly scoped out.
