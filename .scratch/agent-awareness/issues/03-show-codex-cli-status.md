# 03: Show Codex CLI status in its pane

**What to build:** A user can opt into Codex CLI monitoring and see the states supported by documented hooks for a linked session in its Tile pane. The pane stays Unknown when hooks cannot establish the state.

**Blocked by:** 01: Link agent events to live panes.

**Status:** ready-for-agent

- [ ] Tile Settings can enable or disable the Codex integration while preserving unrelated user configuration.
- [ ] Documented hook events update the linked pane with source and last-seen time, including supported permission, failure or interruption, and turn-end signals.
- [ ] Unsupported question and usage signals remain Unknown or Unavailable; Tile does not infer them from terminal text or transcript files.
- [ ] Fixture and in-pane checks cover supported states, duplicate delivery, session exit, and a missing Tile bridge.

