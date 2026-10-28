# 01: Link agent events to live panes

**What to build:** Tile can receive a bounded local agent event, link it to the live terminal pane and shell launch that produced it, and show a sourced status in that pane. Closed panes and fresh shells after restoration cannot inherit an earlier agent's state.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] A versioned local event bridge accepts bounded messages quickly and a missing Tile bridge never blocks the CLI.
- [ ] A shell launch token and generation distinguish live panes, including agents in the same directory and panes moved between workspaces or windows.
- [ ] A synthetic linked event updates pane status with source and last-seen time; terminal command activity remains independent.
- [ ] Unlinked, stale, malformed, or replayed events cannot present a precise live state; restored panes begin Unknown.

# 02: Show Claude Code status in its pane

**What to build:** A user can opt into Claude Code monitoring and see documented approval, question, failure, and turn-completion states in the originating Tile pane, while using the original CLI to respond.

**Blocked by:** 01: Link agent events to live panes.

**Status:** ready-for-agent

- [ ] Tile Settings shows whether Claude Code monitoring is enabled and can enable or disable it without losing unrelated user hooks or an existing status line.
- [ ] Supported Claude events produce sourced pane states; unsupported, missing, or stale signals show Unknown rather than inferred progress.
- [ ] A pending approval or question remains visible until a supported resolution, process exit, or explicit dismissal; completion is labeled as a turn needing review, not verified task success.
- [ ] Fixture and in-pane checks cover an approval, AskUserQuestion, failed turn, completed turn, restart, and Tile being closed.

# 03: Show Codex CLI status in its pane

**What to build:** A user can opt into Codex CLI monitoring and see the states supported by documented hooks for a linked session in its Tile pane. The pane stays Unknown when hooks cannot establish the state.

**Blocked by:** 01: Link agent events to live panes.

**Status:** ready-for-agent

- [ ] Tile Settings can enable or disable the Codex integration while preserving unrelated user configuration.
- [ ] Documented hook events update the linked pane with source and last-seen time, including supported permission, failure or interruption, and turn-end signals.
- [ ] Unsupported question and usage signals remain Unknown or Unavailable; Tile does not infer them from terminal text or transcript files.
- [ ] Fixture and in-pane checks cover supported states, duplicate delivery, session exit, and a missing Tile bridge.

# 04: Show Gemini CLI status in its pane

**What to build:** A user can opt into Gemini CLI monitoring and see supported permission, failure, and turn-completion states in the originating Tile pane, with Unknown for states the integration cannot establish.

**Blocked by:** 01: Link agent events to live panes.

**Status:** ready-for-agent

- [ ] Tile Settings can enable or disable the Gemini integration while preserving unrelated user hooks.
- [ ] Documented hook events update the linked pane with source and last-seen time; a permission notification never grants or denies the request.
- [ ] Turn completion is shown as needing review, and streaming model events do not create false completions or unsupported metrics.
- [ ] Fixture and in-pane checks cover permission, failure, completion, restart, and a missing Tile bridge.

# 05: Open the workspace agent overview and attention queue

**What to build:** The active Tile window shows an overview for its active numbered workspace and a queue of unresolved agent actions. A user can inspect each agent's provider, pane, state, source, and freshness, then jump to the original terminal.

**Blocked by:** 02: Show Claude Code status in its pane.

**Status:** ready-for-agent

- [ ] The overview counts only agents in the active numbered workspace of the active window; pane status stays visible wherever its pane appears.
- [ ] The queue orders approval, question, failure, then completed-needs-review and has one row per unresolved action.
- [ ] Jump activates and focuses the owning window, workspace, and live terminal pane, including after a pane moves.
- [ ] Reviewed or dismissed completion items leave the queue; stale data shows Unknown, and all badges and counts derive from the same snapshot.

# 06: Navigate agent attention with shortcuts

**What to build:** A keyboard user can cycle deterministically through agents needing attention in the active workspace and return to the exact pane they were using before the jump.

**Blocked by:** 05: Open the workspace agent overview and attention queue.

**Status:** ready-for-agent

- [ ] Settings exposes configurable, collision-free defaults for Next agent needing attention and Return to previous pane.
- [ ] Next cycles through the current queue in a stable order, activates the owning window and workspace, and focuses its terminal.
- [ ] Return restores the prior live window, workspace, and pane; if that pane was closed, the action fails safely without selecting a different session.
- [ ] Checks cover several attention items, pane moves, workspace changes, and a queue that changes between key presses.

# 07: Notify once per actionable event

**What to build:** A user receives quiet routine updates and stronger optional alerts for new approvals, questions, or failures. Each action alerts once, and selecting an alert returns to its Tile pane.

