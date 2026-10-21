# Architecture

## Components

- **YaaCore** — agent-neutral model, hook-payload normalizers, session state machine, stuck detection, alerts, wire protocol (Unix socket + spool), SQLite history, efficiency activity rows and reports (`Activity.swift`, `ActivityReport.swift`). `Sources/YaaCore/`
- **YaaIntegrations** — per-agent installers that add/remove YaaKanban hooks or plugins in each agent's config. `Sources/YaaIntegrations/`
- **yaak** — CLI called by agent hooks (`yaak hook`) and by the user (`yaak install|uninstall|status`). Bundled at `YaaKanban.app/Contents/Helpers/yaak`. `Sources/yaak/`
- **YaaKanban app** — menu-bar app: socket server, session model, notifications, floating panel, main window (overview dashboard in `DashboardView.swift`), terminal jump adapters. `Sources/YaaKanban/`
- **Packaging** — `Makefile`, `scripts/bundle.sh`, `Resources/Info.plist`.

## Key Relationships

Agent hook → `yaak hook` → socket line (`WireRequest`) → app → `Normalizer` → `SessionReducer` → UI / alerts / `Store`. Each state change is also diffed into `ActivityRow`s (`activity` table; the time before recording is rebuilt once from stored sessions by `ActivityBackfill`); the overview computes `ActivityReport` from them, cached per range in `AppModel`. The folded side rail (`SidebarRail.swift`) has an experimental slim variant of status-color blocks. When the app is down, `yaak` writes to the spool and the app replays it on launch. Permission requests keep the socket open until the app replies or the CLI times out.
