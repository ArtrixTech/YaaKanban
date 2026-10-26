# Architecture

## Components

- **YaaCore** — agent-neutral model, hook-payload normalizers, session state machine, stuck detection, alerts, wire protocol (Unix socket + spool), SQLite history, efficiency activity rows, reports and their calendar periods (`Activity.swift`, `ActivityReport.swift`, `ActivityPeriod.swift`), the Wave resume block (`WaveResume.swift`). `Sources/YaaCore/`
- **YaaIntegrations** — per-agent installers that add/remove YaaKanban hooks or plugins in each agent's config, and report pending user authorization. `Sources/YaaIntegrations/`
  - Integration protocol, `Installer` (apply, backup, redacted dry run), `StableYaak` (the stable hook link) — `Integration.swift`
  - JSON-hook agents (Claude, Codex, Cursor, Windsurf) — `JSONHooks.swift`; Codex `/hooks` trust check — `CodexTrust.swift`
  - Plugin-file agents (OpenCode, pi, omp) — `Plugins.swift`; Hermes YAML hooks — `Hermes.swift`; DeepSeek dsh bundle — `DeepSeek.swift`
  - Claude-shaped settings hooks (Qwen Code, Gemini CLI, Factory Droid, ZCode) — `ClaudeCompatible.swift`; Copilot CLI hook file — `Copilot.swift`; Kiro CLI hook file — `Kiro.swift`; Kimi Code TOML hooks — `Kimi.swift`; Cline per-event hook scripts — `Cline.swift`
- **yaak** — CLI called by agent hooks (`yaak hook`) and by the user (`yaak install|uninstall|status`). Bundled at `YaaKanban.app/Contents/Helpers/yaak`. `Sources/yaak/`
- **YaaKanban app** — menu-bar app: socket server, session model, notifications, floating panel, main window (overview dashboard in `DashboardView.swift`), terminal jump adapters. `Sources/YaaKanban/`
- **Telemetry & feedback**: opt-in daily report model, bucketing and consent ledger (`YaaCore/Telemetry.swift`) and its Aptabase event (`YaaCore/Aptabase.swift`); diagnostics and prefilled issue links (`YaaIntegrations/Feedback.swift`); the sender and consent prompt (`YaaKanban/TelemetryReporter.swift`) and the feedback dialog (`YaaKanban/FeedbackPrompt.swift`); issue forms in `.github/ISSUE_TEMPLATE/`.
- **Localization**: English source strings in code; one `Resources/<lang>.lproj/` per translation (`Localizable.strings`, `InfoPlist.strings`), copied into the bundle by `scripts/bundle.sh`; the in-app language choice and relaunch in `Sources/YaaKanban/AppLanguage.swift`; `make l10n` (`scripts/l10n-check.py`) checks the compiler-extracted keys against every table.
- **Updates**: version comparison, release offer and changelog excerpts (`YaaCore/Update.swift`); the checker, downloader, signature check, installer and the panel notice state (`YaaKanban/Updater.swift`), shown by `UpdateNotice` and the Updates settings in `YaaKanban/Windows.swift`.
- **Packaging & release** — `Makefile`, `scripts/bundle.sh`, `Resources/Info.plist`; `scripts/release.sh` (`make release`) tags and publishes a GitHub release from `CHANGELOG.md`.

## Key Relationships

Agent hook → `yaak hook` → socket line (`WireRequest`) → app → `Normalizer` → `SessionReducer` → UI / alerts / `Store`. Each state change is also diffed into `ActivityRow`s (`activity` table; the time before recording is rebuilt once from stored sessions by `ActivityBackfill`); the overview computes `ActivityReport` from them, cached per range and resolution in `AppModel`. The folded side rail (`SidebarRail.swift`) has an experimental slim variant of small status cards. When the app is down, `yaak` writes to the spool and the app replays it on launch. Permission requests keep the socket open until the app replies or the CLI times out. Telemetry: `AppModel` and the settings count events into `telemetry.json` (shared with `yaak telemetry`); on its tick the app sends each finished day to Aptabase under the App Key from `Info.plist`.
