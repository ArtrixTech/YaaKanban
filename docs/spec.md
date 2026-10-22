# YaaKanban Spec

Yet another agent kanban: a macOS menu-bar app that watches coding-agent sessions across harnesses and tells the user when a task finishes, gets stuck, or needs input. Goal: see cross-agent work at a glance and cut context-switching cost.

Decisions below were agreed with the user on 2026-10-20 (grilling session).

## 1. Scope

- Personal MVP, but agent integrations are installable/uninstallable modules (distribution-ready shape).
- Local machine only. No remote agents, no phone push, no loop detection, no free-text replies in MVP.

## 2. Stack

- Swift / SwiftUI, SwiftPM, packaged into `.app` by `make app`. macOS 14+. Ad-hoc signing. Login item via `SMAppService`.
- No separate daemon in MVP: the app process owns the socket server. A small CLI `yaak` (bundled at `Contents/Helpers/yaak`) is what hooks call.

## 3. Integrations

- First batch: Claude Code, pi, Codex, OpenCode, Cursor. Hermes and Kiro later (adapter interface ready).
- Like Adrafinil: write entries into each agent's native hook/plugin location; idempotent install/uninstall; coexist with Adrafinil.
  - Claude Code: `~/.claude/settings.json` hooks.
  - Codex: `~/.codex/hooks.json` only (not `notify`, which is single-slot and already taken). Append only; the user must trust via `/hooks`.
  - Cursor: `~/.cursor/hooks.json`.
  - OpenCode: `~/.config/opencode/plugins/yaakanban.ts`.
  - pi: `~/.pi/agent/extensions/yaakanban.ts`.
- Installer safety: back up every file before writing (`.yaak.bak`), `--dry-run` prints the change, tests use a temp HOME.
- Data: hooks drive state transitions; Claude session files (`~/.claude/sessions/<pid>.json`) backfill sessions without hooks and supply status.
- Transport: hook → `yaak hook <agent> <event>` → Unix socket JSON line → app. If the app is down, append to a spool dir; the app replays on start. Hooks return within ~100 ms and never block, except the bounded permission wait.

## 4. Model

- One row = one session. Turns (prompt → stop) are listed in detail. Sub-agents fold under the parent (“2 sub-agents running”).
- States: `running`, `needs_input`, `stuck`, `idle`, `ended`.
- Stuck: running with no new event for 5 min; a single tool running > 5 min; process gone while still running. Running sub-agents count as activity. Thresholds configurable.
- History fully kept in SQLite. Metadata (session, turn, tool name, summary) forever; full tool input/output 30 days.

## 5. UI & alerts

- Agent logos: all five agents use white monochrome marks throughout the UI, including fallback symbols (updated 2026-10-21).

