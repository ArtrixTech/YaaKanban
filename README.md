# YaaKanban

Yet another agent kanban: a macOS menu-bar app that watches your coding-agent sessions
(Claude Code, Codex, Cursor, OpenCode, pi) and tells you when one finishes, gets stuck, or
needs your input.

- Floating panel on every Space: one card per live session, grouped by project and ordered
  by status (needs you → to review → running → done). Shows the agent's latest reply, the tool
  in flight, and token / tool-call usage.
- Snap the panel to the left or right edge and it folds into a narrow sidebar of one block per
  session. Hover it to slide the full panel out, or pin it open.
- Tap a card to jump to the agent: Wave Terminal tab, Cursor / VS Code window, or the
  terminal app it runs in.
- Approve or deny permission requests from the panel or a notification.
- Stuck detection (long silence, a tool running too long, process gone), with thresholds you
  set.
- Full local history in SQLite.

Everything stays on your machine. The only exception is opt-in, anonymous daily usage
statistics, off by default; [docs/telemetry.md](docs/telemetry.md) lists every field.

Found a bug or have an idea? Menu → Feedback… (反馈…) opens a prefilled GitHub issue; `yaak doctor` prints
the same diagnostics.

## Install

macOS 14+. Download the `.dmg` from [Releases](https://github.com/ArtrixTech/YaaKanban/releases/latest),
open it and drag YaaKanban into Applications, then launch it.

On first launch a setup guide walks you through it:

1. **Connect** — the agents found on this Mac; install the integration for the ones you use. Some
   agents also ask you to approve the hooks; the guide shows the steps and ticks them when done.
2. **Check** — start a new session in each agent and send a message; the guide ticks each agent
   as its first event arrives. Sessions already running don't load the hooks; restart them.
3. **Alerts and preferences** — notifications, launch at login, Accessibility (for jumping to the
   exact window or Wave tab) and the `yaak` command.

Reopen it any time from the menu (**Connect agents…** while nothing is connected) or Settings →
General → Setup guide. Settings → Agent integrations manages the integrations afterwards.

## Build from source

Swift 6 toolchain (Xcode or Command Line Tools).

```sh
make test      # run the test suite
make install   # build, copy to ~/Applications, link the yaak CLI to ~/.local/bin, launch
```

## Command line

The `yaak` CLI is inside the app. `make install` links it to `~/.local/bin`; with the disk image,
link it yourself:

```sh
ln -s /Applications/YaaKanban.app/Contents/Helpers/yaak ~/.local/bin/yaak
```

Integrations can be installed from the command line too:

```sh
yaak install --dry-run          # show what would change
yaak install --agent claude-code
yaak status
yaak uninstall
yaak doctor                     # diagnostics for a bug report
yaak telemetry status|on|off
```

Installing writes YaaKanban's hook entries into each agent's own config, next to whatever is
there (a `.yaak.bak` backup is made first):

| Agent | File |
| --- | --- |
| Claude Code | `~/.claude/settings.json` |
| Codex | `~/.codex/hooks.json` (then trust them with `/hooks` in Codex) |
| Cursor | `~/.cursor/hooks.json` |
| OpenCode | `~/.config/opencode/plugins/yaakanban.ts` |
| pi | `~/.pi/agent/extensions/yaakanban.ts` |
| Hermes | `~/.hermes/config.yaml` (Hermes asks to allow each hook on first run) |
| DeepSeek dsh | `~/.dsh/yaakanban/` bundle, added to each dsh profile |
| Qwen Code | `~/.qwen/settings.json` |
| Droid | `~/.factory/hooks.json` (or `settings.json` `hooks` when that is where they live) |
| Copilot CLI | `~/.copilot/hooks/yaak.json` |
| Gemini CLI | `~/.gemini/settings.json` |
| ZCode | `~/.zcode/cli/config.json` (`hooks.events`) |
| Kiro CLI | `~/.kiro/hooks/yaak.json` (V3 engine) |
| Kimi Code | `~/.kimi-code/config.toml` (`[[hooks]]`) |
| Cline | `~/Documents/Cline/Hooks/<Event>` scripts |
| omp | `~/.omp/agent/extensions/yaakanban.ts` |
| Windsurf | `~/.codeium/windsurf/hooks.json` |

Hooks call `yaak hook <agent> <event>`, which forwards the event over a user-only Unix socket
and returns at once; if the app is not running, events are spooled and replayed later. A hook
never blocks or fails the agent.

Jumping to windows and switching Wave tabs uses the Accessibility permission.

## Layout

See [Architecture.md](Architecture.md) for components and [docs/spec.md](docs/spec.md) for the
design.

## License

GPL-3.0. See [LICENSE](LICENSE).

Agent logos in `Resources/AgentIcons` are from
[@lobehub/icons](https://github.com/lobehub/icons) (MIT); the products and their marks belong
to their owners.
