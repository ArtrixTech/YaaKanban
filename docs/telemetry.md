# Telemetry

Off by default. When you turn it on (the one-time prompt, Settings › Privacy and feedback, or
`yaak telemetry on`), the app sends **one report per local day it ran**, after that day ends. A
send waits up to an hour for a network (the first tick of a day is often right after waking);
one that still fails is dropped, not retried; at most the last 7 unsent days are kept. `DO_NOT_TRACK=1`
in the app's environment keeps it off, and `yaak telemetry on` refuses under it. Only the app sends; `yaak` and agent hooks never use the network.

Settings › View shows today's report so far, with setup and settings as of now (a report carries
them as at send time). `yaak telemetry status` shows the
state, install id, the last reported day, how the last send ended (accepted, HTTP status or
network error) and whether this build has an Aptabase App Key. Turning it off deletes the unsent counts.

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
| `integrations` | per agent: `installed`, `outdated`, `needsAuthorization`, `notInstalled`, `notDetected` |
| `settings` | on/off: `show_panel`, `recent_stats`, `flash`, `review_flash`, `stale_tint`, `wave_tab_switching`, `pi_auto_title`, `launch_at_login` (as at send time) |
| `counts` | times that day, bucketed like `sessions` below: `panel_toggle`, `jump_wave`, `jump_iterm`, `jump_terminal`, `jump_editor`, `jump_other`, `jump_unknown`, `resume`, `approval_allow`, `approval_deny`, `approval_timeout`, `rename`, `pin`, `feedback_open`, `integration_install`, `integration_uninstall`, `integration_fail`, `spool_replay` |
| `figures` | ranges, not values: `sessions.<agent>` and `turns.<agent>` (`1`, `2-5`, `6-20`, `21-100`, `100+`), `agent_hours` (`0`, `<1`, `1-3`, `3-8`, `8-24`, `24+`), `parallel_peak` (as sessions), `leverage` (`<0.5`, `0.5-1`, `1-2`, `2-4`, `4+`) |

Never sent: prompts, replies, tool input or output, file paths, project, session or terminal
names, titles, tokens, credentials.

## Where it goes

Reports go to [Aptabase](https://aptabase.com) (US region, `us.aptabase.com`), one event per
report, named `daily`. Version, build, macOS and language travel as Aptabase's system props; the
fields above become string props: `day`, `schema`, `arch`, `integration.<agent>`,
`setting.<name>` (`on`/`off`), `count.<event>`, `figure.<name>`. `install_id` is not sent as is:
the `install` prop is its SHA-256, so days from one install can be linked without the id itself.
Each report is its own session, timestamped when it is sent (Aptabase refuses events over a day
old), so a backlog day shows up under the send date; `day` says which day it covers. Debug builds
send as debug data (the dashboard's Debug/Release switch). Settings › View shows the event itself.

On Aptabase's side: it looks up country and region from the sender's IP and stores those, and
counts a daily user as a salted hash of IP and User-Agent (`macOS/<major> <lang>`); it does not
store the IP itself.

The build reads the App Key from `Info.plist` (`YaakAptabaseAppKey`, like `A-US-…`; the region
part picks the host), committed in `Resources/Info.plist` (YaaKanban's app is in the US region); `YAAK_APTABASE_APP_KEY` replaces it
at bundle time (an empty value there is ignored). A bundle whose App Key is empty sends nothing.
Aptabase answers 200 even for an unknown key; its body then carries an `error`.
