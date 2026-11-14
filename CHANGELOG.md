# Changelog

User-facing changes per release, newest first ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)).
Add entries under **Unreleased** as changes land; `make release` publishes the section of the
version in `Resources/Info.plist` as the GitHub release notes, which the app shows when it offers
the update.

## [Unreleased]

### Added

- 概览's top row shows 杠精指数 (Pushback) in place of the tool call count: the share of finished turns you cut short, by stopping the agent mid-run or sending it a new prompt while it ran. Read from Claude Code and Codex transcripts, from the stop signals of Cursor, Kimi, Cline and Hermes, and from the OpenCode, pi and omp plugins (update them in Settings to count there); other agents count a prompt sent into a running turn. A turn you stop yourself no longer sends a "done" notification.

### Fixed

- A prompt sent before the agent's last turn finished (Esc then typing at once, or a message queued mid-run) now ends that turn, so it counts in the overview's turns and prompts instead of being left open.

- A session waiting on a background job after its turn (for example a shell polling a training run for hours) no longer turns 可能卡住 · N 分钟无新事件 after 5 minutes; it stays running while the agent's process is alive, and finishes if the process exits.

- Dragging cards up and down in the floating panel and side rail works: the card itself follows the pointer and the others make room, instead of a blue line. Every card can be moved within its group (pinned, or its status); 待验收 and 已验收 cards now keep the place you drag them to until they are active again.

## [0.2.3] - 2026-11-09

### Fixed

- A folded side rail no longer opens and shuts over and over when the pointer rests just above the open panel (seen with the panel low on the screen beside a side Dock and few cards).
- A coding agent started by Claude Code (for example `cursor-agent -p` in the background) no longer shows as 可能卡住 · 进程已退出 after it finishes. Its card goes idle when its process exits. Cards stuck before this update have to be dismissed by hand.
- A locally built app is signed by the same team as the released one, so installing it over a release keeps the Accessibility permission instead of losing it.

## [0.2.2] - 2026-11-05

### Changed

- With anonymous statistics on, the daily report also counts installs, updates (with the version updated from), quits by cause (you, an update, a language change, logout or shutdown) and runs that ended without quitting. See `docs/telemetry.md`.
- The away check now triggers after 1 minute without keyboard or mouse input instead of 2.

### Fixed

- Clicking a Wave session now brings Wave to the front reliably; before, it often switched the tab while Wave stayed behind other windows.

## [0.2.1] - 2026-11-01

### Changed
- The logo above the sidebar is a little larger, as far from the window's top as from the row below it, and a band of light sweeps across it when you point at it.
- A session's page in the main window is redesigned around what the session came to: tokens used, turns, agent time and your input at the top; the latest reply drawn as formatted text (headings, lists, code, tables) with what that turn did; a bar of where the time went (running, waiting on you, to review); every turn in brief, expandable to its reply and edited files; the files touched and failed calls; token and tool mix. The raw tool log is folded at the end. Messages the agent's tools inject (background task reports) no longer read as your prompts.
- Uses much less CPU while agents are running: status animations no longer redraw the windows every frame, and session history is written in batches in the background instead of on every hook event.

### Fixed
- With all four state counts showing, the floating panel's top row no longer spills past its edges, cutting off the logo and pushing out the close button; in a narrow panel the counts get tighter and then lose their capsules.
- Clicking a Codex app session after the app has quit offers to open the app at that conversation, instead of asking you to paste a resume command into a terminal.

## [0.2.0] - 2026-10-31

