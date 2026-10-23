# Devlog

## feat(feedback): add opt-in daily telemetry and prefilled issue feedback

`pending` | 2026-10-23

- **Changes**: spec §6 (feedback & telemetry decisions), §1 notes the only network traffic. YaaCore `Telemetry.swift`: `TelemetryEvent` (fixed counters, jump by terminal kind), `TelemetrySetting`, `TelemetryReport` (schema 1), `TelemetryFigures` (sessions/turns per agent from turns started that day), buckets, day keys, `DO_NOT_TRACK`, `TelemetryLedger` (`Paths.telemetry` = `telemetry.json`: consent, asked, install id, per-day counts, lastSent; read-modify-write). YaaIntegrations `Feedback.swift`: `Diagnostics` (versions, integration status, app listening, spool, db size, telemetry; no paths) and `Feedback.issueURL` (issue-form template + `diagnostics` field). App: `TelemetryReporter` (counts, tick sends each finished day once via ephemeral URLSession, preview, consent alert 3 s after first launch of a build with an endpoint), `FeedbackPrompt` (diagnostics shown, optional, then GitHub issue), menu 反馈…, settings 隐私与反馈 (toggle, 查看, 重置 id, 反馈…; replaces the About issue link). Counters in AppModel (jump, resume, approvals, rename, pin, spool replay), panel toggle, settings installs. `yaak doctor`, `yaak telemetry status|on|off`. `Info.plist` `YaakTelemetryEndpoint` (empty), `bundle.sh` sets it from `YAAK_TELEMETRY_ENDPOINT`. `.github/ISSUE_TEMPLATE` bug/feature forms. `docs/telemetry.md` lists every field. README, Architecture updated.
- **Reason**: understand usage anonymously and give users a feedback path, without breaking the local-first promise.
- **User feedback**: "需要研究给本项目加入tlememetry，匿名了解用户使用情况，还要加入反馈功能。" / "先做1-2阶段。1可以默认关闭 2网站/hbrwcask都 3自建 4要" / "在新的分支+新的工作树实现。"
- **Process**: `make test` (117 pass, +12). End to end: app built with `YAAK_TELEMETRY_ENDPOINT` pointing at a local `wrangler dev`, temp HOME/YAAK_HOME, ledger seeded with yesterday's counts → one row in local D1 with those counts, ledger `lastSent` = yesterday. `yaak doctor` / `telemetry status|on|off` and `DO_NOT_TRACK` refusal checked on a temp YAAK_HOME. Snapshots: menu shows 反馈…; settings section renders (endpoint-less build: toggle disabled, footer says so).
- **Result**: telemetry off and unavailable until a release is built with an endpoint; feedback works now.
- **Notes**: settings flags are as at send time, not per day. Consent asked once per `telemetry.json` (existing users see it on their first launch of a build with an endpoint). The feedback/consent dialogs (NSAlert accessory views) were not clicked through on screen. `fixture-report.json` ties the Swift report to the server validator; regenerate with `YAAK_UPDATE_FIXTURES=1 make test`.

## feat(telemetry): add the Worker that stores daily reports

`af5bf04` | 2026-10-23

- **Changes**: `server/telemetry`: Cloudflare Worker (`POST /v1/daily`), strict validator (`src/validate.js`: known fields only, UUID id, day within −2…+10 days, short version strings, bounded maps, bucket-shaped figures), D1 schema with one row per (install_id, day), README covering deploy, queries and free-tier notes. Node tests, including a fixture the Swift tests write.
- **Reason**: phase 2 of the telemetry plan; the user chose a self-hosted backend.
- **User feedback**: "先做1-2阶段。… 3自建，免费用量应该足够？ 4要"
- **Process**: `npm test` (3 pass); `wrangler@4.20.0 dev --local` + local D1: a valid report gives 204, a resend of the same day stays one row, an unknown field gives 400, GET gives 405.
- **Result**: ready to deploy; `database_id` in `wrangler.toml` is a placeholder.
- **Notes**: no IP stored; rate limiting is left to a Cloudflare WAF rule (README). Bump `schema` and update the validator and fixture together.

## feat(panel): show the leverage direction arrow on the panel

`aeada89` | 2026-10-22

- **Changes**: RecentFigures' unfolded branch puts the slim rail's direction arrow (up/level/down from `direction(trend)`) beside the 杠杆 caption; spec notes it.
- **Reason**: the expanded panel showed the curve but not the at-a-glance direction.
- **User feedback**: "需要给展开后的悬浮窗增加杠杆的趋势显示" / "趋势的意思是上中下箭头"
- **Result**: arrow at 9 pt bold in the direction tint; figure width and `RecentFigures.height` unchanged.
- **Notes**: placed by the caption, not the value, so a wide value (e.g. 12.3×) keeps its 70 pt column.

## fix(rail): flash slim cards like the full ones

`94e7bf3` | 2026-10-22

- **Changes**: the slim card used plain `.card`, so neither the waiting-on-you nor the review flash reached it; it now uses `sessionCard(_:hover:radius:stale:)` with radius 6 and `stale: false`. `SessionSurface`, `Flash` and `Stale` take the corner radius. Spec notes the slim rail flashes too.
- **Reason**: 56a5e4e said both rails flash; only the folded (non-slim) rail did.
- **User feedback**: "超窄版本还没有闪。"
- **Process**: `make test`; `make install`.
- **Result**: slim cards pulse in their status tint when the full card would.
- **Notes**: the blue left-alone wash stays off on slim cards (color is only an accent there); pass `stale: true` to change that.

## feat(panel): flash a finished turn left unreviewed at the Mac

`56a5e4e` | 2026-10-22

- **Changes**: `Attention.reviewFlashes(_:presentSince:now:after:)` (default `reviewFlashAfter` 10 min): a `.review` card flashes once `now - max(unreadSince, presentSince) >= after`, never while away. `AppModel.presentSince` (launch time, nil while `awaySince` is set, the absence's end in `endAway`). `SessionSurface` ticks and flashes `.review` cards with the existing `Flash` in the green tint (both the panel and the slim rail use it). Settings 会话提醒: toggle 待验收久未查看时闪烁 (on) + 1–60 min stepper; footer notes only time at the Mac counts. Test `unreviewedTurnFlashesAfterTenMinutesAtTheMac`. Spec updated.
- **Reason**: a finished turn sitting green was easy to overlook while working on something else.
- **User feedback**: "新加入一个功能，任务完成待验收之后，绿色如果很久没人点但人在电脑前工作（阈值10min）就开始闪动" / "功能设置里面可以关"
- **Process**: `make test` (105 pass); `make install`.
- **Result**: as above; opening the card (markRead clears `unreadSince`) stops it.
- **Notes**: "at the Mac" reuses the activity tracker's away (no input 2 min, sleep); the clock restarts on return rather than pausing, so a short absence resets it. Not watched on a live 10-minute wait.

## feat(panel): add a time axis under the leverage trend

`8971c8c` | 2026-10-22

- **Changes**: `TimeAxis` under the panel's `Sparkline`: round clock times (step from 5 min to 6 h, at most three, the first ≥ the line's first point, kept off its ends) at the same x as the curve, and 现在 at the right end; `Sparkline` takes the ticks' fractions and draws a faint vertical guide at each. `RecentFigures.ticks(end:span:slices:)` maps time to the line: its first point is one window after the report's start. The fade mask stays on the curve only, so labels on the left are not faded. Spec sentence extended.
- **Reason**: the curve had no sense of when.
- **User feedback**: "还需要在悬浮窗的杠杆graph的位置增加时间刻度"
- **Process**: `make build`, `make install`; `yaak snapshot` panel.png shows 16:00, 17:00, 现在 under the curve with guides.
- **Result**: as above.
- **Notes**: `Sparkline.endInset` (6) is shared by the curve and the axis; change both together. Labels use `.tertiary`, adaptive on glass.

## fix(panel): show a session only once it got its first message

`e8429f5` | 2026-10-22

- **Changes**: `SessionState.isUnstarted` (hooked, no turns, idle or ended). `AppModel.isLive` and `allSessions` skip such sessions, so they are on neither the boards nor the history list. Test `sessionCountsAsStartedFromItsFirstMessage`. Spec updated.
- **Reason**: SessionStart alone created a card; a `claude`/`pi` window closed without a message (or one whose SessionEnd never came) left a card with nothing in it for the retention period.
- **User feedback**: "目前在打开了某个cc或者pi进程新对话之后就会有item显示在yaak，需要等发出第一条消息之后才显示，否则对应对话退出之后会一直显示在yaak不会消失"
- **Process**: `make test` (104 pass); `make install`.
- **Result**: a new session appears on its first prompt (or tool / permission / question, which also count as activity); unused ones never appear.
- **Notes**: sessions known only from session files (not hooked) are unaffected. Resume keeps the session id, so a resumed session with past turns shows as before. Unstarted sessions are still stored, just not displayed.

## fix(rail): draw the slim track's light in the system tint only

`2eb0187` | 2026-10-22

- **Changes**: `SlimTrack`'s running light drops the fixed RGB core (#9ED6FF) and the shadow glow from 68402b4: a `status.tint` gradient, opaque from 40 % to 80 %, fading at its ends, clipped to the track; the track stays tint 0.22.
- **Reason**: the panel's colors adapt because they are system colors (`.blue`, `.primary`) inside the `NSGlassEffectView` (a4c1571), which picks light or dark for the backdrop; a fixed RGB does not follow it.
- **User feedback**: "我是说 原来颜色不是都做了自动适配吗 这个颜色咋没适配"
- **Process**: `make install`.
- **Result**: the slim track uses only adaptive colors, like the glyph and clock beside it.
- **Notes**: don't put fixed RGB in panel content; `Sparkline`'s greens and `BrandGlyph`'s dot are fixed too (brand colors) and won't shift with the glass.

