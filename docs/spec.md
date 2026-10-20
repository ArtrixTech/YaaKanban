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

- Menu bar: icon + count of sessions needing attention (`needs_input` + `stuck`); click opens the popover; the main window lists all sessions including history.
- Floating panel (NSPanel): all Spaces, draggable, edge snapping, adjustable opacity, toggle ⌥⌘K. One row per active session (status + latest tool), click to expand timeline. `idle` shows grey for 30 min then hides; `ended` hides immediately.
- Timeline: tool name + one-line summary; expand for full input; output truncated to 2 KB. `needs_input` rows show the agent's last message / permission request.
- Notifications: `needs_input` = notification + sound; done = notification; stuck = notification + yellow menu bar. Suppress system notifications while Wave is frontmost (toggle).
- Approvals: Claude Code (`PermissionRequest`) and OpenCode (`permission.ask`). Hook blocks up to 20 s (configurable) waiting for Allow once / Deny from the panel or notification; on timeout fall back to the terminal prompt. If the app is not running the hook returns immediately. No “always allow”.
- Jump: terminal adapters. Wave: hooks record `WAVETERM_BLOCKID/TABID/WORKSPACEID/JWT`; jump = activate Wave + `wsh badge` on the block. Experimental (off by default, needs Accessibility): Cmd+N tab switch + `wsh focusblock`. Upgrade when Wave PR #3333 lands. Other terminals: copy cwd + session id.

## 6. Testing

- TDD for hook-payload normalizers, state machine, stuck detection, installers (temp HOME), wire protocol.
- UI verified by running the app and screenshots.