- Menu bar: icon + count of sessions needing attention (`needs_input` + `stuck`); click opens the popover; the main window lists all sessions including history.
- Floating panel (NSPanel): all Spaces, draggable, edge snapping, adjustable opacity, toggle ⌥⌘K. One row per active session (status + latest tool), click to expand timeline. an unreviewed `idle` stays until looked at, a reviewed one for the retention setting (24 h by default); an agent exit (any SessionEnd, including one a terminal crash causes) is not "ended" for the user: the card stays and shows as a reviewed `idle` card (retention setting, 24 h by default) unless the same process started a new session; a session opened but never sent a message (no prompt or tool) is not shown on the boards or in history (2026-10-22); whether the agent process is still alive does not change the card. The UI says 已结束 only for sessions that left the boards: retention over, or ended on the panel (updated 2026-10-21). Order (2026-10-22): pinned cards first (context menu 置顶 / 取消置顶, newest pin on top, above every status); then waiting on you, then 待验收, then running, then 已验收; 待验收 and 已验收 are freshest first (the later of the last event and the user's last click), running and waiting keep the user's drag order, else start time. Review flash (2026-10-22): a 待验收 card not opened for 10 min of the user being at the Mac (away time does not count; the clock restarts when they come back) starts flashing until opened (the slim rail's cards too, like the waiting-on-you flash); on by default, can be turned off and the threshold changed in settings. Rename (2026-10-22): any session can be renamed from its context menu; the name is YaaKanban's only, wins over the agent's title, and an empty name restores it.
- Timeline: tool name + one-line summary; expand for full input; output truncated to 2 KB. `needs_input` rows show the agent's last message / permission request.
- Notifications: `needs_input` = notification + sound; done = notification; stuck = notification + yellow menu bar. Suppress system notifications while Wave is frontmost (toggle).
- Approvals: Claude Code (`PermissionRequest`) and OpenCode (`permission.ask`). Hook blocks up to 20 s (configurable) waiting for Allow once / Deny from the panel or notification; on timeout fall back to the terminal prompt. If the app is not running the hook returns immediately. No “always allow”.
- Jump: terminal adapters. Wave: hooks record `WAVETERM_BLOCKID/TABID/WORKSPACEID/JWT`; jump = activate Wave + `wsh badge` on the block. Experimental (off by default, needs Accessibility): Cmd+N tab switch + `wsh focusblock`. Upgrade when Wave PR #3333 lands. Other terminals: copy cwd + session id.
- Resume (2026-10-21): clicking a session whose agent is gone (ended, or its process is not running) asks whether to reopen it; reopening continues it in the terminal it ran in: Wave = `wsh run` a new block in its tab with the agent's resume command (the Wave JWT is kept up to 24 h after an ended session's last event, dropped at once when the user ends the card; also when its process died; without a working own token, tokens of other sessions in the same tab are tried, live ones first; if none opens the block, the user is told the command was copied); Terminal/iTerm = new window via AppleScript; other terminals = activate + copy `cd … && <resume command>`. Codex app = open the thread.

- Efficiency (2026-10-21): the main window opens on 概览 (overview), above the sessions. Revised 2026-10-21: intuitive figures first, details after. Top: a one-sentence summary and four headline figures, each against the previous period; revised 2026-10-21 to read from the user's side ("how did I and my agents do"): agent hours (running session-time summed, with the part while the user was away), leverage (agent hours while the user was here ÷ the user's active time), bottleneck, turns. Revised 2026-10-22: the third figure is reply speed (median time agents wait for the user's answer); bottleneck, renamed 全部停工 (all stopped), moves to the detail tiles. Under them four highlights: the session that ran longest, the longest unbroken run, the busiest slice, agent hours while the user was away. Then one chart of running vs waiting-on-the-user sessions per slice (away shaded, previous period's running as a dashed line); then running time per agent kind (军团构成), per-project time, the detail tiles (average parallel moves here), and per-session swimlanes folded by default (busiest 10, all on request). Comparison granularity: day (default), week or month (calendar periods), against the previous one; while the current period runs, against the same elapsed stretch of the previous one. Figures: parallelism (average while something runs, current, peak, sparkline), reply latency (median, P90, slowest project), agent utilization (running ÷ (running + waiting on the user)), bottleneck time (something waits on the user, nothing runs), throughput (turns, tool calls, tokens per active hour), current backlog (count, oldest wait), switches (jumps from a card or notification). Away = no mouse or keyboard input for 2 min, the Mac asleep, or the app not running; it is left out of waits and bottleneck. The menu-bar popover shows today's agent hours, leverage, median reply and turns (revised 2026-10-22); its top (logo, name with a chevron, counts, figures) opens the main window on click. The floating panel shows two figures under its header (revised 2026-10-22): leverage over the last hour (window 15 min–4 h) and today's agent hours (今日工时); can be turned off in settings. Revised 2026-10-22: leverage is the large figure, with its trend as a curve (each point the leverage of the window up to it, three windows back; clock times under it, ending at 现在); 今日工时 is smaller at the side. Shown in the folded rail too, so cards keep their height when the rail unfolds: the folded rail shows leverage and today's hours, the slim rail only leverage with an arrow for its direction; no range label. History before recording began is rebuilt from the stored sessions (running time and turns only). Experimental slim rail (2026-10-21, off by default): folded at a screen side, the panel becomes a thin strip, each card as tall as its full card; height unchanged, only the width shrinks. Revised 2026-10-22: each card is a plain card with the status glyph, agent logo and a short clock; its header is the logo's mark without its tile; color is only an accent (glyph, a thin track; a light runs down the track while running). Pushing the pointer against the docked screen edge (the margin outside the panel) unfolds it too.

## 6. Testing

- TDD for hook-payload normalizers, state machine, stuck detection, installers (temp HOME), wire protocol.
- UI verified by running the app and screenshots.
