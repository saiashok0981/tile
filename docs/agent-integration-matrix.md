# Agent integration verification

Checked 22 October 2026 on the development Mac. Tile links provider events to a live pane token and provider session ID. The green command border is independent of agent state. **Unknown** means no fresh supported status signal; **Unavailable** means no supported fresh metric.

## Installed providers and scope

| Provider | Version and authentication | Live result | Remaining work |
|---|---|---|---|
| Codex CLI | 0.156.1; signed in with ChatGPT | Two authenticated `codex exec` turns completed from separate Tile terminal panes in the same directory. Their hook events linked to distinct panes, including after one pane moved to another Tile window. | User must review and trust Tile hooks with `/hooks` for ordinary Codex launches. A real CLI permission request or failure was not produced. CLI question and usage are unsupported by Tile's hooks-only integration. |
| Tile-managed Codex | Same CLI and account | An authenticated app-server turn reached Review in its linked Tile pane. Thread total tokens and account primary and secondary rate-limit windows arrived. Closing the managed panel cleared its attention item. | Real approval, question, and failure requests were not produced in this check. |
| Claude Code | 2.1.304; `claude auth status` reported logged out | Local hook and status-line fixtures pass. | Live provider checks await sign-in. The user chose to continue with Codex only for now. |
| Gemini CLI | Not installed | Local permission fixture passes. | Deferred at the user's request. Usage and quota remain Unavailable. |

## Codex state and metric coverage

| Signal | Ordinary Codex CLI pane | Tile-managed Codex panel |
|---|---|---|
| Start / working | Verified: `SessionStart` and `UserPromptSubmit` each sent a start event for a live turn. | Verified by app-server thread and turn lifecycle. |
| Approval | Hook fixture passes; no real request observed. | Handler implemented; no real request observed. |
| Question | Unknown: no supported CLI hook for it. | Handler implemented; no real request observed. |
| Failure / interruption | Hook fixture passes; no real failure observed. | Handler implemented; no real failure observed. |
| Turn completion | Verified: `Stop` produced completion in both live CLI panes. | Verified: `turn/completed` produced Review and one attention item. Review means the turn ended; it does not verify the task. |
| Session exit | Verified: `SessionEnd` produced end and cleared the CLI attention item. | Verified: closing the managed panel produced Idle and cleared its attention item. |
| Thread tokens | Unavailable for hooks-only CLI sessions. | Verified from `thread/tokenUsage/updated`; displayed as thread total tokens. |
| Account rate limits | Unavailable for hooks-only CLI sessions. | Verified primary and secondary percentage windows from the app server; displayed with account scope. |

## Reproducible checks and observed gap

- `swift run Tile --codex-live-test` creates two real Tile terminal panes in the same temporary directory, launches one authenticated `codex exec` turn in each, moves one live pane between windows, and checks distinct session IDs and pane tokens. Both turns returned `turn.completed`; each emitted start, start, completion, end. This test uses `--dangerously-bypass-hook-trust` **only for its isolated invocation** after inspecting the installed Tile hook commands. It does not change persisted trust.
- A first live run without that flag completed the Codex turn but delivered **zero hooks** to Tile. [Codex's hook documentation](https://developers.openai.com/codex/hooks) requires the user to review and trust the exact non-managed hook definition with `/hooks`; otherwise Codex skips it. Tile now states this in Settings and README. An untrusted Codex session remains unlinked and has no agent badge.
- `swift run Tile --managed-codex-live-test` starts Tile's managed app-server panel, submits a generic prompt, checks Review, thread tokens and available account windows, then checks that closing the panel clears attention. It requires an authenticated Codex installation and is intentionally separate from the offline test script.
- `./scripts/test.sh` covers duplicate delivery, delayed Claude permission notification deduplication, stale status becoming Unknown, unresolved-action retention, old shell-token rejection after restart, a new shell token, a missing Tile socket, and the local managed app-server handshake. These checks use live Tile terminal processes and controlled payloads; the two Codex commands above supply the authenticated provider evidence.

No authenticated live approval, question, or failure payload was captured. This is an explicit verification gap, not a claim of support beyond the documented handlers. The [Codex app-server documentation](https://developers.openai.com/codex/app-server) and the installed CLI's generated schema were used to check those handler shapes. Claude and Gemini live checks remain outside this Codex-only pass.
