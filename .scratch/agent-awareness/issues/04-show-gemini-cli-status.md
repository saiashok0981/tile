# 04: Show Gemini CLI status in its pane

**What to build:** A user can opt into Gemini CLI monitoring and see supported permission, failure, and turn-completion states in the originating Tile pane, with Unknown for states the integration cannot establish.

**Blocked by:** 01: Link agent events to live panes.

**Status:** ready-for-agent

- [ ] Tile Settings can enable or disable the Gemini integration while preserving unrelated user hooks.
- [ ] Documented hook events update the linked pane with source and last-seen time; a permission notification never grants or denies the request.
- [ ] Turn completion is shown as needing review, and streaming model events do not create false completions or unsupported metrics.
- [ ] Fixture and in-pane checks cover permission, failure, completion, restart, and a missing Tile bridge.

