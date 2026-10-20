# Devlog

## docs: open-source under GPL-3.0 with a README

`pending` | 2026-10-20

- **Changes**: Added `LICENSE` (GPL-3.0) and `README.md`, covering features, build and install, hook locations, and the attribution for the agent icons.
- **Reason**: "帮我放到gihub，开源。检查是否有敏感信息。" The license (GPL-3.0) and keeping the devlog as is were the user's choices.
- **Process**: Scanned every commit's diff for keys, tokens, JWTs, private keys, private IPs, home paths and emails. None found. The only `secret` is a test fixture string. Personal mentions left by choice: one other project name and quotes of the user's requests in the devlog.
- **Result**: `make test` 58/58.

## fix(claude): end failed tool calls; flag outdated hook installs

`b9315ee` | 2026-10-20

- **Changes**:
  - Claude's hooks now include `PostToolUseFailure`. The normalizer already handled it, but it was never installed.
  - As a fallback, the transcript tally collects the ids of tool results it sees (byte search, last 100). The app then ends any tool still running after 10 s whose result is already there. The end is stamped at the session's last event time, so it does not count as new activity.
  - Integrations report `.outdated` when installing again would change the config. Settings shows "需更新" with an "更新" button.
- **Reason**: "claudecode，提示bash运行了14分钟，但实际上bash已经完毕。"
- **Process**: The stuck session had three Bash calls marked running, and all three had a `tool_result` with `Exit code 1` in the transcript. Failed calls fire only `PostToolUseFailure`, which `~/.claude/settings.json` did not have. After the fix, the session went from stuck back to running with no running tools.
- **Result**: `make test` 58/58.
- **Notes**: Existing installs need the "更新" click (the real `~/.claude/settings.json` was not edited by us).

## feat(panel): end sessions from the panel; keep the panel on screen

`42186ef` | 2026-10-20

- **Changes**:
  - Each card has a ✕ ("结束") button, also in the context menu. It sets `SessionState.dismissedAt`, which hides the session from the panel and the menu, clears its review mark, and leaves it out of badges, counts and notifications. It stays in the main window's history, where "恢复到悬浮窗" brings it back.
  - A dismissed session comes back by itself only if it needs the user: a new prompt, a question, or a jump from idle to running. Finishing the turn it was in does not bring it back.
  - The panel window is always kept inside the screen's usable area: fit() and snapping clamp it vertically. The list gives way to the room left on the screen (PanelRoom, updated on move, screen change and screen-parameter change).
- **Reason**: "需要每个条目有按钮点击结束（不再出现在悬浮窗里面）" "靠边吸附的时候，如果靠下吸附，窗体变高，下面会被遮挡".
- **Process**: The panel was found with its bottom 161 pt below the built-in display. Nothing kept the frame on screen, and the list (up to 1400 pt) could outgrow the screen. A ✕ click on a live card removed it, and the panel shrank with its bottom edge unchanged.
- **Result**: `make test` 56/56.

## fix(jump): find the host app by process ancestry; raise Cursor's window

`e7f9928` | 2026-10-20

- **Changes**:
  - The jump walks up from the agent pid to the first regular app, and falls back to TERM_PROGRAM.
  - For an editor (Cursor, VS Code, Windsurf, Zed), it activates the app and raises a window through Accessibility. Cursor's own agent gets the "Cursor Agents" window first; other agents get the window whose title has the project.
- **Reason**: "cursor无法打开。" A Cursor agent runs in Cursor's extension host and has no TERM_PROGRAM, so the jump only copied the cwd.
- **Process**: The pid ancestry of the live Cursor session resolves to Cursor.app. A first try opened the project folder with Cursor; that made a new editor window ("artrix-reach — Cursor") instead of focusing the Agents window, so it was replaced by the window raise, verified with an AX probe.
- **Result**: `make test` 54/54.
- **Notes**: An editor's built-in terminal reports TERM_PROGRAM=vscode even under Cursor; ancestry fixes that too.

## fix(ui): single review button, darker vertical logo gradient

`6038a33` | 2026-10-20

- **Changes**:
  - Review cards and the detail banner have one "去查看" button. Jumping already marks the turn reviewed, so the separate "验收" button was the same action. The context menu keeps "标记已验收" for marking without jumping.
  - Logo background: vertical gradient, dark at top to lighter at bottom (#08090B to #262A31). The dot is #10B981 to #4ADE80, top to bottom.
- **Reason**: Round 5 feedback.
- **User feedback**: "App logo，深色渐变从上到下（上深下浅）。颜色再深一点。绿点也要渐变，上深下浅。" "验收的时候，应该只有一个"去查看"按钮" "绿色渐变顶上太深。"
- **Result**: `make test` 54/54.

## feat(ui): tap to jump, resizable panel, live replies, usage stats

`f4f8cf9` | 2026-10-20

- **Changes**:
  - Card tap jumps to the agent; a chevron (or the context menu) expands it. Same in the menu popover.
  - The panel list height is set by dragging a bottom grip (`panelListHeight`, 120–1400). The grip is an AppKit view so the drag does not move the window. Header buttons open the main window and settings: a notification goes to `WindowOpener` in the menu-bar label, which has `openWindow` / `openSettings`.
  - Card rows: title / agent, project, status, stats / the agent's latest text this turn / the running tool. The prompt moved into the expanded view, and a new prompt clears the previous turn's reply.
  - `TranscriptTally` reads Claude and Codex transcripts incrementally on a background queue. It collects tokens (input, output, cache read/write, context; Codex also gives the context window), tool calls by name, and the latest assistant text. Shown as a badge on cards and a grid in the expanded card and detail view.
  - Wave jump: looks up the tab that holds the agent's block now, and re-reads the DB and tab bar on each retry. The loose window match is only used after exact matching has had all its tries.
  - Logo: A2 graphite with a green dot, the dot under column 3 and flush with column 1's bottom.
- **Reason**: Round 4 feedback.
- **User feedback**:
  - "agent条目默认点击后打开对应agent而不是展开…悬浮窗高度允许调整…第三行显示agent的任何回复。第四行才是工具调用…显示工具效用/token数量的统计"
  - "悬浮窗要允许打开主界面/设置界面"
  - "wave新建tab的时候点击查看agent会有tab对应问题，需要每次重新读取"
- **Process**:
  - Claude: message usage is repeated on every content-block line, so it is deduped by message id.
  - Codex: `token_count` totals are cumulative, and `input_tokens` includes cached tokens.
  - Benchmark: generic `Data.contains` took 31 s on a 100 MB transcript. memmem takes 0.74 s with identical totals (14 MB Codex: 0.19 s).
  - The panel buttons were tested by pressing them through System Events: the main and settings windows open.
- **Result**: `make test` 54/54.
- **Notes**: Wave's tab DOM carries no tab id, so window and tab matching still depends on the tab names in the DB.

## fix(ui): steady panel height, status-first order, brand header

`c9b03c1` | 2026-10-20

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
