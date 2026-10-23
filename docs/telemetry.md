# Telemetry

Off by default. When you turn it on (the one-time prompt, 设置 › 隐私与反馈, or
`yaak telemetry on`), the app sends **one report per local day it ran**, after that day ends. A
failed send is dropped, not retried; at most the last 7 unsent days are kept. `DO_NOT_TRACK=1`
in the environment keeps it off. Only the app sends; `yaak` and agent hooks never use the network.

Settings › 查看 shows today's report exactly as it will be sent. `yaak telemetry status` shows the
state, install id and endpoint. Turning it off deletes the unsent counts.

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
| `counts` | times that day: `panel_toggle`, `jump_wave`, `jump_iterm`, `jump_terminal`, `jump_editor`, `jump_other`, `jump_unknown`, `resume`, `approval_allow`, `approval_deny`, `approval_timeout`, `rename`, `pin`, `feedback_open`, `integration_install`, `integration_uninstall`, `integration_fail`, `spool_replay` |
| `figures` | ranges, not values: `sessions.<agent>` and `turns.<agent>` (`1`, `2-5`, `6-20`, `21-100`, `100+`), `agent_hours` (`0`, `<1`, `1-3`, `3-8`, `8-24`, `24+`), `parallel_peak` (as sessions), `leverage` (`<0.5`, `0.5-1`, `1-2`, `2-4`, `4+`) |

Never sent: prompts, replies, tool input or output, file paths, project, session or terminal
names, titles, tokens, credentials.

## Server

`server/telemetry` is a Cloudflare Worker with D1, one row per install per day, and it stores
no IP address. See its README for deploying. The build reads the endpoint from `Info.plist`
(`YaakTelemetryEndpoint`), set at bundle time from `YAAK_TELEMETRY_ENDPOINT`. Builds without it
send nothing.
