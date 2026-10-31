# Design

Style specimens for the design-system redesign (branch `feature/design-system`). They are rendered offline with SwiftUI. Apart from `DesignSystem.swift`, which the specimen borrows from the app, none of this is built into the app.

- `specimen/`: the working specimen.
  - The tokens and components live in the app, `Sources/YaaKanban/DesignSystem.swift` (moved there once approved); `build.sh` compiles that file with the specimen.
  - `main.swift` holds the tokens sheet, the main window and the settings mock.
  - `overview.swift` is the 概览 page.
  - Render with `specimen/build.sh [out-dir]` (default `/tmp/yaak-ds`). To render an archived overview, set `OVERVIEW=history/overview-vN/overview.swift`.
- `directions/`: the four style boards A–D (`board-*.png`) and their sources.
- `history/`: every version shown to the user, each with its source when it exists.
  - Most images are the downscaled previews the user reviewed.
  - `overview-v8` onward hold full renders at 2×.
  - `overview-v10` onward are the app's own `yaak snapshot` renders (`before-*` from v9 in the app, `after-*`), with the app sources they came from.
  - `overview-v1` has no saved image. `rerender-*.png` is its replayed source drawn with today's `DesignSystem.swift`, so its fonts and canvas are later than the original.
- `references/`: the user's widget references (Pinterest board, pasted images). Kept locally only and ignored by git (third-party images).

## Versions and the feedback that followed

