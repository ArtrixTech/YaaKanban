# Changelog

User-facing changes per release, newest first ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)).
Add entries under **Unreleased** as changes land; `make release` publishes the section of the
version in `Resources/Info.plist` as the GitHub release notes, which the app shows when it offers
the update.

## [Unreleased]

### Added
- A setup guide on first launch: install the integrations for the agents found on this Mac (each is ticked once it reports, no test session needed), then allow notifications and confirm launch at login, Accessibility, the `yaak` command and statistics (all on by default). A frameless window with one big Connect All Agents button. Reopen it from the menu or Settings › General.
- Until an agent is connected, the floating panel and the menu offer **Connect agents…**, which opens the guide. Cards of an agent without its integration show a plug mark, and installing says to restart sessions already running.

### Changed
- An agent that another agent runs as a tool (Claude calling Codex, for example) no longer gets a card of its own: it shows under the calling session, which also shows when it needs your input.

### Fixed
- Reply times on the dashboard no longer count time you were away when the wait began before the day, week or month shown (an overnight wait answered in the morning, for example).
- A session whose transcript has one very large line (an image, a huge tool result) keeps updating its tokens, reply and tool results instead of freezing there.
- Events recorded while the app was closed are no longer lost if it quits while replaying them at launch.
- A pi sub-agent caught before its transcript header is fully written still shows under its parent.
- The main window's History list stays quick with many past sessions.

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
