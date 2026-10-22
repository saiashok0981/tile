# Agent integration verification

Checked 22 October 2026 on the development Mac. Tile associates events with a live pane token and provider session ID. The generic running-command border remains separate from agent state. Unknown means no fresh supported state signal; Unavailable means no supported fresh metric.

| Provider | Installed version | Verified locally | Remaining live check |
|---|---|---|---|
| Claude Code | 2.1.304 | Documented hook payload fixtures for approval, delayed permission notification, resolution, and completion pass through Tile's local socket. Enable/disable preserves an existing hook and status line in an isolated settings directory. The status-line wrapper forwards the original display output. | Trigger real approval, AskUserQuestion, failure, completion, restart, and quota data in a Tile pane. No authenticated live Claude turn was run in this verification. |
| Codex CLI | 0.156.1 | Hook permission fixture links to a pane. The installed `codex app-server` completes initialize and thread/start in the managed panel smoke test. | Trigger real CLI hooks, managed approval and question, turn output, token updates, and account rate limits. No authenticated live Codex turn was run in this verification. |
| Gemini CLI | Not installed | A documented `Notification` payload with `ToolPermission` links to a pane through the local socket. | Install Gemini CLI and verify live permission, failure, completion, restart, and emitted usage semantics. Usage and quota remain Unavailable. |

The automated agent workflow test also covers an invalid pane token, duplicate approval delivery, back-to-back turns, explicit review dismissal, multiple pending actions, and a stale status that becomes Unknown while the unresolved action remains in the queue. The existing app workflow tests cover pane and workspace behavior. The managed Codex test checks local protocol startup; it does not send a user prompt or read account credentials.

Sources for provider contracts: [Claude hooks](https://code.claude.com/docs/en/hooks), [Claude status line](https://code.claude.com/docs/en/statusline), [Codex hooks](https://developers.openai.com/codex/hooks), [Codex app server](https://developers.openai.com/codex/app-server), and [Gemini hooks](https://geminicli.com/docs/hooks/reference/). Codex wire shapes were cross-checked against the installed CLI's generated app-server JSON schema. Any unsupported or absent payload remains Unknown or Unavailable in Tile.