## fix(rail): keep the slim track's light vivid on glass

`68402b4` | 2026-10-22

- **Changes**: `SlimTrack` while running: the track is tinted (blue 0.22) instead of grey; the light is opaque through its middle (blue → light-blue core #9ED6FF → blue, fading only at its ends), 24 pt, with a blue glow (shadow r 2.5); masked only at the track's ends so the glow is not cut at the sides.
- **Reason**: the light was mostly translucent blue, which on the panel's `NSGlassEffectView` mixed with the wallpaper and read as grey-blue.
- **User feedback**: "超窄模式，活动agent的蓝色条，颜色没有做玻璃背景适配"
- **Process**: `make install`; `yaak snapshot` (opaque background, not glass) shows the core and glow.
- **Result**: as above. Not checked on the live glass panel in-session.
- **Notes**: snapshots render without the glass surface, so glass-specific looks need a real screen check.

## feat(panel): chart the leverage trend, slim rail keeps leverage

`6f06cab` | 2026-10-22

- **Changes**: `ActivityReport` gains `activeBuckets` / `presentAgentBuckets` (per-slice parts of leverage) and `rollingLeverage(window:)`. `RecentFigures` (height 40→52) computes one report of 47 slices of window/12 and takes its rolling leverage as a 36-point trend; the figure is the trend's last point. Unfolded: leverage as a 24 pt rounded hero, a `Sparkline` (smooth eased curve, green gradient with glow, fill down to the edge, dashed 1× line, latest point marked, gaps bridged) between it and 今日工时. Folded rail: leverage and "今日 x时". Slim rail: 杠杆, the number, and an arrow (up ≥ +10 %, down ≤ −10 % against one window back). Slim header uses `BrandGlyph`, the logo's columns and dot drawn in the text color without the tile. Test `rollingLeverageEndsAtTheWindowsLeverage`. Spec revised.
- **Reason**: the slim header's logo had a dark tile; the user wanted leverage back in the slim rail and its trend in the panel.
- **User feedback**: "超窄状态，logo换成无背景的版本，大小要合适。另外，数据还要显示，只显示杠杆。另外，悬浮窗的数据请对杠杆显示趋势（曲线）"; on the first chart: "太丑了。这块重做，要漂亮，有设计张力。"; on the first slim figure: "这个超窄模式的数据显示没法用"
- **Process**: first chart (thin blue line beside the number, gaps broken) rejected; redone as the hero layout. Slim figure "1.8×" truncated to "…×" at 20 pt and a mini sparkline was an unreadable blob; replaced by number + arrow. `make test` 103 passed; checked via `yaak snapshot`.
- **Result**: as above.
- **Notes**: the trend report is cached like the others (minute-aligned end, 47 buckets key). Rolling points under 60 s of present time are nil.

## feat(panel): show leverage and today's hours, redo the slim rail

`31fc3be` | 2026-10-22

- **Changes**: panel figures (`RecentFigures`) are now two: leverage over the recent window and today's agent hours (今日工时), folded or not; `QuickFigures` loses its `compact` mode (menu popover only). Slim rail 22→28 pt wide (inset 4): each card is a plain `card` with `StatusGlyph`, `AgentLogo`, a 2.5 pt `SlimTrack` (a light runs down it while running, tint while loud, faint otherwise) and a short clock (42s/7m/2h/3d). `FloatingPanelController.hotZone` extends the folded panel across the snap margin to the usable area's docked edge (+1 pt); global + local `mouseMoved` monitors start a peek there, and `checkPeek` keeps the peek while the pointer is in it. Spec, settings copy, Architecture updated.
- **Reason**: an hour of summed agent time was not intuitive; the slim rail's solid color blocks looked rough and showed nothing; with an 8 pt margin a pointer pushed to the screen edge sat outside the window and never unfolded the rail.
- **User feedback**: "一个杠杆，一个今日工作时长（缩成四个字）"; "如果现在是贴边状态，窗体和屏幕边缘还有缝隙，这里无法触发展开"; "对于在工作的项目要有动态，且现在颜色是整块，视觉上很粗糙，颜色应该还是点缀，也要显示一点信息"
- **Process**: `make test` 102 passed; `yaak snapshot` checked rail-slim and panel renderings.
- **Result**: as above. The edge trigger was not exercised with a real pointer in-session.
- **Notes**: global `mouseMoved` monitors need no Accessibility permission; the handler returns at once unless folded and visible.

## fix(reducer): keep replayed events from reopening a finished turn

`6ba2103` | 2026-10-22

- **Changes**: `SessionReducer.reduce` ignores an event older than the last turn's `endedAt` when the session is idle/ended. `StuckDetector`: a hooked running/stuck session with nothing after its last turn ended (no running tools or subagents) goes back to idle (unread unless opened after it ended). Pin glyph is amber (#FFBF00). Tests `replayedEventDoesNotReopenFinishedTurn`, `runningWithNothingAfterTurnEndIsFinished`.
- **Reason**: a pi session ("查询Kimi K3.1新信息") finished at 11:48:00 and was opened at 11:48:02; when `make install` relaunched the app at 11:50:44 a spooled tool event from inside the turn (a hook that missed its 90 ms send deadline) was replayed and `resume()` set it to running with `lastEventAt` unchanged; 10 min later it was flagged stuck.
- **User feedback**: "这一条已经运行完了，但是还显示在运行"; "钉住的钉子需要显示为amber颜色"
- **Process**: traced via `sessions.json` (turn `endedAt` = `lastEventAt`, status stuck) and `activity` lanes (review 11:48:00 → running 11:50:45, one second after app start). `make test` 102 passed; after install the session is idle, reviewed.
- **Result**: late events no longer revive finished turns; already-revived sessions repair on the next tick.
- **Notes**: the dropped late event loses its tool row; acceptable. Why the hook missed its deadline (app main thread busy?) is not established.

## feat(board): pin sessions to the top and rename them

`8f8b7e8` | 2026-10-22

- **Changes**: `Preferences.pinned` (newest first, UserDefaults `pinnedSessions`); `Board.ordered(…, pinned:)` puts pinned sessions above every tier; `Board.keepsManualOrder`. `AppModel.togglePin`, `isPinned`, `rename` (NSAlert with a text field; empty clears); `remove` drops the pin. `SessionState.customName` wins in `title`. `MoveMenu(session:)`: 置顶/取消置顶, 上移/下移 only where manual order applies, 重命名…; now also in the rail's context menu; history list gets 重命名…. Card title shows `pin.fill` when pinned. Tests `pinnedSitAboveEveryStatus`, `customNameWinsTitle`. Spec revised.
- **Reason**: 置顶 only moved a card to the top of its own status tier, and since b4e5e83 finished tiers ignore manual order, so it did nothing visible; no way to name a session.
- **User feedback**: "悬浮窗菜单需要允许置顶，现在置顶没反应。另外还需要允许重命名session"
- **Process**: `make test` 100 passed; `make install`.
- **Result**: pinned cards stay on top regardless of status; renamed titles persist with the session JSON.
- **Notes**: the custom name is not written back to the agent's transcript (/rename stays separate).

## feat(board): order finished sessions by freshness

`b4e5e83` | 2026-10-22

- **Changes**: `Board.ordered` sorts the 待验收 and 已验收 tiers by `quietSince` (max of last event and `reviewedAt`, set on every click), newest first; manual drag order and start time now apply only to waiting and running tiers. Board tests use running sessions for start/manual order; new `finishedSessionsFreshestFirst`. Spec gains the ordering rule.
- **Reason**: finished cards sat in start order, so the one just finished or just looked at could be buried.
- **User feedback**: "排序需要改变。在待验收的项目里面应该根据最近点击（新鲜程度）来排序。"
- **Process**: `make test` 98 passed.
- **Result**: the freshest finished card is on top of its tier; clicking a card brings it to the top of 已验收.
- **Notes**: dragging within 待验收/已验收 no longer sticks (freshness wins); ties break by id.

## fix(panel): keep recent figures in the folded rail, drop the range label

`409136f` | 2026-10-22

- **Changes**: `RecentFigures` sits outside the header branch in `FloatingPanelView`, so it shows folded too: `compact` (工时, 杠杆) in the rail, an empty spacer of the same height in the slim rail. `QuickFigures` has a fixed `height` (40) and no `title`; the "近1时" label is gone. Spec revised.
- **Reason**: with the strip only in the unfolded panel, cards jumped down by its height whenever the rail peeked or unfolded.
- **User feedback**: "悬浮窗显示应在展开和折叠都有，避免item高度位置变化。另外，近1h可以去掉。"
- **Process**: `make test` 97 passed; rail, rail-wide and rail-slim snapshots show the first card at the same y.
- **Result**: cards stay put across fold, peek and slim.
- **Notes**: the window is still set in settings (tooltip names it).

## feat(metrics): show recent figures on the panel, open main from the menu

`2020c34` | 2026-10-22

- **Changes**: `QuickFigures` (agent 工时, 杠杆, 回复, 轮; one-bucket report) replaces the popover's three numbers; `TodayFigures` and new `RecentFigures` wrap it. Floating panel shows `RecentFigures` under its header (not in the folded rail); `Preferences.showRecentStats` (default on) and `recentMinutes` (15/30/60/120/240, default 60), set in 设置 › 悬浮窗. `MenuHeader`: logo, name with a chevron, counts and today's figures are one button to the main window. Overview headline 全员等你 → 回复速度 (median, P90 in note); bottleneck becomes the tile 全部停工, replacing the 回复延迟 tile; summary says how fast you reply. Menu snapshot 230×230. Spec revised.
- **Reason**: the user wants live recent stats at a glance, a one-click way from the popover to the main window, and found 全员等你 unclear.
- **User feedback**: "用户需要实时查看最近的统计，悬浮窗上（指任务悬浮窗顶部）要有最近1h的统计（时间窗口可调，统计显示可关闭）……首页"全员等你"请去掉 听不明白 换成别的。……菜单栏悬浮窗顶部区域（logo、数据区域）做成点击跳转到主界面。logo右侧要有主界面的小箭头。"
- **Process**: `make test` 97 passed; snapshots of panel, menu, dashboard checked by eye.
- **Result**: panel strip reads e.g. 近1时 22分 · 0.9× · 2分34秒 · 1 轮.
- **Notes**: the rolling window ends on the next whole minute and redraws every 30 s, so `AppModel.report`'s cache (keyed by range) holds between redraws. 回复速度 delta hidden when either period is partly rebuilt (no reply data there).

## feat(metrics): read the overview as you and your agents

`7c760f7` | 2026-10-21

- **Changes**: `ActivityReport` adds `agentTime` / `agentTimeAway` (running session-time, and the part while away, from the sweep), `leverage` ((agentTime − agentTimeAway) ÷ activeTime), `longestRun` (longest running segment), `turnsBySession`. `DashboardView`: headline is Agent 总工时, 杠杆, 全员等你, 完成轮数; new `Highlights` row (最卖力, 最长连跑, 最忙的时候, 你不在时) and `AgentMix` (军团构成: running time per agent kind); 平均同时在跑 moves to the tiles; summary sentence leads with your time vs the agents'; `slotLabel` shared by the chart readout and 最忙的时候. Spec revised.
- **Reason**: figures read as machine stats; the user wants to see how they and their agents did today.
- **User feedback**: "感觉指标还得再有趣一点，还可补一些数据，例如可以评估，agent总工作时长等。可以从用户角度思考，我希望知道，今天我和我的agent军团工作效率如何。"
- **Process**: `make test` 97 passed (new `agentHoursWhileAway`). Day snapshot checked by eye; week/month rendered, not inspected.
- **Result**: real data today: 20.4 h agent time over 9.6 h, 2.0×, 46 min while away.
- **Notes**: leverage away time is excluded from the numerator, so overnight runs don't inflate it; they show in 你不在时. Leverage delta is hidden against partly rebuilt periods (no away data there). Leverage ≈ average parallel × (running share of active time), so the two often read close. This commit also carries the peer session's `bef18a9` hash fill in the devlog.

## fix(board): say when reopen can only copy, and keep the rail sized under alerts

`bef18a9` | 2026-10-21

- **Changes** (the code landed in `081c74d`: a parallel session's commit picked up these staged files; `bef18a9` carries only this entry): `TerminalJumper.runsResume` (Wave block, Terminal, iTerm, Codex app). `AppModel.jump` gives `askReopen` a reason when the command can't be run: Wave token expired, Wave block unknown, or another terminal; the button then reads "切到<app>并复制". `FloatingPanelController` runs `fit` through `RunLoop.main.perform(inModes: [.common])` instead of `DispatchQueue.main.async`.
- **Reason**: (1) a Wave session with no block (resumed before `5740cec`) offered "重新打开", but `resume` could only copy the command and activate the Wave app that was already in front: no visible effect. (2) Clicking a card on a peeked rail opens the alert; the peek ends under it and SwiftUI re-lays out narrow, but `fit` sat on the main queue, which does not drain during `runModal`. The window stayed wide.
- **User feedback**: "点重新打开没反应。另外，如果侧边栏是折叠状态，点击之后的询问是否重新打开弹窗会导致侧边栏窗体仍然是宽状态，但内容已经是窄状态了。"
- **Process**: probe app with `NSAlert.runModal`: `DispatchQueue.main.async` did not run inside the modal, `RunLoop.main.perform(inModes: [.common])` did, and an NSView display link in `.common` kept ticking (the slide still animates). Wave DB has no trace of the closed block, so the old session's tab can't be recovered.
- **Result**: `make build` ok, `make test` 96 passed; the staged tree alone builds. Alert flow not checked by hand.
- **Notes**: Ghostty, WezTerm and editors now get "切到…并复制" too; their `resume` never ran the command either.

## fix(wave): trade the swap token in resumed Wave blocks

`5740cec` | 2026-10-21

- **Changes**: `WaveAdapter.resumeScript` runs `wsh token "$WAVETERM_SWAPTOKEN" zsh` and evals it before `"$SHELL" -ilc <resume>`.
- **Reason**: a `wsh run -c` block gets only `WAVETERM_SWAPTOKEN` (one-time, 5 min). Wave's ZDOTDIR/rcfile trade it for `WAVETERM_BLOCKID`/`TABID`/`JWT`, but `-ilc` reads the user's rc, so the resumed agent's hooks sent `terminal = {termProgram: waveterm}` only. `isWave` was false, the jump fell to `hostApp(...).activate()` on the already-front Wave: no visible effect.
- **User feedback**: "点了这条一点反应没有，其他waveterminal+cc是正常的。"
- **Process**: the dead card (artrix-media, `claude --resume` under `/bin/zsh -c` under wavesrv) had only `WAVETERM_SWAPTOKEN`/`VERSION`/`WSHBINDIR` in its env. Read Wave v0.14.5 `shellexec.StartLocalShellProc` / `makeSwapToken` / `wsh token`. Fake-`wsh` test under zsh and bash: good token exports reach the child shell; bad or empty token is a no-op.
- **Result**: `make build` ok, `make test` 91 passed. Sessions resumed before this fix stay without a block until resumed again.
- **Notes**: `wsh token` output for zsh is `export K='v'` lines (POSIX), so the type is fixed to zsh. The token is consumed on first use; nothing else in the block needs it.

## feat(metrics): lead the overview with figures and one chart

`081c74d` | 2026-10-21

- **Changes**:
  - `DashboardView` rebuilt. From the top: header with 日/周/月 picker and ‹ › navigation (`Periods`: calendar day, week or month), a summary sentence, four headline figures (活跃, 平均同时在跑, 全员等你, 完成轮数) with deltas, and a stacked bar chart (running in blue, waiting in red, away shaded, a dashed step line for the previous period's running, hover readout; for a month, hours per day). Then 按项目 bars, detail tiles with deltas, and 会话明细 swimlanes, folded with the busiest 10. The 7-day table and sparkline are gone.
  - `ActivityReport`: `waitingBuckets` (away excluded); buckets span the whole range, not just up to now; `sessionTotals` (running / waiting with away time taken out, busiest first).
  - New YaaCore `ActivityPeriod.swift`:
    - `Period` (day / week / month);
    - `Periods`: range, previous, previousSoFar, and wall-clock slot edges.
  - `AppModel.report(_:buckets:edges:)`: the slot count is part of the cache key.
  - Snapshots: `dashboard-week`, `dashboard-month`.
- **Reason**: dozens of swimlanes made the page too tall to read, and the numbers didn't say plainly how things went.
- **User feedback**: "效率显示要大改，现在泳道太长，几十条高度很高，没法看。数据也看不明白，不够直观。上来应该就是直观的内容，之后才是细项。" "对比的颗粒度，默认day，可选一周/一月。"
- **Process**: Snapshots of the day, week and month views were checked. Comparing against a period with nothing recorded showed "↑ 全部"; it now shows no delta. Adversarial review found:
  - Month reports were recomputed every redraw. Finished ranges now stay cached for 10 min, and `previousSoFar` is rounded to 10 min.
  - Elapsed seconds shifted the "same point" across a clock change. It is now days in plus the same clock time.
  - Equal-width buckets drifted off midnight and 3-hour marks. Calendar edges replaced them (`Periods.edges`, `compute(edges:)`), and the chart draws slots equal-width via `slotFraction`.
  - Day ticks were at +h hours. They now use `bySettingHour`.
  - Bottleneck, utilization and reply deltas were shown against a partly rebuilt period. They are now hidden when either side has rebuilt time.
- **Result**: `make test` 96 passed. New tests: `bucketsSpanTheWholeRange`, waiting buckets, session totals, and the `Periods_` suite (DST day / week / month edges, same clock time, month cap, explicit edges).
- **Notes**:
  - A running period is compared to the same point of the previous one: days in, same clock time.
  - Late in a long month, the comparison is capped at the previous month's end, so March 29–31 compare against all of February.
  - The chart ghost covers the full previous period, aligned by slot index.
  - A repeated DST hour is one longer slot.

## feat(metrics): add efficiency overview and an experimental slim rail

`3712467` | 2026-10-21

- **Changes**:
  - YaaCore `Activity` (rows diffed from session states: lane / reply / turn / tokens / focus / away), `ActivityReport` (pure sweep: swimlanes, parallelism, utilization, bottleneck, reply percentiles, throughput), `ActivityBackfill` (session turns → running lanes + turn rows before recording began). `Store`: `activity` and `meta` tables.
  - App: `DashboardView` (概览, default selection) with swimlanes, tiles, daily summary, week-over-week; menu shows 3 numbers. Away = 2 min without input, sleep, or app not running (heartbeat; `awaySince` persisted in meta).
  - Slim rail: `settings.slimRail` (设置 → 悬浮窗, experimental). Folded rail is 22 pt wide; each card is a status-color block at its full-card height.
- **Reason**: show the user's multi-session parallelism and response efficiency; history wanted for days before recording.
- **User feedback**: "增加对用户的回复效率等指标的跟踪…核心目标是让用户直观看到最近的多任务并行状态/效率"; "效率面板好像没有历史数据啊。最好能看到。"; "超窄侧边栏，实验性功能…只用色块显示状态，高度保持不变，只是宽度降低。"
- **Process**: adversarial review found: bucket loop could hang on non-integer spans (fixed: step by index, test over 3600.37… spans); reports recomputed on every redraw (now cached per range, ≤ every 5 s, whole-minute week ranges); token rows per scan (now buffered, flushed per minute); replies counted after an already-reviewed turn or a resume days later (now only from needsInput/review); lane left open when a session turns into a sub-agent; lanes of sessions past retention never closed (tick `syncLanes` with `AppModel.display`); willSleep set inside a Task (now synchronous + didWake); dashboard stuck on yesterday past midnight (day offset); session delete no longer drops its activity.
- **Result**: `make test` 90 passed. Snapshots of dashboard, rail, rail-slim checked.
- **Notes**: tokens exclude cacheRead. Rebuilt time has no waits/away: utilization and bottleneck only count from `recordedSince` (meta key); the dashboard notes the rebuilt part. One reply row and the 5.04M token row recorded before the fixes remain in today's data.

## fix(board): show an agent exit as done, not ended

`b504d2f` | 2026-10-21

- **Changes**:
  - `SessionState.display`: `.ended` status maps like `.idle` (done / review / ended-if-dismissed).
  - New `AppModel.display(_:)`: `.ended` for a top-level session that is no longer live (retention over, or dismissed). The main-window list and the detail header use it.
- **Reason**: since ec8f485 the cards of exited agents (12 within the last 24 h) were on the panel labelled 已结束. To the user, "ended" means the idle threshold ran out (adjustable, 24 h default), not that the agent exited.
- **User feedback**: "现在已结束的都显示出来了，啥情况？" "结束=idle阈值超时（阈值可调，默认24h）"
- **Result**: `make test` passes (75, adds `agentExitIsNotTheEndForTheUser`).
- **Notes**: `sessionEnd` still clears `unreadSince`, so an exited session shows as 已验收 (done), not 待验收.

## fix(wave): bound token lifetime and report failed resumes

`e47e0a8` | 2026-10-21

- **Changes**:
  - `dropsWaveToken(now:gone:)`: a session whose process died (`AppModel.isGone`) loses its JWT 24 h after its last event, like an ended one. Before, idle or stuck sessions with a dead pid kept it forever.
  - `AppModel.waveRunners(for:)`: tries the session's own token first, then other tokens in the same tab. Live sessions come before gone ones, newest first, with duplicates removed.
  - `WaveAdapter.resume`: tries each runner in turn on a background queue (`runWaiting`: 5 s bound, exit status 0). If none opens the block, it shows an alert saying the command was copied.
  - The no-token dialog wording no longer promises a tab switch (that needs the experimental tab-switching setting): 切到 Wave 并复制.
  - A needs-input session whose process died no longer sets `unreadSince`: no result came of it, so it fades on retention instead of waiting for review forever.
  - `tick`/`scan` timers run in `.common` run-loop modes, so they keep going while the reopen dialog is open.
  - spec §5: idle wording corrected (it still said "30 min").
- **Reason**: review of ec8f485 and 5228841:
  - (1, high) The token could live forever.
  - (2) The dialog promised a tab switch.
  - (3, 4) Donor or own tokens whose block was closed failed silently, the original symptom.
  - (5) Dead waits stayed as review indefinitely.
  - (7) The modal paused the timers.
- **Result**: `make test` passes (74).
- **Notes**: Not addressed (pre-existing or low):
  - Codex `/new` leaves the old idle card on a live pid.
  - A reused pid looks alive.
  - The reopen dialog also shows for unknown terminals and Codex threads, where 重新打开 raises and copies, or opens the thread.
  - The ec8f485 devlog line "Cursor, OpenCode never send SessionEnd" is imprecise: Cursor has `sessionEnd`, and OpenCode sends it on `session.deleted` only.

## fix(wave): resume with a token borrowed from the same tab

`5228841` | 2026-10-21

- **Changes**:
  - `AppModel.waveRunner(for:)`: the session's own Wave terminal if it has a JWT, else the newest session in the same `waveTabId` that has one.
  - `TerminalJumper.resume(_:wave:)` → `WaveAdapter.resume(..., runner:)`: `wsh run` uses the runner's JWT/block/tab env when the session's own JWT is gone. Tab switching still uses the session's own tab/block.
  - Reopen dialog: app logo as the icon (`BrandMark.image`, was the blank generic icon). With no token anywhere in the tab, the dialog says Wave's authorization expired and offers 切过去并复制 (raise the tab, copy the resume command).
- **Reason**: clicking 重新打开 on a Wave card only switched the tab. Every ended Wave session in history had `waveJWT = nil` (f600089 dropped it 60 s after a clean exit), so `WaveAdapter.run` returned at its JWT guard without a word.
- **User feedback**: "waveterm的恢复目前无效" "能打开对应tab 但是没有开新的terminal并启动cc" (screenshot: the reopen dialog with a blank icon).
- **Process**:
  - `history.sqlite`: 21 ended Wave sessions in the last day, all without a JWT. 20 have a session with a JWT in the same tab.
  - Every stored donor JWT was accepted by Wave (`wsh getmeta -b <block> view` → `"term"`).
- **Result**: `make test` passes. Not run end to end here: that would open a block in the user's Wave.
- **Notes**: new ended sessions keep their own JWT for 24 h (ec8f485), so borrowing mainly covers sessions from before that.

## fix(board): keep every finished session until its retention ends

`ec8f485` | 2026-10-21

- **Changes**:
  - Removed `interruptedAt`, `interruptGrace`, `AppModel.terminalQuit` (NSWorkspace didTerminate observer) and `TerminalJumper.bundleId(of:)`.
  - `isLive`: `ended` lingers like a reviewed idle card (`idleVisibleSeconds`, 24 h default) again. The a1e9ea5 rule is back: a card hides when a top-level session on the same pid started at or after its last event (`/clear`, `/new`).
  - `StuckDetector`: a dead process no longer ends an idle session. A needs-input session whose process died goes back to idle (the wait is dropped, `unreadSince` set). Running sessions with a dead pid still go `stuck` ("进程已退出").
  - `dropsWaveToken`: ended + (dismissed or 24 h quiet). The 60 s clean-exit grace is gone.
  - Clicking a gone session (ended, or pid dead) shows an NSAlert: 重新打开 (resume in original terminal) / 复制恢复命令 / 取消.
- **Reason**: f600089 review:
  - Codex, Cursor, OpenCode and unhooked Claude never send SessionEnd. A plain Ctrl-D became "interrupted" through the dead pid.
  - The Wave-crash rule depended on SessionEnd arriving before didTerminate, which was never established.
  - The user's model: a conversation stays in their head whether or not its process lives. Don't judge crashes; check the process only when clicked.
- **User feedback**: "无论对应进程是否被关掉，对应对话的记忆仍然活跃在用户心里面。进程在不在和yaak管理里面是否把它标记为ended没关系。" "不需要判断崩溃，只需要确认对应进程是否在就行。不在了但仍然idle就点击然后提示进程不在了是否重新打开。" The user chose: any SessionEnd is kept for 24 h like idle.
- **Process**:
  - Checked pi 1.x: `session_shutdown.reason` is `"quit"` for both Ctrl+D and SIGHUP, so the reason cannot separate a crash from an exit.
  - The 15:49 Wave crash sessions in `history.sqlite` were all `ended` by a clean SessionEnd.
- **Result**: `make test` passes (74). Today's crash cards are back on the panel (they are within 24 h).
- **Notes**: Stored rows with an `interruptedAt` key decode fine (unknown keys are ignored).

## fix(board): only interrupted sessions stay on the panel

`f600089` | 2026-10-21

- **Changes**:
  - New `SessionState.interruptedAt`. It is set in two cases:
    - `StuckDetector` sees an idle or needs-input session's process die without SessionEnd.
    - `AppModel.terminalQuit` (`NSWorkspace.didTerminateApplicationNotification`) sees the terminal app of a session that ended within `interruptGrace` (60 s) quit.
  - The reducer clears it on SessionEnd, and whenever the session leaves `ended`.
  - `isLive`: an ended card shows only when it is interrupted. The pid-superseded rule is removed.
  - Wave JWT for a clean exit: dropped after the 60 s grace, not 24 h.
  - `TerminalJumper.bundleId(of:)` and `termProgramIds` were factored out.
- **Reason**: a1e9ea5 showed every ended session (15 cards, mostly normal `/exit`), which the user did not want. A Wave crash makes agents send a clean SessionEnd on SIGHUP. What tells it apart is the terminal app quitting right after: sessions ended at 15:49:03–07, and Wave was back at 15:49:14.
- **User feedback**: "已结束的卡片现在会显示在悬浮窗 这是预期外的。"
- **Result**: `make test` passes (74).
- **Notes**:
  - Older sessions have no `interruptedAt`, so today's crash cards stay hidden. They can still be resumed from the main window.
  - Not verified live: that NSWorkspace posts didTerminate for a Wave crash or force quit (AppKit documents it for any app exit).


## feat(board): keep ended sessions and resume them in their terminal

`a1e9ea5` | 2026-10-21

- **Changes**:
  - `AppModel.isLive`: `ended` cards linger like reviewed idle ones (`idleVisibleSeconds`, 24 h default). They hide when they are sub-agents, or when a top-level session with the same `agentPid` started at or after their last event (`/clear`, `/new`).
  - Clicking a gone session (`AppModel.isGone`: ended, or pid dead) calls `TerminalJumper.resume`:
    - Wave: switch tab and run `wsh run --cwd <cwd> -c '"$SHELL" -ilc <resume>; exec "$SHELL" -il'` with the stored JWT.
    - Terminal/iTerm: new window via `osascript`.
    - Other or unknown terminal: raise it and copy `cd … && <resume>`.
    - Codex app with no terminal: open `codex://threads/<id>`.
  - `SessionState.resumeCommand`, per agent. Ids starting with `-` are refused.
  - The Wave JWT is now kept for ended sessions until the card is dismissed, or for `waveTokenTTL` (24 h) from the last event. Before, it was dropped as soon as the session ended. `tick` also strips aged-out tokens.
  - UI: resume labels, plus a new 复制恢复命令 menu item. spec §5 updated.
- **Reason**: a Wave crash SIGHUPs every agent. SessionEnd hooks fire, and `ended` used to hide the card at once, so the work could not be found.
- **User feedback**: "跑在waveterm的claudecode/pi等，在waveterm挂掉必须重启的时候，右侧悬浮窗任务都消失了……导致我无法找回我的工作". Chose: keep ended cards like idle with 24 h retention, and resume in the original terminal.
- **Process**:
  - DB showed 3 pi and 3 Claude sessions ended at 15:49:03–07, right after Wave restarted at 15:49:14.
  - Verified that a pre-restart JWT still authenticates (`wsh getmeta`). The JWT is long-lived and bound to a blockid; the signing key persists in Wave's DB.
  - `wsh run` lands in the token's tab. A non-login `-c` shell lacks `~/.npm-global/bin`, so `$SHELL -ilc` is used.
  - The adversarial review found five issues; four were fixed:
    - The pid-superseded check hid OpenCode sibling sessions; it now uses the last event and top-level sessions only.
    - The unknown-terminal fallback copied no resume command, and a Codex CLI session opened the Codex app.
    - Flag-like ids are now refused.
    - Clicks extended the JWT TTL.
- **Result**: `make test` passes (73).
  - Live Wave resume was only exercised with test commands (they spawned and closed blocks).
  - Terminal/iTerm AppleScript was not run.
- **Notes**:
  - The 6 sessions from today's crash already lost their JWT, so clicking them switches tab and copies the command.
  - Known trade-off: headless `claude -p` runs and normal `/exit` now also leave an 已结束 card for the retention period.
  - Resuming makes a new Wave block; the old block stays.

## fix(ui): repair the Codex logo path for CoreSVG

`5384ebf` | 2026-10-21

- **Changes**: rewrote the single path in `Resources/AgentIcons/codex.svg` with explicit separators between every number and arc flag. Same geometry, no code change.
- **Reason**: the monochrome Codex logo rendered as a broken blob. CoreSVG logged an error and mis-parsed the compact path (packed decimals like `1.223.123.123`, packed arc flags like `012.285`). The old colored asset hid this behind its white plate and gradient.
- **User feedback**: "之前做了logo统一，Codex Logo看起来不对劲。请修复"
- **Process**: rendered all five SVGs to PNG through `NSImage` (the app's loader). Before: Codex malformed and a CoreSVG error. After: correct cloud mark with the `>_` cutout and no CoreSVG error. The other four were unaffected.
- **Result**: `make app` passed.
- **Notes**: when adding lobe-icons SVGs, render them through NSImage first; CoreSVG is stricter than browsers on compact path syntax.

## style(ui): unify agent logos in white

`80a53e7` | 2026-10-21

- **Changes**: `AgentLogo` renders every SVG and fallback symbol in white; Claude and Codex use monochrome assets. Removed the Codex background plate and gradient while preserving its mark and terminal cutouts. Recorded the visual decision in `docs/spec.md`.
- **Reason**: agent logos mixed brand colors and inherited text colors across the UI.
- **User feedback**: "需要把Logo统一一下（不同agent的），都统一成白色。"
- **Process**: independent read-only review confirmed all five UI call sites use `AgentLogo` and checked the Codex alpha-mask pitfall. `git diff --check` passed.
- **Result**: `make app` passed; all five packaged SVGs match the source assets. Existing `Notifier.swift` Sendable warnings remain.
- **Notes**: no architecture change; no live app visual check or installation performed.

## fix(codex): open the thread on click; ignore the app's background calls

`108a666` | 2026-10-21

- **Changes**:
  - `TerminalJumper`: when the Codex agent's host app is the Codex desktop app (`com.openai.codex`), open `codex://threads/<session_id>` with that app instead of only activating it. Ids that are not hex/dash are never put in the URL. Codex in a terminal keeps the old path.
  - `Normalizer.isCodexBackground`: Codex hook events without `transcript_path` produce no events. `AppModel` deletes stored Codex sessions without a transcript path on load.
- **Reason**: clicking a Codex card only raised the window; the Codex app's own model calls (next-message suggestions and their safety check, "hyperpersonalized suggestions", memory consolidation in `~/.codex/memories_v2`) fire hooks and became cards.
- **User feedback**: "codex兼容性问题比较大，最大问题是点击无法自动跳转对应的对话…很多系统内部的 agent调用也会被视为一个新的thread" / "都修掉。已经存进历史的 6 条后台调用记录，要一起清掉"
- **Process**: read-only investigation of the Codex app bundle (`codex` URL scheme; `open-url` routes `codex://threads/<id>` to `localConversation`) and today's history: 6 of 8 Codex rows had no transcript path, rollout file or `session_index.jsonl` entry; both real threads had all three. Sub-agents already fold into the parent (their hooks carry the parent `session_id`). "Clarify task req…" in the screenshot is a real user thread whose first message was "1". New test `threadsWithoutRolloutAreIgnored` fails without the filter.
- **Result**: `make test` 72/72.
- **Notes**: The rule rests on 8 rows. `codex exec --ephemeral` runs would also be hidden. If a real thread's first SessionStart ever arrives without a path, only that event is lost. The deep link was not opened during investigation.

## feat(pi): session titles from /name or an auto title; ended cards show ended

`89084c8` | 2026-10-21

- **Changes**:
  - New `AgentEvent.Kind.titleChanged` (yaak schema event `title`) sets `peek.title`; handled like a snapshot, so it neither counts as activity nor revives a dismissed card.
  - pi extension: forwards `pi.getSessionName()` on `session_start` and every `session_info_changed`. On the first typed prompt of an unnamed session (not `/…`, not extension input), fires a non-awaited `ctx.modelRegistry.streamSimple` call on the session's model (no reasoning, 64 tokens, 30 s timeout) and `pi.setSessionName()`s the result unless the user named it meanwhile.
  - Settings › "pi 兼容性" › "自动生成会话标题", default on. Stored as the absence of `<YAAK_HOME>/pi-auto-title-off` (`Paths.piAutoTitleOff`) so the extension can read it; the extension resolves YAAK_HOME the same way `Paths` does.
  - `SessionState.display`: an idle session the user ended shows `.ended`, not `.done` ("已验收").
- **Reason**: pi 1.3.0 never names sessions itself (only `/name`, `--name`, `setSessionName`); our extension also never forwarded the name, so cards fell back to the first prompt. Ending a finished card cleared `unreadSince` and so read as reviewed.
- **User feedback**: "pi里面现在似乎不会自动拿到标题…" → "1和2都做，2放到设置里面关于pi的兼容性可选项。默认开。" / "如果是待验收状态，点了x之后（悬浮窗）依然会回到已验收而不是结束状态"
- **Process**: checked pi's session-manager/agent-session source (setSessionName emits session_info_changed to extensions; session_info is buffered until the file is first flushed). Ran the generated extension under bun with a stubbed pi/ctx and temp HOME/YAAK_HOME: one model call, `/name x` skipped, quotes and trailing 。 stripped, `title` event spooled; with the off file no call. New tests `piNameBecomesTitleWithoutCountingAsActivity`, `endedFinishedSessionShowsEndedNotReviewed`.
- **Result**: `make test` 71/71. Needs `yaak install --agent pi` (or 更新 in settings) to take effect; not run against a real pi model.
- **Notes**: The title call runs alongside the first turn and is billed to the user's pi provider. Existing named sessions get their title on the next session_start. The toggle is read at each session's first prompt, so it applies without reinstalling.

## fix(hooks): bound hook time, bind approvals to the shown request, keep Codex indexes

`a75c263` | 2026-10-21

- **Changes**:
  - Hook deadline: `yaak hook` reads stdin via `UnixSocket.readAll` (poll, 60 ms from process start, 16 MiB cap) instead of `readDataToEndOfFile`, and `UnixSocket.send` takes a `deadline` (90 ms for hooks) enforced per write via SO_SNDTIMEO. Missed sends are spooled. The server now drops lines without a trailing newline, so a line cut off at the deadline is never both ingested and spooled.
  - Approvals: `AppModel.decide` requires `requestId`; the panel buttons pass the id of the request they show. Before, a nil id skipped the check, so a button rendered for request A could approve a newer request B.
  - Codex: `ClaudeShapedHooks.edit(keepIndexes:)`. On Codex install, surplus entries of ours are re-pointed at the current yaak rather than dropped, and groups that were already empty stay. Dropping them shifted the index of every later hook, breaking Codex index-keyed trust. Uninstall still removes ours.
- **Reason**: housekeeping audit (gpt-6-astra, high) findings: hooks could block an agent indefinitely; panel approval not bound to a request; Codex reinstall could shift indexes.
- **User feedback**: "用gpt-6-astra（high）审计当前代码实现，做housekeeping…" / "按照建议修复"
- **Process**: new tests `sendGivesUpAtDeadline`, `readAllStopsAtDeadlineAndLimit`, `serverIgnoresUnterminatedLine`, `codexReinstallNeverDropsEntries`; the last fails on the old `JSONHooks.swift` (baseline). Real binary with stdin left open: exits 0 in 66 ms and spools (temp `YAAK_HOME`). Independent review found the cut-off-newline double delivery, fixed here.
- **Result**: `make test` 69/69. Not installed or checked live.
- **Notes**: Known trade-offs: parsing/encoding a large payload after the read is outside the budget; events that miss the deadline while the app is slow are only replayed on next app start; re-pointed duplicate Codex entries still fire twice. Remaining audit items (spool delete-before-persist, swallowed SQLite errors, unchecked Int conversions, etc.) are not addressed.

## feat(board): drop project groups; hand-set height sticks; width changes keep the top

`4c6fd08` | 2026-10-21

- **Changes**:
  - Board: `Board.ordered` replaces `Board.groups` and `BoardGroup`. Order is status tier, then manual order, then start time. There is no project clustering and no group header, and every card shows its project name. Context-menu moves step card by card.
  - Height: dragging the resize grip sets `panelListHeight` (new key `panelListHeightManual`). The panel then keeps that height whatever the content, and the list scrolls. Letting go at the minimum clears it, and the list follows its content again.
  - Position: a width change (unfolding the rail, the width grip) keeps the panel's top edge. Before, the panel re-centred on its middle as the cards rewrapped, so they moved up or down.
- **Reason**: "去掉项目分组概念。另外，高度需要优先保持用户手动调整后的，除非用户手动拉到最低才回到自动" / "横向展开的时候item的高度位置不变化"
- **Result**: `make test` 65/65. Installed. Not checked live.

## fix(panel): height follows the content both ways, growing about its middle

`65b00d3` | 2026-10-20

- **Changes**:
  - The list grows whenever its content is taller than the height set by hand. Before, it grew only within 2 s of a new card or sub-agent id appearing. It shrinks with the content as before.
  - Content-driven height changes keep the panel's middle still, so it grows up and down at once. Snapped to the top or bottom of the screen, it keeps that edge.
  - Dragging the resize grip or folding the list (header chevron) holds the top edge for 0.6 s (`PanelRoom.holdTop`).
- **Reason**: "随着新的任务派发出来，悬浮窗的高度不会自己增加，而是会把多出来的内容折叠进去……任务已经减少的时候自动降低高度……上下两边同时增长的"
- **Process**: A new session often gets its content (reply, tool, sub-agents) after the 2 s window had closed. Then the list stayed at the old height with the new card under the fade.
- **Result**: `make test` 66/66. Installed. Not checked live with real sessions arriving.

## feat(board): one priority-ordered list; project runs get a header line, not a box

`d486a42` | 2026-10-20

- **Changes**:
  - `Board.groups` orders every card by status tier first: needs you / stuck, then to review, then running, then reviewed.
    - Inside a tier, one project's cards sit together.
    - A project that ends a tier opens the next, so its cards stay adjacent across the boundary.
    - Groups are now runs of consecutive cards. A project can have runs in several tiers, with ids of the form `dir#first-card`.
  - `BoardList` is one flat list. A run of two or more cards gets a `GroupHeader` (folder, name, count, hairline) above it, with no background box. Every card has the same width.
  - Status tiers have no headers of their own: card colours already tell them apart.
- **Reason**: "现在的分组在UI上面会让所有的卡片都比其他部分组的要窄一点……目前的优先级顺序又一定要保证的". The user chose a status-first order with project clustering and no status headers.
- **Process**: Before, a group ranked by its most urgent card dragged its reviewed cards above other projects' cards waiting for review. Checked with `yaak snapshot` (folded rail).
- **Result**: `make test` 66/66 (new `strictPriorityAcrossProjects`).

## fix(panel): Liquid Glass surface that adapts to what is behind it

`a4c1571` | 2026-10-20

- **Changes**:
  - On macOS 26 and later the floating panel sits on `NSGlassEffectView`. The SwiftUI content is its `contentView`, so the glass picks light or dark for the content to suit the backdrop.
  - The fixed colour wash from a328e83 is removed.
  - Before 26, the `.popover` blur with the white hairline stays.
  - `HoverView` is now a plain view that holds the surface. The content goes in `content`, which clips during slides.
- **Reason**: "我感觉解决方案不能是只靠拉深背景颜色实现啊。还是得自适应。" "别的app咋做到自适应的？" System surfaces adapt through the material. They never sample the screen.
- **Process**:
  - Sampling the screen behind the panel would need the Screen Recording permission, and the user turned that down.
  - Not checked by eye: screencapture has no permission here, and `yaak snapshot` draws no backdrop.
- **Result**: `make test` 65/65. Installed.

## feat(cards): opening a reviewed session restarts its blue clock

`cfce1ef` | 2026-10-20

- **Changes**:
  - `SessionState.reviewedAt` is set each time the user opens a session (click, jump, "标记已验收").
  - `quietSince`, the later of the last event and the last look, is what blue tint and retention now count from. Opening a blue card clears it, and it turns blue again only after "开始变蓝" has passed once more.
  - The settings footer says the clock restarts on each look.
- **Reason**: "验收很久没看变蓝的效果，需要加上，如果用户这次点进去了，重置计时器（这相当于用户明确看了但是没有继续给反馈）。"
- **Process**: `markRead` used to stop at the first look, since it only cleared `unreadSince`. Now every look is recorded.
- **Result**: `make test` 65/65 (new `lookingAgainRestartsTheBlueClock`). Installed.

## fix(panel): readable over light backgrounds

`a328e83` | 2026-10-20

- **Changes**:
  - The floating panel lays its own window colour over the blur: 60% in Dark, 55% in Light. It follows appearance changes.
  - The hairline edge is dark in Light mode. It was always white.
- **Reason**: "浅色背景效果很差 需要优化". Over a white wallpaper the bare `.popover` material in Dark mode turned mid grey. White titles were low contrast, and secondary text, card fills and edges nearly vanished.
- **Process**: A screen capture over a temporary white window failed: screencapture had no screen-recording permission here. `yaak snapshot` draws without the behind-window blur. Not checked by eye.
- **Result**: `make test` 64/64. Installed.

## fix(settings): retention as a segmented control

`5068953` | 2026-10-20

- **Changes**: "已验收会话保留" shows 4 / 8 / 12 / 24 hours as a segmented control instead of a pop-up menu.
- **Reason**: "做成平铺选择器 不要下啦菜单。"
- **Process**: Checked in a snapshot of a temporarily taller Settings window, then restored the size.
- **Result**: `make test` 64/64. Installed.

## feat(settings): retention picks from 4/8/12/24 hours, default 24

`65fddf0` | 2026-10-20

- **Changes**:
  - "已验收会话保留" is now a menu with 4, 8, 12 and 24 hours instead of a 30-minute stepper. The default goes from 8 h to 24 h.
  - A stored value from the old stepper snaps to the nearest choice on launch.
  - Shortening the retention pulls "开始变蓝" below it if needed.
- **Reason**: "已验收提醒保留，只可选4h/8h/12h/24h，默认24h"
- **Result**: `make test` 64/64. Installed.

## feat(settings): card reminder thresholds (flash, blue tint, retention)

`d966ec0` | 2026-10-20

- **Changes**:
  - New "会话提醒" section in Settings:
    - "已验收会话保留", moved from "悬浮窗": how long reviewed sessions stay on the board, and so when they count as ended there.
    - "需要输入时闪烁": an on/off toggle, plus "开始闪烁" from 5 to 600 s (default 30).
    - "看过未跟进的会话变蓝": an on/off toggle, plus "开始变蓝" from 1 min up to the retention time minus 1 (default 10 min). "最蓝" shows the resulting peak.
  - `Attention.flashes` and `Attention.staleness` take the threshold as a parameter. It defaults to the old constant.
  - The card's one-second timeline runs only when the matching reminder is on.
- **Reason**: "需要让我们之前加入的，几个小时没看的对话变蓝（渐变）的功能做设置项，允许调整阈值。包括item判定为不活跃（结束）的阈值等。"
- **Process**:
  - Other time thresholds: "卡住阈值" was already a setting. The 60 s sub-agent linger stays internal.
  - Checked the section in a snapshot of a temporarily taller Settings window, then restored the size.
- **Result**: `make test` 64/64 (new `thresholdsFollowTheSettings`).

## fix(panel): fold the peek at once on leaving; folded sub-agents fill their card

`977f718` | 2026-10-20

- **Changes**:
  - Peek: the panel folds as soon as the pointer leaves, with no 0.15 s dwell and no 4 pt margin.
    - `HoverView` now reports exits, and the exit runs the check directly. The 50 ms poll still catches exits that the event misses.
    - The check waits while a slide is running or a mouse button is held.
  - Folded sub-agents now use the full card's `SubagentSlots` metrics: 16 pt rows, 4 pt gaps, 6 pt padding. Every sub-agent is listed, with no "+N" cap.
- **Reason**: "展开状态，鼠标离开悬浮窗收起的时候不要有延迟，直接收起。" "现在在折叠状态有subagent的时候，还是有一行空行。"
- **Process**: The folded block was shorter than the full card's block, and the full card's block sets the card height. A card with no reply had nothing to take up the difference, so a blank line showed under the project. Checked with a temporary snapshot of cards with 1 and 3 sub-agents and no reply, then removed it.
- **Result**: `make test` 63/63. Snapshot: no gap under the project row. The instant fold was not checked with real pointer moves.

## feat(panel): grow for new cards; fade the overflow; sub-agents in folded cards

`53bfeeb` | 2026-10-20

- **Changes**:
  - When a new card or sub-agent appears, the list grows past the height set by hand for 2 s, so the new card shows whole. The cap is still the screen's room and 1400 pt. Growth comes from the list's measured height, so it happens after the card is laid out.
  - When the list is taller than the panel, its bottom 28 pt fades out. The fade goes away once the list is scrolled to the end. The list's bottom is tracked with `frame(in: .scrollView)`.
  - Folded cards show sub-agents under the tool line: status and name, at most 5 rows, then "+N 个子 agent". This covers child sessions (pi) and hook-reported sub-agents (Claude Code). The block is a single `FitStack` row, so it either shows whole or not at all.
- **Reason**: "对于新增任务的情况，需要确保悬浮窗高度自动调整，不要出现折叠" "悬浮窗高度低于实际内容高度的情况下，底部overflow需要有渐变遮罩" "subagent现在在折叠状态没有显示，需要显示。"
- **Process**:
  - Temporary snapshot views: a panel with a 330 pt room, and folded cards with 2 and 5 hook sub-agents built through `SessionReducer`. Both were removed afterwards.
  - Showing 3 rows left an empty gap, because the card keeps the full card's height, which lists every sub-agent. Raised to 5.
- **Result**: `make test` 63/63. The fade and the folded sub-agents were checked in snapshots. The growth on a new card was not seen live.

## feat(cards): flash when input waits unclicked; blue tint on reviewed turns left alone

`3ec371e` | 2026-10-20

- **Changes**:
  - Folded rail: no list-height grip. The bottom margin is 8 pt, the same as the sides and the gap between cards. The height is still set in the unfolded panel.
  - A session waiting on the user (`.needsInput`) flashes, with a pulsing red fill and edge, once it has waited 30 s without its card being clicked.
    - `SessionState.needsInputSince` records when it started waiting (set in `SessionReducer.apply`, cleared when it moves on).
    - `AppModel.acknowledged` records the last click on each card. A click after it started waiting stops the flash.
  - A reviewed, finished turn with nothing after it (`.done`) turns blue from 10 min after its last event. The tint is strongest halfway between 10 min and the "reviewed cards stay" setting (8 h by default, so at 4 h 5 min), then fades back to gray by the time the card leaves the board. The curve is a sine ramp each way, so the tint shows soon after it starts.
  - Logic in `YaaCore.Attention` (`flashes`, `staleness`), drawn by a `sessionCard` modifier. Only waiting and done cards tick (once a second).
- **Reason**: "折叠状态底部不应该有高度调整把手。应该左右下三边等宽。" "对于需要输入的状态，如果30s内没点击，请闪烁提醒。" "对于turn结束、验收了但是没有后续运行的turn，在10min后颜色稍微给一点蓝色……到（10min与……8h）中间的时间到达最蓝，此后颜色慢慢变回原来的灰色。"
- **Process**:
  - A temporary offscreen view of reviewed cards at 5, 60, 150, 245 and 400 min, plus a card waiting 60 s.
  - With smoothstep, the 60 min card was still almost gray. Switched to a sine ramp.
  - Removed the temporary view afterwards.
- **Result**: `make test` 63/63 (new `AttentionTests`: the flash threshold and click, the waiting time cleared on resume, the blue curve's zero points and peak).

## fix(rail): fill folded cards to the bottom; tighter rail margins

`07dde05` | 2026-10-20

- **Changes**:
  - Folded cards show the latest reply (or what the session needs, or why it is stuck) as a row of its own. It takes at least one line and grows by whole lines into the room left. The rows are status, title, tool, reply, project and numbers. `FitStack` keeps the rows that fit whole and shares the last few points out between the gaps (at most 3 pt each), so no blank line is left at the bottom. The live line no longer repeats the reply.
  - Rail margins: sides 8 pt, the same as the gap between cards. The bottom grip is 10 pt instead of 14. The card's inner padding is 8 by 7 instead of 10, and row spacing is 2.
  - Snapshots can force the rail folded (`PanelRoom.snapshotFolded`) even when the user pinned it open.
- **Reason**: "折叠状态底下又有空行了。解决。" "折叠状态，左右下的边框可以再窄一点，左右可以对齐卡与卡之间间距。另外卡内的margin可以稍微小一点点，这样最后一行还能放东西。"
- **Process**:
  - A first try spread the leftover height freely between the rows, and the gaps grew large. Capped at 3 pt.
  - Offscreen snapshots of the folded rail.
- **Result**: `make test` 60/60.

## fix(panel): narrow panel layout; folded cards without gaps or overflow

`49accb8` | 2026-10-20

- **Changes**:
  - At a small width the board header drops the "YaaKanban" name instead of pushing the buttons out of the window. Tool and token counts no longer wrap ("233.3 / M").
  - Folded cards lay out through `FitStack`, a column that shows its rows top down while they fit and leaves out the rest whole. The rows are status, title, live line, project and numbers. So the project and numbers sit right under the status with no gap, and nothing is cut in half at the bottom. The numbers fall back to tokens only, or nothing, when the rail is too narrow. The title keeps its two lines.
  - Folded cards have the full card's 10 pt padding, not 8, so both states have the same border.
- **Reason**: "小宽度窗口变形" "折叠状态仍然有空行" "折叠模式下和展开模式下的左右边框宽度不一致，以展开模式下的边框宽度为准" "这排版太紧张了，有溢出"
- **Process**:
  - Logged `FitStack`'s row sizes against the height it is offered. Rows are kept only while whole.
  - Offscreen snapshots at width 300, both states.
- **Result**: `make test` 60/60.

## feat(panel): adjustable width; folded cards show tool name and numbers

`b4862e8` | 2026-10-20

- **Changes**:
  - Drag the floating panel's side edge to set its unfolded width, from 300 to 720 pt (default 340, saved as `panelWidth`). The edge is the one away from the docked side: the left edge when docked right, otherwise the right edge. While dragging, the window follows at once instead of sliding. The folded rail stays 120 pt, and its cards measure their height at the current full width.
  - A folded card's tool line shows only the tool's name (blue while it runs), without its arguments.
  - The space at the bottom of a folded card, there because the full card is taller, now holds the project (unless the group header names it), plus the tool-call and token counts when they fit beside it.
- **Reason**: "展开宽度允许调节。" "另外现在折叠之后每个block底下都空一行，这里可以放点啥" "工具调用行，只显示工具名称，不要显示细节（折叠状态）"
- **Process**:
  - Dragged the left edge of a panel docked right with CGEvent: 340 to 420 to 500 and back to 340. The right edge stayed put, and the panel folded back to 120 pt each time.
  - Offscreen snapshots of both states.
- **Result**: `make test` 60/60.

## style(card): status glyph in the title row

`b0d8850` | 2026-10-20

- **Changes**: The session card's status glyph (now 20 pt) sits in the title row instead of a 26 pt column of its own. The rows under the title (agent, status, reply, tool) and the sub-agent box use the card's full width, so there is no empty strip down the left side.
- **Reason**: "这块导致block左边有空白。怎么调整一下让视觉更紧凑？", about the glyph column.
- **Process**: Offscreen snapshot of the floating panel.
- **Result**: `make test` 60/60.

## tweak(panel): faster fold and unfold

`5593138` | 2026-10-20

- **Changes**: The slide takes 0.14 s instead of 0.2 s, with a quintic ease-out instead of cubic, so it covers most of the distance at once and then settles. Hover opens the panel after 0.03 s instead of 0.08 s, and it folds 0.15 s after the pointer leaves instead of 0.3 s.
- **Reason**: "现在打开关闭动画有点拖沓。速度更快、ease in（前面快后面慢）、延迟降低。"
- **Result**: `make test` 60/60.

## fix(panel): keep hover and clicks through the unfold slide; tidy folded cards

`0c35656` | 2026-10-20

- **Changes**:
  - Fold and unfold no longer animate the window frame. The window takes the union of both shapes at once, and the visible panel (the blur view, now inside a clear root view) slides within it, driven by a display link with an ease-out curve over 0.2 s. At the end, the window settles to the final frame. The SwiftUI content keeps its final size and position on screen during the slide, so it never re-lays out, and the moving edge only uncovers or covers it.
  - Peek checks use where the panel is drawn, not the window frame.
  - The panel's tracking area is added once (`.inVisibleRect` follows resizes), so a resize no longer reports a new entry.
  - Review cards no longer have a "去查看" button, because clicking the card does the same thing. The button is also gone from the expanded card.
  - In folded cards, a running tool shows the same spinner (or check or cross) as the full card, through a shared `ToolGlyph`. The title takes at most two lines, and the status line under it one.
- **Reason**: "1现在待验收不要显示去查看按钮，点击本身就是查看 2折叠状态，对于bash等命令，显示和展开状态一样的loading圈。3标题最多两行，标题下只给一行。4展开的时候hover状态会掉导致无法点击，需要确保连续。"
- **Process**:
  - Logged the panel's pointer enter and exit and the cards' SwiftUI hover while moving the pointer in with CGEvent.
  - Before the fix, the panel reported an exit about 70 ms into the slide and a new entry about 180 ms later, with hover false in between. The new part of a resized window stays blank for a few frames, and the pointer falls through it.
  - After the fix, hover stayed true through the whole slide with the pointer moving.
  - Offscreen snapshots of the folded and unfolded panel: card heights still match.
  - Temporary logging removed.
- **Result**: `make test` 60/60.

## fix(panel): header pushed off the top when folding; live status in folded cards

`52b713f` | 2026-10-20

- **Changes**:
  - The panel's root frame now has `minHeight: 0` and clips. Before, content taller than the window, for a moment mid-resize, grew the root frame, and the hosting view centered it, so the header went above the window top.
  - BoardList remembers each card's full-panel height across folding. A folded card has its height from the first frame instead of growing into it. Until a height is known, it is capped.
  - A snap waits until a fold or unfold slide finishes. When the slide ends, the window settles on the last size the content asked for.
  - Folded cards show live status under a two-line title: the running tool, what it needs, why it may be stuck, or the last reply, in as many lines as fit.
  - The board header is one line high (`fixedSize` title and counts), the same height as the folded header. The title used to wrap next to the pin button, which moved every card down when unfolding.
- **Reason**: "折叠后items的高度会往上（偶尔）并导致看不到顶上的logo/按钮。另外，折叠状态在下方还是要提供实时状态信息。"
- **Process**:
  - Toggled fold and unfold seven times through Accessibility. The window kept its height (591), and the header button stayed 10 pt below the window top.
  - Offscreen snapshots of both states. The cards line up, and the folded ones show the tool or the reply.
- **Result**: `make test` 60/60.

## refactor(panel): fold the panel itself instead of swapping in a rail view

`6b62c9e` | 2026-10-20

- **Changes**:
  - Folded, the panel no longer swaps to a separate rail view with its own blocks. `FloatingPanelView` stays the same view with the same list, groups and cards, and only its width changes (120 pt folded, 340 unfolded). Unfolded it is exactly the normal floating panel, plus the pin or fold button while docked.
  - Folded, each card is a `NarrowSessionCard`: status, agent, clock, and as much of the title as fits. Its height is the full card's, measured off a hidden copy laid out at the full width. So every card keeps its height and position, and unfolding only widens the panel. Group headers drop the logos and drag handle. The panel header becomes `RailHeader` (mark and unfold button) at the same height.
  - The content is laid out at the target width and anchored to the docked side, and the window edge slides over it.
  - Removed `RailBlock` and the old `SidebarRail`.
- **Reason**: "需要完全是同一个窗体的内部状态切换……只做横向的宽度展开确保每一个agent item的高度在两个不同的窗体状态下是相同的" and "感觉现在展开状态的ui有变化，这是预期外的". The previous version had its own wide layout, so the unfolded panel no longer looked like the normal panel.
- **Process**:
  - Offscreen snapshots of the folded and unfolded panel. Every card starts at the same y and has the same height in both states.
  - Pressed pin and fold through Accessibility, and the live window switched between 120 and 340 pt with the right edge fixed.
  - `@Entry` needs the SwiftUI macro plugin, which the Command Line Tools lack, so the environment key is written out by hand.
- **Result**: `make test` 60/60.

## feat(panel): hover to unfold the sidebar, sliding edge

`fa6d3e3` | 2026-10-20

- **Changes**:
  - Hovering the folded rail for 80 ms unfolds it into the full panel. It folds back 0.3 s after the pointer leaves, or while a mouse button is down. While unfolded this way the header shows a pin button that keeps it open (`sidebarExpanded`). Pinned, the button is the usual fold chevron.
  - The pointer is caught by an `NSTrackingArea` with `.activeAlways` on the panel's background view, because SwiftUI hover only tracks while the app is active. Leaving is polled every 50 ms against the window frame, since the window changes size under the pointer.
  - Unfolding and folding no longer crossfade two views. The content switches at once, anchored to the side being revealed, and the window edge slides over 0.2 s (`NSAnimationContext`, ease-out). The panel takes clicks from the first frame. Moves made by the slide are not treated as drags.
  - The rail's logo and unfold button share one row.
- **Reason**: "鼠标hover自动展开悬浮窗。另外，现有logo/展开按钮放到一行，现在两行占空间。" and "需要直接展开，流畅的展开动画，而不是两个窗体切换，导致过程要卡顿一会等待展开好才能点击。"
- **Process**:
  - Hovering did nothing at first: SwiftUI `onHover` does not fire for an inactive app's panel. Switched to the tracking area.
  - Sampled the window frame every 10 ms. The edge moves step by step, starts about 0.15 s after the pointer enters, and is fully open by about 0.35 s. A temporary file log showed the extra delay after the dwell was building the panel (about 50 ms).
  - A brush past the rail does not unfold it. Pin and fold work. The left edge works the same way. Dragging off the edge gives the panel, and dropping back at the edge gives the rail.
- **Result**: `make test` 60/60.

## feat(panel): fold into a sidebar rail when snapped to a side

`6be589e` | 2026-10-20

- **Changes**:
  - When the floating panel is snapped to the left or right edge, it folds into a 112 pt rail (`SidebarRail`). The rail shows the logo, an unfold button, and one block per session in board order. A block shows the status mark, agent logo, sub-agent count, a two-line title, the project and the clock. Tapping a block jumps to the session; hovering shows its detail. Folded is the default.
  - The unfold button (or the context menu) sets `sidebarExpanded`. The setting persists, so the full panel stays open at the edge until the fold button in its header is clicked. That button only shows while docked. Dragging the panel off the edge always gives the normal panel.
  - The controller tracks the dock edge (`PanelRoom.dock`) and updates it only after a move settles. It waits while the mouse button is still down, so the panel does not fold under the pointer. `fit` keeps the docked side in place when the width changes. `snap` also pulls a panel dropped past a side back against that side, which docks it.
- **Reason**: "加入横向折叠功能（收纳到侧边，变成侧边栏，例如右侧），每个agent以块状显示，有一定宽度。靠左边/右边吸附，默认折叠。除非点击展开才会常驻展开。"
- **Process**:
  - The live panel was already at the right edge and came up as the rail. Clicking unfold and fold switched between 340 and 112 pt with the right edge fixed. The same worked at the left edge with the left edge fixed. Moving the rail to mid-screen gave the full panel.
  - A panel dropped partly past the right edge was pulled back but not docked, because only the vertical position was clamped. `snap` now clamps the horizontal position as well.
  - Checked an offscreen snapshot of the rail.
- **Result**: `make test` 60/60.

## feat(settings): logo header, styled rows, about section

`e63f5b2` | 2026-10-20

- **Changes**:
  - The settings window opens with the logo, name, version and a one-line pitch.
  - Each agent row shows its logo and a colored status capsule (已安装 / 需更新 / 未安装 / 未检测到) with small buttons. The other rows have System Settings style icon tiles. The opacity slider shows a percentage, and the hotkey is shown as a keycap. Notes moved to section footers.
  - New 关于 section: version, license, source link, issue link, copyright. Login item moved to 通用. The window is 500×640.
- **Reason**: "设置页面太丑，需要优化。顶上要加入logo。需要关于信息。"
- **Process**: Checked an offscreen snapshot of the window.
- **Result**: `make test` 60/60.

## feat(menu): logo menu-bar icon, small control popover, 8 h finished-session window

`51f3e43` | 2026-10-20

- **Changes**:
  - The menu-bar icon is the logo's three bars, drawn as a template. A dot under the short bar appears while something runs; it is red, orange or green for needs-input, stuck or to-review, next to the count.
  - The popover is a 230 pt control menu: the name, a one-line summary, show or hide the floating panel (⌥⌘K), main window, settings, quit. The session list is gone from it. Opening a window closes the popover first.
  - Finished sessions stay on the boards for 8 hours by default (was 30 min). The settings stepper now goes up to 24 h in 30-min steps and shows hours.
- **Reason**: "顶栏图标也要换。点击图标之后显示一个小窗口就行，现在窗口太大，只用来toggle悬浮窗、设置、主页等。" and "现在默认结束时间似乎太短。设置为8小时。"
- **Process**: Rendered the icon variants offscreen to check them. Clicked the status item and the popover opened at 230×178. 主界面 opened the main window, and the panel toggle flipped `showPanel` 1→0→1. The user had never set `idleVisibleMinutes`, so the new default applies.
- **Result**: `make test` 60/60.

## feat(panel): show sub-agents in their parent's card

`b3089e2` | 2026-10-20

- **Changes**:
  - `SessionState.parentId`. pi runs each sub-agent as a session of its own, and its transcript header names the parent (`parentSession`). The app reads that line once per session (`SubagentLink`) and links the two.
  - A sub-agent whose parent is on the board does not get its own card. It shows as one line in a strip under the parent's card: status, name, the current tool or last reply, and the time. Claude's in-process sub-agents (`subagents`) show there too. A child's permission buttons stay under its row.
  - Children have no review state and no "done" notification. They stay visible for 60 s after finishing, and tapping one jumps to the parent.
- **Reason**: "现在subagent会和主agent并行显示（pi），需要显示到主agent的subagent槽位（下方，缩略显示subagent详情，只用一行）" and "subagent被遮挡".
- **Process**: The live pi sub-agent (`…/run-0/session.jsonl`, spawned by pi-subagents) linked to its parent after install. A snapshot showed the row under the parent card. The first layout let the name crowd out the detail and the time; the name is now capped at 120 pt and the time never shrinks.
- **Result**: `make test` 60/60.

## docs: open-source under GPL-3.0 with a README

`c46c75d` | 2026-10-20

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
