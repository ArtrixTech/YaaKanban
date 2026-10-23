# Telemetry

Off by default. When you turn it on (the one-time prompt, 设置 › 隐私与反馈, or
`yaak telemetry on`), the app sends **one report per local day it ran**, after that day ends. A
failed send is dropped, not retried; at most the last 7 unsent days are kept. `DO_NOT_TRACK=1`
in the app's environment keeps it off, and `yaak telemetry on` refuses under it. Only the app sends; `yaak` and agent hooks never use the network.

Settings › 查看 shows today's report so far, with setup and settings as of now (a report carries
them as at send time). `yaak telemetry status` shows the
state, install id and whether this build has a TelemetryDeck App ID. Turning it off deletes the unsent counts.

## Fields (schema 1)

| Field | Content |
| --- | --- |
| `schema` | `1` |
| `install_id` | random UUID made when you first turn telemetry on; 重置 makes a new one |
| `day` | local date the report covers, `yyyy-MM-dd` |
| `app`, `build` | YaaKanban version |
| `os` | macOS major version |
| `arch` | `arm64` / `x86_64` |
| `lang` | language code only, e.g. `zh` |
| `integrations` | per agent: `installed`, `outdated`, `notInstalled`, `notDetected` |
| `settings` | on/off: `show_panel`, `slim_rail`, `recent_stats`, `flash`, `review_flash`, `stale_tint`, `wave_tab_switching`, `pi_auto_title`, `launch_at_login` (as at send time) |
| `counts` | times that day, bucketed like `sessions` below: `panel_toggle`, `jump_wave`, `jump_iterm`, `jump_terminal`, `jump_editor`, `jump_other`, `jump_unknown`, `resume`, `approval_allow`, `approval_deny`, `approval_timeout`, `rename`, `pin`, `feedback_open`, `integration_install`, `integration_uninstall`, `integration_fail`, `spool_replay` |
| `figures` | ranges, not values: `sessions.<agent>` and `turns.<agent>` (`1`, `2-5`, `6-20`, `21-100`, `100+`), `agent_hours` (`0`, `<1`, `1-3`, `3-8`, `8-24`, `24+`), `parallel_peak` (as sessions), `leverage` (`<0.5`, `0.5-1`, `1-2`, `2-4`, `4+`) |

Never sent: prompts, replies, tool input or output, file paths, project, session or terminal
names, titles, tokens, credentials.

## Where it goes

Reports go to [TelemetryDeck](https://telemetrydeck.com) (`nom.telemetrydeck.com`, namespace
`com.yaakanban`), one signal per report, type `Yaak.daily`. The fields above become string tags:
`Yaak.day`, `Yaak.schema`, `Yaak.integration.<agent>`, `Yaak.setting.<name>` (`on`/`off`),
`Yaak.count.<event>`, `Yaak.figure.<name>`, plus TelemetryDeck's own names for version, build,
macOS, architecture and language. `install_id` is not sent as is: the signal's user is its SHA-256, which TelemetryDeck
salts and hashes again; it stores no IP address. Settings › 查看 shows the signal itself.

The build reads the App ID from `Info.plist` (`YaakTelemetryDeckAppID`), committed in
`Resources/Info.plist`; `YAAK_TELEMETRYDECK_APP_ID` replaces it at bundle time (an empty value
there is ignored). A bundle whose App ID is empty sends nothing. On the free plan TelemetryDeck
indexes new events between hourly and daily, so the dashboard lags behind.
