# 08: Show Claude usage and quota with provenance

**What to build:** A user with an eligible Claude Code session can see reliable quota windows and estimated session cost beside that agent, with clear source, units, scope, and sample time.

**Blocked by:** 02: Show Claude Code status in its pane.

**Status:** ready-for-agent

- [ ] Available five-hour and seven-day windows show used and remaining percentages and provider reset times; absent or stale windows show Unavailable.
- [ ] Estimated cumulative session cost is labeled as an estimate, never an additional subscription bill, and context-window tokens are not labeled session totals.
- [ ] Existing Claude status-line output is preserved when Tile monitoring is enabled, disabled, or unable to connect.
- [ ] Checks cover eligible and ineligible sessions, partial fields, reset changes, stale samples, and an existing user status line.

