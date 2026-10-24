# 11: Show validated Gemini usage

**What to build:** A Gemini CLI user can see a clearly scoped token metric only when emitted usage data has been verified against streaming behavior. Otherwise usage and quota read Unavailable.

**Blocked by:** 04: Show Gemini CLI status in its pane.

**Status:** ready-for-agent

- [ ] Real Gemini payloads establish whether streaming usage values are cumulative or incremental before Tile aggregates them.
- [ ] Any displayed metric names its provider, scope, units, source, and sample time; repeated chunks and model changes cannot inflate totals.
- [ ] No subscription quota or USD cost appears without a documented machine-readable source and valid pricing basis.
- [ ] Checks cover missing metadata, repeated chunks, changed models, stale samples, and the Unavailable fallback.