### Added
- A setup guide on first launch: install the integrations for the agents found on this Mac (each is ticked once it reports, no test session needed), then allow notifications and confirm launch at login, Accessibility, the `yaak` command and statistics (all on by default). A frameless window with one big Connect All Agents button. Reopen it from the menu or Settings › General.
- Clicking a card that needs Accessibility (to bring up the right Wave tab or editor window) first says, in one line, why and that macOS will ask, instead of the system prompt appearing out of nowhere. "Not Now" is remembered.
- In the setup guide, Continue warns when an agent still needs its hooks approved; Skip Setup does not.
- Until an agent is connected, the floating panel and the menu offer **Connect agents…**, which opens the guide. Cards of an agent without its integration show a plug mark, and installing says to restart sessions already running.
- Tabby: clicking a card brings up the agent's own Tabby tab (with "Switch to the matching tab when jumping" on and Accessibility allowed). Tabs with a custom name, unfocused split panes and tmux still only bring Tabby forward.
- Experimental, on by default: a finished turn is marked reviewed as soon as you bring up its terminal pane in Wave, iTerm2, Terminal or WezTerm (tmux inside them too), as if you had clicked its card. iTerm2 and Terminal need Automation access, which Settings › Session reminders asks for with an Allow… button.
- **Reset floating panel position** in the menu-bar menu brings the floating panel back to where a new install puts it: the right edge of the main screen, centered top to bottom. New installs now start there instead of at the top right.
- Every overview card and key figure has an ⓘ: hover it to see what the figure measures and how its chart reads.
- The overview's **Response time** card, beside leverage: how fast you reply to an agent (an answer, or your next prompt after a turn) and how fast you get to a finished turn, each as a median against the previous period with its spread.
- **First day of the week** in Settings › General: where the overview's weeks start, Monday by default (Sunday or Saturday also).

### Changed
- Main window sidebar: the logo sits at the right, across from the window buttons, and under it a round house button opens Overview (named when hovered) beside a slim capsule with the running sessions' state counts and today's leverage, marked in a color that follows it (blue low, red high). Search is a button beside the Active heading (⌘F), and the list fades out above Settings.
- While the main window is open, the app shows in the Dock and the app switcher.
- Overview › Response time shows the average reply and review time instead of the median, which read 0 s when most waits fell while you were away.
- Wave: reopening a session whose agent has stopped now continues it in the terminal it ran in, when that terminal is back at its shell prompt, instead of opening a new one beside it. A terminal that is busy or closed still gets a new one.
- A new look across the app, with fills and space instead of lines, and status color only on session cards. Settings is now a page of the main window (⌘, or the Settings row at the bottom of its sidebar), split into tabs: Agent integrations, Alerts, Floating panel, Compatibility, General and About. The sidebar shows active sessions as cards and history as single lines, with search and an agent filter on top; the arrow keys move through it.
- The overview is rebuilt as a wall of cards: totals in the top bar, a row of key figures, then cards for leverage, time away, sessions running at once, waits on you, reply times, agents, projects and a 7-day rhythm, each compared with the same point of the previous period. Below them, a row for prompts, switches, pickup time and backlog, and the session lanes behind a button.
- The overview is denser: tighter cards that are only as tall as their content, leverage drawn as a bar per day of the week (of the month in the month view) with the same day of the one before as a pale bar of the same width behind it, marked by a short line on the bar where this one is higher, over the break-even 1× line, and kept beside response time down to narrower windows, and time away as a timeline of each stretch, lit where agents ran and red where they waited on you.
- The overview drops the time-away and waiting cards and the all-stalled and backlog figures; reply time and pickup time now live in the Response time card.
- An agent asking you something is purple with a question-bubble mark (cards, menu-bar dot, overview) instead of red; red is kept for errors.
- Main-window sidebar cards line their agent and project up under the status mark, as on the floating panel, and show a pin on pinned sessions.
- The slim side rail is no longer experimental and is now the only folded rail: snapped to a screen edge, the panel folds into a thin strip of status, agent and time. The wider folded rail and its setting are gone.
- The setup guide shows in the Dock and the app switcher while it is open, so you can get back to it after switching to an agent; its Accessibility row asks right there with an Allow… button.
- Codex approval steps describe the Codex desktop app (Settings → Hooks) by default, with a switch for the terminal's /hooks.
- The setup guide shows each agent's state the same way (connected, waiting for first use, needs approval), agents needing approval first, and says once rather than on every row that agents tick themselves when next used.
- The floating panel is always fully opaque; the opacity setting is gone.
- Hook approvals are checked again whenever you come back to YaaKanban, in the guide and in Settings; there is no Recheck button to click anymore.
- An agent that another agent runs as a tool (Claude calling Codex, for example) no longer gets a card of its own: it shows under the calling session, which also shows when it needs your input.
- A sub-agent whose parent session is not on the board (pi-subagents scouts of a pi session YaaKanban never heard from, for example) no longer gets a card of its own, unless it needs your input.

