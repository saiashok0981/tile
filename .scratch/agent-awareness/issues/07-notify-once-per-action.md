# 07: Notify once per actionable event

**What to build:** A user receives quiet routine updates and stronger optional alerts for new approvals, questions, or failures. Each action alerts once, and selecting an alert returns to its Tile pane.

**Blocked by:** 05: Open the workspace agent overview and attention queue.

**Status:** ready-for-agent

- [ ] Settings exposes per-event notification preferences; foreground state and macOS notification behavior are respected.
- [ ] Alerts fire from new attention-item transitions, not repeated rendering or polling, and clicking an alert focuses the owning live pane.
- [ ] Replayed events, retries, and Claude permission request plus delayed permission notification produce one actionable alert.
- [ ] A resolved action can alert again on a genuinely new turn; checks cover back-to-back turns, foreground and background Tile, and Do Not Disturb.

