# Architecture

## Components

- **YaaCore** — agent-neutral model, hook-payload normalizers, session state machine, stuck detection, alerts, wire protocol (Unix socket + spool), SQLite history, efficiency activity rows, reports and their calendar periods (`Activity.swift`, `ActivityReport.swift`, `ActivityPeriod.swift`). `Sources/YaaCore/`
- **YaaIntegrations** — per-agent installers that add/remove YaaKanban hooks or plugins in each agent's config. `Sources/YaaIntegrations/`
- **yaak** — CLI called by agent hooks (`yaak hook`) and by the user (`yaak install|uninstall|status`). Bundled at `YaaKanban.app/Contents/Helpers/yaak`. `Sources/yaak/`
- **YaaKanban app** — menu-bar app: socket server, session model, notifications, floating panel, main window (overview dashboard in `DashboardView.swift`), terminal jump adapters. `Sources/YaaKanban/`
- **Telemetry & feedback**: opt-in daily report model, bucketing and consent ledger (`YaaCore/Telemetry.swift`) and its TelemetryDeck signal (`YaaCore/TelemetryDeck.swift`); diagnostics and prefilled issue links (`YaaIntegrations/Feedback.swift`); the sender and consent prompt (`YaaKanban/TelemetryReporter.swift`) and the feedback dialog (`YaaKanban/FeedbackPrompt.swift`); issue forms in `.github/ISSUE_TEMPLATE/`.
- **Packaging** — `Makefile`, `scripts/bundle.sh`, `Resources/Info.plist`.

## Key Relationships

Agent hook → `yaak hook` → socket line (`WireRequest`) → app → `Normalizer` → `SessionReducer` → UI / alerts / `Store`. Each state change is also diffed into `ActivityRow`s (`activity` table; the time before recording is rebuilt once from stored sessions by `ActivityBackfill`); the overview computes `ActivityReport` from them, cached per range and resolution in `AppModel`. The folded side rail (`SidebarRail.swift`) has an experimental slim variant of small status cards. When the app is down, `yaak` writes to the spool and the app replays it on launch. Permission requests keep the socket open until the app replies or the CLI times out. Telemetry: `AppModel` and the settings count events into `telemetry.json` (shared with `yaak telemetry`); on its tick the app sends each finished day to TelemetryDeck under the App ID from `Info.plist`.
