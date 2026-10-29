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
| `overview-v10` | in the app, after 新版ui挺不错的，问题就是信息密度有点低，很多组件有大量空白: tighter cards (16 pt padding and radius, smaller figures), rows as tall as their content, a cumulative leverage curve over a 1× line, 你不在时 as a timeline of the stretches away, Agents beside Projects | (awaiting) |