### Fixed
- Clicking a notification goes to its agent's terminal again, instead of opening the main window over it.
- A session no longer shows Maybe stuck while it waits for sub-agents, after a sub-agent stopped under an id the app had not seen and left a tool marked running.
- The side rail folds back while an alert it opened is up (reopening a session, renaming, Accessibility, feedback), instead of staying as wide as the panel around its narrow cards until the alert closes.
- Wave: after a new tab was added, clicking a card again brings up its own tab, instead of only bringing Wave forward (or opening a tab next to it).
- A card no longer shows To review while an agent it started (e.g. `codex exec` through Bash) is still running under it: it stays running until that work ends.
- The floating panel's leverage arrow and dashed line compare the last 4 hours with today's average 4 hours (the 4-hour leverage at each whole hour), not with the whole day so far.
- Clicking a session in the floating panel's search that had left the panel now also takes you to its terminal, as clicking its card does, instead of only putting it back on the panel.
- The floating panel no longer stays wide around the folded rail after being dragged to a screen edge: a window that ends up a different size from its content is put right.
- Dropping the floating panel near a screen edge glides it there with the panel's own animation, which a fold can no longer cut into, and the system can no longer zoom it.
- An agent run by another agent (Claude calling Codex, for example) that exits early, even with an error, no longer shows "Process exited" under the calling session; its run is simply over.
- Claude Code `/bg`: the session moved into a background job no longer stays on the board as "Maybe stuck" next to the job's card, and the job's card no longer jumps to an unrelated Wave pane (the one that happened to start Claude's daemon).
- The floating panel is never taller than its cards: a list height set by hand with the grip now stops at the end of the list, and the panel shrinks when sessions leave.
- Reply times on the dashboard no longer count time you were away when the wait began before the day, week or month shown (an overnight wait answered in the morning, for example).
- A session whose transcript has one very large line (an image, a huge tool result) keeps updating its tokens, reply and tool results instead of freezing there.
- Events recorded while the app was closed are no longer lost if it quits while replaying them at launch.
- A pi sub-agent caught before its transcript header is fully written still shows under its parent.
- The main window's History list stays quick with many past sessions.
- A Codex session no longer shows Maybe stuck while it carries on past a command it left running (a long `exec_command` it stopped waiting for).
- A Claude Code session reopened with `--resume` no longer shows Maybe stuck after its reply, waiting for background agents the previous run started, which ended with it.

## [0.1.2] - 2026-10-26

### Added
- A drag-to-install disk image (open it, drag YaaKanban into Applications) and an app icon.

## [0.1.1] - 2026-10-26

### Added
- Automatic updates from GitHub Releases: a new version downloads in the background, then a line on the floating panel offers to restart into it. After an update the same line says so, with a link to these notes. Can be turned off in Settings › Updates.
- Search on the floating panel (magnifier, bottom right): every session of the last 14 days by name, project, agent, prompts or replies; click one to jump to it or put it back. Replaces the ended list.
- Pinned cards stay on the board until unpinned.
- Hooks for Cline, omp, Windsurf, ZCode, Kiro, Kimi, Qwen Code, Factory Droid, Copilot CLI, Gemini CLI, Hermes and DeepSeek, with checks for hooks the agent still has to approve.
- The interface in 10 languages, with a language setting.
- Opt-in anonymous daily usage statistics and prefilled issue feedback.

### Changed
- Leverage counts the work done while you are away and is measured over the last 4 hours; the floating panel's curve spans those 4 hours. Waiting on you splits into blocked and to review.
- Settings list only the agents found on this Mac.
- The floating panel fades at its top as well as its bottom, scrolls back to the top when it folds, and comes back where and as big as you left it.

### Fixed
- Opening a popover from the folded side rail no longer folds the rail and closes it.
- Claude Code turns stay running while a background shell is out.
- Wave resume opens an ordinary terminal block.
- Unchanged sessions are no longer rewritten to disk every few seconds (about 13× less disk writing).
- Telemetry waits for a network and records each send's outcome.
