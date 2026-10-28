# 02: Show Claude Code status in its pane

**What to build:** A user can opt into Claude Code monitoring and see documented approval, question, failure, and turn-completion states in the originating Tile pane, while using the original CLI to respond.

**Blocked by:** 01: Link agent events to live panes.

**Status:** ready-for-agent

- [ ] Tile Settings shows whether Claude Code monitoring is enabled and can enable or disable it without losing unrelated user hooks or an existing status line.
- [ ] Supported Claude events produce sourced pane states; unsupported, missing, or stale signals show Unknown rather than inferred progress.
- [ ] A pending approval or question remains visible until a supported resolution, process exit, or explicit dismissal; completion is labeled as a turn needing review, not verified task success.
- [ ] Fixture and in-pane checks cover an approval, AskUserQuestion, failed turn, completed turn, restart, and Tile being closed.

