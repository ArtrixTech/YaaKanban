# Devlog

## fix(ui): steady panel height, status-first order, brand header

`pending` | 2026-10-20

- **Changes**:
  - The panel content is top-aligned in a host pinned to all edges. SwiftUI reports the natural height, and the window follows it on the next runloop turn. It used to be sized by `intrinsicContentSize`.
  - A running card's detail line stays one line: the latest tool (finished or not), instead of switching to a two-line recap between tools.
  - The board is ordered by status tier first: needs input / stuck, then review, then running, then reviewed. Manual or start order applies only inside a tier. A group sits in the tier of its most urgent session.
  - The header shows the YaaKanban mark (`Resources/Brand/logo.svg`) and name. Five logo drafts were offered, and option A is a placeholder until the user picks one.
- **Reason**: Round 3 feedback.
- **User feedback**: "悬浮窗显示不对劲，上下会跳动，顶上空间一会大一会小。另外，需要先按照运行状态排序，优先排列待验收，然后是运行中，然后已验收。" and "悬浮窗左上角放YaaKanban的名字和Logo，Logo帮我重新画一个，给我一些选项。"
- **Process**: Sampled the window frame with CGWindowList every 100 ms.
  - Before: the top edge stayed fixed while the height swung 478 → 447 → 464 within seconds.
  - After: steady at 528 for 12 s.
- **Result**: `make test` 51/51.
- **Notes**: When NSHostingView is taller than its content for a moment, it centers that content. Every height change the window had not caught up with yet showed up as a moving gap at the top.

## feat(ui): titles, project groups, manual order, logos, Wave tab jump

`39e0a7f` | 2026-10-20

- **Changes**:
  - Card titles are the agent's own short title: Claude `custom-title`/`ai-title` from the transcript, Codex `thread_name` from `session_index.jsonl`. Falls back to the first line of the first prompt, then the project.
  - Sessions are grouped by the directory they started in (`projectDir`, so a `cd` does not move them).
  - Board order is start time, not recent activity. Drag a card or a group header to reorder, or use the context menu (上移/下移/置顶). The order is kept in `manualOrder`.
  - Real agent logos (SVG from @lobehub/icons-static-svg 1.95.1) are bundled in `Resources/AgentIcons`.
  - Wave jump presses the tab through Accessibility. Wave's tab bar is Electron DOM, exposed after `AXManualAccessibility`; tabs answer AXPress. The window is matched by tab names from Wave's DB. This replaces the Cmd+N keystroke hack and is now on by default.
  - The app is signed with the Apple Development identity when one exists, so the Accessibility grant survives rebuilds.
  - Floating panel: the content is pinned to the top only and the window follows its height. Previously the content was also pinned to the bottom, so collapsing could not shrink the window and expanding centered the content, which shifted its top.