**Blocked by:** 05: Open the workspace agent overview and attention queue.

**Status:** ready-for-agent

- [ ] Settings exposes per-event notification preferences; foreground state and macOS notification behavior are respected.
- [ ] Alerts fire from new attention-item transitions, not repeated rendering or polling, and clicking an alert focuses the owning live pane.
- [ ] Replayed events, retries, and Claude permission request plus delayed permission notification produce one actionable alert.
- [ ] A resolved action can alert again on a genuinely new turn; checks cover back-to-back turns, foreground and background Tile, and Do Not Disturb.

# 08: Show Claude usage and quota with provenance

**What to build:** A user with an eligible Claude Code session can see reliable quota windows and estimated session cost beside that agent, with clear source, units, scope, and sample time.

**Blocked by:** 02: Show Claude Code status in its pane.

**Status:** ready-for-agent

- [ ] Available five-hour and seven-day windows show used and remaining percentages and provider reset times; absent or stale windows show Unavailable.
- [ ] Estimated cumulative session cost is labeled as an estimate, never an additional subscription bill, and context-window tokens are not labeled session totals.
- [ ] Existing Claude status-line output is preserved when Tile monitoring is enabled, disabled, or unable to connect.
- [ ] Checks cover eligible and ineligible sessions, partial fields, reset changes, stale samples, and an existing user status line.

# 09: Link Tile-managed Codex sessions

**What to build:** A user can start a deliberately Tile-managed Codex session in a terminal pane and see that session's documented app-server status linked to the pane. Ordinary interactive Codex CLI sessions continue using hooks.

**Blocked by:** 03: Show Codex CLI status in its pane.

**Status:** ready-for-agent

- [ ] Managed-session ownership and pane linkage are explicit, survive pane moves, and end when the owning process or pane exits.
- [ ] Documented app-server approval, question, and turn lifecycle signals update only the linked managed session; requests are answered in the original CLI or supported managed surface.
- [ ] Existing unmanaged CLI sessions are not claimed by the app-server integration and retain their supported hooks status.
- [ ] An in-pane managed-session check covers linking, approval or question, completion, restart, and missing app-server data.

# 10: Show managed Codex usage and quota

**What to build:** A user with a linked Tile-managed Codex session can inspect sourced thread token usage and available ChatGPT Codex rate-limit windows without confusing account metrics with session metrics.

**Blocked by:** 09: Link Tile-managed Codex sessions.

**Status:** ready-for-agent

- [ ] Thread token updates display the correct scope and handle replay, resets, and repeated updates without double counting.
- [ ] Available account rate-limit windows show used or remaining percentage and reset time with account scope, source, and freshness.
- [ ] Hooks-only or unsupported sessions show Unavailable rather than zero; account usage is never labeled session usage.
- [ ] Checks cover missing fields, subscription and API modes, stale data, reset boundaries, and model changes.

# 11: Show validated Gemini usage

**What to build:** A Gemini CLI user can see a clearly scoped token metric only when emitted usage data has been verified against streaming behavior. Otherwise usage and quota read Unavailable.

**Blocked by:** 04: Show Gemini CLI status in its pane.

**Status:** ready-for-agent

- [ ] Real Gemini payloads establish whether streaming usage values are cumulative or incremental before Tile aggregates them.
- [ ] Any displayed metric names its provider, scope, units, source, and sample time; repeated chunks and model changes cannot inflate totals.
- [ ] No subscription quota or USD cost appears without a documented machine-readable source and valid pricing basis.
- [ ] Checks cover missing metadata, repeated chunks, changed models, stale samples, and the Unavailable fallback.

# 12: Verify the three provider workflows end to end

**What to build:** Users and contributors can see which agent states and metrics Tile reliably supports for the installed Claude Code, Codex, and Gemini CLI versions, verified through real sessions in Tile panes.

**Blocked by:** 02: Show Claude Code status in its pane; 03: Show Codex CLI status in its pane; 04: Show Gemini CLI status in its pane; 05: Open the workspace agent overview and attention queue; 07: Notify once per actionable event; 08: Show Claude usage and quota with provenance; 10: Show managed Codex usage and quota; 11: Show validated Gemini usage.

**Status:** ready-for-agent

- [ ] A compatibility matrix records installed provider versions and verified support for approval, question, failure, turn completion, session exit, and available metrics.
- [ ] Real Tile-pane checks cover restart, stale data, duplicate signals, two agents in one directory, pane moves, and missing bridges.
- [ ] Unsupported behavior is recorded as Unknown or Unavailable in Tile and in the matrix; completion never claims the task was verified.
- [ ] Any gap between documented schemas and observed payloads is captured with a reproducible case and addressed or explicitly scoped out.
