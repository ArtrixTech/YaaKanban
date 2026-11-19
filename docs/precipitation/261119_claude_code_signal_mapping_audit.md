# Claude Code signal mapping audit (2.1.327–2.1.328)

## Summary
Every signal Claude Code emits that YaaKanban can observe (hooks, task notifications, the
`~/.claude/sessions/<pid>.json` file, transcript markers), each set against how `Normalizer` /
`SessionReducer` / `StuckDetector` read it. The gaps found came from real sessions with wrong
states; each entry says what was fixed and what is still open. Re-check this list when Claude
Code changes a hook or a notice format.

## Content

### Sources
- Binary strings of `~/.local/share/claude/versions/2.1.328`, `code.claude.com/docs/en/hooks`,
  the Claude Code CHANGELOG, about 200 local transcripts and 16 session files (read-only).
- YaaKanban history: 319 claude-code sessions, 52 with turns after 2026-11-14.
- One spooled Stop payload (2.1.328), which showed `background_tasks` ids equal to our `agentId`.

### How to read the signals

| Signal | What it really means | Our reading | Status |
|---|---|---|---|
| `UserPromptSubmit` | Typed prompt, **and** harness input: `<task-notification>`, `<cross-session-message …>`, `[Cross-session idle notice]`, /loop and scheduled prompts. `source` is in the schema but never sent. Mid-turn deliveries are absorbed into the running turn (transcript `queue-operation remove reason=absorbed_mid_turn`) but the hook still fires | Typed prompt: new turn; if a turn is open, end it as steered (deliberate, pushback index). Harness input: **joins the open turn**, or starts one between turns | Fixed 2026-11-19: before this, every mid-turn notice opened a new turn and left the old one open forever (80 turns in 17 sessions), and peer messages counted as pushback |
| `Stop` | End of a turn, including one that background work will wake again. Carries `background_tasks[]` (since 2.1.145) and `session_crons[]`. Not fired on Esc | `turnEnd`; an id missing from `background_tasks` is marked, then dropped when missing from the next Stop too or after 15 s of quiet (never added from the list) | Added 2026-11-19. Not dropped at once: a task that finishes while the final reply streams is already off the list, and its notice arrives ~0.2 s after Stop. A Stop replayed late is ignored |
| `StopFailure` | API error ends the turn; `error` enum, text in `last_assistant_message` | `turnEnd` | OK |
| Esc / rejecting a permission prompt | **No hook at all.** Transcript: `[Request interrupted by user]` / `[Request interrupted by user for tool use]`; session file → idle | Session-file idle ends the turn only if > 1 s after our last hook; transcript marker marks the turn and now **ends it** when no tool started after the marker | Fixed 2026-11-19 (36c8a14): Esc within 1 s of a tool end left the turn open, later "stuck" |
| `PostToolUse` background launches | Bash `backgroundTaskId` (also auto-backgrounded on timeout, Ctrl+B, or to deliver a message, without `run_in_background`); Agent `isAsync`+`agentId`; Monitor `taskId`; SendMessage `resumedAgentId` / `revivedAgentId`; Workflow `taskId` + `taskType: local_workflow` | `backgroundStart` for all but Workflow | `revivedAgentId` added 2026-11-19. Workflow not tracked (open) |
| `<task-notification>` | `<status>` only on terminal notices (completed / failed / killed / stopped / blocked). No status: Monitor events, **Monitor expiry** (`<event>[Monitor expired …]`), Bash check-ins, goal check-ins, agent resumed. "completed" can be interim ("is waiting on its own background work"), and one id can notify again | Ends a task on `<status>` or Monitor expiry; the transcript tally also reads them (user lines and `queue-operation enqueue`) and repairs stored state on launch | Expiry fixed 2026-11-19 (19c41a5). Interim "completed" ends the wait early (open, minor: the next notice restarts the turn) |
| `TaskStop` | `task_id`; fails with "No task found" if already gone | Ends the task on success, or on "No task found" | Fixed 2026-11-19 |
| `Notification` | `permission_prompt` (6 s delay, cancelled if answered; also plan approval, sandbox, dialogs), `idle_prompt` (~60 s idle, not while background agents run), `elicitation_dialog`, plus `elicitation_url_dialog`, `worker_permission_prompt`, `agent_needs_input`, others informational | permission/elicitation → needs input; idle_prompt → idle snapshot; rest ignored | `elicitation_url_dialog` and `worker_permission_prompt` not mapped (open) |
| `PermissionRequest` | No `tool_use_id`; matched by tool name + input | Same | OK |
| `SessionStart` / `SessionEnd` | `/clear`: End(clear) + Start(clear) with a **new session_id**, same pid file. `/resume` similar. SessionEnd skipped in untrusted workspaces, time-boxed to 1.5 s | Start revives an ended session; End ends it | OK; a missing SessionEnd is covered by process-gone checks |
| `SubagentStart/Stop` | Start also fires on resume and for each teammate message; tool calls inside carry `agent_id` | List of running sub-agents | OK |
| `~/.claude/sessions/<pid>.json` | `busy` / `idle` / `waiting` / **`shell`** (idle with a background Bash). Rewritten in place: a shorter record can leave the old tail (`…}}`) | Parsed per scan | Torn files were skipped silently (2 of 16 live); now the leading record is read (2026-11-19) |
| Spool | A hook that misses its 90 ms deadline spools its event | Drained only at launch | Now drained on every 5 s scan; a Stop replayed after the next prompt is ignored |

### Pitfalls worth remembering
- Stop does not mean done: check `background_tasks`. Esc fires nothing: read the transcript.
- A Monitor's expiry looks like one of its events; only its text says the watch is over.
- Bash can be backgrounded without `run_in_background`; read `backgroundTaskId`.
- Hook `prompt` text is the only way to tell harness input from the user.
- Session files can be torn or stale (dead pid); check the pid is alive. They can also stay `busy` for hours after the turn ended; only hooks are trusted for hooked sessions.
- A notice delivered while Claude was busy may exist only as a `queue-operation enqueue` record, never as a user line.
- Any event can come late through the spool: check it against the last turn's start and joins before letting it end or clear anything.

### Still open
- Hook stdin is read for at most 60 ms; a payload cut off there parses to `{}` and is dropped
  with no trace. Suspected for two lost PostToolUse events under heavy CPU load; unverified.
- Workflow launches, `elicitation_url_dialog`, `worker_permission_prompt` are not mapped.
- A short turn whose prompt was spooled (prompt late, its Stop live) is folded into the turn before.
- Process gone while stuck stays stuck ("Process exited") even when the transcript shows the turn
  had ended.
- `[Request interrupted by user for tool use]` (rejecting a permission prompt) counts toward the
  pushback index; the 2026-11-14 decision said permission denials should not.