| Version | What it was | Feedback |
|---|---|---|
| `before/` | the app before the redesign | "系统性优化主界面、菜单栏窗口、设置窗口……做一个设计系统" |
| `ds-1` | first tokens and the settings in the main window | 渐变从上到下由深到浅；不够精致 |
| `ds-2` | finer details; 3× / 4× detail crops | 深色渐变方向反了；去线、留白；更硬朗的字体；设置点进去才看到更多选项 |
| `ds-3` | current tokens, settings and detail renders | 选中项不染色不渐变（会话卡除外）；关键数字用窄体 |
| `overview-v1` | first 概览: summary sentence and stat cards | 太丑了（给了 3 张 widget 参考） |
| `overview-v2` | widget wall: dot matrix, bar day, ring | 太丑，缺乏视觉张力，要从数字、逻辑到视觉系统迭代 |
| `overview-v3` | rethought metrics, stacked bars, hero numbers | 色彩和主系统不搭；不够精致；开头一句话丑；缺少协调 |
| `overview-v4` | toned to the system palette | 全是柱子；提炼 Pinterest 收藏的风格 |
| `overview-v5` | first pass at the Pinterest style | 方向对一点；仍太多柱子，缺少实感图形，卡片细节不够 |
| `overview-v6` | graphic forms (rings, waves, gauges) | 字体丑；卡片背景、文字、图形、色彩都差；要 Linear/Apple 风格 |
| `overview-v7` | flat Linear-style cards | 缺少视觉张力；出几个风格方向 → `directions/` |
| `directions` | A 黑底霓虹（Live Activities）· B 饱和色块 · C 巨字裁切 · D 深色色调格子 | 选 A+C：A 常规、C 点缀；A 不够细致协调 |
| `overview-v8` | **milestone.** A as black slabs with four hues, C on 杠杆 / 你不在时 | 只有黑卡、浅色模式不协调；大字太大，要更规整；小圆角卡片放一些到上面；用好顶栏放关键信息 |
| `overview-v9` | cards follow the appearance (white / lifted gray); figures in primary ink at two sizes, units and labels in the hue; top bar with the day's totals; chip rows top and bottom; accents as a colour fill at the card's foot | 先按照当前设计系统来完整迁移整个ui (approved; migrate the app) |
| `overview-v10` | in the app, after 新版ui挺不错的，问题就是信息密度有点低，很多组件有大量空白: tighter cards (16 pt padding and radius, smaller figures), rows as tall as their content, a cumulative leverage curve over a 1× line, 你不在时 as a timeline of the stretches away, Agents beside Projects | 统计有点没话找话：你不在时 100% 看不懂（什么算等待？跑完没后续算不算？）；等你处理优先级低；回复速度能衡量效率；工作去向、谁在干活、节奏不错 |
| `overview-v11` | 你不在时 and 等你处理 removed; 回复速度 → 响应速度 beside 杠杆 (replying and reviewing, each a median, P90 and arc); 全部停工 / 当前积压 / 验收时间 chips removed; needs input purple with a question bubble; sidebar cards' second row under the glyph, pin shown | (awaiting) |
| `leverage-v1` | 杠杆 bars, the period before at the same width and centre: today's wide ghost vs A notch, B cap line, C gain (shared part faded), D hatch; day / past week / month at 330 pt, day at 600 pt; `main.swift` renders it with `DesignSystem.swift` | 选 B；横线窄一点、两端圆角；颜色比柱更深更灰，不要纯白 |
| `leverage-v2` | B refined: a cap 60% of the bar's width, round ends, 3 pt (2 pt in a month); the bar's hue under 40% / 55% black or 60% dark gray; the last row (shipped) uses 55% black where the bar covers the cap and the mid hue where the cap sits on the pale ghost | (awaiting) |
| `sidebar-v1` | in the app: logo beside the window buttons, a light 概览 block with agent hours, leverage, mean reply and count chips, search always under it (`before-main` is the sidebar before) | 太丑，非常不协调；logo 放回红绿灯下面；概览入口要更大、更炫酷的卡片（给了太阳系光弧、蓝色玻璃格、信用分卡片参考），不要硬放内容；搜索不要常驻，做成「活跃」标题旁的按钮 |
| `sidebar-v2` | a dark 概览 card: counts in the title row, today's leverage, one glowing disc per state (`card-states` shows 1, 2, 4 and no states); search behind a button on the 活跃 heading; light and dark renders | 选中概览后卡片不要高亮，hover 要有 (applied)；风格可以延续，但卡片还是丑，背景要炫酷、动态但不抓眼（给了红色渐变左栏 + 黑色右侧的分栏卡片参考）；杠杆做颜色分级，低蓝高红，混叠一些动态效果 |
| `sidebar-v3` | a dark split card: today's leverage on a panel lit in its heat (blue 1× → violet → red 8×, slowly drifting lights and a sheen; `card-heat` shows 1.1–8× and none), beside it 概览, the change vs yesterday, agent time ÷ yours, state dots | 高度降到 55%；去掉一些元素，不要左右分割（太丑）；主要只显示「概览」两字，不再显示杠杆数据，少一点内容；风格：现代、玻璃感、科技光渐变（有一点酸感），动效柔和、光影 morphing |
| `sidebar-v4` | a 62 pt frosted glass card with only 概览 and a small arrow; four blurred lights (acid lime, cyan, violet, a touch of pink) drift and stretch on 17/23/29/37 s loops under a pale veil, lit rim; follows the appearance; `glass-light`/`glass-dark` show five moments, normal and hovered | 没在概览页还是要显示杠杆数据；把 logo 合到卡片里，高度可微调；视觉参考给了一张深色玻璃卡（底部向上的蓝色光晕）：颜色还是老样子，要有渐变，且与杠杆关联 |
| `sidebar-v5` | the logo and name moved into the card (`layout-glass-*`: A one row, B name as a caption over 概览, B taken, 72 pt); dark glass lit from its foot in the leverage hue (blue 1×, violet ~3×, red 8×, dim gray with none; `heat-*` shows 1/2/3/5/8.5× and none, normal, hovered and on 概览), lobes drifting on 19/23/29 s, a pale core on 17 s; today's leverage on the right except while 概览 is open | logo 和「概览」间距有点小；不显示杠杆数字时右侧要有箭头 |
| `sidebar-v6` | 6 pt between the logo line and 概览 (was 3); an arrow on the right while 概览 is open; `main-session` shows the figure, `main-overview` the arrow | 卡片高光要有渐变，现在突变 |
| `sidebar-v7` | the rim catches the light gradually (white 0.2 at the top, the hue from mid-height up to full at the foot) instead of jumping to it low on the sides; hover eases (a fading veil and rim layer) instead of switching; `card-before` is v6 | logo 和「概览」再上下分开一点 |
| `sidebar-v8` | 10 pt between the logo line and 概览 (was 6); hover then softened (veil 15% → 7% instead of 0, hovered rim 0.6 instead of 0.8) | hover 高光太亮了 (applied) |
| `sidebar-v9` | the logo mark leaves the card for the right end of the window buttons' line (14 pt, was 12; the row is the title bar's 28 pt, centred on the buttons), the card keeps the name over 概览 at the same height | logo 位置太上了，需要在窗体边缘和 block 上边缘中间 |
| `sidebar-v10` | the logo row is the full 38 pt above the card, so the mark is centred 19 pt down, midway between the window's top and the card | 概览左边加上 home 的图标; then block 稍矮、YaaKanban 和概览距离近一点 |
| `sidebar-v11` | a house before 概览: first `house.fill` 14 pt semibold at the Label's default gap, then `house` 14 pt medium 4 pt away (`card-session`) | 图标和文字近一点、换简洁图标; then 去掉 home 图标 (dropped, back to v10) |
| `sidebar-v12` | card 66 pt tall (was 72), 8 pt between the YaaKanban line and 概览 (was 10) | |
