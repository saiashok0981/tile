# 10: Show managed Codex usage and quota

**What to build:** A user with a linked Tile-managed Codex session can inspect sourced thread token usage and available ChatGPT Codex rate-limit windows without confusing account metrics with session metrics.

**Blocked by:** 09: Link Tile-managed Codex sessions.

**Status:** ready-for-agent

- [ ] Thread token updates display the correct scope and handle replay, resets, and repeated updates without double counting.
- [ ] Available account rate-limit windows show used or remaining percentage and reset time with account scope, source, and freshness.
- [ ] Hooks-only or unsupported sessions show Unavailable rather than zero; account usage is never labeled session usage.
- [ ] Checks cover missing fields, subscription and API modes, stale data, reset boundaries, and model changes.