- **Reason**: User feedback: the folder name is not enough to identify a session, multiple agents per project should be grouped, the order should be start order and allow manual sorting, real logos, collapse broken, top misaligned on expand, and Wave jump did not switch tabs.
- **Process**: Confirmed AXPress on Wave 0.14.5 switches the active tab (checked `activetabid` in the DB, then switched back). Tab text ends with private-use icon glyphs, which are stripped before matching. Panel window measured via CGWindowList: collapsed h=78 and expanded h=524, same top y.
- **Result**: `make test` 50/50.
- **Notes**: `wsh` 0.14.5 has no tab focus command (PR #3333 still open). Without the Accessibility permission, the jump only activates Wave.

## feat(ui): redesign panel and add review state

`99e0956` | 2026-10-20

- **Changes**:
  - A finished turn is now "待验收" (`unreadSince`). It stays in the panel, turns the menu-bar icon green with a count, keeps the Wave badge on and plays a sound. It is cleared by 验收, by jumping to the terminal, or by the next prompt.
  - Sessions started before hooks were installed now show their last prompt, reply and recap, read from the transcript tail (`TranscriptPeek`).
  - Bug fix: Claude's AskUserQuestion was treated as a command approval. It now becomes a question, the hook no longer blocks for it, and the generic "needs your permission" notice no longer overwrites the question text.
  - UI: the floating panel is borderless, rounded and vibrant, with no traffic lights. It sizes itself to its content and can be collapsed. Cards have animated status glyphs, pills and hover feedback. The menu and detail page were restyled to match.
- **Reason**: User feedback: the UI was ugly, a mystery task showed no content, a finished turn should ask for review, and a question was shown as a permission request.
- **Process**: Tests were written for the review state, transcript parsing and the AskUserQuestion flow. Verified with `yaak snapshot` using live sessions.
- **Result**: `make test` 46/46.
- **Notes**: The snapshot command cannot render vibrancy or the sidebar, so the real panel background was not captured.

## fix: address adversarial review findings

`57f0bdb` | 2026-10-20

- **Changes**:
  - Hook commands shell-quote the yaak path.
  - Claude-shaped installers update our entry in place, so Codex index trust survives a reinstall.
  - Installers write through symlinks and back up file contents.
  - Permission replies carry a per-request token, so a stale timer cannot expire a newer request, and notification Allow/Deny checks the request id.
  - Resolved permission banners are withdrawn. Truncated or multi-line commands show their full text and get no Allow action in the banner.
  - Parallel same-name tools no longer clear a pending permission; Claude's id-less PermissionRequest adopts the matching PreToolUse id.
  - Interrupts end the turn: `idle_prompt` or a newer idle session file goes to idle.
  - Only permission/elicitation notifications count as needs-input.
  - `yaak hook` trims strings to 8 KB.
  - The accept loop survives ECONNABORTED/EMFILE.
  - `JSONValue.string` no longer traps on huge numbers.
  - The Wave JWT is dropped from history once a session ends.
  - Also covers `cf56a8c` (precipitation doc, macOS Swift pitfalls).
- **Reason**: An adversarial review by an uninvolved agent (AGENTS.md) reported 11 findings. Three were high severity: a path with `'` made hooks exit 2, which blocks Claude; a stale notification could approve a different command; Esc left sessions "running", causing false stuck alerts.
- **Process**: A regression test was written first for each core/installer finding (11 new). End to end: a 6 MB PostToolUse payload through the built `yaak` with a temp `YAAK_HOME` was spooled at 9 KB, exit 0.
- **Result**: `make test` 38/38.
- **Notes**: Not changed: the approval timeout stays capped at 25 s by the hook (Claude hook timeout is 30 s); the setting's range already stops there.

## feat(app): add menu bar app, floating panel, notifications, Wave jump

`5183c4b` | 2026-10-20

- **Changes**: YaaKanban app: `AppModel` (socket server, spool drain, 10 s stuck tick, 5 s Claude session scan, SQLite history), MenuBarExtra with tinted icon + count, floating NSPanel (⌥⌘K, edge snap, opacity), main window with active/history + search/filter + session detail, Settings (installers, thresholds, Wave tab switching, login item). Notifications with Allow/Deny actions, suppressed while Wave is frontmost. Wave jump via `wsh badge` + activate; opt-in Cmd+N tab switch. Stuck silence rule now only applies to hooked sessions. Debug `yaak snapshot <dir>` renders all windows offscreen.
- **Reason**: Spec §4–§5 UI and alerts.
- **Process**: No screen-recording permission, so UI was verified through the snapshot command: panel, menu, settings and main-window detail render with live data (blocking PermissionRequest showed Allow/Deny buttons; real Claude sessions found by the scanner).
- **Result**: `make test` 27/27. Permission hook falls back after 20 s with exit 0 and no output.
- **Notes**: `cacheDisplay` skips the window background and vibrancy, so snapshots paint `windowBackgroundColor` explicitly and the NavigationSplitView sidebar still renders blank there. Naming a type `Settings` shadows the SwiftUI scene; renamed to `Preferences`.

## feat(integrations): add agent installers and yaak CLI

`7d725a7` | 2026-10-20

- **Changes**: YaaIntegrations: Claude/Codex (Claude-shaped hooks.json), Cursor hooks.json, OpenCode + pi plugin files; idempotent plan/apply with `.yaak.bak` backups and `--dry-run`. CLI `yaak hook|install|uninstall|status`; permission hook blocks up to 25 s for an app decision (Claude, OpenCode), spools when the app is down. Snapshot events no longer count as activity for hooked sessions.
- **Reason**: Spec §3 transport and installer safety.
- **Process**: Temp-HOME tests for every installer. Plugins checked by stripping TS types (node 22) + `node --check`, then driven with a fake pi object end to end into the spool.
- **Result**: `make test` 26/26. pi event order verified (prompt → tool_start → tool_end → turn_end).
- **Notes**: `FileManager.homeDirectoryForCurrentUser` ignores `$HOME`; a dry-run under a fake HOME read the real settings.json (no write). All home lookups now go through `Paths.home`. Concurrent `spawn` in plugins reordered events; plugins now chain sends and stamp `ts`. `unref()` on the child let node exit before the chain drained, so it was removed.

## feat(core): add event model, reducer, stuck detection, wire, store

`5c7406b` | 2026-10-20

- **Changes**: Scaffold SwiftPM package (YaaCore, YaaIntegrations, yaak, YaaKanban), AGENTS.md from artrix-skills `9f9d782`, spec, Makefile. YaaCore: JSONValue, models, normalizers (Claude/Codex schema, Cursor, yaak plugin schema), SessionReducer + Alerts, StuckDetector, Unix socket client/server + spool, SQLite Store.
- **Reason**: Foundation for the cross-agent monitor agreed in the grilling session (see `docs/spec.md`).
- **User feedback**: "快速写个程序，用来监控各个harness下的任务情况…和我用grilling对齐。" Then "agents.md用artrixskills的。然后开干，做好工作流。"
- **Process**: Hook schemas verified from local installs: Claude settings.json, Codex binary strings (PreToolUse/PermissionRequest/…; `tool_use_id`, `last_assistant_message`), OpenCode plugin SDK 1.2.10 types, pi 1.3.0 extension docs. CLT lacks a default Swift Testing path; Makefile passes `-F` + rpath.
- **Result**: `make test` 19/19 pass.
- **Notes**: Synthetic tool ids must be process-stable (FNV-1a), since pre/post hooks run in separate `yaak` processes. A research sub-agent accidentally ran `adrafinil install-hooks` (no `--help` support) and rewrote Adrafinil entries in the user's agent configs; files verified valid, user informed.
